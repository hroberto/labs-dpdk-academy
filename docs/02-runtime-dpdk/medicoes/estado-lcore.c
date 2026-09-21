/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * O que a EAL decidiu, e a máquina de estados do lcore.
 *
 * Duas perguntas que a documentação responde por texto e este programa responde
 * por observação:
 *
 * 1. O que exatamente a EAL escolheu nesta máquina, com estes argumentos —
 *    modo IOVA, tipo de processo, quais lcores, em que CPU física cada um caiu,
 *    em que nó NUMA. É o "análise de ambiente" do nível 3 do plano.
 *
 * 2. Em que estados um lcore trabalhador passa. Este ponto merece atenção
 *    porque MUDOU: até o DPDK 20.11 o enum tinha três estados
 *    (WAIT, RUNNING, FINISHED) e o vocabulário era master/slave. No DPDK 25.11
 *    são DOIS estados (WAIT, RUNNING) e o vocabulário é main/worker. Material
 *    escrito para versões antigas — que é a maior parte do que se encontra na
 *    web, em inglês e em chinês — ainda descreve o modelo de três estados.
 *    Este programa imprime o que a versão instalada realmente expõe.
 *
 * USO:
 *   ./estado-lcore -l 0-3 --in-memory
 *   ./estado-lcore --lcores '0@6,1@7' --in-memory      (remapeamento)
 */
#define _GNU_SOURCE
#include <inttypes.h>
#include <stdio.h>
#include <unistd.h>

#include <rte_cycles.h>
#include <rte_eal.h>
#include <rte_errno.h>
#include <rte_launch.h>
#include <rte_pause.h>
#include <rte_lcore.h>
#include <rte_version.h>
#include "statistics.h"

/* Tempo que o trabalhador fica ocupado, para o principal conseguir observá-lo
 * em RUNNING. Sem isso, a função retornaria antes da primeira amostragem. */
#define TRABALHO_MS 300

/* Lista as CPUs de um cpuset em forma legivel: "6" ou "6,18". */
static void imprimir_cpuset(char *destino, size_t n, rte_cpuset_t conjunto)
{
    size_t usado = 0;
    destino[0] = '\0';
    for (int cpu = 0; cpu < CPU_SETSIZE && usado < n; cpu++) {
        if (!CPU_ISSET(cpu, &conjunto))
            continue;
        /* `snprintf` devolve O QUE CABERIA, nao o que escreveu.
         *
         * A versao anterior somava esse retorno direto em `usado`, e a unica
         * coisa que impedia `usado` de passar de `n` era a guarda `usado + 8 <
         * n` do laco. Ela funcionava por coincidencia aritmetica: com
         * CPU_SETSIZE de 1024 cada volta escreve no maximo 6 bytes (virgula,
         * quatro digitos e o NUL) e a guarda deixava 9 livres.
         *
         * Nao havia estouro -- havia dependencia NAO DECLARADA entre o numero
         * magico 8 e a quantidade de digitos de CPU_SETSIZE. Numa plataforma
         * com cpuset maior, ou se alguem reduzisse a guarda, `usado` passaria
         * de `n` e o `n - usado` seguinte, sendo size_t, estouraria para baixo
         * virando um valor enorme.
         *
         * Achado pelo CodeQL (cpp/overflowing-snprintf) na primeira execucao,
         * e e o tipo de defeito que revisao humana nao pega: o codigo esta
         * correto, e so a premissa que nao esta escrita. */
        const int escrito = snprintf(destino + usado, n - usado, "%s%d", usado ? "," : "", cpu);
        if (escrito < 0 || (size_t)escrito >= n - usado)
            break; /* truncou: para, em vez de contabilizar o que nao coube */
        usado += (size_t)escrito;
    }
    if (usado == 0)
        snprintf(destino, n, "-");
}

static const char *nome_estado(enum rte_lcore_state_t e)
{
    switch (e) {
    case WAIT:
        return "WAIT";
    case RUNNING:
        return "RUNNING";
    default:
        return "?";
    }
}

static int trabalhador(void *arg)
{
    const unsigned id = rte_lcore_id();
    const uint64_t fim = rte_rdtsc() + rte_get_tsc_hz() * TRABALHO_MS / 1000;
    while (rte_rdtsc() < fim)
        rte_pause();

    /* O valor devolvido não se perde: rte_eal_wait_lcore() o entrega ao
     * principal. É o canal de retorno de um trabalhador — e a razão pela qual
     * não se deve ignorar o retorno dessa função. */
    return (int)(id * 100u + *(const unsigned *)arg);
}

static void imprimir_estados(const char *momento)
{
    printf("  %-22s", momento);
    unsigned id;
    RTE_LCORE_FOREACH_WORKER(id)
        printf(" lcore %u: %-8s", id, nome_estado(rte_eal_get_lcore_state(id)));
    printf("\n");
}

