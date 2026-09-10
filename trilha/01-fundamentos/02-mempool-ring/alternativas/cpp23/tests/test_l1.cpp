// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Henrique M Roberto
//
// Teste L1 (unitário) da alternativa C++23.
//
// Este arquivo é deliberadamente um ESPELHO de
//   trilha/01-fundamentos/02-mempool-ring/tests/test_l1.cpp
// Os nomes dos casos e os valores esperados são os mesmos (695 bytes, 10
// pacotes, saturação em 1500). Só as implementações diferem: lá, C com
// rte_mempool e ponteiros; aqui, C++23 com std::span, std::expected e
// std::views::chunk.
//
// É essa simetria que torna a comparação honesta — se as duas suítes passam com
// as mesmas asserções, a diferença entre as abordagens é de arquitetura e custo,
// não de comportamento.

#include <gtest/gtest.h>

#include "packet.hpp"

namespace {

using namespace academy;

TEST(Checksum, EhXorDeIdComTamanho)
{
    EXPECT_EQ(checksum(7, 100), 7u ^ 100u);
    EXPECT_EQ(checksum(0, 0), 0u);
    // Vantagem do lado C++23: o contrato é verificável em tempo de compilação.
    static_assert(checksum(7, 100) == (7u ^ 100u));
}

TEST(Criar, GuardaIdETamanho)
{
    const auto p = make(7, 100);
    EXPECT_EQ(p.id, 7u);
    EXPECT_EQ(p.size, 100u);
    EXPECT_EQ(p.checksum, checksum(7, 100));
}

TEST(Criar, LimitaTamanhoAoMaximoDeEthernet)
{
    const auto p = make(1, 9000);
    EXPECT_EQ(p.size, max_size);
    EXPECT_EQ(p.checksum, checksum(1, max_size));
}

TEST(Processar, IncrementaTamanhoEMisturaChecksum)
{
    auto p = make(3, 64);
    const auto antes = p.checksum;

    process(p);

    EXPECT_EQ(p.size, 65u);
    EXPECT_EQ(p.checksum, antes ^ static_cast<std::uint32_t>(3 * 0x9E3779B97F4A7C15ULL));
}

TEST(Processar, SaturaNoTamanhoMaximo)
{
    auto p = make(3, max_size);
    process(p);
    EXPECT_EQ(p.size, max_size) << "processar nao pode ultrapassar o limite";
}

TEST(ProcessarLote, LoteVazioNaoAlteraOResumo)
{
    Summary r{};
    process_burst(std::span<Packet>{}, r);
    EXPECT_EQ(r.packets, 0u);
    EXPECT_EQ(r.bytes, 0u);
}

// A fila reserva capacidade uma única vez; passar dela é erro esperado, não
// exceção. std::expected torna esse caminho explícito na assinatura.
TEST(Queue, NovaEstaVaziaComCapacidadeReservada)
{
    const Queue f(16);
    EXPECT_EQ(f.size(), 0u);
    EXPECT_EQ(f.capacity(), 16u);
}

TEST(Queue, EnfileirarAlemDaCapacidadeDevolveErro)
{
    Queue f(2);
    EXPECT_TRUE(f.enqueue(make(0, 64)).has_value());
    EXPECT_TRUE(f.enqueue(make(1, 64)).has_value());

    const auto r = f.enqueue(make(2, 64));
    ASSERT_FALSE(r.has_value());
    EXPECT_EQ(r.error(), Error::queue_full);
}

TEST(Queue, ConsumirEsvaziaMasPreservaCapacidade)
{
    Queue f(16);
    for (std::uint64_t i = 0; i < 10; ++i) {
        ASSERT_TRUE(f.enqueue(make(i, 64u + static_cast<std::uint32_t>(i % 32u))).has_value());
    }
    ASSERT_EQ(f.size(), 10u);

    (void)f.consume(4);

    EXPECT_EQ(f.size(), 0u);
    EXPECT_EQ(f.capacity(), 16u) << "consumir nao pode devolver a memoria reservada";
}

// ---------------------------------------------------------------------------
// Mesmo invariante do lado DPDK: o tamanho do lote é um botão de DESEMPENHO,
// nunca de semântica. Aqui o batching é feito por std::views::chunk; lá, por
// rte_ring_dequeue_burst. O resultado precisa ser idêntico nos dois.
// ---------------------------------------------------------------------------
class ResultadoIndependeDoLote : public ::testing::TestWithParam<std::size_t> {};

TEST_P(ResultadoIndependeDoLote, DezPacotesSempreSomam695Bytes)
{
    Queue f(16);
    for (std::uint64_t i = 0; i < 10; ++i) {
        ASSERT_TRUE(f.enqueue(make(i, 64u + static_cast<std::uint32_t>(i % 32u))).has_value());
    }

    const auto r = f.consume(GetParam());

    EXPECT_EQ(r.packets, 10u);
    EXPECT_EQ(r.bytes, 695u) << "tamanho de lote = " << GetParam();
}

INSTANTIATE_TEST_SUITE_P(TamanhosDeLote, ResultadoIndependeDoLote,
                         ::testing::Values(1u, 2u, 3u, 4u, 8u, 10u, 32u));

}  // namespace

