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
 * METODOLOGIA: cada medição é repetida AMOSTRAS_PADRAO vezes e o resultado é
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

#include "statistics.h"

#define RODADAS_PRIMITIVO_FIXO 2000000
#define RODADAS_PRIMITIVO rounds(RODADAS_PRIMITIVO_FIXO)
#define RODADAS_REPASSE_FIXO_N 200000
#define RODADAS_REPASSE rounds(RODADAS_REPASSE_FIXO_N)
#define BUDGET_10GBE_NS 67.2

static int cpu_a = 0, cpu_b = 2;

static uint64_t now_ns(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000000000ull + t.tv_nsec;
}

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

#define AQUECIMENTO_MS 60
/* O repasse é caro (o condvar leva ~1,3 us por par), então usa menos amostras
 * para o programa terminar em tempo razoável. Ainda é ordem de grandeza acima
 * das 3 repetições que este arquivo usava antes. */
#define AMOSTRAS_REPASSE_FIXO 15
#define AMOSTRAS_REPASSE samples(AMOSTRAS_REPASSE_FIXO)

/* Gira em espaço de usuário para a CPU subir de frequência e as caches
 * aquecerem, antes de qualquer medição valer. */
static void aquecer(void)
{
    const uint64_t ate = now_ns() + (uint64_t)AQUECIMENTO_MS * 1000000ull;
    long acumulador = 0;
    while (now_ns() < ate)
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
    const uint64_t t0 = now_ns();
    for (int i = 0; i < RODADAS_PRIMITIVO; i++) {
        atomic_store_explicit(&valor, i, memory_order_relaxed);
        sumidouro = atomic_load_explicit(&valor, memory_order_relaxed);
    }
    return (double)(now_ns() - t0) / RODADAS_PRIMITIVO;
}

static double m_mutex_simples(void)
{
    const uint64_t t0 = now_ns();
    for (int i = 0; i < RODADAS_PRIMITIVO; i++) {
        pthread_mutex_lock(&mtx);
        sumidouro = i;
        pthread_mutex_unlock(&mtx);
    }
    return (double)(now_ns() - t0) / RODADAS_PRIMITIVO;
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
    print_row(rotulo, collect(com_outra_thread, DEFAULT_SAMPLES));
}

static double m_atomica_seqcst(void)
{
    const uint64_t t0 = now_ns();
    for (int i = 0; i < RODADAS_PRIMITIVO; i++) {
        atomic_store(&valor, i); /* seq_cst: barreira completa */
        sumidouro = atomic_load(&valor);
    }
    return (double)(now_ns() - t0) / RODADAS_PRIMITIVO;
}

static double m_spinlock(void)
{
    const uint64_t t0 = now_ns();
    for (int i = 0; i < RODADAS_PRIMITIVO; i++) {
        pthread_spin_lock(&spin);
        sumidouro = i;
        pthread_spin_unlock(&spin);
    }
    return (double)(now_ns() - t0) / RODADAS_PRIMITIVO;
}

static double m_semaforo_livre(void)
{
    sem_t s;
    sem_init(&s, 0, 0);
    const uint64_t t0 = now_ns();
    for (int i = 0; i < RODADAS_PRIMITIVO; i++) {
        sem_post(&s);
        sem_wait(&s); /* nunca bloqueia: já há permissão */
    }
    const double r = (double)(now_ns() - t0) / RODADAS_PRIMITIVO;
    sem_destroy(&s);
    return r;
}

static void grupo_primitivo(void)
{
    print_header();
    measure_default("atomica relaxed (store+load)", m_atomica_relaxed);
    measure_default("atomica seq_cst (store+load)", m_atomica_seqcst);
    measure_default("mutex lock+unlock", m_mutex_simples);
    measure_default("spinlock lock+unlock", m_spinlock);
    measure_default("semaforo post+wait", m_semaforo_livre);
}

/* ================ Grupo 2: repasse de verdade entre núcleos ================ */

static _Alignas(64) atomic_int bola;
static pthread_mutex_t mtx2 = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cond = PTHREAD_COND_INITIALIZER;
static _Alignas(64) int estado;
static sem_t sem_ida, sem_volta;

static void *par_atomica(void *_)
{
    (void)_;
    fixar(cpu_b);
    for (int i = 0; i < RODADAS_REPASSE; i++) {
        while (atomic_load_explicit(&bola, memory_order_acquire) != 1)
            __builtin_ia32_pause();
        atomic_store_explicit(&bola, 0, memory_order_release);
    }
    return NULL;
}

/* Mutex usado SEM dormir: tranca, confere, destranca, repete. */
static void *par_mutex_ativo(void *_)
{
    (void)_;
    fixar(cpu_b);
    for (int i = 0; i < RODADAS_REPASSE; i++) {
        for (;;) {
            pthread_mutex_lock(&mtx2);
            if (estado == 1) {
                estado = 0;
                pthread_mutex_unlock(&mtx2);
                break;
            }
            pthread_mutex_unlock(&mtx2);
            __builtin_ia32_pause();
        }
    }
    return NULL;
}

