// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Henrique M Roberto
//
// Pipeline em memória em C++23 "puro" (só biblioteca padrão, pilha do kernel
// não é usada porque não há rede). Equivalente à versão DPDK em
// trilha/01-fundamentos/02-mempool-ring: mesmos parâmetros, mesma saída.
//
// Uso: ./packet_pipeline [-n pacotes] [-b tamanho_do_lote] [-c cpu_consumidor]
//
// Sem `#define _GNU_SOURCE` aqui: ao contrario do lado C, o g++ ja o define
// por padrao em C++, e redefini-lo emite -Wmacro-redefined.
#include <pthread.h>
#include <sched.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <thread>
#include <cstdio>
#include <cstdlib>
#include <print>
#include <string_view>

#include "packet.hpp"

namespace {

struct Config {
    std::uint64_t num_packets = 10;
    std::size_t burst = 32;
    // -c N: consumidor em thread propria, fixada na CPU N. Espelha o `-l 0,N`
    // da versao DPDK, e existe para que o nivel 2 da comparacao (troca entre
    // nucleos) tenha os DOIS lados medidos, e nao so o do DPDK.
    int consumer_cpu = -1;
};

constexpr std::size_t burst_max = 256;

// Aquecimento e limiar de medição: os MESMOS da versão DPDK, e a simetria é o
// ponto. Comparar um programa aquecido com um frio mediria a diferença de
// aquecimento, não a diferença de arquitetura — e é essa comparação que o
// README deste diretório usa como argumento central.
constexpr std::uint64_t warmup_packets = 4096;
constexpr std::uint64_t min_to_measure = 10000;

// Uma passagem completa com o resultado DESCARTADO, para que a medição seguinte
// encontre o vector já tocado, os caches quentes e o preditor treinado.
void warmup(std::size_t burst) {
    academy::Queue fila(1024);
    academy::Summary r{};
    std::uint64_t produced = 0;
    while (r.packets < warmup_packets) {
        for (std::size_t i = 0; i < burst && produced < warmup_packets; ++i) {
            auto p = academy::make(produced, 64u);
            if (fila.enqueue(p)) ++produced; else break;
        }
        const auto partial = fila.consume(burst);
        r.packets += partial.packets;
        r.bytes += partial.bytes;
    }
}

// Frequência corrente do núcleo, em GHz, ou 0 se o sistema não a expuser.
double freq_ghz() {
    std::FILE* f = std::fopen("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq", "r");
    if (f == nullptr) return 0.0;
    long khz = 0;
    if (std::fscanf(f, "%ld", &khz) != 1) khz = 0;
    std::fclose(f);
    return static_cast<double>(khz) / 1e6;
}

std::expected<Config, std::string_view> parse_config(int argc, char** argv) {
    Config cfg;
    for (int i = 1; i < argc; ++i) {
        std::string_view arg{argv[i]};
        if ((arg == "-n" || arg == "-b" || arg == "-c") && i + 1 < argc) {
            const auto valor = std::strtoull(argv[++i], nullptr, 10);
            if (arg == "-n") cfg.num_packets = valor;
            else if (arg == "-b") cfg.burst = valor;
            else cfg.consumer_cpu = static_cast<int>(valor);
        } else {
            return std::unexpected("Uso: packet_pipeline [-n pacotes] [-b lote (1..256)] [-c cpu_consumidor]");
        }
    }
    if (cfg.num_packets == 0 || cfg.burst == 0 || cfg.burst > burst_max)
        return std::unexpected("Parametros invalidos: -n deve ser > 0 e -b entre 1 e 256");
    return cfg;
}


// Fixa a thread corrente numa CPU. Espelha o que a EAL faz com um lcore -- sem
// isso a comparacao mediria o escalonador, erro que ja custou caro neste
// projeto (ver custo-contencao.c).
bool pin_to(int cpu) {
    cpu_set_t cs;
    CPU_ZERO(&cs);
    CPU_SET(cpu, &cs);
    return pthread_setaffinity_np(pthread_self(), sizeof(cs), &cs) == 0;
}

// Produtor e consumidor em nucleos distintos, ligados pelo SpscRing.
//
// E o espelho do modo de dois lcores da versao DPDK: mesmo contrato de saida,
// mesma carga por pacote, mesmo tamanho de lote. O que muda e so a estrutura
// que atravessa os nucleos -- rte_ring la, SpscRing aqui.
academy::Summary run_two_cores(const Config& cfg, int cpu_prod, int cpu_cons) {
    academy::SpscRing ring(1024);
    academy::Summary total{};
    std::atomic<bool> producing{true};

    std::thread consumidor([&] {
        if (!pin_to(cpu_cons))
            std::println(stderr, "aviso: nao fixei o consumidor na CPU {}", cpu_cons);
        academy::Packet p{};
        std::vector<academy::Packet> burst;
        burst.reserve(cfg.burst);
        auto accumulate = [&] {
            burst.push_back(p);
            if (burst.size() == cfg.burst) {
                academy::process_burst(std::span<academy::Packet>{burst}, total);
                burst.clear();
            }
        };

        // ENCERRAMENTO, e a sutileza que custou um teste intermitente.
        //
        // A versao anterior era `if (dequeue) ... else if (!produzindo)
        // break;` -- e perdia pacotes sob contencao de CPU, uma execucao em
        // muitas. O motivo: a leitura de `cauda_` que falhou aconteceu ANTES da
        // leitura de `produzindo`. O `acquire` em `produzindo` sincroniza com
        // tudo que o produtor fez antes de publicar o fim, inclusive a ultima
        // atualizacao de `cauda_` -- mas isso nao retroage sobre uma leitura ja
        // realizada. O consumidor podia, portanto, ver "anel vazio" com um
        // `cauda_` defasado e "produtor terminou" atualizado, e sair deixando
        // pacotes para tras.
        //
        // A correcao e RECONFERIR o anel depois de observar o fim: essa segunda
        // leitura acontece depois do `acquire`, entao enxerga o `cauda_` final.
        // Como o produtor ja terminou, nada mais entra depois dela.
        while (true) {
            if (ring.dequeue(p)) {
                accumulate();
                continue;
            }
            if (!producing.load(std::memory_order_acquire)) {
                if (!ring.dequeue(p)) break;  // agora sim: vazio de verdade
                accumulate();
            }
        }
        if (!burst.empty()) academy::process_burst(std::span<academy::Packet>{burst}, total);
    });

    if (!pin_to(cpu_prod))
        std::println(stderr, "aviso: nao fixei o produtor na CPU {}", cpu_prod);
    for (std::uint64_t i = 0; i < cfg.num_packets; ++i) {
        auto p = academy::make(i, 64u + static_cast<std::uint32_t>(i % 32u));
        while (!ring.enqueue(p)) ;  // anel cheio: gira, como o lado DPDK faz
    }
    producing.store(false, std::memory_order_release);
    consumidor.join();
    return total;
}

}  // namespace

