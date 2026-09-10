// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Henrique M Roberto
//
// Teste L1 do módulo de estatística — a base de TODO número publicado.
//
// POR QUE ESTE ARQUIVO EXISTE, E POR QUE DEMOROU
//
// `statistics.h` calcula a mediana, o IQR, o p99, a dispersão e o CV de cada
// tabela deste repositório. Passou muito tempo sem nenhum teste, o que é o pior
// lugar possível para não ter: um defeito aqui não quebra nada visivelmente —
// apenas publica números errados com aparência de certos.
//
// UM CUIDADO NA CONSTRUÇÃO DESTES CASOS
//
// Teste escrito lendo a implementação apenas CONSAGRA o que ela faz, defeitos
// inclusive. Os valores esperados abaixo vêm da definição publicada do quantil
// **tipo 7 de Hyndman-Fan** — o padrão do R e do `numpy` com método "linear" —
// e não de executar o código:
//
//     h = (n-1)·p ;  Q = x[⌊h⌋] + (h-⌊h⌋)·(x[⌊h⌋+1] - x[⌊h⌋])
//
// Referência verificável: `quantile(c(1,2,3,4,5), type = 7)` no R devolve
// 25% = 2, 50% = 3, 75% = 4 — exatamente as asserções de PercentilTipo7.
//
// statistics.h é C; o bloco extern "C" evita name mangling do C++.

#include <gtest/gtest.h>

#include <cmath>

extern "C" {
#include "statistics.h"
}

