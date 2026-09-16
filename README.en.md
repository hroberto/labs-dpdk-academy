![labs-dpdk-academy — study guide and hands-on lab for DPDK: high throughput, low latency, C/C++23, Linux, reproducible measurements. The illustration follows a packet: in through RX, processed by DPDK, across rings and mempool, spread over lcores, and into NUMA memory.](labs-dpdk-academy-preview.en.png)

# DPDK Academy

A study guide for DPDK grounded in software engineering, systems architecture,
C++23 and in-depth technical teaching.

*Leia em [português](README.md).*

> **Full parity, and what it costs.** This page is a **complete counterpart** of
> [`README.md`](README.md), not a summary — same sections, same tables, same
> numbers. The project kept an English summary for a long time, for a reason
> written down in the [roadmap](ROADMAP.md): *a stale English version does not
> make the reader think the translation is behind, it makes them think the
> numbers are unreliable.*
>
> Parity was chosen anyway, so the defence against staleness had to become
> mechanical rather than a matter of discipline: `verificar-autodescricao.py`
> checks that every module has its English counterpart and that **no number
> published here is absent from the Portuguese**. What it cannot check is
> meaning — that limit is stated in its own header, and it is the honest edge of
> this parity.

## Purpose

This repository is meant as a teaching base for beginners and advanced
practitioners who want to learn DPDK in a structured, deep and applied way.

It combines:

- theoretical foundations of DPDK and of the data plane
- software architecture and high-performance runtime
- practical exercises in C and C++23
- comparison against pure C++23 implementations
- a critical take on trade-offs and performance
- documentation treated as a source of technical knowledge

## What this project covers

- introduction to DPDK and the role of the data plane
- high-performance principles and software architecture
- Linux fundamentals: memory, cache, NUMA and CPU affinity
- [EAL][cEAL], mbuf, mempool, ring and packet lifecycles
- RX/TX, burst, batch processing and polling
- comparison between DPDK and pure C++23 software
- benchmarking, observability, quality and real engineering

## Repository layout

- `docs/` — teaching documentation and study structure
- `trilha/` — modules organised by depth level
- `scripts/` — build and test automation
- `subprojects/` — test dependencies pinned by hash (`.wrap` files)
- `ROADMAP.md` — overview of the project's evolution plan
- `LICENSE` — licence for the project's content

Every topic in the trail is **self-contained**: document, code, tests and, where
it exists, the no-DPDK alternative for the same problem, under `alternativas/`
inside the topic itself. For example:

```
trilha/01-fundamentos/02-mempool-ring/
├── README.md              theory, mechanism, trade-offs, exercises
├── packet.c / packet.h    pure logic (testable without DPDK)
├── pipeline_ring.c        runtime: EAL, mempool, ring
├── tests/                 L1 (GoogleTest) and L2 (integration)
└── alternativas/cpp23/    same problem without DPDK, same contract
```

## Teaching philosophy

This project does not treat DPDK as an isolated tool. It aims to teach:

- theory and architecture before the API
- mechanism before optimisation
- runnable practice before imagined performance
- software design before context-free micro-optimisation
- clear, rigorous documentation as part of engineering
- numbers that are measured and confronted with the literature, never asserted

## Study trails

The main trail lives in:

- `docs/plano-estudo-dpdk.md`
- `trilha/README.md`
- `ROADMAP.md`

**The canonical study order is the ten levels of the
[study plan](docs/plano-estudo-dpdk.md).** It is the only numbering the modules
cite: each document opens by declaring its "Nível N", and that is the number
that counts. The other entry documents play different roles and do not number
the progression:

| Document | What it is for |
|---|---|
| [docs/plano-estudo-dpdk.md](docs/plano-estudo-dpdk.md) | **the study order**, in ten levels — what the modules cite |
| [trilha/README.md](trilha/README.md) | index of what exists in code and tests, with each topic's state |
| [ROADMAP.md](ROADMAP.md) | the **build** order of the material — not a reading order |

The ten levels, and where each one is:

