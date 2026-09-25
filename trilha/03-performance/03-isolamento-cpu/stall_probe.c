/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Sonda de paradas: quanto tempo a CPU deixa de ser sua, com a thread fixada.
 *
 * O QUE ESTE PROGRAMA MEDE
 *
 * Um laco que so le o relogio. Entre duas leituras consecutivas nao ha trabalho
 * nenhum, entao qualquer intervalo acima do custo da propria leitura e tempo em
 * que a CPU esteve executando OUTRA COISA -- interrupcao, tick, IPI, kthread.
 *
 * Nao ha DPDK aqui, e isso e o ponto: a pergunta e sobre o sistema operacional,
 * nao sobre o plano de dados. O resultado vale para qualquer laco de polling,
 * em qualquer framework.
 *
 * POR QUE AFINIDADE NAO BASTA -- QUE E A HIPOTESE DO TOPICO
 *
 * `sched_setaffinity` prende a thread a uma CPU. Nao impede que o kernel
 * execute trabalho NAQUELA CPU: tick do escalonador, callbacks de RCU,
 * workqueues por CPU, IPIs de outras CPUs e interrupcoes de dispositivo
 * continuam chegando. A thread nao saiu; o sistema entrou.
 *
 * A DIFERENCA ENTRE ESTA SONDA E UM BENCHMARK
 *
 * Nao ha trabalho util e nao ha resultado a publicar em ns/operacao. O que sai
 * e a CAUDA: o maior intervalo, os percentis altos, e quantos deles excedem a
 * janela do anel de RX -- que e o unico limiar em que uma parada custa pacote.
 *
 * Por isso a saida traz histograma, e nao mediana: a mediana de um laco ocioso
 * e o custo da leitura do relogio, que nao interessa a ninguem.
 *
 * USO
 *
 *   stall_probe <cpu> <segundos> [limiar_ns] [cpu_provocador]
 *
 * O limiar so filtra o que entra no relato textual de eventos; o histograma
 * recebe todos os intervalos.
 *
 * O PROVOCADOR E UMA THREAD DESTE PROCESSO, E ISSO E O PONTO
 *
 * Com `cpu_provocador`, uma thread deste mesmo processo passa a alterar o
 * mapeamento de memoria em ciclo, noutra CPU. O IPI de invalidacao de TLB vai
 * para toda CPU que execute o MESMO espaco de enderecamento -- e a CPU da sonda
 * executa, porque e o mesmo processo.
 *
 * Um PROCESSO separado fazendo o mesmo trabalho nao produz o efeito: espaco de
 * enderecamento distinto, nenhum IPI. O `ipi_provoker` existe justamente para
 * demonstrar esse contraste, e a diferenca entre os dois e a evidencia de que o
 * escopo e o espaco de enderecamento, nao a CPU.
 */
#define _GNU_SOURCE
#include <pthread.h>
#include <sched.h>
#include <sys/mman.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "gap_hist.h"
#include "procstat.h"

/* Leitura do relogio. `CLOCK_MONOTONIC` e nao o TSC bruto: a sonda precisa
 * sobreviver a mudanca de frequencia, e `clock_gettime` com vDSO custa dezenas
 * de nanossegundos -- ordem de grandeza abaixo das paradas que se procura. */
static inline uint64_t agora_ns(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        /* Medir tempo com relogio quebrado e pior que nao medir. */
        fprintf(stderr, "clock_gettime falhou\n");
        exit(2);
    }
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

/* Thread provocadora: altera o mapeamento em ciclo, para forcar invalidacao de
 * TLB nas demais CPUs deste processo. Ver o cabecalho e o README secao 2.1. */
struct provocador {
    int cpu;
    /* Escrito pela thread principal, lido pela provocadora.
     *
     * `volatile` impede o compilador de eliminar a releitura e nao faz mais que
     * isso: nao torna o acesso indivisivel nem ordena nada contra o modelo de
     * memoria de C11, que continua chamando isto de corrida de dados. Em x86-64
     * um `int` alinhado de fato nao rasga, mas a licenca que o compilador tem
     * para supor que a corrida nao existe e o que quebra codigo sob otimizacao.
     *
     * `relaxed` basta: o sinalizador nao publica outro dado, e o que se exige
     * dele e atomicidade e visibilidade eventual. */
    _Atomic int parar;
};

