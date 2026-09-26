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

#include <errno.h>
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

/* PULADO, e nao falha: a maquina nao tem a topologia que a medicao exige.
 * E o 77 do Meson, que a suite ja usa com esse significado. */
#define ACADEMY_SAIDA_SEM_TOPOLOGIA 77

/* Confere ANTES de medir que todas as CPUs necessarias existem e estao
 * permitidas a este processo, e pula quando nao estao.
 *
 * POR QUE PULAR, E NAO FALHAR
 *
 * `academy_fixar_cpu()` aborta com 86 porque uma fixacao que falha no meio de
 * uma medicao e defeito: o programa pediu uma CPU que ele mesmo escolheu. Mas
 * um runner de CI com 4 CPUs nao tem a CPU 4, e isso nao e defeito do programa
 * -- e uma maquina que nao pode produzir este numero. Falhar ali transformaria
 * "esta medicao nao cabe aqui" em "o projeto esta quebrado".
 *
 * A diferenca importa porque foi medida: com o retorno de `setaffinity`
 * descartado, `custo-espera` rodava na CI pedindo a CPU 4, nao a obtinha, e
 * media com a thread de ruido onde o escalonador quisesse -- publicando um
 * numero cuja condicao declarada nao existia naquela maquina.
 *
 * A PERGUNTA E SOBRE A MASCARA PERMITIDA, e nao sobre a contagem de CPUs:
 * `sysconf(_SC_NPROCESSORS_ONLN)` diria 24 numa maquina onde um cpuset deixou
 * so duas ao processo. Aqui `sched_getaffinity` e a ferramenta certa -- nao
 * como conferencia depois de fixar, que nao acrescenta nada, mas como
 * pre-condicao antes.
 */
static inline void academy_exigir_cpus(const int *cpus, int n, const char *porque)
{
    cpu_set_t permitidas;
    CPU_ZERO(&permitidas);
    if (sched_getaffinity(0, sizeof(permitidas), &permitidas) != 0) {
        fprintf(stderr, "topologia: nao foi possivel ler as CPUs permitidas "
                        "(%s). Nada foi medido.\n", strerror(errno));
        exit(ACADEMY_SAIDA_SEM_TOPOLOGIA);
    }
    for (int i = 0; i < n; i++) {
        if (cpus[i] >= 0 && cpus[i] < CPU_SETSIZE && CPU_ISSET(cpus[i], &permitidas))
            continue;
        fprintf(stderr,
                "PULADO: esta medicao precisa da CPU %d, que esta maquina nao\n"
                "  oferece a este processo (%s).\n"
                "  Nada foi medido -- e isto NAO e uma medicao com sucesso.\n",
                cpus[i], porque);
        exit(ACADEMY_SAIDA_SEM_TOPOLOGIA);
    }
}

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
