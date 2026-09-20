/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Nível 1 — o que acontece quando o orçamento por pacote estoura.
 *
 * Este é o experimento do EIXO DE FALHA dos fundamentos (ROADMAP, Etapa 7.5).
 *
 * O módulo publica o orçamento por pacote — 67,2 ns para um quadro de 64 B em
 * 10 GbE — e usa esse número para justificar tudo o que vem depois. O que ele
 * não mostra é o que acontece do outro lado da linha. Este programa mostra, e a
 * resposta é menos gradual do que a intuição sugere.
 *
 * A INTUIÇÃO ERRADA
 *
 * "Se o sistema ficar 10% mais lento, a latência sobe 10%." Isso vale enquanto o
 * serviço é mais rápido que a chegada. Passando desse ponto, não existe "um
 * pouco sobrecarregado": a fila cresce sem limite, a latência cresce com o TEMPO
 * DE OPERAÇÃO em vez de com a carga, e o sistema só volta ao normal se a
 * chegada parar. É a diferença entre ρ < 1 e ρ ≥ 1, e ela é um degrau, não uma
 * rampa.
 *
 * O QUE ESTE PROGRAMA FAZ
 *
 * Sem rede e sem DPDK — como todo este módulo, cujas medições são sobre a
 * MÁQUINA, não sobre o framework. A chegada é simulada por prazo: um pacote a
 * cada `orçamento` nanossegundos, medido com CLOCK_MONOTONIC. O serviço é um
 * trabalho sintético calibrado, e a fila tem capacidade finita, como qualquer
 * fila real.
 *
 * Para cada nível de trabalho o programa reporta ρ, quantos pacotes foram
 * servidos, quantos foram DESCARTADOS por fila cheia, e a latência de fila —
 * mediana e p99 — dos que sobreviveram.
 *
 * POR QUE A FILA É FINITA, E POR QUE ISSO IMPORTA
 *
 * Uma fila infinita não descarta: ela transforma sobrecarga em latência
 * ilimitada, e some com o sintoma mais fácil de observar. Toda fila real é
 * finita — o anel de descritores da NIC, o rte_ring, o buffer do socket. Com ρ
 * ≥ 1 o sistema perde pacote; a única escolha é ONDE ele perde.
 *
 * USO: ./orcamento-estourado
 */
#define _GNU_SOURCE
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "clock_ns.h"
#include "statistics.h"

/* Orçamento de 10 GbE com quadro de 64 B, o número que o módulo publica:
 * 14 880 952 pacotes/s -> 67,2 ns por pacote. */
#define BUDGET_NS 67.2

#define QUEUE_CAPACITY 512u    /* ordem de grandeza de um anel de RX */
#define DURATION_MS 120          /* por nível de carga */
#define MAX_LATENCIES 200000


/* Trabalho sintético por pacote. `volatile` impede que o compilador elimine o
 * laço — sem isso, -O2 apagaria a função inteira e mediríamos zero. */
static void do_work(unsigned passos)
{
    static volatile uint64_t sink_var;
    uint64_t x = sink_var;
    for (unsigned i = 0; i < passos; i++)
        x = x * 6364136223846793005ULL + 1442695040888963407ULL;
    sink_var = x;
}

/* Tempo de serviço REAL por pacote, em ns — incluindo tudo que o laço de
 * serviço faz, não só `trabalhar()`.
 *
 * A primeira versão desta função cronometrava `trabalhar()` isolada, e isso
 * subestimava ρ: no laço de verdade cada pacote paga também duas leituras de
 * relógio e a contabilidade da fila, que somam dezenas de nanossegundos —
 * comparáveis ao próprio trabalho. Com ρ subestimado, a tabela mostrava perda
 * em "ρ = 0,68", número que não queria dizer nada.
 *
 * Medir em SATURAÇÃO resolve: roda o mesmo corpo do serviço o mais rápido que a
 * máquina permite e divide o tempo pelas voltas. O resultado é a capacidade de
 * fato, que é contra o que a chegada precisa ser comparada. */
static double saturated_service(unsigned passos)
{
    const int repet = 50000;
    double descarte[8];
    unsigned idx = 0;

    for (int i = 0; i < 1000; i++) /* aquece */
        do_work(passos);

    const double t0 = academy_now_ns_d();
    for (int i = 0; i < repet; i++) {
        const double arrived_at = academy_now_ns_d(); /* mesma leitura que o laço real faz */
        idx = (idx + 1) % 8;              /* mesma contabilidade de índice */
        do_work(passos);
        descarte[idx] = academy_now_ns_d() - arrived_at;
    }
    const double total = academy_now_ns_d() - t0;
    /* Impede que o compilador descarte `descarte[]`. */
    if (descarte[idx] < 0.0)
        printf("impossible\n");
    return total / repet;
}

struct resultado {
    double rho, service_ns;
    uint64_t offered, served, dropped;
    unsigned max_queue;
    double lat_median, lat_p99;
};

/* Uma corrida com chegada a cada ORCAMENTO_NS e serviço de `servico_ns`. */
static struct resultado correr(unsigned passos, double service_ns, double *lat)
{
    struct resultado r = {0};
    r.service_ns = service_ns;
    r.rho = service_ns / BUDGET_NS;

    /* Fila circular de instantes de chegada: guardar QUANDO o pacote chegou é o
     * que permite medir latência de fila sem relógio adicional. */
    static double fila[QUEUE_CAPACITY];
    unsigned cabeca = 0, cauda = 0, occupancy = 0;
    int n_lat = 0;

    const double t0 = academy_now_ns_d();
    const double fim = t0 + (double)DURATION_MS * 1e6;
    double next_arrival = t0;

