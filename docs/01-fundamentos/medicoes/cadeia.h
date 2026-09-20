/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Cadeia de ponteiros: a permutação e o encadeamento, num lugar só.
 *
 * POR QUE ISTO EXISTE
 *
 * Três programas desta pasta montam a mesma estrutura — `efeito-cache.c`,
 * `custo-traducao.c` e `custo-paralelismo.c`. Todos precisam da mesma coisa:
 * uma permutação das linhas de uma região e um encadeamento em que cada linha
 * guarda o índice da próxima, formando um ciclo que passa por todas.
 *
 * Estava escrito três vezes, e a terceira cópia saiu ERRADA. A primeira versão
 * da coluna dependente de `efeito-cache.c` embaralhava as `n` posições do vetor
 * e depois reduzia cada valor com `% nos` para caber no número de linhas. Isso
 * não é uma permutação: vários nós recebem o mesmo sucessor, a cadeia degenera
 * em ciclos de dois ou três nós que cabem na L1, e o programa publicou **0,9 ns
 * como latência da RAM**.
 *
 * O QUE ISSO ENSINA SOBRE O TESTE QUE NÃO EXISTIA
 *
 * A suíte ficou VERDE com esse defeito. O teste do programa era
 * `efeito-cache executa` — ele confere o código de saída, e um programa que
 * mede a coisa errada sai com zero do mesmo jeito. É a mesma classe de falso
 * verde que o `meson.build` desta pasta já documenta duas vezes.
 *
 * A propriedade violada é puramente combinatória, não depende de hardware nem
 * de tempo, e por isso é testável em L1: **o encadeamento tem de formar K
 * ciclos disjuntos que, juntos, visitam cada nó exatamente uma vez.** Ver
 * `tests/test_l1_cadeia.cpp`.
 *
 * POR QUE A API DEVOLVE ÍNDICES, E NÃO ESCREVE NA REGIÃO
 *
 * Os três programas usam tipos diferentes para a região (`size_t*` em dois,
 * `uint32_t*` no outro) e passos diferentes. Generalizar isso exigiria macro ou
 * ponteiro void, e o ganho seria nenhum: escrever o sucessor no vetor é uma
 * linha trivial e específica de cada programa. O que vale compartilhar é a
 * parte que erra — a permutação e a escolha do sucessor.
 *
 * POR QUE NÃO `rand()`
 *
 * `rand()` usa estado global, e `rand() % (i + 1)` introduz viés de módulo. Nas
 * dimensões destes programas o viés é desprezível, mas o estado global não é:
 * ele torna a permutação dependente de quem mais chamou `rand()` antes, o que
 * é exatamente o tipo de acoplamento que impede um teste de ser determinístico.
 * O gerador abaixo é xorshift64, com a semente passada pelo chamador.
 */
#ifndef ACADEMY_CADEIA_H
#define ACADEMY_CADEIA_H

#include <stddef.h>
#include <stdint.h>

#if defined(__GNUC__)
#define CADEIA_MAYBE_UNUSED __attribute__((unused))
#else
#define CADEIA_MAYBE_UNUSED
#endif

/* xorshift64 (Marsaglia). Determinístico dada a semente, sem estado global. */
static CADEIA_MAYBE_UNUSED uint64_t academy_aleatorio(uint64_t *semente)
{
    uint64_t x = *semente;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *semente = x;
    return x;
}

/* Preenche `ordem` com uma permutação uniforme de 0..n-1 (Fisher-Yates).
 *
 * O laço vai do fim para o começo e sorteia em [0, i], que é a forma correta:
 * sortear em [0, n) a cada passo produz distribuição não uniforme. */
static CADEIA_MAYBE_UNUSED void academy_permutar(size_t *ordem, size_t n, uint64_t *semente)
{
    for (size_t i = 0; i < n; i++)
        ordem[i] = i;
    for (size_t i = n; i-- > 1;) {
        const size_t j = (size_t)(academy_aleatorio(semente) % (i + 1));
        const size_t t = ordem[i];
        ordem[i] = ordem[j];
        ordem[j] = t;
    }
}

/* Índice, dentro de `ordem`, do sucessor da posição `i` quando a permutação é
 * dividida em `k` fatias iguais e cada fatia é fechada em ciclo.
 *
 * Com k = 1 há um ciclo único sobre os n nós. Com k > 1 há k ciclos disjuntos
 * de n/k nós cada — o que permite percorrer k cadeias em paralelo sem que duas
 * compartilhem uma linha.
 *
 * As `n % k` posições finais ficam de fora quando n não divide por k; quem
 * chama deve percorrer apenas `(n / k) * k` posições. `academy_cadeia_nos()`
 * devolve esse número. */
static CADEIA_MAYBE_UNUSED size_t academy_sucessor(const size_t *ordem, size_t n, int k, size_t i)
{
    const size_t por_fatia = n / (size_t)k;
    const size_t fatia = i / por_fatia;
    const size_t inicio = fatia * por_fatia;
    const size_t prox = i + 1;
    return ordem[(prox == inicio + por_fatia) ? inicio : prox];
}

/* Quantas posições de `ordem` participam das k cadeias. */
static CADEIA_MAYBE_UNUSED size_t academy_cadeia_nos(size_t n, int k)
{
    return (n / (size_t)k) * (size_t)k;
}

/* Índice, dentro de `ordem`, onde começa a cadeia `c`. */
static CADEIA_MAYBE_UNUSED size_t academy_cadeia_inicio(size_t n, int k, int c)
{
    return (size_t)c * (n / (size_t)k);
}

#endif /* ACADEMY_CADEIA_H */
