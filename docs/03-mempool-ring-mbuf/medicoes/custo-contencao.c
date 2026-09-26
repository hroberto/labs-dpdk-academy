/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Nível 4 — o regime em que o mempool finalmente ganha.
 *
 * A alternativa em C++23 deste projeto mede o mempool contra o `malloc` num
 * núcleo só, em memória, e o mempool PERDE. A conclusão é legítima para aquele
 * regime, e enganosa fora dele: o cache por lcore existe para evitar contenção
 * entre núcleos, e com um núcleo ele é indireção pura.
 *
 * Este programa devolve a contenção. N núcleos disputam a MESMA fonte de
 * objetos, e a pergunta é como cada abordagem escala.
 *
 * POR QUE OS TRABALHADORES SÃO LANÇADOS COM rte_eal_remote_launch
 *
 * Nao e estilo: e condicao de validade. Uma thread comum recebe LCORE_ID_ANY e
 * pula o cache por lcore. Ver README.md secao 5 "Validacao: reproduza na sua
 * maquina".
 *
 * O lado do malloc usa pthreads porque e o que um programa comum faria.
 *
 * USO: ./custo-contencao -l 0-7 --no-huge --file-prefix=meu_teste --no-pci <cache_size>
 */
#define _GNU_SOURCE
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <rte_eal.h>
#include <rte_errno.h>
#include <rte_launch.h>
#include <rte_lcore.h>
#include <rte_mempool.h>

#include "clock_ns.h"
#include "statistics.h"

#define OBJS 32767u
#define TAM 128u
#define ITER 300000
#define BURST 32u

/* Teto de threads de `measure_malloc`. Precisa acompanhar o maior `n` que o
 * laco de main() alcanca -- ele dobra ate rte_lcore_count(), entao 128
 * cobre maquinas de ate 128 lcores, e acima disso a funcao recusa em vez
 * de corromper a pilha. */
#define MAX_THREADS 128u

static struct rte_mempool *pool;
static _Alignas(64) atomic_int start_flag = 0;
static _Alignas(64) atomic_ullong ns_total = 0;

static inline void consume_ptr(void*p){ __asm__ __volatile__("" : : "r"(p) : "memory"); }

/* Roda num lcore da EAL: e o que faz rte_lcore_id() ser valido e o cache por
 * lcore do mempool ser realmente usado. Thread comum recebe LCORE_ID_ANY e
 * PULA o cache -- detalhe que muda o resultado por completo. */
/* O DENOMINADOR SAO AS OPERACOES QUE ACONTECERAM, e nao as que foram pedidas.
 *
 * A versao anterior dividia por `ITER` sempre, e o `continue` do `get_bulk`
 * falhado nao tirava nada da conta. Uma falha custa quase zero -- ela nem chega
 * a consumir os objetos --, entao cada falha EMPURRAVA O CUSTO PUBLICADO PARA
 * BAIXO.
 *
 * O vies tem direcao e endereco: falha de `get_bulk` acontece quando o pool
 * esvazia, ou seja, sob CONTENCAO -- que e exatamente o que esta medicao
 * estuda. O mecanismo que deveria piorar o numero o melhorava.
 *
 * As falhas viram contador proprio em vez de desaparecerem: coleta com falha
 * mede outra coisa, e quem le precisa saber disso em vez de deduzir. */
static _Atomic unsigned long long falhas_get;

static int worker_pool(void *arg)
{
    (void)arg;
    void *v[BURST];
    unsigned long long feitas = 0, falhou = 0;
    while (!atomic_load_explicit(&start_flag, memory_order_acquire)) ;
    const double t0 = academy_now_ns_d();
    for (int i = 0; i < ITER / (int)BURST; i++) {
        if (rte_mempool_get_bulk(pool, v, BURST) < 0) { falhou++; continue; }
        for (unsigned j = 0; j < BURST; j++) consume_ptr(v[j]);
        rte_mempool_put_bulk(pool, (void *const *)v, BURST);
        feitas++;
    }
    const double decorrido = academy_now_ns_d() - t0;
    atomic_fetch_add(&falhas_get, falhou);
    /* Sem nenhuma operacao concluida nao ha custo por operacao a somar: somar
     * zero seria publicar "de graca" o que na verdade nao mediu nada. */
    if (feitas > 0)
        atomic_fetch_add(&ns_total,
                         (unsigned long long)(decorrido * 1000.0
                                              / (double)(feitas * BURST)));
    return 0;
}

