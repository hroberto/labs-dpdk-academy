/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Contrato de memória compartilhada entre o feed handler (processo PRIMÁRIO) e
 * o assinante (processo SECUNDÁRIO).
 *
 * Este cabeçalho é o ponto exato onde o modelo multiprocesso do DPDK deixa de
 * ser abstrato: os dois programas são binários diferentes, com main() próprio,
 * e compartilham ESTA estrutura — que vive numa memzone da EAL, mapeada no
 * MESMO endereço virtual nos dois processos.
 *
 * Três decisões de layout, todas com motivo:
 *
 * 1. SEM PONTEIROS. Um ponteiro guardado aqui só valeria se os dois processos
 *    mapeassem a região no mesmo endereço. A EAL faz exatamente isso, mas
 *    depender disso é frágil (a própria documentação chama a partida do
 *    secundário de "generally unreliable" por causa do ASLR). Índices são
 *    válidos em qualquer mapeamento.
 *
 * 2. CAMPOS DE ESCRITA EXCLUSIVA EM LINHAS DE CACHE SEPARADAS. `publicados` é
 *    escrito só pelo produtor; `consumidos`, só pelo consumidor. Na mesma linha
 *    de 64 B, cada publicação invalidaria a linha do consumidor e vice-versa —
 *    é o falso compartilhamento medido em §4.2.1 dos fundamentos, que lá custou
 *    de 8 ns para 53 ns. Aqui o erro custaria o dobro, porque a linha atravessa
 *    a fronteira de processo.
 *
 * 3. CAPACIDADE POTÊNCIA DE DOIS. Índice & máscara em vez de índice % n: uma
 *    instrução em vez de uma divisão inteira, no caminho de cada tick.
 */
#ifndef DPDK_ACADEMY_FEED_H
#define DPDK_ACADEMY_FEED_H

#include <stdatomic.h>
#include <stdint.h>

#include "order_book.h"

/* Nome da memzone. É por ESTE nome que o secundário encontra a região: no
 * modelo multiprocesso do DPDK, o nome é a única coisa que os dois lados
 * combinam previamente. */
#define FEED_MEMZONE "academia_feed_marketdata"

#define FEED_CAPACIDADE 8192u
#define FEED_MASCARA (FEED_CAPACIDADE - 1u)
#define FEED_LINHA 64

/* Quantos papéis o feed publica. Os dois lados precisam concordar: o produtor
 * gera ticks para estes instrumentos, e o consumidor mantém UM LIVRO POR
 * INSTRUMENTO. Misturar papéis num livro só produz spread negativo — ver o
 * comentário de abertura de livro.h. */
#define FEED_INSTRUMENTOS 4u

/* Sentinela de encerramento: o produtor publica este total quando termina. */
#define FEED_FIM UINT64_MAX

struct shared_feed {
    /* --- escrito SÓ pelo produtor (primário) --- */
    _Alignas(FEED_LINHA) _Atomic uint64_t published;

    /* --- escrito SÓ pelo consumidor (secundário) --- */
    _Alignas(FEED_LINHA) _Atomic uint64_t consumidos;

    /* --- escrito SÓ pelo consumidor: apertos de mão de entrada e de saída --- */
    _Alignas(FEED_LINHA) _Atomic uint32_t assinante_pronto;

    /* O consumidor sinaliza aqui ANTES de chamar rte_eal_cleanup(). O primário
     * espera por este sinal para só então encerrar.
     *
     * A ordem importa e o motivo não é óbvio: o secundário conversa com o
     * primário por um socket de controle em $XDG_RUNTIME_DIR/dpdk/<prefixo>/.
     * Se o primário sair primeiro, esse socket some, e o cleanup do secundário
     * reclama com "failed to send to (...mp_socket)". Não corrompe nada, mas é
     * ruído de encerramento mal ordenado — e ensinar a ordem errada seria pior
     * do que o ruído. Em produção, o processo dono da memória é o último a sair. */
    _Alignas(FEED_LINHA) _Atomic uint32_t assinante_terminou;

    /* --- só leitura depois da criação, pelo produtor --- */
    _Alignas(FEED_LINHA) uint64_t total_previsto;
    uint64_t tsc_hz;       /* calibração do relógio, vinda de rte_get_tsc_hz() */

    /* Perdas SIMULADAS que o produtor vai injetar. Calculado ANTES de publicar
     * qualquer tick, e não ao final: o consumidor lê este campo quando termina,
     * e uma escrita tardia do produtor pode ainda não estar visível para ele —
     * foi o que aconteceu na primeira execução, com o consumidor relatando
     * "o primario injetou 0" enquanto o produtor havia injetado 3. Valor
     * conhecido de antemão não tem corrida. */
    uint64_t lacunas_injetadas;

    /* --- o anel --- */
    _Alignas(FEED_LINHA) struct tick ring[FEED_CAPACIDADE];
};

#endif /* DPDK_ACADEMY_FEED_H */
