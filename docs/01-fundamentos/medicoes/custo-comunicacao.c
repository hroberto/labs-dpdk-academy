/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Fundamentos — quanto custa dois núcleos trocarem um dado.
 *
 * Mede o tempo de uma linha de cache viajar do cache de um núcleo para o de
 * outro, com um ping-pong: a thread A escreve, a thread B percebe e responde.
 * O tempo de ida e volta dividido por dois é a latência da transferência.
 *
 * O ponto do exercício é comparar PARES DE NÚCLEOS DIFERENTES. Em processadores
 * modernos os núcleos não são equidistantes: os que compartilham o mesmo cache
 * L3 conversam rápido; os que estão em blocos distintos (CCX/CCD na AMD,
 * clusters na Intel) precisam atravessar a interconexão interna do chip.
 *
 * Isso importa diretamente para plano de dados: um rte_ring entre produtor e
 * consumidor faz exatamente esta viagem a cada lote. Colocar os dois lcores no
 * bloco errado pode custar mais que o orçamento inteiro de um pacote.
 *
 * Os pares testados são derivados de /sys/.../cache/index3/shared_cpu_list, que
 * informa quais CPUs compartilham cada L3 — portanto o programa se adapta à
 * máquina em que roda.
 *
 * METODOLOGIA: igual à dos demais programas desta pasta. Ver statistics.h.
 *
 * O programa também mede CONTENÇÃO DE SMT: quando duas threads rodam nos dois
 * fluxos do MESMO núcleo físico, elas compartilham as unidades de execução, a
 * L1 e o preditor de saltos. Um laço de polling é justamente o pior caso — ele
 * não bloqueia nunca, então disputa essas unidades o tempo todo. Saber quanto
 * isso custa é o que separa "tenho 24 CPUs" de "tenho 12 núcleos".
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

#define RODADAS 200000
#define AMOSTRAS_C2C_FIXO 15
#define AMOSTRAS_C2C samples(AMOSTRAS_C2C_FIXO)

/* collect() recebe ponteiro sem argumentos; o par vai por variáveis. */
static int par_a, par_b;
#define BUDGET_10GBE_NS 67.2
#define MAX_DOMINIOS 16

/* A linha de cache disputada, isolada para não sofrer falso compartilhamento. */
static _Alignas(64) atomic_int bola;
static int cpu_a, cpu_b;

static uint64_t now_ns(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000000000ull + t.tv_nsec;
}

static int fixar(int cpu)
{
    cpu_set_t conjunto;
    CPU_ZERO(&conjunto);
    CPU_SET(cpu, &conjunto);
    return pthread_setaffinity_np(pthread_self(), sizeof(conjunto), &conjunto);
}

static void *rebatedor(void *ignorado)
{
    (void)ignorado;
    fixar(cpu_b);
    for (int i = 0; i < RODADAS; i++) {
        while (atomic_load_explicit(&bola, memory_order_acquire) != 1)
            __builtin_ia32_pause();
        atomic_store_explicit(&bola, 0, memory_order_release);
    }
    return NULL;
}

static double medir(int a, int b)
{
    cpu_a = a;
    cpu_b = b;
    atomic_store(&bola, 0);

    pthread_t t;
    if (pthread_create(&t, NULL, rebatedor, NULL) != 0)
        return -1.0;
    fixar(cpu_a);

    const struct timespec espera = {0, 1000000};
    nanosleep(&espera, NULL); /* deixa o rebatedor chegar ao laço */

    const uint64_t t0 = now_ns();
    for (int i = 0; i < RODADAS; i++) {
        atomic_store_explicit(&bola, 1, memory_order_release);
        while (atomic_load_explicit(&bola, memory_order_acquire) != 0)
            __builtin_ia32_pause();
    }
    const uint64_t dt = now_ns() - t0;
    pthread_join(t, NULL);

    return (double)dt / RODADAS / 2.0; /* ida e volta -> uma travessia */
}