static void *provocar(void *arg)
{
    struct provocador *pv = arg;
    cpu_set_t set;
    CPU_ZERO(&set);
    CPU_SET(pv->cpu, &set);
    if (sched_setaffinity(0, sizeof set, &set) != 0)
        return NULL;
    const size_t bytes = 8u * 1024u * 1024u;
    while (!atomic_load_explicit(&pv->parar, memory_order_relaxed)) {
        void *p = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (p == MAP_FAILED)
            break;
        /* Tocar e obrigatorio: sem pagina residente nao ha o que invalidar,
         * e o `munmap` nao gera IPI para ninguem. */
        memset(p, 1, bytes);
        munmap(p, bytes);
    }
    return NULL;
}

static int fixar_em(int cpu)
{
    cpu_set_t set;
    CPU_ZERO(&set);
    CPU_SET(cpu, &set);
    return sched_setaffinity(0, sizeof set, &set);
}

static char *ler_arquivo(const char *caminho)
{
    FILE *f = fopen(caminho, "re");
    if (f == NULL)
        return NULL;
    size_t cap = 65536, len = 0;
    char *buf = malloc(cap);
    if (buf == NULL) {
        fclose(f);
        return NULL;
    }
    size_t n;
    while ((n = fread(buf + len, 1, cap - len - 1, f)) > 0) {
        len += n;
        if (len + 1 >= cap) {
            cap *= 2;
            char *novo = realloc(buf, cap);
            if (novo == NULL) {
                free(buf);
                fclose(f);
                return NULL;
            }
            buf = novo;
        }
    }
    buf[len] = '\0';
    fclose(f);
    return buf;
}

/* Trocas de contexto NAO VOLUNTARIAS desta thread.
 *
 * POR QUE ISTO ESTA AQUI
 *
 * `/proc/interrupts` nao explica as maiores paradas: um tique nao dura
 * centenas de microssegundos. A candidata obvia e PREEMPCAO -- afinidade
 * impede que a thread MIGRE, nao que o escalonador a tire da CPU em favor de
 * outra tarefa executavel. A sonda e SCHED_OTHER como qualquer processo.
 *
 * O contador esta em /proc/self/status e custa uma leitura por execucao. Sem
 * ele, a maior parada fica sem causa atribuida, e atribuir sem medir seria
 * exatamente o que este material recusa.
 */
static uint64_t trocas_forcadas(void)
{
    char *t = ler_arquivo("/proc/self/status");
    if (t == NULL)
        return 0;
    uint64_t v = 0;
    const char *p = strstr(t, "nonvoluntary_ctxt_switches:");
    if (p != NULL)
        v = strtoull(p + strlen("nonvoluntary_ctxt_switches:"), NULL, 10);
    free(t);
    return v;
}

/* Le /proc/interrupts para uma tabela. Devolve 0 em sucesso. */
static int capturar(struct proc_tabela *t)
{
    char *texto = ler_arquivo("/proc/interrupts");
    if (texto == NULL)
        return -1;
    const int r = proc_analisar(texto, t);
    free(texto);
    return r;
}

