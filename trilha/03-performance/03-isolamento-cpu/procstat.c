/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Ver procstat.h para o porque de cada decisao.
 */
#include "procstat.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Conta as colunas `CPUn` do cabecalho. E daqui que sai `n_cpus`: supor um
 * numero fixo quebra ao trocar de maquina, e quebra em silencio. */
static unsigned contar_cpus(const char *linha)
{
    unsigned n = 0;
    for (const char *p = linha; (p = strstr(p, "CPU")) != NULL; p += 3)
        if (isdigit((unsigned char)p[3]))
            n++;
    return n;
}

/* Copia ate o `:` como rotulo, sem espacos. Devolve o ponto apos o `:`, ou
 * NULL se a linha nao tiver a forma `rotulo: ...`. */
static const char *extrair_rotulo(const char *linha, char *fora, size_t max)
{
    const char *dp = strchr(linha, ':');
    if (dp == NULL)
        return NULL;
    const char *ini = linha;
    while (ini < dp && isspace((unsigned char)*ini))
        ini++;
    /* Os dois modos de falha sao distintos e ficam separados: rotulo vazio e
     * uma linha como `  : 1 2 3`, e rotulo longo demais nao cabe no destino.
     * Escrever `n == 0` depois da subtracao fazia o analisador reclamar da
     * propria guarda -- ele prova que no caminho em que o laco chega ao `:` a
     * diferenca e zero, o que e verdade e e exatamente o caso tratado. */
    if (ini == dp)
        return NULL;
    const size_t n = (size_t)(dp - ini);
    if (n >= max)
        return NULL;
    memcpy(fora, ini, n);
    fora[n] = '\0';
    return dp + 1;
}

int proc_analisar(const char *texto, struct proc_tabela *t)
{
    memset(t, 0, sizeof *t);

    const char *p = texto;
    const char *fim_linha = strchr(p, '\n');
    if (fim_linha == NULL)
        return -1;

    char cabecalho[512];
    size_t n = (size_t)(fim_linha - p);
    if (n >= sizeof cabecalho)
        n = sizeof cabecalho - 1;
    memcpy(cabecalho, p, n);
    cabecalho[n] = '\0';

    t->n_cpus = contar_cpus(cabecalho);
    if (t->n_cpus == 0)
        return -1;
    if (t->n_cpus > PROC_MAX_CPUS)
        t->n_cpus = PROC_MAX_CPUS;

    p = fim_linha + 1;
    while (*p != '\0') {
        fim_linha = strchr(p, '\n');
        const size_t len = (fim_linha != NULL) ? (size_t)(fim_linha - p) : strlen(p);

        char linha[1024];
        size_t c = (len < sizeof linha - 1) ? len : sizeof linha - 1;
        memcpy(linha, p, c);
        linha[c] = '\0';

        struct proc_linha atual;
        memset(&atual, 0, sizeof atual);
        const char *resto = extrair_rotulo(linha, atual.rotulo, sizeof atual.rotulo);
        if (resto != NULL) {
            /* Le exatamente `n_cpus` numeros. Parar no numero certo e o que
             * impede a descricao do vetor de virar contagem -- a linha do
             * IO-APIC tem texto depois dos numeros. */
            unsigned lidos = 0;
            char *ponta = NULL;
            while (lidos < t->n_cpus) {
                const unsigned long long v = strtoull(resto, &ponta, 10);
                if (ponta == resto)
                    break;
                atual.por_cpu[lidos++] = (uint64_t)v;
                resto = ponta;
            }
            if (lidos > 0 && t->n_linhas < PROC_MAX_LINHAS)
                t->linha[t->n_linhas++] = atual;
        }

        if (fim_linha == NULL)
            break;
        p = fim_linha + 1;
    }
    return 0;
}

uint64_t proc_valor(const struct proc_tabela *t, const char *rotulo, unsigned cpu)
{
    if (cpu >= t->n_cpus)
        return 0;
    for (unsigned i = 0; i < t->n_linhas; i++)
        if (strcmp(t->linha[i].rotulo, rotulo) == 0)
            return t->linha[i].por_cpu[cpu];
    return 0;
}

size_t proc_delta_cpu(const struct proc_tabela *antes,
                      const struct proc_tabela *depois,
                      unsigned cpu, struct proc_delta *fora, size_t max)
{
    size_t n = 0;
    /* A GUARDA VEM ANTES DO ACESSO, e ate 26/09/2026 vinha depois.
     *
     * A checagem de `cpu` estava no `if` do corpo do laco, DEPOIS de
     * `por_cpu[cpu]` ja ter sido lido -- ela relatava o problema sem impedi-lo.
     * O `cpu` chega de `atoi(argv[1])` no `stall_probe`, e `por_cpu` tem
     * PROC_MAX_CPUS posicoes: um argumento acima disso lia fora do vetor.
     *
     * As tres condicoes sao distintas e todas necessarias: as duas tabelas
     * podem ter numero de colunas diferente entre as capturas, e o teto do
     * vetor e o unico limite que nao depende do que foi lido de /proc. */
    if (cpu >= PROC_MAX_CPUS || cpu >= depois->n_cpus || cpu >= antes->n_cpus)
        return 0;
    for (unsigned i = 0; i < depois->n_linhas && n < max; i++) {
        const uint64_t d1 = depois->linha[i].por_cpu[cpu];
        const uint64_t d0 = proc_valor(antes, depois->linha[i].rotulo, cpu);
        /* Contadores do kernel nao decrescem; se decresceram, houve reinicio do
         * contador ou troca de tabela, e somar lixo e pior que ignorar. */
        if (d1 <= d0)
            continue;
        snprintf(fora[n].rotulo, sizeof fora[n].rotulo, "%s", depois->linha[i].rotulo);
        fora[n].delta = d1 - d0;
        n++;
    }
    /* Ordenacao por insercao: `n` e no maximo algumas dezenas, e um qsort com
     * comparador aqui custaria mais leitura do que economiza. */
    for (size_t i = 1; i < n; i++) {
        struct proc_delta chave = fora[i];
        size_t j = i;
        while (j > 0 && fora[j - 1].delta < chave.delta) {
            fora[j] = fora[j - 1];
            j--;
        }
        fora[j] = chave;
    }
    return n;
}
