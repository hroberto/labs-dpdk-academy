/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Fundamentos — o custo real de esperar por trabalho.
 *
 * É comum atribuir o custo da sincronização ao "mutex". Esta medição mostra que
 * a conta é outra, comparando o mesmo primitivo em DOIS CENÁRIOS:
 *
 *   SEM DISPUTA  - ninguém mais quer o mesmo primitivo ao mesmo tempo. Não é o
 *                  mesmo que "uma thread só": um processo com dezenas de
 *                  threads tem travas sem disputa o tempo todo. Sem quem
 *                  esperar nem quem acordar, o primitivo toma seu caminho
 *                  rápido, em espaço de usuário. É o PISO do custo.
 *                  (Quantas threads existem no processo é um eixo separado, e
 *                  as duas linhas de mutex mostram que ele também pesa.)
 *
 *   NO REPASSE   - duas threads, em núcleos diferentes, alternando entrega e
 *                  devolução. Aqui o primitivo faz aquilo para que existe, e ao
 *                  piso somam-se a migração da linha de cache entre os núcleos
 *                  e, se a thread bloquear, o custo de dormir e ser acordada.
 *
 * Os dois cenários não são opostos: o primeiro isola o primitivo, o segundo o
 * coloca para trabalhar. Comparando-os, separam-se três custos:
 *
 *   1. O CUSTO DO PRIMITIVO em si, sem disputa e sem travessia de núcleo.
 *      Um mutex sem contenção resolve tudo em espaço de usuário (caminho rápido
 *      do futex, sem chamada de sistema) e custa poucos nanossegundos.
 *
 *   2. O CUSTO DA TRAVESSIA entre núcleos: a linha de cache que carrega o dado
 *      precisa migrar de um cache para o outro. Independe do primitivo.
 *
 *   3. O CUSTO DE DORMIR: quando a thread realmente bloqueia, entra o
 *      escalonador — chamada de sistema, marcação de pronto, troca de contexto.
 *      É aqui que mora a ordem de grandeza que inviabiliza o plano de dados.
 *
 * A comparação decisiva é entre as duas últimas linhas do grupo 2: o MESMO
 * mutex, usado sem dormir e com condvar. A diferença é exclusivamente o sono.
 *
 * METODOLOGIA: o grupo 1 repete cada medição DEFAULT_SAMPLES vezes (25) e o
 * grupo 2 repete AMOSTRAS_REPASSE vezes (15, porque o repasse é caro); o
 * resultado é
 * publicado como mediana, mínimo, intervalo interquartil e coeficiente de
 * variação. Ver statistics.h para por que esses quatro, e não uma média.
 * Medições com dispersão alta são marcadas, para que o leitor saiba quando
 * desconfiar em vez de precisar adivinhar.
 *
 * Antes de tudo há uma fase de AQUECIMENTO. Sem ela, a primeira medição sai
 * sistematicamente pior: o processo começa com a frequência da CPU baixa, as
 * caches frias e as páginas ainda não faltadas. Medir nesse estado mede o
 * arranque, não o regime permanente.
 *
 * Nota sobre C++: a versão espelhada em custo-espera-cpp.cpp permite comparar.
 * Ver scripts/validar-cpp-vs-c.sh.
 */
#define _GNU_SOURCE
#include <pthread.h>
#include <sched.h>
#include <semaphore.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>

#include "cpu_pause.h"
#include "clock_ns.h"
#include "statistics.h"

