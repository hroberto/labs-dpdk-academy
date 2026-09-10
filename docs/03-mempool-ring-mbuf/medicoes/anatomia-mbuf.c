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
 * USO: ./anatomia-mbuf -l 0 --in-memory --no-huge
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

#define N_MBUFS 1023u
#define CACHE_MBUF 32u

/* Imprime os quatro números que se confundem, sempre juntos e sempre na mesma
 * ordem: é assim que a relação entre eles fica visível. */
static void estado(const char *momento, const struct rte_mbuf *m)
{
    printf("  %-26s %8u %9u %9u %9u %9u %7u\n", momento, m->buf_len,
           rte_pktmbuf_headroom(m), m->data_len, m->pkt_len, rte_pktmbuf_tailroom(m), m->nb_segs);
}

static void cabecalho_estado(void)
{
    printf("  %-26s %8s %9s %9s %9s %9s %7s\n", "momento", "buf_len", "headroom", "data_len",
           "pkt_len", "tailroom", "nb_segs");
    printf("  %-26s %8s %9s %9s %9s %9s %7s\n", "--------------------------", "-------",
           "--------", "--------", "-------", "--------", "------");
}

int main(int argc, char **argv)
{
    if (rte_eal_init(argc, argv) < 0) {
        fprintf(stderr, "anatomia-mbuf: EAL nao inicializou: %s\n", rte_strerror(rte_errno));
        return 2;
    }

    struct rte_mempool *mp =
        rte_pktmbuf_pool_create("mbufs_anatomia", N_MBUFS, CACHE_MBUF, 0,
                                RTE_MBUF_DEFAULT_BUF_SIZE, (int)rte_socket_id());
    if (mp == NULL) {
        fprintf(stderr, "anatomia-mbuf: rte_pktmbuf_pool_create falhou: %s\n",
                rte_strerror(rte_errno));
        rte_eal_cleanup();
        return 1;
    }

    /* ---------------------------------------------------------------- */
    printf("\n== 1. O layout, com os numeros desta versao ==\n\n");
    printf("  sizeof(struct rte_mbuf) ..... %zu bytes (%zu linhas de cache de 64 B)\n",
           sizeof(struct rte_mbuf), sizeof(struct rte_mbuf) / 64);
    printf("  RTE_PKTMBUF_HEADROOM ........ %u bytes reservados ANTES dos dados\n",
           RTE_PKTMBUF_HEADROOM);
    printf("  RTE_MBUF_DEFAULT_DATAROOM ... %u bytes para o pacote\n", RTE_MBUF_DEFAULT_DATAROOM);
    printf("  RTE_MBUF_DEFAULT_BUF_SIZE ... %u bytes (dataroom + headroom)\n",
           RTE_MBUF_DEFAULT_BUF_SIZE);
    /* CUIDADO com o que cada numero inclui. rte_mempool_calc_obj_size recebe o
     * tamanho do elemento "without header and trailer" e devolve o total COM o
     * cabecalho do mempool. Rotular o resultado como "mbuf + buffer" atribuiria
     * ao mbuf bytes que sao do pool. */
    const unsigned elt = RTE_MBUF_DEFAULT_BUF_SIZE + (unsigned)sizeof(struct rte_mbuf);
    const unsigned obj = rte_mempool_calc_obj_size(elt, 0, NULL);
    printf("  elemento (mbuf + buffer) .... %u bytes\n", elt);
    printf("  + cabecalho do mempool ...... %u bytes\n", obj - elt);
    printf("  = objeto no pool ............ %u bytes\n", obj);
    printf("\n  Um pool de 8192 mbufs ocupa cerca de %.1f MiB so em objetos.\n",
           (double)obj * 8192.0 / (1024.0 * 1024.0));

    printf("\n  Deslocamento de cada campo dentro da estrutura:\n\n");
    printf("    %-14s %6s  %s\n", "campo", "offset", "linha de cache");
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

    printf("\n  A divisao em duas linhas de cache e deliberada, e a tabela acima a\n");
    printf("  mostra: TODOS os campos, menos um, cabem na primeira linha. O que\n");
    printf("  sobrou para a segunda foi `next`, que so tem valor em pacote\n");
    printf("  segmentado -- o caso menos comum. O proprio cabecalho do DPDK se\n");
    printf("  refere a ele como \"next pointer in the second cache line\".\n");
    printf("  Consequencia: um pacote de um segmento so toca uma linha por mbuf,\n");
    printf("  e a milhoes de pacotes por segundo isso e largura de banda de cache.\n");

    /* ---------------------------------------------------------------- */
    printf("\n== 2. Os quatro numeros, em movimento ==\n\n");
    printf("  Um pacote de 60 bytes, encapsulado e depois desencapsulado.\n");
    printf("  Repare em QUANDO cada numero muda -- e em quando nao muda.\n\n");

    struct rte_mbuf *m = rte_pktmbuf_alloc(mp);
    if (m == NULL) {
        fprintf(stderr, "anatomia-mbuf: rte_pktmbuf_alloc falhou\n");
        rte_mempool_free(mp);
        rte_eal_cleanup();
        return 1;
    }

    cabecalho_estado();
    estado("recem-alocado", m);

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
    estado("prepend(20) = tunel", m);

    rte_pktmbuf_adj(m, 20);
    estado("adj(20) = tira o tunel", m);

    rte_pktmbuf_trim(m, 4);
    estado("trim(4) = tira do fim", m);

    printf("\n  headroom encolhe a cada prepend e cresce a cada adj: e o espaco\n");
    printf("  ANTES dos dados. tailroom faz o oposto, no fim. buf_len nunca muda:\n");
    printf("  e o tamanho do buffer, nao do pacote.\n");

    /* ---------------------------------------------------------------- */
    printf("\n== 3. Pacote em varios segmentos ==\n\n");
    printf("  Aqui data_len e pkt_len DEIXAM de ser iguais, e e onde mais\n");
    printf("  codigo quebra: quem le data_len achando que e o tamanho do\n");
    printf("  pacote processa so o primeiro pedaco, em silencio.\n\n");

    struct rte_mbuf *seg = rte_pktmbuf_alloc(mp);
    if (seg != NULL) {
        char *d2 = rte_pktmbuf_append(seg, 100);
        if (d2 != NULL)
            memset(d2, 0xDD, 100);
        if (rte_pktmbuf_chain(m, seg) == 0) {
            cabecalho_estado();
            estado("cabeca da cadeia", m);
            printf("  %-26s %8u %9s %9u %9s %9s %7s\n", "segundo segmento", seg->buf_len, "-",
                   seg->data_len, "-", "-", "-");
            printf("\n  pkt_len (%u) = soma de todos os segmentos.\n", m->pkt_len);
            printf("  data_len (%u) = so o que cabe NESTE mbuf.\n", m->data_len);
            printf("  nb_segs (%u) = quantos mbufs formam o pacote.\n", m->nb_segs);
        }
    }

    /* ---------------------------------------------------------------- */
    printf("\n== 4. Quem libera o mbuf ==\n\n");
    printf("  refcnt do cabeca ............ %u\n", rte_mbuf_refcnt_read(m));
    printf("  objetos livres no pool ...... %u de %u\n", rte_mempool_avail_count(mp), N_MBUFS);

    rte_pktmbuf_free(m); /* libera a CADEIA inteira, não só o primeiro */

    printf("\n  apos rte_pktmbuf_free(cabeca):\n");
    printf("  objetos livres no pool ...... %u de %u\n", rte_mempool_avail_count(mp), N_MBUFS);
    printf("\n  Os DOIS mbufs voltaram com uma unica chamada: free() percorre a\n");
    printf("  cadeia. Liberar o segundo segmento tambem, por conta propria,\n");
    printf("  seria devolver duas vezes o mesmo objeto ao pool -- e o pool nao\n");
    printf("  reclama: ele passa a entregar o MESMO objeto a dois donos.\n\n");

    rte_mempool_free(mp);
    rte_eal_cleanup();
    return 0;
}
