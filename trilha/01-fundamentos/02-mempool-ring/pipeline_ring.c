/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Tópico 02 — Pipeline em memória com rte_mempool e rte_ring.
 *
 * Produtor: obtém objetos do pool em lote, preenche e enfileira no ring.
 * Consumidor: desenfileira em lotes (bursts), processa e devolve ao pool.
 * Nenhuma NIC é usada; o objetivo é praticar o ciclo alocação -> fila ->
 * processamento em lote -> devolução ao pool, que é o mesmo dos mbufs em RX/TX.
 *
 * DOIS MODOS, escolhidos pelo número de lcores dados à EAL:
 *
 *   -l 0        um lcore: produtor e consumidor se alternam no mesmo núcleo.
 *               A fila nunca atravessa núcleos; é o caso mais simples.
 *
 *   -l 0,2      dois lcores: o consumidor roda em núcleo próprio, e cada lote
 *               atravessa de um cache para o outro. É o uso real de um ring, e
 *               é aqui que a topologia da CPU passa a importar — comparar dois
 *               núcleos do mesmo domínio de L3 com dois de domínios diferentes
 *               mostra a diferença. Veja docs/01-fundamentos §4.3.
 *
 * Uso: ./pipeline_ring <opções da EAL> -- [-n pacotes] [-b tamanho_do_lote]
 */
/* _GNU_SOURCE precisa vir ANTES de qualquer include: os cabecalhos do DPDK usam
 * ssize_t e strnlen, que sao POSIX/GNU e nao fazem parte do C11 do padrao ISO.
 * E assim que o proprio DPDK resolve isso upstream -- macro de funcionalidade
 * por arquivo, nao troca do padrao da linguagem para gnu11. */
#define _GNU_SOURCE
#include <rte_cycles.h>
#include <rte_eal.h>
#include <rte_errno.h>
#include <rte_lcore.h>
#include <rte_mempool.h>
#include <rte_ring.h>

#include <getopt.h>
#include <inttypes.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

#include "packet.h"
#include "../../../docs/01-fundamentos/medicoes/statistics.h"

#define BURST_MAX 256u

struct config {
    uint64_t num_packets;
    unsigned burst;
    /* Cache por lcore do mempool. Ver README.md secao 4.2 "Parametros de execucao e a impossibilidade de medir constantes". */
    unsigned cache_size;
    /* Prazo SEM PROGRESSO em milissegundos; 0 desliga. Nao e prazo total de
     * execucao. Ver README.md secao 4.2 "Parametros de execucao e a impossibilidade de medir constantes". */
    uint64_t progresso_ms;
    /* Profundidade da fila, em objetos. Potencia de dois; capacidade util e
     * profundidade-1. Ver README.md secao 4.1 "A estrutura de configuracao e seus invariantes". */
    unsigned profundidade;
};

/* Exigencia do rte_ring, conferida aqui para que o erro saia com a explicacao
 * em vez de sair do DPDK como "invalid argument". */
static int potencia_de_dois(unsigned n)
{
    return n != 0 && (n & (n - 1)) == 0;
}