static void *worker_malloc(void *arg)
{
    (void)arg;
    void *v[BURST];
    while (!atomic_load_explicit(&start_flag, memory_order_acquire)) ;
    const double t0 = academy_now_ns_d();
    const int lotes = ITER / (int)BURST;
    for (int i = 0; i < lotes; i++) {
        for (unsigned j = 0; j < BURST; j++) { v[j] = malloc(TAM); consume_ptr(v[j]); }
        for (unsigned j = 0; j < BURST; j++) free(v[j]);
    }
    /* Mesmo denominador do `worker_pool`: objetos que passaram pelo laco. Aqui
     * nao ha falha possivel, entao sao todos -- mas a conta fica escrita do
     * mesmo jeito nos dois, para que a razao publicada compare o comparavel. */
    atomic_fetch_add(&ns_total,
                     (unsigned long long)((academy_now_ns_d() - t0) * 1000.0
                                          / (double)((unsigned long long)lotes * BURST)));
    return NULL;
}

/* AMOSTRA QUE NAO VALE, e nao um numero ruim.
 *
 * Os dois medidores abaixo precisam recusar a amostra quando a condicao
 * declarada nao ocorreu -- fixacao que falhou, thread que nao subiu. O jeito
 * usado no resto do projeto e `exit()`, e aqui ele esta PROIBIDO: a EAL esta
 * de pe, e sair no meio pula `rte_eal_cleanup()`. O cabecalho do
 * `tests/coleta_zero.c` ja registra essa restricao.
 *
 * Entao a recusa viaja como valor de retorno, o `main` invalida a LINHA
 * inteira em que ela aparece, e o codigo de saida sai diferente de zero depois
 * do cleanup. Negativo serve de sentinela porque tempo por operacao nao e: o
 * menor valor legitimo e maior que zero. */
#define AMOSTRA_INVALIDA (-1.0)

static double measure_pool(unsigned n_lcores)
{
    atomic_store(&start_flag, 0); atomic_store(&ns_total, 0);
    atomic_store(&falhas_get, 0);
    unsigned id, launched_n = 0;
    RTE_LCORE_FOREACH_WORKER(id) {
        if (launched_n + 1 >= n_lcores) break;
        if (rte_eal_remote_launch(worker_pool, NULL, id) == 0) launched_n++;
    }
    atomic_store_explicit(&start_flag, 1, memory_order_release);
    worker_pool(NULL);
    rte_eal_mp_wait_lcore();
    /* O ROTULO DA LINHA AFIRMA `n` THREADS, e so o lancamento sabe se foram
     * tantas. `rte_eal_remote_launch` so conta em sucesso, e uma falha dele
     * deixaria a linha rotulada com um numero que nao foi medido. */
    /* AVISAR E PUBLICAR E A PROPRIA MENTIRA. Ate aqui esta condicao imprimia
     * "a linha nao mede o que o rotulo diz" e devolvia o numero na linha
     * seguinte; o `main` imprimia a linha sob o `n` pedido, e quem lesse a
     * tabela veria um valor rotulado com uma contagem de threads que nao
     * correu. O stderr de uma campanha nao lida nao desfaz uma tabela lida. */
    if (launched_n + 1 != n_lcores) {
        fprintf(stderr, "  AMOSTRA INVALIDA: pedi %u thread(s) e lancei %u;"
                        " a linha seria rotulada com um numero que nao foi"
                        " medido\n", n_lcores, launched_n + 1);
        return AMOSTRA_INVALIDA;
    }
    const unsigned long long falhou = atomic_load(&falhas_get);
    if (falhou > 0)
        fprintf(stderr, "  AVISO: %llu lote(s) de get_bulk falharam com %u"
                        " thread(s); o custo publicado e o do caminho de"
                        " sucesso\n", falhou, n_lcores);
    return (double)atomic_load(&ns_total) / 1000.0 / (launched_n + 1);
}

/* Primeira CPU do cpuset de um lcore da EAL.
 *
 * Usa rte_lcore_cpuset(), e não rte_lcore_to_cpu_id(): a segunda é descrita de
 * formas incompatíveis entre a documentação e a implementação conforme a
 * release, e não deve ser usada para decidir afinidade. O cpuset é o contrato
 * estável. */
static int cpu_of_lcore(unsigned lcore)
{
    rte_cpuset_t cs = rte_lcore_cpuset(lcore);
    for (int c = 0; c < CPU_SETSIZE; c++)
        if (CPU_ISSET(c, &cs))
            return c;
    return -1;
}

