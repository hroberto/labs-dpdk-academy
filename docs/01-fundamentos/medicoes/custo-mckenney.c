/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Fundamentos — reprodução da Tabela 3.1 de McKenney nesta máquina.
 *
 * A referência técnica aceita na área para custo de sincronização é o livro de
 * Paul E. McKenney, criador e mantenedor do RCU no kernel Linux:
 *
 *   "Is Parallel Programming Hard, And, If So, What Can You Do About It?"
 *   https://arxiv.org/abs/1701.00854   (também em kernel.org)
 *
 * A Tabela 3.1 dele mede, num AMD Opteron 844 de 1,8 GHz com QUATRO SOQUETES:
 *
 *     período de clock ............   0,6 ns
 *     CAS, best case ..........  37,9 ns
 *     lock, best case ........  65,6 ns
 *     falta de cache simples ...... 139,5 ns
 *     CAS com falta de cache ...... 306,0 ns
 *
 * A METODOLOGIA QUE ELE USA, E QUE ESTE PROGRAMA SEGUE
 *
 * O eixo de classificação não é "com ou sem disputa", e sim o ESTADO DA LINHA
 * DE CACHE no momento da operação:
 *
 *   melhor caso  - a linha já está no cache deste núcleo, porque foi ele o
 *                  último a tocá-la. Nenhuma transferência é necessária.
 *
 *   falta        - a linha está no cache de OUTRO núcleo e precisa migrar. É
 *                  o protocolo de coerência entrando em ação.
 *
 * Essa taxonomia é melhor que a minha original porque é uma propriedade do
 * hardware, não do software: independe de quantas threads existem ou de qual
 * primitivo se usa. É por isso que a tabela dele atravessa vinte anos e
 * continua comparável.
 *
 * ACRÉSCIMO DESTA MÁQUINA
 *
 * O sistema de McKenney tem quatro soquetes, e nele "outro núcleo" implica
 * atravessar soquetes. Esta CPU tem um soquete só, mas dois blocos de núcleos
 * (CCD) com L3 separado — então a categoria "falta" se desdobra em duas, e a
 * diferença entre elas é justamente o assunto da §4.3 do documento.
 */
#define _GNU_SOURCE
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "fixar_cpu.h"
#include "topologia.h"
#include "cpu_pause.h"
#include "clock_ns.h"
#include "statistics.h"

#define RODADAS 500000
#define AQUECIMENTO_MS 60

/* Cada variável disputada em sua própria linha, para que o efeito medido seja o
 * da coerência e não o de compartilhamento acidental. */
static _Alignas(64) atomic_int alvo;
static _Alignas(64) pthread_mutex_t trava = PTHREAD_MUTEX_INITIALIZER;
static _Alignas(64) atomic_int bastao;
static _Alignas(64) atomic_int encerrar;
static _Alignas(64) volatile long sumidouro;

static int cpu_local = 0;
static int cpu_remoto = 2; /* mesmo CCD por padrão; a main varia */


static void aquecer(void)
{
    const uint64_t ate = academy_now_ns() + (uint64_t)AQUECIMENTO_MS * 1000000ull;
    long a = 0;
    while (academy_now_ns() < ate)
        for (int i = 0; i < 10000; i++)
            a += i;
    sumidouro = a;
}

/* --------- Período de clock: referência para converter ns em ciclos -------- */
static double clock_period_ns(void)
{
    /* Cadeia de dependências de somas inteiras: uma por ciclo em regime. */
    const int n = 20000000;
    volatile long x = 0;
    const uint64_t t0 = academy_now_ns();
    for (int i = 0; i < n; i++)
        x = x + 1;
    const double r = (double)(academy_now_ns() - t0) / n;
    sumidouro = x;
    return r;
}

/* ---------------- Melhor caso: a linha já está no meu cache ---------------- */

static double cas_melhor_caso(void)
{
    const uint64_t t0 = academy_now_ns();
    for (int i = 0; i < RODADAS; i++) {
        int esperado = 0;
        atomic_compare_exchange_strong(&alvo, &esperado, 1);
        atomic_store(&alvo, 0);
    }
    return (double)(academy_now_ns() - t0) / RODADAS;
}

static double trava_melhor_caso(void)
{
    const uint64_t t0 = academy_now_ns();
    for (int i = 0; i < RODADAS; i++) {
        pthread_mutex_lock(&trava);
        pthread_mutex_unlock(&trava);
    }
    return (double)(academy_now_ns() - t0) / RODADAS;
}