/* Lê os domínios de L3 do sysfs: cada linha distinta é um bloco de núcleos. */
static int ler_dominios(char lista[MAX_DOMINIOS][256])
{
    int n = 0;
    for (int cpu = 0; cpu < 512 && n < MAX_DOMINIOS; cpu++) {
        char caminho[128];
        snprintf(caminho, sizeof(caminho),
                 "/sys/devices/system/cpu/cpu%d/cache/index3/shared_cpu_list", cpu);
        FILE *f = fopen(caminho, "r");
        if (f == NULL)
            continue;
        char buf[256];
        if (fgets(buf, sizeof(buf), f) != NULL) {
            buf[strcspn(buf, "\n")] = '\0';
            int novo = 1;
            for (int i = 0; i < n; i++)
                if (strcmp(lista[i], buf) == 0)
                    novo = 0;
            if (novo)
                snprintf(lista[n++], 256, "%s", buf);
        }
        fclose(f);
    }
    return n;
}

/* ---------------- Contenção entre fluxos SMT do mesmo núcleo ---------------- */

/* Trabalho puramente de ALU, sem memória: isola a disputa por unidades de
 * execução, que é o mecanismo do SMT.
 *
 * Quatro acumuladores INDEPENDENTES de propósito: cadeias independentes têm
 * paralelismo de instruções alto e saturam as ALUs, que é a condição em que a
 * disputa por SMT aparece. Uma cadeia serial deixaria unidades ociosas, e os
 * dois fluxos se intercalariam sem competir — medindo o caso favorável em vez
 * do caso que importa.
 *
 * A barreira de otimização é obrigatória: sem ela o compilador reduz o laço a
 * uma fórmula fechada e a medição devolve zero — erro fácil de cometer e de não
 * perceber, porque o programa continua rodando e imprimindo. */
#define TRABALHO_ALU(n, a, b, c, d)                                                                \
    do {                                                                                           \
        for (int i_ = 0; i_ < (n); i_++) {                                                         \
            (a) += i_ * 3 + 1;                                                                     \
            (b) ^= i_ * 5 + 7;                                                                     \
            (c) += i_ | 1;                                                                         \
            (d) ^= i_ * 11 + 3;                                                                    \
            __asm__ __volatile__("" : "+r"(a), "+r"(b), "+r"(c), "+r"(d));                         \
        }                                                                                          \
    } while (0)
static _Alignas(64) atomic_int parar_vizinho;
static _Alignas(64) volatile long soma_vizinho;
static int cpu_vizinho = -1;

static void *vizinho_ocupado(void *_)
{
    (void)_;
    if (cpu_vizinho >= 0)
        fixar(cpu_vizinho);
    long a = 0, b = 0, c = 0, d = 0;
    while (!atomic_load_explicit(&parar_vizinho, memory_order_relaxed))
        TRABALHO_ALU(1000, a, b, c, d);
    soma_vizinho = a + b + c + d;
    return NULL;
}

/* Mede o próprio laço de trabalho, com ou sem vizinho competindo. */
static double laco_de_trabalho(void)
{
    const int n = 20000000;
    long a = 0, b = 0, c = 0, d = 0;
    const uint64_t t0 = now_ns();
    TRABALHO_ALU(n, a, b, c, d);
    const double r = (double)(now_ns() - t0) / n;
    soma_vizinho += a + b + c + d;
    return r;
}

static double com_vizinho(void)
{
    pthread_t t;
    atomic_store(&parar_vizinho, 0);
    if (pthread_create(&t, NULL, vizinho_ocupado, NULL) != 0)
        return 0.0;
    const struct timespec d = {0, 20000000};
    nanosleep(&d, NULL);
    const double r = laco_de_trabalho();
    atomic_store(&parar_vizinho, 1);
    pthread_join(t, NULL);
    return r;
}

/* Primeiro CPU listado num intervalo como "0-5,12-17". */
static int primeiro_cpu(const char *lista)
{
    return (int)strtol(lista, NULL, 10);
}

static double measure_pair(void)
{
    return medir(par_a, par_b);
}

