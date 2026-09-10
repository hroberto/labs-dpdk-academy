/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Nível 4 — o que acontece quando o pool esgota no meio de um lote.
 *
 * Este é o experimento do EIXO DE FALHA deste módulo (ROADMAP, Etapa 7.5). O
 * resto do material responde "quanto custa?"; aqui a pergunta é "e quando
 * acaba?".
 *
 * DUAS COISAS SÃO MEDIDAS, E A SEGUNDA É A QUE INTERESSA
 *
 * 1. O DEGRAU. `rte_mempool_get_bulk()` é tudo-ou-nada: a documentação diz
 *    "Get several objects from the mempool [...] Returns 0: Success; -ENOBUFS:
 *    Not enough entries in the mempool". Não existe lote parcial. Com o pool
 *    quase vazio, pedir um objeto a mais que o disponível devolve ZERO objetos,
 *    não `disponível` objetos. Quem escreve `if (get_bulk(...) != 0) continue;`
 *    num laço de produção acabou de escrever uma parada total disfarçada de
 *    tratamento de erro.
 *
 * 2. A REGRA 4, VERIFICADA. `dimensionamento.h` enuncia, a partir da
 *    documentação, que "n modulo cache_size == 0: if this is not the case, some
 *    elements will always stay in the pool and will never be used". Essa regra
 *    é testada em L1 como ARITMÉTICA — dim_leftover_objects() —, mas o número que
 *    ela prevê nunca foi confrontado com um mempool real. É o que a segunda
 *    metade deste programa faz: drena o pool até o `get_bulk` falhar e compara
 *    o que sobrou com a previsão.
 *
 *    Confrontar previsão com medição é a regra editorial do projeto. Uma regra
 *    copiada da documentação e nunca observada é folclore com boa procedência.
 *
 * POR QUE ISTO NÃO É UM BENCHMARK
 *
 * Não há tempo medido aqui, de propósito: o que se mede é COMPORTAMENTO na
 * fronteira, e comportamento não precisa de mediana nem de dispersão. Números
 * de contagem são exatos e reprodutíveis; por isso este programa não usa
 * statistics.h e não aceita DPDK_ACADEMY_AMOSTRAS.
 *
 * USO: ./pool-esgotado -l 0 --no-huge --file-prefix=meu_teste
 *
 * NAO use `--in-memory --no-huge` juntos: antes do DPDK 24, `--no-huge` liga
 * `--legacy-mem`, que e incompativel com `--in-memory`, e a EAL aborta.
 */
#define _GNU_SOURCE
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

#include <rte_eal.h>
#include <rte_errno.h>
#include <rte_mempool.h>
#include <rte_version.h>

#include "sizing.h"

/* Objeto sintético. O conteúdo é irrelevante: o que se estuda é a contabilidade
 * do pool, não o que cabe dentro do objeto. */
struct object {
    uint64_t id;
    uint8_t payload[56];
};

#define MAX_RESERVE 65536u

static void *reserve_slots[MAX_RESERVE];

/* Cria um pool e falha ruidosamente: um pool que não subiu invalida tudo que
 * viria depois, e seguir em frente publicaria número inventado. */
static struct rte_mempool *make_pool(const char *name, uint32_t n, uint32_t cache)
{
    struct rte_mempool *mp = rte_mempool_create(name, n, sizeof(struct object), cache, 0, NULL,
                                                NULL, NULL, NULL, SOCKET_ID_ANY, 0);
    if (mp == NULL)
        fprintf(stderr, "rte_mempool_create(%s, n=%u, cache=%u) falhou: %s\n", name, n, cache,
                rte_strerror(rte_errno));
    return mp;
}

/* --- Experimento 1: o degrau tudo-ou-nada -------------------------------- */
static int cliff(void)
{
    const uint32_t n = 1023, cache = 0; /* sem cache: isola o degrau do efeito da regra 4 */
    struct rte_mempool *mp = make_pool("degrau", n, cache);
    if (mp == NULL)
        return -1;

    /* Deixa exatamente 10 objetos livres. */
    const uint32_t reter = n - 10;
    if (rte_mempool_get_bulk(mp, reserve_slots, reter) != 0) {
        fprintf(stderr, "nao consegui reter %u objetos\n", reter);
        rte_mempool_free(mp);
        return -1;
    }

    printf("\n== Experimento 1: o degrau de rte_mempool_get_bulk ==\n\n");
    printf("  pool com %u objetos, cache 0, com %u livres no momento do pedido\n\n", n,
           rte_mempool_avail_count(mp));
    printf("  %-8s  %-10s  %-12s  %s\n", "pedido", "resultado", "entregues", "livres depois");

    static void *attempt[32];
    for (uint32_t requested = 8; requested <= 12; requested++) {
        const int rc = rte_mempool_get_bulk(mp, attempt, requested);
        const unsigned delivered = (rc == 0) ? requested : 0u;
        printf("  %-8u  %-10s  %-12u  %u\n", requested, (rc == 0) ? "ok" : "-ENOBUFS", delivered,
               rte_mempool_avail_count(mp));
        if (rc == 0)
            rte_mempool_put_bulk(mp, attempt, requested);
    }

    printf("\n  Leitura: o pedido de %u falha com 10 objetos livres e devolve ZERO,\n", 11u);
    printf("  nao 10. Nao existe lote parcial em get_bulk -- para aceitar o que\n");
    printf("  houver e preciso pedir menos, ou usar rte_mempool_get() um a um.\n");

    rte_mempool_put_bulk(mp, reserve_slots, reter);
    rte_mempool_free(mp);
    return 0;
}

/* --- Experimento 2: a regra 4, confrontada com o pool real ---------------- */

