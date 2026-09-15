// SPDX-License-Identifier: MIT
#include <gtest/gtest.h>
#include "feed-health.h"
TEST(FeedHealth, HeartbeatNaoSignificaDadosAtuais) {
    feed_watch w;
    feed_watch_init(&w, 7, 0);
    EXPECT_EQ(feed_watch_update(&w, 7, 1, 1, 1, 10, 30), FEED_HEALTHY);
    EXPECT_EQ(feed_watch_update(&w, 7, 2, 1, 9, 10, 30), FEED_HEALTHY);
    EXPECT_EQ(feed_watch_update(&w, 7, 3, 1, 31, 10, 30), FEED_STALE);
}
TEST(FeedHealth, DetectaNoLimiarSemConfundirGeracoes) {
    feed_watch w;
    feed_watch_init(&w, 7, 0);
    EXPECT_EQ(feed_watch_update(&w, 7, 1, 1, 1, 10, 30), FEED_HEALTHY);
    EXPECT_EQ(feed_watch_update(&w, 7, 1, 1, 10, 10, 30), FEED_HEALTHY);
    EXPECT_EQ(feed_watch_update(&w, 7, 1, 1, 11, 10, 30), FEED_SILENT);
    EXPECT_EQ(feed_watch_update(&w, 8, 2, 2, 12, 10, 30), FEED_WRONG_GENERATION);
    EXPECT_EQ(w.generation, 7u);
    feed_watch_init(&w, 8, 12);
    EXPECT_EQ(feed_watch_update(&w, 8, 2, 2, 12, 10, 30), FEED_HEALTHY);
}
