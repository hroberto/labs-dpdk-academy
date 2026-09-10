// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Henrique M Roberto
//
// Alternativa C++23 ao tópico trilha/01-fundamentos/02-mempool-ring:
// mesma lógica de pacote, mesma transformação e mesmo resumo, mas com
// std::vector pré-reservado no lugar de rte_mempool e std::views::chunk no
// lugar de rte_ring_dequeue_burst. Lógica pura: testável em L1.
#pragma once

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <expected>
#include <ranges>
#include <span>
#include <vector>

namespace academy {

inline constexpr std::uint32_t max_size = 1500u;

struct Packet {
    std::uint64_t id{};
    std::uint32_t size{};
    std::uint32_t checksum{};
};

struct Summary {
    std::uint64_t packets{};
    std::uint64_t bytes{};
};

enum class Error { queue_full };

[[nodiscard]] constexpr std::uint32_t checksum(std::uint64_t id, std::uint32_t size) noexcept {
    return static_cast<std::uint32_t>((id ^ size) & 0xFFFFFFFFu);
}

[[nodiscard]] constexpr Packet make(std::uint64_t id, std::uint32_t size) noexcept {
    const auto t = std::min(size, max_size);
    return Packet{id, t, checksum(id, t)};
}

constexpr void process(Packet& p) noexcept {
    p.checksum ^= static_cast<std::uint32_t>(p.id * 0x9E3779B97F4A7C15ULL);
    p.size = std::min<std::uint32_t>(p.size + 1u, max_size);
}

// Processa um lote (burst) e acumula no resumo. std::span evita ponteiro + tamanho.
constexpr void process_burst(std::span<Packet> burst, Summary& r) noexcept {
    for (auto& p : burst) {
        process(p);
        ++r.packets;
        r.bytes += p.size;
    }
}

// Fila com capacidade fixa: o vector é reservado uma vez (sem alocação no hot path).
class Queue {
public:
    explicit Queue(std::size_t capacity) : capacity_(capacity) { packets_.reserve(capacity); }

    // std::expected (C++23): erro sem exceção no caminho crítico.
    [[nodiscard]] std::expected<void, Error> enqueue(Packet p) {
        if (packets_.size() >= capacity_) return std::unexpected(Error::queue_full);
        packets_.push_back(p);
        return {};
    }

    // Consome tudo em lotes de `lote` elementos (std::views::chunk, C++23).
    Summary consume(std::size_t burst) {
        Summary r{};
        for (auto chunk : std::span{packets_} | std::views::chunk(burst))
            process_burst(std::span<Packet>{chunk.data(), chunk.size()}, r);
        packets_.clear();  // mantém a capacidade reservada
        return r;
    }

    [[nodiscard]] std::size_t size() const noexcept { return packets_.size(); }
    [[nodiscard]] std::size_t capacity() const noexcept { return capacity_; }

private:
    std::size_t capacity_;
    std::vector<Packet> packets_;
};

// Anel SPSC sem trava: o equivalente em C++23 do `rte_ring` em modo SP/SC.
//
// POR QUE ESTA CLASSE EXISTE
//
// O README deste diretório afirmava que "um anel SPSC escrito à mão em C++23
// custa 15,9 ns" contra 16,0 ns do rte_ring, e concluía empate no nível 2 da
// comparação. Esse anel NÃO existia no repositório: o número não tinha programa
// que o produzisse, o que viola a regra editorial do projeto -- a mesma que
// derrubou o folclore do `malloc()`. Ou o anel passava a existir, ou o número
// tinha de sair. Ele existe agora, e o número é medido.
//
// O ALGORITMO, e por que é o mesmo do DPDK
//
// Um produtor e um consumidor, índices monotônicos, capacidade potência de dois
// para que o resto vire máscara. O produtor só escreve `cauda_`; o consumidor só
// escreve `cabeca_`. Cada um LÊ o índice do outro com `acquire` e PUBLICA o seu
// com `release`: é o par que garante que o dado escrito no vetor seja visível
// antes do índice que o anuncia. Sem isso o consumidor pode ver o índice novo e
// o dado velho -- e em x86 isso quase nunca aparece em teste, o que torna o erro
// pior, não melhor.
//
// O ALINHAMENTO NÃO É ENFEITE. Os dois índices ficam em linhas de cache
// distintas. Juntos, cada publicação do produtor invalidaria a linha que o
// consumidor lê a cada volta -- falso compartilhamento, medido nos fundamentos
// (§4.2.1). É a mesma razão pela qual o rte_ring separa `prod` e `cons`.
class SpscRing {
public:
    // `capacidade` é arredondada para cima até potência de dois. Uma posição
    // fica sempre vazia, para distinguir cheio de vazio sem contador extra --
    // exatamente o que o rte_ring faz, e por isso um anel pedido com 1024
    // guarda 1023.
    explicit SpscRing(std::size_t capacity)
        : mask_(round_up_pow2(capacity) - 1), buffer_(round_up_pow2(capacity)) {}

    [[nodiscard]] bool enqueue(const Packet& p) noexcept {
        const auto cauda = tail_.load(std::memory_order_relaxed);
        const auto proxima = (cauda + 1) & mask_;
        // `acquire` no índice do consumidor: precisamos ver os slots que ele já
        // liberou antes de decidir que há espaço.
        if (proxima == head_.load(std::memory_order_acquire)) return false;
        buffer_[cauda] = p;
        tail_.store(proxima, std::memory_order_release);  // publica dado, depois índice
        return true;
    }

    [[nodiscard]] bool dequeue(Packet& out) noexcept {
        const auto cabeca = head_.load(std::memory_order_relaxed);
        if (cabeca == tail_.load(std::memory_order_acquire)) return false;  // vazio
        out = buffer_[cabeca];
        head_.store((cabeca + 1) & mask_, std::memory_order_release);
        return true;
    }

    [[nodiscard]] std::size_t usable_capacity() const noexcept { return mask_; }

private:
    static constexpr std::size_t round_up_pow2(std::size_t n) noexcept {
        std::size_t p = 1;
        while (p < n) p <<= 1;
        return p;
    }

    // Tamanho da linha de cache, para separar os dois índices.
    //
    // O padrão oferece `std::hardware_destructive_interference_size`, e a
    // primeira versão desta classe o usava. O GCC emite -Winterference-size
    // contra esse uso, e o aviso tem razão: o valor participa da ABI, então
    // duas unidades de tradução compiladas com parâmetros diferentes podem
    // discordar sobre o layout da MESMA struct. Num cabeçalho -- que é o caso
    // aqui -- isso é exatamente o cenário perigoso.
    //
    // 64 é o valor real em x86-64 e em arm64 comum. Está fixo, declarado, e
    // conferível na máquina de medição com:
    //     cat /sys/devices/system/cpu/cpu0/cache/index0/coherency_line_size
    static constexpr std::size_t cache_line = 64;

    alignas(cache_line) std::atomic<std::size_t> tail_{0};   // só o produtor escreve
    alignas(cache_line) std::atomic<std::size_t> head_{0};  // só o consumidor escreve
    std::size_t mask_;
    std::vector<Packet> buffer_;
};

}  // namespace academy
