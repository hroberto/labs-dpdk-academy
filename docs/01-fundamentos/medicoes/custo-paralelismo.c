/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Fundamentos — latência não é vazão, e a diferença entre as duas é uma
 * decisão de projeto.
 *
 * O PROBLEMA QUE ESTE PROGRAMA RESOLVE
 *
 * `efeito-cache.c` publica ~7,5 ns por acesso aleatório à RAM. `custo-traducao.c`
 * publica ~95 ns para o mesmo acesso. Os dois estão certos, e por muito tempo o
 * documento tratou o primeiro número como "a latência da RAM" — que ele não é.
 *
 * A diferença é a CONCORRÊNCIA. Em `efeito-cache.c` o índice vem de um vetor
 * lido em sequência, então todos os endereços são conhecidos de antemão e o
 * processador dispara vários acessos ao mesmo tempo. Em `custo-traducao.c` cada
 * endereço só existe depois que o anterior chega, e nada se sobrepõe.
 *
 * Este programa mede a ponte entre os dois regimes. Ele percorre K cadeias de
 * ponteiros INDEPENDENTES sobre a mesma região, com K crescente:
 *
 *   K = 1    nada se sobrepõe: o resultado é a latência de um acesso.
 *   K médio  K acessos em voo: o custo amortizado cai por um fator de ~K.
 *   K grande a banda da memória satura, e mais concorrência não compra nada.
 *
 * A LEI POR TRÁS
 *
 *   vazão = concorrência / latência          (Little)
 *
 * A latência é uma propriedade física da máquina e não muda em nenhuma linha
 * desta tabela. O que muda é a concorrência — e ela é escolha de quem escreve o
 * programa. É por isso que "otimizar memória" quase nunca significa tornar um
 * acesso mais rápido, e quase sempre significa ter mais acessos em voo.
 *
 * O QUE ISTO CUSTA, E POR QUE A TABELA MOSTRA AS DUAS COLUNAS
 *
 * Concorrência não é de graça: para ter K acessos em voo é preciso ter K itens
 * à mão, ou seja, esperar o lote encher. Por isso a saída publica também o
 * tempo de conclusão do LOTE INTEIRO (K x ns/acesso). A vazão melhora sempre; o
 * tempo de lote piora depois de certo ponto. O joelho entre as duas curvas é a
 * decisão de engenharia que o módulo 04 discute.
 *
 * METODOLOGIA: igual à dos demais programas desta pasta. Ver statistics.h.
 *
 * Requer hugepages reservadas — aqui elas não são o objeto da medição, e sim a
 * forma de tirar a TLB da conta, para que a tabela meça concorrência e nada
 * mais. Sem elas o programa sai com 77 (PULADO):
 *   sudo sysctl -w vm.nr_hugepages=512
 */
#define _GNU_SOURCE
#include <pthread.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>

#include "cadeia.h"
#include "clock_ns.h"
#include "fixar_cpu.h"
#include "statistics.h"

#define REGIAO_BYTES (256ull * 1024 * 1024)
#define LINHA_CACHE 64
#define PASSO (LINHA_CACHE / sizeof(size_t))
/* Cada amostra remonta as cadeias sobre 256 MB: poucas amostras, senão o
 * programa leva minutos. */
#define AMOSTRAS_FIXO 7
#define AMOSTRAS samples(AMOSTRAS_FIXO)
#define BUDGET_10GBE_NS 67.2
/* Fase 2: quantas cadeias cada nucleo percorre. 16 e o joelho da fase 1 --
 * concorrencia suficiente para o nucleo sair da latencia pura, e ainda barata
 * em espera pelo lote. */
#define K_POR_NUCLEO 16
/* A fase 2 usa MAIS amostras que a fase 1, e isto foi medido.
 *
 * Com 7 amostras o selo de confianca vira loteria. Coletando 70 amostras e
 * recalculando `disp` em dez grupos de 7 — com o estimador de statistics.h,
 * interpolado —, o mesmo ponto de 2 cores produziu selo em branco cinco
 * vezes, `~` tres e `!` duas, quando a dispersao verdadeira e 4,4%. E em 4
 * nucleos, cuja dispersao verdadeira e 10,4% (`!`), NENHUM dos dez grupos
 * chegou a marcar `!`.
 *
 * O problema nao e a medicao: e o estimador. Com n = 7 o p25 sai interpolado
 * entre a 2a e a 3a amostra e o p75 entre a 5a e a 6a, e a distancia entre
 * esses dois pontos varia muito de coleta para coleta. A fase 1 sofre menos
 * porque um nucleo sozinho tem dispersao baixa; a fase 2, com varios nucleos
 * disputando memoria, cai exatamente na faixa de 3% a 15% onde o selo decide. */