/* Taxa de acerto do cache do mempool, por lcore. Ver README.md secao 4.3 "Contabilizacao do cache do mempool". */
static void relatar_mempool(const struct rte_mempool *mp)
{
#ifdef RTE_LIBRTE_MEMPOOL_STATS
    unsigned id;
    uint64_t tg = 0, tgc = 0, tp = 0, tpc = 0;

    printf("mempool cache stats (per lcore)\n");
    printf("  lcore  %10s %10s %7s  %10s %10s %7s\n",
           "get_bulk", "get_common", "miss%", "put_bulk", "put_common", "flush%");
    for (id = 0; id <= RTE_MAX_LCORE; id++) {
        /* Os contadores vivem em dois lugares. Ver README.md secao 4.3 "Contabilizacao do cache do mempool". */
        uint64_t g, pu;
        const uint64_t gc = mp->stats[id].get_common_pool_bulk;
        const uint64_t pc = mp->stats[id].put_common_pool_bulk;

        /* `stats[]` tem RTE_MAX_LCORE + 1 entradas; `local_cache[]` tem
         * RTE_MAX_LCORE. Delimitar o indice e obrigatorio. Ver README.md
         * secao 4.3 "Contabilizacao do cache do mempool". */
        if (mp->cache_size != 0 && mp->local_cache != NULL && id < RTE_MAX_LCORE) {
            g = mp->local_cache[id].stats.get_success_bulk;
            pu = mp->local_cache[id].stats.put_bulk;
        } else {
            g = mp->stats[id].get_success_bulk;
            pu = mp->stats[id].put_bulk;
        }
        if (g == 0 && pu == 0 && gc == 0 && pc == 0)
            continue;
        printf("  %5u  %10" PRIu64 " %10" PRIu64 " %6.2f%%  %10" PRIu64 " %10" PRIu64 " %6.2f%%\n",
               id, g, gc, g ? 100.0 * (double)gc / (double)g : 0.0,
               pu, pc, pu ? 100.0 * (double)pc / (double)pu : 0.0);
        tg += g; tgc += gc; tp += pu; tpc += pc;
    }
    printf("  total  %10" PRIu64 " %10" PRIu64 " %6.2f%%  %10" PRIu64 " %10" PRIu64 " %6.2f%%\n",
           tg, tgc, tg ? 100.0 * (double)tgc / (double)tg : 0.0,
           tp, tpc, tp ? 100.0 * (double)tpc / (double)tp : 0.0);
#else
    (void)mp;
    printf("mempool cache stats: UNAVAILABLE"
           " (DPDK built without RTE_LIBRTE_MEMPOOL_STATS)\n");
#endif
}

static int parse_config(int argc, char **argv, struct config *cfg)
{
    int opt;
    cfg->num_packets = 10;
    cfg->burst = 32;
    cfg->progresso_ms = 0;
    cfg->profundidade = 1024;
    cfg->cache_size = 64;
    optind = 1;
    while ((opt = getopt(argc, argv, "n:b:t:q:c:")) != -1) {
        switch (opt) {
        case 'n': cfg->num_packets = strtoull(optarg, NULL, 10); break;
        case 'b': cfg->burst = (unsigned)strtoul(optarg, NULL, 10); break;
        case 't': cfg->progresso_ms = strtoull(optarg, NULL, 10); break;
        case 'q': cfg->profundidade = (unsigned)strtoul(optarg, NULL, 10); break;
        case 'c': cfg->cache_size = (unsigned)strtoul(optarg, NULL, 10); break;
        default:
            fprintf(stderr, "Usage: %s <EAL> -- [-n packets] [-b batch (1..%u)]"
                            " [-t ms without progress] [-q queue depth]"
                            " [-c per-lcore cache]\n",
                    argv[0], BURST_MAX);
            return -1;
        }
    }
    if (cfg->burst == 0 || cfg->burst > BURST_MAX || cfg->num_packets == 0) {
        fprintf(stderr, "Invalid parameters: -n must be > 0 and -b between 1 and %u\n", BURST_MAX);
        return -1;
    }
    if (!potencia_de_dois(cfg->profundidade)) {
        fprintf(stderr, "Invalid parameters: -q must be a power of two"
                        " (rte_ring requirement); got %u\n", cfg->profundidade);
        return -1;
    }
    /* Invariante 2 do README.md secao 4.1 "A estrutura de configuracao e seus invariantes": a fila precisa caber um lote
     * inteiro. Capacidade util e profundidade-1, dai o `<=`. */
    if (cfg->profundidade <= cfg->burst) {
        fprintf(stderr, "Invalid parameters: -q %u cannot hold a batch of %u"
                        " (usable capacity is depth-1)\n",
                cfg->profundidade, cfg->burst);
        return -1;
    }
    return 0;
}

/* Estado do consumidor. Alinhado à linha de cache para que a escrita do
 * consumidor não compartilhe linha com dados do produtor (falso
 * compartilhamento arruinaria a medição). */
struct consumer_context {
    struct rte_ring *ring;
    struct rte_mempool *pool;
    unsigned burst;
    uint64_t target;
    struct summary r;
    /* OS DOIS CAMPOS ABAIXO SAO LIDOS POR UM LCORE E ESCRITOS POR OUTRO.
     *
     * `volatile` nao serve para isso, e a distincao nao e academica: ele impede
     * o compilador de eliminar o acesso, e NAO torna o acesso indivisivel nem
     * ordena nada contra o modelo de memoria. Um `uint64_t` lido enquanto outro
     * nucleo o escreve e corrida de dados -- comportamento indefinido em C11,
     * independentemente de x86-64 na pratica devolver o valor inteiro. O
     * compilador tem licenca para supor que a corrida nao existe, e e por essa
     * licenca que otimizacao quebra codigo que "funcionava".
     *
     * `memory_order_relaxed` nos dois: nenhum deles publica OUTRO dado. Sao
     * sinais isolados -- "pare" e "estou avancando" --, e o que se exige deles e
     * atomicidade e visibilidade eventual, nao ordenacao. Um `acquire`/`release`
     * aqui seria custo sem consumidor. Isso NAO e licenca geral: o anel e o
     * mempool publicam dados, e la a ordenacao e da biblioteca. */

