/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Estatística mínima para microbenchmarks.
 *
 * POR QUE ISTO EXISTE
 *
 * Publicar um número solto ("8,4 ns") esconde a pergunta que importa: quão
 * confiável ele é? Uma medição de 8,4 com dispersão de 0,1 e outra de 8,4 com
 * dispersão de 6,0 sustentam conclusões muito diferentes, e o leitor não tem
 * como distinguir se só lhe damos a média.
 *
 * O QUE REPORTAMOS, E POR QUÊ
 *
 *   mediana  - tendência central robusta. Diferente da média, não é arrastada
 *              por uma única amostra ruim (uma interrupção do sistema no meio
 *              da coleta).
 *
 *   mínimo   - em microbenchmark de operação determinística, o ruído é
 *              UNILATERAL: interferência só faz a medição demorar mais, nunca
 *              menos. Por isso o mínimo é a melhor estimativa do custo real da
 *              operação, e a mediana estima o que se observa na prática. Quando
 *              os dois quase coincidem, a medição está limpa.
 *
 *   p25-p75  - intervalo interquartil: onde caem as 50% amostras centrais.
 *
 *   amplitude- min-max, a faixa completa observada. Vale reportá-la mesmo sendo
 *              sensível a um único outlier: em trabalho acadêmico, esconder a
 *              extensão do que se observou é pior que exibi-la. Quando a
 *              amplitude é muito maior que o intervalo interquartil, há
 *              interferência esporádica que o leitor precisa conhecer.
 *
 *   CV       - coeficiente de variação (desvio padrão / média, em %).
 *              Reportado, mas NÃO usado para julgar a medição, porque é
 *              sensível a um único outlier: uma amostra ruim entre 25 pode
 *              levá-lo de 2% a 27% sem que a mediana se mova. Serve como
 *              DETECTOR DE OUTLIER, não como medida de confiança.
 *
 * COMO LER disp E CV JUNTOS
 *
 * O selo (~ ou !) sai de `disp`, e só dela: é o indicador de CONFIANÇA, robusto
 * por não olhar as caudas. Diz se o valor típico é reprodutível.
 *
 * O CV entra como segunda leitura, pela RELAÇÃO com disp:
 *
 *   CV parecido com disp   -> distribuição bem comportada.
 *   CV muito maior que disp -> o miolo é firme, mas houve amostras isoladas
 *                              destoantes: interferência esporádica, não
 *                              instabilidade do valor.
 *
 * Deliberadamente não há marcador binário para outlier. Um limiar do tipo
 * "máximo > 1,25x a mediana" produz um penhasco arbitrário: duas linhas com
 * excursão praticamente igual (1,246x e 1,264x) receberiam selos opostos por
 * uma diferença de 1,4%. Exibir os dois números e ensinar a lê-los juntos é
 * mais honesto que esconder a continuidade atrás de um limiar.
 *
 * O QUE ISTO NÃO É
 *
 * Não é análise estatística rigorosa: não há intervalo de confiança formal nem
 * teste de hipótese, porque as amostras de um microbenchmark não são
 * independentes nem normalmente distribuídas (há autocorrelação por estado de
 * cache e por frequência da CPU). O objetivo é honestidade sobre a dispersão,
 * não inferência.
 */
#ifndef DPDK_ACADEMY_STATISTICS_H
#define DPDK_ACADEMY_STATISTICS_H

/* Compartilhado entre custo-espera.c e custo-espera-cpp.cpp: a comparação entre
 * as duas linguagens só vale se a metodologia de coleta for literalmente a
 * mesma, e não apenas equivalente. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Nem todo programa usa todas as variantes de impressão. */
#if defined(__GNUC__)
#define STAT_MAYBE_UNUSED __attribute__((unused))
#else
#define STAT_MAYBE_UNUSED
#endif

/* Número de amostras. Pode ser reduzido pela variável de ambiente
 * DPDK_ACADEMY_AMOSTRAS, para que a integração contínua verifique que os
 * programas EXECUTAM sem gastar minutos coletando estatística que ninguém vai
 * ler. Medição de verdade usa o padrão. */
#define DEFAULT_SAMPLES_FIXED 25
/* Limiares sobre a dispersão ROBUSTA (IQR/mediana), não sobre o CV. */
#define DISP_ESTAVEL 3.0
#define DISP_SUSPEITA 10.0


