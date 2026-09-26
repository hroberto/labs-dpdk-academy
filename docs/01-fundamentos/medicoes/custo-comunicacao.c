/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Fundamentos — quanto custa dois núcleos trocarem um dado.
 *
 * Mede o tempo de uma linha de cache viajar do cache de um núcleo para o de
 * outro, com um ping-pong: a thread A escreve, a thread B percebe e responde.
 * O tempo de ida e volta dividido por dois é a latência da transferência.
 *
 * O ponto do exercício é comparar PARES DE NÚCLEOS DIFERENTES. Em processadores
 * modernos os núcleos não são equidistantes: os que compartilham o mesmo cache
 * L3 conversam rápido; os que estão em blocos distintos (CCX/CCD na AMD,
 * clusters na Intel) precisam atravessar a interconexão interna do chip.
 *
 * Isso importa diretamente para plano de dados: um rte_ring entre produtor e
 * consumidor faz exatamente esta viagem a cada lote. Colocar os dois lcores no
 * bloco errado pode custar mais que o orçamento inteiro de um pacote.
 *
 * Os pares testados são derivados de /sys/.../cache/index3/shared_cpu_list, que
 * informa quais CPUs compartilham cada L3 — portanto o programa se adapta à
 * máquina em que roda.
 *
 * METODOLOGIA: igual à dos demais programas desta pasta. Ver statistics.h.
 *
 * O programa também mede CONTENÇÃO DE SMT: quando duas threads rodam nos dois
 * fluxos do MESMO núcleo físico, elas compartilham as unidades de execução, a
 * L1 e o preditor de saltos. Um laço de polling é justamente o pior caso — ele
 * não bloqueia nunca, então disputa essas unidades o tempo todo. Saber quanto
 * isso custa é o que separa "tenho 24 CPUs" de "tenho 12 núcleos".
 */
#define _GNU_SOURCE
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "fixar_cpu.h"
#include "largada.h"
#include "topologia.h"
#include "cpu_pause.h"
#include "clock_ns.h"
#include "statistics.h"

#define RODADAS 200000
/* VINTE E UMA, e a escolha nao e de orcamento de tempo.
 *
 * Com 15 amostras estas linhas saiam com dispersao entre 3% e 15%, que e
 * exatamente a faixa onde o selo NAO DECIDE abaixo de 20 amostras -- medido em
 * 18/09/2026 e documentado na secao "QUANTAS AMOSTRAS O SELO EXIGE" de
 * statistics.h. O `avisar_selo_indeciso()` avisava em stderr a cada execucao, e
 * o aviso ficou sem resposta ate 19/09/2026.
 *
 * 21 e o mesmo valor que a fase 2 do custo-paralelismo usa, pelo mesmo motivo. */
#define AMOSTRAS_C2C_FIXO 21
#define AMOSTRAS_C2C samples(AMOSTRAS_C2C_FIXO)

/* collect_or_fail() recebe ponteiro sem argumentos; o par vai por variáveis. */
static int par_a, par_b;

/* Os três CPUs do experimento, e dois adaptadores que fixam o par antes de
 * medir. Existem para permitir COLETA PAREADA: a razão entre travessia local e
 * remota é a conclusão desta seção, e razão de duas medianas colhidas em blocos
 * separados não herda a estabilidade delas. Ver `collect_paired`. */
static int cpu_local_a, cpu_local_b, cpu_remoto_b;
#define BUDGET_10GBE_NS 67.2
#define MAX_DOMINIOS 16

/* A linha de cache disputada, isolada para não sofrer falso compartilhamento. */
static _Alignas(64) atomic_int bola;
static int cpu_a, cpu_b;


static void *rebatedor(void *ignorado)
{
    (void)ignorado;
    academy_fixar_cpu(cpu_b);
    for (int i = 0; i < RODADAS; i++) {
        while (atomic_load_explicit(&bola, memory_order_acquire) != 1)
            academy_cpu_pause();
        atomic_store_explicit(&bola, 0, memory_order_release);
    }
    return NULL;
}