    /* Pedido de parada, escrito pelo produtor e lido pelo consumidor. A
     * terminacao e pedida, nao imposta. Ver README.md secao 6.5 "Terminacao sob falha". */
    _Atomic int parar;
    /* Progresso do consumidor, para o cao de guarda do produtor.
     *
     * Separado de `r.packets` de proposito: aquele e o contador do caminho
     * quente, lido e escrito so pelo consumidor, e torna-lo atomico mudaria o
     * que o programa mede. Este e escrito UMA vez por lote, nao por pacote. */
    _Atomic uint64_t progresso;
    /* Maior lote REALMENTE desenfileirado de uma vez. O parametro ecoado nao
     * e evidencia de uso. Ver README.md secao 5.2 "O contrato e o codigo de saida, nao a mensagem". */
    unsigned maior_deq;
} __rte_cache_aligned;

/* Executado no lcore trabalhador quando há dois ou mais lcores. */
static int consumer_loop(void *arg)
{
    struct consumer_context *c = arg;
#ifndef DPDK_ACADEMY_INJECT_PAUSE
    /* So existe no caminho que consome: na variante de injecao o consumidor
     * nao esvazia o anel, e o vetor de lote seria variavel nao usada. */
    struct packet *burst[BURST_MAX];
#endif

    while (c->r.packets < c->target && !atomic_load_explicit(&c->parar, memory_order_relaxed)) {
#ifndef DPDK_ACADEMY_INJECT_PAUSE
        const unsigned deq = rte_ring_dequeue_burst(c->ring, (void **)burst, c->burst, NULL);
        if (deq > c->maior_deq) c->maior_deq = deq;
        if (deq > 0) {
            packet_process_burst(burst, deq, &c->r);
            rte_mempool_put_bulk(c->pool, (void *const *)burst, deq);
            /* Uma escrita por LOTE. O cao de guarda so precisa saber que o
             * numero anda, nao qual e. */
            atomic_store_explicit(&c->progresso, c->r.packets, memory_order_relaxed);
        }
#else
        /* CONSUMIDOR PARADO DE PROPOSITO, compilado so na variante de teste.
         * Ver o mesmo bloco no laco de um lcore so. */
        rte_pause();
#endif
    }
    return 0;
}

/* Primeira CPU do cpuset de um lcore.
 *
 * `rte_lcore_id()` devolve o identificador de lcore da EAL, que NAO e um numero
 * de CPU: a identidade entre os dois so vale quando o comando usa `-l` com uma
 * lista que coincide, e quebra em silencio com `--lcores` remapeando. Passar o
 * lcore direto a `freq_ghz` leria a frequencia de outro nucleo -- ou de nenhum,
 * e o zero de "sysfs nao expoe" e indistinguivel do zero de "CPU errada".
 *
 * Nao se usa `rte_lcore_to_cpu_id()`: ela e descrita de formas incompativeis
 * entre a documentacao e a implementacao conforme a release. O cpuset e o
 * contrato estavel. Mesmo criterio de custo-contencao.c. */
static unsigned cpu_do_lcore(unsigned lcore)
{
    rte_cpuset_t cs = rte_lcore_cpuset(lcore);
    for (unsigned c = 0; c < CPU_SETSIZE; c++)
        if (CPU_ISSET(c, &cs))
            return c;
    return lcore; /* sem cpuset legivel, o lcore e o melhor palpite disponivel */
}

/* Frequência corrente do núcleo, em GHz, ou 0 se o sistema não a expuser.
 * Publicar o tempo sem publicar a frequência convida a comparação inválida:
 * com governor "powersave" e turbo, ela varia entre execuções, e os valores
 * absolutos vão junto. */