int main(void)
{
    char dominios[MAX_DOMINIOS][256];
    const int n = ler_dominios(dominios);

    printf("Custo de dois nucleos trocarem uma linha de cache\n\n");
    if (n <= 0) {
        printf("  Nao foi possivel ler os dominios de L3 do sysfs.\n");
        /* CÓDIGO 77 = PULADO, e não sucesso.
         *
         * Sair com 0 aqui fazia o Meson reportar OK sem que nada tivesse sido medido —
         * um falso verde. E não era caso raro: no runner do CI o requisito nunca
         * existiu, então este teste jamais verificou coisa alguma e sempre apareceu
         * verde. O Meson trata 77 como SKIP, conta separado e não falha a suíte. */
        return 77;
    }

    printf("  Dominios de cache L3 nesta maquina: %d\n", n);
    for (int i = 0; i < n; i++)
        printf("    dominio %d: CPUs %s\n", i, dominios[i]);
    printf("\n");

    const int a = primeiro_cpu(dominios[0]);
    par_a = a;
    par_b = a + 2;
    const struct statistics e_dentro = collect(measure_pair, AMOSTRAS_C2C);
    const double dentro = e_dentro.median;

    print_header();
    char rot[64];
    snprintf(rot, sizeof(rot), "dentro do dominio 0 (cpu %d <-> %d)", par_a, par_b);
    print_row(rot, e_dentro);

    if (n < 2) {
        printf("\n  Esta maquina tem um unico dominio de L3: nao ha par\n");
        printf("  'distante' para comparar. Em processadores com varios blocos\n");
        printf("  (Ryzen 9/Threadripper/EPYC, Xeon com clusters) a diferenca aparece.\n");
        /* CÓDIGO 77 = PULADO, e não sucesso.
         *
         * Sair com 0 aqui fazia o Meson reportar OK sem que nada tivesse sido medido —
         * um falso verde. E não era caso raro: no runner do CI o requisito nunca
         * existiu, então este teste jamais verificou coisa alguma e sempre apareceu
         * verde. O Meson trata 77 como SKIP, conta separado e não falha a suíte. */
        return 77;
    }

    const int b = primeiro_cpu(dominios[1]);
    par_a = a;
    par_b = b;
    const struct statistics e_entre = collect(measure_pair, AMOSTRAS_C2C);
    const double entre = e_entre.median;
    snprintf(rot, sizeof(rot), "ENTRE dominios (cpu %d <-> %d)", par_a, par_b);
    print_row(rot, e_entre);
    /* ---- Contenção de SMT ---- */
    printf("\n  Contencao entre fluxos SMT (mesmo nucleo fisico)\n\n");
    print_header();

    cpu_vizinho = -1;
    const struct statistics e_sozinho = collect(laco_de_trabalho, AMOSTRAS_C2C);
    print_row("laco sozinho no nucleo", e_sozinho);

    /* Irmão SMT do cpu 0, lido do sysfs. */
    int irmao = -1;
    FILE *f = fopen("/sys/devices/system/cpu/cpu0/topology/thread_siblings_list", "r");
    if (f != NULL) {
        char buf[64];
        if (fgets(buf, sizeof(buf), f) != NULL) {
            const char *v = strpbrk(buf, ",-");
            if (v != NULL)
                irmao = (int)strtol(v + 1, NULL, 10);
        }
        fclose(f);
    }

    if (irmao > 0) {
        cpu_vizinho = irmao;
        char rot[64];
        snprintf(rot, sizeof(rot), "vizinho no irmao SMT (cpu %d)", irmao);
        const struct statistics e_smt = collect(com_vizinho, AMOSTRAS_C2C);
        print_row(rot, e_smt);

        cpu_vizinho = par_b; /* núcleo físico distinto, mesmo domínio */
        snprintf(rot, sizeof(rot), "vizinho em nucleo fisico (cpu %d)", par_b);
        const struct statistics e_fis = collect(com_vizinho, AMOSTRAS_C2C);
        print_row(rot, e_fis);

        printf("\n  Compartilhar o nucleo custa %.0f%% de desempenho; usar nucleos\n",
               100.0 * (e_smt.median / e_sozinho.median - 1.0));
        const double custo_fis = 100.0 * (e_fis.median / e_sozinho.median - 1.0);
        printf("  fisicos distintos custa %.0f%%. Duas CPUs logicas nao sao dois\n",
               custo_fis > 0.5 ? custo_fis : 0.0);
        printf("  nucleos: num laco de polling, que nunca cede as unidades de\n");
        printf("  execucao, o irmao SMT compete o tempo todo.\n");
    }

    printf("\n  Atravessar a interconexao custa %.1fx mais.\n", entre / dentro);
    printf("  Isso e %.0f%% do orcamento de %.1f ns de um pacote de 64 B em 10 GbE:\n",
           100.0 * entre / BUDGET_10GBE_NS, BUDGET_10GBE_NS);
    printf("  um unico repasse entre nucleos mal posicionados ja o estoura.\n");
    return 0;
}