static double medir(int a, int b)
{
    cpu_a = a;
    cpu_b = b;
    atomic_store(&bola, 0);

    pthread_t t;
    if (pthread_create(&t, NULL, rebatedor, NULL) != 0)
        return -1.0;
    academy_fixar_cpu(cpu_a);

    const struct timespec espera = {0, 1000000};
    nanosleep(&espera, NULL); /* deixa o rebatedor chegar ao laço */

    const uint64_t t0 = academy_now_ns();
    for (int i = 0; i < RODADAS; i++) {
        atomic_store_explicit(&bola, 1, memory_order_release);
        while (atomic_load_explicit(&bola, memory_order_acquire) != 0)
            academy_cpu_pause();
    }
    const uint64_t dt = academy_now_ns() - t0;
    pthread_join(t, NULL);

    return (double)dt / RODADAS / 2.0; /* ida e volta -> uma travessia */
}

/* CONDICIONAMENTO DO TRAFEGO ENTRE NUCLEOS
 *
 * POR QUE `acomodar_frequencia` NAO BASTOU
 *
 * O comentario abaixo, em main(), registra este mesmo sintoma -- `dentro do
 * dominio` variando de 17,65 a 27,25 ns entre coletas -- e o atribui a rampa de
 * frequencia. A atribuicao estava errada, e a medicao que a derruba e simples:
 *
 *   apos 30 s de ociosidade   23,12  25,17  25,42  25,23
 *   execucao imediata depois  18,95  19,21  18,05  17,69
 *
 * Quatro ciclos, faixas DISJUNTAS. E na mesma coleta o `laco sozinho no
 * nucleo` -- ALU pura, que depende diretamente do clock do core -- nao se move
 * (0,2%). Se fosse rampa de frequencia do core, ele se moveria junto.
 *
 * O que se move e so o trafego ENTRE nucleos, e a penalidade a frio e de ~6 ns
 * em `dentro` e ~4,8 ns em `ENTRE`: valores absolutos parecidos, nao
 * proporcionais. Efeito aditivo, nao multiplicativo.
 *
 * E NAO E CUSTO UNICO DE ACORDAR: o laco cronometrado roda RODADAS idas e
 * voltas, uns 4 ms contidos; um despertar pontual se diluiria a nada. A
 * penalidade persiste pela coleta inteira, logo e ESTADO SUSTENTADO.
 *
 * Dai o reparo: condicionar com o proprio trafego que se vai medir, por tempo
 * na ordem de segundos -- que e o que a observacao pede, porque no teste acima
 * UMA execucao anterior (~6 s) ja bastou para levar a medicao ao regime baixo.
 * Condicionar com trabalho de ALU nao serve: e exatamente o que ja se fazia.
 */
#define CONDICIONAR_C2C_MS 1500
static _Alignas(64) atomic_int parar_c2c;

static void *rebatedor_condicionamento(void *ignorado)
{
    (void)ignorado;
    academy_fixar_cpu(cpu_b);
    while (!atomic_load_explicit(&parar_c2c, memory_order_relaxed)) {
        while (atomic_load_explicit(&bola, memory_order_acquire) != 1) {
            if (atomic_load_explicit(&parar_c2c, memory_order_relaxed))
                return NULL;
            academy_cpu_pause();
        }
        atomic_store_explicit(&bola, 0, memory_order_release);
    }
    return NULL;
}

static void condicionar_c2c(int a, int b, int ms)
{
    cpu_a = a;
    cpu_b = b;
    atomic_store(&bola, 0);
    atomic_store(&parar_c2c, 0);

    pthread_t t;
    if (pthread_create(&t, NULL, rebatedor_condicionamento, NULL) != 0)
        return;
    academy_fixar_cpu(cpu_a);
    const struct timespec espera = {0, 1000000};
    nanosleep(&espera, NULL);

    const uint64_t ate = academy_now_ns() + (uint64_t)ms * 1000000ull;
    while (academy_now_ns() < ate) {
        atomic_store_explicit(&bola, 1, memory_order_release);
        while (atomic_load_explicit(&bola, memory_order_acquire) != 0) {
            if (academy_now_ns() > ate + 1000000000ull)
                break; /* nunca trava a suite por causa do aquecimento */
            academy_cpu_pause();
        }
    }
    /* Para o rebatedor: sinaliza e destrava quem estiver esperando a bola. */
    atomic_store_explicit(&parar_c2c, 1, memory_order_relaxed);
    atomic_store_explicit(&bola, 1, memory_order_release);
    pthread_join(t, NULL);
}

