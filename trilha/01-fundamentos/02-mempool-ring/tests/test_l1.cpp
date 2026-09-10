// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Henrique M Roberto
//
// Teste L1 (unitário) do tópico 02 — lógica pura, sem EAL e sem hardware.
//
// Por que L1 existe separado do L2:
//   A lógica de pacote (pacote.c) não depende do DPDK. Testá-la isoladamente
//   roda em qualquer máquina, em milissegundos, sem hugepages nem privilégios.
//   O que depende do runtime (mempool, ring, devolução de objetos) é coberto
//   pelo L2. Essa separação é a razão de pacote.c ser um arquivo à parte de
//   pipeline_ring.c: código testável não deve estar preso ao runtime.
//
// pacote.h é C; o bloco extern "C" evita name mangling do C++.

#include <gtest/gtest.h>

extern "C" {
#include "packet.h"
}

namespace {

TEST(Checksum, EhXorDeIdComTamanho)
{
    EXPECT_EQ(packet_checksum(7, 100), 7u ^ 100u);
    EXPECT_EQ(packet_checksum(0, 0), 0u);
}

TEST(Preencher, GuardaIdETamanho)
{
    struct packet p;
    packet_fill(&p, 7, 100);
    EXPECT_EQ(p.id, 7u);
    EXPECT_EQ(p.size, 100u);
    EXPECT_EQ(p.checksum, packet_checksum(7, 100));
}

TEST(Preencher, LimitaTamanhoAoMaximoDeEthernet)
{
    struct packet p;
    packet_fill(&p, 1, 9000);
    EXPECT_EQ(p.size, PACKET_MAX_SIZE);
    // O checksum precisa refletir o tamanho JÁ limitado, não o valor original.
    EXPECT_EQ(p.checksum, packet_checksum(1, PACKET_MAX_SIZE));
}

TEST(Processar, IncrementaTamanhoEMisturaChecksum)
{
    struct packet p;
    packet_fill(&p, 3, 64);
    const uint32_t antes = p.checksum;

    packet_process(&p);

    EXPECT_EQ(p.size, 65u);
    EXPECT_EQ(p.checksum, antes ^ static_cast<uint32_t>(3 * 0x9E3779B97F4A7C15ULL));
}

TEST(Processar, SaturaNoTamanhoMaximo)
{
    struct packet p;
    packet_fill(&p, 3, PACKET_MAX_SIZE);
    packet_process(&p);
    EXPECT_EQ(p.size, PACKET_MAX_SIZE) << "processar nao pode ultrapassar o limite";
}

TEST(ProcessarLote, LoteVazioNaoAlteraOResumo)
{
    struct summary r = {0, 0};
    packet_process_burst(nullptr, 0, &r);
    EXPECT_EQ(r.packets, 0u);
    EXPECT_EQ(r.bytes, 0u);
}

// ---------------------------------------------------------------------------
// Invariante central do tópico, expresso como teste parametrizado.
//
// Burst processing existe por desempenho: amortiza o custo por pacote sobre
// vários pacotes. Mas o tamanho do lote NÃO pode alterar o resultado. Se
// alterasse, seria um bug de lógica disfarçado de otimização.
//
// TEST_P roda o mesmo corpo para cada tamanho de lote, incluindo lote=1
// (equivalente a não fazer batching) e lote maior que a entrada.
// ---------------------------------------------------------------------------
class ResultadoIndependeDoLote : public ::testing::TestWithParam<unsigned> {};

TEST_P(ResultadoIndependeDoLote, DezPacotesSempreSomam695Bytes)
{
    const unsigned tamanho_lote = GetParam();

    struct packet v[10];
    struct packet *ponteiros[10];
    for (unsigned i = 0; i < 10; i++) {
        packet_fill(&v[i], i, 64u + (i % 32u));
        ponteiros[i] = &v[i];
    }

    struct summary r = {0, 0};
    for (unsigned off = 0; off < 10; off += tamanho_lote) {
        const unsigned n = (off + tamanho_lote > 10) ? (10 - off) : tamanho_lote;
        packet_process_burst(&ponteiros[off], n, &r);
    }

    EXPECT_EQ(r.packets, 10u);
    EXPECT_EQ(r.bytes, 695u) << "tamanho de lote = " << tamanho_lote;
}

INSTANTIATE_TEST_SUITE_P(TamanhosDeLote, ResultadoIndependeDoLote,
                         ::testing::Values(1u, 2u, 3u, 4u, 8u, 10u, 32u));

}  // namespace
