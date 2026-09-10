// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Henrique M Roberto
//
// Teste L1 (unitário) do módulo 02 — fluxo e livro de ofertas, sem EAL.
//
// Por que existe separado do L2:
//   Subir a EAL custa 123 ms nesta máquina (é o que custo-init.c mede). Se a
//   regra de negócio do feed só pudesse ser testada com o runtime de pé, cada
//   rodada de teste pagaria esse preço. livro.c não inclui nada do DPDK
//   justamente para que estes casos rodem em milissegundos.
//
// O que se testa aqui é o que dá errado em feed de mercado de verdade: perda de
// datagrama, retransmissão repetida, cancelamento de lado, livro cruzado, e a
// separação entre a numeração do FLUXO e o preço do INSTRUMENTO — que é o erro
// de modelagem que produz spread negativo.
//
// livro.h é C; o bloco extern "C" evita name mangling do C++.

#include <gtest/gtest.h>

extern "C" {
#include "order_book.h"
}

namespace {

// Constrói um tick com o mínimo de ruído no corpo dos testes.
struct tick faz_tick(uint64_t seq, uint8_t lado, int32_t price, uint32_t qtd = 100,
                     uint32_t instrument = 1)
{
    struct tick t {};
    t.sequence = seq;
    t.tsc = 0;
    t.instrument = instrument;
    t.price = price;
    t.quantity = qtd;
    t.lado = lado;
    return t;
}

// ------------------------------ fluxo ------------------------------

TEST(Fluxo, SequenciaContiguaNaoAcusaPerda)
{
    struct fluxo f {};
    fluxo_iniciar(&f);

    for (uint64_t s = 1; s <= 5; s++)
        EXPECT_EQ(fluxo_verificar(&f, s), FLUXO_OK);

    EXPECT_EQ(f.recebidos, 5u);
    EXPECT_EQ(f.gaps, 0u);
    EXPECT_EQ(f.dropped, 0u);
}

TEST(Fluxo, SaltoContaExatamenteOsDatagramasAusentes)
{
    struct fluxo f {};
    fluxo_iniciar(&f);

    EXPECT_EQ(fluxo_verificar(&f, 1), FLUXO_OK);
    EXPECT_EQ(fluxo_verificar(&f, 5), FLUXO_LACUNA);  // 2, 3 e 4 se perderam

    EXPECT_EQ(f.gaps, 3u);
    EXPECT_EQ(f.recebidos, 2u);  // o tick que chegou continua válido
}

TEST(Fluxo, RepeticaoDeRetransmissaoEDescartada)
{
    struct fluxo f {};
    fluxo_iniciar(&f);

    EXPECT_EQ(fluxo_verificar(&f, 1), FLUXO_OK);
    EXPECT_EQ(fluxo_verificar(&f, 1), FLUXO_DESCARTADO);

    EXPECT_EQ(f.dropped, 1u);
    EXPECT_EQ(f.recebidos, 1u);
    EXPECT_EQ(f.ultima_sequencia, 1u);
}

TEST(Fluxo, TickForaDeOrdemEDescartadoSemMexerNoEstado)
{
    struct fluxo f {};
    fluxo_iniciar(&f);

    EXPECT_EQ(fluxo_verificar(&f, 10), FLUXO_OK);
    EXPECT_EQ(fluxo_verificar(&f, 4), FLUXO_DESCARTADO);

    EXPECT_EQ(f.ultima_sequencia, 10u);
    EXPECT_EQ(f.gaps, 0u);
}

TEST(Fluxo, PrimeiraSequenciaAltaNaoEContadaComoPerda)
{
    struct fluxo f {};
    fluxo_iniciar(&f);

    // Assinar o feed no meio do pregão é normal: a primeira sequência vista é
    // alta, e o que veio antes nunca foi endereçado a nós.
    EXPECT_EQ(fluxo_verificar(&f, 918273), FLUXO_OK);
    EXPECT_EQ(f.gaps, 0u);
}

// ------------------------------ livro ------------------------------

TEST(Livro, ComecaSemPrecoDosDoisLados)
{
    struct order_book l {};
    order_book_init(&l);

    EXPECT_EQ(l.best_bid, LIVRO_SEM_PRECO);
    EXPECT_EQ(l.best_ask, LIVRO_SEM_PRECO);
    // Zero não serviria como sentinela: zero é um preço válido.
    EXPECT_EQ(livro_spread(&l), LIVRO_SEM_PRECO);
}

TEST(Livro, AtualizacaoSubstituiOLadoEmVezDeAcumular)
{
    struct order_book l {};
    order_book_init(&l);

    struct tick a = faz_tick(1, LIVRO_COMPRA, 3210);
    struct tick b = faz_tick(2, LIVRO_COMPRA, 3190);  // preço CAIU
    order_book_apply(&l, &a);
    order_book_apply(&l, &b);

    // Nível 1: o feed publica o melhor vigente. Guardar o máximo histórico
    // deixaria no topo uma oferta que já saiu do mercado.
    EXPECT_EQ(l.best_bid, 3190);
}

TEST(Livro, SpreadEAVendaMenosACompra)
{
    struct order_book l {};
    order_book_init(&l);

    struct tick c = faz_tick(1, LIVRO_COMPRA, 3248);
    struct tick v = faz_tick(2, LIVRO_VENDA, 3252);
    order_book_apply(&l, &c);
    order_book_apply(&l, &v);

    EXPECT_EQ(livro_spread(&l), 4);
    EXPECT_FALSE(order_book_crossed(&l));
}

TEST(Livro, SpreadIndefinidoEnquantoFaltarUmLado)
{
    struct order_book l {};
    order_book_init(&l);

    struct tick a = faz_tick(1, LIVRO_COMPRA, 3200);
    order_book_apply(&l, &a);

    // Há compra, não há venda: publicar um spread aqui seria inventar número.
    EXPECT_EQ(livro_spread(&l), LIVRO_SEM_PRECO);
    EXPECT_FALSE(order_book_crossed(&l));  // faltando um lado, não há o que cruzar
}

TEST(Livro, QuantidadeZeroCancelaOLado)
{
    struct order_book l {};
    order_book_init(&l);

    struct tick a = faz_tick(1, LIVRO_COMPRA, 3210);
    struct tick cancela = faz_tick(2, LIVRO_COMPRA, 3210, 0);

    order_book_apply(&l, &a);
    EXPECT_EQ(l.best_bid, 3210);

    order_book_apply(&l, &cancela);
    // Sem este tratamento, restaria uma oferta fantasma no topo do livro.
    EXPECT_EQ(l.best_bid, LIVRO_SEM_PRECO);
    EXPECT_EQ(livro_spread(&l), LIVRO_SEM_PRECO);
}

TEST(Livro, CancelamentoDeUmLadoNaoMexeNoOutro)
{
    struct order_book l {};
    order_book_init(&l);

    struct tick c = faz_tick(1, LIVRO_COMPRA, 3248);
    struct tick v = faz_tick(2, LIVRO_VENDA, 3252);
    struct tick cancela_compra = faz_tick(3, LIVRO_COMPRA, 3248, 0);
    order_book_apply(&l, &c);
    order_book_apply(&l, &v);
    order_book_apply(&l, &cancela_compra);

    EXPECT_EQ(l.best_bid, LIVRO_SEM_PRECO);
    EXPECT_EQ(l.best_ask, 3252);
}

TEST(Livro, LivroCruzadoEDetectado)
{
    struct order_book l {};
    order_book_init(&l);

    // Alguém pagaria 3260 enquanto outro aceita receber 3250: a negociação
    // deveria ter ocorrido. Em produção isso vem de perda, atraso ou defeito.
    struct tick c = faz_tick(1, LIVRO_COMPRA, 3260);
    struct tick v = faz_tick(2, LIVRO_VENDA, 3250);
    order_book_apply(&l, &c);
    order_book_apply(&l, &v);

    EXPECT_TRUE(order_book_crossed(&l));
    EXPECT_LT(livro_spread(&l), 0);  // o spread negativo é o sintoma
}

TEST(Livro, PrecoEInteiroEmCentavos)
{
    struct order_book l {};
    order_book_init(&l);

    // 0,1 + 0,2 != 0,3 em ponto flutuante binário. Em centavos inteiros a
    // comparação é exata, que é o requisito de um livro de ofertas.
    struct tick c = faz_tick(1, LIVRO_COMPRA, 10);
    struct tick v = faz_tick(2, LIVRO_VENDA, 20);
    order_book_apply(&l, &c);
    order_book_apply(&l, &v);

    EXPECT_EQ(livro_spread(&l), 10);
}

// ---------------- a separação entre fluxo e instrumento ----------------

TEST(FluxoELivro, PapeisDiferentesNaoCompartilhamLivro)
{
    // Este é o teste que existe por causa de um defeito real: misturar dois
    // papéis num livro só produziu "melhor compra" de um contra "melhor venda"
    // de outro, e um spread de -441 centavos, que não existe no mundo.
    struct fluxo f {};
    fluxo_iniciar(&f);

    struct order_book petr {};
    struct order_book vale {};
    order_book_init(&petr);
    order_book_init(&vale);

    // Um único fluxo numera as duas atualizações; cada uma vai ao seu livro.
    struct tick t1 = faz_tick(1, LIVRO_COMPRA, 3600, 100, /*instrumento=*/0);
    struct tick t2 = faz_tick(2, LIVRO_VENDA, 3150, 100, /*instrumento=*/1);

    EXPECT_EQ(fluxo_verificar(&f, t1.sequence), FLUXO_OK);
    order_book_apply(&petr, &t1);
    EXPECT_EQ(fluxo_verificar(&f, t2.sequence), FLUXO_OK);
    order_book_apply(&vale, &t2);

    // Nenhum dos dois livros tem os dois lados, então nenhum tem spread.
    EXPECT_EQ(livro_spread(&petr), LIVRO_SEM_PRECO);
    EXPECT_EQ(livro_spread(&vale), LIVRO_SEM_PRECO);
    EXPECT_FALSE(order_book_crossed(&petr));
    EXPECT_FALSE(order_book_crossed(&vale));

    // E o fluxo contou as duas, independentemente do papel de cada uma.
    EXPECT_EQ(f.recebidos, 2u);
    EXPECT_EQ(f.gaps, 0u);
}

// O tick atravessa a fronteira de processo: se o layout mudar de um lado só,
// os dois programas leem lixo. Este teste é uma trava contra isso.
TEST(Tick, LayoutEstavelParaMemoriaCompartilhada)
{
    EXPECT_EQ(sizeof(struct tick), 32u);
    // 32 bytes = meia linha de cache: dois ticks por linha de 64 B.
    EXPECT_EQ(64u / sizeof(struct tick), 2u);
}

}  // namespace
