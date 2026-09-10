/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Nível 4 — quanto custa conseguir um objeto.
 *
 * O tópico prático de mempool afirma que `malloc()` "pode tomar dezenas de
 * nanossegundos" e que emprestar do pool custa "poucos nanossegundos". Este
 * programa mede as duas coisas na mesma máquina, com a mesma metodologia, para
 * que a afirmação deixe de ser folclore.
 *
 * O QUE É COMPARADO
 *
 * Duas tabelas, e a segunda é o resultado principal:
 *
 *   a) UM OBJETO POR VEZ — malloc/free contra rte_mempool_get/put, este último
 *      com e sem cache por lcore. A linha sem cache existe para isolar quanto
 *      do ganho vem do cache e quanto vem do resto do desenho.
 *
 *   b) EM LOTE, varrendo 1, 8, 32 e 128 — malloc/free contra
 *      rte_mempool_get_bulk/put_bulk. É onde se vê que o lote barateia um lado
 *      e encarece o outro, o que a comparação objeto-a-objeto esconde.
 *
 * UMA ARMADILHA DE MEDIÇÃO QUE MUDA O RESULTADO
 *
 * A glibc tem um caminho rápido para processo de UMA thread: enquanto
 * `__libc_single_threaded` for verdadeiro, malloc evita o trabalho de
 * sincronização. Medir malloc num programa mono-thread produz um número que não
 * existe em nenhum servidor real — e, pior, favorece justamente o lado que se
 * quer comparar. Este programa mantém uma thread de ruído viva do início ao fim
 * exatamente por isso, seguindo o padrão que os fundamentos adotaram depois de
 * descartar uma medição inválida pelo mesmo motivo.
 */
#define _GNU_SOURCE
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

#include <rte_eal.h>
#include <rte_errno.h>
#include <rte_lcore.h>
#include <rte_mempool.h>

#include "sizing.h"
#include "statistics.h"

#define OBJECTS 4095u   /* 2^12 - 1: tamanho ótimo em uso de memória */
#define OBJECT_SIZE 128u /* estado por pacote, sem o payload */

/* O cache NÃO é uma constante escolhida a olho. A primeira versão deste
 * programa usava 256, que passa nos dois limites documentados e ainda assim
 * deixa 4095 % 256 = 255 objetos que o cache nunca alcança — a regra
 * "n modulo cache_size == 0" da documentação de rte_mempool_create, que falha
 * em silêncio. O valor agora é derivado, e o programa imprime a verificação. */
#define ITERATIONS 200000
#define BURST 32u
#define BURST_MAX 128u

static struct rte_mempool *pool_cache;
static struct rte_mempool *pool_sem_cache;

/* A thread de ruído não faz trabalho útil: existe só para que a glibc não
 * escolha o caminho de processo mono-thread. Ver o comentário de abertura. */
static _Alignas(64) atomic_int parar_ruido = 0;

/* CPU da thread de ruído. Precisa ser um NÚCLEO FÍSICO diferente do lcore que
 * mede: deixá-la solta faz o escalonador colocá-la sobre a mesma CPU de vez em
 * quando, e a medição sai bimodal — foi o que aconteceu na primeira versão
 * deste programa (p25 de 10,5 ns contra p75 de 25,4 ns na mesma medição).
 * Também não pode ser o irmão de SMT: os fundamentos mediram +174% de custo
 * nesse caso. Ajuste com DPDK_ACADEMY_CPU_RUIDO se a sua topologia diferir. */
#define CPU_RUIDO_PADRAO 2

static void *ruido(void *arg)
{
    const int cpu = *(const int *)arg;
    cpu_set_t conjunto;
    CPU_ZERO(&conjunto);
    CPU_SET(cpu, &conjunto);
    pthread_setaffinity_np(pthread_self(), sizeof(conjunto), &conjunto);

    while (!atomic_load_explicit(&parar_ruido, memory_order_relaxed))
        ;
    return NULL;
}

/* Frequência corrente do núcleo que mede, em GHz, ou 0 se o sistema não a
 * expuser. Não é firula: os valores absolutos desta tabela variam com ela, e
 * publicar o número sem publicar a frequência convida a comparação inválida. */
static double freq_ghz(unsigned cpu)
{
    char caminho[128];
    snprintf(caminho, sizeof(caminho),
             "/sys/devices/system/cpu/cpu%u/cpufreq/scaling_cur_freq", cpu);
    FILE *f = fopen(caminho, "r");
    if (f == NULL)
        return 0.0;
    long khz = 0;
    if (fscanf(f, "%ld", &khz) != 1)
        khz = 0;
    fclose(f);
    return (double)khz / 1e6;
}

static double now_ns(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec * 1e9 + (double)t.tv_nsec;
}

/* Barreira contra o otimizador: sem ela, o compilador percebe que o ponteiro
 * não é usado e remove o par alocar/liberar inteiro, produzindo 0,000 ns. */
static inline void consume_ptr(void *p)
{
    __asm__ __volatile__("" : : "r"(p) : "memory");
}