    for (;;) {
        const double t = academy_now_ns_d();
        if (t >= fim)
            break;

        /* Chegadas vencidas desde a última volta. O laço trata rajada: se o
         * serviço demorou, várias chegadas venceram no intervalo. */
        while (next_arrival <= t) {
            r.offered++;
            if (occupancy < QUEUE_CAPACITY) {
                fila[cauda] = next_arrival;
                cauda = (cauda + 1) % QUEUE_CAPACITY;
                occupancy++;
                if (occupancy > r.max_queue)
                    r.max_queue = occupancy;
            } else {
                r.dropped++; /* fila cheia: o pacote morre aqui */
            }
            next_arrival += BUDGET_NS;
        }

        /* Serve um pacote, se houver. */
        if (occupancy > 0) {
            const double arrived_at = fila[cabeca];
            cabeca = (cabeca + 1) % QUEUE_CAPACITY;
            occupancy--;
            do_work(passos);
            if (n_lat < MAX_LATENCIES)
                lat[n_lat++] = academy_now_ns_d() - arrived_at;
            r.served++;
        }
    }

    const struct statistics e = summarize(lat, n_lat);
    r.lat_median = e.median;
    r.lat_p99 = e.p99;
    return r;
}

int main(void)
{
    print_provenance("orcamento-estourado");
    static double lat[MAX_LATENCIES];

    printf("== When the per-packet budget is blown ==\n\n");
    printf("  Budget: %.1f ns/packet (10 GbE, 64 B frame)\n", BUDGET_NS);
    printf("  Queue: %u slots | %d ms per load level\n\n", QUEUE_CAPACITY, DURATION_MS);

    /* Níveis escolhidos para cair dos dois lados de ρ = 1. Os passos são
     * convertidos em ρ pela calibração, não supostos. */
    static const unsigned levels[] = {8, 16, 24, 32, 40, 64, 96};

    printf("  %-8s %-10s %-7s %-11s %-11s %-9s %-10s %s\n", "steps", "service", "rho",
           "offered", "served", "dropped", "lat.med", "lat.p99");
    printf("  %-8s %-10s %-7s %-11s %-11s %-9s %-10s %s\n", "------", "-------", "---",
           "----------", "--------", "--------", "-------", "-------");

    int had_loss = 0;
    for (size_t i = 0; i < sizeof(levels) / sizeof(levels[0]); i++) {
        const double s = saturated_service(levels[i]);
        const struct resultado r = correr(levels[i], s, lat);
        const double loss_pct =
            r.offered ? 100.0 * (double)r.dropped / (double)r.offered : 0.0;
        if (r.dropped > 0)
            had_loss = 1;
        char perda[16];
        snprintf(perda, sizeof(perda), "%.1f%%", loss_pct);
        printf("  %-8u %-10.1f %-7.2f %-11" PRIu64 " %-11" PRIu64 " %-9s %-10.0f %.0f\n",
               levels[i], s, r.rho, r.offered, r.served, perda, r.lat_median, r.lat_p99);
    }

    printf("\n  How to read this table\n\n");
    printf("  rho = service / budget. Below 1 the consumer keeps up and the queue\n");
    printf("  stays practically empty: the observed latency is the service time\n");
    printf("  itself. Above 1 the queue fills to capacity and STAYS full -- every\n");
    printf("  packet now waits for the whole queue, and latency stops measuring\n");
    printf("  service and starts measuring queue depth.\n\n");
    printf("  THREE READINGS, AND THE THIRD IS THE OPERATIONAL ONE\n\n");
    printf("  1. Loss is a step, not a ramp. It stays at 0.0%% until rho is close\n");
    printf("     to 1 and only then appears. There is no stable regime of\n");
    printf("     \"slightly overloaded\": either the consumer keeps up, or the\n");
    printf("     excess is cumulative and the queue never recovers on its own.\n\n");
    printf("  2. The median latency jumps orders of magnitude at the crossing,\n");
    printf("     because on the other side it is a different quantity: before it\n");
    printf("     is service, after it is wait. A mean-latency plot crossing that\n");
    printf("     point does not show the same variable on both sides.\n\n");
    printf("  3. THE TAIL DEGRADES FIRST. Note the rows where loss is still\n");
    printf("     0.0%% and the median is still in the tens of ns, but the p99 has\n");
    printf("     already climbed two orders of magnitude. It is the only warning\n");
    printf("     that arrives BEFORE the damage: whoever monitors mean latency and\n");
    printf("     mean utilisation sees nothing, because both stay healthy. That is\n");
    printf("     why this material publishes percentiles, not means.\n\n");
    printf("  DESIGN CONSEQUENCE: sizing for the average load is not enough.\n");
    printf("  What decides survival is the margin over the PEAK, and the indicator\n");
    printf("  that warns in time is the high percentile -- not the mean.\n\n");
    printf("  LIMITATIONS OF THIS MEASUREMENT\n\n");
    printf("  Arrival here is PERIODIC (one packet every %.1f ns exactly). Real\n", BUDGET_NS);
    printf("  traffic arrives in bursts, and bursts bring loss forward: at the same\n");
    printf("  mean rate, an irregular arrival fills the queue at a lower rho than\n");
    printf("  this table shows. These numbers are therefore the OPTIMISTIC case.\n");
    printf("  The machine also has no pinned frequency, and the loop itself pays\n");
    printf("  two clock reads per packet -- already accounted for in `service`,\n");
    printf("  which is measured under saturation precisely for that reason.\n");

    if (!had_loss) {
        printf("\n  NOTE: no level dropped a packet on this machine. Either it is too\n");
        printf("  fast for the chosen steps, or the clock lacks resolution. Increase\n");
        printf("  the values in `levels[]` and repeat.\n");
    }
    return EXIT_SUCCESS;
}