/* AS MACROS ABAIXO NAO PODEM APARECER NA CONDICAO DE UM LACO.
 *
 * `rounds()` chama `getenv()`. Escrita como `for (i = 0; i < RODADAS_PRIMITIVO;
 * i++)`, a macro e reavaliada A CADA ITERACAO, e cada iteracao paga uma
 * varredura do ambiente: ~30 ns somados ao custo de UMA operacao atomica que
 * custa 0,2 ns. Medido em 18/09/2026, o mesmo laco deu 30,649 ns com a macro na
 * condicao e 0,204 ns com o valor lido uma vez antes -- 150 vezes.
 *
 * Foi o que aconteceu com este arquivo: as macros entraram em 25b3547, para a
 * CI poder baixar o custo, e a tabela do 5.2 ja estava publicada desde
 * bf57672, sete minutos antes. Ninguem reexecutou, entao o instrumento passou
 * a mentir sem que nenhum numero publicado mudasse de forma -- e o portao
 * continuou verde, porque portao nenhum roda a medicao e compara.
 *
 * Por isso cada funcao le o valor UMA vez, numa constante local. */
#define RODADAS_PRIMITIVO_FIXO 2000000
#define RODADAS_PRIMITIVO rounds(RODADAS_PRIMITIVO_FIXO)
#define RODADAS_REPASSE_FIXO_N 200000
#define RODADAS_REPASSE rounds(RODADAS_REPASSE_FIXO_N)
#define BUDGET_10GBE_NS 67.2

static int cpu_a = 0, cpu_b = 2;


static void fixar(int cpu)
{
    cpu_set_t c;
    CPU_ZERO(&c);
    CPU_SET(cpu, &c);
    pthread_setaffinity_np(pthread_self(), sizeof(c), &c);
}

/* Alinhado à linha de cache: sem isso, o compilador pode empacotá-lo na mesma
 * linha de outra variável escrita por outra thread, e a medição passa a medir
 * falso compartilhamento em vez do primitivo. */
static _Alignas(64) volatile long sumidouro;

/* ===================== Repetição e descarte da pior ===================== */

/* QUATROCENTOS, e o numero saiu de uma medicao, nao de um palpite.
 *
 * Com 60 ms, a `atomica relaxed` -- PRIMEIRA linha do grupo 1 -- publicava
 * mediana 0,206 ns com p75 em 0,259 e maximo em 0,411: dispersao de 26,2%,
 * enquanto as outras quatro linhas do MESMO grupo ficavam entre 0,1% e 0,3%.
 *
 * A sonda que decidiu mediu o MESMO primitivo duas vezes, em posicoes
 * diferentes do mesmo grupo, variando so o aquecimento:
 *
 *   aquecimento    relaxed (1a posicao)    relaxed (3a posicao)
 *   -----------    --------------------    --------------------
 *      60 ms            0.260 ns                0.201 ns
 *     200 ms            0.200 ns                0.202 ns
 *     400 ms            0.200 ns                0.202 ns
 *     800 ms            0.200 ns                0.202 ns
 *
 * Nao e o primitivo: e a POSICAO. Com 60 ms a primeira leitura sai 29% mais
 * cara que a terceira, e 29% e exatamente a amplitude da rampa de frequencia
 * desta maquina (4,35 -> 5,62 GHz). A partir de 200 ms as duas posicoes
 * concordam, e a dispersao publicada cai para menos de 1%.
 *
 * POR QUE SO ESTA LINHA sofria: 2M rodadas a ~0,2 ns sao 0,4 ms por amostra,
 * e 25 amostras sao 10 ms. A coleta inteira da `relaxed` cabe DENTRO da rampa.
 * A linha seguinte, o mutex a 8,5 ns, gasta 17 ms por amostra e ja comeca do
 * outro lado dela. O selo nao estava denunciando um primitivo instavel --
 * estava denunciando que a medicao mais barata da tabela e a unica curta o
 * bastante para caber no transiente.
 *
 * 400 ms, e nao 200, pela mesma razao que o custo-comunicacao usa 400 em
 * `condicionar()`: o limiar medido e onde o efeito some, nao onde se para. */
#define AQUECIMENTO_MS 400
/* O repasse é caro (o condvar leva ~1,3 us por par), então usa menos amostras
 * para o programa terminar em tempo razoável. Ainda é ordem de grandeza acima
 * das 3 repetições que este arquivo usava antes. */