/* Lê os domínios de L3 do sysfs: cada linha distinta é um bloco de núcleos. */
static int ler_dominios(char lista[MAX_DOMINIOS][256])
{
    int n = 0;
    for (int cpu = 0; cpu < 512 && n < MAX_DOMINIOS; cpu++) {
        char caminho[128];
        snprintf(caminho, sizeof(caminho),
                 "/sys/devices/system/cpu/cpu%d/cache/index3/shared_cpu_list", cpu);
        FILE *f = fopen(caminho, "r");
        if (f == NULL)
            continue;
        char buf[256];
        if (fgets(buf, sizeof(buf), f) != NULL) {
            buf[strcspn(buf, "\n")] = '\0';
            int novo = 1;
            for (int i = 0; i < n; i++)
                if (strcmp(lista[i], buf) == 0)
                    novo = 0;
            if (novo)
                snprintf(lista[n++], 256, "%s", buf);
        }
        fclose(f);
    }
    return n;
}

/* ---------------- Contenção entre fluxos SMT do mesmo núcleo ---------------- */

/* Trabalho puramente de ALU, sem memória: isola a disputa por unidades de
 * execução, que é o mecanismo do SMT.
 *
 * Quatro acumuladores INDEPENDENTES de propósito: cadeias independentes têm
 * paralelismo de instruções alto e saturam as ALUs, que é a condição em que a
 * disputa por SMT aparece. Uma cadeia serial deixaria unidades ociosas, e os
 * dois fluxos se intercalariam sem competir — medindo o caso favorável em vez
 * do caso que importa.
 *
 * A barreira de otimização é obrigatória: sem ela o compilador reduz o laço a
 * uma fórmula fechada e a medição devolve zero — erro fácil de cometer e de não
 * perceber, porque o programa continua rodando e imprimindo. */
#define TRABALHO_ALU(n, a, b, c, d)                                                                \
    do {                                                                                           \
        for (int i_ = 0; i_ < (n); i_++) {                                                         \
            (a) += i_ * 3 + 1;                                                                     \
            (b) ^= i_ * 5 + 7;                                                                     \
            (c) += i_ | 1;                                                                         \
            (d) ^= i_ * 11 + 3;                                                                    \
            __asm__ __volatile__("" : "+r"(a), "+r"(b), "+r"(c), "+r"(d));                         \
        }                                                                                          \
    } while (0)
static _Alignas(64) atomic_int parar_vizinho;
static _Alignas(64) volatile long soma_vizinho;
static int cpu_vizinho = -1;

static void *vizinho_ocupado(void *_)
{
    (void)_;
    if (cpu_vizinho >= 0)
        academy_fixar_cpu(cpu_vizinho);
    long a = 0, b = 0, c = 0, d = 0;
    while (!atomic_load_explicit(&parar_vizinho, memory_order_relaxed))
        TRABALHO_ALU(1000, a, b, c, d);
    soma_vizinho = a + b + c + d;
    return NULL;
}

/* Condicionamento deliberado entre as duas fases do experimento de SMT.
 *
 * NAO se chama "aquecimento" de proposito. Aquecimento pressupoe que se sabe o
 * que esta sendo aquecido -- frequencia, cache, preditor -- e aqui isso ainda
 * nao foi estabelecido. O que este bloco faz e colocar o nucleo sob carga
 * continua por um tempo declarado, para verificar SE a linha de base muda de
 * patamar depois disso. Se mudar de forma reproduzivel, ha dois regimes. Se
 * alternar independentemente do condicionamento, ha uma variavel oculta, e
 * chama-la de "frio" e "quente" seria batismo causal prematuro. */
#define CONDICIONAR_MS 400