/* Le um campo de topologia do sysfs. -1 quando o campo nao existe. */
static int topologia(int cpu, const char *campo)
{
    char caminho[160];
    snprintf(caminho, sizeof(caminho),
             "/sys/devices/system/cpu/cpu%d/%s", cpu, campo);
    FILE *f = fopen(caminho, "r");
    if (f == NULL)
        return -1;
    int v = -1;
    if (fscanf(f, "%d", &v) != 1)
        v = -1;
    fclose(f);
    return v;
}

/* QUE FRONTEIRA CADA LINHA ATRAVESSA -- e por que isso vai na saida.
 *
 * `n` dobra ate `rte_lcore_count()`, e numa maquina de 12 nucleos fisicos em
 * dois CCDs as linhas nao medem todas a mesma coisa:
 *
 *   n <= 6    todas as threads no mesmo dominio de L3
 *   n = 8     duas delas no outro CCD: a disputa passa a atravessar a
 *             interconexao, que a §4.2 do modulo 01 mede em ~81 ns
 *   n = 16    quatro delas sao IRMAS SMT de outras: duas threads dividem as
 *             unidades de execucao de um nucleo fisico
 *
 * Publicar a coluna sem dizer isso convida a ler a curva como se o unico fator
 * fosse o numero de threads. Sao tres fatores, e a tabela nao os separa -- o
 * que ela pode fazer, e passa a fazer, e DECLARAR onde cada um entra.
 *
 * Nao se corrige escolhendo lcores "melhores": com 8 threads em 6 nucleos por
 * CCD, atravessar e inevitavel. O que se corrige e o silencio. */
static void marcar_fronteira(char *buf, size_t n_buf, unsigned n)
{
    int l3 = -1, ccd = 0, smt = 0;
    unsigned vistos[128];
    unsigned n_vistos = 0;
    unsigned id;
    RTE_LCORE_FOREACH(id) {
        if (n_vistos >= n || n_vistos >= 128)
            break;
        const int cpu = cpu_of_lcore(id);
        if (cpu < 0)
            continue;
        /* IRMAO SMT: o mesmo `core_id` ja visto significa que duas threads
         * caem no mesmo nucleo fisico. */
        const int core = topologia(cpu, "topology/core_id");
        for (unsigned k = 0; k < n_vistos; k++)
            if ((int)vistos[k] == core)
                smt = 1;
        vistos[n_vistos++] = (unsigned)core;
        /* CCD: o primeiro campo de `shared_cpu_list` da L3 identifica o
         * dominio. Mudou entre threads, atravessou. */
        const int dom = topologia(cpu, "cache/index3/id");
        if (dom >= 0) {
            if (l3 < 0) l3 = dom;
            else if (dom != l3) ccd = 1;
        }
    }
    if (ccd && smt)      snprintf(buf, n_buf, "  <- cruza CCD e SMT");
    else if (ccd)        snprintf(buf, n_buf, "  <- cruza CCD");
    else if (smt)        snprintf(buf, n_buf, "  <- cruza SMT");
    else                 buf[0] = '\0';
}