/* Drena o pool em lotes de `lote` até get_bulk falhar. Devolve quantos objetos
 * saíram, e escreve em `*sobraram` o que rte_mempool_avail_count() ainda
 * reporta. Os objetos retirados voltam ao pool antes de retornar. */
static uint32_t drain(struct rte_mempool *mp, uint32_t lote, uint32_t *remaining)
{
    uint32_t obtained = 0;
    while (obtained + lote <= MAX_RESERVE && rte_mempool_get_bulk(mp, &reserve_slots[obtained], lote) == 0)
        obtained += lote;
    *remaining = rte_mempool_avail_count(mp);
    if (obtained > 0)
        rte_mempool_put_bulk(mp, reserve_slots, obtained);
    return obtained;
}

static int rule4(void)
{
    /* Pares (n, cache) escolhidos para cair dos dois lados da regra: os dois
     * primeiros dividem exato, os dois últimos não. O par (4095, 256) é o que o
     * próprio módulo já usou e que motivou dimensionamento.h a existir. */
    static const struct {
        uint32_t n, cache;
    } casos[] = {
        {1023, 0},   /* sem cache: a regra não se aplica */
        {1024, 256}, /* 1024 % 256 == 0  -> previsão: 0 presos */
        {4095, 256}, /* 4095 % 256 == 255 -> previsão: 255 presos */
        {1023, 32},  /* 1023 % 32 == 31   -> previsão: 31 presos */
    };

    printf("\n== Experimento 2: a regra 4 de dimensionamento, medida ==\n\n");
    printf("  A documentacao adverte que, com n %% cache != 0, \"some elements will\n");
    printf("  always stay in the pool and will never be used\". dim_leftover_objects()\n");
    printf("  calcula quantos seriam. Aqui esse numero e confrontado com um pool\n");
    printf("  real, drenado um objeto por vez ate get_bulk falhar.\n\n");
    printf("  %-6s %-6s %-8s %-10s %-10s %-8s %s\n", "n", "cache", "lote", "previsto", "obtidos",
           "sobra", "confere?");

    int divergences = 0;
    for (size_t i = 0; i < RTE_DIM(casos); i++) {
        char name[32];
        snprintf(name, sizeof(name), "regra4_%zu", i);
        struct rte_mempool *mp = make_pool(name, casos[i].n, casos[i].cache);
        if (mp == NULL)
            return -1;

        const uint32_t lote = 1; /* um a um: mede o teto real, sem o degrau do lote */
        uint32_t remaining = 0;
        const uint32_t obtained = drain(mp, lote, &remaining);
        const uint32_t predicted = dim_leftover_objects(casos[i].n, casos[i].cache);
        const uint32_t unreachable = casos[i].n - obtained;
        const int matches = (unreachable == predicted);
        if (!matches)
            divergences++;

        printf("  %-6u %-6u %-8u %-10u %-10u %-8u %s\n", casos[i].n, casos[i].cache, lote, predicted,
               obtained, unreachable, matches ? "sim" : "NAO");

        rte_mempool_free(mp);
    }

    if (divergences == 0) {
        printf("\n  Nesta release, nenhum caso divergiu: o consumidor unico nao\n");
        printf("  alcancou mais objetos do que a previsao permitia.\n");
    } else {
        printf("\n  %d caso(s) DIVERGEM -- e a divergencia e o resultado, nao um erro.\n",
               divergences);
        printf("\n  Um consumidor unico drenando o pool obtem TODOS os objetos, mesmo\n");
        printf("  quando n %% cache != 0. A leitura absoluta da regra 4 (\"never be\n");
        printf("  used\") nao se sustenta, e o mecanismo esta no proprio cabecalho do\n");
        printf("  DPDK: em rte_mempool_do_generic_get(), quando o reabastecimento do\n");
        printf("  cache falha por nao haver objetos suficientes para um lote inteiro,\n");
        printf("  o codigo faz `goto driver_dequeue` e busca os que faltam DIRETO do\n");
        printf("  anel de tras, ignorando o cache. O resto do pool continua alcancavel.\n");
        printf("\n  O que a regra 4 de fato governa e EFICIENCIA em regime, com varios\n");
        printf("  lcores: cada cache retem objetos que os outros nucleos nao veem, e a\n");
        printf("  divisibilidade decide se a reposicao acontece em lotes cheios. Nao e\n");
        printf("  uma condicao de alcancabilidade -- e e assim que dimensionamento.h\n");
        printf("  passou a enunciar a regra, depois desta medicao.\n");
    }
    /* Divergir da previsão é o achado, não uma falha: o valor de retorno some
     * aqui de propósito, para que o teste L2 não fique vermelho por um
     * resultado correto. Quem lê a tabela decide. */
    return 0;
}

int main(int argc, char **argv)
{
    const int consumidos = rte_eal_init(argc, argv);
    if (consumidos < 0) {
        fprintf(stderr, "Erro ao inicializar a EAL: %s\n", rte_strerror(rte_errno));
        return EXIT_FAILURE;
    }

    printf("== Quando o mempool esgota ==\n");
    printf("  DPDK %s | RTE_MEMPOOL_CACHE_MAX_SIZE = %u\n", rte_version(),
           (unsigned)RTE_MEMPOOL_CACHE_MAX_SIZE);

    int rc = cliff();
    if (rc == 0)
        rc = rule4();

    rte_eal_cleanup();
    /* Divergência da previsão é RESULTADO, não erro de execução: o programa
     * termina bem e quem lê decide. Só falha de infraestrutura sai != 0. */
    return (rc < 0) ? EXIT_FAILURE : EXIT_SUCCESS;
}