/* VINTE E UMA, e a escolha nao e de orcamento de tempo.
 *
 * Com 15 amostras estas linhas saiam com dispersao entre 3% e 15%, que e
 * exatamente a faixa onde o selo NAO DECIDE abaixo de 20 amostras -- medido em
 * 18/09/2026 e documentado na secao "QUANTAS AMOSTRAS O SELO EXIGE" de
 * statistics.h. O `avisar_selo_indeciso()` avisava em stderr a cada execucao, e
 * o aviso ficou sem resposta ate 19/09/2026.
 *
 * 21 e o mesmo valor que a fase 2 do custo-paralelismo usa, pelo mesmo motivo. */
#define AMOSTRAS_REPASSE_FIXO 21
#define AMOSTRAS_REPASSE samples(AMOSTRAS_REPASSE_FIXO)

/* Gira em espaço de usuário para a CPU subir de frequência e as caches
 * aquecerem, antes de qualquer medição valer. */
static void aquecer(void)
{
    const uint64_t ate = academy_now_ns() + (uint64_t)AQUECIMENTO_MS * 1000000ull;
    long acumulador = 0;
    while (academy_now_ns() < ate)
        for (int i = 0; i < 10000; i++)
            acumulador += i;
    sumidouro = acumulador;
}


/* ================= Grupo 1: custo do primitivo, sem disputa ================= */

static _Alignas(64) atomic_int valor;

/* Alinhado: o mutex é ESCRITO a cada lock/unlock. Se dividir linha de cache com
 * qualquer variável tocada por outra thread — inclusive apenas LIDA em laço —,
 * a medição passa a medir invalidação de linha, não o mutex. A escala do erro
 * não é sutil: com a flag de parada da thread de ruído caindo 32 bytes antes do
 * mutex, o custo medido salta de 8 ns para 53 ns. */
static _Alignas(64) pthread_mutex_t mtx = PTHREAD_MUTEX_INITIALIZER;
static _Alignas(64) pthread_spinlock_t spin;

static double m_atomica_relaxed(void)
{
    const int n_rodadas = RODADAS_PRIMITIVO;
    const uint64_t t0 = academy_now_ns();
    for (int i = 0; i < n_rodadas; i++) {
        atomic_store_explicit(&valor, i, memory_order_relaxed);
        sumidouro = atomic_load_explicit(&valor, memory_order_relaxed);
    }
    return (double)(academy_now_ns() - t0) / n_rodadas;
}

static double m_mutex_simples(void)
{
    const int n_rodadas = RODADAS_PRIMITIVO;
    const uint64_t t0 = academy_now_ns();
    for (int i = 0; i < n_rodadas; i++) {
        pthread_mutex_lock(&mtx);
        sumidouro = i;
        pthread_mutex_unlock(&mtx);
    }
    return (double)(academy_now_ns() - t0) / n_rodadas;
}

/* Executa QUALQUER medição com uma thread de ruído presente no processo.
 *
 * Existe porque a contagem de threads é um eixo independente da disputa, e nem
 * todo primitivo reage a ela do mesmo jeito: instruções atômicas do hardware
 * não mudam, mas primitivos da biblioteca podem ter caminho rápido para
 * processo de uma thread só. Medir todos nos dois regimes é o que permite dizer
 * quais mudam — em vez de supor.
 *
 * O mesmo mutex, ainda sem disputa, mas num processo que já tem outra thread.
 *
 * A distinção importa: a glibc detecta processo de uma única thread e pula a
 * instrução atômica, porque não há com quem competir. Basta existir uma segunda
 * thread — mesmo que ela jamais toque neste mutex — para o caminho rápido
 * desaparecer e o custo subir ao de um CAS atômico de verdade.
 *
 * O valor multi-thread é o realista: nenhum programa concorrente paga o preço
 * mono-thread. */
static _Alignas(64) atomic_int parar_ruido;
static _Alignas(64) volatile long sumidouro_ruido;

