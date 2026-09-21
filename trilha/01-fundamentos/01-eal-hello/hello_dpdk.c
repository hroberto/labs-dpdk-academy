/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Tópico 01 — Inicialização da EAL.
 *
 * Demonstra o ciclo mínimo de qualquer aplicação DPDK:
 *   1. rte_eal_init() interpreta as opções da EAL (-l, --in-memory, --no-huge…),
 *      reserva memória, cria as threads dos lcores e descobre dispositivos;
 *   2. a aplicação roda;
 *   3. rte_eal_cleanup() libera os recursos.
 */
/* _GNU_SOURCE precisa vir ANTES de qualquer include: os cabecalhos do DPDK usam
 * ssize_t e strnlen, que sao POSIX/GNU e nao fazem parte do C11 do padrao ISO.
 * E assim que o proprio DPDK resolve isso upstream -- macro de funcionalidade
 * por arquivo, nao troca do padrao da linguagem para gnu11. */
#define _GNU_SOURCE
#include <rte_eal.h>
#include <rte_errno.h>
#include <rte_lcore.h>
#include <rte_version.h>

#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    /* rte_eal_init devolve quantos argumentos consumiu, ou -1 com rte_errno. */
    int consumidos = rte_eal_init(argc, argv);
    if (consumidos < 0) {
        fprintf(stderr, "Error initialising the EAL: %s\n", rte_strerror(rte_errno));
        return EXIT_FAILURE;
    }

    /* Os argumentos após "--" pertencem à aplicação, não à EAL. */
    argc -= consumidos;
    argv += consumidos;

    printf("DPDK Academy: EAL initialised successfully.\n");
    printf("DPDK version: %s\n", rte_version());
    printf("Lcores available: %u (main lcore: %u)\n",
           rte_lcore_count(), rte_get_main_lcore());
    printf("NUMA node of the main lcore: %d\n", rte_socket_id());
    printf("Arguments left for the application: %d\n", argc - 1);

    rte_eal_cleanup();
    return EXIT_SUCCESS;
}