int main(int argc, char** argv) {
    const auto cfg = parse_config(argc, argv);
    if (!cfg) {
        std::println(stderr, "{}", cfg.error());
        return EXIT_FAILURE;
    }

    warmup(cfg->burst);

    // Capacidade fixa, sem alocação no caminho quente — o mesmo objetivo do ring
    // da versão DPDK, que é criado com 1024.
    //
    // As capacidades NÃO são iguais, e a diferença é instrutiva: um rte_ring
    // pedido com 1024 guarda 1023, porque uma posição fica reservada para
    // distinguir cheio de vazio. Esta Fila guarda 1024. O contrato de saída
    // (10 pacotes, 695 bytes) não muda, porque a fila nunca enche nos tamanhos
    // usados; mas afirmar paridade de capacidade seria impreciso.
    // --- Modo de dois nucleos: o espelho do `-l 0,N` da versao DPDK ---------
    if (cfg->consumer_cpu >= 0) {
        const auto ti = std::chrono::steady_clock::now();
        const auto r = run_two_cores(*cfg, 0, cfg->consumer_cpu);
        const auto ns_total =
            std::chrono::duration<double, std::nano>(std::chrono::steady_clock::now() - ti).count();
        std::println("Pacotes processados: {}", r.packets);
        std::println("Total de bytes: {}", r.bytes);
        std::println("Modo: 2 threads (produtor CPU 0, consumidor CPU {})", cfg->consumer_cpu);
        std::println("Lote (burst): {}", cfg->burst);
        const auto media = ns_total / static_cast<double>(r.packets);
        if (r.packets >= min_to_measure) {
            std::println("Tempo medio: {:.1f} ns/pacote", media);
            if (const auto f = freq_ghz(); f > 0.0)
                std::println("Frequencia do lcore 0: {:.2f} GHz (o tempo acima varia com ela)", f);
        } else {
            std::println("Tempo medio: {:.1f} ns/pacote  <- NAO E MEDICAO", media);
        }
        return r.packets == cfg->num_packets ? EXIT_SUCCESS : EXIT_FAILURE;
    }

    academy::Queue fila(1024);
    academy::Summary total{};
    std::uint64_t produced = 0, refused = 0;

    const auto t0 = std::chrono::steady_clock::now();

    while (total.packets < cfg->num_packets) {
        // Produtor: enche a fila em lotes.
        for (std::size_t i = 0; i < cfg->burst && produced < cfg->num_packets; ++i) {
            auto p = academy::make(produced, 64u + static_cast<std::uint32_t>(produced % 32u));
            if (fila.enqueue(p)) ++produced; else { ++refused; break; }
        }
        // Consumidor: processa tudo que há na fila em lotes de `lote`.
        const auto r = fila.consume(cfg->burst);
        total.packets += r.packets;
        total.bytes += r.bytes;
    }

    const auto ns = std::chrono::duration<double, std::nano>(std::chrono::steady_clock::now() - t0).count();

    std::println("Pacotes processados: {}", total.packets);
    std::println("Total de bytes: {}", total.bytes);
    // Conta LOTES INTERROMPIDOS, nao objetos: o laco acima faz `break` na
    // primeira recusa, entao o resto do lote nem e tentado. E grandeza
    // diferente da que a versao DPDK publica na mesma posicao -- por isso o
    // rotulo e diferente, em vez de dois numeros incomparaveis com o mesmo nome.
    std::println("Lote (burst): {} | lotes interrompidos por fila cheia: {}",
                 cfg->burst, refused);
    const auto media = ns / static_cast<double>(total.packets);
    if (total.packets >= min_to_measure) {
        std::println("Tempo medio: {:.1f} ns/pacote", media);
        if (const auto f = freq_ghz(); f > 0.0)
            std::println("Frequencia do lcore 0: {:.2f} GHz (o tempo acima varia com ela)", f);
    } else {
        std::println("Tempo medio: {:.1f} ns/pacote  <- NAO E MEDICAO", media);
        std::println("  {} pacotes sao poucos demais: o custo de ler o relogio e da mesma",
                     total.packets);
        std::println("  ordem do trabalho medido. Use -n {} ou mais para um numero defensavel.",
                     min_to_measure);
    }
    return EXIT_SUCCESS;
}
