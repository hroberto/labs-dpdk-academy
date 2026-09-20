/* SPDX-License-Identifier: MIT */
#ifndef ACADEMY_FEED_CLOCK_H
#define ACADEMY_FEED_CLOCK_H
#include <errno.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>
static inline uint64_t feed_now_ns(void)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0)
        abort();
    return (uint64_t)now.tv_sec * 1000000000ULL + (uint64_t)now.tv_nsec;
}
/* Zero indica configuração inválida; não inicia o runtime nesse caso. */
static inline uint64_t feed_env_number(const char *name, uint64_t fallback, uint64_t max)
{
    const char *s = getenv(name);
    if (!s) return fallback;
    char *end;
    errno = 0;
    unsigned long long value = strtoull(s, &end, 10);
    if (errno || *s < '0' || *s > '9' || *end || !value || value > max)
        return 0;
    return (uint64_t)value;
}
#endif
