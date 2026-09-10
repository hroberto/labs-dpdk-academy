// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Henrique M Roberto
//
// Fundamentos — validação: a linguagem muda a conta?
//
// Espelho de custo-espera.c, trocando os primitivos de C e POSIX pelos
// equivalentes da biblioteca padrão de C++:
//
//     _Atomic / stdatomic.h  ->  std::atomic
//     pthread_mutex_t        ->  std::mutex
//     pthread_cond_t         ->  std::condition_variable
//     sem_t                  ->  std::counting_semaphore  (C++20)
//     pthread_t              ->  std::thread
//
// METODOLOGIA: idêntica à da versão em C, e pela mesma razão — a comparação só
// vale se a única variável for o primitivo. Aquecimento inicial, depois
// AMOSTRAS_PADRAO amostras por medição, publicadas como mediana, intervalo
// interquartil, amplitude e coeficiente de variação (ver statistics.h).
//
// A estrutura usa funções nomeadas em vez de lambdas para que `collect()`, que
// recebe ponteiro de função, seja compartilhado com o lado C sem adaptador.
//
// Rode os dois e compare com ./scripts/validar-cpp-vs-c.sh

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <mutex>
#include <semaphore>
#include <thread>

#include <pthread.h>
#include <sched.h>

#include "statistics.h"

