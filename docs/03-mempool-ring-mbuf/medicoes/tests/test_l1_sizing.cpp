// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Henrique M Roberto
//
// Teste L1 (unitário) do módulo 03 — as regras de dimensionamento de mempool.
//
// Por que este teste existe:
//   As quatro restrições sobre (n, cache_size) não são verificadas em tempo de
//   compilação, e três delas falham em SILÊNCIO — o pool é criado, funciona, e
//   desperdiça memória ou objetos sem avisar. O caso que motivou o arquivo foi
//   real: o programa de medição deste próprio módulo usava n=4095 com cache=256,
//   deixando 255 objetos inalcançáveis, e nada acusou.
//
// dimensionamento.h não inclui nada do DPDK, então estes casos rodam em
// milissegundos, sem EAL — a mesma separação do livro de ofertas no módulo 02.

#include <gtest/gtest.h>

extern "C" {
#include "sizing.h"
}

namespace {

// Valor de RTE_MEMPOOL_CACHE_MAX_SIZE no DPDK 25.11. Passado como parâmetro, e
// não espelhado no cabeçalho, para que uma mudança no DPDK apareça aqui como
// falha de teste em vez de divergência silenciosa.
constexpr uint32_t CACHE_MAX = 512;

TEST(Dimensionamento, PotenciaDeDoisMenosUmNaoGeraAviso)
{
    for (uint32_t n : {1u, 3u, 7u, 255u, 1023u, 4095u, 65535u})
        EXPECT_FALSE(dim_check(n, 0, CACHE_MAX) & DIM_N_NOT_POW2_MINUS_ONE)
            << "n = " << n;
}

TEST(Dimensionamento, PotenciaDeDoisCheiaEDesperdicio)
{
    // 4096 parece o número "redondo", e é justamente o que a documentação
    // desaconselha: o anel interno precisaria dobrar para caber um objeto a mais.
    for (uint32_t n : {2u, 8u, 256u, 4096u})
        EXPECT_TRUE(dim_check(n, 0, CACHE_MAX) & DIM_N_NOT_POW2_MINUS_ONE)
            << "n = " << n;
}

TEST(Dimensionamento, CacheAcimaDoMaximoEErroDeCriacao)
{
    // Acima de RTE_MEMPOOL_CACHE_MAX_SIZE a criação falha — não é desperdício.
    const unsigned a = dim_check(65535, CACHE_MAX + 1, CACHE_MAX);
    EXPECT_TRUE(a & DIM_CACHE_ABOVE_MAX);

    EXPECT_FALSE(dim_check(65535, CACHE_MAX, CACHE_MAX) & DIM_CACHE_ABOVE_MAX);
}

TEST(Dimensionamento, RegraDeNSobreUmEMeioNaFronteira)
{
    // cache <= n/1.5, ou seja cache*3 <= n*2. Com n = 15: teto = 10.
    EXPECT_FALSE(dim_check(15, 10, CACHE_MAX) & DIM_CACHE_OVER_N_DIV_1_5);
    EXPECT_TRUE(dim_check(15, 11, CACHE_MAX) & DIM_CACHE_OVER_N_DIV_1_5);
}

TEST(Dimensionamento, CacheZeroNaoViolaRegraDeCache)
{
    // Sem cache não há regra de cache a violar — mas a regra de n continua.
    const unsigned a = dim_check(4095, 0, CACHE_MAX);
    EXPECT_EQ(a & (DIM_CACHE_ABOVE_MAX | DIM_CACHE_OVER_N_DIV_1_5 |
                   DIM_N_NOT_MULTIPLE_OF_CACHE),
              0u);
    EXPECT_EQ(dim_leftover_objects(4095, 0), 0u);
}

// Este é o caso que originou o arquivo.
TEST(Dimensionamento, OCasoRealDoProgramaDesteModulo)
{
    const unsigned a = dim_check(4095, 256, CACHE_MAX);

    // n = 4095 é 2^12 - 1: ótimo em memória, sem aviso.
    EXPECT_FALSE(a & DIM_N_NOT_POW2_MINUS_ONE);
    // 256 <= 512 e 256*3 <= 4095*2: os dois limites passam.
    EXPECT_FALSE(a & DIM_CACHE_ABOVE_MAX);
    EXPECT_FALSE(a & DIM_CACHE_OVER_N_DIV_1_5);
    // E ainda assim: 4095 % 256 = 255 objetos que o cache nunca alcança.
    EXPECT_TRUE(a & DIM_N_NOT_MULTIPLE_OF_CACHE);
    EXPECT_EQ(dim_leftover_objects(4095, 256), 255u);
}

TEST(Dimensionamento, CacheRecomendadoNaoDeixaObjetoPreso)
{
    for (uint32_t n : {255u, 1023u, 4095u, 65535u}) {
        const uint32_t c = dim_recommended_cache(n, CACHE_MAX);
        ASSERT_GT(c, 0u) << "n = " << n;
        EXPECT_EQ(dim_leftover_objects(n, c), 0u) << "n = " << n << ", cache = " << c;
        EXPECT_EQ(dim_check(n, c, CACHE_MAX), DIM_OK) << "n = " << n << ", cache = " << c;
    }
}

TEST(Dimensionamento, CacheRecomendadoRespeitaOTeto)
{
    // Pool grande: o teto é o máximo do DPDK, não n/1.5.
    EXPECT_LE(dim_recommended_cache(1048575, CACHE_MAX), CACHE_MAX);
    // Pool minúsculo: nenhum cache não-nulo serve, e zero é resposta legítima.
    EXPECT_EQ(dim_recommended_cache(1, CACHE_MAX), 0u);
}

TEST(Dimensionamento, NOtimoSobeParaOProximoDaForma)
{
    EXPECT_EQ(dim_optimal_n(1), 1u);
    EXPECT_EQ(dim_optimal_n(2), 3u);
    EXPECT_EQ(dim_optimal_n(1000), 1023u);
    EXPECT_EQ(dim_optimal_n(4095), 4095u);  // já está na forma: não mexe
    EXPECT_EQ(dim_optimal_n(4096), 8191u);
}

TEST(Dimensionamento, DescricaoNaoEstouraOBuffer)
{
    char pequeno[16];
    // Todos os avisos ligados, buffer curto: deve truncar e terminar em '\0'.
    dim_describe(0xFFFFFFFFu, pequeno, sizeof(pequeno));
    EXPECT_LT(strnlen(pequeno, sizeof(pequeno)), sizeof(pequeno));

    char grande[256];
    EXPECT_STREQ(dim_describe(DIM_OK, grande, sizeof(grande)), "sem ressalvas");
}

}  // namespace
