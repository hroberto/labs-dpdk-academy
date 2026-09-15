/* SPDX-License-Identifier: MIT
 *
 * Leitura do relógio monotônico, em um lugar só.
 *
 * POR QUE ISTO EXISTE
 *
 * `now_ns()` estava definida DEZ vezes nos programas de medição, em três
 * variantes: seis devolviam `uint64_t`, três devolviam `double`, e uma era a
 * mesma coisa escrita em duas linhas. Cópia não é só repetição -- ela diverge,
 * e estas já tinham divergido em duas dimensões:
 *
 *   1. o TIPO de retorno, o que faz o mesmo nome significar coisas diferentes
 *      conforme o arquivo;
 *   2. o TRATAMENTO DE FALHA, e esta é a que importa. Nenhuma das dez conferia
 *      o retorno de `clock_gettime()`. Quando ela falha, `struct timespec` fica
 *      NÃO INICIALIZADA e a função devolve lixo da pilha -- que vira intervalo
 *      medido, entra na estatística e sai publicado como tempo.
 *
 * O projeto já tinha a versão correta, em `docs/02-runtime-dpdk/medicoes/
 * feed-clock.h`: ela confere o retorno e aborta. A disciplina existia num
 * canto e não tinha alcançado os outros dez arquivos -- que é exatamente a
 * causa-raiz que a auditoria do projeto nomeou como "a disciplina está
 * concentrada num núcleo estreito".
 *
 * POR QUE ABORTAR, E NÃO DEVOLVER ERRO
 *
 * `clock_gettime(CLOCK_MONOTONIC)` não falha em operação normal: os motivos
 * possíveis são relógio inexistente ou ponteiro inválido, e os dois são defeito
 * de programa, não condição de ambiente. Propagar erro obrigaria cada laço de
 * medição a tratar um caso que não acontece, e o tratamento morto seria pior
 * que a ausência dele. Abortar deixa o defeito visível no instante em que ele
 * ocorre, em vez de publicá-lo como número.
 *
 * DUAS ASSINATURAS, DE PROPÓSITO
 *
 * `academy_now_ns()` devolve `uint64_t`: é a leitura exata, sem perda.
 * `academy_now_ns_d()` devolve `double`, para os laços que calculam médias e
 * dividem -- evita conversão espalhada no ponto de uso. As duas leem o mesmo
 * relógio pela mesma chamada; a diferença é só o tipo na fronteira.
 */
#ifndef ACADEMY_CLOCK_NS_H
#define ACADEMY_CLOCK_NS_H

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

/* O caminho de erro sai de linha, e isto foi MEDIDO.
 *
 * Com o `abort()` embutido na funcao inline, o compilador degrada a otimizacao
 * do laco que a chama: `custo-anel.c` ficou 17% mais lento no lote 32 e 28% no
 * lote 128, em 10 execucoes por ponto, contra a versao anterior sem verificacao
 * nenhuma. Nao e o custo do carimbo -- ele e amortizado sobre 200 000 operacoes
 * e seria invisivel.
 *
 * `cold` diz ao compilador que este caminho nao acontece, e `noinline` o tira
 * do corpo da funcao. A verificacao continua existindo; o que sai do caminho
 * quente e o tratamento dela. */
__attribute__((cold, noinline)) static void academy_clock_falhou(void)
{
    fprintf(stderr, "clock_gettime(CLOCK_MONOTONIC) falhou: "
                    "nao ha medicao possivel sem relogio\n");
    abort();
}

static inline uint64_t academy_now_ns(void)
{
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t) != 0)
        academy_clock_falhou();
    return (uint64_t)t.tv_sec * 1000000000ULL + (uint64_t)t.tv_nsec;
}

static inline double academy_now_ns_d(void)
{
    return (double)academy_now_ns();
}

#endif /* ACADEMY_CLOCK_NS_H */