| Level | Subject | State |
|---:|---|---|
| 1-2 | System and network fundamentals | [docs/01-fundamentos](docs/01-fundamentos/) |
| 3 | Runtime and EAL | [docs/02-runtime-dpdk](docs/02-runtime-dpdk/) · [trilha 01-eal-hello](trilha/01-fundamentos/01-eal-hello/) |
| 4 | Mempool, mbuf, ring and the data cycle | [docs/03-mempool-ring-mbuf](docs/03-mempool-ring-mbuf/) · [trilha 02-mempool-ring](trilha/01-fundamentos/02-mempool-ring/) |
| 5 | Pipeline and backpressure | [trilha/02-pipeline](trilha/02-pipeline/) — **written**; queue depth and refusal measured |
| 6 | RX/TX and hardware | [trilha 01-rx-tx-burst](trilha/02-pipeline/01-rx-tx-burst/) — environment measured, no code; depends on a NIC |
| 7 | NUMA, cache and performance | covered inside the [fundamentals](docs/01-fundamentos/) |
| 8 | Observability and quality | [trilha/03-performance](trilha/03-performance/) — **written**; measurement method and telemetry measured |
| 9 | Virtualisation and cloud | **not started** |
| 10 | Final project and alternatives | [trilha/04-projeto-final](trilha/04-projeto-final/) — **consolidation written**; the application does not exist |

> **This table replaced a seven-step list that competed with the ten levels
> instead of citing them.** The collision was concrete: step 5 of the list was
> "NUMA, cache and CPU affinity" while Level 5 is "Pipeline", so "level 5" meant
> two different things depending on the document. The list also omitted, without
> saying so, levels 6 and 9.

## What is assumed of you

The trail goes from beginner to advanced **in DPDK** — not in systems
programming. Familiarity with C, Linux, threads, pointers and networking basics
is expected; knowing NUMA, TLB, hugepages, cache coherence, IOMMU or anything
DPDK-specific is **not** — the material teaches those from zero.

