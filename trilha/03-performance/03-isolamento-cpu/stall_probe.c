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
#include "argumento.h"
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
/* O ESTADO DO PROVOCADOR SOBE, e nao morre dentro da thread.
 *
 * `tem_provocador` dizia apenas que `pthread_create` funcionou. Se a fixacao
 * falhasse dentro da thread -- CPU fora do cpuset, por exemplo --, ela devolvia
 * NULL em silencio, nenhuma carga era gerada, e o programa imprimia
 * "provoker thread: same process, other CPU" assim mesmo. O rotulo afirmava a
 * condicao central do experimento sem que ela tivesse ocorrido. */
enum { PROV_NAO_INICIOU = 0, PROV_ATIVO, PROV_SEM_AFINIDADE, PROV_SEM_MEMORIA };

struct provocador {
    int cpu;
    _Atomic int estado;
    _Atomic unsigned long voltas;   /* prova que a carga rodou, e nao so subiu */
#ifdef DPDK_ACADEMY_INJECAO
    int parar_apos_primeira;
#endif
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
    if (sched_setaffinity(0, sizeof set, &set) != 0) {
        atomic_store_explicit(&pv->estado, PROV_SEM_AFINIDADE, memory_order_release);
        return NULL;
    }
#ifdef DPDK_ACADEMY_INJECAO
    /* VARIANTE DE INJECAO, so existe na build de teste.
     *
     * O handshake antes da janela nunca roda numa execucao normal: o
     * provocador sobe em microssegundos. Um caminho que a suite nao exercita e
     * indistinguivel de um que nao existe, e este decide se a janela medida
     * tem carga.
     *
     * SAO TRES CENARIOS DIFERENTES, e um so nao basta -- a primeira versao
     * deste teste tinha apenas o primeiro, e dois mutantes sobreviveram:
     *
     *   LENTO     demora a ficar ATIVO       -> o handshake expira
     *   SEM_VOLTA fica ATIVO e nao trabalha  -> o handshake exige a 1a volta
     *   PARA      trabalha e para logo apos  -> a conferencia do fim exige
     *                                           continuidade durante a janela
     *
     * O ambiente e lido UMA VEZ, fora de qualquer laco: o portao de medicao
     * recusa `getenv()` por iteracao, e com razao. */
    const char *e_lento = getenv("INJETAR_LENTO");
    const char *e_sem_volta = getenv("INJETAR_SEM_VOLTA");
    pv->parar_apos_primeira = getenv("INJETAR_PARA") != NULL;
    if (e_lento != NULL) {
        const struct timespec atraso = { atoi(e_lento), 0 };
        nanosleep(&atraso, NULL);
    }
#endif
    atomic_store_explicit(&pv->estado, PROV_ATIVO, memory_order_release);
#ifdef DPDK_ACADEMY_INJECAO
    if (e_sem_volta != NULL) {
        const struct timespec atraso = { atoi(e_sem_volta), 0 };
        nanosleep(&atraso, NULL);
    }
#endif
    const size_t bytes = 8u * 1024u * 1024u;
    while (!atomic_load_explicit(&pv->parar, memory_order_relaxed)) {
        void *p = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (p == MAP_FAILED) {
            atomic_store_explicit(&pv->estado, PROV_SEM_MEMORIA, memory_order_release);
            break;
        }

        /* Tocar e obrigatorio: sem pagina residente nao ha o que invalidar,
         * e o `munmap` nao gera IPI para ninguem. */
        memset(p, 1, bytes);
        munmap(p, bytes);
        /* O INCREMENTO FICA AQUI, DEPOIS DO TRABALHO.
         *
         * Contando logo apos o `mmap`, `voltas > 0` significava apenas que a
         * volta COMECOU -- e a thread pode ser preemptada entre o incremento e
         * o `memset`, que e onde a pressao de memoria de fato acontece. O
         * handshake liberaria a janela com a carga ainda por vir, que e
         * exatamente o que ele existe para impedir.
         *
         * `release` para que o `acquire` do leitor veja o trabalho concluido,
         * e nao so o contador. */
        atomic_fetch_add_explicit(&pv->voltas, 1u, memory_order_release);
#ifdef DPDK_ACADEMY_INJECAO
        if (pv->parar_apos_primeira)
            break;   /* trabalhou uma vez e parou: a janela fica sem carga */
#endif
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
    /* A MASCARA ORIGINAL, ANTES DE QUALQUER FIXACAO.
     *
     * Este programa fixa a si mesmo na CPU da sonda logo abaixo, e a partir
     * dali `sched_getaffinity` devolve apenas essa CPU. Conferir o provocador
     * contra a mascara JA REDUZIDA rejeitaria toda CPU valida -- foi o que a
     * primeira versao desta conferencia fez, e o sintoma era o oposto do
     * defeito: recusava o caso correto. */
    cpu_set_t permitidas_no_inicio;
    CPU_ZERO(&permitidas_no_inicio);
    const int leu_mascara =
        sched_getaffinity(0, sizeof permitidas_no_inicio, &permitidas_no_inicio) == 0;

    /* CONVERSAO CONFERIDA. `atoi("abc")` devolvia 0 e o programa media a CPU 0
     * imprimindo "cpu 0" -- o rotulo afirmando uma condicao que ninguem pediu,
     * e saindo com codigo 0. A guarda `cpu < 0` nao pegava, porque 0 e uma CPU
     * legitima: o valor de erro estava dentro do dominio valido. */
    int cpu = 0;
    double segundos = 0.0;
    unsigned long long limiar_lido = 1000u;
    if (academy_arg_int(argv[1], "cpu", 0, CPU_SETSIZE - 1, &cpu) != 0)
        return 2;
    if (academy_arg_double(argv[2], "seconds", &segundos) != 0)
        return 2;
    if (argc == 4 &&
        academy_arg_u64(argv[3], "threshold_ns", 1u, UINT64_MAX, &limiar_lido) != 0)
        return 2;
    const uint64_t limiar = (uint64_t)limiar_lido;
    /* SER UM `double` VALIDO NAO E PERTENCER AO DOMINIO DA OPERACAO.
     *
     * `academy_arg_double` recusa lixo textual, conversao parcial, NaN e
     * infinito -- e `1e30` passa nos quatro. Depois, `(uint64_t)(segundos *
     * 1e9)` com esse valor e comportamento INDEFINIDO: o resultado nao cabe no
     * tipo. Medido: `stall_probe 0 1e30` era aceito e anunciava
     * "1000000000000000019884624838656.0 s".
     *
     * A regra que os inteiros ja seguem vale aqui: a faixa faz parte do
     * contrato. O teto de um dia e folgado de proposito -- a campanha usa
     * segundos a minutos --, e existe para impedir o transbordo, nao para
     * limitar o experimento. */
    const double SEGUNDOS_MAX = 86400.0;   /* um dia */
    if (segundos <= 0.0) {
        fprintf(stderr, "seconds must be greater than zero\n");
        return 2;
    }
    if (segundos > SEGUNDOS_MAX) {
        fprintf(stderr, "seconds: %.0f is above the accepted ceiling of %.0f"
                        " (the conversion to nanoseconds would overflow)\n",
                segundos, SEGUNDOS_MAX);
        return 2;
    }
    /* O teto vem da tabela de /proc/interrupts, nao do escalonador: um CPU
     * valido para `sched_setaffinity` e alto demais para `por_cpu[]` daria
     * contagem de interrupcao lida fora do vetor. Recusar aqui e melhor que
     * medir e reportar numero de origem desconhecida. */
    if (cpu >= PROC_MAX_CPUS) {
        fprintf(stderr, "CPU %d acima do teto de %d desta ferramenta\n",
                cpu, PROC_MAX_CPUS);
        return 2;
    }
    if (fixar_em(cpu) != 0) {
        fprintf(stderr, "sched_setaffinity to CPU %d failed\n", cpu);
        return 1;
    }

    /* A thread provocadora sobe ANTES da captura inicial, para que o delta de
     * /proc/interrupts cubra exatamente a janela em que ela esteve ativa. */
    int cpu_prov = -1;
    if (argc == 5 && academy_arg_int(argv[4], "provoker_cpu", 0, CPU_SETSIZE - 1,
                                     &cpu_prov) != 0)
        return 2;
#ifdef DPDK_ACADEMY_INJECAO
    struct provocador pv = { cpu_prov, PROV_NAO_INICIOU, 0, 0, 0 };
#else
    struct provocador pv = { cpu_prov, PROV_NAO_INICIOU, 0, 0 };
#endif
    pthread_t th;
    int tem_provocador = 0;
    if (cpu_prov >= 0) {
        if (cpu_prov == cpu) {
            fprintf(stderr, "provoker CPU must differ from probe CPU\n");
            return 2;
        }
        /* A CPU PEDIDA PRECISA ESTAR PERMITIDA A ESTE PROCESSO. Sem isto o
         * `CPU_SET` aceita qualquer numero e a falha so aparece dentro da
         * thread, tarde demais para distinguir de "nao pedi provocador". */
        if (!leu_mascara || cpu_prov >= CPU_SETSIZE ||
            !CPU_ISSET(cpu_prov, &permitidas_no_inicio)) {
            fprintf(stderr, "provoker CPU %d is not available to this process\n", cpu_prov);
            return 2;
        }
        tem_provocador = (pthread_create(&th, NULL, provocar, &pv) == 0);
        if (!tem_provocador) {
            fprintf(stderr, "pthread_create failed\n");
            return 1;
        }

        /* HANDSHAKE ANTES DA JANELA, e nao so conferencia depois dela.
         *
         * `pthread_create` devolve quando a thread FOI CRIADA, nao quando ela
         * foi escalonada. Sem esperar aqui, a captura inicial de
         * /proc/interrupts e o aquecimento da sonda podiam acontecer com o
         * provocador ainda parado -- e a conferencia do fim, que exige
         * `voltas > 0`, aprovaria uma execucao em que a carga so comecou
         * depois de metade da janela ter passado.
         *
         * A espera e por DUAS coisas: o estado ATIVO, que diz que a fixacao
         * deu certo, e a primeira volta, que diz que a carga de fato comecou.
         * Estar fixado e nao ter mapeado nada ainda nao e provocar. */
        const uint64_t limite_espera = agora_ns() + 2000000000ull;  /* 2 s */
        for (;;) {
            const int est = atomic_load_explicit(&pv.estado, memory_order_acquire);
            if (est == PROV_ATIVO &&
                atomic_load_explicit(&pv.voltas, memory_order_relaxed) > 0)
                break;
            if (est == PROV_SEM_AFINIDADE || est == PROV_SEM_MEMORIA) {
                fprintf(stderr, "provoker failed before the window: %s\n",
                        est == PROV_SEM_AFINIDADE ? "could not pin to the requested CPU"
                                                  : "mmap failed");
                atomic_store_explicit(&pv.parar, 1, memory_order_relaxed);
                pthread_join(th, NULL);
                return 1;
            }
            if (agora_ns() > limite_espera) {
                fprintf(stderr, "provoker did not start within 2 s;"
                                " the window would be labelled with a load that had not begun\n");
                atomic_store_explicit(&pv.parar, 1, memory_order_relaxed);
                pthread_join(th, NULL);
                return 1;
            }
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

    /* A CONTAGEM NO INICIO DA JANELA. O handshake acima prova que o provocador
     * JA trabalhava; este marcador prova que ele CONTINUOU durante a medicao.
     * Sao duas afirmacoes diferentes, e a conferencia do fim precisa das duas. */
    const unsigned long voltas_no_inicio =
        tem_provocador ? atomic_load_explicit(&pv.voltas, memory_order_acquire) : 0;
    unsigned long voltas_no_fim = 0;
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
        /* A FOTOGRAFIA E TIRADA ANTES DO `parar`, e nao depois do `join`.
         *
         * Lendo depois, uma volta iniciada pouco antes do fim da janela e
         * concluida fora dela entrava na conta -- e o rotulo "durante a
         * janela" passava a contar trabalho que aconteceu fora dela. */
        voltas_no_fim = atomic_load_explicit(&pv.voltas, memory_order_acquire);
        atomic_store_explicit(&pv.parar, 1, memory_order_relaxed);
        pthread_join(th, NULL);
        /* O QUE FOI PEDIDO PRECISA TER ACONTECIDO. `pthread_create` ter
         * funcionado nao diz que a thread se fixou, nem que gerou carga; sem
         * esta conferencia a medicao sai rotulada com um provocador que pode
         * nao ter existido de fato. */
        const int est = atomic_load_explicit(&pv.estado, memory_order_acquire);
        const unsigned long voltas = voltas_no_fim;
        if (est != PROV_ATIVO || voltas == 0 || voltas <= voltas_no_inicio) {
            fprintf(stderr, "provoker did not run as declared: %s (%lu rounds)\n",
                    est == PROV_SEM_AFINIDADE ? "could not pin to the requested CPU"
                    : est == PROV_SEM_MEMORIA ? "mmap failed"
                    : est == PROV_NAO_INICIOU ? "never started"
                    : voltas <= voltas_no_inicio ? "stopped before the window ended"
                    : "no work done",
                    voltas);
            fprintf(stderr, "  the measurement would be labelled with a provoker that did not exist.\n");
            return 1;
        }
    }

    printf("stall probe: cpu %d, %.1f s, threshold %" PRIu64 " ns\n",
           cpu, segundos, limiar);
    printf("provoker thread: %s\n",
           tem_provocador ? "same process, other CPU (verified: pinned and ran)" : "none");
    /* A CONTAGEM SAI NA TABELA, e nao so a afirmacao de que houve provocador.
     *
     * `voltas > 0` prova que a carga comecou; nao prova a TAXA. Um provocador
     * que deu tres voltas numa janela de dez segundos passa na conferencia e
     * nao gerou pressao comparavel a uma execucao normal. Publicar o numero
     * deixa isso visivel a quem le, em vez de exigir confianca no binario:
     * duas coletas com contagens de ordem diferente nao sao comparaveis,
     * mesmo que as duas digam "verified". */
    if (tem_provocador)
        printf("provoker rounds completed during the window: %lu"
               " (8 MiB mapped, touched and unmapped each)\n",
               voltas_no_fim - voltas_no_inicio);
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
