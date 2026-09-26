/* SPDX-License-Identifier: MIT
 *
 * Injeção de falha em `pthread_create`, para o caminho que nunca roda.
 *
 * POR QUE ISTO EXISTE
 *
 * `pthread_create` praticamente nunca falha numa máquina de estudo, e por isso
 * o caminho de erro dela ficou anos sem ser exercitado. Ele continha um
 * deadlock determinístico: com `pthread_barrier_t`, as threads já criadas
 * ficavam esperando participantes que nunca viriam, e o `join` do criador
 * esperava por elas.
 *
 * O kernel devolve `EAGAIN` ao bater `RLIMIT_NPROC`. Este objeto compartilhado
 * devolve o mesmo, na hora escolhida.
 *
 * A MIRA E A CRIACAO PARCIAL, e nao a ordem das chamadas.
 *
 * Contar chamadas do processo inteiro obriga a saber quantas threads cada
 * medição anterior criou -- o número muda quando alguém acrescenta uma fase, e
 * o teste passa a mirar noutro lugar sem avisar. Contar por ponteiro de função
 * também não serve: com `n = 1` a "segunda chamada" é a segunda AMOSTRA, onde
 * não há participante anterior e o laço de `join` está vazio. Medido: assim o
 * código defeituoso saía limpo, e o teste não separava nada.
 *
 * O que caracteriza a criação parcial é outra coisa: JA HA UMA THREAD VIVA e a
 * próxima não sobe. Este objeto conta as criadas desde o último `pthread_join`
 * e falha quando esse número já é positivo -- exatamente a condição em que as
 * anteriores ficam presas na sincronização, independente de qual medição está
 * correndo.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Threads criadas com sucesso desde o ultimo `pthread_join`. */
static int vivas;
static pthread_mutex_t trava = PTHREAD_MUTEX_INITIALIZER;

int pthread_create(pthread_t *t, const pthread_attr_t *a, void *(*f)(void *), void *arg)
{
    static int (*real)(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
    if (real == NULL) {
        /* `dlsym` devolve `void *`, e atribui-lo a ponteiro de funcao e
         * condicionalmente suportado em ISO C -- `-Wpedantic` acusa, e a barra
         * deste projeto e zero aviso. `memcpy` e a forma que POSIX documenta
         * para a conversao. */
        const void *sim = dlsym(RTLD_NEXT, "pthread_create");
        memcpy(&real, &sim, sizeof real);
    }

    if (getenv("FALHAR_NA_CRIACAO_PARCIAL") == NULL)
        return real(t, a, f, arg);

    pthread_mutex_lock(&trava);
    const int ha_vivas = vivas > 0;
    pthread_mutex_unlock(&trava);

    if (ha_vivas) {
        fprintf(stderr, "[injecao] pthread_create devolvendo EAGAIN com %d thread(s) ja viva(s)\n",
                ha_vivas);
        return EAGAIN;
    }

    const int rc = real(t, a, f, arg);
    if (rc == 0) {
        pthread_mutex_lock(&trava);
        vivas++;
        pthread_mutex_unlock(&trava);
    }
    return rc;
}

int pthread_join(pthread_t t, void **r)
{
    static int (*real)(pthread_t, void **);
    if (real == NULL) {
        const void *sim = dlsym(RTLD_NEXT, "pthread_join");
        memcpy(&real, &sim, sizeof real);
    }
    const int rc = real(t, r);
    pthread_mutex_lock(&trava);
    if (vivas > 0)
        vivas--;
    pthread_mutex_unlock(&trava);
    return rc;
}