The full list, with what is taught and what is not, is in
[docs/00-visao-geral](docs/00-visao-geral/README.md#2-o-que-se-pressupõe-do-leitor).

## Tooling requirements

- Linux x86_64 or arm64
- GCC 14+ or Clang 18+ (C11 and C++23; POSIX declarations come from
  `_GNU_SOURCE`, declared per file — see
  [ferramental §2.2](docs/00-visao-geral/ferramental.md))
- **DPDK 23.11 or newer**, with `pkg-config --modversion libdpdk` working
  (Debian/Ubuntu: `dpdk-dev`; Fedora/RHEL: `dpdk-devel`)

  | Release | State |
  |---|---|
  | 25.11 | reference machine — every published number comes from it |
  | 23.11 | CI (Ubuntu 24.04); the suite passes |
  | < 23.11 | untested; `meson setup` refuses |

  The range is not decorative: the difference between 23.11 and 25.11 has
  already produced two defects that show up in only one of them —
  `--in-memory --no-huge` together, and the exit code for an unknown argument.
  Both are documented in
  [topic 01](trilha/01-fundamentos/01-eal-hello/README.md).
- Meson 1.1+ and Ninja

Optional, and only from the benchmarking and quality stage onwards:
clang-format, clang-tidy, sanitizers and perf. Nothing in the current trail
depends on them — building, running and testing topics 1 to 4 needs only the
list above.

GoogleTest, used by the L1 tests, is fetched automatically by Meson and does not
need to be installed. Run `./scripts/check-env.sh` to diagnose the environment.
The tooling decisions are explained in
[docs/00-visao-geral/ferramental.md](docs/00-visao-geral/ferramental.md).

## Quick start

```bash
./scripts/check-env.sh      # what is installed and what is missing
./scripts/ambiente.sh       # records the machine the numbers came from
./scripts/build-all.sh      # configure and build everything
./scripts/test-all.sh       # the whole suite
./scripts/test-all.sh l1    # pure logic only (fast, no EAL)
./scripts/test-all.sh l2    # runtime integration only
./scripts/test-all.sh l3    # only what the host must grant
```

> **Before you wonder about the tests that skip: a reserved hugepage is not a
> usable hugepage.** It is the likeliest trap on this list, and it does not look
> like an error.
>
> DPDK multi-process needs **two** things at the same time: reserved pages
> **and** a `hugetlbfs` mount *your* user can write to. The systemd default is
> `/dev/hugepages`, `root:root 755` — so the common case is a thousand free
> pages and none of them reachable, and the **L3 tests skip** with nothing
> looking wrong.
>
> `check-env.sh` draws that conclusion for you, in one line. When it is missing:
>
> ```bash
> sudo ./scripts/preparar-hugepages.sh
> ```
>
> It asks for privilege **once** and mounts the point in your name — after that
> no run needs root.
>
> **And if you experiment a lot by hand, clean the runtime directory.** Every
> run with a fresh `--file-prefix` leaves tens of MB in `$XDG_RUNTIME_DIR/dpdk`,
> which is *tmpfs*. The suite cleans up after itself; ad-hoc runs do not. When it
> fills up, the EAL dies with **SIGBUS** while mapping the `fbarray` — even under
> `--no-huge` — and the message talks about the bus, not about a full disk. Here
> that took down nine tests at once and looked like a code regression.
> `check-env.sh` warns beforehand; with no DPDK running,
> `rm -rf $XDG_RUNTIME_DIR/dpdk/*` fixes it. And there is no unprivileged
> shortcut: `hugetlbfs` cannot be mounted in a *user namespace* (the kernel does
> not mark it as such), and `--no-huge` does not help because the secondary
> process attaches by mapping the hugepage backing file — without it, there is no
> attach. Measured, not assumed.

### The three test levels, and what separates them

Every test name starts with `l1`, `l2` or `l3`, and the criterion is **not size
nor importance** — it is *what the test needs from the machine in order to run at
all*. That is the question that decides where it lives:

| Level | Needs | Practical consequence |
|---|---|---|
| **L1** | nothing beyond the compiler | runs anywhere, in milliseconds; this is where pure logic lives, without the EAL |
| **L2** | the EAL up, one process, no privilege | runs anywhere; pays ~123 ms of initialisation per case |
| **L3** | something the **host** must grant: writable `hugetlbfs`, several cores | may not run, and then it **skips** instead of failing |

The canonical source of this definition is
[`scripts/test-all.sh`](scripts/test-all.sh), which is also what executes it. To
count how many there are of each:

```bash
meson test -C build --list | grep -oE '^l[123]' | sort | uniq -c
```

**An L3 that skips is not a test that passed.** When the precondition is absent,
the runner exits with code 77 — which Meson records as `SKIP`, not as `OK` — and
prints which precondition was missing. On this machine, as an ordinary user,
three L3 tests skip because `/dev/hugepages` is `drwxr-xr-x root root`: the
condition is checked, not assumed. Confirm it yourself with
`ls -ld /dev/hugepages`, and run `sudo ./scripts/test-all.sh l3` to exercise them
for real.

The distinction exists because the alternative is worse: a test that needs
privilege and *pretends* to pass without it publishes a green that corresponds to
no verification at all.

## Recommended flow

### 1. Theoretical study

Start with the documentation in `docs/` and `trilha/`.

### 2. Modular practice

Every module should be run, understood and documented.

### 3. Comparison against pure C++23

The pure C++23 alternative should be used to understand costs, abstractions and
architecture.

### 4. Benchmark and critical analysis

The goal is not just to "run it", but to understand why the architecture works
and when the choice is the right one.

## Final goal

The project aims to build a solid technical base for anyone who wants to:

- learn DPDK consistently
- understand high-performance software
- work with data architecture and the *data plane*
- compare DPDK against pure C++23 critically and didactically
- build professional documentation and real study material

## Contributing

Suggestions for modules, studies, examples and teaching improvements are welcome.

## Security

How to report a problem, and what counts as a problem in this context:
[SECURITY.md](SECURITY.md). In short: the asset to protect is the **provenance
of the content**, not secrecy — there are no secrets here. Every commit is
signed, and `main` requires a verified signature.

## Licence

Content published for educational and study purposes.

[cEAL]: https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html
