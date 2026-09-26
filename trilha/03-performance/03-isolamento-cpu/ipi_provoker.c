/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Provoca invalidacao de TLB a distancia, de dentro do proprio processo.
 *
 * POR QUE ISTO EXISTE
 *
 * Todos os mecanismos de isolamento do Linux controlam QUEM MAIS usa a CPU:
 * `isolcpus` tira o escalonador, `nohz_full` tira o tick, afinidade de IRQ tira
 * o dispositivo, `rcu_nocbs` tira os callbacks. Nenhum deles alcanca este caso.
 *
 * Quando uma thread altera o mapeamento de memoria do processo -- `munmap`,
 * `mprotect`, `madvise(MADV_DONTNEED)` -- o kernel precisa invalidar o TLB de
 * TODA CPU que esteja executando aquele mesmo espaco de enderecamento. Ele faz
 * isso por IPI, e a CPU isolada recebe como qualquer outra.
 *
 * A thread nao saiu da CPU, o escalonador nao a tocou, nenhum dispositivo
 * interrompeu -- e ainda assim houve parada. A causa esta dentro do processo,
 * e por isso nenhum parametro de boot a remove. O que remove e disciplina de
 * memoria: nao alterar mapeamento no caminho quente.
 *
 * COMO SE OBSERVA
 *
 * O contador `TLB` de /proc/interrupts, na CPU da sonda. O `stall_probe` ja o
 * imprime; rodar os dois juntos mostra a linha subir.
 *
 * USO
 *
 *   ipi_provoker <cpu> <segundos> [mib_por_ciclo]
 *
 * A CPU aqui e a do PROVOCADOR, que deve ser DIFERENTE da CPU da sonda -- o
 * objetivo e demonstrar o efeito a distancia.
 */
#define _GNU_SOURCE
#include <inttypes.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>

static uint64_t agora_ns(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        fprintf(stderr, "clock_gettime falhou\n");
        exit(2);
    }
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

int main(int argc, char **argv)
{
    if (argc < 3 || argc > 4) {
        fprintf(stderr, "usage: %s <cpu> <seconds> [mib_per_cycle]\n", argv[0]);
        return 2;
    }
    const int cpu = atoi(argv[1]);
    const double segundos = atof(argv[2]);
    const size_t mib = (argc == 4) ? (size_t)strtoul(argv[3], NULL, 10) : 8u;
    if (cpu < 0 || segundos <= 0.0 || mib == 0) {
        fprintf(stderr, "invalid parameters\n");
        return 2;
    }

    cpu_set_t set;
    CPU_ZERO(&set);
    CPU_SET(cpu, &set);
    if (sched_setaffinity(0, sizeof set, &set) != 0) {
        fprintf(stderr, "sched_setaffinity to CPU %d failed\n", cpu);
        return 1;
    }

    const size_t bytes = mib * 1024u * 1024u;
    const uint64_t fim = agora_ns() + (uint64_t)(segundos * 1e9);
    uint64_t ciclos = 0;

    while (agora_ns() < fim) {
        void *p = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (p == MAP_FAILED) {
            fprintf(stderr, "mmap failed\n");
            return 1;
        }
        /* TOCAR A MEMORIA E OBRIGATORIO. Sem escrever, as paginas nao chegam a
         * existir -- `mmap` so reserva o intervalo -- e o `munmap` de um
         * mapeamento sem pagina residente nao gera invalidacao para ninguem.
         * O IPI so acontece se houver o que invalidar. */
        memset(p, 1, bytes);
        if (munmap(p, bytes) != 0) {
            fprintf(stderr, "munmap failed\n");
            return 1;
        }
        ciclos++;
    }

    printf("ipi provoker: cpu %d, %.1f s, %zu MiB per cycle\n", cpu, segundos, mib);
    printf("cycles: %" PRIu64 "\n", ciclos);
    printf("note: no boot parameter removes this; see README section 2.3\n");
    return 0;
}
