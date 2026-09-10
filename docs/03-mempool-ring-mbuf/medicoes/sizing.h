/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Dimensionamento de mempool — as regras, sem o DPDK.
 *
 * A documentação de `rte_mempool_create` declara quatro restrições sobre o par
 * (n, cache_size). Nenhuma delas é verificada em tempo de compilação, e três
 * falham em SILÊNCIO: o pool é criado, funciona, e desperdiça memória ou
 * objetos sem avisar. A quarta rejeita a criação.
 *
 * Este cabeçalho não inclui nada do DPDK justamente para que as regras sejam
 * testáveis em L1, em milissegundos, sem subir a EAL — a mesma separação que o
 * módulo 02 faz com o livro de ofertas.
 *
 * AS QUATRO REGRAS, COMO A DOCUMENTAÇÃO AS ENUNCIA
 *
 *   1. "The optimum size (in terms of memory usage) for a mempool is when n is
 *      a power of two minus one: n = (2^q - 1)."
 *   2. cache_size "must be lower or equal to RTE_MEMPOOL_CACHE_MAX_SIZE"
 *   3. ...e "lower or equal to n / 1.5"
 *   4. "It is advised to choose cache_size to have n modulo cache_size == 0:
 *      if this is not the case, some elements will always stay in the pool and
 *      will never be used."
 *
 * A regra 4 é a mais fácil de violar sem perceber, e foi violada pelo próprio
 * programa de medição deste módulo antes desta verificação existir: um pool de
 * 4095 objetos com cache de 256 tem 4095 % 256 = 255 objetos fora dos lotes
 * cheios de reposição.
 *
 * ATENÇÃO AO ENUNCIADO DA REGRA 4 — CORRIGIDO POR MEDIÇÃO
 *
 * A frase da documentação ("will never be used") sugere que esses 255 objetos
 * ficam INALCANÇÁVEIS. Isso é falso, e `pool-esgotado.c` mede: um consumidor
 * único que drena o pool obtém os 4095, sem exceção.
 *
 * O mecanismo está em `rte_mempool_do_generic_get()`: quando o reabastecimento
 * do cache falha por não haver objetos para um lote inteiro, o código faz
 * `goto driver_dequeue` e busca os que faltam direto do anel de trás,
 * ignorando o cache. Não há objeto preso — há objeto que não passa pelo cache.
 *
 * O que a regra 4 governa de fato é EFICIÊNCIA em regime, com vários lcores:
 * cada cache retém objetos que os outros núcleos não enxergam, e a
 * divisibilidade decide se a reposição acontece em lotes cheios. Vale seguir a
 * regra — só não pelo motivo que a frase original sugere.
 *
 * Por isso `dim_leftover_objects()` continua com a mesma aritmética, e mudou de
 * significado: ver o comentário da função.
 */
#ifndef DPDK_ACADEMY_SIZING_H
#define DPDK_ACADEMY_SIZING_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Avisos combináveis por OU. Zero significa dimensionamento sem ressalva. */
enum dim_warning {
    DIM_OK = 0,
    DIM_N_NOT_POW2_MINUS_ONE = 1u << 0, /* desperdiça memória */
    DIM_CACHE_ABOVE_MAX = 1u << 1,     /* rte_mempool_create FALHA */
    DIM_CACHE_OVER_N_DIV_1_5 = 1u << 2,/* rte_mempool_create FALHA */
    DIM_N_NOT_MULTIPLE_OF_CACHE = 1u << 3,   /* objetos inalcançáveis */
};

/* Verifica o par (n, cache_size) contra as quatro regras.
 *
 * `cache_max` é PARÂMETRO, e não constante espelhada aqui, de propósito: copiar
 * RTE_MEMPOOL_CACHE_MAX_SIZE para dentro deste arquivo criaria uma cópia que
 * envelhece em silêncio se o DPDK mudar o valor. Quem chama a partir de código
 * ligado ao DPDK passa a constante real; o teste L1 passa o valor que quer
 * exercitar.
 */
unsigned dim_check(uint32_t n, uint32_t cache_size, uint32_t cache_max);

/* Menor valor da forma 2^q - 1 que comporta `minimo` objetos.
 * Devolve 0 se `minimo` não couber em uint32_t nessa forma. */
uint32_t dim_optimal_n(uint32_t minimum);

/* Maior cache válido para `n` que satisfaz as três regras de cache — inclusive
 * a divisibilidade. Devolve 0 quando nenhum valor não-nulo serve, o que é
 * resposta legítima: pool pequeno demais não comporta cache. */
uint32_t dim_recommended_cache(uint32_t n, uint32_t cache_max);

/* Quantos objetos sobram fora dos lotes cheios de reposição do cache, isto é,
 * n % cache_size. Zero quando n % cache == 0; zero também com cache_size == 0,
 * porque sem cache não há reposição em lote.
 *
 * NÃO são objetos inalcançáveis — `pool-esgotado.c` mede um consumidor único
 * obtendo todos eles, pelo caminho `driver_dequeue`. São os objetos que a
 * reposição do cache não movimenta em bloco, e é isso que custa eficiência com
 * vários lcores. O nome foi mantido para não quebrar o teste L1 que o exercita;
 * o significado está no cabeçalho deste arquivo. */
uint32_t dim_leftover_objects(uint32_t n, uint32_t cache_size);

/* Escreve em `buf` a lista de avisos, separados por "; ". Sempre termina em
 * '\0'. Devolve `buf`, para poder ser usada dentro de printf. */
const char *dim_describe(unsigned warnings, char *buf, size_t tam);

#ifdef __cplusplus
}
#endif

#endif /* DPDK_ACADEMY_DIMENSIONAMENTO_H */