int main(int argc, char **argv)
{
    print_provenance("estado-lcore");
    const int n = rte_eal_init(argc, argv);
    if (n < 0) {
        fprintf(stderr, "estado-lcore: EAL did not initialise: %s\n", rte_strerror(rte_errno));
        return 2;
    }

    printf("\n== What the EAL decided ==\n\n");
    printf("  version .............. %s\n", rte_version());
    printf("  process type ......... %s\n",
           rte_eal_process_type() == RTE_PROC_PRIMARY ? "PRIMARIO" : "SECUNDARIO");
    printf("  IOVA mode ............ %s\n", rte_eal_iova_mode() == RTE_IOVA_VA ? "VA (virtual)"
                                                                              : "PA (fisico)");
    printf("  arguments consumed     %d  (rte_eal_init returns the COUNT, not 0/-1)\n", n);
    printf("  lcores in use ........ %u  (the machine has %u logical CPUs)\n", rte_lcore_count(),
           (unsigned)sysconf(_SC_NPROCESSORS_ONLN));
    printf("  main lcore ........... %u\n", rte_get_main_lcore());
    printf("  clock (TSC) .......... %.3f GHz\n\n", (double)rte_get_tsc_hz() / 1e9);

    printf("  %-8s %-14s %-12s %-14s %-8s\n", "lcore", "real CPU(s)", "role", "index in node",
           "NUMA node");
    printf("  %-8s %-14s %-12s %-14s %-8s\n", "-----", "------------", "-----", "------------",
           "-------");
    unsigned id;
    RTE_LCORE_FOREACH(id) {
        char cpus[64] = "";
        imprimir_cpuset(cpus, sizeof(cpus), rte_lcore_cpuset(id));
        printf("  %-8u %-14s %-12s %-14d %-8u\n", id, cpus,
               id == rte_get_main_lcore() ? "main" : "worker",
               rte_lcore_to_cpu_id((int)id), rte_lcore_to_socket_id(id));
    }

    printf("\n  Two columns that are often confused:\n\n");
    printf("  * \"real CPU(s)\" comes from rte_lcore_cpuset(): it is where the lcore's\n");
    printf("    thread is actually pinned. With -l 0-3 it matches the lcore number; with\n");
    printf("    --lcores '0@6' lcore 0 starts running on CPU 6.\n\n");
    printf("  * \"index in node\" comes from rte_lcore_to_cpu_id(), whose name MISLEADS: the\n");
    printf("    documentation says \"the id of the lcore on a socket starting from\n");
    printf("    zero\", that is, an index relative to the NUMA node -- not the CPU\n");
    printf("    number. Using it to pin a thread or pick an IRQ puts the work on the\n");
    printf("    wrong core, and the symptom shows up only in performance.\n");

    if (rte_lcore_count() < 2) {
        printf("\n  Only one lcore: there is no worker to observe.\n");
        printf("  Run with -l 0-3 to see the state machine.\n\n");
        rte_eal_cleanup();
        /* CÓDIGO 77 = PULADO, e não sucesso.
         *
         * Sair com 0 aqui fazia o Meson reportar OK sem que nada tivesse sido medido —
         * um falso verde. E não era caso raro: no runner do CI o requisito nunca
         * existiu, então este teste jamais verificou coisa alguma e sempre apareceu
         * verde. O Meson trata 77 como SKIP, conta separado e não falha a suíte. */
        return 77;
    }

    printf("\n== State machine of the worker lcore ==\n\n");
    printf("  This DPDK version exposes TWO states: WAIT and RUNNING.\n");
    printf("  Until DPDK 20.11 there was a third, FINISHED, still described in\n");
    printf("  most of the material available on the web.\n\n");

    unsigned marca = 7;

    imprimir_estados("apos rte_eal_init:");

    RTE_LCORE_FOREACH_WORKER(id) {
        const int r = rte_eal_remote_launch(trabalhador, &marca, id);
        if (r != 0)
            fprintf(stderr, "  lcore %u refused the task: %d\n", id, r);
    }

    imprimir_estados("apos remote_launch:");

    /* Amostra no meio do trabalho: o trabalhador ainda esta ocupado. */
    rte_delay_ms(TRABALHO_MS / 2);
    imprimir_estados("durante o trabalho:");

    /* Espera o retorno e RECOLHE o valor de cada trabalhador. */
    printf("\n  values returned by the workers:\n");
    RTE_LCORE_FOREACH_WORKER(id)
        printf("    lcore %u -> %d\n", id, rte_eal_wait_lcore(id));

    printf("\n");
    imprimir_estados("apos wait_lcore:");

    printf("\n  Note that the state returns to WAIT on its own: there is no FINISHED to\n");
    printf("  observe. rte_eal_wait_lcore() is what delivers the return value,\n");
    printf("  and that is why it remains mandatory even when the worker\n");
    printf("  has already finished.\n\n");

    rte_eal_cleanup();
    return 0;
}