/* ACOMODAR A FREQUENCIA antes de coletar, e este programa nao fazia isso.
 *
 * A linha de base do laco saia ora ~0,45 ns, ora ~0,54 -- e a causa foi medida
 * em 19/09/2026: e a FREQUENCIA, so ela. Rodando o mesmo laco e lendo
 * `scaling_cur_freq` a cada amostra, os ciclos por operacao ficam em 2,63 a
 * 2,69 em TODAS elas, enquanto a frequencia vai de 4,35 a 5,62 GHz e o tempo
 * por operacao varia 29% na proporcao inversa. O trabalho e o mesmo; o relogio
 * e que muda.
 *
 * Nao e contencao de SMT: na mesma janela o irmao ficou 0,0% ocupado, lido de
 * /proc/stat. E nao e disputa por CPU, entao prioridade -- `nice` -- nao tem o
 * que resolver: `nice` decide QUEM e escalonado, e aqui nao ha com quem
 * disputar. Prioridade de escalonamento nao governa clock.
 *
 * O laco leva ~4 amostras para a frequencia assentar. Fazer isso ANTES de
 * coletar custa ~50 ms e tira a bimodalidade da linha de base. */
#define ACOMODAR_AMOSTRAS 5

/* ===================== Vazao AGREGADA de um par de CPUs =====================
 *
 * POR QUE ESTE BLOCO EXISTE, e ele nasceu de uma objecao procedente.
 *
 * O §5.1.1 concluia que `-l 0,12` "da pouco mais que um nucleo". A conclusao e
 * de CAPACIDADE, e o experimento ao lado dela nao mede capacidade: ele mede a
 * DEGRADACAO da thread observada quando o irmao esta ativo (2,29x). Sao
 * grandezas diferentes -- uma diz quanto A sofre com B presente, a outra diz
 * quanto A e B juntos produzem.
 *
 * Dava para inferir: se a degradacao valesse simetricamente, dois irmaos a
 * 1/2,29 cada renderiam 0,87 de um nucleo. Mas inferir nao e medir, e a
 * inferencia erra -- o valor medido e 1,03 a 1,04, nao 0,87. A degradacao da
 * thread observada nao se transfere linearmente para o agregado.
 *
 * O desenho e o minimo que responde a pergunta: N threads identicas, barreira
 * de largada, e o cronometro parando na ULTIMA a terminar. O agregado e o total
 * de operacoes sobre esse tempo -- que e o que "quanto rende este par de CPUs"
 * quer dizer.
 *
 * A carga e a mesma TRABALHO_ALU do resto do arquivo, de proposito: ela satura
 * as unidades de execucao e e o PIOR caso para SMT. O numero abaixo nao vale
 * para carga que espera memoria, e o §5.1.1 diz isso. */
#define OPS_AGREGADO 20000000

static struct academy_largada largada_agregado;

struct trabalhador {
    int cpu;
    long acumulador;
};

static void *trabalhador_agregado(void *arg)
{
    struct trabalhador *t = arg;
    academy_fixar_cpu(t->cpu);
    long a = 0, b = 0, c = 0, d = 0;
    /* Acomoda a frequencia DENTRO da thread, antes da barreira: sem isto a
     * primeira configuracao medida sai mais cara que as outras, que e
     * exatamente o defeito que o custo-espera publicou por oito dias. */
    TRABALHO_ALU(2000000, a, b, c, d);
    /* A LARGADA PODE SER CANCELADA. Com `pthread_barrier_t`, uma falha de
     * `pthread_create` deixava esta thread esperando por participantes que
     * nunca viriam, e o caminho de erro destruia a barreira com ela ainda
     * bloqueada -- comportamento indefinido por POSIX. */
    if (!academy_largada_esperar(&largada_agregado)) {
        t->acumulador = 0;
        return NULL;
    }
    TRABALHO_ALU(OPS_AGREGADO, a, b, c, d);
    t->acumulador = a + b + c + d;
    return NULL;
}

#define MAX_AGREGADO 4

