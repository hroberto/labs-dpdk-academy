/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 *
 * Lógica pura do tópico 02: representação e processamento de um "pacote"
 * sintético. Não depende do DPDK, por isso é testável em L1.
 */
#ifndef DPDK_ACADEMY_PACKET_H
#define DPDK_ACADEMY_PACKET_H

#include <stdint.h>

#define PACKET_MAX_SIZE 1500u

struct packet {
    uint64_t id;
    uint32_t size;   /* bytes; limitado a PACOTE_TAMANHO_MAX */
    uint32_t checksum;
};

struct summary {
    uint64_t packets;
    uint64_t bytes;
};

/* Checksum sintético: mistura id e tamanho em 32 bits. */
uint32_t packet_checksum(uint64_t id, uint32_t size);

/* Preenche um pacote recém-obtido do pool. */
void packet_fill(struct packet *p, uint64_t id, uint32_t size);

/* Etapa de processamento: altera checksum e tamanho de forma determinística. */
void packet_process(struct packet *p);

/* Processa um lote (burst) de ponteiros e acumula no resumo. */
void packet_process_burst(struct packet *const *burst, unsigned n, struct summary *r);

#endif
