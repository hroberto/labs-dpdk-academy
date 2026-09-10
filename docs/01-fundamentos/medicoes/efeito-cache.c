/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Fundamentos — por que "estrutura de dados contígua" não é preferência de
 * estilo, e sim decisão de desempenho.
 *
 * Percorre o mesmo vetor de duas formas, para conjuntos de trabalho de tamanhos
 * crescentes (que cabem em L1, L2, L3 e só na RAM):
 *
 *   sequencial — a[0], a[1], a[2]...  o prefetcher da CPU acerta a previsão e
 *                busca a linha de cache seguinte antes de ela ser pedida.
 *   aleatorio  — ordem embaralhada.   O prefetcher erra, e cada acesso paga a
 *                latência real do nível de memória onde o dado está.
 *
 * A diferença entre as duas colunas é o custo de perder a localidade.
 *
 * METODOLOGIA: igual à dos demais programas desta pasta. Ver statistics.h.
 */
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "statistics.h"

/* Total de acessos por medição, constante entre os tamanhos para comparar. */
#define ACESSOS_TOTAIS (64u * 1024u * 1024u)
#define AMOSTRAS_CACHE_FIXO 9
#define AMOSTRAS_CACHE samples(AMOSTRAS_CACHE_FIXO)

/* collect() recebe ponteiro sem argumentos; o caso vai por variáveis. */
static size_t caso_tam;
static int caso_aleatorio;

static uint64_t now_ns(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000000000ull + t.tv_nsec;
}

static double medir(const uint32_t *a, const uint32_t *ordem, size_t n, size_t repeticoes)
{
    volatile uint64_t soma = 0;
    const uint64_t t0 = now_ns();
    if (ordem == NULL) {
        for (size_t r = 0; r < repeticoes; r++)
            for (size_t i = 0; i < n; i++)
                soma += a[i];
    } else {
        for (size_t r = 0; r < repeticoes; r++)
            for (size_t i = 0; i < n; i++)
                soma += a[ordem[i]];
    }
    (void)soma;
    return (double)(now_ns() - t0) / (double)(n * repeticoes);
}

/* Uma amostra do caso corrente: aloca, embaralha se preciso, percorre. */
static double amostra_caso(void)
{
    const size_t n = caso_tam / sizeof(uint32_t);
    uint32_t *a = aligned_alloc(64, n * sizeof(uint32_t));
    uint32_t *ordem = malloc(n * sizeof(uint32_t));
    if (a == NULL || ordem == NULL) {
        free(a);
        free(ordem);
        return -1.0;
    }
    for (size_t i = 0; i < n; i++) {
        a[i] = (uint32_t)i;
        ordem[i] = (uint32_t)i;
    }
    if (caso_aleatorio) {
        for (size_t i = n - 1; i > 0; i--) {
            const size_t j = (size_t)rand() % (i + 1);
            const uint32_t t = ordem[i];
            ordem[i] = ordem[j];
            ordem[j] = t;
        }
    }
    const size_t repeticoes = ACESSOS_TOTAIS / n + 1;
    const double r = medir(a, caso_aleatorio ? ordem : NULL, n, repeticoes);
    free(a);
    free(ordem);
    return r;
}

int main(void)
{
    const size_t tamanhos[] = {16u * 1024, 256u * 1024, 8u * 1024 * 1024, 256u * 1024 * 1024};
    const char *nivel[] = {"L1d", "L2", "L3", "RAM"};

    printf("Latencia media por acesso, conjunto de trabalho crescente\n");
    printf("(linha de cache = 64 B; cada uint32_t = 4 B, logo 16 por linha)\n\n");
    printf("(%d amostras por medicao; tempos em ns)\n\n", AMOSTRAS_CACHE);

    for (size_t k = 0; k < sizeof(tamanhos) / sizeof(tamanhos[0]); k++) {
        caso_tam = tamanhos[k];
        char rot[64];

        printf("  %s (%zu KB)\n", nivel[k], tamanhos[k] / 1024);
        print_header();

        caso_aleatorio = 0;
        const struct statistics seq = collect(amostra_caso, AMOSTRAS_CACHE);
        snprintf(rot, sizeof(rot), "  sequencial");
        print_row(rot, seq);

        caso_aleatorio = 1;
        const struct statistics ale = collect(amostra_caso, AMOSTRAS_CACHE);
        snprintf(rot, sizeof(rot), "  aleatorio");
        print_row(rot, ale);

        printf("  -> penalidade por perder a localidade: %.1fx\n\n", ale.median / seq.median);
        fflush(stdout);
    }

    printf("\n  Sequencial custa praticamente o mesmo em qualquer tamanho: o\n");
    printf("  prefetcher esconde a latencia. Aleatorio degrada ate a latencia\n");
    printf("  real da RAM -- e um unico acesso desses ja consome parte\n");
    printf("  significativa do orcamento de 67 ns por pacote em 10 GbE.\n");
    return 0;
}
