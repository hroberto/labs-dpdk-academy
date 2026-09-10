/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Assinante do feed — o processo SECUNDÁRIO.
 *
 * É um BINÁRIO DIFERENTE, com main() próprio, compilado separadamente. Ele não
 * recebe nada por socket, pipe ou fila do sistema: ele se ANEXA à memória que o
 * primário já criou, encontrando-a pelo nome da memzone, e lê os ticks
 * diretamente de lá. Nenhuma cópia atravessa a fronteira de processo.
 *
 * O que este programa mede: quanto tempo um tick leva entre ser publicado pelo
 * primário e ser observado aqui. Publica-se por percentis (§7 dos fundamentos:
 * latência não se reporta por média), porque num feed de mercado o requisito
 * está na cauda — o tick da abertura que chegou tarde é o que custa dinheiro.
 *
 * USO:
 *   ./feed-secundario -l 1 --file-prefix=academia --proc-type=secondary
 */
#define _GNU_SOURCE
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

#include <rte_cycles.h>
#include <rte_eal.h>
#include <rte_errno.h>
#include <rte_lcore.h>
#include <rte_memzone.h>
#include <rte_pause.h>

#include "statistics.h"
#include "feed.h"

/* O primário pode ainda estar subindo a EAL quando este processo já está de pé. */
#define ESPERA_MEMZONE_S 15

