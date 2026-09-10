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
#include <stdio.h>
#include <stdlib.h>

#include "packet.h"

#define BURST_MAX 256u

struct config {
    uint64_t num_packets;
    unsigned burst;
};

static int parse_config(int argc, char **argv, struct config *cfg)
{
    int opt;
    cfg->num_packets = 10;
    cfg->burst = 32;
    optind = 1;
    while ((opt = getopt(argc, argv, "n:b:")) != -1) {
        switch (opt) {
        case 'n': cfg->num_packets = strtoull(optarg, NULL, 10); break;
        case 'b': cfg->burst = (unsigned)strtoul(optarg, NULL, 10); break;
        default:
            fprintf(stderr, "Uso: %s <EAL> -- [-n pacotes] [-b lote (1..%u)]\n", argv[0], BURST_MAX);
            return -1;
        }
    }
    if (cfg->burst == 0 || cfg->burst > BURST_MAX || cfg->num_packets == 0) {
        fprintf(stderr, "Parametros invalidos: -n deve ser > 0 e -b entre 1 e %u\n", BURST_MAX);
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
} __rte_cache_aligned;

/* Executado no lcore trabalhador quando há dois ou mais lcores. */
static int consumer_loop(void *arg)
{
    struct consumer_context *c = arg;
    struct packet *burst[BURST_MAX];

    while (c->r.packets < c->target) {
        const unsigned deq = rte_ring_dequeue_burst(c->ring, (void **)burst, c->burst, NULL);
        if (deq > 0) {
            packet_process_burst(burst, deq, &c->r);
            rte_mempool_put_bulk(c->pool, (void *const *)burst, deq);
        }
    }
    return 0;
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
        fprintf(stderr, "Erro ao inicializar a EAL: %s\n", rte_strerror(rte_errno));
        return EXIT_FAILURE;
    }
    argc -= consumed;
    argv += consumed;

    struct config cfg;
    if (parse_config(argc, argv, &cfg) < 0) {
        rte_eal_cleanup();
        return EXIT_FAILURE;
    }

    /* Pool de objetos fixos, alocado no nó NUMA do lcore principal.
     *
     * 4095 = 2^12 - 1, e isso é OTIMIZAÇÃO, não exigência da API: qualquer n
     * funciona. A documentação de rte_mempool_create diz que "the optimum size
     * (in terms of memory usage) for a mempool is when n is a power of two
     * minus one", porque o anel interno é dimensionado em potência de dois e um
     * elemento fica reservado para distinguir cheio de vazio. Pedir 4096
     * gastaria o dobro de anel para caber um objeto a mais. */
    const unsigned pool_objs = 4095;
    struct rte_mempool *pool = rte_mempool_create(
        "pool_pacotes", pool_objs, sizeof(struct packet),
        /* cache por lcore */ 64, /* private data */ 0,
        NULL, NULL, NULL, NULL, rte_socket_id(), 0);
    if (pool == NULL) {
        fprintf(stderr, "rte_mempool_create falhou: %s\n", rte_strerror(rte_errno));
        rte_eal_cleanup();
        return EXIT_FAILURE;
    }

    /* Fila de ponteiros entre produtor e consumidor (um de cada: SP/SC). */
    struct rte_ring *ring = rte_ring_create("fila", 1024, rte_socket_id(),
                                            RING_F_SP_ENQ | RING_F_SC_DEQ);
    if (ring == NULL) {
        fprintf(stderr, "rte_ring_create falhou: %s\n", rte_strerror(rte_errno));
        rte_mempool_free(pool);
        rte_eal_cleanup();
        return EXIT_FAILURE;
    }

    struct packet *burst_prod[BURST_MAX];
    struct packet *burst_cons[BURST_MAX];
    struct summary r = {0, 0};
    uint64_t produced = 0, did_not_fit = 0;

    /* Com dois ou mais lcores, o consumidor ganha núcleo próprio e a fila
     * passa a atravessar caches. Com um só, os dois papéis se alternam aqui. */
    const unsigned lcore_consumer = rte_get_next_lcore(rte_lcore_id(), 1, 0);
    const int two_cores = (lcore_consumer != RTE_MAX_LCORE);

    /* Aquecimento ANTES de lançar o consumidor e antes de t0: o que se quer
     * medir é regime permanente, não o custo de tocar a memória pela primeira
     * vez. Ver o comentário de aquecer(). */
    if (warmup(ring, pool, cfg.burst, pool_objs) != 0) {
        fprintf(stderr, "Aquecimento deixou o pool incompleto: %u de %u\n",
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
        ctx.r.bytes = 0;
        /* O retorno importa, e a falha mais provável é instrutiva: -EBUSY
         * significa que o lcore NÃO está em WAIT — ou seja, já recebeu trabalho
         * e ainda não o terminou. Ignorar isso deixaria o produtor publicando
         * para um consumidor que nunca foi lançado, e o sintoma seria uma
         * espera infinita, não um erro. Sobre os estados do lcore, ver o módulo
         * de runtime em docs/02-runtime-dpdk/. */
        const int launched = rte_eal_remote_launch(consumer_loop, &ctx, lcore_consumer);
        if (launched != 0) {
            fprintf(stderr, "rte_eal_remote_launch no lcore %u falhou: %s\n", lcore_consumer,
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
            produced += enq;
            /* Fila cheia: os que não couberam voltam ao pool (nunca vazam). */
            if (enq < n) {
#ifndef DPDK_ACADEMY_INJECT_LEAK
                rte_mempool_put_bulk(pool, (void *const *)&burst_prod[enq], n - enq);
#else
                /* VAZAMENTO DELIBERADO, compilado só na variante de teste.
                 *
                 * Existe porque o invariante do pool, verificado no fim de
                 * main(), precisa de um teste NEGATIVO: uma verificação que
                 * nunca falhou é indistinguível de uma que nunca dispara. A
                 * variante `pipeline_ring_vazado` remove esta devolução e o
                 * teste L2 exige que o programa detecte e saia com erro.
                 *
                 * É também o exercício 3 do README deste tópico, agora
                 * automatizado em vez de sugerido ao leitor. */
#endif
                did_not_fit += n - enq;
            }
        }

        /* --- Consumidor: só neste laço quando há um único lcore --- */
        if (!two_cores) {
            unsigned deq = rte_ring_dequeue_burst(ring, (void **)burst_cons, cfg.burst, NULL);
            if (deq > 0) {
                packet_process_burst(burst_cons, deq, &r);
                rte_mempool_put_bulk(pool, (void *const *)burst_cons, deq);
            }
        }
    }

    if (two_cores) {
        rte_eal_wait_lcore(lcore_consumer);
        r = ctx.r;
    }

    const uint64_t cycles = rte_rdtsc() - t0;
    const double ns_per_packet = (double)cycles * 1e9 / (double)rte_get_tsc_hz() / (double)r.packets;

    printf("Pacotes processados: %" PRIu64 "\n", r.packets);
    printf("Total de bytes: %" PRIu64 "\n", r.bytes);
    /* Conta OBJETOS, nao eventos: `n - enq` e quanto sobrou do lote. Rotular
     * isto de "tentativas" ja induziu a leitura errada de que a fila encheu
     * N vezes, quando N e o total de objetos que nao couberam. E o mesmo
     * numero que vaza na variante `pipeline_ring_vazado`, e e por isso que
     * os dois batem exatamente. */
    printf("Lote (burst): %u | objetos que nao couberam na fila: %" PRIu64 "\n",
           cfg.burst, did_not_fit);
    if (two_cores)
        printf("Modo: 2 lcores (produtor %u, consumidor %u)\n", rte_lcore_id(), lcore_consumer);
    else
        printf("Modo: 1 lcore (%u), produtor e consumidor alternados\n", rte_lcore_id());
    printf("Objetos livres no pool ao final: %u de %u\n", rte_mempool_avail_count(pool), pool_objs);
    if (r.packets >= MIN_TO_MEASURE) {
        printf("Tempo medio: %.1f ns/pacote\n", ns_per_packet);
        const double f = freq_ghz(rte_lcore_id());
        if (f > 0.0)
            printf("Frequencia do lcore %u: %.2f GHz (o tempo acima varia com ela)\n",
                   rte_lcore_id(), f);
    } else {
        printf("Tempo medio: %.1f ns/pacote  <- NAO E MEDICAO\n", ns_per_packet);
        printf("  %" PRIu64 " pacotes sao poucos demais: o custo de ler o relogio e da mesma\n",
               r.packets);
        printf("  ordem do trabalho medido. Use -n %u ou mais para um numero defensavel.\n",
               MIN_TO_MEASURE);
    }

    /* O INVARIANTE DO TÓPICO, verificado pelo próprio programa.
     *
     * Antes, quem verificava isto era o teste L2, procurando a substring
     * "4095 de 4095" na saída. Uma revisão externa apontou o problema: um
     * teste que casa texto valida a MENSAGEM, não a propriedade. Mudar o
     * formato do printf quebraria o teste sem que nada estivesse errado; e,
     * pior, um vazamento acompanhado de mudança de formato passaria despercebido.
     *
     * A verificação agora vive aqui, onde o dado está, e o programa sai com
     * código diferente de zero se falhar. O teste L2 passa a conferir o código
     * de saída — que é o contrato — e usa o texto apenas para diagnóstico. */
    const unsigned free_objs = rte_mempool_avail_count(pool);
    const int intact = (free_objs == pool_objs);
    if (!intact)
        fprintf(stderr,
                "INVARIANTE VIOLADO: %u de %u objetos no pool ao final. "
                "%u objeto(s) vazaram: algum caminho de retorno nao devolveu ao pool.\n",
                free_objs, pool_objs, pool_objs - free_objs);

    rte_ring_free(ring);
    rte_mempool_free(pool);
    rte_eal_cleanup();
    return intact ? EXIT_SUCCESS : EXIT_FAILURE;
}