namespace {

constexpr double TOL = 1e-12;

// ---------------------------------------------------------------------
// percentil() — a função de que dependem mediana, p25, p75 e p99
// ---------------------------------------------------------------------

TEST(Percentil, SegueOTipo7DeHyndmanFan)
{
    // Os três valores conferidos contra R: quantile(c(1,2,3,4,5), type=7).
    const double v[] = {1, 2, 3, 4, 5};
    EXPECT_NEAR(percentil(v, 5, 0.25), 2.0, TOL);
    EXPECT_NEAR(percentil(v, 5, 0.50), 3.0, TOL);
    EXPECT_NEAR(percentil(v, 5, 0.75), 4.0, TOL);
}

TEST(Percentil, InterpolaEntreAmostrasQuandoAPosicaoNaoEInteira)
{
    // n=4: h = 3p. p25 -> h=0,75, entre x[0] e x[1]; p75 -> h=2,25.
    const double v[] = {10, 20, 30, 40};
    EXPECT_NEAR(percentil(v, 4, 0.25), 17.5, TOL);
    EXPECT_NEAR(percentil(v, 4, 0.50), 25.0, TOL);
    EXPECT_NEAR(percentil(v, 4, 0.75), 32.5, TOL);
    EXPECT_NEAR(percentil(v, 4, 0.99), 39.7, 1e-9);
}

TEST(Percentil, ExtremosDevolvemMinimoEMaximo)
{
    const double v[] = {1, 2, 3, 4, 5};
    EXPECT_NEAR(percentil(v, 5, 0.0), 1.0, TOL);
    EXPECT_NEAR(percentil(v, 5, 1.0), 5.0, TOL);
}

TEST(Percentil, AmostraUnicaDevolveOValorParaQualquerPercentil)
{
    // A guarda n==1 não é redundante: sem ela, h = 0·p = 0 e a expressão
    // acessaria v[1], fora do vetor.
    const double v[] = {42.0};
    for (double p : {0.0, 0.25, 0.5, 0.99, 1.0})
        EXPECT_NEAR(percentil(v, 1, p), 42.0, TOL);
}

TEST(Percentil, AmostrasIguaisDevolvemOMesmoValorEmTodoPercentil)
{
    const double v[] = {5, 5, 5};
    for (double p : {0.0, 0.25, 0.5, 0.75, 0.99, 1.0})
        EXPECT_NEAR(percentil(v, 3, p), 5.0, TOL);
}

// ---------------------------------------------------------------------
// selo() — a marca que diz ao leitor se pode confiar no valor
// ---------------------------------------------------------------------

// Este é o caso que motivou a criação do selo "?", e a regressão que ele impede.
TEST(Selo, MedicaoQueFalhouNaoPodeParecerAMaisConfiavel)
{
    // Cenário real: uma função de medição devolve 0.0 porque pthread_create
    // falhou. Todas as amostras viram zero. Aí média e mediana são zero, e os
    // guards `media > 0` / `mediana > 0` de summarize(), que existem para evitar
    // divisão por zero, fazem cv e disp valerem 0,0%.
    //
    // Com disp = 0, selo() devolvia " ": a linha em que NADA foi medido
    // aparecia como a mais confiável da tabela.
    double v[5] = {0, 0, 0, 0, 0};
    const struct statistics e = summarize(v, 5);

    EXPECT_NEAR(e.median, 0.0, TOL);
    EXPECT_NEAR(e.disp, 0.0, TOL);          // o guard continua evitando o NaN
    EXPECT_STREQ(badge(e), "?");             // mas o selo não mente mais
}

TEST(Selo, MedicaoNegativaEUmCodigoDeErro)
{
    // As funções de medição deste projeto devolvem negativo como erro, e uma
    // duração negativa não existe.
    double v[3] = {-1, -1, -1};
    EXPECT_STREQ(badge(summarize(v, 3)), "?");
}

TEST(Selo, VetorVazioNaoRecebeSeloDeEstavel)
{
    struct statistics e = summarize(nullptr, 0);
    EXPECT_EQ(e.samples, 0);
    EXPECT_STREQ(badge(e), "?");
}

TEST(Selo, DispersaoDecideAsTresFaixas)
{
    // Os limiares são DISP_ESTAVEL (3%) e DISP_SUSPEITA (10%), e o selo sai da
    // dispersão ROBUSTA, nunca do CV.
    struct statistics e{};
    e.samples = 25;
    e.median = 10.0;

    e.disp = 0.0;                 EXPECT_STREQ(badge(e), " ");
    e.disp = DISP_ESTAVEL;        EXPECT_STREQ(badge(e), " ");   // fronteira inclusiva
    e.disp = DISP_ESTAVEL + 0.1;  EXPECT_STREQ(badge(e), "~");
    e.disp = DISP_SUSPEITA;       EXPECT_STREQ(badge(e), "~");   // fronteira inclusiva
    e.disp = DISP_SUSPEITA + 0.1; EXPECT_STREQ(badge(e), "!");
}

// ---------------------------------------------------------------------
// summarize() — o resumo completo
// ---------------------------------------------------------------------

TEST(Resumir, CalculaOsCamposDeUmaAmostraConhecida)
{
    double v[] = {5, 1, 3, 2, 4};   // desordenado de propósito
    const struct statistics e = summarize(v, 5);

    EXPECT_EQ(e.samples, 5);
    EXPECT_NEAR(e.minimum, 1.0, TOL);
    EXPECT_NEAR(e.maximum, 5.0, TOL);
    EXPECT_NEAR(e.median, 3.0, TOL);
    EXPECT_NEAR(e.p25, 2.0, TOL);
    EXPECT_NEAR(e.p75, 4.0, TOL);

    // disp = (p75-p25)/mediana = (4-2)/3 = 66,67%
    EXPECT_NEAR(e.disp, 200.0 / 3.0, 1e-9);

    // média = 3; variância amostral = 10/4 = 2,5; cv = 100·√2,5/3
    EXPECT_NEAR(e.cv, 100.0 * std::sqrt(2.5) / 3.0, 1e-9);
}

TEST(Resumir, OrdenaOVetorNoLugar)
{
    // Efeito colateral documentado no cabeçalho. Quem passar um vetor que
    // precise manter a ordem original tem de copiá-lo antes.
    double v[] = {3, 1, 2};
    summarize(v, 3);
    EXPECT_NEAR(v[0], 1.0, TOL);
    EXPECT_NEAR(v[1], 2.0, TOL);
    EXPECT_NEAR(v[2], 3.0, TOL);
}

TEST(Resumir, EntradasInvalidasDevolvemEstruturaZerada)
{
    for (const struct statistics &e : {summarize(nullptr, 5), summarize(nullptr, 0)}) {
        EXPECT_EQ(e.samples, 0);
        EXPECT_NEAR(e.median, 0.0, TOL);
    }

    double v[] = {1.0};
    const struct statistics neg = summarize(v, -1);
    EXPECT_EQ(neg.samples, 0);
}

TEST(Resumir, UmaAmostraTemVarianciaZeroPorDefinicao)
{
    // var /= (n > 1 ? n-1 : 1). Com n=1 não há grau de liberdade: a variância
    // amostral é indefinida, e o arquivo escolhe reportar 0 em vez de NaN.
    // O leitor precisa saber que 0,0% de CV aqui vem de UMA observação.
    double v[] = {7.0};
    const struct statistics e = summarize(v, 1);
    EXPECT_EQ(e.samples, 1);
    EXPECT_NEAR(e.median, 7.0, TOL);
    EXPECT_NEAR(e.cv, 0.0, TOL);
    EXPECT_NEAR(e.disp, 0.0, TOL);
    EXPECT_STREQ(badge(e), " ");   // mediana > 0: é medição, ainda que magra
}

TEST(Resumir, NenhumCampoSaiComoNaNOuInfinito)
{
    // Os guards existem para isto. Sem eles, 0/0 produz NaN, e NaN atravessa
    // toda a formatação sem erro até virar "-nan" numa tabela publicada.
    double zeros[4] = {0, 0, 0, 0};
    const struct statistics e = summarize(zeros, 4);
    for (double x : {e.median, e.minimum, e.maximum, e.p25, e.p75, e.p99, e.cv, e.disp}) {
        EXPECT_FALSE(std::isnan(x));
        EXPECT_FALSE(std::isinf(x));
    }
}

// ---------------------------------------------------------------------
// amostras() — o teto vindo do ambiente
// ---------------------------------------------------------------------

TEST(Amostras, SemVariavelDeAmbienteDevolveOPadrao)
{
    unsetenv("DPDK_ACADEMY_AMOSTRAS");
    EXPECT_EQ(samples(25), 25);
    EXPECT_EQ(samples(11), 11);
}

TEST(Amostras, EUmTetoENuncaAumentaOPadrao)
{
    // A invariante que o CI depende: definir a variável só pode REDUZIR o
    // trabalho. Se pudesse aumentar, um valor grande no ambiente faria a suíte
    // levar horas sem que ninguém tivesse pedido.
    for (const char *valor : {"3", "5", "25", "1000", "999999"}) {
        setenv("DPDK_ACADEMY_AMOSTRAS", valor, 1);
        EXPECT_LE(samples(25), 25) << "valor = " << valor;
        EXPECT_LE(samples(11), 11) << "valor = " << valor;
    }
    unsetenv("DPDK_ACADEMY_AMOSTRAS");
}

TEST(Amostras, TemUmPisoDeTresQueADocumentacaoNaoMenciona)
{
    // `const int teto = n >= 3 ? n : 3` — qualquer valor abaixo de 3, e também
    // lixo que atoi() converte para 0, colapsam em 3. O contrato real é a faixa
    // [3, padrao], não "o que você pedir".
    for (const char *valor : {"0", "1", "2", "-7", "abc", ""}) {
        setenv("DPDK_ACADEMY_AMOSTRAS", valor, 1);
        EXPECT_EQ(samples(25), 3) << "valor = " << valor;
    }
    unsetenv("DPDK_ACADEMY_AMOSTRAS");
}

TEST(Amostras, NuncaDevolveValorQueQuebrariaColetar)
{
    // collect() faz malloc(n * sizeof(double)) e um laço de n iterações. Um n
    // zero ou negativo produziria malloc(0) e uma estatística de vetor vazio.
    // O piso de 3 impede isso por construção.
    for (const char *valor : {"0", "-1", "-999999", "abc"}) {
        setenv("DPDK_ACADEMY_AMOSTRAS", valor, 1);
        EXPECT_GE(samples(25), 3) << "valor = " << valor;
    }
    unsetenv("DPDK_ACADEMY_AMOSTRAS");
}

// ---------------------------------------------------------------------
// A estrutura em si
// ---------------------------------------------------------------------

TEST(Estatistica, TodosOsCamposSaoZeradosNaEntradaInvalida)
{
    // summarize() usa `struct statistics e = {0,0,0,0,0,0,0,0,0}` — nove zeros
    // para nove campos. Acrescentar um campo sem acrescentar um zero deixaria
    // lixo, e o aviso do compilador que pegaria isso não é erro.
    const struct statistics e = summarize(nullptr, 0);
    EXPECT_NEAR(e.median, 0.0, TOL);
    EXPECT_NEAR(e.minimum, 0.0, TOL);
    EXPECT_NEAR(e.maximum, 0.0, TOL);
    EXPECT_NEAR(e.p25, 0.0, TOL);
    EXPECT_NEAR(e.p75, 0.0, TOL);
    EXPECT_NEAR(e.p99, 0.0, TOL);
    EXPECT_NEAR(e.cv, 0.0, TOL);
    EXPECT_NEAR(e.disp, 0.0, TOL);
    EXPECT_EQ(e.samples, 0);
}

}  // namespace