#define AMOSTRAS_NUCLEOS_FIXO 21
#define AMOSTRAS_NUCLEOS samples(AMOSTRAS_NUCLEOS_FIXO)
#define ACESSOS_POR_NUCLEO (2u * 1024u * 1024u)
#define NUCLEOS_MAX 32
#define PPS_10GBE_64B 14.880952  /* milhões de pacotes/s — ver secao 1 "O orcamento: quanto tempo existe por pacote" do modulo */

static volatile size_t sumidouro;
static size_t *regiao;
static size_t linhas;
static size_t *ordem;

/* Monta K ciclos DISJUNTOS sobre as linhas da região e devolve o início de cada
 * um. Disjuntos é o ponto: duas cadeias nunca compartilham uma linha, então
 * percorrê-las em paralelo produz K acessos genuinamente independentes — e essa
 * propriedade é verificada em `tests/test_l1_cadeia.cpp`, não na inspeção.
 *
 * A semente avança entre amostras (permutação diferente a cada uma) mas parte de
 * valor fixo, então a execução inteira é reproduzível. */
static void montar_cadeias(int k, size_t *inicio)
{
    static uint64_t semente = 0x9E3779B97F4A7C15ull;
    academy_permutar(ordem, linhas, &semente);
    const size_t nos = academy_cadeia_nos(linhas, k);
    for (size_t i = 0; i < nos; i++)
        regiao[ordem[i] * PASSO] = academy_sucessor(ordem, linhas, k, i) * PASSO;
    for (int c = 0; c < k; c++)
        inicio[c] = ordem[academy_cadeia_inicio(linhas, k, c)] * PASSO;
}

/* Uma amostra: percorre as K cadeias em intercalação, devolvendo o tempo médio
 * por acesso. O total de acessos é constante entre os K, para que as linhas da
 * tabela sejam comparáveis.
 *
 * POR QUE K É CONSTANTE DE COMPILAÇÃO, E NÃO UM PARÂMETRO
 *
 * A primeira versão guardava os K índices num vetor na pilha e percorria com
 * `for (c = 0; c < k; c++)`. Com `k` variável o compilador não desenrola o laço
 * e os índices ficam na L1 em vez de em registradores — um acesso à L1 e um
 * incremento por acesso medido. Isso é invisível quando cada acesso custa 95 ns,
 * e deixa de ser quando custa 4: a versão com vetor publicava 4,83 ns em K = 32
 * contra 3,9 ns desta, ou seja **24% de sobrecarga do instrumento** exatamente
 * na região da tabela que decide onde fica o joelho.
 *
 * Com K literal, o laço interno desenrola e os índices viram registradores: o
 * que sobra no tempo medido é o acesso à memória, que é o objeto. O custo desta
 * decisão é gerar uma função por K — legibilidade trocada por uma medição que
 * não mede a si mesma. */
#define GERA_PERCURSO(K)                                                      \
    static double percurso_##K(void)                                          \
    {                                                                         \
        size_t idx[K];                                                        \
        montar_cadeias((K), idx);                                             \
        const size_t iteracoes = (4 * linhas) / (size_t)(K);                  \
        const uint64_t t0 = academy_now_ns();                                 \
        for (size_t i = 0; i < iteracoes; i++)                                \
            for (int c = 0; c < (K); c++)                                     \
                idx[c] = regiao[idx[c]];                                      \
        const uint64_t dt = academy_now_ns() - t0;                            \
        size_t soma = 0;                                                      \
        for (int c = 0; c < (K); c++)                                         \
            soma += idx[c];                                                   \
        sumidouro = soma;                                                     \
        return (double)dt / (double)(iteracoes * (size_t)(K));                \
    }