/* ------------ Falta de cache: a linha está no cache de outro núcleo --------- */

/* A thread parceira devolve o bastão, forçando a linha a migrar a cada volta. */
static void *parceiro(void *_)
{
    (void)_;
    academy_fixar_cpu(cpu_remoto);
    while (!atomic_load_explicit(&encerrar, memory_order_relaxed)) {
        int esperado = 1;
        atomic_compare_exchange_weak_explicit(&bastao, &esperado, 0, memory_order_acq_rel,
                                              memory_order_relaxed);
    }
    return NULL;
}

/* Leitura simples de uma linha que outro núcleo acabou de escrever. */
static double falta_de_cache(void)
{
    pthread_t t;
    atomic_store(&encerrar, 0);
    atomic_store(&bastao, 0);
    if (pthread_create(&t, NULL, parceiro, NULL) != 0)
        {
            fprintf(stderr, "  AMOSTRA INVALIDA: pthread_create falhou (thread parceira)\n");
            /* NEGATIVO, E NAO ZERO. `statistics.h` declara a convencao tres
             * linhas acima de `collection_state`: "ou NaN em falha, nunca
             * zero". Zero e um tempo plausivel -- entra na mediana e some.
             * Negativo dispara `e.minimum < 0` e a coleta e recusada. */
            return -1.0;
        }
    const struct timespec d = {0, 5000000};
    nanosleep(&d, NULL);

    const uint64_t t0 = academy_now_ns();
    for (int i = 0; i < RODADAS; i++) {
        atomic_store_explicit(&bastao, 1, memory_order_release);
        while (atomic_load_explicit(&bastao, memory_order_acquire) != 0)
            academy_cpu_pause();
    }
    const double r = (double)(academy_now_ns() - t0) / RODADAS / 2.0;

    atomic_store(&encerrar, 1);
    pthread_join(t, NULL);
    return r;
}

/* CAS sobre uma linha que outro núcleo detém: soma coerência e operação atômica. */
static double cas_com_falta(void)
{
    pthread_t t;
    atomic_store(&encerrar, 0);
    atomic_store(&bastao, 0);
    if (pthread_create(&t, NULL, parceiro, NULL) != 0)
        {
            fprintf(stderr, "  AMOSTRA INVALIDA: pthread_create falhou (thread parceira)\n");
            /* NEGATIVO, E NAO ZERO. `statistics.h` declara a convencao tres
             * linhas acima de `collection_state`: "ou NaN em falha, nunca
             * zero". Zero e um tempo plausivel -- entra na mediana e some.
             * Negativo dispara `e.minimum < 0` e a coleta e recusada. */
            return -1.0;
        }
    const struct timespec d = {0, 5000000};
    nanosleep(&d, NULL);

    const uint64_t t0 = academy_now_ns();
    for (int i = 0; i < RODADAS; i++) {
        int esperado = 0;
        atomic_compare_exchange_strong(&bastao, &esperado, 1);
        while (atomic_load_explicit(&bastao, memory_order_acquire) != 0)
            academy_cpu_pause();
    }
    const double r = (double)(academy_now_ns() - t0) / RODADAS / 2.0;

    atomic_store(&encerrar, 1);
    pthread_join(t, NULL);
    return r;
}

/* A lista de CPUs do domínio de L3 do núcleo local, ou string vazia. */
static void dominio_do_local(char *saida, size_t tam)
{
    char caminho[128];
    saida[0] = '\0';
    snprintf(caminho, sizeof(caminho),
             "/sys/devices/system/cpu/cpu%d/cache/index3/shared_cpu_list", cpu_local);
    FILE *f = fopen(caminho, "r");
    if (f == NULL)
        return;
    if (fgets(saida, (int)tam, f) != NULL)
        saida[strcspn(saida, "\n")] = '\0';
    fclose(f);
}

/* Descobre o primeiro núcleo de um domínio de L3 diferente do local. */
static int nucleo_de_outro_dominio(void)
{
    char meu[256] = {0};
    for (int cpu = 0; cpu < 512; cpu++) {
        char caminho[128], buf[256];
        snprintf(caminho, sizeof(caminho),
                 "/sys/devices/system/cpu/cpu%d/cache/index3/shared_cpu_list", cpu);
        FILE *f = fopen(caminho, "r");
        if (f == NULL)
            continue;
        if (fgets(buf, sizeof(buf), f) != NULL) {
            buf[strcspn(buf, "\n")] = '\0';
            if (cpu == cpu_local)
                snprintf(meu, sizeof(meu), "%s", buf);
            else if (meu[0] != '\0' && strcmp(meu, buf) != 0) {
                fclose(f);
                return cpu;
            }
        }
        fclose(f);
    }
    return -1;
}

