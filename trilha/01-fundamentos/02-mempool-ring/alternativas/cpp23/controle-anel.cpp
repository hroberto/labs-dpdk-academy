// SPDX-License-Identifier: MIT
// Mesmo SPSC e payload: varia publicação por objeto/lote e uma/duas CPUs.
#include "packet.hpp"
#include <array>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <thread>
#include <sched.h>

static bool pin(int cpu) {
    if (cpu < 0 || cpu >= CPU_SETSIZE) return false;
    cpu_set_t set; CPU_ZERO(&set); CPU_SET(cpu, &set);
    return sched_setaffinity(0, sizeof(set), &set) == 0;
}
int main(int argc, char **argv) {
    if (argc != 6) {
        std::fprintf(stderr, "usage: controle-anel bulk(0/1) batch cpu-prod cpu-cons samples\n");
        return 2;
    }
    const int bulk = std::atoi(argv[1]), burst = std::atoi(argv[2]);
    const int producer = std::atoi(argv[3]), consumer = std::atoi(argv[4]), samples = std::atoi(argv[5]);
    if ((bulk != 0 && bulk != 1) || burst < 1 || burst > 128 || samples < 1 || samples > 1000 || !pin(consumer)) return 2;
    constexpr std::uint64_t total = 200000;
    using clock = std::chrono::steady_clock;
    std::printf("sample,bulk,burst,producer,consumer,objects,ns_per_object\n");
    for (int sample = -1; sample < samples; ++sample) { // uma passagem descartada
        academy::SpscRing ring(4096);
        std::array<academy::Packet,128> in{}, out{};
        std::atomic<bool> start{false}, stop{false}, failed{false};
        std::uint64_t produced = 0, consumed = 0;
        auto produce = [&] {
            auto count = std::min<std::uint64_t>(burst, total - produced);
            for (std::size_t j = 0; j < count; ++j) in[j] = academy::make(produced + j, 64);
            std::size_t accepted = 0;
            if (bulk) accepted = ring.enqueue_burst(std::span{in}.first(count));
            else while (accepted < count && ring.enqueue(in[accepted])) ++accepted;
            produced += accepted;
        };
        std::thread worker;
        if (producer != consumer) {
            worker = std::thread([&] {
                if (!pin(producer)) { failed.store(true); return; }
                while (!start.load(std::memory_order_acquire) && !stop.load()) {}
                while (produced < total && !stop.load(std::memory_order_relaxed)) produce();
            });
        }
        const auto begin = clock::now();
        start.store(true, std::memory_order_release);
        while (consumed < total && !failed.load()) {
            if (producer == consumer) produce();
            std::size_t count = 0;
            if (bulk) count = ring.dequeue_burst(std::span{out}.first(burst));
            else while (count < std::size_t(burst) && ring.dequeue(out[count])) ++count;
            for (std::size_t j = 0; j < count; ++j) {
                if (out[j].id != consumed || out[j].checksum != academy::checksum(consumed, 64)) failed.store(true);
                ++consumed;
            }
            if (clock::now() - begin > std::chrono::seconds(5)) { failed.store(true); break; }
        }
        const auto end = clock::now();
        stop.store(true);
        if (worker.joinable()) worker.join();
        if (failed.load() || produced != total || consumed != total) return 1;
        if (sample >= 0) {
            const double ns = std::chrono::duration<double,std::nano>(end - begin).count() / total;
            std::printf("%d,%d,%d,%d,%d,%llu,%.9f\n", sample, bulk, burst, producer, consumer,
                        static_cast<unsigned long long>(total), ns);
        }
    }
}