int main(int argc, char **argv)
{
    if (argc < 3 || argc > 5) {
        fprintf(stderr, "usage: %s <cpu> <seconds> [threshold_ns] [provoker_cpu]\n",
                argv[0]);
        return 2;
    }
    const int cpu = atoi(argv[1]);
    const double segundos = atof(argv[2]);
    const uint64_t limiar = (argc == 4) ? strtoull(argv[3], NULL, 10) : 1000u;
    if (cpu < 0 || segundos <= 0.0) {
        fprintf(stderr, "invalid parameters\n");
        return 2;
    }
    if (fixar_em(cpu) != 0) {
        fprintf(stderr, "sched_setaffinity to CPU %d failed\n", cpu);
        return 1;
    }

    /* A thread provocadora sobe ANTES da captura inicial, para que o delta de
     * /proc/interrupts cubra exatamente a janela em que ela esteve ativa. */
    const int cpu_prov = (argc == 5) ? atoi(argv[4]) : -1;
    struct provocador pv = { cpu_prov, 0 };
    pthread_t th;
    int tem_provocador = 0;
    if (cpu_prov >= 0) {
        if (cpu_prov == cpu) {
            fprintf(stderr, "provoker CPU must differ from probe CPU\n");
            return 2;
        }
        tem_provocador = (pthread_create(&th, NULL, provocar, &pv) == 0);
        if (!tem_provocador) {
            fprintf(stderr, "pthread_create failed\n");
            return 1;
        }
    }

    struct proc_tabela antes, depois;
    const int tem_proc = (capturar(&antes) == 0);
    const uint64_t trocas0 = trocas_forcadas();

    struct gap_hist h;
    gap_hist_iniciar(&h);

    /* Aquecimento: a primeira passagem paga falta de pagina e preditor frio, e
     * mediria o inicio em vez do regime. Mesmo argumento do `aquecer()` do
     * topico de mempool. */
    for (int i = 0; i < 100000; i++)
        (void)agora_ns();

    const uint64_t t0 = agora_ns();
    const uint64_t fim = t0 + (uint64_t)(segundos * 1e9);
    uint64_t anterior = agora_ns(), acima = 0;
    for (;;) {
        const uint64_t t = agora_ns();
        gap_hist_somar(&h, t - anterior);
        if (t - anterior >= limiar)
            acima++;
        anterior = t;
        if (t >= fim)
            break;
    }

    if (tem_provocador) {
        atomic_store_explicit(&pv.parar, 1, memory_order_relaxed);
        pthread_join(th, NULL);
    }

    printf("stall probe: cpu %d, %.1f s, threshold %" PRIu64 " ns\n",
           cpu, segundos, limiar);
    printf("provoker thread: %s\n",
           tem_provocador ? "same process, other CPU" : "none");
    printf("samples: %" PRIu64 "\n", h.amostras);
    printf("stalls above threshold: %" PRIu64 "\n", acima);
    /* Percentis saem do histograma e sao PISOS de balde; o maior e exato.
     * Publicar o piso e nao interpolar dentro do balde e deliberado -- ver
     * gap_hist.h. */
    printf("p99 floor: %" PRIu64 " ns\n", gap_percentil_piso(&h, 990));
    printf("p99.9 floor: %" PRIu64 " ns\n", gap_percentil_piso(&h, 999));
    printf("max stall: %" PRIu64 " ns\n", h.maior);
    /* Preempcao nao aparece em /proc/interrupts, e e a candidata para as
     * maiores paradas. Ver o comentario de `trocas_forcadas`. */
    printf("involuntary context switches: %" PRIu64 "\n",
           trocas_forcadas() - trocas0);

    /* A janela e cota inferior: ver gap_hist.h. Publicada junto para que o
     * leitor compare a maior parada com o limiar que custa pacote. */
    printf("RX ring window (lower bound, 10 GbE, 64 B frames):\n");
    for (unsigned d = 512; d <= 4096; d *= 2)
        printf("  %4u descriptors: %.1f us\n", d, janela_ns(d, 64, 10.0) / 1000.0);

    if (tem_proc && capturar(&depois) == 0) {
        struct proc_delta d[16];
        const size_t n = proc_delta_cpu(&antes, &depois, (unsigned)cpu, d, 16);
        printf("interrupts on cpu %d during the run:\n", cpu);
        if (n == 0)
            printf("  none\n");
        for (size_t i = 0; i < n; i++)
            printf("  %-8s %" PRIu64 "\n", d[i].rotulo, d[i].delta);
    } else {
        /* Ausencia de evidencia aparece; nao vira silencio. */
        printf("interrupts on cpu %d: UNAVAILABLE (/proc/interrupts unreadable)\n", cpu);
    }
    return 0;
}