int main(void)
{
    print_provenance("custo-mckenney");
    academy_fixar_cpu(cpu_local);
    aquecer();

    const struct statistics clk = collect_or_fail(clock_period_ns, 9);

    printf("McKenney's Table 3.1, reproduced on this machine\n");
    printf("(%d samples per measurement; times in ns)\n\n", DEFAULT_SAMPLES);
    printf("  Reference: McKenney, \"Is Parallel Programming Hard...\", Table 3.1,\n");
    printf("  measured on an AMD Opteron 844, 1.8 GHz, 4 sockets.\n");
    printf("  Here: 1 socket, 2 L3 domains. Measured clock period: %.3f ns.\n\n",
           clk.median);

    const double T = clk.median;

    printf("BEST CASE - the cache line is already on this core\n\n");
    print_header_cycles();
    print_row_cycles("CAS, best case", collect_or_fail(cas_melhor_caso, DEFAULT_SAMPLES), T);
    print_row_cycles("lock, best case", collect_or_fail(trava_melhor_caso, DEFAULT_SAMPLES), T);

    printf("\nCACHE MISS - the line is on another core and has to migrate\n\n");
    print_header_cycles();

    /* O NUMERO 2 ERA CONSTANTE, e o rotulo da linha afirma "same L3 domain".
     *
     * Este mesmo arquivo ja lia o sysfs para achar o OUTRO dominio, logo
     * abaixo; para o MESMO dominio ele chutava. Nesta maquina o chute acerta
     * -- CCD0 e `0-5,12-17` --, e noutra topologia a linha rotulada "same L3
     * domain" mediria travessia entre dominios, que e exatamente a linha
     * seguinte do programa. */
    char meu_dominio[256];
    dominio_do_local(meu_dominio, sizeof(meu_dominio));
    cpu_remoto = meu_dominio[0] != '\0'
               ? academy_parceiro_no_dominio(cpu_local, meu_dominio, 2)
               : -1;
    if (cpu_remoto < 0) {
        printf("\n  (nao ha segunda CPU em nucleo fisico distinto no dominio de\n"
               "   L3 da CPU %d: sem categoria 'same L3 domain')\n", cpu_local);
        return 77;   /* PULADO: a maquina nao oferece a condicao */
    }
    print_row_cycles("plain miss, same L3 domain", collect_or_fail(falta_de_cache, DEFAULT_SAMPLES), T);
    print_row_cycles("CAS with miss, same L3 domain", collect_or_fail(cas_com_falta, DEFAULT_SAMPLES), T);

    const int outro = nucleo_de_outro_dominio();
    if (outro < 0) {
        printf("\n  (CPU with a single L3 domain: no 'other domain' category)\n");
        /* CÓDIGO 77 = PULADO, e não sucesso.
         *
         * Sair com 0 aqui fazia o Meson reportar OK sem que nada tivesse sido medido —
         * um falso verde. E não era caso raro: no runner do CI o requisito nunca
         * existiu, então este teste jamais verificou coisa alguma e sempre apareceu
         * verde. O Meson trata 77 como SKIP, conta separado e não falha a suíte. */
        return 77;
    }
    cpu_remoto = outro;
    print_row_cycles("plain miss, OTHER L3 domain", collect_or_fail(falta_de_cache, DEFAULT_SAMPLES), T);
    print_row_cycles("CAS with miss, OTHER L3 domain", collect_or_fail(cas_com_falta, DEFAULT_SAMPLES), T);

    printf("\n  For comparison, McKenney's values in CYCLES (0.6 ns period):\n");
    printf("    CAS best case    63 | lock best case   109\n");
    printf("    cache miss      232 | CAS with miss     510\n");

    printf("\n  McKenney's system has 4 sockets; there 'another core' can\n");
    printf("  mean another socket. Here the equivalent distinction is between the\n");
    printf("  two L3 domains -- the last two rows against the two\n");
    printf("  before them. That is the SOSP 2013 conclusion: the scalability of\n");
    printf("  synchronisation is, above all, a property of the hardware.\n");
    return 0;
}