// --- SpscRing -------------------------------------------------------------
//
// Classe nova, com atomicas: precisa de teste proprio. O que se verifica aqui
// e o CONTRATO, nao a concorrencia -- ordenacao de memoria com um so thread
// nao e exercitada, e dizer o contrario seria falso conforto. A concorrencia
// de verdade e exercitada pelo modo `-c` do packet_pipeline, no L2.

TEST(SpscRing, CapacidadeArredondaParaPotenciaDeDoisMenosUm)
{
    // Pedir 1000 da um anel de 1024 com 1023 uteis -- a mesma regra do
    // rte_ring, e a razao e a mesma: uma posicao distingue cheio de vazio.
    academy::SpscRing ring(1000);
    EXPECT_EQ(ring.usable_capacity(), 1023u);
}

TEST(SpscRing, VazioNaoDesenfileira)
{
    academy::SpscRing ring(8);
    academy::Packet p{};
    EXPECT_FALSE(ring.dequeue(p));
}

TEST(SpscRing, PreservaOrdemFIFO)
{
    academy::SpscRing ring(8);
    for (std::uint64_t i = 0; i < 5; ++i)
        EXPECT_TRUE(ring.enqueue(academy::make(i, 64)));

    for (std::uint64_t i = 0; i < 5; ++i) {
        academy::Packet p{};
        ASSERT_TRUE(ring.dequeue(p));
        EXPECT_EQ(p.id, i);
    }
}

TEST(SpscRing, CheioRecusaEmVezDeSobrescrever)
{
    academy::SpscRing ring(4);              // 4 posicoes, 3 uteis
    EXPECT_EQ(ring.usable_capacity(), 3u);
    for (std::uint64_t i = 0; i < 3; ++i)
        EXPECT_TRUE(ring.enqueue(academy::make(i, 64)));
    EXPECT_FALSE(ring.enqueue(academy::make(99, 64)));

    // E o que estava dentro continua intacto: recusar nao pode corromper.
    academy::Packet p{};
    ASSERT_TRUE(ring.dequeue(p));
    EXPECT_EQ(p.id, 0u);
}

TEST(SpscRing, CirculaSemPerderPacote)
{
    // Da varias voltas no anel: e onde um erro de mascara apareceria.
    academy::SpscRing ring(4);
    std::uint64_t esperado = 0;
    for (std::uint64_t i = 0; i < 100; ++i) {
        ASSERT_TRUE(ring.enqueue(academy::make(i, 64)));
        academy::Packet p{};
        ASSERT_TRUE(ring.dequeue(p));
        EXPECT_EQ(p.id, esperado++);
    }
    EXPECT_EQ(esperado, 100u);
}
