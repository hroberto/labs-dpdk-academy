# Module 03 — Performance and observability

*Leia em [português](README.md).*

> **Level 8** of the [study plan](../../docs/plano-estudo-dpdk.md) ·
> Prerequisite: [02 — Pipeline](../02-pipeline/)

Measure rigorously and see what is happening inside a data-plane program — the two
things that separate "it got faster" from "I know why it got faster".

## State of this module

| Submodule | State |
|---|---|
| [01 — Benchmarking](01-benchmarking/) | **written** — the cost of sloppiness, measured |
| [02 — Observability](02-observabilidade/) | **written** — telemetry exercised against live processes |

Both were written without depending on hardware this machine does not have, which
makes them reproducible by any reader.

## This module is peculiar: the project already uses what it teaches

Every measurement under [`docs/01-fundamentos/medicoes/`](../../docs/01-fundamentos/medicoes/)
and [`docs/02-runtime-dpdk/medicoes/`](../../docs/02-runtime-dpdk/medicoes/) follows
a common methodology, implemented in `statistics.h`:

- median and interquartile range instead of the mean, because
  [the mean lies](../../docs/01-fundamentos/README.md#7-métricas-o-vocabulário-para-não-se-enganar)
  in the presence of a tail;
- robust dispersion as a confidence seal, instead of the coefficient of variation;
- percentiles for latency, with p99 published;
- **declaring the instrument's resolution** alongside the result — the runtime
  module measures its own sampling period so as not to display precision it does
  not have.

The work here was turning practice into teachable content, and measuring what was
still assumption.

## What the two submodules established

**The methodological caveat charges less than it seems — and what it does charge is
something else.** Twelve runs with the starting frequency varying **9×** (0.61 to
5.62 GHz) produced **4.6%** amplitude in the result. The **first run after idle**,
on the other hand, measured ~**30%** more, across three independent observations.
Pinning the governor helps little; discarding the first run helps a lot — the
opposite of what the caveat suggests.

**Telemetry is on by default**, despite the EAL help showing `--telemetry` and
`--no-telemetry` side by side as if one enabled and the other disabled. The one
that changes anything is `--no-telemetry`.

**The CPU profiler does not see the drop at the NIC.** When a descriptor is
missing, no instruction of the process runs — there is no stack to sample. The
counter (`imissed`) is readable through telemetry while the program runs.

## Commitments already published

| Origin | What was deferred to here | State |
|---|---|---|
| [Tooling](../../docs/00-visao-geral/ferramental.md) | adopting `google-benchmark` | **open** — declared in submodule 01's limitations |
| [02-mempool-ring §3](../01-fundamentos/02-mempool-ring/README.md) | rigorous measurement, with frequency control and warm-up | **answered differently** — submodule 01 measured that frequency control matters little here, and that cross-process warm-up matters a lot |
| [Fundamentals §7](../../docs/01-fundamentos/README.md) | formal treatment of jitter | **open** |

The second row deserves a note: the commitment was to *pin* frequency and warm-up,
and what was delivered was the **measurement of what each one costs**. It is less
than promised in execution and more than promised in understanding — anyone
following the promise literally would spend the afternoon on the control that
barely changes the result.

## A level-8 block that still has no owner

The master plan includes, at level 8, **memory safety in the data plane** —
sanitizers, what they cost, and what they miss in code doing pointer arithmetic over
shared memory. No submodule claims this today. Recorded here so it is not lost;
when it is written, we decide whether it becomes a third submodule or a section of
`02-observabilidade`.

## What is still missing

- **`google-benchmark`**, promised in the tooling document and not adopted;
- **jitter treated formally** — today there is a published p99, not tail analysis;
- **core isolation measured**: this machine has no `isolcpus`, and checking the
  gain requires a reboot. "Isolating helps" remains theory in the material;
- **`imissed` observed happening**: the mechanism is demonstrated with `net_null`,
  which has no hardware descriptor — the value requires the card outside the
  kernel;
- **an automated telemetry test**: it would be L3, and it does not exist.

## Navigation

| | |
|---|---|
| **Previous** | [02 — Pipeline](../02-pipeline/) |
| **Next** | [04 — Final project](../04-projeto-final/) |
| **Index** | [Track](../README.md) · [Study plan](../../docs/plano-estudo-dpdk.md) |
