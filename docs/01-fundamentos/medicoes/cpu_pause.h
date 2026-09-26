/* SPDX-License-Identifier: MIT
 *
 * Dica de espera ocupada, portátil entre x86-64 e arm64.
 *
 * POR QUE ISTO EXISTE
 *
 * O README do projeto declara como requisito "Linux x86_64 ou arm64", e quatro
 * programas de medição chamavam `__builtin_ia32_pause()` em doze pontos, sem
 * nenhuma guarda de arquitetura. Em arm64 eles não compilam: o builtin é
 * exclusivo de alvo x86 no GCC e no Clang. A promessa da porta de entrada não
 * correspondia ao código.
 *
 * Estes quatro programas NÃO incluem DPDK de propósito -- medem primitivas do
 * processador e do sistema operacional sem a EAL no caminho --, então usar
 * `rte_pause()` resolveria a portabilidade ao custo de introduzir a dependência
 * que o experimento evita. Daí este cabeçalho, que é a mesma ideia em três
 * linhas.
 *
 * O QUE CADA INSTRUÇÃO FAZ
 *
 *   x86-64  `pause`: avisa o processador de que este laço é espera, reduzindo o
 *           consumo e a penalidade de saída do laço por especulação.
 *   arm64   `isb`: barreira de sincronização de instruções. Não é equivalente
 *           exato de `pause` -- arm64 tem `wfe`, que exige um evento para
 *           acordar e não serve a uma espera por variável comum.
 *
 * ESTA NÃO É A ESCOLHA DO DPDK, e dizer que era estava errado. Em arm64
 * `rte_pause()` emite `yield` -- `lib/eal/arm/include/rte_pause_64.h:24`,
 * idêntico no 25.11 e no 26.07. O `isb` aparece em outros projetos como dica
 * de espera justamente porque `yield` é quase inócuo em vários núcleos Arm,
 * mas "quase inócuo" é afirmação sobre desempenho, e o projeto não tem arm64
 * para medi-la. A instrução fica; a atribuição sai.
 *
 * Em arquitetura desconhecida vira nada: o laço continua correto, só não
 * recebe a dica. Correção nunca depende desta chamada.
 */
#ifndef ACADEMY_CPU_PAUSE_H
#define ACADEMY_CPU_PAUSE_H

#if defined(__x86_64__) || defined(__i386__)
#define academy_cpu_pause() __builtin_ia32_pause()
#elif defined(__aarch64__)
#define academy_cpu_pause() __asm__ __volatile__("isb" ::: "memory")
#else
#define academy_cpu_pause() ((void)0)
#endif

#endif /* ACADEMY_CPU_PAUSE_H */
