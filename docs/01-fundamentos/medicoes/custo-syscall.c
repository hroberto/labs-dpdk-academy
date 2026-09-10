/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Fundamentos — quanto custa atravessar a fronteira user-space/kernel-space.
 *
 * Compara três operações:
 *   1. chamada de função comum      (referência: fica tudo em user-space)
 *   2. syscall real (SYS_getpid)    (atravessa a fronteira)
 *   3. clock_gettime()              (syscall servida pelo vDSO, sem trap)
 *
 * O item 3 existe para mostrar que "syscall" não é um custo único: o vDSO
 * mapeia algumas funções do kernel no espaço do processo, evitando a troca de
 * contexto. É a mesma ideia — remover a fronteira do caminho quente — que o
 * DPDK leva ao extremo para o tráfego de rede.
 *
 * METODOLOGIA: igual à dos demais programas desta pasta — AMOSTRAS_PADRAO
 * amostras por medição, publicadas como mediana, intervalo interquartil,
 * amplitude e coeficiente de variação. Ver statistics.h.
 */
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

#include "statistics.h"

#define ITERATIONS 2000000
#define AQUECIMENTO 100000

/* Orçamento por pacote em 10 GbE com quadros mínimos (64 B + 20 B de overhead
 * de preâmbulo e intervalo entre quadros): 10e9 / (84 * 8) = 14,88 Mpps. */
#define BUDGET_10GBE_NS 67.2

static uint64_t now_ns(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000000000ull + t.tv_nsec;
}

/* volatile impede que o compilador elimine os laços de medição. */
static volatile long sumidouro;

/* Referência: uma chamada de função que REALMENTE acontece.
 *
 * `noinline` sozinho não bastava, e o erro era silencioso. Sem argumento, sem
 * efeito colateral e com retorno constante, o GCC infere que esta função é
 * `const`: ele dobra a chamada no literal e a iça para fora do laço.
 * `noinline` impede *inlining*, não propagação interprocedural de constante.
 *
 * O laço medido virava, literalmente, isto — conferido com `objdump -d` sobre
 * o binário do próprio build do projeto:
 *
 *     movq $0x2a,0x244d(%rip)   # sumidouro
 *     movq $0x2a,0x2442(%rip)   # sumidouro
 *     sub  $0x2,%eax
 *     jne  <inicio>
 *
 * Nenhuma instrução `call`. A "chamada de função" media duas escritas em
 * `volatile`, e a razão publicada comparava syscall contra dois stores.
 *
 * O que conserta é tornar a função OPACA: o `asm volatile` com clobber de
 * memória impede que o compilador saiba o que ela faz, e o argumento impede
 * que ele preveja o resultado. Verifique com:
 *
 *     objdump -d build/docs/01-fundamentos/medicoes/custo-syscall | \
 *         awk '/<m_funcao>:/,/^$/' | grep call
 */
__attribute__((noinline)) static long plain_call(long x)
{
    __asm__ __volatile__("" : "+r"(x) : : "memory");
    return x;
}

static double m_funcao(void)
{
    const uint64_t t0 = now_ns();
    for (int i = 0; i < ITERATIONS; i++)
        sumidouro = plain_call(i);
    return (double)(now_ns() - t0) / ITERATIONS;
}

static double m_syscall(void)
{
    const uint64_t t0 = now_ns();
    for (int i = 0; i < ITERATIONS; i++)
        sumidouro = syscall(SYS_getpid);
    return (double)(now_ns() - t0) / ITERATIONS;
}

static double m_vdso(void)
{
    const uint64_t t0 = now_ns();
    for (int i = 0; i < ITERATIONS; i++)
        sumidouro = (long)now_ns();
    return (double)(now_ns() - t0) / ITERATIONS;
}

int main(void)
{
    for (int i = 0; i < AQUECIMENTO; i++) {
        sumidouro = plain_call(i);
        sumidouro = syscall(SYS_getpid);
    }

    printf("Custo por operacao (%d iteracoes, %d amostras; tempos em ns)\n\n", ITERATIONS,
           DEFAULT_SAMPLES);
    print_header();
    const struct statistics e_funcao = collect(m_funcao, DEFAULT_SAMPLES);
    print_row("chamada de funcao (user-space)", e_funcao);
    const struct statistics e_vdso = collect(m_vdso, DEFAULT_SAMPLES);
    print_row("clock_gettime (vDSO, sem trap)", e_vdso);
    const struct statistics e_syscall = collect(m_syscall, DEFAULT_SAMPLES);
    print_row("syscall real (SYS_getpid)", e_syscall);

    const double ns_funcao = e_funcao.median;
    const double ns_syscall = e_syscall.median;
    printf("\n  syscall custa %.0fx uma chamada de funcao\n", ns_syscall / ns_funcao);

    printf("\nOrcamento de 10 GbE com quadros de 64 B: %.1f ns por pacote\n",
           BUDGET_10GBE_NS);
    printf("  syscalls que cabem nesse orcamento: %.2f\n", BUDGET_10GBE_NS / ns_syscall);
    printf("\n  O caminho tradicional do kernel gasta pelo menos uma syscall por\n");
    printf("  lote de pacotes, mais interrupcao, alocacao de sk_buff e copia.\n");
    return 0;
}