GERA_PERCURSO(1)
GERA_PERCURSO(2)
GERA_PERCURSO(4)
GERA_PERCURSO(8)
GERA_PERCURSO(12)
GERA_PERCURSO(16)
GERA_PERCURSO(32)
GERA_PERCURSO(64)

/* =====================================================================
 * FASE 2 — o teto e COMPARTILHADO
 *
 * A fase 1 mede um nucleo contra um controlador de memoria ocioso, e esse e o
 * numero que costuma ser citado. Ele nao e o que um plano de dados encontra:
 * ali varios lcores empurram a mesma memoria ao mesmo tempo, e a banda nao se
 * multiplica por nucleo.
 *
 * Esta fase mede exatamente isso. N nucleos fisicos, cada um percorrendo
 * K_POR_NUCLEO cadeias DISJUNTAS sobre a MESMA regiao -- nenhuma linha e
 * compartilhada entre threads, entao o que sobra de interferencia e o caminho
 * de memoria, que e o objeto.
 * ===================================================================== */

static int cpus_fisicas[NUCLEOS_MAX];
static int n_cpus_fisicas;

/* Uma CPU logica por nucleo FISICO. Numa CPU com SMT, dois irmaos dividem as
 * unidades de execucao e o L1: usa-los como "dois nucleos" mediria contencao de
 * SMT (ver secao 5.1.1 "SMT: duas CPUs logicas nao sao dois nucleos"), nao a banda de memoria. */
static void descobrir_cpus_fisicas(void)
{
    int vistos[NUCLEOS_MAX];
    int n_vistos = 0;
    for (int cpu = 0; cpu < 4 * NUCLEOS_MAX && n_cpus_fisicas < NUCLEOS_MAX; cpu++) {
        char caminho[128];
        snprintf(caminho, sizeof(caminho),
                 "/sys/devices/system/cpu/cpu%d/topology/core_id", cpu);
        FILE *f = fopen(caminho, "r");
        if (f == NULL)
            continue;
        int core = -1;
        if (fscanf(f, "%d", &core) == 1) {
            int novo = 1;
            for (int i = 0; i < n_vistos; i++)
                if (vistos[i] == core)
                    novo = 0;
            if (novo && n_vistos < NUCLEOS_MAX) {
                vistos[n_vistos++] = core;
                cpus_fisicas[n_cpus_fisicas++] = cpu;
            }
        }
        fclose(f);
    }
}

struct tarefa {
    int cpu;
    int primeira_cadeia;      /* fatia de cadeias que este nucleo percorre */
    const size_t *inicios;
    pthread_barrier_t *largada;
    double ns_por_acesso;     /* saida */
};

static void *trabalhar(void *arg)
{
    struct tarefa *t = arg;
    academy_fixar_cpu(t->cpu);

    size_t idx[K_POR_NUCLEO];
    for (int i = 0; i < K_POR_NUCLEO; i++)
        idx[i] = t->inicios[t->primeira_cadeia + i];

    const size_t iteracoes = ACESSOS_POR_NUCLEO / K_POR_NUCLEO;
    /* Todos comecam juntos: medir um nucleo enquanto os outros ainda montam
     * daria a ele um controlador de memoria vazio -- exatamente o que esta fase
     * existe para nao medir. */
    pthread_barrier_wait(t->largada);
    const uint64_t t0 = academy_now_ns();
    for (size_t i = 0; i < iteracoes; i++)
        for (int c2 = 0; c2 < K_POR_NUCLEO; c2++)
            idx[c2] = regiao[idx[c2]];
    const uint64_t dt = academy_now_ns() - t0;

    size_t soma = 0;
    for (int i = 0; i < K_POR_NUCLEO; i++)
        soma += idx[i];
    sumidouro = soma;
    t->ns_por_acesso = (double)dt / (double)(iteracoes * K_POR_NUCLEO);
    return NULL;
}

/* Devolve o ns/acesso do nucleo MAIS LENTO: e o unico valor que descreve a
 * janela em que todos os N estavam de fato empurrando memoria. */