/* Mesmo mutex, agora com condvar: a thread realmente dorme. */
static void *par_condvar(void *_)
{
    (void)_;
    fixar(cpu_b);
    for (int i = 0; i < RODADAS_REPASSE; i++) {
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
    (void)_;
    fixar(cpu_b);
    for (int i = 0; i < RODADAS_REPASSE; i++) {
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
    pthread_t t;
    atomic_store(&bola, 0);
    if (pthread_create(&t, NULL, par_atomica, NULL) != 0)
        return 0.0;
    nanosleep(&assentar, NULL);
    const uint64_t t0 = now_ns();
    for (int i = 0; i < RODADAS_REPASSE; i++) {
        atomic_store_explicit(&bola, 1, memory_order_release);
        while (atomic_load_explicit(&bola, memory_order_acquire) != 0)
            __builtin_ia32_pause();
    }
    const double r = (double)(now_ns() - t0) / RODADAS_REPASSE / 2.0;
    pthread_join(t, NULL);
    return r;
}

static double m_repasse_mutex_ativo(void)
{
    pthread_t t;
    estado = 0;
    if (pthread_create(&t, NULL, par_mutex_ativo, NULL) != 0)
        return 0.0;
    nanosleep(&assentar, NULL);
    const uint64_t t0 = now_ns();
    for (int i = 0; i < RODADAS_REPASSE; i++) {
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
            __builtin_ia32_pause();
        }
    }
    const double r = (double)(now_ns() - t0) / RODADAS_REPASSE / 2.0;
    pthread_join(t, NULL);
    return r;
}

static double m_repasse_condvar(void)
{
    pthread_t t;
    estado = 0;
    if (pthread_create(&t, NULL, par_condvar, NULL) != 0)
        return 0.0;
    nanosleep(&assentar, NULL);
    const uint64_t t0 = now_ns();
    for (int i = 0; i < RODADAS_REPASSE; i++) {
        pthread_mutex_lock(&mtx2);
        estado = 1;
        pthread_cond_signal(&cond);
        while (estado != 0)
            pthread_cond_wait(&cond, &mtx2);
        pthread_mutex_unlock(&mtx2);
    }
    const double r = (double)(now_ns() - t0) / RODADAS_REPASSE / 2.0;
    pthread_join(t, NULL);
    return r;
}

static double m_repasse_semaforo(void)
{
    pthread_t t;
    sem_init(&sem_ida, 0, 0);
    sem_init(&sem_volta, 0, 0);
    if (pthread_create(&t, NULL, par_semaforo, NULL) != 0)
        return 0.0;
    nanosleep(&assentar, NULL);
    const uint64_t t0 = now_ns();
    for (int i = 0; i < RODADAS_REPASSE; i++) {
        sem_post(&sem_ida);
        sem_wait(&sem_volta);
    }
    const double r = (double)(now_ns() - t0) / RODADAS_REPASSE / 2.0;
    pthread_join(t, NULL);
    sem_destroy(&sem_ida);
    sem_destroy(&sem_volta);
    return r;
}

int main(void)
{
    pthread_spin_init(&spin, 0);
    fixar(cpu_a);
    aquecer();

    printf("Custo de esperar por trabalho\n");
    printf("(%d amostras por medicao, apos %d ms de aquecimento; tempos em ns)\n",
           DEFAULT_SAMPLES, AQUECIMENTO_MS);
    printf("(CV = coeficiente de variacao;  ~ = dispersao moderada,  ! = instavel)\n\n");
    printf("GRUPO 1 - SEM DISPUTA: ninguem mais quer o mesmo primitivo\n");
    printf("          (processo com outra thread presente, que e o regime real\n");
    printf("           de qualquer programa concorrente -- ver nota no fonte)\n\n");
    grupo_primitivo();

    printf("\nGRUPO 2 - NO REPASSE: duas threads coordenando (cpu %d <-> cpu %d)\n\n",
           cpu_a, cpu_b);

    print_header();
    const struct statistics e_ativa = collect(m_repasse_atomica, AMOSTRAS_REPASSE);
    print_row("atomica + espera ativa (nao dorme)", e_ativa);
    const struct statistics e_mutex = collect(m_repasse_mutex_ativo, AMOSTRAS_REPASSE);
    print_row("mutex + espera ativa (nao dorme)", e_mutex);
    const struct statistics e_dorme = collect(m_repasse_condvar, AMOSTRAS_REPASSE);
    print_row("mutex + condvar (DORME)", e_dorme);
    print_row("semaforo POSIX (DORME)", collect(m_repasse_semaforo, AMOSTRAS_REPASSE));

    const double ns_ativa = e_ativa.median;
    const double ns_mutex_ativo = e_mutex.median;
    const double ns_dorme = e_dorme.median;

    printf("\nLeitura:\n");
    printf("  O primitivo nao e o problema: um mutex sem disputa custa poucos ns.\n");
    printf("  O MESMO mutex custa %.0f ns sem dormir e %.0f ns com condvar --\n",
           ns_mutex_ativo, ns_dorme);
    printf("  %.0fx de diferenca, e a unica variavel mudada foi dormir ou nao.\n\n",
           ns_dorme / ns_mutex_ativo);
    printf("  Orcamento de um pacote de 64 B em 10 GbE: %.1f ns\n", BUDGET_10GBE_NS);
    printf("    espera ativa cabe %.1f vezes nele\n", BUDGET_10GBE_NS / ns_ativa);
    printf("    dormir gasta %.1f orcamentos inteiros\n", ns_dorme / BUDGET_10GBE_NS);
    printf("\n  Por isso o plano de dados faz polling: nao ha tempo para dormir.\n");
    printf("  O preco e ocupar 100%% do nucleo mesmo sem trafego algum.\n");
    return 0;
}
