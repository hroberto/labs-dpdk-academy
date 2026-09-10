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
 *     CAS em melhor caso ..........  37,9 ns
 *     trava em melhor caso ........  65,6 ns
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

static uint64_t now_ns(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000000000ull + t.tv_nsec;
}

static void fixar(int cpu)
{
    cpu_set_t c;
    CPU_ZERO(&c);
    CPU_SET(cpu, &c);
    pthread_setaffinity_np(pthread_self(), sizeof(c), &c);
}

static void aquecer(void)
{
    const uint64_t ate = now_ns() + (uint64_t)AQUECIMENTO_MS * 1000000ull;
    long a = 0;
    while (now_ns() < ate)
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
    const uint64_t t0 = now_ns();
    for (int i = 0; i < n; i++)
        x = x + 1;
    const double r = (double)(now_ns() - t0) / n;
    sumidouro = x;
    return r;
}

/* ---------------- Melhor caso: a linha já está no meu cache ---------------- */

static double cas_melhor_caso(void)
{
    const uint64_t t0 = now_ns();
    for (int i = 0; i < RODADAS; i++) {
        int esperado = 0;
        atomic_compare_exchange_strong(&alvo, &esperado, 1);
        atomic_store(&alvo, 0);
    }
    return (double)(now_ns() - t0) / RODADAS;
}

static double trava_melhor_caso(void)
{
    const uint64_t t0 = now_ns();
    for (int i = 0; i < RODADAS; i++) {
        pthread_mutex_lock(&trava);
        pthread_mutex_unlock(&trava);
    }
    return (double)(now_ns() - t0) / RODADAS;
}

/* ------------ Falta de cache: a linha está no cache de outro núcleo --------- */

/* A thread parceira devolve o bastão, forçando a linha a migrar a cada volta. */
static void *parceiro(void *_)
{
    (void)_;
    fixar(cpu_remoto);
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
        return 0.0;
    const struct timespec d = {0, 5000000};
    nanosleep(&d, NULL);

    const uint64_t t0 = now_ns();
    for (int i = 0; i < RODADAS; i++) {
        atomic_store_explicit(&bastao, 1, memory_order_release);
        while (atomic_load_explicit(&bastao, memory_order_acquire) != 0)
            __builtin_ia32_pause();
    }
    const double r = (double)(now_ns() - t0) / RODADAS / 2.0;

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
        return 0.0;
    const struct timespec d = {0, 5000000};
    nanosleep(&d, NULL);

    const uint64_t t0 = now_ns();
    for (int i = 0; i < RODADAS; i++) {
        int esperado = 0;
        atomic_compare_exchange_strong(&bastao, &esperado, 1);
        while (atomic_load_explicit(&bastao, memory_order_acquire) != 0)
            __builtin_ia32_pause();
    }
    const double r = (double)(now_ns() - t0) / RODADAS / 2.0;

    atomic_store(&encerrar, 1);
    pthread_join(t, NULL);
    return r;
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
    fixar(cpu_local);
    aquecer();

    const struct statistics clk = collect(clock_period_ns, 9);

    printf("Tabela 3.1 de McKenney, reproduzida nesta maquina\n");
    printf("(%d amostras por medicao; tempos em ns)\n\n", DEFAULT_SAMPLES);
    printf("  Referencia: McKenney, \"Is Parallel Programming Hard...\", Tabela 3.1,\n");
    printf("  medida em AMD Opteron 844, 1,8 GHz, 4 soquetes.\n");
    printf("  Aqui: 1 soquete, 2 dominios de L3. Periodo de clock medido: %.3f ns.\n\n",
           clk.median);

    const double T = clk.median;

    printf("MELHOR CASO - a linha de cache ja esta neste nucleo\n\n");
    print_header_cycles();
    print_row_cycles("CAS em melhor caso", collect(cas_melhor_caso, DEFAULT_SAMPLES), T);
    print_row_cycles("trava em melhor caso", collect(trava_melhor_caso, DEFAULT_SAMPLES), T);

    printf("\nFALTA DE CACHE - a linha esta em outro nucleo e precisa migrar\n\n");
    print_header_cycles();

    cpu_remoto = 2;
    print_row_cycles("falta simples, mesmo dominio L3", collect(falta_de_cache, DEFAULT_SAMPLES), T);
    print_row_cycles("CAS com falta, mesmo dominio L3", collect(cas_com_falta, DEFAULT_SAMPLES), T);

    const int outro = nucleo_de_outro_dominio();
    if (outro < 0) {
        printf("\n  (CPU com um unico dominio de L3: sem categoria 'outro dominio')\n");
        /* CÓDIGO 77 = PULADO, e não sucesso.
         *
         * Sair com 0 aqui fazia o Meson reportar OK sem que nada tivesse sido medido —
         * um falso verde. E não era caso raro: no runner do CI o requisito nunca
         * existiu, então este teste jamais verificou coisa alguma e sempre apareceu
         * verde. O Meson trata 77 como SKIP, conta separado e não falha a suíte. */
        return 77;
    }
    cpu_remoto = outro;
    print_row_cycles("falta simples, OUTRO dominio L3", collect(falta_de_cache, DEFAULT_SAMPLES), T);
    print_row_cycles("CAS com falta, OUTRO dominio L3", collect(cas_com_falta, DEFAULT_SAMPLES), T);

    printf("\n  Para comparar, os valores de McKenney em CICLOS (periodo 0,6 ns):\n");
    printf("    CAS melhor caso  63 | trava melhor caso 109\n");
    printf("    falta de cache  232 | CAS com falta     510\n");

    printf("\n  O sistema de McKenney tem 4 soquetes; nele 'outro nucleo' pode\n");
    printf("  significar outro soquete. Aqui a distincao equivalente e entre os\n");
    printf("  dois dominios de L3 -- as duas ultimas linhas contra as duas\n");
    printf("  anteriores. A conclusao do SOSP 2013 e essa: a escalabilidade da\n");
    printf("  sincronizacao e, sobretudo, propriedade do hardware.\n");
    return 0;
}