static double medir_n_nucleos(int n)
{
    const int total_cadeias = n * K_POR_NUCLEO;
    size_t *inicios = malloc((size_t)total_cadeias * sizeof(size_t));
    if (inicios == NULL)
        return -1.0;
    montar_cadeias(total_cadeias, inicios);

    pthread_barrier_t largada;
    if (pthread_barrier_init(&largada, NULL, (unsigned)n) != 0) {
        free(inicios);
        return -1.0;
    }
    pthread_t fios[NUCLEOS_MAX];
    struct tarefa tarefas[NUCLEOS_MAX];
    for (int i = 0; i < n; i++) {
        tarefas[i] = (struct tarefa){ .cpu = cpus_fisicas[i],
                                      .primeira_cadeia = i * K_POR_NUCLEO,
                                      .inicios = inicios,
                                      .largada = &largada };
        if (pthread_create(&fios[i], NULL, trabalhar, &tarefas[i]) != 0) {
            for (int j = 0; j < i; j++)
                pthread_join(fios[j], NULL);
            pthread_barrier_destroy(&largada);
            free(inicios);
            return -1.0;
        }
    }
    double pior = 0.0;
    for (int i = 0; i < n; i++) {
        pthread_join(fios[i], NULL);
        if (tarefas[i].ns_por_acesso > pior)
            pior = tarefas[i].ns_por_acesso;
    }
    pthread_barrier_destroy(&largada);
    free(inicios);
    return pior;
}

static int caso_n;
static double amostra_n_nucleos(void) { return medir_n_nucleos(caso_n); }

