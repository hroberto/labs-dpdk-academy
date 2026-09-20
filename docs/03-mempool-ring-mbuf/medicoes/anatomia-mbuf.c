/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Nível 4 — a anatomia do mbuf, observada em vez de descrita.
 *
 * O `rte_mbuf` é a estrutura que carrega um pacote no DPDK, e é onde mais gente
 * se perde. O motivo é que ela tem QUATRO números que parecem redundantes e não
 * são: `buf_len`, `data_off`, `data_len` e `pkt_len`. Confundi-los produz
 * corrupção silenciosa — o pacote sai com bytes a mais, a menos, ou com lixo no
 * começo, e nada acusa erro.
 *
 * Este programa não descreve o layout: ele o imprime, com os deslocamentos reais
 * da versão instalada, e depois mostra os quatro números mudando conforme o
 * pacote é manipulado.
 *
 * Três coisas que ele demonstra e que só se entendem vendo:
 *
 *   1. HEADROOM — por que existe espaço reservado ANTES dos dados, e o que
 *      acontece com quem encapsula um pacote sem ele.
 *   2. SEGMENTAÇÃO — um pacote pode ocupar vários mbufs encadeados, e aí
 *      `data_len` e `pkt_len` deixam de ser iguais. É a fonte clássica de bug
 *      em código que só foi testado com pacote pequeno.
 *   3. CONTAGEM DE REFERÊNCIA — quem libera o mbuf, e por que liberar duas
 *      vezes é fácil.
 *
 * USO: ./anatomia-mbuf -l 0 --no-huge --file-prefix=meu_teste
 */
#define _GNU_SOURCE
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#include <rte_eal.h>
#include <rte_errno.h>
#include <rte_lcore.h>
#include <rte_mbuf.h>
#include <rte_mempool.h>
#include "statistics.h"

#define N_MBUFS 1023u
#define CACHE_MBUF 32u

/* Imprime os quatro números que se confundem, sempre juntos e sempre na mesma
 * ordem: é assim que a relação entre eles fica visível. */
static void estado(const char *momento, const struct rte_mbuf *m)
{
    printf("  %-30s %8u %9u %9u %9u %9u %7u\n", momento, m->buf_len,
           rte_pktmbuf_headroom(m), m->data_len, m->pkt_len, rte_pktmbuf_tailroom(m), m->nb_segs);
}

static void cabecalho_estado(void)
{
    printf("  %-30s %8s %9s %9s %9s %9s %7s\n", "step", "buf_len", "headroom", "data_len",
           "pkt_len", "tailroom", "nb_segs");
    printf("  %-30s %8s %9s %9s %9s %9s %7s\n", "------------------------------", "-------",
           "--------", "--------", "-------", "--------", "------");
}

