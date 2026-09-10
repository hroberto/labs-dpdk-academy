/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Fundamentos — quanto custa traduzir um endereço virtual em físico.
 *
 * Todo acesso à memória exige descobrir a que endereço físico o endereço
 * virtual corresponde. Quando a tradução está na TLB, isso é praticamente
 * gratuito. Quando não está, o hardware percorre a árvore de tabelas de página
 * (o "page walk"): até quatro leituras de memória antes do acesso pretendido.
 *
 * Este programa isola esse custo. Ele percorre 512 MB em ordem dispersa, de
 * duas formas:
 *
 *   - com páginas normais de 4 KB, onde a TLB não alcança o conjunto de
 *     trabalho e quase todo acesso paga a caminhada;
 *   - com hugepages de 2 MB, onde a mesma quantidade de entradas de TLB cobre
 *     512x mais memória e a caminhada tem um nível a menos.
 *
 * A latência da RAM aparece nas duas medições e não é o objeto do teste. O que
 * interessa é a DIFERENÇA entre elas: o custo da tradução.
 *
 * O percurso é feito por cadeia de ponteiros (cada acesso depende do anterior),
 * o que impede o processador de sobrepor os acessos e esconder a latência.
 *
 * METODOLOGIA: igual à dos demais programas desta pasta — várias amostras por
 * medição, publicadas com mediana, intervalo interquartil, amplitude e
 * coeficiente de variação. Ver statistics.h.
 *
 * Requer hugepages reservadas. Se não houver, o programa avisa e encerra sem
 * erro — reserve com, por exemplo:
 *   sudo sysctl -w vm.nr_hugepages=512
 */
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>

#include "statistics.h"

#define REGIAO_BYTES (512ull * 1024 * 1024)
/* Cada amostra aloca 512 MB e percorre milhões de linhas: poucas amostras,
 * senão o programa leva minutos. */
#define AMOSTRAS_PAGINA_FIXO 7
#define AMOSTRAS_PAGINA samples(AMOSTRAS_PAGINA_FIXO)
#define LINHA_CACHE 64
#define BUDGET_10GBE_NS 67.2

static volatile size_t sumidouro;

static uint64_t now_ns(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000000000ull + t.tv_nsec;
}

static uint64_t aleatorio_64(void)
{
    return ((uint64_t)rand() << 31) ^ (uint64_t)rand();
}

/* Monta uma permutação cíclica sobre as linhas de cache da região e a percorre.
 * Devolve o tempo médio por acesso. */
static double medir(void *mem, size_t bytes)
{
    const size_t n = bytes / LINHA_CACHE;
    size_t *p = (size_t *)mem;
    size_t *ordem = malloc(n * sizeof(size_t));
    if (ordem == NULL)
        return -1.0;

    for (size_t i = 0; i < n; i++)
        ordem[i] = i;
    /* Fisher-Yates: destrói qualquer previsibilidade para o prefetcher. */
    for (size_t i = n - 1; i > 0; i--) {
        const size_t j = (size_t)(aleatorio_64() % (i + 1));
        const size_t t = ordem[i];
        ordem[i] = ordem[j];
        ordem[j] = t;
    }
    /* Cada posição guarda o índice da próxima: o acesso vira uma cadeia. */
    for (size_t i = 0; i < n; i++)
        p[ordem[i] * (LINHA_CACHE / sizeof(size_t))] =
            ordem[(i + 1) % n] * (LINHA_CACHE / sizeof(size_t));
    free(ordem);

    size_t idx = 0;
    const size_t iteracoes = n * 4;
    const uint64_t t0 = now_ns();
    for (size_t i = 0; i < iteracoes; i++)
        idx = p[idx];
    const uint64_t dt = now_ns() - t0;
    sumidouro = idx;

    return (double)dt / (double)iteracoes;
}

/* Uma amostra completa: mapeia, percorre, desmapeia. Mapear a cada amostra é
 * proposital — reaproveitar o mapeamento deixaria a TLB aquecida da amostra
 * anterior e mediria menos que o custo real. */
static double amostra(int com_hugepages)
{
    const int extra = com_hugepages ? MAP_HUGETLB : 0;
    void *m = mmap(NULL, REGIAO_BYTES, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS | extra, -1, 0);
    if (m == MAP_FAILED)
        return -1.0;
    memset(m, 0, REGIAO_BYTES);
    const double r = medir(m, REGIAO_BYTES);
    munmap(m, REGIAO_BYTES);
    return r;
}

static double amostra_4k(void)
{
    return amostra(0);
}

static double amostra_2m(void)
{
    return amostra(1);
}

int main(void)
{
    printf("Custo da traducao de endereco (percurso disperso em %llu MB)\n",
           REGIAO_BYTES / (1024 * 1024));
    printf("(%d amostras por medicao; tempos em ns)\n\n", AMOSTRAS_PAGINA);

    if (amostra_2m() < 0) {
        printf("  hugepages de 2 MB indisponiveis para este processo.\n\n");
        printf("  Reserve hugepages para completar a medicao, por exemplo:\n");
        printf("    sudo sysctl -w vm.nr_hugepages=512\n");
        /* CÓDIGO 77 = PULADO, e não sucesso.
         *
         * Sair com 0 aqui fazia o Meson reportar OK sem que nada tivesse sido medido —
         * um falso verde. E não era caso raro: no runner do CI o requisito nunca
         * existiu, então este teste jamais verificou coisa alguma e sempre apareceu
         * verde. O Meson trata 77 como SKIP, conta separado e não falha a suíte. */
        return 77;
    }

    print_header();
    const struct statistics e4k = collect(amostra_4k, AMOSTRAS_PAGINA);
    print_row("paginas de 4 KB", e4k);
    const struct statistics e2m = collect(amostra_2m, AMOSTRAS_PAGINA);
    print_row("hugepages de 2 MB", e2m);

    const double ns_4k = e4k.median, ns_2m = e2m.median;
    const double delta = ns_4k - ns_2m;
    printf("\n  diferenca (o custo do page walk): %.2f ns  (%.1f%%)\n", delta,
           100.0 * delta / ns_4k);

    printf("\n  A latencia da RAM (~%.0f ns) aparece nas duas medicoes e nao\n", ns_2m);
    printf("  depende do tamanho da pagina. A diferenca acima e o custo do\n");
    printf("  page walk, que as hugepages eliminam: %.1f%% do orcamento de\n",
           100.0 * delta / BUDGET_10GBE_NS);
    printf("  %.1f ns por pacote em 10 GbE, gasto antes de qualquer trabalho util.\n",
           BUDGET_10GBE_NS);
    return 0;
}