int main(void)
{
    print_provenance("custo-paralelismo");
    static const struct { int k; double (*percorrer)(void); } casos[] = {
        {1, percurso_1},   {2, percurso_2},   {4, percurso_4},   {8, percurso_8},
        {12, percurso_12}, {16, percurso_16}, {32, percurso_32}, {64, percurso_64},
    };
    const size_t n_ks = sizeof(casos) / sizeof(casos[0]);

    printf("Latency vs throughput: the same access, with K in flight (%llu MB)\n",
           REGIAO_BYTES / (1024 * 1024));
    printf("(%d samples per measurement; times in ns)\n\n", AMOSTRAS);

    regiao = mmap(NULL, REGIAO_BYTES, PROT_READ | PROT_WRITE,
                  MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0);
    if (regiao == MAP_FAILED) {
        printf("  2 MB hugepages unavailable to this process.\n\n");
        printf("  They are not the object of this measurement: they take the TLB\n");
        printf("  out of the picture, so the table measures concurrency and nothing else.\n");
        printf("  Reserve them with, for example:\n");
        printf("    sudo sysctl -w vm.nr_hugepages=512\n");
        /* 77 = PULADO no Meson. Ver a nota de custo-traducao.c: sair com 0 aqui
         * publicaria verde sem que nada tivesse sido medido. */
        return 77;
    }
    memset(regiao, 0, REGIAO_BYTES);
    linhas = REGIAO_BYTES / LINHA_CACHE;
    ordem = malloc(linhas * sizeof(size_t));
    if (ordem == NULL) {
        fprintf(stderr, "out of memory for the order vector\n");
        return EXIT_FAILURE;
    }

    double ns[sizeof(casos) / sizeof(casos[0])];
    print_header();
    for (size_t i = 0; i < n_ks; i++) {
        char rot[64];
        const struct statistics e = collect_or_fail(casos[i].percorrer, AMOSTRAS);
        snprintf(rot, sizeof(rot), "K = %-2d (%d access%s in flight)", casos[i].k,
                 casos[i].k, casos[i].k == 1 ? "" : "es");
        print_row(rot, e);
        ns[i] = e.median;
    }

    printf("\n  What the table above means, column by column:\n\n");
    printf("   K   ns/access   M accesses/s   batch of K ready in   throughput gain\n");
    printf("  ---  ---------   -----------   ---------------------   --------------\n");
    for (size_t i = 0; i < n_ks; i++)
        printf("  %3d   %8.2f   %9.1f   %15.0f ns   %12.1fx\n",
               casos[i].k, ns[i], 1000.0 / ns[i], ns[i] * casos[i].k, ns[0] / ns[i]);

    printf("\n  The latency of ONE access is ~%.0f ns and does not change in any row.\n", ns[0]);
    printf("  What changes is how many of them happen at the same time.\n\n");
    printf("  With K = 1 this machine does %.1f M accesses/s -- BELOW the %.1f M\n",
           1000.0 / ns[0], PPS_10GBE_64B);
    printf("  packets/s of the 10 GbE line rate with 64 B frames. A single\n");
    printf("  dependent access per packet already loses the rate, before any\n");
    printf("  processing. With K = %d there is %.0f%% of headroom left.\n",
           casos[n_ks - 1].k, 100.0 * ((1000.0 / ns[n_ks - 1]) / PPS_10GBE_64B - 1.0));
    printf("\n  And the price: the batch of %d is only ready in %.0f ns, against %.0f ns\n",
           casos[n_ks - 1].k, ns[n_ks - 1] * casos[n_ks - 1].k, ns[0]);
    printf("  for the lone access. Throughput bought with latency -- the budget of\n");
    printf("  %.1f ns per packet says how much of that trade you can afford.\n", BUDGET_10GBE_NS);

    /* ---------------- FASE 2: o teto compartilhado ---------------- */
    descobrir_cpus_fisicas();
    if (n_cpus_fisicas < 2) {
        printf("\n  (phase 2 skipped: fewer than two physical cores visible)\n");
        free(ordem);
        munmap(regiao, REGIAO_BYTES);
        return 0;
    }

    printf("\n\n  PHASE 2 -- and when several cores want the same memory?\n\n");
    printf("  Each core walks %d chains of its own over the SAME region.\n",
           K_POR_NUCLEO);
    printf("  No line is shared between threads: what remains is the\n");
    printf("  memory path. %d physical cores available.\n", n_cpus_fisicas);
    printf("  (%d samples per point -- more than phase 1; see the comment\n"
           "   on AMOSTRAS_NUCLEOS_FIXO for why 7 are not enough here)\n\n",
           AMOSTRAS_NUCLEOS);

    static const int ns_nucleos[] = {1, 2, 4, 8, 12, 16};
    int usados[sizeof(ns_nucleos) / sizeof(ns_nucleos[0])];
    double por_nucleo[sizeof(ns_nucleos) / sizeof(ns_nucleos[0])];
    size_t n_casos = 0;

    print_header();
    for (size_t i = 0; i < sizeof(ns_nucleos) / sizeof(ns_nucleos[0]); i++) {
        if (ns_nucleos[i] > n_cpus_fisicas)
            break;
        char rot[64];
        caso_n = ns_nucleos[i];
        const struct statistics e = collect_or_fail(amostra_n_nucleos, AMOSTRAS_NUCLEOS);
        snprintf(rot, sizeof(rot), "%d core%s", caso_n, caso_n == 1 ? "" : "s");
        print_row(rot, e);
        usados[n_casos] = caso_n;
        por_nucleo[n_casos] = e.median;
        n_casos++;
    }

    printf("\n     cores   ns/access   M accesses/s     aggregate   ideal scaling\n");
    printf("  --------   ---------   -----------   -----------   ------------\n");
    for (size_t i = 0; i < n_casos; i++) {
        const double agregado = usados[i] * 1000.0 / por_nucleo[i];
        const double ideal = usados[i] * 1000.0 / por_nucleo[0];
        printf("  %8d   %9.2f   %9.1f     %9.1f   %10.0f%%\n",
               usados[i], por_nucleo[i], 1000.0 / por_nucleo[i], agregado,
               100.0 * agregado / ideal);
    }

    const size_t u = n_casos - 1;
    printf("\n  From 1 to %d cores the AGGREGATE throughput grows %.1fx, not %dx.\n",
           usados[u], (usados[u] * 1000.0 / por_nucleo[u]) / (1000.0 / por_nucleo[0]),
           usados[u]);
    printf("  Each core, alone, did %.1f M accesses/s; with %d active it does\n",
           1000.0 / por_nucleo[0], usados[u]);
    printf("  %.1f M -- %.0f%% of what it did alone. Bandwidth does not multiply\n",
           1000.0 / por_nucleo[u], 100.0 * por_nucleo[0] / por_nucleo[u]);
    printf("  per core: it is divided.\n\n");
    printf("  And the design consequence: sizing a data plane from the\n");
    printf("  measurement of ONE lcore overestimates the whole system. The number\n");
    printf("  that matters is the bottom row of this table, not the top one.\n");

    free(ordem);
    munmap(regiao, REGIAO_BYTES);
    return 0;
}