static double measure_malloc(unsigned n)
{
    atomic_store(&start_flag, 0); atomic_store(&ns_total, 0);

    /* ESPELHAR A COLOCAÇÃO É CONDIÇÃO DE VALIDADE, e a falta disso invalidava
     * a comparação inteira deste programa.
     *
     * `rte_eal_init()` fixa a thread principal num único núcleo, e
     * `pthread_create()` HERDA a máscara de afinidade de quem cria. Sem o
     * ajuste abaixo, as n threads do malloc disputavam UMA CPU enquanto
     * `medir_pool` usava n lcores em n CPUs distintas -- e a razão publicada
     * media 1 núcleo contra n, não malloc contra mempool.
     *
     * Sonda que comprova a herança, com -l 0-7:
     *     main apos rte_eal_init  CPUs permitidas: 0
     *     thread pthread_create   CPUs permitidas: 0
     *
     * Cada thread recebe agora a MESMA CPU que o lcore correspondente usaria. */
    int cpus[MAX_THREADS];
    unsigned n_cpus = 0;
    unsigned id;
    RTE_LCORE_FOREACH(id) {
        if (n_cpus >= n || n_cpus >= MAX_THREADS)
            break;
        const int c = cpu_of_lcore(id);
        if (c >= 0)
            cpus[n_cpus++] = c;
    }
    /* Dimensionado pelo MESMO teto que limita `n` em main(), e não por um 32
     * solto: `n` dobra até rte_lcore_count(), então numa máquina de 64 lcores
     * ele chega a 64 e este laço escreveria t[0..62] -- 63 elementos num vetor
     * de 32, corrompendo a pilha. Passava despercebido porque a máquina de
     * referência tem 24 lcores, e aí `n` para em 16. */
    pthread_t t[MAX_THREADS];
    if (n > MAX_THREADS) {
        fprintf(stderr, "measure_malloc: n=%u above the ceiling of %u threads\n", n, MAX_THREADS);
        return AMOSTRA_INVALIDA;
    }
    /* A thread principal fica no cpus[0] -- onde a EAL já a colocou -- e cada
     * filha recebe a CPU do lcore seguinte, uma por núcleo, como no lado do
     * mempool.
     *
     * A COLOCAÇÃO É A COMPARAÇÃO, e por isso falhar aqui elimina a amostra.
     * A versão anterior imprimia `warning: could not pin` e media assim mesmo,
     * dizendo em comentário que isso era "avisar em vez de mentir sobre a
     * colocação" -- mas avisar e publicar é a mentira, e é exatamente a classe
     * de defeito que o `fixar_cpu.h` eliminou nos outros sete programas.
     *
     * O retorno de `pthread_create` também é conferido, e não por simetria: o
     * laço antigo o descartava e logo depois chamava `pthread_join(t[i], NULL)`
     * sobre um `pthread_t` que podia nunca ter sido escrito -- comportamento
     * indefinido, não viés de medição. Agora só se espera pelo que subiu. */
    unsigned criadas = 0;
    int invalida = 0;
    for (unsigned i = 0; i + 1 < n; i++) {
        pthread_attr_t at;
        pthread_attr_init(&at);
        if (i + 1 >= n_cpus) {
            fprintf(stderr, "  AMOSTRA INVALIDA: sem CPU para a thread %u"
                            " (%u lcore(s) mapeado(s) para %u pedida(s))\n",
                    i, n_cpus, n);
            invalida = 1;
        } else {
            cpu_set_t cs;
            CPU_ZERO(&cs);
            CPU_SET(cpus[i + 1], &cs);
            if (pthread_attr_setaffinity_np(&at, sizeof(cs), &cs) != 0) {
                fprintf(stderr, "  AMOSTRA INVALIDA: nao fixei a thread %u na"
                                " CPU %d; a linha compararia %u nucleo(s)"
                                " contra outro numero\n", i, cpus[i + 1], n);
                invalida = 1;
            }
        }
        if (pthread_create(&t[criadas], &at, worker_malloc, NULL) != 0) {
            fprintf(stderr, "  AMOSTRA INVALIDA: pthread_create falhou na"
                            " thread %u de %u\n", i, n);
            invalida = 1;
            pthread_attr_destroy(&at);
            break;
        }
        criadas++;
        pthread_attr_destroy(&at);
    }
    /* A LIBERACAO E O JOIN ACONTECEM MESMO NA AMOSTRA INVALIDA. As threads que
     * subiram estao giradas na `start_flag`; voltar daqui sem solta-las
     * deixaria o processo pendurado no proximo ponto, e uma medicao recusada
     * nao pode virar travamento. */
    atomic_store_explicit(&start_flag, 1, memory_order_release);
    worker_malloc(NULL);
    for (unsigned i = 0; i < criadas; i++) pthread_join(t[i], NULL);
    if (invalida || criadas + 1 != n)
        return AMOSTRA_INVALIDA;
    return (double)atomic_load(&ns_total) / 1000.0 / (criadas + 1);
}