static void *thread_ruido(void *_)
{
    (void)_;
    /* Fixada num núcleo físico distinto — nem o de medição nem seu irmão SMT —
     * para que só a existência da thread influa, e não a disputa por unidades
     * de execução. Não toca em mtx nem em sumidouro, e usa a própria linha de
     * cache. */
    fixar(cpu_b + 2);
    while (!atomic_load_explicit(&parar_ruido, memory_order_relaxed))
        sumidouro_ruido++;
    return NULL;
}

/* Ponteiro para a medição que deve rodar sob ruído. */
static double (*medicao_sob_ruido)(void);

static double com_outra_thread(void)
{
    pthread_t t;
    atomic_store(&parar_ruido, 0);
    if (pthread_create(&t, NULL, thread_ruido, NULL) != 0)
        return 0.0;
    const struct timespec d = {0, 20000000};
    nanosleep(&d, NULL);

    const double r = medicao_sob_ruido();

    atomic_store(&parar_ruido, 1);
    pthread_join(t, NULL);
    return r;
}

/* Coleta a medição no regime PADRÃO deste programa: com outra thread presente.
 *
 * Por que não medimos também com uma thread só: a glibc mantém um caminho
 * rápido para processos de thread única (__libc_single_threaded), que faz um
 * mutex custar ~2 ns em vez de ~8,5. Esse número é INVÁLIDO como referência,
 * por duas razões:
 *
 *   1. Nenhum programa concorrente o desfruta.
 *   2. Ele é perdido PERMANENTEMENTE na primeira criação de thread — mesmo
 *      depois de a thread ser juntada, __libc_single_threaded continua 0.
 *      Consequência prática: o valor medido dependia da ORDEM das medições
 *      dentro do programa, e mudava de 2,4 para 9,0 ns conforme a posição.
 *
 * Medição que depende da ordem em que se mede não é medição. */
static void measure_default(const char *rotulo, double (*m)(void))
{
    medicao_sob_ruido = m;
    print_row(rotulo, collect_or_fail(com_outra_thread, DEFAULT_SAMPLES));
}

static double m_atomica_seqcst(void)
{
    const int n_rodadas = RODADAS_PRIMITIVO;
    const uint64_t t0 = academy_now_ns();
    for (int i = 0; i < n_rodadas; i++) {
        atomic_store(&valor, i); /* seq_cst: barreira completa */
        sumidouro = atomic_load(&valor);
    }
    return (double)(academy_now_ns() - t0) / n_rodadas;
}

static double m_spinlock(void)
{
    const int n_rodadas = RODADAS_PRIMITIVO;
    const uint64_t t0 = academy_now_ns();
    for (int i = 0; i < n_rodadas; i++) {
        pthread_spin_lock(&spin);
        sumidouro = i;
        pthread_spin_unlock(&spin);
    }
    return (double)(academy_now_ns() - t0) / n_rodadas;
}

static double m_semaforo_livre(void)
{
    const int n_rodadas = RODADAS_PRIMITIVO;
    sem_t s;
    sem_init(&s, 0, 0);
    const uint64_t t0 = academy_now_ns();
    for (int i = 0; i < n_rodadas; i++) {
        sem_post(&s);
        sem_wait(&s); /* nunca bloqueia: já há permissão */
    }
    const double r = (double)(academy_now_ns() - t0) / n_rodadas;
    sem_destroy(&s);
    return r;
}

static void grupo_primitivo(void)
{
    print_header();
    measure_default("atomic relaxed (store+load)", m_atomica_relaxed);
    measure_default("atomic seq_cst (store+load)", m_atomica_seqcst);
    measure_default("mutex lock+unlock", m_mutex_simples);
    measure_default("spinlock lock+unlock", m_spinlock);
    measure_default("semaphore post+wait", m_semaforo_livre);
}

/* ================ Grupo 2: repasse de verdade entre núcleos ================ */

static _Alignas(64) atomic_int bola;
static pthread_mutex_t mtx2 = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cond = PTHREAD_COND_INITIALIZER;
static _Alignas(64) int estado;
static sem_t sem_ida, sem_volta;