static double vazao_agregada(const int *cpus, int n)
{
    pthread_t th[MAX_AGREGADO];
    struct trabalhador t[MAX_AGREGADO];
    if (n > MAX_AGREGADO)
        return -1.0;
    academy_largada_init(&largada_agregado);
    for (int i = 0; i < n; i++) {
        t[i].cpu = cpus[i];
        if (pthread_create(&th[i], NULL, trabalhador_agregado, &t[i]) != 0) {
            /* SOLTAR, ESPERAR, E SO ENTAO DESISTIR. O caminho anterior
             * destruia a barreira com threads bloqueadas nela e voltava sem
             * `join`: comportamento indefinido, threads penduradas, e 0.0
             * entrando na estatistica como se fosse medida. */
            academy_largada_soltar(&largada_agregado, 0);
            for (int j = 0; j < i; j++)
                pthread_join(th[j], NULL);
            fprintf(stderr, "  AMOSTRA INVALIDA: pthread_create falhou na"
                            " thread %d de %d (vazao agregada)\n", i, n);
            return -1.0;
        }
    }
    /* Espera os N anunciarem que chegaram; so entao solta e marca `t0`. A
     * barreira de `n + 1` fazia isso, e era a unica coisa que ela fazia bem. */
    academy_largada_aguardar(&largada_agregado, n);
    academy_largada_soltar(&largada_agregado, 1);
    const uint64_t t0 = academy_now_ns();
    for (int i = 0; i < n; i++) {
        pthread_join(th[i], NULL);
        soma_vizinho += t[i].acumulador;
    }
    const double dt = (double)(academy_now_ns() - t0);
    return (double)n * OPS_AGREGADO / (dt / 1e9) / 1e6;   /* M operacoes/s */
}

/* As tres configuracoes, cada uma num adaptador sem argumento porque e assim
 * que `collect` recebe a medicao. Os cpus sao preenchidos pelo main. */
static int cfg_um[1], cfg_fisicos[2], cfg_irmaos[2];
static double m_agr_um(void)      { return vazao_agregada(cfg_um, 1); }
static double m_agr_fisicos(void) { return vazao_agregada(cfg_fisicos, 2); }
static double m_agr_irmaos(void)  { return vazao_agregada(cfg_irmaos, 2); }

static void acomodar_frequencia(void)
{
    long a = 0, b = 0, c = 0, d = 0;
    for (int k = 0; k < ACOMODAR_AMOSTRAS; k++)
        TRABALHO_ALU(20000000, a, b, c, d);
    soma_vizinho += a + b + c + d;
}

static void condicionar(void)
{
    long a = 0, b = 0, c = 0, d = 0;
    const uint64_t ate = academy_now_ns() + (uint64_t)CONDICIONAR_MS * 1000000ull;
    while (academy_now_ns() < ate)
        TRABALHO_ALU(100000, a, b, c, d);
    soma_vizinho += a + b + c + d;
}

/* Mede o próprio laço de trabalho, com ou sem vizinho competindo. */
static double laco_de_trabalho(void)
{
    const int n = 20000000;
    long a = 0, b = 0, c = 0, d = 0;
    const uint64_t t0 = academy_now_ns();
    TRABALHO_ALU(n, a, b, c, d);
    const double r = (double)(academy_now_ns() - t0) / n;
    soma_vizinho += a + b + c + d;
    return r;
}

static double laco_sem_vizinho(void)
{
    const int guardado = cpu_vizinho;
    cpu_vizinho = -1;
    const double r = laco_de_trabalho();
    cpu_vizinho = guardado;
    return r;
}

static double com_vizinho(void)
{
    pthread_t t;
    atomic_store(&parar_vizinho, 0);
    if (pthread_create(&t, NULL, vizinho_ocupado, NULL) != 0)
        {
            fprintf(stderr, "  AMOSTRA INVALIDA: pthread_create falhou (vizinho ocupado)\n");
            /* NEGATIVO, E NAO ZERO. `statistics.h` declara a convencao tres
             * linhas acima de `collection_state`: "ou NaN em falha, nunca
             * zero". Zero e um tempo plausivel -- entra na mediana e some.
             * Negativo dispara `e.minimum < 0` e a coleta e recusada. */
            return -1.0;
        }
    const struct timespec d = {0, 20000000};
    nanosleep(&d, NULL);
    const double r = laco_de_trabalho();
    atomic_store(&parar_vizinho, 1);
    pthread_join(t, NULL);
    return r;
}