static double freq_ghz(unsigned cpu)
{
    char path[128];
    snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu%u/cpufreq/scaling_cur_freq",
             cpu);
    FILE *f = fopen(path, "r");
    if (f == NULL)
        return 0.0;
    long khz = 0;
    if (fscanf(f, "%ld", &khz) != 1)
        khz = 0;
    fclose(f);
    return (double)khz / 1e6;
}

/* Quantos pacotes o aquecimento processa antes da medição começar. */
#define WARMUP 4096u

/* Abaixo deste número de pacotes, o tempo médio NÃO é medição e o programa se
 * recusa a publicá-lo como tal.
 *
 * O motivo não é falta de aquecimento — este programa aquece. É que 10 pacotes
 * representam ~20 ns de trabalho real, medidos com um relógio cuja leitura
 * custa a mesma ordem de grandeza: o instrumento domina o fenômeno. Medido
 * nesta máquina, três execuções seguidas deram, para o mesmo comando:
 *
 *     -n 10        40 / 55 / 134 ns    (inutilizável)
 *     -n 100       10 / 15 / 16 ns     (ainda ±50%)
 *     -n 10000     2,2 / 2,4 / 2,4 ns  (estável)
 *
 * Publicar o primeiro caso com uma casa decimal seria precisão inventada. */
#define MIN_TO_MEASURE 10000u

/* Uma passagem completa de produtor+consumidor no MESMO lcore, com o resultado
 * DESCARTADO.
 *
 * Sem isto, a primeira passagem paga falta de página no pool recém-criado,
 * preditor de desvio frio e rampa de frequência — e o "Tempo medio" impresso
 * mede aquecimento em vez de regime permanente. Com -n pequeno o efeito domina
 * o número inteiro: execuções seguidas desta máquina davam 92, 115 e 134
 * ns/pacote para a mesma carga.
 *
 * Devolve 0 se o pool ficou íntegro ao final, que é também uma verificação:
 * se o aquecimento vazar objeto, a medição seguinte parte de um pool menor. */
static int warmup(struct rte_ring *ring, struct rte_mempool *pool, unsigned burst,
                   unsigned pool_objs)
{
    struct packet *prod[BURST_MAX];
    struct packet *cons[BURST_MAX];
    struct summary r = {0, 0};
    uint64_t produced = 0;

    while (r.packets < WARMUP) {
        unsigned n = burst;
        if (WARMUP - produced < n)
            n = (unsigned)(WARMUP - produced);
        if (n > 0 && rte_mempool_get_bulk(pool, (void **)prod, n) == 0) {
            for (unsigned i = 0; i < n; i++)
                packet_fill(prod[i], produced + i, 64u);
            const unsigned enq = rte_ring_enqueue_burst(ring, (void *const *)prod, n, NULL);
            produced += enq;
            if (enq < n)
                rte_mempool_put_bulk(pool, (void *const *)&prod[enq], n - enq);
        }
        const unsigned deq = rte_ring_dequeue_burst(ring, (void **)cons, burst, NULL);
        if (deq > 0) {
            packet_process_burst(cons, deq, &r);
            rte_mempool_put_bulk(pool, (void *const *)cons, deq);
        }
    }

    return rte_mempool_avail_count(pool) == pool_objs ? 0 : -1;
}

