/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Nível 4 — o que o anel cobra por permitir vários produtores.
 *
 * O tópico prático de mempool afirma que o modo MP/MC tem "custo maior por
 * exigir operações atômicas de disputa". Isso é verdade, e nunca foi medido
 * aqui. Este programa mede — e o resultado tem uma sutileza que a afirmação
 * esconde: parte do custo aparece MESMO SEM DISPUTA, porque a instrução atômica
 * é executada de qualquer jeito.
 *
 * Medir sem disputa é deliberado. Com dois núcleos disputando, o que domina é a
 * migração da linha de cache entre eles — custo que os fundamentos já mediram
 * (§4.2.1) e que existiria com qualquer estrutura. O que se quer isolar aqui é o
 * preço da GENERALIDADE: quanto custa a fila estar preparada para vários
 * produtores quando existe só um.
 *
 * Mede também a diferença entre as duas famílias de função, que se confundem
 * pelo nome:
 *
 *   _bulk  -> "The number of objects enqueued, either 0 or n"  (tudo ou nada)
 *   _burst -> aceita parcial, e devolve quantos couberam
 *
 * A escolha errada aqui não aparece como lentidão: aparece como vazamento, no
 * dia em que a fila enche.
 *
 * USO: ./custo-anel -l 0 --in-memory --no-huge
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include <rte_eal.h>
#include <rte_errno.h>
#include <rte_lcore.h>
#include <rte_ring.h>

#include "statistics.h"

#define RING_SIZE 4096u
#define ITERATIONS 200000
#define BURST_MAX 128u

static struct rte_ring *ring_spsc;
static struct rte_ring *ring_mpmc;
static unsigned current_burst = 32u;
static struct rte_ring *ring_current;

/* Objetos falsos: o anel guarda ponteiros e nunca os desreferencia, então
 * qualquer endereço distinto serve. Usar um vetor real evita depender de
 * ponteiro inválido, que sanitizers reclamariam. */
static char objects[BURST_MAX];

static double now_ns(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec * 1e9 + (double)t.tv_nsec;
}

/* Um ciclo completo: enfileirar o lote e desenfileirar o lote. Medir só um dos
 * lados deixaria a fila crescendo ou vazia, e a medição mudaria de regime no
 * meio. */
static double m_ciclo_bulk(void)
{
    void *v[BURST_MAX];
    for (unsigned j = 0; j < current_burst; j++)
        v[j] = &objects[j];

    const int rounds = ITERATIONS / (int)current_burst;
    const double t0 = now_ns();
    for (int i = 0; i < rounds; i++) {
        if (rte_ring_enqueue_bulk(ring_current, v, current_burst, NULL) == 0)
            return -1.0; /* 0 = nada entrou: tudo ou nada */
        if (rte_ring_dequeue_bulk(ring_current, v, current_burst, NULL) == 0)
            return -1.0;
    }
    return (now_ns() - t0) / (rounds * (int)current_burst);
}

static double m_spsc(void)
{
    ring_current = ring_spsc;
    return m_ciclo_bulk();
}

static double m_mpmc(void)
{
    ring_current = ring_mpmc;
    return m_ciclo_bulk();
}

/* Demonstra a diferença de CONTRATO entre bulk e burst com a fila quase cheia.
 * Não é medição de tempo: é medição de comportamento. */
