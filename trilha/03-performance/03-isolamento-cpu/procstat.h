/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Leitura de `/proc/interrupts`, por CPU e por vetor.
 *
 * POR QUE ISTO EXISTE
 *
 * Medir a parada diz QUE houve interrupcao; nao diz QUAL. Sem atribuir a fonte,
 * o experimento vira uma coleta de numeros grandes sem causa, e a conclusao
 * "isolar ajuda" fica sem mecanismo -- exatamente o que este material recusa.
 *
 * O delta por CPU e por vetor entre o inicio e o fim de uma execucao responde
 * a pergunta certa: quantas vezes CADA fonte interrompeu a CPU medida.
 *
 * O FORMATO, E POR QUE ELE E CHATO
 *
 *            CPU0       CPU1       CPU2
 *   0:         31          0          0   IO-APIC   2-edge      timer
 *  NMI:         0          0          0   Non-maskable interrupts
 *  LOC:   1234567    1234568    1234569   Local timer interrupts
 *
 * O cabecalho nomeia as colunas, e o numero delas varia com a maquina. As
 * linhas de vetor numerado trazem descricao apos as contagens; as de vetor
 * simbolico (LOC, NMI, RES, CAL, TLB) trazem so o texto. Um parser que suponha
 * numero fixo de colunas quebra ao trocar de maquina, e quebra em silencio --
 * por isso o numero de CPUs sai do CABECALHO, nao de uma constante.
 *
 * O QUE ELE DELIBERADAMENTE NAO FAZ
 *
 * Nao interpreta o que cada vetor significa. `TLB` e IPI de invalidacao,
 * `RES` e reagendamento, `CAL` e chamada de funcao -- isso e conhecimento do
 * documento, nao do parser. Aqui so sai o rotulo como o kernel o escreve.
 */
#ifndef DPDK_ACADEMY_PROCSTAT_H
#define DPDK_ACADEMY_PROCSTAT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PROC_MAX_CPUS    64
#define PROC_MAX_LINHAS 256
#define PROC_ROTULO_MAX  32

struct proc_linha {
    char rotulo[PROC_ROTULO_MAX];      /* "0", "LOC", "TLB", "RES" ... */
    uint64_t por_cpu[PROC_MAX_CPUS];
};

struct proc_tabela {
    unsigned n_cpus;                   /* do cabecalho, nao suposto */
    unsigned n_linhas;
    struct proc_linha linha[PROC_MAX_LINHAS];
};

/* Analisa o conteudo de /proc/interrupts (ou /proc/softirqs, mesmo formato).
 *
 * Devolve 0 em sucesso, -1 se o cabecalho nao trouxer nenhuma coluna `CPUn`.
 * Linhas alem de PROC_MAX_LINHAS sao ignoradas em vez de truncar a tabela pela
 * metade: perder uma linha rara e melhor que reportar contagens deslocadas.
 */
int proc_analisar(const char *texto, struct proc_tabela *t);

/* Contagem de um rotulo numa CPU, ou 0 se o rotulo nao existir.
 *
 * Devolver 0 para rotulo ausente e correto aqui: um vetor que nao aparece em
 * /proc/interrupts nunca disparou, e `TLB` so aparece depois do primeiro
 * shootdown da maquina.
 */
uint64_t proc_valor(const struct proc_tabela *t, const char *rotulo, unsigned cpu);

/* Delta entre duas leituras, para uma CPU. `fora` recebe ate `max` entradas com
 * delta diferente de zero, ordenadas da maior para a menor.
 *
 * Devolve quantas entradas foram escritas.
 */
struct proc_delta {
    char rotulo[PROC_ROTULO_MAX];
    uint64_t delta;
};

size_t proc_delta_cpu(const struct proc_tabela *antes,
                      const struct proc_tabela *depois,
                      unsigned cpu, struct proc_delta *fora, size_t max);

#ifdef __cplusplus
}
#endif

#endif /* DPDK_ACADEMY_PROCSTAT_H */
