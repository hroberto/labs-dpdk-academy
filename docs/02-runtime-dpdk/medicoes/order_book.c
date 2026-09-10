/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Implementação do fluxo e do livro de nível 1. Sem DPDK, sem alocação, sem
 * I/O: é a parte do exemplo de market data que se testa em L1.
 */
#include "order_book.h"

/* ---------------------------- fluxo ---------------------------- */

void fluxo_iniciar(struct fluxo *f)
{
    f->ultima_sequencia = 0;
    f->recebidos = 0;
    f->gaps = 0;
    f->dropped = 0;
}

enum fluxo_resultado fluxo_verificar(struct fluxo *f, uint64_t sequence)
{
    /* Repetição de retransmissão: o feed reenvia o que já mandou. Aplicar de
     * novo corromperia a contagem e poderia reintroduzir um preço vencido. */
    if (f->recebidos > 0 && sequence <= f->ultima_sequencia) {
        f->dropped++;
        return FLUXO_DESCARTADO;
    }

    /* Salto na sequência: um ou mais datagramas se perderam. O tick recebido
     * continua válido e é aceito — o que se perde é a GARANTIA de que a
     * assinatura reflete tudo que a bolsa publicou. Contabilizar isso é
     * obrigatório: é o sinal de que a estratégia opera sobre dado incompleto.
     *
     * A primeira sequência vista NÃO conta como perda: assinar o feed no meio
     * do pregão é normal, e o que veio antes nunca foi endereçado a nós. */
    enum fluxo_resultado r = FLUXO_OK;
    if (f->recebidos > 0 && sequence > f->ultima_sequencia + 1) {
        f->gaps += sequence - f->ultima_sequencia - 1;
        r = FLUXO_LACUNA;
    }

    f->ultima_sequencia = sequence;
    f->recebidos++;
    return r;
}

/* ---------------------------- livro ---------------------------- */

void order_book_init(struct order_book *l)
{
    l->best_bid = LIVRO_SEM_PRECO;
    l->best_ask = LIVRO_SEM_PRECO;
    l->aplicados = 0;
}

void order_book_apply(struct order_book *l, const struct tick *t)
{
    /* Nível 1: a atualização SUBSTITUI o lado. Não se compara com o valor
     * anterior — o feed já publica o melhor preço vigente daquele lado, e
     * guardar o máximo histórico deixaria no topo uma oferta que já saiu. */
    int32_t *lado = (t->lado == LIVRO_COMPRA) ? &l->best_bid : &l->best_ask;

    /* Quantidade zero é cancelamento: o lado deixa de ter preço. Tratar como
     * preço normal deixaria uma oferta fantasma no topo do livro. */
    *lado = (t->quantity == 0) ? LIVRO_SEM_PRECO : t->price;

    l->aplicados++;
}

int32_t livro_spread(const struct order_book *l)
{
    if (l->best_bid == LIVRO_SEM_PRECO || l->best_ask == LIVRO_SEM_PRECO)
        return LIVRO_SEM_PRECO;
    return l->best_ask - l->best_bid;
}

int order_book_crossed(const struct order_book *l)
{
    if (l->best_bid == LIVRO_SEM_PRECO || l->best_ask == LIVRO_SEM_PRECO)
        return 0; /* faltando um lado, não há o que cruzar */
    return l->best_bid >= l->best_ask;
}