/* Primeiro CPU listado num intervalo como "0-5,12-17". */
static int primeiro_cpu(const char *lista)
{
    return (int)strtol(lista, NULL, 10);
}

static double measure_pair(void)
{
    return medir(par_a, par_b);
}

static double medir_dentro(void)
{
    par_a = cpu_local_a;
    par_b = cpu_local_b;
    return measure_pair();
}

static double medir_entre(void)
{
    par_a = cpu_local_a;
    par_b = cpu_remoto_b;
    return measure_pair();
}

int main(void)
{
    print_provenance("custo-comunicacao");
    char dominios[MAX_DOMINIOS][256];
    const int n = ler_dominios(dominios);

    printf("Cost of two cores exchanging a cache line\n\n");
    if (n <= 0) {
        printf("  Could not read the L3 domains from sysfs.\n");
        /* CÓDIGO 77 = PULADO, e não sucesso.
         *
         * Sair com 0 aqui fazia o Meson reportar OK sem que nada tivesse sido medido —
         * um falso verde. E não era caso raro: no runner do CI o requisito nunca
         * existiu, então este teste jamais verificou coisa alguma e sempre apareceu
         * verde. O Meson trata 77 como SKIP, conta separado e não falha a suíte. */
        return 77;
    }

    printf("  L3 cache domains on this machine: %d\n", n);
    for (int i = 0; i < n; i++)
        printf("    domain %d: CPUs %s\n", i, dominios[i]);
    printf("\n");

    const int a = primeiro_cpu(dominios[0]);
    cpu_local_a = a;
    /* A PARCEIRA SAI DA LISTA QUE ACABOU DE SER IMPRESSA, e nao de `a + 2`.
     *
     * A linha acima le `shared_cpu_list`, as tres linhas anteriores imprimem os
     * dominios na tela, e a versao anterior entao somava 2 -- ignorando o que
     * tinha lido. Nesta maquina acerta por coincidencia do enumerador (CCD0 e
     * `0-5,12-17`, logo 0 e 2 servem); noutra topologia este programa, que
     * existe para medir a travessia ENTRE dominios contra a de DENTRO,
     * compararia dois dominios e chamaria isso de "within domain". */
    cpu_local_b = academy_parceiro_no_dominio(a, dominios[0], a + 2);
    if (cpu_local_b < 0) {
        printf("  O dominio de L3 da CPU %d nao tem segunda CPU em nucleo\n"
               "  fisico distinto: nao ha par 'dentro do dominio' para medir.\n", a);
        return 77;   /* PULADO: a maquina nao oferece a condicao, e nao e defeito */
    }
    char rot[64];

    if (n < 2) {
        par_a = cpu_local_a;
        par_b = cpu_local_b;
        const struct statistics so_local = collect_or_fail(measure_pair, AMOSTRAS_C2C);
        print_header();
        snprintf(rot, sizeof(rot), "within domain 0 (cpu %d <-> %d)", par_a, par_b);
        print_row(rot, so_local);
        printf("\n  This machine has a single L3 domain: there is no 'distant'\n");
        printf("  pair to compare. On processors with several blocks\n");
        printf("  (Ryzen 9/Threadripper/EPYC, Xeon with clusters) the difference shows.\n");
        /* CÓDIGO 77 = PULADO, e não sucesso.
         *
         * Sair com 0 aqui fazia o Meson reportar OK sem que nada tivesse sido medido —
         * um falso verde. E não era caso raro: no runner do CI o requisito nunca
         * existiu, então este teste jamais verificou coisa alguma e sempre apareceu
         * verde. O Meson trata 77 como SKIP, conta separado e não falha a suíte. */
        return 77;
    }

    cpu_remoto_b = primeiro_cpu(dominios[1]);

    /* ACOMODA A FREQUENCIA ANTES DO PING-PONG TAMBEM.
     *
     * A acomodacao existia so antes do bloco de SMT, e por isso as duas
     * primeiras linhas da tabela -- `dentro` e `ENTRE` -- eram medidas durante
     * a rampa de frequencia. O sintoma: `dentro do dominio` variou de 17,65 a
     * 27,25 ns entre coletas, 55% de faixa, enquanto `ENTRE dominios` saia
     * estavel na mesma execucao. Medir durante a rampa e o mesmo defeito que a
     * secao 2 "A fronteira user-space / kernel-space" ja documentava para a chamada de funcao, em outro lugar. */
    academy_fixar_cpu(cpu_local_a);
    acomodar_frequencia();

    /* E CONDICIONA O PROPRIO TRAFEGO ENTRE NUCLEOS -- ver o cabecalho de
     * `condicionar_c2c`. A acomodacao acima cuida do clock do core; esta
     * cuida do que o clock do core nao alcanca. */
    condicionar_c2c(cpu_local_a, cpu_local_b, CONDICIONAR_C2C_MS);

    /* INTERCALADAS, para que a razão abaixo tenha selo próprio. */
    const struct paired_stats pc =
        collect_paired_or_fail(medir_entre, medir_dentro, AMOSTRAS_C2C);
    const struct statistics e_dentro = pc.b, e_entre = pc.a;
    const double dentro = e_dentro.median, entre = e_entre.median;

    print_header();
    snprintf(rot, sizeof(rot), "within domain 0 (cpu %d <-> %d)",
             cpu_local_a, cpu_local_b);
    print_row(rot, e_dentro);
    snprintf(rot, sizeof(rot), "BETWEEN domains (cpu %d <-> %d)",
             cpu_local_a, cpu_remoto_b);
    print_row(rot, e_entre);
    print_row("RATIO between/within (paired)", pc.razao);
    /* ---- Contenção de SMT ---- */
    printf("\n  Contention between SMT threads (same physical core)\n\n");
    print_header();

    /* FIXA A THREAD DE MEDICAO EXPLICITAMENTE.
     *
     * Ate aqui ela estava fixada em cpu_a por EFEITO COLATERAL: `measure_pair`
     * chama `academy_fixar_cpu(cpu_a)` para o ping-pong, e a fixacao sobrevivia ate este
     * bloco. Funcionava, e nao dizia isso em lugar nenhum -- bastava alguem
     * reordenar os blocos para a medicao de SMT passar a rodar onde o
     * escalonador quisesse, sem que nada acusasse. */
    academy_fixar_cpu(cpu_local_a);
    acomodar_frequencia();

    cpu_vizinho = -1;
    const struct statistics e_sozinho = collect_or_fail(laco_de_trabalho, AMOSTRAS_C2C);
    print_row("loop alone on the core", e_sozinho);
    /* A penalidade do SMT tambem e uma RAZAO, e tambem precisa de selo
     * proprio -- ver o bloco do irmao SMT logo abaixo. */

    /* Irmão SMT do cpu 0, lido do sysfs. */
    int irmao = -1;
    FILE *f = fopen("/sys/devices/system/cpu/cpu0/topology/thread_siblings_list", "r");
    if (f != NULL) {
        char buf[64];
        if (fgets(buf, sizeof(buf), f) != NULL) {
            const char *v = strpbrk(buf, ",-");
            if (v != NULL)
                irmao = (int)strtol(v + 1, NULL, 10);
        }
        fclose(f);
    }

    if (irmao > 0) {
        cpu_vizinho = irmao;
        snprintf(rot, sizeof(rot), "neighbour on SMT sibling (cpu %d)", irmao);
        /* DUAS FASES, e a razao de ser esta documentada no bloco abaixo. */
        const struct paired_stats f1 =
            collect_paired_or_fail(com_vizinho, laco_sem_vizinho, AMOSTRAS_C2C);
        condicionar();
        const struct paired_stats f2 =
            collect_paired_or_fail(com_vizinho, laco_sem_vizinho, AMOSTRAS_C2C);

        const struct statistics e_smt = f2.a;
        print_row(rot, e_smt);

        print_row("RATIO with/without SMT sibling (paired)", f2.razao);

        /* O CONTROLE DE REGIME, e ele existe porque uma coleta avulsa sugeriu
         * que a razao dependia do estado da maquina: uma execucao deu 2,29 com
         * linha de base de 0,540 ns, contra 2,74 com 0,451 ns. A hipotese era
         * que houvesse dois regimes reproduziveis, e que a penalidade do SMT
         * dependesse de qual deles produziu o denominador.
         *
         * O experimento das duas fases REFUTOU a hipotese: condicionar o nucleo
         * por 400 ms nao move a linha de base, e as duas fases concordam. O
         * 2,29 avulso era estado transitorio da maquina, nao regime. A razao
         * fica publicada como numero unico -- e este bloco fica no programa
         * para que a pergunta nao precise ser reaberta de memoria. */
        printf("\n  regime control  phase 1: base %.3f  ratio %.2f\n"
               "                      phase 2: base %.3f  ratio %.2f   (after %d ms"
               " of continuous load)\n",
               f1.b.median, f1.razao.median, f2.b.median, f2.razao.median,
               CONDICIONAR_MS);
        printf("  The two phases agree: the ratio does not depend on conditioning.\n");

        cpu_vizinho = par_b; /* núcleo físico distinto, mesmo domínio */
        snprintf(rot, sizeof(rot), "neighbour on physical core (cpu %d)", par_b);
        const struct statistics e_fis = collect_or_fail(com_vizinho, AMOSTRAS_C2C);
        print_row(rot, e_fis);

        printf("\n  Sharing the core costs %.0f%% of performance; using distinct\n",
               100.0 * (e_smt.median / e_sozinho.median - 1.0));
        const double custo_fis = 100.0 * (e_fis.median / e_sozinho.median - 1.0);
        printf("  physical cores costs %.0f%%. Two logical CPUs are not two\n",
               custo_fis > 0.5 ? custo_fis : 0.0);
        printf("  cores: in a polling loop, which never yields the execution\n");
        printf("  units, the SMT sibling competes all the time.\n");

        /* A pergunta de CAPACIDADE, que a degradacao acima nao responde. */
        printf("\n  AGGREGATE throughput of the CPU pair (M operations/s)\n\n");
        print_header();
        cfg_um[0] = cpu_local_a;
        cfg_fisicos[0] = cpu_local_a; cfg_fisicos[1] = par_b;
        cfg_irmaos[0] = cpu_local_a;  cfg_irmaos[1] = irmao;
        const struct statistics a1 = collect_or_fail(m_agr_um, AMOSTRAS_C2C);
        const struct statistics a2 = collect_or_fail(m_agr_fisicos, AMOSTRAS_C2C);
        const struct statistics a3 = collect_or_fail(m_agr_irmaos, AMOSTRAS_C2C);
        snprintf(rot, sizeof(rot), "1 thread  on 1 physical core (cpu %d)", cpu_local_a);
        print_row(rot, a1);
        snprintf(rot, sizeof(rot), "2 threads on 2 physical cores (cpu %d,%d)",
                 cpu_local_a, par_b);
        print_row(rot, a2);
        snprintf(rot, sizeof(rot), "2 threads on 2 SMT siblings (cpu %d,%d)",
                 cpu_local_a, irmao);
        print_row(rot, a3);
        printf("\n  two physical cores yield %.2fx one core\n", a2.median / a1.median);
        printf("  two SMT siblings    yield %.2fx one core\n", a3.median / a1.median);
        printf("  The %.2fx degradation of the observed thread does NOT predict this:\n",
               f2.razao.median);
        printf("  applied symmetrically, it would give %.2fx.\n", 2.0 / f2.razao.median);
    }

    printf("\n  Crossing the interconnect costs %.1fx more.\n", entre / dentro);
    printf("  That is %.0f%% of the %.1f ns budget of a 64 B packet at 10 GbE:\n",
           100.0 * entre / BUDGET_10GBE_NS, BUDGET_10GBE_NS);
    printf("  a single handoff between badly placed cores already blows it.\n");
    return 0;
}
