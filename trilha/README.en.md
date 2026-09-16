# Learning track

*Leia em [português](README.md).*

This track organises the study of DPDK into progressive modules, aligned with the
master plan in [docs/plano-estudo-dpdk.md](../docs/plano-estudo-dpdk.md).

## Theory and practice, and how each calls the other

The study has two halves, and they live in different places on purpose:

- **`docs/`** — the theory: the problem, the mechanism and the numbers that hold
  the decisions up. Read first.
- **`trilha/`** (here) — the practice: runnable code, tests and exercises. Run
  afterwards, and go back to the theory whenever the result surprises you.

A track topic without its theory module becomes a recipe; a theory module without
its topic becomes reading. The table below ties the two together.

## Mapping to the master plan

| Level | Theory in `docs/` | Practice here | State |
|---|---|---|---|
| 1 — system fundamentals | [01 — Fundamentals](../docs/01-fundamentos/README.md) | — | **written** |
| 2 — networking and the data plane | [01 — Fundamentals](../docs/01-fundamentos/README.md) | — | **written** |
| 3 — [EAL][cEAL] and runtime | [02 — DPDK runtime](../docs/02-runtime-dpdk/README.md) | [01-eal-hello/](01-fundamentos/01-eal-hello/) | **written** |
| 4 — mempool, ring and mbuf | [03 — Mempool, ring and mbuf](../docs/03-mempool-ring-mbuf/README.md) | [02-mempool-ring/](01-fundamentos/02-mempool-ring/) | **written** |
| 5 — pipeline and design | — | [02-pipeline/](02-pipeline/) | **written** (backpressure measured) |
| 6 — RX/TX, burst and hardware | — | [02-pipeline/01-rx-tx-burst/](02-pipeline/01-rx-tx-burst/) | scope and environment measured; the hardware is what is missing |
| 7 — NUMA, cache and real performance | [01 — Fundamentals §4 and §5](../docs/01-fundamentos/README.md#4-memória-onde-o-desempenho-realmente-se-decide) | to be defined | theory written; practice pending |
| 8 — observability and quality | — | [03-performance/](03-performance/) | **written** |
| 9 — virtualisation, SR-IOV, [vhost-user][cVhost] | — | — | not started |
| 10 — final project and the alternatives ([AF_XDP][cAfxdp]) | — | [04-projeto-final/](04-projeto-final/) | **consolidation written**; the application does not exist |

## Current structure

| Directory | Content | State |
|---|---|---|
| [01-fundamentos/](01-fundamentos/) | EAL initialisation; mempool, ring and batching, with a C++23 alternative | **two complete topics**, with L1 and L2 tests |
| [02-pipeline/](02-pipeline/) | batching, backpressure, RX/TX | **written**; RX/TX waits for the card |
| [03-performance/](03-performance/) | benchmarking and observability | **written** |
| [04-projeto-final/](04-projeto-final/) | consolidation and comparison with the alternatives | **consolidation written**; the application is missing |

## The scenario that runs through the modules

Where it helps to anchor a concept, the examples lean on a single scenario: a
***market data* server** receiving an exchange feed. It shows up in the
[fundamentals](../docs/01-fundamentos/README.md#62-o-barramento-também-tem-orçamento)
as the extreme ultra-low-latency case, and in the
[runtime module](../docs/02-runtime-dpdk/README.md) as the system that justifies
separating processes.

It is **grounding, not a straitjacket**. The object of study is DPDK, and when a
concept asks for a different example, the different example is used — the topics
under `01-fundamentos/`, for instance, work with generic packets, and that is
right: what they teach does not get clearer by calling the packet a *tick*.

## Philosophy

The track combines:

- technical didactics
- progressive study
- comparison against pure C++23
- direct application in runnable examples
- a focus on real engineering and trade-offs

## Pedagogical goal

At each module, the student should be able to:

- place the concept inside the overall plan
- understand DPDK's internal mechanism
- recognise limitations and trade-offs
- implement or adapt an example
- document the technical conclusions

## State of the material

Levels 1 to 4 have real content on both sides: theory in `docs/`, practice in
`trilha/`, with code, tests and reproducible measurements.

Levels 5, 8 and 10 gained content on 16/09/2026: backpressure and queue depth in
[02-pipeline](02-pipeline/), measurement methodology and telemetry in
[03-performance](03-performance/), and the consolidation in
[04-projeto-final](04-projeto-final/) — all measured on this machine. **No
document is a skeleton.**

That does not mean everything is finished, and the difference matters: the final
project has the consolidation written and **does not have the application**, which
it declares in its first section instead of calling itself done. The
[RX/TX](02-pipeline/01-rx-tx-burst/) submodule has the environment and the NIC's
capabilities measured, and waits for the card to leave the kernel.

The state table above is kept alongside the material — if it diverges from what is
on disk, the disk is what is right and the table needs fixing. Since 16/09/2026
that divergence does not depend on someone noticing: `verificar-autodescricao.py`
checks each "skeleton" label in this table against the banner of the document it
points to, and it was what flagged these four rows as soon as the modules were
finished.

[cEAL]: https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html
[cVhost]: https://doc.dpdk.org/guides/nics/vhost.html
[cAfxdp]: https://doc.dpdk.org/guides/nics/af_xdp.html