int main(int argc, char **argv)
{
    print_provenance("anatomia-mbuf");
    if (rte_eal_init(argc, argv) < 0) {
        fprintf(stderr, "anatomia-mbuf: EAL did not initialise: %s\n", rte_strerror(rte_errno));
        return 2;
    }

    struct rte_mempool *mp =
        rte_pktmbuf_pool_create("mbufs_anatomia", N_MBUFS, CACHE_MBUF, 0,
                                RTE_MBUF_DEFAULT_BUF_SIZE, (int)rte_socket_id());
    if (mp == NULL) {
        fprintf(stderr, "anatomia-mbuf: rte_pktmbuf_pool_create failed: %s\n",
                rte_strerror(rte_errno));
        rte_eal_cleanup();
        return 1;
    }

    /* ---------------------------------------------------------------- */
    printf("\n== 1. The layout, with this version's numbers ==\n\n");
    printf("  sizeof(struct rte_mbuf) ..... %zu bytes (%zu cache lines of 64 B)\n",
           sizeof(struct rte_mbuf), sizeof(struct rte_mbuf) / 64);
    printf("  RTE_PKTMBUF_HEADROOM ........ %u bytes reserved BEFORE the data\n",
           RTE_PKTMBUF_HEADROOM);
    printf("  RTE_MBUF_DEFAULT_DATAROOM ... %u bytes for the packet\n", RTE_MBUF_DEFAULT_DATAROOM);
    printf("  RTE_MBUF_DEFAULT_BUF_SIZE ... %u bytes (dataroom + headroom)\n",
           RTE_MBUF_DEFAULT_BUF_SIZE);
    /* CUIDADO com o que cada numero inclui. rte_mempool_calc_obj_size recebe o
     * tamanho do elemento "without header and trailer" e devolve o total COM o
     * cabecalho do mempool. Rotular o resultado como "mbuf + buffer" atribuiria
     * ao mbuf bytes que sao do pool. */
    const unsigned elt = RTE_MBUF_DEFAULT_BUF_SIZE + (unsigned)sizeof(struct rte_mbuf);
    const unsigned obj = rte_mempool_calc_obj_size(elt, 0, NULL);
    printf("  element (mbuf + buffer) ..... %u bytes\n", elt);
    printf("  + mempool header ............ %u bytes\n", obj - elt);
    printf("  = object in the pool ........ %u bytes\n", obj);
    printf("\n  A pool of 8192 mbufs takes about %.1f MiB in objects alone.\n",
           (double)obj * 8192.0 / (1024.0 * 1024.0));

    printf("\n  Offset of each field inside the structure:\n\n");
    printf("    %-14s %6s  %s\n", "field", "offset", "cache line");
    printf("    %-14s %6s  %s\n", "-----", "------", "--------------");
    struct { const char *name; size_t off; } campos[] = {
        {"buf_addr", offsetof(struct rte_mbuf, buf_addr)},
        {"data_off", offsetof(struct rte_mbuf, data_off)},
        {"refcnt", offsetof(struct rte_mbuf, refcnt)},
        {"nb_segs", offsetof(struct rte_mbuf, nb_segs)},
        {"port", offsetof(struct rte_mbuf, port)},
        {"pkt_len", offsetof(struct rte_mbuf, pkt_len)},
        {"data_len", offsetof(struct rte_mbuf, data_len)},
        {"buf_len", offsetof(struct rte_mbuf, buf_len)},
        {"pool", offsetof(struct rte_mbuf, pool)},
        {"next", offsetof(struct rte_mbuf, next)},
    };
    for (size_t i = 0; i < sizeof(campos) / sizeof(campos[0]); i++)
        printf("    %-14s %6zu  %zu\n", campos[i].name, campos[i].off, campos[i].off / 64);

    printf("\n  The split across two cache lines is deliberate, and the table above\n");
    printf("  shows it: ALL fields but one fit in the first line. What spilled\n");
    printf("  into the second was `next`, which only matters for a segmented\n");
    printf("  packet -- the less common case. The DPDK header itself refers to\n");
    printf("  it as \"next pointer in the second cache line\".\n");
    printf("  Consequence: a single-segment packet touches only one line per mbuf,\n");
    printf("  and at millions of packets per second that is cache bandwidth.\n");

    /* ---------------------------------------------------------------- */
    printf("\n== 2. The four numbers, in motion ==\n\n");
    printf("  A 60-byte packet, encapsulated and then decapsulated.\n");
    printf("  Note WHEN each number changes -- and when it does not.\n\n");

    struct rte_mbuf *m = rte_pktmbuf_alloc(mp);
    if (m == NULL) {
        fprintf(stderr, "anatomia-mbuf: rte_pktmbuf_alloc failed\n");
        rte_mempool_free(mp);
        rte_eal_cleanup();
        return 1;
    }

    cabecalho_estado();
    estado("freshly allocated", m);

    char *dados = rte_pktmbuf_append(m, 60);
    if (dados != NULL)
        memset(dados, 0xAA, 60);
    estado("append(60) = payload", m);

    /* Encapsular = escrever ANTES do que já existe. É exatamente para isto que
     * o headroom foi reservado na alocação: sem ele, seria preciso copiar o
     * pacote inteiro para abrir espaço. */
    char *cabecalho = rte_pktmbuf_prepend(m, 14);
    if (cabecalho != NULL)
        memset(cabecalho, 0xBB, 14);
    estado("prepend(14) = ethernet", m);

    char *externo = rte_pktmbuf_prepend(m, 20);
    if (externo != NULL)
        memset(externo, 0xCC, 20);
    estado("prepend(20) = tunnel", m);

    rte_pktmbuf_adj(m, 20);
    estado("adj(20) = strips the tunnel", m);

    rte_pktmbuf_trim(m, 4);
    estado("trim(4) = strips from the end", m);

    printf("\n  headroom shrinks on every prepend and grows on every adj: it is the\n");
    printf("  space BEFORE the data. tailroom does the opposite, at the end. buf_len\n");
    printf("  never changes: it is the size of the buffer, not of the packet.\n");

    /* ---------------------------------------------------------------- */
    printf("\n== 3. Packet in several segments ==\n\n");
    printf("  Here data_len and pkt_len STOP being equal, and this is where most\n");
    printf("  code breaks: whoever reads data_len thinking it is the packet size\n");
    printf("  processes only the first chunk, silently.\n\n");

    struct rte_mbuf *seg = rte_pktmbuf_alloc(mp);
    if (seg != NULL) {
        char *d2 = rte_pktmbuf_append(seg, 100);
        if (d2 != NULL)
            memset(d2, 0xDD, 100);
        if (rte_pktmbuf_chain(m, seg) == 0) {
            cabecalho_estado();
            estado("head of the chain", m);
            printf("  %-30s %8u %9s %9u %9s %9s %7s\n", "second segment", seg->buf_len, "-",
                   seg->data_len, "-", "-", "-");
            printf("\n  pkt_len (%u) = sum of all segments.\n", m->pkt_len);
            printf("  data_len (%u) = only what fits in THIS mbuf.\n", m->data_len);
            printf("  nb_segs (%u) = how many mbufs make up the packet.\n", m->nb_segs);
        }
    }

    /* ---------------------------------------------------------------- */
    printf("\n== 4. Who frees the mbuf ==\n\n");
    printf("  refcnt of the head .......... %u\n", rte_mbuf_refcnt_read(m));
    printf("  free objects in the pool .... %u of %u\n", rte_mempool_avail_count(mp), N_MBUFS);

    rte_pktmbuf_free(m); /* libera a CADEIA inteira, não só o primeiro */

    printf("\n  after rte_pktmbuf_free(head):\n");
    printf("  free objects in the pool .... %u of %u\n", rte_mempool_avail_count(mp), N_MBUFS);
    printf("\n  BOTH mbufs came back with a single call: free() walks the chain.\n");
    printf("  Freeing the second segment as well, on its own, would return the\n");
    printf("  same object to the pool twice -- and the pool does not complain:\n");
    printf("  it starts handing the SAME object to two owners.\n\n");

    rte_mempool_free(mp);
    rte_eal_cleanup();
    return 0;
}
