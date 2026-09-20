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

/* Tempo que o trabalhador fica ocupado, para o principal conseguir observá-lo
 * em RUNNING. Sem isso, a função retornaria antes da primeira amostragem. */
#define TRABALHO_MS 300

/* Lista as CPUs de um cpuset em forma legivel: "6" ou "6,18". */
static void imprimir_cpuset(char *destino, size_t n, rte_cpuset_t conjunto)
{
    size_t usado = 0;
    destino[0] = '\0';
    for (int cpu = 0; cpu < CPU_SETSIZE && usado + 8 < n; cpu++) {
        if (!CPU_ISSET(cpu, &conjunto))
            continue;
        usado += (size_t)snprintf(destino + usado, n - usado, "%s%d", usado ? "," : "", cpu);
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
    const int n = rte_eal_init(argc, argv);
    if (n < 0) {
        fprintf(stderr, "estado-lcore: EAL nao inicializou: %s\n", rte_strerror(rte_errno));
        return 2;
    }

    printf("\n== O que a EAL decidiu ==\n\n");
    printf("  versao ............... %s\n", rte_version());
    printf("  tipo de processo ..... %s\n",
           rte_eal_process_type() == RTE_PROC_PRIMARY ? "PRIMARIO" : "SECUNDARIO");
    printf("  modo IOVA ............ %s\n", rte_eal_iova_mode() == RTE_IOVA_VA ? "VA (virtual)"
                                                                              : "PA (fisico)");
    printf("  argumentos consumidos  %d  (rte_eal_init devolve a CONTAGEM, nao 0/-1)\n", n);
    printf("  lcores em uso ........ %u  (a maquina tem %u CPUs logicas)\n", rte_lcore_count(),
           (unsigned)sysconf(_SC_NPROCESSORS_ONLN));
    printf("  lcore principal ...... %u\n", rte_get_main_lcore());
    printf("  relogio (TSC) ........ %.3f GHz\n\n", (double)rte_get_tsc_hz() / 1e9);

    printf("  %-8s %-14s %-12s %-14s %-8s\n", "lcore", "CPU(s) reais", "papel", "indice no no",
           "no NUMA");
    printf("  %-8s %-14s %-12s %-14s %-8s\n", "-----", "------------", "-----", "------------",
           "-------");
    unsigned id;
    RTE_LCORE_FOREACH(id) {
        char cpus[64] = "";
        imprimir_cpuset(cpus, sizeof(cpus), rte_lcore_cpuset(id));
        printf("  %-8u %-14s %-12s %-14d %-8u\n", id, cpus,
               id == rte_get_main_lcore() ? "principal" : "trabalhador",
               rte_lcore_to_cpu_id((int)id), rte_lcore_to_socket_id(id));
    }

    printf("\n  Duas colunas que costumam ser confundidas:\n\n");
    printf("  * \"CPU(s) reais\" vem de rte_lcore_cpuset(): e onde a thread do lcore\n");
    printf("    esta de fato fixada. Com -l 0-3 coincide com o numero do lcore; com\n");
    printf("    --lcores '0@6' o lcore 0 passa a rodar na CPU 6.\n\n");
    printf("  * \"indice no no\" vem de rte_lcore_to_cpu_id(), cujo nome ENGANA: a\n");
    printf("    documentacao diz \"the id of the lcore on a socket starting from\n");
    printf("    zero\", ou seja, um indice relativo ao no NUMA -- nao o numero da\n");
    printf("    CPU. Usa-la para fixar thread ou escolher IRQ poe o trabalho no\n");
    printf("    nucleo errado, e o sintoma aparece so no desempenho.\n");

    if (rte_lcore_count() < 2) {
        printf("\n  Apenas um lcore: nao ha trabalhador para observar.\n");
        printf("  Rode com -l 0-3 para ver a maquina de estados.\n\n");
        rte_eal_cleanup();
        /* CÓDIGO 77 = PULADO, e não sucesso.
         *
         * Sair com 0 aqui fazia o Meson reportar OK sem que nada tivesse sido medido —
         * um falso verde. E não era caso raro: no runner do CI o requisito nunca
         * existiu, então este teste jamais verificou coisa alguma e sempre apareceu
         * verde. O Meson trata 77 como SKIP, conta separado e não falha a suíte. */
        return 77;
    }

    printf("\n== Maquina de estados do lcore trabalhador ==\n\n");
    printf("  Esta versao do DPDK expoe DOIS estados: WAIT e RUNNING.\n");
    printf("  Ate o DPDK 20.11 havia um terceiro, FINISHED, ainda descrito na\n");
    printf("  maior parte do material disponivel na web.\n\n");

    unsigned marca = 7;

    imprimir_estados("apos rte_eal_init:");

    RTE_LCORE_FOREACH_WORKER(id) {
        const int r = rte_eal_remote_launch(trabalhador, &marca, id);
        if (r != 0)
            fprintf(stderr, "  lcore %u recusou a tarefa: %d\n", id, r);
    }

    imprimir_estados("apos remote_launch:");

    /* Amostra no meio do trabalho: o trabalhador ainda esta ocupado. */
    rte_delay_ms(TRABALHO_MS / 2);
    imprimir_estados("durante o trabalho:");

    /* Espera o retorno e RECOLHE o valor de cada trabalhador. */
    printf("\n  valores devolvidos pelos trabalhadores:\n");
    RTE_LCORE_FOREACH_WORKER(id)
        printf("    lcore %u -> %d\n", id, rte_eal_wait_lcore(id));

    printf("\n");
    imprimir_estados("apos wait_lcore:");

    printf("\n  Repare que o estado volta a WAIT sozinho: nao ha FINISHED para\n");
    printf("  observar. rte_eal_wait_lcore() e o que entrega o valor de retorno,\n");
    printf("  e por isso continua sendo obrigatoria mesmo quando o trabalhador\n");
    printf("  ja terminou.\n\n");

    rte_eal_cleanup();
    return 0;
}
