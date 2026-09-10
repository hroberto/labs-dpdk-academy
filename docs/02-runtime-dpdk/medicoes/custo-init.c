/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Runtime — quanto custa a EAL nascer e morrer.
 *
 * Nenhum tutorial de DPDK publica este número, e ele decide arquitetura: se
 * inicializar o runtime custa centenas de milissegundos, o processo de plano de
 * dados é um SERVIÇO DE LONGA DURAÇÃO, não algo que se sobe por requisição.
 * Num servidor de market data, é a diferença entre reiniciar o feed handler
 * fora do pregão e reiniciá-lo às 10h05 com o livro em movimento.
 *
 * METODOLOGIA: rte_eal_init() não é reentrante — devolve EALREADY na segunda
 * chamada do mesmo processo. Medir N amostras exige, portanto, N PROCESSOS.
 * Este programa faz fork() por amostra: o filho inicializa a EAL, cronometra, e
 * devolve o resultado ao pai por um pipe. O pai NUNCA inicializa a EAL, apenas
 * agrega — mediana, IQR, amplitude e CV, como os demais programas do projeto.
 *
 * As amostras são serializadas (fork, espera, próxima) de propósito: dois
 * processos inicializando ao mesmo tempo disputariam as mesmas páginas e o
 * mesmo diretório de runtime, e o que sairia seria contenção, não custo.
 *
 * USO: os argumentos da EAL são os deste próprio programa.
 *   ./custo-init -l 0 --in-memory
 *   ./custo-init -l 0 --no-huge --file-prefix=meu_teste
 *
 * NAO combine `--in-memory` com `--no-huge`: antes do DPDK 24 a segunda liga
 * `--legacy-mem`, incompativel com a primeira, e a EAL aborta citando uma
 * opcao que voce nao passou.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include <rte_eal.h>
#include <rte_errno.h>

#include "statistics.h"

/* Caras: cada amostra é um processo inteiro subindo e descendo o runtime. */
#define AMOSTRAS_INIT 11

enum etapa { ETAPA_INIT = 0, ETAPA_CLEANUP = 1 };

/* argv original: o filho o repassa intacto para rte_eal_init(). */
static int g_argc;
static char **g_argv;
static enum etapa g_etapa;

static double now_ms(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec * 1e3 + (double)t.tv_nsec / 1e6;
}

/* Executa no FILHO. Cronometra as duas etapas e devolve as duas pelo pipe;
 * o pai fica com a que pediu. Silencia a EAL: o log dela iria para o terminal a
 * cada amostra e não acrescenta nada depois da primeira. */
static void filho_mede(int fd)
{
    double r[2] = {-1.0, -1.0};

    /* Silencia a EAL: o log dela sairia a cada amostra. Se o redirecionamento
     * falhar, o ruído atrapalha a leitura mas não invalida a medição. */
    FILE *nulo_err = freopen("/dev/null", "w", stderr);
    FILE *nulo_saida = freopen("/dev/null", "w", stdout);
    (void)nulo_err;
    (void)nulo_saida;

    const double t0 = now_ms();
    const int n = rte_eal_init(g_argc, g_argv);
    const double t1 = now_ms();

    if (n < 0) {
        /* -1 sinaliza falha ao pai, que aborta com mensagem legível. */
        ssize_t ignorado = write(fd, r, sizeof(r));
        (void)ignorado;
        _exit(1);
    }

    r[ETAPA_INIT] = t1 - t0;

    const double t2 = now_ms();
    rte_eal_cleanup();
    r[ETAPA_CLEANUP] = now_ms() - t2;

    ssize_t ignorado = write(fd, r, sizeof(r));
    (void)ignorado;
    _exit(0);
}

/* Executa no PAI. Uma amostra = um processo. */
static double m_amostra(void)
{
    int tubo[2];
    if (pipe(tubo) != 0)
        return -1.0;

    /* Esvaziar os buffers ANTES do fork: o filho herdaria o conteúdo ainda não
     * gravado e o imprimiria de novo ao sair — uma amostra, duas saídas. */
    fflush(NULL);

    const pid_t pid = fork();
    if (pid < 0) {
        close(tubo[0]);
        close(tubo[1]);
        return -1.0;
    }

    if (pid == 0) {
        close(tubo[0]);
        filho_mede(tubo[1]);
    }

    close(tubo[1]);
    double r[2] = {-1.0, -1.0};
    const ssize_t lidos = read(tubo[0], r, sizeof(r));
    close(tubo[0]);

    int estado = 0;
    waitpid(pid, &estado, 0);

    if (lidos != (ssize_t)sizeof(r))
        return -1.0;
    return r[g_etapa];
}

static struct statistics medir(enum etapa e, int n)
{
    g_etapa = e;
    return collect(m_amostra, n);
}

int main(int argc, char **argv)
{
    g_argc = argc;
    g_argv = argv;

    const int n = samples(AMOSTRAS_INIT);

    printf("\n== Custo de inicializar e encerrar a EAL ==\n\n");
    printf("  configuracao medida:");
    for (int i = 1; i < argc; i++)
        printf(" %s", argv[i]);
    if (argc == 1)
        printf(" (nenhuma opcao: a EAL usa os padroes)");
    printf("\n  amostras: %d (uma por processo; rte_eal_init nao e reentrante)\n\n", n);

    /* Amostra de sondagem: se a EAL não sobe nesta máquina com estes
     * argumentos, dizer isso é mais útil do que imprimir uma tabela de -1. */
    g_etapa = ETAPA_INIT;
    if (m_amostra() < 0) {
        printf("  A EAL nao inicializou com estes argumentos nesta maquina.\n");
        printf("  Rode o mesmo comando sem este programa para ver o motivo, por exemplo:\n");
        printf("    ./build/trilha/01-fundamentos/01-eal-hello/hello_dpdk");
        for (int i = 1; i < argc; i++)
            printf(" %s", argv[i]);
        printf("\n\n  Causas comuns: sem hugepages reservadas (use --no-huge), ou sem\n");
        printf("  permissao de escrita em /dev/hugepages (use --in-memory, sozinho).\n");
        printf("  As duas juntas falham antes do DPDK 24: --no-huge liga --legacy-mem.\n\n");
        return 0; /* ambiente, não defeito: o teste L2 continua valido */
    }

    const struct statistics init = medir(ETAPA_INIT, n);
    const struct statistics limpeza = medir(ETAPA_CLEANUP, n);

    printf("  valores em MILISSEGUNDOS\n\n");
    print_header();
    print_row("rte_eal_init()", init);
    print_row("rte_eal_cleanup()", limpeza);

    printf("\n  Leitura:\n");
    printf("    Em 10 GbE com quadros de 64 B chega 1 pacote a cada 67,2 ns.\n");
    printf("    A janela de %.0f ms da inicializacao equivale a %.0f milhoes de pacotes\n",
           init.median, init.median * 1e6 / 67.2 / 1e6);
    printf("    nao atendidos. Por isso o processo de plano de dados sobe uma vez\n");
    printf("    e fica de pe: reinicia-lo em producao nao e uma operacao barata.\n\n");

    return 0;
}
