/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Histograma de paradas, e a janela que decide se uma parada custa algo.
 *
 * Este cabecalho nao inclui nada do DPDK de proposito: a aritmetica da janela e
 * a classificacao das paradas sao logica pura, testaveis em L1 sem subir a EAL.
 * A mesma separacao que o `order_book.h` do modulo 02 faz com o livro.
 *
 * POR QUE HISTOGRAMA EM POTENCIAS DE DOIS
 *
 * Uma parada do sistema operacional nao tem escala unica: as frequentes estao
 * na casa do microssegundo e as raras na casa do milissegundo, tres ordens de
 * grandeza acima. Um histograma linear com baldes finos desperdicaria memoria
 * na cauda; com baldes largos esconderia o corpo.
 *
 * Balde por potencia de dois resolve os dois: resolucao relativa constante --
 * cada balde cobre o dobro do anterior -- e 64 baldes bastam para toda a faixa
 * representavel em uint64. E o preco de inserir e um `clz`, nao uma divisao.
 *
 * O QUE ESTE CABECALHO DELIBERADAMENTE NAO FAZ
 *
 * Nao le relogio e nao decide quando medir. Recebe gaps ja medidos, em ciclos,
 * e a frequencia para converte-los. Assim o mesmo codigo serve para a sonda sem
 * DPDK e para a que roda sob a EAL, e o teste L1 nao precisa de relogio nenhum.
 */
#ifndef DPDK_ACADEMY_GAP_HIST_H
#define DPDK_ACADEMY_GAP_HIST_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 64 baldes cobrem de 1 ciclo a 2^63 ciclos. Nao ha como estourar. */
#define GAP_BALDES 64

struct gap_hist {
    uint64_t balde[GAP_BALDES];
    uint64_t amostras;
    uint64_t maior;     /* maior gap visto, em ciclos, sem perda de resolucao */
    uint64_t soma;      /* para a media; a mediana sai dos baldes */
};

void gap_hist_iniciar(struct gap_hist *h);

/* Indice do balde de um gap: floor(log2(ciclos)), com 0 ciclos no balde 0. */
unsigned gap_balde_de(uint64_t ciclos);

/* Limite inferior do balde `i`, em ciclos. O balde `i` cobre [2^i, 2^(i+1)). */
uint64_t gap_balde_piso(unsigned i);

void gap_hist_somar(struct gap_hist *h, uint64_t ciclos);

/* Percentil aproximado, em ciclos, devolvido como o PISO do balde que o contem.
 *
 * Devolver o piso e deliberado: o balde diz que o valor esta em [2^i, 2^(i+1)),
 * e interpolar dentro dele afirmaria uma precisao que o histograma nao tem.
 * Quem precisa do valor exato usa `maior`, que e guardado sem quantizacao.
 *
 * `q` em milesimos: 999 para p99,9; 99999 nao cabe, use `maior`.
 */
uint64_t gap_percentil_piso(const struct gap_hist *h, unsigned q_milesimos);

/* ------------------------------------------------------------------ */
/* A JANELA: quanto tempo o anel de RX aguenta antes de a NIC descartar */
/* ------------------------------------------------------------------ */

/* Nanossegundos que um quadro ocupa no fio.
 *
 * O quadro de `bytes_quadro` carrega 20 bytes de sobrecarga alem dos dados --
 * 7 de preambulo, 1 de delimitador e 12 de intervalo entre quadros -- conforme
 * a IEEE 802.3. A conta e a mesma da secao 1 do modulo 01, e esta aqui porque a
 * janela depende dela.
 */
double janela_ns_por_quadro(unsigned bytes_quadro, double gbps);

/* Quanto tempo `n_descritores` absorvem antes do primeiro descarte.
 *
 * E COTA INFERIOR, e isso precisa ser dito: o FIFO interno da NIC tambem
 * absorve, e nao ha como le-lo pelo driver. Uma parada abaixo desta janela
 * seguramente nao custa; uma acima pode ainda assim nao custar. Medir a janela
 * efetiva e o exercicio 3.
 */
double janela_ns(unsigned n_descritores, unsigned bytes_quadro, double gbps);

/* Quantas amostras do histograma excedem a janela.
 *
 * Conta pelo PISO do balde: um balde so e contado quando todo ele esta acima da
 * janela. Subestima de proposito -- e melhor dizer "pelo menos N paradas
 * custaram" do que inflar a contagem com um balde que so parcialmente excede.
 */
uint64_t gap_acima_da_janela(const struct gap_hist *h, double janela_ns_,
                             double ciclos_por_ns);

#ifdef __cplusplus
}
#endif

#endif /* DPDK_ACADEMY_GAP_HIST_H */