static void *par_atomica(void *_)
{
    const int n_rodadas = RODADAS_REPASSE;
    (void)_;
    fixar(cpu_b);
    for (int i = 0; i < n_rodadas; i++) {
        while (atomic_load_explicit(&bola, memory_order_acquire) != 1)
            academy_cpu_pause();
        atomic_store_explicit(&bola, 0, memory_order_release);
    }
    return NULL;
}

/* Mutex usado SEM dormir: tranca, confere, destranca, repete. */
static void *par_mutex_ativo(void *_)
{
    const int n_rodadas = RODADAS_REPASSE;
    (void)_;
    fixar(cpu_b);
    for (int i = 0; i < n_rodadas; i++) {
        for (;;) {
            pthread_mutex_lock(&mtx2);
            if (estado == 1) {
                estado = 0;
                pthread_mutex_unlock(&mtx2);
                break;
            }
            pthread_mutex_unlock(&mtx2);
            academy_cpu_pause();
        }
    }
    return NULL;
}

/* Mesmo mutex, agora com condvar: a thread realmente dorme. */
static void *par_condvar(void *_)
{
    const int n_rodadas = RODADAS_REPASSE;
    (void)_;
    fixar(cpu_b);
    for (int i = 0; i < n_rodadas; i++) {
        pthread_mutex_lock(&mtx2);
        while (estado != 1)
            pthread_cond_wait(&cond, &mtx2);
        estado = 0;
        pthread_cond_signal(&cond);
        pthread_mutex_unlock(&mtx2);
    }
    return NULL;
}

static void *par_semaforo(void *_)
{
    const int n_rodadas = RODADAS_REPASSE;
    (void)_;
    fixar(cpu_b);
    for (int i = 0; i < n_rodadas; i++) {
        sem_wait(&sem_ida);
        sem_post(&sem_volta);
    }
    return NULL;
}

/* Cada medição de repasse cria a thread parceira, mede e a encerra, para que a
 * repetição seja realmente independente. */
static const struct timespec assentar = {0, 2000000};

static double m_repasse_atomica(void)
{
    const int n_rodadas = RODADAS_REPASSE;
    pthread_t t;
    atomic_store(&bola, 0);
    if (pthread_create(&t, NULL, par_atomica, NULL) != 0)
        return 0.0;
    nanosleep(&assentar, NULL);
    const uint64_t t0 = academy_now_ns();
    for (int i = 0; i < n_rodadas; i++) {
        atomic_store_explicit(&bola, 1, memory_order_release);
        while (atomic_load_explicit(&bola, memory_order_acquire) != 0)
            academy_cpu_pause();
    }
    const double r = (double)(academy_now_ns() - t0) / n_rodadas / 2.0;
    pthread_join(t, NULL);
    return r;
}

static double m_repasse_mutex_ativo(void)
{
    const int n_rodadas = RODADAS_REPASSE;
    pthread_t t;
    estado = 0;
    if (pthread_create(&t, NULL, par_mutex_ativo, NULL) != 0)
        return 0.0;
    nanosleep(&assentar, NULL);
    const uint64_t t0 = academy_now_ns();
    for (int i = 0; i < n_rodadas; i++) {
        pthread_mutex_lock(&mtx2);
        estado = 1;
        pthread_mutex_unlock(&mtx2);
        for (;;) {
            pthread_mutex_lock(&mtx2);
            if (estado == 0) {
                pthread_mutex_unlock(&mtx2);
                break;
            }
            pthread_mutex_unlock(&mtx2);
            academy_cpu_pause();
        }
    }
    const double r = (double)(academy_now_ns() - t0) / n_rodadas / 2.0;
    pthread_join(t, NULL);
    return r;
}

