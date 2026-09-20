// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Henrique M Roberto
//
// L1 de `cadeia.h` — a estrutura que três programas de medição montam.
//
// POR QUE ESTE TESTE EXISTE, E POR QUE ELE É L1
//
// A coluna "dependente" de `efeito-cache.c` publicou 0,9 ns como latência da
// RAM porque o encadeamento estava degenerado: a permutação era gerada sobre os
// ELEMENTOS do vetor e reduzida com `%` para caber no número de LINHAS, o que
// dá sucessores repetidos. A cadeia virava um ciclo de dois ou três nós, que
// cabe na L1 — e o programa mediu a L1 enquanto o documento dizia RAM.
//
// A suíte ficou verde o tempo todo. O teste do programa era "executa", e um
// programa que mede a coisa errada também sai com zero.
//
// A propriedade violada não depende de hardware, de tempo nem de tamanho de
// cache: é combinatória. Por isso cabe num teste L1 determinístico, que roda em
// milissegundos e falha exatamente no defeito que passou.
#include <gtest/gtest.h>

#include <cstdint>
#include <set>
#include <vector>

#include "cadeia.h"

namespace {

// Percorre a cadeia `c` e devolve os nós visitados, na ordem.
std::vector<size_t> percorrer(const std::vector<size_t> &ordem, size_t n, int k, int c)
{
    const size_t por_fatia = n / static_cast<size_t>(k);
    std::vector<size_t> visitados;
    size_t i = academy_cadeia_inicio(n, k, c);
    size_t no = ordem[i];
    for (size_t passo = 0; passo < por_fatia; passo++) {
        visitados.push_back(no);
        // Reencontra a posição do nó atual para pedir o sucessor. Os programas
        // não fazem isso (eles varrem `ordem` linearmente); aqui interessa
        // seguir a cadeia como o HARDWARE a segue, que é o que estava quebrado.
        no = academy_sucessor(ordem.data(), n, k, i);
        i = (i + 1 == academy_cadeia_inicio(n, k, c) + por_fatia)
                ? academy_cadeia_inicio(n, k, c)
                : i + 1;
    }
    return visitados;
}

std::vector<size_t> permutacao(size_t n, uint64_t semente)
{
    std::vector<size_t> ordem(n);
    academy_permutar(ordem.data(), n, &semente);
    return ordem;
}

// --- a permutação -------------------------------------------------------

TEST(Cadeia, PermutacaoContemCadaIndiceExatamenteUmaVez)
{
    for (size_t n : {size_t{2}, size_t{3}, size_t{64}, size_t{1000}}) {
        const auto ordem = permutacao(n, 0x9E3779B97F4A7C15ull);
        const std::set<size_t> distintos(ordem.begin(), ordem.end());
        ASSERT_EQ(distintos.size(), n) << "n = " << n;
        EXPECT_EQ(*distintos.begin(), 0u);
        EXPECT_EQ(*distintos.rbegin(), n - 1);
    }
}

TEST(Cadeia, PermutacaoEhDeterministicaDadaASemente)
{
    EXPECT_EQ(permutacao(256, 12345), permutacao(256, 12345));
    EXPECT_NE(permutacao(256, 12345), permutacao(256, 54321));
}

TEST(Cadeia, PermutacaoDeUmElementoNaoEstoura)
{
    // O laço Fisher-Yates decrementa; com n = 1 ele não pode executar nenhuma
    // iteração. Escrito com `for (i = n - 1; i > 0; i--)` e n = 0, `n - 1`
    // estoura para SIZE_MAX e varre a memória inteira.
    auto ordem = permutacao(1, 7);
    ASSERT_EQ(ordem.size(), 1u);
    EXPECT_EQ(ordem[0], 0u);
    std::vector<size_t> vazio;
    uint64_t s = 7;
    academy_permutar(vazio.data(), 0, &s);  // não deve estourar
}

// --- o encadeamento: a propriedade que o defeito violava ----------------

TEST(Cadeia, CicloUnicoVisitaTodosOsNosExatamenteUmaVez)
{
    const size_t n = 4096;
    const auto ordem = permutacao(n, 0xDEADBEEF);
    const auto visitados = percorrer(ordem, n, 1, 0);

    ASSERT_EQ(visitados.size(), n) << "a cadeia tem de ter n passos";
    const std::set<size_t> distintos(visitados.begin(), visitados.end());
    EXPECT_EQ(distintos.size(), n)
        << "ciclo degenerado: " << n - distintos.size() << " no(s) repetido(s). "
           "E este e o defeito que publicou 0,9 ns como latencia da RAM.";
}

TEST(Cadeia, CicloFechaNoPontoDePartida)
{
    const size_t n = 1024;
    const auto ordem = permutacao(n, 99);
    // Depois de n passos, o sucessor tem de ser o nó inicial de novo.
    EXPECT_EQ(academy_sucessor(ordem.data(), n, 1, n - 1), ordem[0]);
}

TEST(Cadeia, KCadeiasSaoDisjuntasECobremTudo)
{
    const size_t n = 4096;
    const auto ordem = permutacao(n, 2026);
    for (int k : {1, 2, 4, 8, 16, 64}) {
        std::set<size_t> todos;
        for (int c = 0; c < k; c++) {
            const auto visitados = percorrer(ordem, n, k, c);
            ASSERT_EQ(visitados.size(), n / static_cast<size_t>(k))
                << "k = " << k << ", cadeia " << c;
            const std::set<size_t> distintos(visitados.begin(), visitados.end());
            ASSERT_EQ(distintos.size(), visitados.size())
                << "cadeia " << c << " de k = " << k << " repete nos";
            const size_t antes = todos.size();
            todos.insert(distintos.begin(), distintos.end());
            EXPECT_EQ(todos.size(), antes + distintos.size())
                << "cadeias de k = " << k << " se cruzam: acessos nao sao independentes";
        }
        EXPECT_EQ(todos.size(), academy_cadeia_nos(n, k)) << "k = " << k;
    }
}

TEST(Cadeia, NQueNaoDivideDeixaSobraDeclarada)
{
    // 1000 nós em 3 cadeias: 333 cada, 1 sobra. Quem chama percorre 999.
    EXPECT_EQ(academy_cadeia_nos(1000, 3), 999u);
    EXPECT_EQ(academy_cadeia_inicio(1000, 3, 0), 0u);
    EXPECT_EQ(academy_cadeia_inicio(1000, 3, 1), 333u);
    EXPECT_EQ(academy_cadeia_inicio(1000, 3, 2), 666u);
}

// --- o defeito, reproduzido: o teste falha se a propriedade voltar -------

TEST(Cadeia, ConstrucaoDegeneradaSeriaDetectada)
{
    // Reproduz exatamente o que a versão errada fazia: permutar sobre `n`
    // elementos e reduzir com `% nos` para caber nas linhas.
    const size_t n = 4096, nos = n / 16;
    const auto ordem = permutacao(n, 42);
    std::set<size_t> sucessores;
    for (size_t i = 0; i < nos; i++)
        sucessores.insert(ordem[(i + 1) % nos] % nos);

    EXPECT_LT(sucessores.size(), nos)
        << "se esta construcao virasse uma permutacao valida, o teste acima "
           "deixaria de proteger contra o defeito que ele descreve";
}

}  // namespace