int main(int argc, char **argv)
{
    print_provenance("custo-contencao");
    if (rte_eal_init(argc, argv) < 0) { fprintf(stderr,"EAL: %s\n", rte_strerror(rte_errno)); return 2; }
    const unsigned cache = argc > 1 ? (unsigned)atoi(argv[argc-1]) : 0;
    printf("\n== Contention over the SAME source of objects ==\n");
    printf("  pool of %u objects of %u B, batch %u, per-lcore cache = %u\n", OBJS, TAM, BURST, cache);
    printf("  lcores available: %u\n\n", rte_lcore_count());
    pool = rte_mempool_create("p", OBJS, TAM, cache, 0, NULL,NULL,NULL,NULL,(int)rte_socket_id(),0);
    if (!pool) { fprintf(stderr,"pool: %s\n", rte_strerror(rte_errno)); return 1; }
    /* REPETICOES, e nao uma medida so.
     *
     * O lado do mempool fica em sub-nanossegundo com muitas threads, e ai o
     * ruido de escalonamento domina: cinco execucoes de uma versao anterior
     * deste programa deram razoes de 86,8x a 110,8x para o mesmo caso -- com o
     * malloc estavel em +-0,6% e toda a variacao vindo do mempool. Publicar
     * "98x" com duas casas seria precisao inventada.
     *
     * Mediana e dispersao robusta, como em todo o resto do projeto. */
    const int R = samples(9);
    double *vp = malloc((size_t)R * sizeof(double));
    double *vm = malloc((size_t)R * sizeof(double));
    if (vp == NULL || vm == NULL) { fprintf(stderr, "out of memory\n"); return 1; }

    printf("  repetitions per point: %d (median; disp = IQR/median)\n\n", R);
    printf("  %-8s %20s %20s %10s\n", "threads", "mempool", "malloc", "ratio");
    printf("  %-8s %20s %20s %10s\n", "-------", "-------", "------", "-----");
    /* UMA CELULA INVALIDA CONTAMINA A LINHA INTEIRA, e nao so a repeticao.
     *
     * A mediana de R repeticoes esconde uma amostra recusada: bastaria
     * descarta-la e seguir com R-1 para a tabela sair com aparencia normal e
     * numero de repeticoes diferente do declarado no cabecalho. A linha inteira
     * sai como INVALIDA, e o programa termina com codigo diferente de zero --
     * depois do `rte_eal_cleanup()`. */
    int linhas_invalidas = 0;
    for (unsigned n = 1; n <= rte_lcore_count(); n *= 2) {
        measure_pool(n); measure_malloc(n);                 /* aquecimento */
        int valida = 1;
        for (int i = 0; i < R; i++) {
            vp[i] = measure_pool(n); vm[i] = measure_malloc(n);
            if (vp[i] < 0.0 || vm[i] < 0.0) valida = 0;
        }
        if (!valida) {
            printf("  %-8u %20s %20s %10s   LINHA INVALIDA (ver stderr)\n",
                   n, "--", "--", "--");
            linhas_invalidas++;
            continue;
        }
        const struct statistics ep = summarize(vp, R), em = summarize(vm, R);
        char fronteira[32];
        marcar_fronteira(fronteira, sizeof(fronteira), n);
        /* UMA CASA ABAIXO DE 10, E NAO `%.0f` SEMPRE.
         *
         * Com 8 threads o mempool PERDE do malloc, e a razao vira 0,21 --
         * que `%.0f` imprime como `0x`. O documento publicava `0,2x` porque
         * alguem calculou a mao o que o programa nao sabia dizer, e numero
         * transcrito a mao e numero sem quem o confira. */
        const double razao = ep.median > 0 ? em.median / ep.median : 0.0;
        if (razao < 10.0)
            printf("  %-8u %11.2f ns %5.0f%% %11.2f ns %5.0f%% %8.1fx%s\n", n, ep.median,
                   ep.disp, em.median, em.disp, razao, fronteira);
        else
            printf("  %-8u %11.2f ns %5.0f%% %11.2f ns %5.0f%% %9.0fx%s\n", n, ep.median,
                   ep.disp, em.median, em.disp, razao, fronteira);
    }
    free(vp); free(vm);
    printf("\n  The marks on the right say which boundary each row crosses.\n");
    printf("  Rows are NOT comparable across a mark: with more threads than\n");
    printf("  physical cores in one L3 domain, contention starts crossing the\n");
    printf("  interconnect; past the physical core count, two threads share one\n");
    printf("  core's execution units. Three factors, one column.\n");
    printf("\n");
    if (linhas_invalidas > 0)
        printf("  %d linha(s) NAO foram medidas nas condicoes que o rotulo"
               " declara; a tabela esta incompleta.\n\n", linhas_invalidas);
    rte_mempool_free(pool); rte_eal_cleanup();
    /* O CODIGO DE SAIDA DEPOIS DO CLEANUP. Quem le a tabela ve a linha
     * INVALIDA; quem automatiza le o `$?`, e os dois precisam concordar. */
    return linhas_invalidas > 0 ? 1 : 0;
}