static double m_repasse_condvar(void)
{
    const int n_rodadas = RODADAS_REPASSE;
    pthread_t t;
    estado = 0;
    if (pthread_create(&t, NULL, par_condvar, NULL) != 0)
        return 0.0;
    nanosleep(&assentar, NULL);
    const uint64_t t0 = academy_now_ns();
    for (int i = 0; i < n_rodadas; i++) {
        pthread_mutex_lock(&mtx2);
        estado = 1;
        pthread_cond_signal(&cond);
        while (estado != 0)
            pthread_cond_wait(&cond, &mtx2);
        pthread_mutex_unlock(&mtx2);
    }
    const double r = (double)(academy_now_ns() - t0) / n_rodadas / 2.0;
    pthread_join(t, NULL);
    return r;
}

static double m_repasse_semaforo(void)
{
    const int n_rodadas = RODADAS_REPASSE;
    pthread_t t;
    sem_init(&sem_ida, 0, 0);
    sem_init(&sem_volta, 0, 0);
    if (pthread_create(&t, NULL, par_semaforo, NULL) != 0)
        return 0.0;
    nanosleep(&assentar, NULL);
    const uint64_t t0 = academy_now_ns();
    for (int i = 0; i < n_rodadas; i++) {
        sem_post(&sem_ida);
        sem_wait(&sem_volta);
    }
    const double r = (double)(academy_now_ns() - t0) / n_rodadas / 2.0;
    pthread_join(t, NULL);
    sem_destroy(&sem_ida);
    sem_destroy(&sem_volta);
    return r;
}

int main(void)
{
    print_provenance("custo-espera");
    pthread_spin_init(&spin, 0);
    fixar(cpu_a);
    aquecer();

    printf("Cost of waiting for work\n");
    printf("(%d samples per measurement, after %d ms of warm-up; times in ns)\n",
           DEFAULT_SAMPLES, AQUECIMENTO_MS);
    printf("(CV = coefficient of variation;  ~ = moderate dispersion,  ! = unstable)\n\n");
    printf("GROUP 1 - UNCONTENDED: nobody else wants the same primitive\n");
    printf("          (process with another thread present, which is the real regime\n");
    printf("           of any concurrent program -- see the note in the source)\n\n");
    grupo_primitivo();

    printf("\nGROUP 2 - HANDOFF: two threads coordinating (cpu %d <-> cpu %d)\n\n",
           cpu_a, cpu_b);

    print_header();
    const struct statistics e_ativa = collect_or_fail(m_repasse_atomica, AMOSTRAS_REPASSE);
    print_row("atomic + busy wait (does not sleep)", e_ativa);
    const struct statistics e_mutex = collect_or_fail(m_repasse_mutex_ativo, AMOSTRAS_REPASSE);
    print_row("mutex + busy wait (does not sleep)", e_mutex);
    const struct statistics e_dorme = collect_or_fail(m_repasse_condvar, AMOSTRAS_REPASSE);
    print_row("mutex + condvar (SLEEPS)", e_dorme);
    print_row("POSIX semaphore (SLEEPS)", collect_or_fail(m_repasse_semaforo, AMOSTRAS_REPASSE));

    const double ns_ativa = e_ativa.median;
    const double ns_mutex_ativo = e_mutex.median;
    const double ns_dorme = e_dorme.median;

    printf("\nReading:\n");
    printf("  The primitive is not the problem: an uncontended mutex costs a few ns.\n");
    printf("  The SAME mutex costs %.0f ns without sleeping and %.0f ns with a condvar --\n",
           ns_mutex_ativo, ns_dorme);
    printf("  %.0fx of difference, and the only variable changed was sleeping or not.\n\n",
           ns_dorme / ns_mutex_ativo);
    printf("  Budget of a 64 B packet at 10 GbE: %.1f ns\n", BUDGET_10GBE_NS);
    printf("    busy waiting fits %.1f times in it\n", BUDGET_10GBE_NS / ns_ativa);
    printf("    sleeping spends %.1f whole budgets\n", ns_dorme / BUDGET_10GBE_NS);
    printf("\n  That is why the data plane polls: there is no time to sleep.\n");
    printf("  The price is occupying 100%% of the core even with no traffic at all.\n");
    return 0;
}