static void demonstrate_contract(void)
{
    struct rte_ring *r = rte_ring_create("anel_contrato", 16, (int)rte_socket_id(),
                                         RING_F_SP_ENQ | RING_F_SC_DEQ);
    if (r == NULL) {
        printf("  (nao foi possivel criar o anel da demonstracao)\n");
        return;
    }

    void *v[12];
    for (unsigned j = 0; j < 12; j++)
        v[j] = &objects[j];

    /* Anel de 16 guarda 15: um lugar fica reservado para distinguir cheio de
     * vazio. É a mesma razão do "2^q - 1" do mempool. */
    printf("  anel pedido com 16 posicoes; capacidade real: %u\n", rte_ring_get_capacity(r));
    printf("  (uma posicao fica reservada para distinguir cheio de vazio)\n\n");

    unsigned n = rte_ring_enqueue_burst(r, v, 12, NULL);
    printf("  enfileirados 12 em anel vazio ......... burst aceitou %u, livre=%u\n", n,
           rte_ring_free_count(r));

    /* Agora só há 3 lugares livres, e pedimos 12. */
    unsigned livre = rte_ring_free_count(r);
    unsigned b = rte_ring_enqueue_bulk(r, v, 12, NULL);
    printf("  pedindo mais 12 com apenas %u livres:\n", livre);
    printf("    _bulk  aceitou %u  <- tudo ou nada: NADA entrou\n", b);

    unsigned c = rte_ring_enqueue_burst(r, v, 12, NULL);
    printf("    _burst aceitou %u  <- parcial: %u entraram, %u ficaram de fora\n", c, c, 12 - c);

    printf("\n  A consequencia pratica esta no retorno do _burst: os %u objetos que\n", 12 - c);
    printf("  NAO entraram continuam sendo seus. Quem ignora esse numero e trata\n");
    printf("  todos como enfileirados perde a posse deles -- e, se vieram de um\n");
    printf("  mempool, o pool esvazia em silencio ate o pipeline parar.\n");

    rte_ring_free(r);
}

int main(int argc, char **argv)
{
    if (rte_eal_init(argc, argv) < 0) {
        fprintf(stderr, "custo-anel: EAL nao inicializou: %s\n", rte_strerror(rte_errno));
        return 2;
    }

    ring_spsc = rte_ring_create("anel_spsc", RING_SIZE, (int)rte_socket_id(),
                                RING_F_SP_ENQ | RING_F_SC_DEQ);
    ring_mpmc = rte_ring_create("anel_mpmc", RING_SIZE, (int)rte_socket_id(), 0);
    if (ring_spsc == NULL || ring_mpmc == NULL) {
        fprintf(stderr, "custo-anel: rte_ring_create falhou: %s\n", rte_strerror(rte_errno));
        rte_eal_cleanup();
        return 1;
    }

    const int n = samples(DEFAULT_SAMPLES_FIXED);

    printf("\n== O preco da generalidade do anel ==\n\n");
    printf("  anel de %u posicoes; ciclo completo enfileirar+desenfileirar\n", RING_SIZE);
    printf("  UM lcore, SEM disputa: o que se mede e a instrucao atomica, nao a\n");
    printf("  migracao de linha de cache entre nucleos\n");
    printf("  amostras: %d, cada uma com %d operacoes\n\n", n, ITERATIONS);

    printf("  %-8s %16s %16s %10s\n", "lote", "SP/SC (ns/obj)", "MP/MC (ns/obj)", "custo MP/MC");
    printf("  %-8s %16s %16s %10s\n", "-----", "--------------", "--------------", "-----------");
    static const unsigned bursts[] = {1, 8, 32, 128};
    for (size_t i = 0; i < sizeof(bursts) / sizeof(bursts[0]); i++) {
        current_burst = bursts[i];
        const struct statistics s = collect(m_spsc, n);
        const struct statistics m = collect(m_mpmc, n);
        printf("  %-8u %13.3f ns %13.3f ns %9.0f%%\n", bursts[i], s.median, m.median,
               s.median > 0 ? 100.0 * (m.median - s.median) / s.median : 0.0);
    }

    printf("\n  O custo do MP/MC nao desaparece por nao haver disputa: a operacao\n");
    printf("  atomica e executada de qualquer forma. O que o lote faz e diluir\n");
    printf("  esse custo fixo sobre mais objetos -- a mesma logica que ja apareceu\n");
    printf("  no tamanho de lote e na travessia entre nucleos.\n");

    printf("\n== _bulk e _burst nao sao sinonimos ==\n\n");
    demonstrate_contract();
    printf("\n");

    rte_ring_free(ring_spsc);
    rte_ring_free(ring_mpmc);
    rte_eal_cleanup();
    return 0;
}
