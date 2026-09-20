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
 *   - com 2 MB hugepages, onde a mesma quantidade de entradas de TLB cobre
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

#include "cadeia.h"
#include "clock_ns.h"
#include "statistics.h"

#define REGIAO_BYTES (512ull * 1024 * 1024)
/* Cada amostra aloca 512 MB e percorre milhões de linhas: poucas amostras,
 * senão o programa leva minutos. */
/* VINTE E UMA, e a escolha nao e de orcamento de tempo.
 *
 * Com 7 amostras estas linhas saiam com dispersao entre 3% e 15%, que e
 * exatamente a faixa onde o selo NAO DECIDE abaixo de 20 amostras -- medido em
 * 18/09/2026 e documentado na secao "QUANTAS AMOSTRAS O SELO EXIGE" de
 * statistics.h. O `avisar_selo_indeciso()` avisava em stderr a cada execucao, e
 * o aviso ficou sem resposta ate 19/09/2026.
 *
 * 21 e o mesmo valor que a fase 2 do custo-paralelismo usa, pelo mesmo motivo. */
#define AMOSTRAS_PAGINA_FIXO 21
#define AMOSTRAS_PAGINA samples(AMOSTRAS_PAGINA_FIXO)
#define LINHA_CACHE 64
#define BUDGET_10GBE_NS 67.2

static volatile size_t sumidouro;


/* Monta uma permutação cíclica sobre as linhas de cache da região e a percorre.
 * Devolve o tempo médio por acesso. */
static double medir(void *mem, size_t bytes)
{
    const size_t n = bytes / LINHA_CACHE;
    size_t *p = (size_t *)mem;
    size_t *ordem = malloc(n * sizeof(size_t));
    if (ordem == NULL)
        return -1.0;

    /* Permutação e encadeamento vêm de `cadeia.h`, com a propriedade
     * "ciclo único que visita cada linha uma vez" verificada em L1. Estava
     * escrito à mão aqui, e a terceira cópia da mesma construção saiu errada
     * em `efeito-cache.c` — ver o cabeçalho de `cadeia.h`. */
    static uint64_t semente = 0x2545F4914F6CDD1Dull;
    academy_permutar(ordem, n, &semente);
    const size_t nos = academy_cadeia_nos(n, 1);
    for (size_t i = 0; i < nos; i++)
        p[ordem[i] * (LINHA_CACHE / sizeof(size_t))] =
            academy_sucessor(ordem, n, 1, i) * (LINHA_CACHE / sizeof(size_t));
    free(ordem);

    size_t idx = 0;
    const size_t iteracoes = n * 4;
    const uint64_t t0 = academy_now_ns();
    for (size_t i = 0; i < iteracoes; i++)
        idx = p[idx];
    const uint64_t dt = academy_now_ns() - t0;
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
    print_provenance("custo-traducao");
    printf("Custo da traducao de endereco (percurso disperso em %llu MB)\n",
           REGIAO_BYTES / (1024 * 1024));
    printf("(%d amostras por medicao; tempos em ns)\n\n", AMOSTRAS_PAGINA);

    if (amostra_2m() < 0) {
        printf("  2 MB hugepages indisponiveis para este processo.\n\n");
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

    /* COLETA PAREADA, e nao dois blocos sequenciais. A versao anterior media 21
     * amostras de 4 KB e depois 21 de 2 MB, e subtraia as medianas -- o que
     * absorve a deriva da maquina entre os dois blocos e, pior, publica a
     * diferenca sem nenhum indicador da estabilidade DELA. Ver o comentario de
     * `collect_paired` em statistics.h. */
    print_header();
    const struct paired_stats p =
        collect_paired(amostra_4k, amostra_2m, AMOSTRAS_PAGINA);
    if (!collection_is_valid(p.a, AMOSTRAS_PAGINA) ||
        !collection_is_valid(p.b, AMOSTRAS_PAGINA)) {
        fprintf(stderr, "COLETA INVALIDA OU ABAIXO DA RESOLUCAO:"
                        " sem resultado publicavel\n");
        return EXIT_FAILURE;
    }
    const struct statistics e4k = p.a, e2m = p.b;
    print_row("4 KB pages", e4k);
    print_row("2 MB hugepages", e2m);
    printf("\n  A diferenca abaixo e PAREADA -- delta_i = t_4k,i - t_2m,i na mesma\n"
           "  volta do laco -- e por isso tem distribuicao propria:\n\n");
    /* "DIFERENCA (o page walk)" era o rotulo, e ele prometia demais.
     *
     * t_4K - t_2M nao e uma medicao direta do page walk: e a diferenca pareada
     * entre dois REGIMES de tradução, num desenho construido para que o custo
     * adicional de tradução domine a diferenca. A pagina de 2 MB tambem tem
     * tradução e tambem tem TLB -- o que ela nao tem e a mesma PRESSAO sobre
     * ela. Chamar a diferenca de "o page walk" apaga essa distincao. */
    print_delta("DIFFERENCE attributable to translation", p);

    const double ns_4k = e4k.median, ns_2m = e2m.median;
    const double delta = p.delta.median;
    printf("\n  custo do page walk: %.2f ns  (%.1f%% do acesso com 4 KB)\n", delta,
           100.0 * delta / ns_4k);
    printf("  a ultima coluna e o que sustenta a conclusao: em %d dos %d pares a\n"
           "  pagina de 4 KB foi a mais lenta. Subtrair duas medianas nao diz isso.\n",
           p.mesmo_sinal, p.n);

    printf("\n  A latencia da RAM (~%.0f ns) aparece nas duas medicoes e nao\n", ns_2m);
    printf("  depende do tamanho da pagina. A diferenca acima e o custo do\n");
    printf("  page walk, que as hugepages eliminam: %.1f%% do orcamento de\n",
           100.0 * delta / BUDGET_10GBE_NS);
    printf("  %.1f ns por pacote em 10 GbE, gasto antes de qualquer trabalho util.\n",
           BUDGET_10GBE_NS);
    return 0;
}
