/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Ver gap_hist.h para o porque de cada decisao.
 */
#include "gap_hist.h"

#include <string.h>

void gap_hist_iniciar(struct gap_hist *h)
{
    memset(h, 0, sizeof *h);
}

unsigned gap_balde_de(uint64_t ciclos)
{
    /* `__builtin_clzll` e indefinido para zero, e zero e um gap legitimo:
     * duas leituras de relogio consecutivas podem devolver o mesmo valor. */
    if (ciclos == 0)
        return 0;
    return (unsigned)(63 - __builtin_clzll(ciclos));
}

uint64_t gap_balde_piso(unsigned i)
{
    return (i >= GAP_BALDES) ? 0 : (uint64_t)1 << i;
}

void gap_hist_somar(struct gap_hist *h, uint64_t ciclos)
{
    h->balde[gap_balde_de(ciclos)]++;
    h->amostras++;
    h->soma += ciclos;
    if (ciclos > h->maior)
        h->maior = ciclos;
}

uint64_t gap_percentil_piso(const struct gap_hist *h, unsigned q_milesimos)
{
    if (h->amostras == 0)
        return 0;
    /* Alvo e a posicao da amostra procurada, contada a partir do inicio.
     * O arredondamento para cima garante que p100 caia na ultima amostra. */
    const uint64_t alvo = (h->amostras * q_milesimos + 999) / 1000;
    uint64_t acumulado = 0;
    for (unsigned i = 0; i < GAP_BALDES; i++) {
        acumulado += h->balde[i];
        if (acumulado >= alvo)
            return gap_balde_piso(i);
    }
    return gap_balde_piso(GAP_BALDES - 1);
}

double janela_ns_por_quadro(unsigned bytes_quadro, double gbps)
{
    if (gbps <= 0.0)
        return 0.0;
    /* 20 bytes de sobrecarga na linha: 7 de preambulo, 1 de delimitador de
     * inicio de quadro e 12 de intervalo entre quadros (IEEE 802.3). */
    const double bits = (double)(bytes_quadro + 20u) * 8.0;
    return bits / gbps;   /* gbps em bits por nanossegundo == Gbit/s */
}

double janela_ns(unsigned n_descritores, unsigned bytes_quadro, double gbps)
{
    return (double)n_descritores * janela_ns_por_quadro(bytes_quadro, gbps);
}

uint64_t gap_acima_da_janela(const struct gap_hist *h, double janela_ns_,
                             double ciclos_por_ns)
{
    if (janela_ns_ <= 0.0 || ciclos_por_ns <= 0.0)
        return 0;
    const double limite = janela_ns_ * ciclos_por_ns;
    uint64_t n = 0;
    for (unsigned i = 0; i < GAP_BALDES; i++) {
        /* So conta o balde cujo PISO ja excede: ver o comentario do cabecalho
         * sobre subestimar de proposito. */
        if ((double)gap_balde_piso(i) > limite)
            n += h->balde[i];
    }
    return n;
}