static double m_malloc_unitario(void)
{
    const double t0 = now_ns();
    for (int i = 0; i < ITERATIONS; i++) {
        void *p = malloc(OBJECT_SIZE);
        consume_ptr(p);
        free(p);
    }
    return (now_ns() - t0) / ITERATIONS;
}

/* Lote corrente da varredura. Global porque collect() recebe função sem
 * parâmetro — o preço de reusar a metodologia dos demais programas. */
static unsigned current_burst = BURST;

static double m_malloc_lote(void)
{
    void *v[BURST_MAX];
    const int rounds = ITERATIONS / (int)current_burst;
    const double t0 = now_ns();
    for (int i = 0; i < rounds; i++) {
        for (unsigned j = 0; j < current_burst; j++) {
            v[j] = malloc(OBJECT_SIZE);
            consume_ptr(v[j]);
        }
        for (unsigned j = 0; j < current_burst; j++)
            free(v[j]);
    }
    return (now_ns() - t0) / (rounds * (int)current_burst);
}

static double measure_pool_single(struct rte_mempool *mp)
{
    const double t0 = now_ns();
    for (int i = 0; i < ITERATIONS; i++) {
        void *p = NULL;
        if (rte_mempool_get(mp, &p) < 0)
            return -1.0;
        consume_ptr(p);
        rte_mempool_put(mp, p);
    }
    return (now_ns() - t0) / ITERATIONS;
}

static double m_pool_com_cache(void)
{
    return measure_pool_single(pool_cache);
}

static double m_pool_sem_cache(void)
{
    return measure_pool_single(pool_sem_cache);
}

static double m_pool_bulk(void)
{
    void *v[BURST_MAX];
    const int rounds = ITERATIONS / (int)current_burst;
    const double t0 = now_ns();
    for (int i = 0; i < rounds; i++) {
        if (rte_mempool_get_bulk(pool_cache, v, current_burst) < 0)
            return -1.0;
        for (unsigned j = 0; j < current_burst; j++)
            consume_ptr(v[j]);
        rte_mempool_put_bulk(pool_cache, v, current_burst);
    }
    return (now_ns() - t0) / (rounds * (int)current_burst);
}

