/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Livro de ofertas mínimo — a LÓGICA do exemplo de market data, sem DPDK.
 *
 * Este cabeçalho não inclui nada do DPDK de propósito. O objetivo é que a regra
 * de negócio seja testável em L1, com GoogleTest, sem subir a EAL. O runtime
 * entra em feed-primario.c e feed-secundario.c; aqui não.
 *
 * DUAS COISAS SEPARADAS, E A SEPARACAO E O CONCEITO
 *
 * `struct fluxo` e do TRANSPORTE -- a numeracao de sequencia vale para a
 * assinatura inteira. `struct order_book` e do INSTRUMENTO -- cada papel tem
 * seu topo de livro. Este arquivo implementa livro de NIVEL 1: a atualizacao
 * SUBSTITUI o valor do lado.
 *
 * O porque de cada decisao -- sem ponteiro, preco inteiro, padding explicito,
 * e por que aplicar semantica de substituicao a um feed de profundidade produz
 * um livro errado que continua funcionando -- esta no README.md secao 8.1
 * "O dado que atravessa a fronteira de processo".
 */
#ifndef DPDK_ACADEMY_ORDER_BOOK_H
#define DPDK_ACADEMY_ORDER_BOOK_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LIVRO_COMPRA 0
#define LIVRO_VENDA 1

/* Sem preço conhecido para este lado. Zero não serve: zero é um preço. */
#define LIVRO_SEM_PRECO INT32_MIN

/* Uma atualização do feed.
 *
 * O preço é INTEIRO, em centavos. Livro de ofertas não usa ponto flutuante:
 * 0,1 + 0,2 != 0,3 em binário, e um centavo de erro em comparação de preço é
 * uma ordem executada no nível errado. Bolsas publicam preço como inteiro com
 * expoente declarado justamente por isso.
 *
 * O layout é fixo e sem ponteiros porque esta estrutura ATRAVESSA A FRONTEIRA
 * DE PROCESSO: ela vive em memória compartilhada da EAL, escrita pelo primário
 * e lida pelo secundário. Um ponteiro aqui seria válido só de um lado.
 */
struct tick {
    uint64_t sequence;   /* numeração do FLUXO, contígua e crescente */
    uint64_t tsc;         /* carimbo de publicação, em ciclos (rte_rdtsc) */
    uint32_t instrument; /* identificador do papel */
    int32_t price;        /* em centavos */
    uint32_t quantity;  /* zero significa cancelamento deste lado */
    uint8_t lado;         /* LIVRO_COMPRA ou LIVRO_VENDA */
    uint8_t _reservado[3];
};

/* ------------------------------------------------------------------ */
/* O FLUXO: integridade da assinatura, independente de qual papel veio */
/* ------------------------------------------------------------------ */

struct fluxo {
    uint64_t ultima_sequencia;
    uint64_t recebidos;   /* ticks aceitos */
    uint64_t gaps;     /* datagramas que o feed pulou (perda) */
    uint64_t dropped; /* repetidos ou fora de ordem */
};

enum fluxo_resultado {
    FLUXO_OK = 0,
    FLUXO_LACUNA,    /* aceito, mas houve perda antes dele */
    FLUXO_DESCARTADO /* sequência já vista: não aceitar */
};

void fluxo_iniciar(struct fluxo *f);

/* Avalia a sequência de um tick e devolve o que aconteceu.
 *
 * Semântica de perda igual à de um feed multicast real: sequência maior que a
 * esperada significa que um datagrama se perdeu no caminho — o tick vale, mas a
 * assinatura passa a estar incompleta. Sequência já vista é repetição de
 * retransmissão e não pode ser aplicada duas vezes.
 *
 * Só atualiza o estado quando o resultado NÃO é FLUXO_DESCARTADO.
 */
enum fluxo_resultado fluxo_verificar(struct fluxo *f, uint64_t sequence);

/* ------------------------------------------------------ */
/* O LIVRO: topo de mercado de UM instrumento (nível 1)    */
/* ------------------------------------------------------ */

struct order_book {
    int32_t best_bid;
    int32_t best_ask;
    uint64_t aplicados;
};

void order_book_init(struct order_book *l);

/* Aplica a atualização ao lado indicado, substituindo o valor anterior.
 * Quantidade zero cancela o lado, que volta a LIVRO_SEM_PRECO. */
void order_book_apply(struct order_book *l, const struct tick *t);

/* Diferença entre a melhor venda e a melhor compra, em centavos.
 * Devolve LIVRO_SEM_PRECO enquanto algum dos lados não tiver preço. */
int32_t livro_spread(const struct order_book *l);

/* Verdadeiro quando a melhor compra é maior ou igual à melhor venda.
 *
 * Um livro cruzado é anomalia, não estado normal: significa que alguém pagaria
 * mais do que outro alguém aceita receber, e a negociação deveria ter ocorrido.
 * Em produção acontece por perda de mensagem, atraso, ou erro de aplicação —
 * exatamente os três casos que este módulo ensina a detectar. Publicar o
 * indicador é melhor do que confiar que ele nunca ocorre.
 */
int order_book_crossed(const struct order_book *l);

/* Veredito de validade da assinatura inteira, a partir das duas condicoes que a
 * invalidam: `cruzados` invalida o LIVRO, `degenerados` invalida a MEDICAO
 * publicada junto dele.
 *
 * Recebe os numeros APURADOS em vez de le-los: um mutante que trocasse esta
 * decisao por "sempre valido" sobrevivia a suite enquanto ela lia o estado
 * sozinha.
 *
 * O limiar e contagem absoluta, nao fracao, e o valor saiu de vinte sessoes
 * arquivadas. Ver README.md secao 9.1 "O criterio de validade da assinatura, e
 * como o limiar foi calibrado". */
#define FEED_DEGENERADOS_MAX 2ULL

/* Separada de `feed_assinatura_valida` porque o limiar é a parte que se quer
 * exercitar sozinha, nas bordas e sem depender de livro nenhum. */
static inline int feed_degenerados_toleraveis(unsigned long long degenerados)
{
    return degenerados <= FEED_DEGENERADOS_MAX;
}

static inline int feed_assinatura_valida(int cruzados, unsigned long long degenerados)
{
    return cruzados == 0 && feed_degenerados_toleraveis(degenerados);
}

#ifdef __cplusplus
}
#endif

#endif /* DPDK_ACADEMY_LIVRO_H */