int main(int argc, char **argv)
{
    int consumed = rte_eal_init(argc, argv);
    if (consumed < 0) {
        fprintf(stderr, "Error initialising the EAL: %s\n", rte_strerror(rte_errno));
        return EXIT_FAILURE;
    }
    argc -= consumed;
    argv += consumed;

    struct config cfg;
    if (parse_config(argc, argv, &cfg) < 0) {
        rte_eal_cleanup();
        return EXIT_FAILURE;
    }

    /* Pool de objetos fixos, alocado no no NUMA do lcore principal. O 4095 e
     * recomendacao de uso de memoria, nao exigencia da API. Ver README.md
     * secao 4.1 "A estrutura de configuracao e seus invariantes". */
    const unsigned pool_objs = 4095;
    struct rte_mempool *pool = rte_mempool_create(
        "pool_pacotes", pool_objs, sizeof(struct packet),
        cfg.cache_size, /* private data */ 0,
        NULL, NULL, NULL, NULL, rte_socket_id(), 0);
    if (pool == NULL) {
        fprintf(stderr, "rte_mempool_create failed: %s\n", rte_strerror(rte_errno));
        rte_eal_cleanup();
        return EXIT_FAILURE;
    }

    /* Fila de ponteiros entre produtor e consumidor (um de cada: SP/SC). */
    struct rte_ring *ring = rte_ring_create("fila", cfg.profundidade, rte_socket_id(),
                                            RING_F_SP_ENQ | RING_F_SC_DEQ);
    if (ring == NULL) {
        fprintf(stderr, "rte_ring_create failed: %s\n", rte_strerror(rte_errno));
        rte_mempool_free(pool);
        rte_eal_cleanup();
        return EXIT_FAILURE;
    }

    struct packet *burst_prod[BURST_MAX];
#ifndef DPDK_ACADEMY_INJECT_PAUSE
    struct packet *burst_cons[BURST_MAX];
#endif
    struct summary r = {0, 0};
    uint64_t produced = 0, did_not_fit = 0;
    /* Maiores lotes REALMENTE movidos, produtor e consumidor. Ver README.md
     * secao 5.2 "O contrato e o codigo de saida, nao a mensagem". */
    unsigned maior_enq = 0, maior_deq_local = 0;
    /* Espera limitada: tempo aceito SEM PROGRESSO. O relogio so anda quando
     * nada avanca. Ver README.md secao 4.2 "Parametros de execucao e a impossibilidade de medir constantes". */
    const uint64_t prazo_ciclos = cfg.progresso_ms
                                      ? cfg.progresso_ms * (rte_get_tsc_hz() / 1000ULL)
                                      : 0;
    uint64_t marco_progresso = 0, ultimo_avanco = 0;
    int sem_progresso = 0;

    /* Com dois ou mais lcores, o consumidor ganha núcleo próprio e a fila
     * passa a atravessar caches. Com um só, os dois papéis se alternam aqui. */
    const unsigned lcore_consumer = rte_get_next_lcore(rte_lcore_id(), 1, 0);
    const int two_cores = (lcore_consumer != RTE_MAX_LCORE);

    /* Aquecimento ANTES de lançar o consumidor e antes de t0: o que se quer
     * medir é regime permanente, não o custo de tocar a memória pela primeira
     * vez. Ver o comentário de aquecer(). */
    if (warmup(ring, pool, cfg.burst, pool_objs) != 0) {
        fprintf(stderr, "Warm-up left the pool incomplete: %u of %u\n",
                rte_mempool_avail_count(pool), pool_objs);
        rte_ring_free(ring);
        rte_mempool_free(pool);
        rte_eal_cleanup();
        return EXIT_FAILURE;
    }

    static struct consumer_context ctx;
    if (two_cores) {
        ctx.ring = ring;
        ctx.pool = pool;
        ctx.burst = cfg.burst;
        ctx.target = cfg.num_packets;
        ctx.r.packets = 0;
        atomic_store_explicit(&ctx.progresso, 0, memory_order_relaxed);
        atomic_store_explicit(&ctx.parar, 0, memory_order_relaxed);
        ctx.r.bytes = 0;
        /* O retorno importa, e a falha mais provável é instrutiva: -EBUSY
         * significa que o lcore NÃO está em WAIT — ou seja, já recebeu trabalho
         * e ainda não o terminou. Ignorar isso deixaria o produtor publicando
         * para um consumidor que nunca foi lançado, e o sintoma seria uma
         * espera infinita, não um erro. Sobre os estados do lcore, ver o módulo
         * de runtime em docs/02-runtime-dpdk/. */
        const int launched = rte_eal_remote_launch(consumer_loop, &ctx, lcore_consumer);
        if (launched != 0) {
            fprintf(stderr, "rte_eal_remote_launch on lcore %u failed: %s\n", lcore_consumer,
                    rte_strerror(-launched));
            rte_ring_free(ring);
            rte_mempool_free(pool);
            rte_eal_cleanup();
            return EXIT_FAILURE;
        }
    }

    const uint64_t t0 = rte_rdtsc();

    while (produced < cfg.num_packets || (!two_cores && r.packets < cfg.num_packets)) {
        /* --- Produtor: aloca do pool em lote e enfileira --- */
        unsigned n = cfg.burst;
        if (cfg.num_packets - produced < n)
            n = (unsigned)(cfg.num_packets - produced);
        if (n > 0 && rte_mempool_get_bulk(pool, (void **)burst_prod, n) == 0) {
            for (unsigned i = 0; i < n; i++)
                packet_fill(burst_prod[i], produced + i, 64u + (uint32_t)((produced + i) % 32u));
            unsigned enq = rte_ring_enqueue_burst(ring, (void *const *)burst_prod, n, NULL);
            if (enq > maior_enq) maior_enq = enq;
            produced += enq;
            /* Fila cheia: os que não couberam voltam ao pool (nunca vazam). */
            if (enq < n) {
#ifndef DPDK_ACADEMY_INJECT_LEAK
                rte_mempool_put_bulk(pool, (void *const *)&burst_prod[enq], n - enq);
#else
                /* VAZAMENTO DELIBERADO, compilado so na variante de teste.
                 * Injecao de defeito; ver README.md secao 5.1 "Injecao de defeito: verificar que a verificacao dispara". */
#endif
                did_not_fit += n - enq;
            }
        }

        /* --- Consumidor: só neste laço quando há um único lcore --- */
        if (!two_cores) {
#ifndef DPDK_ACADEMY_INJECT_PAUSE
            unsigned deq = rte_ring_dequeue_burst(ring, (void **)burst_cons, cfg.burst, NULL);
            if (deq > maior_deq_local) maior_deq_local = deq;
            if (deq > 0) {
                packet_process_burst(burst_cons, deq, &r);
                rte_mempool_put_bulk(pool, (void *const *)burst_cons, deq);
            }
#else
            /* CONSUMIDOR PARADO DE PROPOSITO, compilado so na variante de
             * teste. Injecao de defeito; ver README.md secao 5.1 "Injecao de defeito: verificar que a verificacao dispara". */
#endif
        }

        /* O prazo so corre enquanto nada avanca. */
        if (prazo_ciclos) {
            const uint64_t agora_total = produced + r.packets;
            const uint64_t agora = rte_rdtsc();
            if (agora_total != marco_progresso) {
                marco_progresso = agora_total;
                ultimo_avanco = agora;
            } else if (ultimo_avanco && agora - ultimo_avanco > prazo_ciclos) {
                sem_progresso = 1;
                break;
            } else if (!ultimo_avanco) {
                ultimo_avanco = agora;
            }
        }
    }

    if (two_cores) {
        /* O prazo vale tambem para a espera: com dois lcores quem pode
         * bloquear e `rte_eal_wait_lcore`, nao o laco do produtor.
         * Ver README.md secao 6.5 "Terminacao sob falha". */
        if (prazo_ciclos && !sem_progresso) {
            uint64_t visto = atomic_load_explicit(&ctx.progresso, memory_order_relaxed);
            uint64_t desde = rte_rdtsc();
            for (;;) {
                const uint64_t agora_visto =
                    atomic_load_explicit(&ctx.progresso, memory_order_relaxed);
                if (agora_visto >= cfg.num_packets)
                    break;
                if (agora_visto != visto) {
                    visto = agora_visto;
                    desde = rte_rdtsc();
                } else if (rte_rdtsc() - desde > prazo_ciclos) {
                    sem_progresso = 1;
                    break;
                }
                rte_pause();
            }
        }
        /* Pede a parada ANTES de esperar. Ver README.md secao 6.5 "Terminacao sob falha". */
        if (sem_progresso)
            atomic_store_explicit(&ctx.parar, 1, memory_order_relaxed);
        rte_eal_wait_lcore(lcore_consumer);
        r = ctx.r;
    }

    const uint64_t cycles = rte_rdtsc() - t0;
    /* Lido aqui, fora dos lacos: o portao recusa getenv() por iteracao. */
    const int relatar_bruto = getenv("DPDK_ACADEMY_BRUTO") != NULL;
    const double ns_per_packet = (double)cycles * 1e9 / (double)rte_get_tsc_hz() / (double)r.packets;

    print_provenance("pipeline_ring");
    printf("Configured per-lcore cache: %u\n", cfg.cache_size);
    printf("Packets processed: %" PRIu64 "\n", r.packets);
    printf("Total bytes: %" PRIu64 "\n", r.bytes);
    /* Conta OBJETOS, nao eventos: `n - enq` e quanto sobrou do lote. Rotular
     * isto de "tentativas" ja induziu a leitura errada de que a fila encheu
     * N vezes, quando N e o total de objetos que nao couberam. E o mesmo
     * numero que vaza na variante `pipeline_ring_vazado`, e e por isso que
     * os dois batem exatamente. */
    printf("Batch (burst): %u | objects that did not fit in the queue: %" PRIu64 "\n",
           cfg.burst, did_not_fit);
    printf("Largest batch actually moved: enqueued %u, dequeued %u\n",
           maior_enq, two_cores ? ctx.maior_deq : maior_deq_local);
    if (two_cores)
        printf("Mode: 2 lcores (producer %u, consumer %u)\n", rte_lcore_id(), lcore_consumer);
    else
        printf("Mode: 1 lcore (%u), producer and consumer interleaved\n", rte_lcore_id());
    /* DRENAGEM: o que ficou no anel volta ao pool antes de qualquer relato.
     * Ver README.md secao 6.5 "Terminacao sob falha". */
    uint64_t descartados = 0;
    if (sem_progresso) {
        void *sobra[BURST_MAX];
        unsigned deq;
        while ((deq = rte_ring_dequeue_burst(ring, sobra, BURST_MAX, NULL)) > 0) {
            rte_mempool_put_bulk(pool, (void *const *)sobra, deq);
            descartados += deq;
        }
        printf("NO PROGRESS: no packet advanced for %" PRIu64 " ms; shutting down.\n",
               cfg.progresso_ms);
        printf("Objects dropped at shutdown: %" PRIu64 "\n", descartados);
    }
    printf("Free objects in the pool at the end: %u of %u\n", rte_mempool_avail_count(pool), pool_objs);
    relatar_mempool(pool);
    if (r.packets >= MIN_TO_MEASURE) {
        printf("Mean time: %.1f ns/packet\n", ns_per_packet);
        /* INGREDIENTES BRUTOS, so quando pedidos.
         *
         * A media acima sai com UMA casa decimal, e isso e deliberado: sobre
         * ~5 ns por pacote, publicar mais casas afirmaria uma precisao que uma
         * execucao nao sustenta -- o mesmo argumento que o README faz contra o
         * numero de `-n 10`.
         *
         * Mas uma casa quantiza em 2%, e o estudo que quer ligar taxa de miss a
         * TEMPO precisa comparar diferencas dessa mesma ordem. Emitir os tres
         * inteiros de onde a media sai resolve os dois lados: nao ha
         * arredondamento nenhum, e nenhuma precisao e afirmada -- quem analisa
         * deriva a que os dados sustentarem.
         *
         * Fora da variavel, a saida nao muda um byte, e os blocos publicados
         * que reproduzem esta saida continuam valendo. */
        if (relatar_bruto)
            printf("raw timing: cycles=%" PRIu64 " tsc_hz=%" PRIu64
                   " packets=%" PRIu64 "\n",
                   cycles, rte_get_tsc_hz(), r.packets);
        const double f = freq_ghz(cpu_do_lcore(rte_lcore_id()));
        if (f > 0.0)
            printf("Frequency of lcore %u: %.2f GHz (the time above varies with it)\n",
                   rte_lcore_id(), f);
    } else {
        printf("Mean time: %.1f ns/packet  <- NOT A MEASUREMENT\n", ns_per_packet);
        printf("  %" PRIu64 " packets are far too few: the cost of reading the clock is of the same\n",
               r.packets);
        printf("  order as the work measured. Use -n %u or more for a defensible number.\n",
               MIN_TO_MEASURE);
    }

    /* O INVARIANTE DO TOPICO, verificado aqui, onde o dado esta. O contrato
     * com a suite e o codigo de saida, nao a mensagem. Ver README.md
     * secao 5.2 "O contrato e o codigo de saida, nao a mensagem". */
    const unsigned free_objs = rte_mempool_avail_count(pool);
    const int intact = (free_objs == pool_objs);
    if (!intact)
        fprintf(stderr,
                "INVARIANT VIOLATED: %u of %u objects in the pool at the end. "
                "%u object(s) leaked: some return path did not give back to the pool.\n",
                free_objs, pool_objs, pool_objs - free_objs);

    rte_ring_free(ring);
    rte_mempool_free(pool);
    rte_eal_cleanup();
    /* Tres desfechos distintos: 0 integro, 1 invariante violado, 3 sem
     * progresso. Ver README.md secao 6.5 "Terminacao sob falha". */
    if (!intact)
        return EXIT_FAILURE;
    return sem_progresso ? 3 : EXIT_SUCCESS;
}