int main(int argc, char **argv)
{
    if (rte_eal_init(argc, argv) < 0) {
        fprintf(stderr, "custo-alocacao: EAL nao inicializou: %s\n", rte_strerror(rte_errno));
        return 2;
    }

    const uint32_t cache_lcore = dim_recommended_cache(OBJECTS, RTE_MEMPOOL_CACHE_MAX_SIZE);
    pool_cache = rte_mempool_create("pool_com_cache", OBJECTS, OBJECT_SIZE, cache_lcore, 0, NULL,
                                    NULL, NULL, NULL, (int)rte_socket_id(), 0);
    pool_sem_cache = rte_mempool_create("pool_sem_cache", OBJECTS, OBJECT_SIZE, 0, 0, NULL, NULL,
                                        NULL, NULL, (int)rte_socket_id(), 0);
    if (pool_cache == NULL || pool_sem_cache == NULL) {
        fprintf(stderr, "custo-alocacao: rte_mempool_create falhou: %s\n",
                rte_strerror(rte_errno));
        rte_eal_cleanup();
        return 1;
    }

    /* CPU da thread de ruído: fixa, e distinta do lcore que mede. */
    const char *e = getenv("DPDK_ACADEMY_CPU_RUIDO");
    int cpu_ruido = e != NULL ? atoi(e) : CPU_RUIDO_PADRAO;
    if (cpu_ruido == (int)rte_lcore_id())
        cpu_ruido = (cpu_ruido + 1) % (int)sysconf(_SC_NPROCESSORS_ONLN);

    pthread_t t_ruido;
    if (pthread_create(&t_ruido, NULL, ruido, &cpu_ruido) != 0) {
        fprintf(stderr, "custo-alocacao: nao foi possivel criar a thread de ruido\n");
        rte_eal_cleanup();
        return 1;
    }

    /* AQUECIMENTO, e não é zelo excessivo.
     *
     * A primeira execução de cada caminho paga falta de página no binário e nas
     * bibliotecas, preditor de desvio frio e rampa de frequência do
     * processador. Sem descartá-la, a PRIMEIRA execução do programa devolve
     * números sistematicamente piores e mais dispersos que as seguintes —
     * medimos 2,78 ns contra 2,19 ns no malloc, e dispersão de 23% contra 1,5%
     * na linha sem cache. Quem rodasse uma vez e comparasse com o documento
     * encontraria divergência sem causa aparente.
     *
     * Uma passagem por cada medição, jogada fora, resolve. */
    current_burst = BURST;
    (void)m_malloc_unitario();
    (void)m_malloc_lote();
    (void)m_pool_com_cache();
    (void)m_pool_sem_cache();
    (void)m_pool_bulk();

    const int n = samples(DEFAULT_SAMPLES_FIXED);

    printf("\n== Quanto custa conseguir um objeto ==\n\n");
    printf("  objeto de %u bytes; pool de %u objetos\n", OBJECT_SIZE, OBJECTS);
    char warning[160], naive_warning[160];
    printf("  cache por lcore ........ %u objetos (derivado, nao escolhido a olho)\n",
           cache_lcore);
    printf("    escolhido ............ %s\n",
           dim_describe(dim_check(OBJECTS, cache_lcore, RTE_MEMPOOL_CACHE_MAX_SIZE), warning,
                         sizeof(warning)));
    printf("    o obvio (256) seria .. %s -> %u objetos presos\n",
           dim_describe(dim_check(OBJECTS, 256, RTE_MEMPOOL_CACHE_MAX_SIZE), naive_warning,
                         sizeof(naive_warning)),
           dim_leftover_objects(OBJECTS, 256));
    printf("  amostras: %d, cada uma com %d operacoes\n", n, ITERATIONS);
    printf("  medindo no lcore %u; thread de ruido fixada na CPU %d\n", rte_lcore_id(),
           cpu_ruido);
    printf("  (a glibc tem caminho rapido para processo mono-thread; sem a thread\n");
    printf("   de ruido o malloc mediria um custo que nao existe em servidor real)\n\n");

    printf("  --- um objeto por vez, em NANOSSEGUNDOS POR OBJETO ---\n\n");
    const double f0 = freq_ghz(rte_lcore_id());
    print_header();
    const struct statistics e_malloc = collect(m_malloc_unitario, n);
    const struct statistics e_cache = collect(m_pool_com_cache, n);
    const struct statistics e_sem = collect(m_pool_sem_cache, n);
    print_row("malloc/free", e_malloc);
    print_row("mempool get/put, com cache", e_cache);
    print_row("mempool get/put, SEM cache", e_sem);
    const double f1 = freq_ghz(rte_lcore_id());

    /* AS RAZOES SAO O RESULTADO; os nanossegundos sao circunstancia.
     *
     * Sem fixar a frequencia do processador, os valores absolutos desta tabela
     * mudam entre execucoes: medimos o mesmo programa dar 2,19 ns e 2,77 ns
     * para o malloc, conforme o turbo engatasse ou nao. As RAZOES, no entanto,
     * ficaram identicas (2,23x nas duas). E por isso que este modulo afirma
     * "duas vezes mais rapido" e nao "0,98 nanossegundos". */
    printf("\n  frequencia do nucleo %u durante a medicao: %.2f -> %.2f GHz\n",
           rte_lcore_id(), f0, f1);
    printf("  razoes, que NAO dependem da frequencia:\n");
    printf("    mempool com cache e %.2fx mais rapido que malloc\n",
           e_cache.median > 0 ? e_malloc.median / e_cache.median : 0.0);
    printf("    o cache por lcore vale %.1fx (com cache contra sem cache)\n",
           e_cache.median > 0 ? e_sem.median / e_cache.median : 0.0);
    printf("    sem o cache, o mempool fica %.1fx mais LENTO que o malloc\n",
           e_malloc.median > 0 ? e_sem.median / e_malloc.median : 0.0);

    printf("\n  --- em LOTE, ns por objeto: os dois lados variam em sentidos opostos ---\n\n");
    printf("  %-10s %14s %14s %10s\n", "lote", "malloc/free", "mempool bulk", "razao");
    printf("  %-10s %14s %14s %10s\n", "-----", "-----------", "------------", "-----");
    static const unsigned bursts[] = {1, 8, 32, 128};
    for (size_t i = 0; i < sizeof(bursts) / sizeof(bursts[0]); i++) {
        current_burst = bursts[i];
        const struct statistics m = collect(m_malloc_lote, n);
        const struct statistics p = collect(m_pool_bulk, n);
        printf("  %-10u %11.2f ns %11.3f ns %9.1fx\n", bursts[i], m.median, p.median,
               p.median > 0 ? m.median / p.median : 0.0);
    }

    printf("\n  Leitura:\n");
    printf("    O pool nao e magico: troca alocacao dinamica por indice em vetor\n");
    printf("    pre-alocado, e o cache por lcore evita ate a operacao atomica do\n");
    printf("    anel comum -- e o que a linha SEM cache mede.\n\n");
    printf("    O sentido das duas colunas de lote e o resultado principal: pedir\n");
    printf("    mais objetos de uma vez BARATEIA cada objeto no mempool e ENCARECE\n");
    printf("    no malloc. O motivo do lado do malloc esta dentro do alocador da\n");
    printf("    glibc e este projeto nao o investiga; o que importa aqui e que a\n");
    printf("    estrategia de lote, central no plano de dados, so compensa de um\n");
    printf("    dos lados.\n\n");
    printf("    Nenhum destes numeros inclui falta de pagina: o pool ja esta quente.\n");
    printf("    Em producao, a primeira passagem sobre a memoria e mais cara.\n\n");

    atomic_store_explicit(&parar_ruido, 1, memory_order_relaxed);
    pthread_join(t_ruido, NULL);

    rte_mempool_free(pool_cache);
    rte_mempool_free(pool_sem_cache);
    rte_eal_cleanup();
    return 0;
}
