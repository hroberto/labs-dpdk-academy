/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Livro de ofertas mínimo — a LÓGICA do exemplo de market data, sem DPDK.
 *
 * Este cabeçalho não inclui nada do DPDK de propósito. O objetivo é que a regra
 * de negócio seja testável em L1, com GoogleTest, sem subir a EAL. O runtime
 * entra em feed-primario.c e feed-secundario.c; aqui não.
 *
 * DUAS COISAS SEPARADAS, E A SEPARAÇÃO É O CONCEITO
 *
 * É tentador guardar tudo numa estrutura só. Seria errado, e o erro aparece na
 * primeira execução com mais de um papel:
 *
 *   - A NUMERAÇÃO DE SEQUÊNCIA é do FLUXO. O feed numera os datagramas que
 *     envia, não as atualizações de cada papel. Um salto na sequência significa
 *     perda no transporte, e vale para a assinatura inteira. É `struct fluxo`.
 *
 *   - O PREÇO é do INSTRUMENTO. Cada papel tem seu próprio topo de livro.
 *     Misturar papéis num livro só produz um "melhor compra" de um papel contra
 *     um "melhor venda" de outro — e um spread negativo, que não existe.
 *     É `struct livro`, um por instrumento.
 *
 * Protocolos reais de mercado fazem exatamente essa separação: o MoldUDP64, por
 * exemplo, numera a SESSÃO, e as mensagens de dentro carregam o identificador
 * do papel.
 *
 * QUAL MODELO DE LIVRO ESTE ARQUIVO IMPLEMENTA
 *
 * Um livro de **nível 1** (*top of book*): o feed publica, a cada atualização, o
 * melhor preço vigente de um dos lados, e a atualização SUBSTITUI o valor
 * anterior daquele lado. É o modelo de feeds de melhor oferta, e é o que
 * corresponde ao dado que feed-primario.c gera.
 *
 * Um livro de **profundidade** (níveis 2 e 3) é outra estrutura: guarda todas as
 * ofertas vivas, e o melhor preço é o máximo das compras e o mínimo das vendas,
 * com remoção quando uma oferta é cancelada ou executada. Não está aqui, e a
 * diferença importa: aplicar semântica de substituição a um feed de
 * profundidade, ou vice-versa, produz um livro errado que ainda assim "funciona".
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

/* Veredito de validade da assinatura inteira, a partir das duas condições que a
 * invalidam. Recebe os números APURADOS em vez de lê-los, e a razão é medida:
 *
 * Enquanto esta decisão vivia embutida no final de `feed-secundario.c`, um
 * mutante que a trocasse por "sempre VALIDO" SOBREVIVIA à suíte -- porque nesta
 * máquina o livro é de fato válido, e "sempre sim" é indistinguível de "sim
 * porque apurei" quando a resposta é sim. É o mesmo padrão de `modelo_de_driver`
 * em lib-nic.sh e de `hugepages_veredito` em lib-hugepages.sh: decisão que lê o
 * ambiente sozinha só pode ser testada no ambiente em que se está.
 *
 *   cruzados     livros com compra acima da venda -- impossível num livro
 *                consistente, logo qualquer valor > 0 invalida;
 *   degenerados  amostras de latência impossíveis (TSC desalinhado entre os
 *                núcleos). Não invalidam o LIVRO, invalidam a MEDIÇÃO que se
 *                publica junto dele -- e publicar as duas coisas sob um único
 *                selo de "válido" exige que as duas estejam boas.
 *
 * O LIMIAR SEPARA TRANSITÓRIO DE SESSÃO DEGRADADA, E A UNIDADE É CONTAGEM.
 *
 * Medido nesta máquina, com a máquina dedicada, em vinte sessões arquivadas em
 * `historico/.../calibracao-degenerados.*`: dez de 200 000 ticks e dez de
 * 1 000 000. A distribuição é BIMODAL -- ou a sessão tem no máximo UMA amostra
 * degenerada, ou tem 82. Não há nada entre 2 e 81.
 *
 * A contagem NÃO escala com o tamanho da coleta: as sessões de 1 000 000
 * mostram as mesmas 0 ou 1 das de 200 000. O defeito é por evento, não por
 * amostra -- e por isso a unidade é contagem absoluta, não fração. Uma fração
 * daria vereditos diferentes para o mesmo evento conforme a coleta fosse curta
 * ou longa.
 *
 * A sessão das 82 não é transitória: nela o mínimo publicado foi 0,00 ns --
 * travessia impossível -- e a resolução do instrumento dobrou, de ~11,9 para
 * 23,5 ns. É uma sessão sob pressão de escalonamento, e é precisamente o que o
 * selo precisa recusar.
 *
 * O limite fica no pé do intervalo vazio: duas amostras impossíveis já sugerem
 * condição que persistiu, em vez de evento isolado. Qualquer valor entre 2 e 81
 * separaria as duas populações nestes dados; o pé é a escolha conservadora.
 *
 * A CONTAGEM CONTINUA IMPRESSA ao lado do resultado. O limiar decide o selo,
 * não esconde o número. */
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