int main(int argc, char **argv)
{
    const int consumidos_pela_eal = rte_eal_init(argc, argv);
    if (consumidos_pela_eal < 0) {
        fprintf(stderr, "feed-secundario: EAL nao inicializou: %s\n", rte_strerror(rte_errno));
        fprintf(stderr, "  Confira: mesmo --file-prefix do primario, e --proc-type=secondary.\n");
        return 2;
    }

    if (rte_eal_process_type() != RTE_PROC_SECONDARY) {
        fprintf(stderr, "feed-secundario: este processo subiu como PRIMARIO.\n");
        fprintf(stderr, "  Faltou --proc-type=secondary, ou o primario nao estava no ar.\n");
        fprintf(stderr, "  Atencao: com --proc-type=auto a EAL vira primaria em silencio.\n");
        rte_eal_cleanup();
        return 2;
    }

    /* rte_memzone_lookup NÃO cria: um secundário não pode inicializar memória
     * compartilhada, só se anexar à que já existe. Se o primário ainda não
     * chegou a reservar a região, a busca falha — daí o laço. */
    const struct rte_memzone *mz = NULL;
    const uint64_t hz_local = rte_get_tsc_hz();
    const uint64_t limite = rte_rdtsc() + (uint64_t)ESPERA_MEMZONE_S * hz_local;
    while ((mz = rte_memzone_lookup(FEED_MEMZONE)) == NULL) {
        if (rte_rdtsc() > limite) {
            fprintf(stderr, "feed-secundario: memzone \"%s\" nao apareceu.\n", FEED_MEMZONE);
            rte_eal_cleanup();
            return 3;
        }
        rte_pause();
    }

    struct shared_feed *f = (struct shared_feed *)mz->addr;
    const uint64_t total = f->total_previsto;

    printf("\n== Assinante do feed (processo secundario) ==\n\n");
    printf("  memzone .............. \"%s\" (encontrada pelo NOME)\n", mz->name);
    printf("  endereco virtual ..... %p        <- compare com o do primario\n", mz->addr);
    printf("  endereco IOVA ........ 0x%" PRIx64 "\n", (uint64_t)mz->iova);
    printf("  lcore do consumidor .. %u (indice no no %d, no NUMA %u)\n", rte_lcore_id(),
           rte_lcore_to_cpu_id((int)rte_lcore_id()), rte_socket_id());
    printf("  ticks previstos ...... %" PRIu64 "\n\n", total);
    fflush(stdout);

    double *amostras_ns = (double *)malloc((size_t)total * sizeof(double));
    if (amostras_ns == NULL) {
        fprintf(stderr, "feed-secundario: sem memoria para %" PRIu64 " amostras\n", total);
        rte_eal_cleanup();
        return 1;
    }

    /* UM fluxo (a assinatura) e UM LIVRO POR INSTRUMENTO. A separação não é
     * estética: aplicar ticks de papéis diferentes ao mesmo livro compara a
     * compra de um com a venda de outro e produz spread negativo. */
    struct fluxo fl;
    fluxo_iniciar(&fl);

    struct order_book livros[FEED_INSTRUMENTOS];
    for (unsigned i = 0; i < FEED_INSTRUMENTOS; i++)
        order_book_init(&livros[i]);

    const double ns_por_ciclo = 1e9 / (double)f->tsc_hz;

    /* RESOLUÇÃO DO INSTRUMENTO.
     *
     * O consumidor descobre um tick novo ao sondar `publicados`. Entre duas
     * sondagens ele está cego, então a latência medida é sempre "tempo até a
     * PRÓXIMA sondagem perceber" — nunca o instante exato da chegada. O passo
     * dessa régua é o custo de uma iteração do laço, dominado por rte_pause().
     *
     * Medir e publicar esse passo não é firula: sem ele, a tabela abaixo exibe
     * casas decimais que o instrumento não tem, e o leitor conclui precisão que
     * não existe. Os valores medidos são LIMITE SUPERIOR da travessia. */
    const int calibragem = 20000;
    const uint64_t c0 = rte_rdtsc();
    for (int i = 0; i < calibragem; i++) {
        (void)atomic_load_explicit(&f->published, memory_order_acquire);
        rte_pause();
    }
    const double passo_ns = (double)(rte_rdtsc() - c0) * ns_por_ciclo / calibragem;

    /* Anuncia presença. release: o primário só deve ver este sinal depois de
     * tudo que este processo preparou estar de fato pronto. */
    atomic_store_explicit(&f->assinante_pronto, 1u, memory_order_release);

    uint64_t lidos = 0;
    uint64_t lacunas_vistas = 0;
    uint64_t degenerados = 0; /* amostras impossíveis: TSC desalinhado */

    while (lidos < total) {
        /* acquire: emparelha com o release do produtor. Garante que, ao ver o
         * índice, o conteúdo do tick correspondente já está visível. */
        const uint64_t disponiveis = atomic_load_explicit(&f->published, memory_order_acquire);

        if (lidos == disponiveis) {
            rte_pause(); /* nada novo: girar sem queimar a linha de cache */
            continue;
        }

        while (lidos < disponiveis) {
            const struct tick *t = &f->ring[lidos & FEED_MASCARA];

            /* A latência é medida ANTES de qualquer trabalho sobre o tick: o
             * que se quer é o custo da travessia, não o do livro. */
            const uint64_t agora = rte_rdtsc();
            /* Subtração sem sinal: se o TSC do núcleo do consumidor estivesse
             * ATRÁS do núcleo do produtor, isto viraria um número gigante em
             * vez de negativo. Contar os casos degenerados é o que permite
             * afirmar que os dois relógios estão alinhados. */
            const uint64_t delta = agora - t->tsc;
            if (delta == 0 || delta > f->tsc_hz) /* zero, ou mais de 1 segundo */
                degenerados++;
            amostras_ns[lidos] = (double)delta * ns_por_ciclo;

            /* Primeiro a integridade do FLUXO... */
            const enum fluxo_resultado r = fluxo_verificar(&fl, t->sequence);
            if (r == FLUXO_LACUNA)
                lacunas_vistas++;

            /* ...e só então o preço, no livro DO PAPEL que veio no tick. */
            if (r != FLUXO_DESCARTADO && t->instrument < FEED_INSTRUMENTOS)
                order_book_apply(&livros[t->instrument], t);

            lidos++;
        }

        atomic_store_explicit(&f->consumidos, lidos, memory_order_release);
    }

    const struct statistics lat = summarize(amostras_ns, (int)total);

    printf("  --- travessia entre processos, por tick (nanossegundos) ---\n\n");
    print_header_tail();
    print_row_tail("publicacao -> observacao", lat);
    printf("\n    resolucao do instrumento: %.1f ns (uma sondagem do consumidor).\n", passo_ns);
    printf("    amostras degeneradas: %" PRIu64 " de %" PRIu64 " %s\n", degenerados, total,
           degenerados == 0 ? "(TSC alinhado entre os dois nucleos)"
                            : "<- TSC DESALINHADO: medicao nao confiavel");
    printf("    Os valores acima sao LIMITE SUPERIOR: entre duas sondagens o\n");
    printf("    consumidor esta cego, entao a travessia real cabe dentro do\n");
    printf("    ultimo passo. Diferencas menores que %.1f ns nao sao mensuraveis aqui.\n",
           passo_ns);

    printf("\n  --- integridade da assinatura ---\n\n");
    printf("    ticks aceitos ........... %" PRIu64 "\n", fl.recebidos);
    printf("    descartados (repetidos) . %" PRIu64 "\n", fl.dropped);
    printf("    lacunas detectadas ...... %" PRIu64 " (o primario injetou %" PRIu64 ")\n",
           fl.gaps, f->lacunas_injetadas);
    printf("    eventos com lacuna ...... %" PRIu64 "\n", lacunas_vistas);

    printf("\n  --- livro por instrumento (topo de mercado) ---\n\n");
    printf("    %-12s %10s %10s %8s %9s\n", "instrumento", "compra", "venda", "spread",
           "aplicados");
    printf("    %-12s %10s %10s %8s %9s\n", "-----------", "------", "-----", "------",
           "---------");
    int cruzados = 0;
    for (unsigned i = 0; i < FEED_INSTRUMENTOS; i++) {
        const struct order_book *lv = &livros[i];
        char bid[16], ask[16], spread[16];
        snprintf(bid, sizeof(bid), "%s", lv->best_bid == LIVRO_SEM_PRECO ? "-" : "");
        if (lv->best_bid != LIVRO_SEM_PRECO)
            snprintf(bid, sizeof(bid), "%d", lv->best_bid);
        snprintf(ask, sizeof(ask), "%s", lv->best_ask == LIVRO_SEM_PRECO ? "-" : "");
        if (lv->best_ask != LIVRO_SEM_PRECO)
            snprintf(ask, sizeof(ask), "%d", lv->best_ask);
        const int32_t sp = livro_spread(lv);
        snprintf(spread, sizeof(spread), "%s", sp == LIVRO_SEM_PRECO ? "-" : "");
        if (sp != LIVRO_SEM_PRECO)
            snprintf(spread, sizeof(spread), "%d", sp);
        cruzados += order_book_crossed(lv);
        printf("    papel %-6u %10s %10s %8s %9" PRIu64 "\n", i, bid, ask, spread,
               lv->aplicados);
    }
    printf("\n    livros cruzados ......... %d %s\n", cruzados,
           cruzados == 0 ? "(nenhum: compra sempre abaixo da venda)"
                         : "<- ANOMALIA: investigar");
    printf("    precos em centavos; spread e venda menos compra\n");

    printf("\n  Leitura: o minimo se aproxima do custo de a linha de cache com o\n");
    printf("  tick migrar de um nucleo para o outro; a mediana e o p99 incluem\n");
    printf("  tambem a espera pela proxima sondagem. O p99 e o que um sistema de\n");
    printf("  producao precisa dimensionar: a media esconderia essa cauda.\n\n");

    free(amostras_ns);

    /* Avisa o primário de que já terminou, ANTES do próprio cleanup: é ele que
     * mantém o socket de controle com que este processo ainda vai conversar. */
    atomic_store_explicit(&f->assinante_terminou, 1u, memory_order_release);

    rte_eal_cleanup();
    return 0;
}
