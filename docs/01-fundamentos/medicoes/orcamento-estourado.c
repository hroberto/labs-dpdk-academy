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

#include "statistics.h"

/* Orçamento de 10 GbE com quadro de 64 B, o número que o módulo publica:
 * 14 880 952 pacotes/s -> 67,2 ns por pacote. */
#define BUDGET_NS 67.2

#define QUEUE_CAPACITY 512u    /* ordem de grandeza de um anel de RX */
#define DURATION_MS 120          /* por nível de carga */
#define MAX_LATENCIES 200000

static double now_ns(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec * 1e9 + (double)t.tv_nsec;
}

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

    const double t0 = now_ns();
    for (int i = 0; i < repet; i++) {
        const double arrived_at = now_ns(); /* mesma leitura que o laço real faz */
        idx = (idx + 1) % 8;              /* mesma contabilidade de índice */
        do_work(passos);
        descarte[idx] = now_ns() - arrived_at;
    }
    const double total = now_ns() - t0;
    /* Impede que o compilador descarte `descarte[]`. */
    if (descarte[idx] < 0.0)
        printf("impossivel\n");
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

    const double t0 = now_ns();
    const double fim = t0 + (double)DURATION_MS * 1e6;
    double next_arrival = t0;

    for (;;) {
        const double t = now_ns();
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
                lat[n_lat++] = now_ns() - arrived_at;
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
    static double lat[MAX_LATENCIES];

    printf("== Quando o orcamento por pacote estoura ==\n\n");
    printf("  Orcamento: %.1f ns/pacote (10 GbE, quadro de 64 B)\n", BUDGET_NS);
    printf("  Fila: %u posicoes | %d ms por nivel de carga\n\n", QUEUE_CAPACITY, DURATION_MS);

    /* Níveis escolhidos para cair dos dois lados de ρ = 1. Os passos são
     * convertidos em ρ pela calibração, não supostos. */
    static const unsigned levels[] = {8, 16, 24, 32, 40, 64, 96};

    printf("  %-8s %-10s %-7s %-11s %-11s %-9s %-10s %s\n", "passos", "servico", "rho",
           "oferecidos", "servidos", "perdidos", "lat.med", "lat.p99");
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

    printf("\n  Como ler esta tabela\n\n");
    printf("  rho = servico / orcamento. Abaixo de 1 o consumidor acompanha e a\n");
    printf("  fila fica praticamente vazia: a latencia observada e o proprio\n");
    printf("  tempo de servico. Acima de 1 a fila enche ate a capacidade e FICA\n");
    printf("  cheia -- todo pacote passa a esperar a fila inteira, e a latencia\n");
    printf("  deixa de medir o servico para medir a profundidade da fila.\n\n");
    printf("  TRES LEITURAS, E A TERCEIRA E A OPERACIONAL\n\n");
    printf("  1. A perda e um degrau, nao uma rampa. Ela fica em 0,0%% ate rho\n");
    printf("     perto de 1 e so entao aparece. Nao ha regime estavel de\n");
    printf("     \"levemente sobrecarregado\": ou o consumidor acompanha, ou o\n");
    printf("     excesso e cumulativo e a fila nunca se recupera sozinha.\n\n");
    printf("  2. A mediana da latencia pula ordens de grandeza na travessia,\n");
    printf("     porque do outro lado ela e outra grandeza: antes e servico,\n");
    printf("     depois e espera. Um grafico de latencia media atravessando esse\n");
    printf("     ponto nao mostra a mesma variavel nos dois lados.\n\n");
    printf("  3. A CAUDA DEGRADA PRIMEIRO. Repare nas linhas em que a perda ainda\n");
    printf("     e 0,0%% e a mediana ainda esta na casa das dezenas de ns, mas o\n");
    printf("     p99 ja subiu duas ordens de grandeza. E o unico aviso que chega\n");
    printf("     ANTES do dano: quem monitora media e utilizacao media nao ve\n");
    printf("     nada, porque as duas continuam saudaveis. Por isso este material\n");
    printf("     publica percentis, e nao media.\n\n");
    printf("  CONSEQUENCIA DE PROJETO: dimensionar para a carga media e\n");
    printf("  insuficiente. O que decide a sobrevivencia e a margem sobre o PICO,\n");
    printf("  e o indicador que avisa a tempo e o percentil alto -- nao a media.\n\n");
    printf("  LIMITACOES DESTA MEDICAO\n\n");
    printf("  A chegada aqui e PERIODICA (um pacote a cada %.1f ns exatos). Trafego\n", BUDGET_NS);
    printf("  real chega em rajada, e rajada antecipa a perda: com a mesma taxa\n");
    printf("  media, uma chegada irregular enche a fila em rho menor que o desta\n");
    printf("  tabela. Os numeros daqui sao, portanto, o caso OTIMISTA.\n");
    printf("  A maquina tambem nao tem frequencia fixada, e o proprio laco paga\n");
    printf("  duas leituras de relogio por pacote -- ja contabilizadas em\n");
    printf("  `servico`, que e medido em saturacao justamente por isso.\n");

    if (!had_loss) {
        printf("\n  NOTA: nenhum nivel perdeu pacote nesta maquina. Ou ela e rapida\n");
        printf("  demais para os passos escolhidos, ou o relogio nao tem resolucao\n");
        printf("  suficiente. Aumente os valores em `niveis[]` e repita.\n");
    }
    return EXIT_SUCCESS;
}
