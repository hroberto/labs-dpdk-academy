/* SPDX-License-Identifier: MIT
 *
 * Largada simultânea para N trabalhadores, com caminho de cancelamento.
 *
 * POR QUE ISTO EXISTE
 *
 * Dois programas usavam `pthread_barrier_t` para soltar os trabalhadores
 * juntos, e os dois tinham o mesmo defeito no caminho de erro: quando
 * `pthread_create` falha na thread `i`, as `0..i-1` já estão bloqueadas na
 * barreira, e ela nunca vai completar -- as que faltam não existem.
 *
 *   `custo-paralelismo` fazia `pthread_join` nas já criadas. O join espera uma
 *   thread que espera uma barreira que nunca enche: DEADLOCK determinístico.
 *   Reproduzido com injeção de falha (EAGAIN, que é o que o kernel devolve ao
 *   bater RLIMIT_NPROC): falhar a criação #5 ou #7 trava o processo; #4 e #6
 *   saem limpas, porque ali o laço de join está vazio. A alternância é o
 *   modelo: ímpar é a SEGUNDA thread de uma medição, par é a primeira.
 *
 *   `custo-comunicacao` chamava `pthread_barrier_destroy` com threads ainda
 *   bloqueadas nela -- comportamento indefinido por POSIX --, não fazia join, e
 *   devolvia 0.0 como se fosse medida.
 *
 * `pthread_barrier_t` NÃO TEM COMO SER CANCELADA, e é essa a raiz: a
 * cardinalidade é fixada em `init`, antes de se saber quantas threads de fato
 * subiram. Daí este módulo, que separa as duas coisas.
 *
 * AS DUAS PROPRIEDADES QUE ELE PRECISA TER
 *
 *   1. Largada simultânea. Trocar a barreira por um simples sinalizador não
 *      basta: o `main` soltaria e tomaria `t0` antes de os trabalhadores
 *      chegarem a olhar o sinal, e o tempo de partida de cada um entraria no
 *      intervalo medido. Por isso há DUAS fases -- cada trabalhador anuncia
 *      que chegou, o `main` espera todos, e só então solta.
 *
 *   2. Cancelamento. `soltar(l, 0)` acorda quem já está esperando com a
 *      resposta "não meça", e aí o `join` termina. O `main` NÃO espera pelos
 *      prontos nesse caminho: eles nunca serão N.
 *
 * A espera é ativa (`pause`), e não bloqueante: são microssegundos entre a
 * criação e a largada, e um mutex aqui acrescentaria ao intervalo medido
 * justamente o que se quer excluir dele.
 */
#ifndef ACADEMY_LARGADA_H
#define ACADEMY_LARGADA_H

#include <stdatomic.h>

#include "cpu_pause.h"

#define ACADEMY_LARGADA_ESPERA  0
#define ACADEMY_LARGADA_VAI     1
#define ACADEMY_LARGADA_CANCELA 2

struct academy_largada {
    _Atomic int prontos;
    _Atomic int estado;
};

static inline void academy_largada_init(struct academy_largada *l)
{
    atomic_store_explicit(&l->prontos, 0, memory_order_relaxed);
    atomic_store_explicit(&l->estado, ACADEMY_LARGADA_ESPERA, memory_order_release);
}

/* Chamada pelo TRABALHADOR. Devolve 1 se deve medir, 0 se foi cancelada. */
static inline int academy_largada_esperar(struct academy_largada *l)
{
    int e;
    atomic_fetch_add_explicit(&l->prontos, 1, memory_order_release);
    while ((e = atomic_load_explicit(&l->estado, memory_order_acquire))
           == ACADEMY_LARGADA_ESPERA)
        academy_cpu_pause();
    return e == ACADEMY_LARGADA_VAI;
}

/* Chamada pelo MAIN, só no caminho de sucesso: espera os N chegarem. */
static inline void academy_largada_aguardar(const struct academy_largada *l, int n)
{
    while (atomic_load_explicit(&l->prontos, memory_order_acquire) < n)
        academy_cpu_pause();
}

/* Chamada pelo MAIN. `medir` = 0 cancela, e é o que destrava o `join`. */
static inline void academy_largada_soltar(struct academy_largada *l, int medir)
{
    atomic_store_explicit(&l->estado,
                          medir ? ACADEMY_LARGADA_VAI : ACADEMY_LARGADA_CANCELA,
                          memory_order_release);
}

#endif /* ACADEMY_LARGADA_H */
