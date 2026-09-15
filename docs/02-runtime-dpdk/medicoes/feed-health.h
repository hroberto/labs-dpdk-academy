/* SPDX-License-Identifier: MIT */
#ifndef ACADEMY_FEED_HEALTH_H
#define ACADEMY_FEED_HEALTH_H
#include <stdint.h>

enum feed_health { FEED_HEALTHY, FEED_SILENT, FEED_STALE, FEED_WRONG_GENERATION };
struct feed_watch {
    uint64_t generation, heartbeat, published, last_heartbeat, last_data;
};
static inline void feed_watch_init(struct feed_watch *w, uint64_t gen, uint64_t now)
{
    struct feed_watch initial = {gen, 0, 0, now, now};
    *w = initial;
}
/* Todos os instantes são do relógio local do observador. */
static inline enum feed_health feed_watch_update(struct feed_watch *w, uint64_t gen,
    uint64_t heartbeat, uint64_t published, uint64_t now, uint64_t silence, uint64_t freshness)
{
    if (gen != w->generation || gen == 0)
        return FEED_WRONG_GENERATION;
    if (heartbeat != w->heartbeat) {
        w->heartbeat = heartbeat;
        w->last_heartbeat = now;
    }
    if (published != w->published) {
        w->published = published;
        w->last_data = now;
    }
    if (now - w->last_heartbeat >= silence)
        return FEED_SILENT;
    if (now - w->last_data >= freshness)
        return FEED_STALE;
    return FEED_HEALTHY;
}
#endif
