/* SPDX-License-Identifier: MIT
 *
 * A fixação de CPU falha FECHADA — e aqui está o programa que a faz falhar.
 *
 * POR QUE ELE EXISTE
 *
 * `academy_fixar_cpu()` encerra o processo quando não consegue prender a thread
 * na CPU pedida. É a única razão de o cabeçalho existir: sete programas
 * chegaram a medir depois de uma fixação que não aconteceu, porque descartavam
 * o retorno de `pthread_setaffinity_np()`.
 *
 * Um caminho de aborto que nunca dispara na suíte é indistinguível de um que
 * não existe -- trocar o `exit()` por `return` deixaria tudo verde. Este
 * programa faz os dois lados dispararem, em processos filhos, e só sai com
 * sucesso se AMBOS se comportarem:
 *
 *   - CPU existente: a chamada volta, e o filho chega ao fim com código 0;
 *   - CPU inexistente: o filho morre com ACADEMY_SAIDA_AFINIDADE, e não com
 *     um código qualquer -- é o código que a campanha lê para distinguir
 *     "a pré-condição falhou" de "o programa quebrou".
 *
 * O segundo caso precisa de um número de CPU que o `cpu_set_t` aceite e a
 * máquina não tenha. Numa máquina com quase CPU_SETSIZE processadores esse
 * número não existe, e aí o teste PULA (77) em vez de inventar um veredito.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

#include "fixar_cpu.h"

/* Roda `academy_fixar_cpu(cpu)` num filho e devolve o código de saída dele,
 * ou -1 se o filho morreu de sinal. */
static int saida_ao_fixar(int cpu)
{
    pid_t filho = fork();
    if (filho == 0) {
        fclose(stderr); /* o aborto é esperado; a mensagem poluiria o log */
        academy_fixar_cpu(cpu);
        _exit(0);
    }
    int estado = 0;
    if (filho < 0 || waitpid(filho, &estado, 0) != filho)
        return -2;
    return WIFEXITED(estado) ? WEXITSTATUS(estado) : -1;
}

int main(void)
{
    long n = sysconf(_SC_NPROCESSORS_CONF);
    int falhas = 0, rc;

    rc = saida_ao_fixar(0);
    if (rc != 0) {
        printf("FALHA: fixar na CPU 0 devia seguir, saiu com %d\n", rc);
        falhas++;
    }

    if (n <= 0 || n >= CPU_SETSIZE - 1) {
        printf("PULADO: sem numero de CPU inexistente abaixo de CPU_SETSIZE "
               "(%d CPUs configuradas)\n", (int)n);
        return falhas ? 1 : 77;
    }

    /* O LITERAL, e nao a macro, de proposito: comparar com
     * `ACADEMY_SAIDA_AFINIDADE` faria o teste concordar com qualquer valor que
     * o cabecalho escolhesse, inclusive 1. Medido: com a macro, mudar 86 para 1
     * mantinha a suite verde. O numero e contrato com quem le o codigo de
     * saida, entao esta escrito aqui tambem. */
    const int ausente = CPU_SETSIZE - 1;
    rc = saida_ao_fixar(ausente);
    if (rc != 86) {
        printf("FALHA: fixar na CPU %d devia sair com 86, saiu com %d\n",
               ausente, rc);
        falhas++;
    }
    if (ACADEMY_SAIDA_AFINIDADE != 86) {
        printf("FALHA: ACADEMY_SAIDA_AFINIDADE virou %d; era 86\n",
               ACADEMY_SAIDA_AFINIDADE);
        falhas++;
    }

    printf("%s\n", falhas ? "FALHOU" : "ok: fixacao falha fechada nos dois lados");
    return falhas ? 1 : 0;
}
