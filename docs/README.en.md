# Project documentation

*Leia em [português](README.md).*

This directory centralises the teaching base and the technical documentation of
the DPDK Academy project.

## Purpose

To provide a structured study trail for anyone who wants to learn DPDK
practically and deeply, with:

- theoretical foundations of the system and the network
- an understanding of DPDK's internal mechanism
- examples in C and C++23
- comparison against pure C++23 implementations
- focus on architecture, performance and software engineering

## Sections

| Section | Plan level | State |
|---|---|---|
| [00 — Overview](00-visao-geral/) | — | **written**: [positioning, prerequisites, method and measurement environment](00-visao-geral/README.en.md), plus the [tooling](00-visao-geral/ferramental.en.md) |
| [01 — Fundamentals](01-fundamentos/) | 1 and 2 | **written**, with [reproducible measurements](01-fundamentos/medicoes/) and [confrontation with the literature](01-fundamentos/README.en.md#10-comparison-with-the-literature) |
| [02 — DPDK runtime](02-runtime-dpdk/) | 3 | **written**, with [runtime measurements](02-runtime-dpdk/medicoes/) and a [primary/secondary](02-runtime-dpdk/README.en.md#4-primary-and-secondary-processes) *market data* example |
| [03 — Mempool, ring and mbuf](03-mempool-ring-mbuf/) | 4 | **written**, with [measurements](03-mempool-ring-mbuf/medicoes/) of allocation, ring and the [mbuf's anatomy](03-mempool-ring-mbuf/README.en.md#2-the-mbuf-four-numbers-that-look-redundant) |
| [Study plan](plano-estudo-dpdk.en.md) | all | master map of the **10** levels |

Theory lives here in `docs/`; runnable practice lives in
[`trilha/`](../trilha/README.en.md), where each topic gathers document, code and
tests in the same directory.

## Teaching levels

The canonical list is the one in the [study plan](plano-estudo-dpdk.en.md); this is
a summary for quick orientation, and it must agree with it.

1. System fundamentals — Linux, memory, cache, NUMA, execution
2. Network and data-plane fundamentals
3. [EAL][cEAL] and the runtime environment
4. Mempool, mbuf, ring and the data cycle
5. Processing pipeline and software design
6. RX/TX, I/O and hardware-aware design
7. NUMA, cache and real performance
8. Observability and quality
9. Virtualisation and the path to the cloud
10. Final project and the alternatives to DPDK

## Alignment with the trail

The structure of the modules in [../trilha](../trilha) was designed to mirror
exactly the levels described in the master plan in
[plano-estudo-dpdk.md](plano-estudo-dpdk.en.md). The intent is to keep the teaching
progression coherent and to avoid contradictions between documentation and
modules.

## Teaching philosophy

The documentation prioritises:

- concept before the API
- mechanism before optimisation
- practice before "magical" performance
- architecture and trade-offs before simplistic examples
- reliable sources, runnable examples and critical analysis

## Audience

- DPDK beginners
- software and systems professionals
- C/C++ developers
- people who want to learn high performance, architecture and the data plane

[cEAL]: https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html