namespace {

// Tetos vindos do ambiente, iguais aos do lado C -- a simetria e o ponto: um
// espelho que mede quantidade diferente de trabalho nao e espelho.
const int rodadas_primitivo = rounds(2'000'000);
const int rodadas_repasse = rounds(200'000);
constexpr int amostras_repasse_fixo = 15;
#define amostras_repasse samples(amostras_repasse_fixo)
constexpr int aquecimento_ms = 60;
constexpr double budget_10gbe_ns = 67.2;

constexpr int cpu_a = 0;
constexpr int cpu_b = 2;

// Afinidade não é padronizada em C++; usa-se a mesma chamada POSIX do lado C,
// justamente para que a única variável entre os dois programas sejam os
// primitivos de sincronização.
void fixar(int cpu)
{
    cpu_set_t c;
    CPU_ZERO(&c);
    CPU_SET(cpu, &c);
    pthread_setaffinity_np(pthread_self(), sizeof(c), &c);
}

[[nodiscard]] double now_ns()
{
    return static_cast<double>(std::chrono::duration_cast<std::chrono::nanoseconds>(
                                   std::chrono::steady_clock::now().time_since_epoch())
                                   .count());
}

alignas(64) volatile long sumidouro = 0;

void aquecer()
{
    const double ate = now_ns() + aquecimento_ms * 1'000'000.0;
    long a = 0;
    while (now_ns() < ate)
        for (int i = 0; i < 10000; i++)
            a += i;
    sumidouro = a;
}

// ===================== Grupo 1: sem disputa =====================

alignas(64) std::atomic<int> valor{0};
// Alinhado pelo mesmo motivo da versão em C: o mutex é escrito a cada
// lock/unlock, e dividir linha de cache com algo tocado por outra thread faz a
// medição medir invalidação de linha em vez do primitivo.
alignas(64) std::mutex mtx;
alignas(64) std::atomic<bool> parar_ruido{false};
alignas(64) volatile long sumidouro_ruido = 0;

double m_atomica_relaxed()
{
    const double t0 = now_ns();
    for (int i = 0; i < rodadas_primitivo; i++) {
        valor.store(i, std::memory_order_relaxed);
        sumidouro = valor.load(std::memory_order_relaxed);
    }
    return (now_ns() - t0) / rodadas_primitivo;
}

double m_mutex_simples()
{
    const double t0 = now_ns();
    for (int i = 0; i < rodadas_primitivo; i++) {
        mtx.lock();
        sumidouro = i;
        mtx.unlock();
    }
    return (now_ns() - t0) / rodadas_primitivo;
}

void thread_ruido()
{
    fixar(cpu_b + 2);
    while (!parar_ruido.load(std::memory_order_relaxed))
        sumidouro_ruido = sumidouro_ruido + 1;  // volatile++ é depreciado em C++20
}

// Regime padrão: qualquer medição roda com outra thread presente no processo.
//
// A versão em C explica por extenso; em resumo: a glibc tem caminho rápido para
// processo de thread única, perdido PERMANENTEMENTE na primeira criação de
// thread. Medir nesse regime dá números que dependem da ordem das medições —
// e medição que depende da ordem em que se mede não é medição.
double (*medicao_sob_ruido)() = nullptr;

double com_outra_thread()
{
    parar_ruido.store(false);
    std::thread ruido(thread_ruido);
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    const double r = medicao_sob_ruido();
    parar_ruido.store(true);
    ruido.join();
    return r;
}

void measure_default(const char* rotulo, double (*m)())
{
    medicao_sob_ruido = m;
    print_row(rotulo, collect(com_outra_thread, DEFAULT_SAMPLES));
}

double m_atomica_seqcst()
{
    const double t0 = now_ns();
    for (int i = 0; i < rodadas_primitivo; i++) {
        valor.store(i);  // seq_cst
        sumidouro = valor.load();
    }
    return (now_ns() - t0) / rodadas_primitivo;
}

double m_semaforo_livre()
{
    std::counting_semaphore<1> sem{0};
    const double t0 = now_ns();
    for (int i = 0; i < rodadas_primitivo; i++) {
        sem.release();
        sem.acquire();
    }
    return (now_ns() - t0) / rodadas_primitivo;
}

// ===================== Grupo 2: no repasse =====================

alignas(64) std::atomic<int> bola{0};
alignas(64) std::mutex mtx2;
std::condition_variable cond;
alignas(64) int estado = 0;
std::counting_semaphore<1> sem_ida{0};
std::counting_semaphore<1> sem_volta{0};

void assentar()
{
    std::this_thread::sleep_for(std::chrono::milliseconds(2));
}

void par_atomica()
{
    fixar(cpu_b);
    for (int i = 0; i < rodadas_repasse; i++) {
        while (bola.load(std::memory_order_acquire) != 1)
            __builtin_ia32_pause();
        bola.store(0, std::memory_order_release);
    }
}

double m_repasse_atomica()
{
    bola.store(0);
    std::thread t(par_atomica);
    assentar();
    const double t0 = now_ns();
    for (int i = 0; i < rodadas_repasse; i++) {
        bola.store(1, std::memory_order_release);
        while (bola.load(std::memory_order_acquire) != 0)
            __builtin_ia32_pause();
    }
    const double r = (now_ns() - t0) / rodadas_repasse / 2.0;
    t.join();
    return r;
}

void par_mutex_ativo()
{
    fixar(cpu_b);
    for (int i = 0; i < rodadas_repasse; i++) {
        for (;;) {
            mtx2.lock();
            if (estado == 1) {
                estado = 0;
                mtx2.unlock();
                break;
            }
            mtx2.unlock();
            __builtin_ia32_pause();
        }
    }
}

double m_repasse_mutex_ativo()
{
    estado = 0;
    std::thread t(par_mutex_ativo);
    assentar();
    const double t0 = now_ns();
    for (int i = 0; i < rodadas_repasse; i++) {
        mtx2.lock();
        estado = 1;
        mtx2.unlock();
        for (;;) {
            mtx2.lock();
            if (estado == 0) {
                mtx2.unlock();
                break;
            }
            mtx2.unlock();
            __builtin_ia32_pause();
        }
    }
    const double r = (now_ns() - t0) / rodadas_repasse / 2.0;
    t.join();
    return r;
}

void par_condvar()
{
    fixar(cpu_b);
    for (int i = 0; i < rodadas_repasse; i++) {
        std::unique_lock lk(mtx2);
        cond.wait(lk, [] { return estado == 1; });
        estado = 0;
        cond.notify_one();
    }
}

double m_repasse_condvar()
{
    estado = 0;
    std::thread t(par_condvar);
    assentar();
    const double t0 = now_ns();
    for (int i = 0; i < rodadas_repasse; i++) {
        std::unique_lock lk(mtx2);
        estado = 1;
        cond.notify_one();
        cond.wait(lk, [] { return estado == 0; });
    }
    const double r = (now_ns() - t0) / rodadas_repasse / 2.0;
    t.join();
    return r;
}

void par_semaforo()
{
    fixar(cpu_b);
    for (int i = 0; i < rodadas_repasse; i++) {
        sem_ida.acquire();
        sem_volta.release();
    }
}

double m_repasse_semaforo()
{
    std::thread t(par_semaforo);
    assentar();
    const double t0 = now_ns();
    for (int i = 0; i < rodadas_repasse; i++) {
        sem_ida.release();
        sem_volta.acquire();
    }
    const double r = (now_ns() - t0) / rodadas_repasse / 2.0;
    t.join();
    return r;
}

}  // namespace

int main()
{
    fixar(cpu_a);
    aquecer();

    std::printf("Custo de esperar por trabalho -- versao C++23\n");
    std::printf("(%d amostras por medicao, apos %d ms de aquecimento; tempos em ns)\n",
                DEFAULT_SAMPLES, aquecimento_ms);
    std::printf("(CV = coeficiente de variacao;  ~ = dispersao moderada,  ! = instavel)\n\n");

    std::printf("GRUPO 1 - SEM DISPUTA: ninguem mais quer o mesmo primitivo\n");
    std::printf("          (processo com outra thread presente, como na versao em C)\n\n");
    print_header();
    measure_default("std::atomic relaxed (store+load)", m_atomica_relaxed);
    measure_default("std::atomic seq_cst (store+load)", m_atomica_seqcst);
    measure_default("std::mutex lock+unlock", m_mutex_simples);
    measure_default("std::semaphore rel+acq, sem bloq.", m_semaforo_livre);

    std::printf("\nGRUPO 2 - NO REPASSE: duas threads coordenando (cpu %d <-> cpu %d)\n\n", cpu_a,
                cpu_b);
    print_header();
    const statistics e_ativa = collect(m_repasse_atomica, amostras_repasse);
    print_row("std::atomic + espera ativa", e_ativa);
    const statistics e_mutex = collect(m_repasse_mutex_ativo, amostras_repasse);
    print_row("std::mutex + espera ativa", e_mutex);
    const statistics e_dorme = collect(m_repasse_condvar, amostras_repasse);
    print_row("std::condition_variable (DORME)", e_dorme);
    // std::counting_semaphore no libstdc++ NAO envolve sem_t: gira antes de
    // bloquear, entao neste ping-pong quase nunca chega a dormir.
    print_row("std::counting_semaphore (gira)", collect(m_repasse_semaforo, amostras_repasse));

    std::printf("\n  O MESMO std::mutex custa %.0f ns sem dormir e %.0f ns com condvar\n",
                e_mutex.median, e_dorme.median);
    std::printf("  -- %.0fx de diferenca, mesma conclusao da versao em C.\n",
                e_dorme.median / e_mutex.median);
    std::printf("\n  dormir gasta %.1f orcamentos de pacote de 64 B em 10 GbE\n",
                e_dorme.median / budget_10gbe_ns);
    return 0;
}