struct statistics {
    double median;
    double minimum;
    double maximum;
    double p25, p75;
    double p99;   /* cauda: só é significativo com amostras suficientes */
    double cv;    /* coeficiente de variação, em % — sensível a outliers */
    double disp;  /* dispersão robusta: (p75-p25)/mediana, em % */
    int samples;
};

/* Devolve quantas amostras usar. Medições caras declaram um padrão menor; a
 * variável de ambiente, quando presente, é um TETO aplicado a todas. */
static STAT_MAYBE_UNUSED int samples(int padrao)
{
    const char *e = getenv("DPDK_ACADEMY_AMOSTRAS");
    if (e == NULL)
        return padrao;
    const int n = atoi(e);
    const int teto = n >= 3 ? n : 3; /* menos de 3 não permite quartis úteis */
    return padrao < teto ? padrao : teto;
}

#define DEFAULT_SAMPLES samples(DEFAULT_SAMPLES_FIXED)

static int cmp_double(const void *a, const void *b)
{
    const double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}

/* Percentil por interpolação linear sobre o vetor JÁ ORDENADO. */
static STAT_MAYBE_UNUSED double percentil(const double *v, int n, double p)
{
    if (n == 1)
        return v[0];
    const double pos = p * (n - 1);
    const int i = (int)pos;
    const double frac = pos - i;
    return i + 1 < n ? v[i] + frac * (v[i + 1] - v[i]) : v[n - 1];
}

/* Resume um vetor de amostras JÁ coletadas. ORDENA `v` no lugar.
 *
 * Existe separado de collect() porque nem toda medição cabe no formato "chame
 * esta função n vezes": travessia entre processos, por exemplo, produz uma
 * amostra por mensagem recebida, e o vetor já chega pronto. */
static STAT_MAYBE_UNUSED struct statistics summarize(double *v, int n)
{
    struct statistics e = {0, 0, 0, 0, 0, 0, 0, 0, 0};
    if (v == NULL || n <= 0)
        return e;

    double soma = 0;
    for (int i = 0; i < n; i++)
        soma += v[i];
    const double media = soma / n;

    double var = 0;
    for (int i = 0; i < n; i++)
        var += (v[i] - media) * (v[i] - media);
    var /= (n > 1 ? n - 1 : 1); /* variância amostral */

    qsort(v, (size_t)n, sizeof(double), cmp_double);
    e.samples = n;
    e.minimum = v[0];
    e.maximum = v[n - 1];
    e.median = percentil(v, n, 0.50);
    e.p25 = percentil(v, n, 0.25);
    e.p75 = percentil(v, n, 0.75);
    e.p99 = percentil(v, n, 0.99);
    e.cv = media > 0 ? 100.0 * sqrt(var) / media : 0.0;
    e.disp = e.median > 0 ? 100.0 * (e.p75 - e.p25) / e.median : 0.0;

    return e;
}

/* Executa `medicao` n vezes e resume as amostras. */
static STAT_MAYBE_UNUSED struct statistics collect(double (*measurement)(void), int n)
{
    /* Cast explícito: este cabeçalho é compartilhado com a versão em C++, onde
     * a conversão implícita de void* não é permitida. */
    double *v = (double *)malloc((size_t)n * sizeof(double));
    struct statistics e = {0, 0, 0, 0, 0, 0, 0, 0, 0};
    if (v == NULL)
        return e;

    for (int i = 0; i < n; i++)
        v[i] = measurement();

    e = summarize(v, n);
    free(v);
    return e;
}

/* Marca visual de confiança, para o leitor não precisar interpretar o CV.
 *
 *   " "  dispersão baixa: o valor típico é confiável
 *   "~"  dispersão moderada: leia com reserva
 *   "!"  dispersão alta: o valor típico diz pouco
 *   "?"  NÃO HOUVE MEDIÇÃO — ver abaixo
 *
 * O SELO "?" EXISTE POR CAUSA DE UM DEFEITO REAL DESTE ARQUIVO.
 *
 * Quando uma medição falha por completo — por exemplo, uma função de medição
 * que devolve 0.0 porque pthread_create falhou —, todas as amostras são zero.
 * Aí `media` e `mediana` são zero, e os guards `media > 0` / `mediana > 0` de
 * summarize(), que existem para evitar divisão por zero, fazem cv e disp valerem
 * **0,0%**. Com disp = 0, este selo devolvia " ": a linha da tabela em que nada
 * foi medido aparecia como a MAIS confiável do conjunto.
 *
 * Uma medição de tempo cuja mediana é exatamente zero não é uma medição rápida:
 * é uma medição que não aconteceu. O selo agora diz isso.
 *
 * Mediana negativa recebe o mesmo tratamento: as funções de medição deste
 * projeto devolvem valores negativos como código de erro, e uma duração
 * negativa não existe. */
