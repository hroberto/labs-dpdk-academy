/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Implementação das regras de dimensionamento de mempool. Sem DPDK, sem
 * alocação, sem I/O: é a parte deste módulo que se testa em L1.
 */
#include "sizing.h"

#include <stdio.h>
#include <string.h>

/* n é da forma 2^q - 1 exatamente quando n+1 é potência de dois. O truque
 * n & (n+1) evita laço e trata n = 0 corretamente (0 é 2^0 - 1). */
static int is_pow2_minus_one(uint32_t n)
{
    return (n & (n + 1u)) == 0u;
}

unsigned dim_check(uint32_t n, uint32_t cache_size, uint32_t cache_max)
{
    unsigned warnings = DIM_OK;

    if (!is_pow2_minus_one(n))
        warnings |= DIM_N_NOT_POW2_MINUS_ONE;

    if (cache_size == 0)
        return warnings; /* sem cache não há regra de cache a violar */

    if (cache_size > cache_max)
        warnings |= DIM_CACHE_ABOVE_MAX;

    /* "lower or equal to n / 1.5". Em inteiros, cache <= n/1.5 equivale a
     * cache * 3 <= n * 2 — sem ponto flutuante, e sem erro de arredondamento
     * na fronteira. O produto é feito em 64 bits porque n e cache são
     * uint32_t e o dobro/triplo deles estoura. */
    if ((uint64_t)cache_size * 3u > (uint64_t)n * 2u)
        warnings |= DIM_CACHE_OVER_N_DIV_1_5;

    if (n % cache_size != 0u)
        warnings |= DIM_N_NOT_MULTIPLE_OF_CACHE;

    return warnings;
}

uint32_t dim_optimal_n(uint32_t minimum)
{
    if (is_pow2_minus_one(minimum))
        return minimum;

    /* Sobe até o próximo 2^q - 1. O laço para antes de estourar: o maior valor
     * representável dessa forma em uint32_t é UINT32_MAX, que já é 2^32 - 1. */
    uint32_t n = 1;
    while (n - 1u < minimum) {
        if (n > UINT32_MAX / 2u)
            return UINT32_MAX; /* 2^32 - 1, o maior possível */
        n *= 2u;
    }
    return n - 1u;
}

uint32_t dim_recommended_cache(uint32_t n, uint32_t cache_max)
{
    /* Teto imposto pelas duas regras de limite, em inteiros: cache <= n*2/3. */
    uint64_t teto = ((uint64_t)n * 2u) / 3u;
    if (teto > cache_max)
        teto = cache_max;
    if (teto == 0)
        return 0;

    /* Desce até achar um divisor exato de n. Busca linear é aceitável: o teto é
     * RTE_MEMPOOL_CACHE_MAX_SIZE (512 no DPDK 25.11), não o tamanho do pool. */
    for (uint32_t c = (uint32_t)teto; c > 0; c--)
        if (n % c == 0u)
            return c;

    return 0;
}

uint32_t dim_leftover_objects(uint32_t n, uint32_t cache_size)
{
    if (cache_size == 0)
        return 0;
    return n % cache_size;
}

const char *dim_describe(unsigned warnings, char *buf, size_t tam)
{
    static const struct {
        unsigned bit;
        const char *texto;
    } tabela[] = {
        {DIM_N_NOT_POW2_MINUS_ONE, "n nao e 2^q-1 (desperdicio de memoria)"},
        {DIM_CACHE_ABOVE_MAX, "cache acima do maximo (criacao falha)"},
        {DIM_CACHE_OVER_N_DIV_1_5, "cache maior que n/1.5 (criacao falha)"},
        {DIM_N_NOT_MULTIPLE_OF_CACHE, "n nao e multiplo do cache (objetos presos)"},
    };

    if (tam == 0)
        return buf;
    buf[0] = '\0';

    if (warnings == DIM_OK) {
        snprintf(buf, tam, "sem ressalvas");
        return buf;
    }

    size_t usado = 0;
    for (size_t i = 0; i < sizeof(tabela) / sizeof(tabela[0]); i++) {
        if (!(warnings & tabela[i].bit))
            continue;
        const int escrito =
            snprintf(buf + usado, tam - usado, "%s%s", usado ? "; " : "", tabela[i].texto);
        if (escrito < 0 || (size_t)escrito >= tam - usado)
            break; /* trunca em vez de estourar */
        usado += (size_t)escrito;
    }
    return buf;
}
