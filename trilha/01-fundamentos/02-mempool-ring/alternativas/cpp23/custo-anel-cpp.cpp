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
// USO: ./custo-anel-cpp
#include <chrono>
#include <cstdint>
#include <cstdio>

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

    const int rounds = iterations / static_cast<int>(current_burst);
    const auto t0 = now_ns();
    for (int i = 0; i < rounds; i++) {
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

}  // namespace

int main() {
    const int n = DEFAULT_SAMPLES;
    std::printf("\n== O anel SPSC em C++23, medido ==\n\n");
    std::printf("  anel de %zu posicoes; ciclo completo enfileirar+desenfileirar\n", capacity);
    std::printf("  UM thread, SEM disputa: mesma condicao de custo-anel.c, para\n");
    std::printf("  que os dois numeros sejam comparaveis\n");
    std::printf("  amostras: %d, cada uma com %d operacoes\n\n", n, iterations);

    std::printf("  %-8s %16s\n", "lote", "SP/SC (ns/obj)");
    std::printf("  %-8s %16s\n", "-----", "--------------");

    static const std::size_t bursts[] = {1, 8, 32, 128};
    for (const auto l : bursts) {
        current_burst = l;
        const struct statistics e = collect(m_cycle, n);
        std::printf("  %-8zu %13.3f ns\n", l, e.median);
    }

    std::printf("\n  Compare com a mesma tabela do lado C, em\n");
    std::printf("  docs/03-mempool-ring-mbuf/medicoes/custo-anel.c: mesma condicao,\n");
    std::printf("  mesmo numero de operacoes, mesma estatistica.\n\n");
    return 0;
}
