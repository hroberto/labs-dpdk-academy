/* SPDX-License-Identifier: MIT
 *
 * Fixa a thread corrente numa CPU, e aborta se não conseguir.
 *
 * POR QUE ISTO EXISTE
 *
 * Sete programas deste repositório fixavam a thread com
 * `pthread_setaffinity_np()` e descartavam o retorno -- cinco no próprio corpo
 * de um `static void fixar(int)`, um devolvendo o código a oito chamadores que
 * não o liam, e um imprimindo `warning` no stderr antes de medir assim mesmo.
 *
 * Em todos eles a colocação não é detalhe de execução: é a variável
 * independente. `custo-comunicacao` compara ida-e-volta no mesmo CCD contra CCD
 * cruzado; `packet_pipeline` faz o mesmo sem DPDK. Uma fixação que falha não
 * degrada o número -- ela troca a condição por outra, mantém o rótulo e sai com
 * código zero. O resultado fica publicável na aparência e não corresponde ao
 * experimento descrito.
 *
 * Daí o aborto: falhou a afinidade, não existe amostra.
 *
 * POR QUE O RETORNO BASTA, E NÃO SE CONFERE A MÁSCARA DEPOIS
 *
 * Seria natural reler a afinidade com `pthread_getaffinity_np()` e comparar,
 * ou perguntar a `sched_getcpu()` onde a thread foi parar. Nenhum dos dois
 * acrescenta garantia AQUI, e a razão é a máscara ser de um bit só:
 *
 *   - O kernel intersecta o pedido com as CPUs permitidas ao processo. Uma
 *     máscara singular ou sobrevive inteira ou fica vazia, e vazia é `EINVAL`.
 *     Não há estado em que a máscara efetiva discorde do pedido com a chamada
 *     tendo devolvido 0 -- o caso de estreitamento silencioso por cpuset exige
 *     um pedido de dois ou mais bits.
 *   - Se a thread não estiver numa CPU da nova máscara, o kernel a migra
 *     (sched_setaffinity(2)), e para a thread corrente isso ocorre antes do
 *     retorno.
 *
 * Medido antes de simplificar: 556 800 fixações bem-sucedidas, 48 threads
 * disputando 24 CPUs, varrendo todas elas. Máscara efetiva diferente da
 * pedida em 0; `sched_getcpu()` diferente da pedida em 0. As duas conferências
 * não falham -- elas não podem falhar, e custam a leitura de quem vier depois.
 *
 * REQUER `_GNU_SOURCE` declarado na fonte, antes de qualquer cabeçalho do
 * sistema, como o restante das medições deste repositório faz.
 */
#ifndef ACADEMY_FIXAR_CPU_H
#define ACADEMY_FIXAR_CPU_H

#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Código de saída próprio: distingue "a fixação falhou" de um erro qualquer do
 * programa, para que a campanha relate a causa sem depender do stderr. Não
 * colide com o 77 que o Meson reserva para teste PULADO -- pular é exatamente o
 * que uma pré-condição falha não pode fazer aqui. */
#define ACADEMY_SAIDA_AFINIDADE 86

static inline void academy_fixar_cpu(int cpu)
{
    cpu_set_t pedida;
    int rc;

    CPU_ZERO(&pedida);
    CPU_SET(cpu, &pedida);

    rc = pthread_setaffinity_np(pthread_self(), sizeof(pedida), &pedida);
    if (rc != 0) {
        fprintf(stderr,
                "afinidade: nao foi possivel fixar a thread na CPU %d (%s).\n"
                "  A colocacao e a variavel independente desta medicao; sem ela\n"
                "  nao ha amostra publicavel. Nada foi medido.\n",
                cpu, strerror(rc));
        exit(ACADEMY_SAIDA_AFINIDADE);
    }
}

#endif /* ACADEMY_FIXAR_CPU_H */
