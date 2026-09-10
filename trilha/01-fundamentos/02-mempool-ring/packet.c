/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Henrique M Roberto
 */
#include "packet.h"

uint32_t packet_checksum(uint64_t id, uint32_t size)
{
    return (uint32_t)((id ^ size) & 0xFFFFFFFFu);
}

void packet_fill(struct packet *p, uint64_t id, uint32_t size)
{
    p->id = id;
    p->size = size > PACKET_MAX_SIZE ? PACKET_MAX_SIZE : size;
    p->checksum = packet_checksum(id, p->size);
}

void packet_process(struct packet *p)
{
    p->checksum ^= (uint32_t)(p->id * 0x9E3779B97F4A7C15ULL);
    p->size = p->size + 1u > PACKET_MAX_SIZE ? PACKET_MAX_SIZE : p->size + 1u;
}

void packet_process_burst(struct packet *const *burst, unsigned n, struct summary *r)
{
    for (unsigned i = 0; i < n; i++) {
        packet_process(burst[i]);
        r->packets++;
        r->bytes += burst[i]->size;
    }
}