static STAT_MAYBE_UNUSED const char *badge(struct statistics e)
{
    if (e.samples <= 0 || e.median <= 0.0)
        return "?";
    if (e.disp <= DISP_ESTAVEL)
        return " ";
    if (e.disp <= DISP_SUSPEITA)
        return "~";
    return "!";
}

/* Casas decimais conforme a magnitude: sem isso, valores abaixo de 1 ns saem
 * todos iguais na exibição e contradizem o CV, que é calculado sobre os
 * valores reais. */
static STAT_MAYBE_UNUSED int decimals(double v)
{
    if (v < 1.0)
        return 3;
    if (v < 100.0)
        return 2;
    return 1;
}

static STAT_MAYBE_UNUSED void print_row(const char *rotulo, struct statistics e)
{
    const int d = decimals(e.median);
    char iqr[40], amp[40];
    snprintf(iqr, sizeof(iqr), "%.*f-%.*f", d, e.p25, d, e.p75);
    snprintf(amp, sizeof(amp), "%.*f-%.*f", d, e.minimum, d, e.maximum);
    printf("  %-34s %9.*f  %-15s %-17s %5.1f%% %5.1f%% %s\n", rotulo, d, e.median, iqr, amp,
           e.disp, e.cv, badge(e));
}

static STAT_MAYBE_UNUSED void print_header(void)
{
    printf("  %-34s %9s  %-15s %-17s %5s %5s\n", "medicao", "mediana", "p25-p75 (IQR)",
           "amplitude min-max", "disp", "CV");
    printf("  %-34s %9s  %-15s %-17s %5s %5s\n", "----------------------------------", "---------",
           "---------------", "-----------------", "-----", "-----");
}

/* Variante com conversão para ciclos de clock. Comparar em CICLOS neutraliza a
 * diferença de frequência entre máquinas e gerações — é assim que se separa
 * "ficou mais rápido porque o clock subiu" de "ficou mais rápido de verdade". */
static STAT_MAYBE_UNUSED void print_row_cycles(const char *rotulo, struct statistics e, double period_ns)
{
    const int d = decimals(e.median);
    char iqr[40];
    snprintf(iqr, sizeof(iqr), "%.*f-%.*f", d, e.p25, d, e.p75);
    printf("  %-34s %9.*f  %-15s %8.0f      %5.1f%% %s\n", rotulo, d, e.median, iqr,
           period_ns > 0 ? e.median / period_ns : 0.0, e.disp, badge(e));
}

static STAT_MAYBE_UNUSED void print_header_cycles(void)
{
    /* O rótulo é `disp`, e não `CV`, porque é `e.disp` que imprimir_ciclos()
     * publica nesta coluna. Enquanto dizia "CV", a tabela mais acadêmica do
     * projeto -- a que confronta a Tabela 3.1 de McKenney -- rotulava a
     * dispersão robusta com o nome do coeficiente de variação, que é outra
     * grandeza e vive na outra variante de impressão. */
    printf("  %-34s %9s  %-15s %8s      %5s\n", "medicao", "mediana", "p25-p75 (IQR)", "ciclos",
           "disp");
    printf("  %-34s %9s  %-15s %8s      %5s\n", "----------------------------------", "---------",
           "---------------", "--------", "-----");
}

/* Variante para LATÊNCIA, que se reporta por percentis e não por valor típico.
 * Publica p99 no lugar da amplitude: em plano de dados a cauda é o requisito,
 * e o máximo isolado é uma amostra só — informa menos do que parece. */
static STAT_MAYBE_UNUSED void print_row_tail(const char *rotulo, struct statistics e)
{
    const int d = decimals(e.median);
    printf("  %-30s %9.*f %9.*f %9.*f %9.*f  %7d\n", rotulo, d, e.minimum, d, e.median, d, e.p75, d,
           e.p99, e.samples);
}

static STAT_MAYBE_UNUSED void print_header_tail(void)
{
    printf("  %-30s %9s %9s %9s %9s  %7s\n", "medicao", "minimo", "mediana", "p75", "p99",
           "amostras");
    printf("  %-30s %9s %9s %9s %9s  %7s\n", "------------------------------", "---------",
           "---------", "---------", "---------", "-------");
}

#endif
