// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Henrique M Roberto
//
// Espelho em C++23 de docs/03-mempool-ring-mbuf/medicoes/custo-anel.c.
//
// POR QUE ESTE PROGRAMA EXISTE
//
// O README deste diretório afirmava, no nível 2 da comparação, que "o rte_ring
// em modo SP/SC custa 16,0 ns por repasse; um anel SPSC escrito à mão em C++23
// custa 15,9 ns", e concluía EMPATE. Duas coisas estavam erradas:
//
//   1. o anel em C++23 não existia. O número não tinha programa que o
//      produzisse -- exatamente o que a regra editorial do projeto proíbe;
//   2. os 16,0 ns não medem o anel. Vêm do `bench-ccd.sh`, que cronometra o
//      PIPELINE INTEIRO do tópico com dois lcores: mempool get/put por pacote,
//      mais o anel, mais a migração da linha de cache entre núcleos. Chamar
//      isso de "custo do rte_ring" atribui ao anel o custo do conjunto.
//
// Este programa mede o anel, e só o anel, com o MESMO protocolo do lado C:
// um thread, sem disputa, ciclo completo enfileirar+desenfileirar, o mesmo
// número de operações e a mesma estatística. É assim que "é o mesmo algoritmo"
// deixa de ser conjectura e vira comparação.
//
// O QUE ESTE PROGRAMA NÃO MEDE, e o lado C também não: a migração de linha de
// cache entre núcleos. Com um thread ela não existe. O que sobra é o custo da
// instrução atômica e da contabilidade de índices -- que é a parte que depende
// do algoritmo, e portanto a parte comparável.
//
// DUAS COLUNAS, E A RAZÃO DE SEREM DUAS
//
// O lado C usa `rte_ring_enqueue_bulk`, que move n ponteiros com UM par de
// operações atômicas. Comparar isso com um laço de `enqueue()` unitário compara
// duas coisas diferentes e atribui à linguagem o que é desenho de interface.
//
// O `SpscRing` tem as duas formas -- `enqueue`/`dequeue` e
// `enqueue_burst`/`dequeue_burst` --, então as duas são medidas aqui:
//
//   unitario   laço de n chamadas unitárias; n publicações `release`
//   em bloco   uma chamada com std::span; UMA publicação `release`
//
// A coluna `em bloco` é a comparação pareada com o lado C. A coluna `unitario`
// fica porque é ela que mostra o que a API de bloco amortiza -- e porque o
// README publicava a segunda como se fosse a única que o C++ tem.
//
// USO: ./custo-anel-cpp
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <span>
#include <vector>

#include "packet.hpp"

// Sem extern "C": statistics.h ja e compilado como C++ aqui, e o mesmo vale
// para custo-espera-cpp.cpp, o outro espelho C++ deste projeto.
#include "statistics.h"

namespace {

// Mesma forma de custo-espera-cpp.cpp, para que os espelhos concordem.
[[nodiscard]] double now_ns() {
    return static_cast<double>(std::chrono::duration_cast<std::chrono::nanoseconds>(
                                   std::chrono::steady_clock::now().time_since_epoch())
                                   .count());
}

constexpr int iterations = 200000;  // o mesmo de custo-anel.c
constexpr std::size_t capacity = 4096;

std::size_t current_burst = 1;

// Ciclo completo: enfileira `lote` e desenfileira `lote`, repetido até somar
// `iteracoes` operações. Espelha m_ciclo_bulk() do lado C.
double m_cycle() {
    academy::SpscRing ring(capacity);
    academy::Packet p = academy::make(1, 64);
    academy::Packet out{};

    const int voltas = iterations / static_cast<int>(current_burst);
    const auto t0 = now_ns();
    for (int i = 0; i < voltas; i++) {
        for (std::size_t j = 0; j < current_burst; j++)
            if (!ring.enqueue(p)) break;
        for (std::size_t j = 0; j < current_burst; j++)
            if (!ring.dequeue(out)) break;
    }
    const double total = now_ns() - t0;
    // Impede que o compilador conclua que `saida` não é usada e apague o laço.
    __asm__ __volatile__("" : : "r"(&out) : "memory");
    return total / iterations;
}

// O mesmo ciclo, pela API de bloco. Espelha m_ciclo_bulk() do lado C na forma
// da chamada, e não só na contagem: um `enqueue_burst` de n contra um
// `rte_ring_enqueue_bulk` de n.
//
// Os buffers são alocados FORA da janela cronometrada e reusados em todas as
// voltas. Alocar dentro mediria o alocador junto com o anel, que é o erro que
// este espelho existe para não cometer.
double m_cycle_bulk() {
    academy::SpscRing ring(capacity);
    std::vector<academy::Packet> input(current_burst, academy::make(1, 64));
    std::vector<academy::Packet> output(current_burst);

    const int voltas = iterations / static_cast<int>(current_burst);
    const auto t0 = now_ns();
    for (int i = 0; i < voltas; i++) {
        (void)ring.enqueue_burst(std::span<const academy::Packet>{input});
        (void)ring.dequeue_burst(std::span<academy::Packet>{output});
    }
    const double total = now_ns() - t0;
    __asm__ __volatile__("" : : "r"(output.data()) : "memory");
    return total / iterations;
}

}  // namespace

int main() {
    const int n = DEFAULT_SAMPLES;
    std::printf("\n== The SPSC ring in C++23, measured ==\n\n");
    std::printf("  ring of %zu slots; full enqueue+dequeue cycle\n", capacity);
    std::printf("  ONE thread, NO contention: same condition as custo-anel.c, so\n");
    std::printf("  that the two numbers are comparable\n");
    std::printf("  samples: %d, each with %d operations\n\n", n, iterations);

    std::printf("  %-8s %16s %16s\n", "batch", "unitary (ns/obj)", "bulk (ns/obj)");
    std::printf("  %-8s %16s %16s\n", "-----", "----------------", "-------------");

    static const std::size_t bursts[] = {1, 8, 32, 128};
    for (const auto l : bursts) {
        current_burst = l;
        const struct statistics u = collect(m_cycle, n);
        const struct statistics b = collect(m_cycle_bulk, n);
        std::printf("  %-8zu %13.3f ns %13.3f ns\n", l, u.median, b.median);
    }

    std::printf("\n  'unitary' is a loop of n single-element calls: n release\n");
    std::printf("  stores. 'bulk' is one span call: ONE release store. The C side\n");
    std::printf("  uses rte_ring_enqueue_bulk, so 'bulk' is the paired column.\n");

    std::printf("\n  Compare with the same table on the C side, in\n");
    std::printf("  docs/03-mempool-ring-mbuf/medicoes/custo-anel.c: same condition,\n");
    std::printf("  same number of operations, same statistic.\n\n");
    return 0;
}
