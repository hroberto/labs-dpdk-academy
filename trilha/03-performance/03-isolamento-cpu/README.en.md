# Topic 03 — Affinity is not isolation

> **Part A: operating-system noise, without the network.** What is measured here
> needs no NIC, no traffic generator and no reboot. The part that does need them
> — `imissed` observed happening — is declared in §8 and awaits the hardware,
> like the RX/TX module.

A thread pinned with `sched_setaffinity` does not leave the CPU. That is not the
same as owning the CPU. The system keeps running work there: the scheduler tick,
RCU callbacks, per-CPU workqueues, IPIs from other CPUs and device interrupts.

This topic measures **how much** of that happens on this machine, **which**
source causes each stall, and **when** a stall starts costing packets.

---

## 1. Foundation: the threshold at which a stall costs something

A 10 µs stall is irrelevant on a web server and fatal on a data plane — and the
difference is not opinion, it is arithmetic.

At 10 Gbit/s with minimum-size frames, each frame occupies `64 + 20 = 84 bytes`
on the wire (7 of preamble, 1 of start-of-frame delimiter and 12 of interframe
gap, per [IEEE 802.3][ieee8023]). That is 672 bits, or **67.2 ns per frame** —
the same budget as
[§1 of module 01](../../../docs/01-fundamentos/README.en.md#1-the-budget-how-much-time-exists-per-packet).

While polling is stalled, frames keep arriving and occupy descriptors. The RX
ring absorbs `N × 67.2 ns` before the first drop:

| Descriptors | Window |
|---:|---:|
| 512 | 34.4 µs |
| 1024 | 68.8 µs |
| 2048 | 137.6 µs |
| 4096 | 275.3 µs |

> **The window is a lower bound, and that changes what can be concluded.** The
> NIC's internal FIFO absorbs too, and no driver exposes it. A stall **below**
> this window certainly costs no packet; one **above** it may still cost none.
> Measuring the effective window is exercise 3, and it needs the card.

The arithmetic lives in [`gap_hist.c`](gap_hist.c) and is checked in L1 — it is
arithmetic, not measurement, and the test verifies it by hand.

---

## 2. Mechanism: who interrupts a CPU that already has an owner

`sched_setaffinity` solves **one** problem: the thread does not migrate. It does
not solve the converse — the kernel still has work to do on that CPU.

| Source | Where it shows | What removes it |
|---|---|---|
| Other tasks, load balancing | `ctx-switches`, `migrations` | cpuset `isolated` partition, or `isolcpus=domain` |
| Scheduler tick | `LOC` in `/proc/interrupts` | `nohz_full` — requires **one** runnable task, and a residual tick remains |
| RCU callbacks | `rcuo*` kthreads | `rcu_nocbs` |
| Device IRQ | numbered vector in `/proc/interrupts` | `/proc/irq/*/smp_affinity`, `irqaffinity=`, `isolcpus=managed_irq` |
| Per-CPU workqueues | `ps -eLo psr,comm` | `workqueue` mask |
| `vmstat_update` | `osnoise` | `vm.stat_interval` |
| **TLB shootdown IPI** | `TLB` in `/proc/interrupts` | **no parameter** — see §2.1 |
| Function and reschedule IPIs | `CAL`, `RES` | isolation plus discipline |
| Watchdogs | `NMI` | `nmi_watchdog=0`, `nosoftlockup` — at the cost of diagnosis |
| Firmware SMI | only `hwlat` | none, from the operating system's side |
| C and P states | idle exit latency | `performance` governor, C-state cap |
| Busy SMT sibling | does not appear as an interrupt | leave the sibling idle, or disable SMT |

The last row is already measured in this repository:
[§5.1.1 of module 01](../../../docs/01-fundamentos/README.en.md#511-smt-two-logical-cpus-are-not-two-cores)
shows **2.29×** the time per operation when the SMT sibling is busy, against
**3%** when the neighbour sits on a distinct physical core.

### 2.1 The source no boot line removes

Every mechanism above controls **who else uses the CPU**. There is one case in
which the interrupter is the process itself.

When a thread changes the memory mapping — `munmap`, `mprotect`,
`madvise(MADV_DONTNEED)` — the kernel must invalidate the TLB of **every** CPU
running that address space. It does so by IPI, and the isolated CPU receives it
like any other.

The thread did not migrate, the scheduler did not touch it, no device
interrupted — and there was a stall. The probe produces the effect on purpose
when given a provoker CPU: a thread **of its own** starts changing mappings on
another CPU, and the `TLB` counter rises from **0 to 38,135** in thirty seconds
(§6.2).

> **What removes it is discipline, not configuration.** Do not change memory
> mappings on the hot path. It is why DPDK allocates everything at startup, and
> why [§2.3 of module 02](../../../docs/02-runtime-dpdk/README.en.md#23-what-this-decides-in-the-architecture)
> concludes the process should be long-lived.

### 2.2 What transfers beyond DPDK

Nothing in this section is specific to data planes. A polling loop in any
framework — a matching engine, a bus reader, a game loop — faces the same
sources. What changes between domains is only the threshold: the ring window
here, the response deadline there.

---

## 3. Implementation

| File | Role |
|---|---|
| [`gap_hist.h`](gap_hist.h) / [`gap_hist.c`](gap_hist.c) | power-of-two histogram, window arithmetic — **no DPDK** |
| [`procstat.h`](procstat.h) / [`procstat.c`](procstat.c) | reading `/proc/interrupts` per CPU and per vector — **no DPDK** |
| [`stall_probe.c`](stall_probe.c) | the probe: clock loop, histogram, interrupt deltas |
| [`ipi_provoker.c`](ipi_provoker.c) | the same work in a **separate process** — it is the negative control |

The real provoker is a **thread of the probe itself**, enabled by
`stall_probe <cpu> <s> <threshold> <provoker_cpu>`. The separate program exists
for the contrast: same work, same CPU, **different address space**. §6 shows the
difference between them is total.

> **That distinction was not in the first design, and it cost a collection.**
> The provoker started as a separate program, and the positive control failed:
> `TLB` did not rise. The cause is in §2.1 — the IPI goes to CPUs running the
> **same** address space. The defect became the control.

The separation is deliberate, and it is the same as the
[mempool topic](../../01-fundamentos/02-mempool-ring/README.en.md#41-the-configuration-structure-and-its-invariants):
the arithmetic and the parser need no machine to be tested, and therefore have
an L1 test that runs in milliseconds.

```bash
./scripts/build-all.sh
./build/trilha/03-performance/03-isolamento-cpu/stall_probe 2 10
```

### 3.1 Why a power-of-two histogram, and why the percentile is a floor

A system stall has no single scale: the frequent ones live in microseconds, the
rare ones three orders of magnitude above. A fine linear bucket wastes memory in
the tail; a wide one hides the body. Powers of two give constant relative
resolution, and 64 buckets cover everything that fits in a `uint64_t`.

The price is that the percentile comes out **quantized**. The program returns
the **floor** of the bucket containing it, and does not interpolate:

```
p99.9 floor: 16384 ns      <- the sample lies in [16384, 32768)
max stall:   18304 ns      <- this one is exact
```

Interpolating inside the bucket would assert a precision the histogram does not
have. The **maximum** is kept unquantized because it is the number that decides
whether the window was exceeded — and for that one no approximation is accepted.

### 3.2 Why `CLOCK_MONOTONIC` and not the raw TSC

The TSC is cheaper to read, and would be the obvious choice in a tight loop.
The reason that weighed more is **conversion**: the counter counts ticks, and
turning ticks into nanoseconds requires knowing the rate it runs at.

On this CPU the TSC does **not** vary with the governor — `/proc/cpuinfo`
carries `constant_tsc` and `nonstop_tsc`, and
[§2.2 of module 02](../../../docs/02-runtime-dpdk/README.en.md#22-why-that-wait-exists-and-when-it-does-not-happen)
records both. The problem is a different one: `tsc_known_freq` is absent, so
**nobody publishes the rate** and anyone wanting to convert has to calibrate
it. That is why the EAL spends 100 ms doing exactly that at startup.

A probe calibrating on its own would inherit the calibration's error, and that
error lands precisely on the tail, which is what this topic measures.

`clock_gettime(CLOCK_MONOTONIC)` costs tens of nanoseconds through the vDSO —
an order of magnitude **below** the stalls being looked for. If the read cost as
much as the phenomenon, the instrument would dominate the measurement, which is
the defect the [mempool topic](../../01-fundamentos/02-mempool-ring/README.en.md)
refuses to publish.

---

## 4. Hypothesis, recorded before measurement

> **H1.** With affinity alone, the largest observed stall exceeds at least one
> of the windows in the §1 table.
>
> **H2.** The scheduler tick (`LOC`) is the most frequent source under pure
> affinity, and drops to zero — or to a residue — under `nohz_full`.
>
> **H3.** The `ipi_provoker` raises the `TLB` counter of the probe's CPU in
> **every** profile, including the most isolated one.

**Refutation of each:**

| | Refuted if |
|---|---|
| H1 | the largest stall stays below every window, even under load |
| H2 | `LOC` is not the dominant source, or does not fall with `nohz_full` |
| H3 | any profile zeroes `TLB` with the provoker active |

The third is the one this topic exists to demonstrate, and the one that
contradicts the common expectation that isolation solves it.

### 4.1 Outcome

| | Outcome |
|---|---|
| H1 | **confirmed** — 5 of 20 runs exceed the 512-descriptor window |
| H2 | **half confirmed** — `LOC` dominates; the fall under `nohz_full` was not tested |
| H3 | **confirmed**, and with a contrast that strengthens it |

The missing half of H2 requires a reboot, and is declared untested rather than
inferred. **A hypothesis recorded and not tested does not become confirmed by
plausibility.**

---

## 5. Profiles

Cumulative. The first two **require no reboot**, and are the only ones Part A
executes.

| Profile | Adds | Needs reboot |
|---|---|---|
| P0 | affinity only | no |
| P1 | + IRQ affinity, `vm.stat_interval` | no |
| P2 | + `performance` governor, C-state cap | no |
| P3 | + `isolcpus=domain` or cpuset partition | **yes** |
| P4 | + `nohz_full` + `rcu_nocbs` | **yes** |
| P5 | idle SMT sibling × busy sibling | no |

> **Why P0–P2 and P5 first.** They answer most of H1 and all of H3 without
> touching the boot line. And they answer a debt this material has already
> declared: the [branch's limitations section](../README.en.md) says *"core
> isolation measured"* is still owed.

> **P2 was collected; P1 is still out.** Both require privilege, and the
> reference machine asks for a password. P2 was obtained in a dedicated
> collection and the outcome is in §6.6: **null effect on the tail on this
> machine**. P1 — IRQ affinity and `vm.stat_interval` — remains pending.

> **And the sixty runs say something about how much P1 still matters here.** A
> numbered device vector appeared on the measured CPU **exactly once**: vector
> 114 (`snd_hda_intel`, HDMI audio), with 40 interrupts, in one run of
> collection B. In the other fifty-nine, the only labels were `LOC`, `TLB`,
> `CAL`, `NMI` and `PMI` — none of them addressable by IRQ affinity. On a
> machine with an active NIC the picture would differ, and that is why P1 stays
> on the list instead of being dropped.

---

## 6. Measurement

Eight collections from 2026-09-23, each with four cells × five repetitions ×
30 s, cell order permuted per repetition. Machine declared exclusive; browser
closed. CPU measured: 2 (SMT sibling: 14). Provoker on CPU 4.

Each collection declares the machine state it ran in. The difference between
them is the instrument of §6.6: one collection measures; a pair differing in
one variable decides.

> **Where these collections are.** This topic's `historico/` directory was
> emptied on 24/09/2026: two runs on the same day had collided on the same name
> and one ended up labelled with the wrong memory configuration. The nine
> collections in this table remain in the git history, in the commit preceding
> the removal, and the four that succeed them — the memory factorial of §6.7 —
> are archived under names carrying hour, minute and a configuration checked by
> program. The table is kept because it is the evidence for §6.1 to §6.6; what
> changed is where it lives, and this block exists so that the change is not
> discovered by whoever goes looking for the file.

| | Machine state | max stall, median | above 34.4 µs |
|---|---|---:|---:|
| **A** | single channel; swap 2.01 GiB, available 4.89 GiB | 515.5 µs | 16/20 |
| **B** | dual channel; `performance`, C3 disabled | 29.0 µs | 3/20 |
| **C** | dual channel; `powersave`, C3 active | 25.2 µs | 5/20 |
| **C′** | same as C, 91 min later | 24.1 µs | 1/20 |
| **E′** | same as C, 101 min later | 24.6 µs | 3/20 |
| **D** | same as C + memory pressure confined to a cgroup | 30.9 µs | 7/20 |
| **E** | same as C + global pressure: swap 2.19 GiB, available 5.08 GiB | 153.9 µs | 11/20 |
| **E″** | same as E: swap 2.51 GiB, available 4.87 GiB | 24.0 µs | 1/20 |

> **Collection E′ was planned as a pressure arm and ran with none.** The memory
> consumer's stop condition was absolute — "allocate until 2 GiB sit in swap" —
> and swap was already at that level, left over from the previous collection.
> It was born satisfied, nothing was allocated, and the campaign ran with
> 22.97 GiB available. The arm is valid; what it measures is the **no-pressure**
> condition, and that is how it enters the arithmetic.

**Collection C is the one published in the per-cell tables below.** Medians of
five runs:

| Cell | max stall | preemptions | stalls > 2 µs | `TLB` | `CAL` | `LOC` |
|---|---:|---:|---:|---:|---:|---:|
| P0 — affinity only | 26.3 µs | 228 | 563 | 0 | 1 | 59,974 |
| P0 + **thread** provoker | 24.9 µs | 215 | 24,186 | **38,375** | 38,377 | 59,998 |
| P0 + **process** provoker | 19.7 µs | 153 | 326 | **0** | 1 | 60,000 |
| P5 — busy SMT sibling | 31.6 µs | 203 | 909 | 0 | 0 | 59,984 |

### 6.1 H1: affinity does not hold the tail

**Five of the twenty runs** in collection C have a max stall above the
512-descriptor window, and the largest observed was **752.9 µs** — 22 times
that window, and still **2.7 times** the 4096-descriptor window. H1 holds: one
stall above the window is enough for affinity alone not to guarantee the
budget.

What the collection shows more strongly is the **shape** of the distribution,
not the count. Fifteen runs fall between 15.7 and 31.6 µs, two brush against the
window (34.8 and 40.0 µs) and three jump to the hundreds — 631.6, 660.4 and
752.9 µs. There is nothing between 40.0 µs and 631.6 µs: the distribution is
**bimodal**, with two modes separated by more than an order of magnitude and
nothing in between.

That constrains the mechanism before any further measurement. A continuous tail
would indicate the accumulation of many small sources, each adding a little.
Two disjoint modes indicate a **discrete event** that either happens or does
not, and whose duration is a property of the event, not of the load. §6.6
pursues that event.

The separation between the modes holds across the eight collections. What
changes between them is **how often** the high mode happens — from 1/20 to
16/20 — not where it sits.

### 6.2 H3: the IPI's scope is the address space, not the CPU

It is the cleanest result of the topic, and it comes from comparing two cells
that differ in **one** thing:

| | work | CPU | address space | `TLB` |
|---|---|---|---|---:|
| **thread** provoker | 8 MiB `mmap`/`munmap` | 4 | **the same** as the probe | 38,375 |
| **process** provoker | same | 4 | distinct | **0** |

Same work, same CPU, same volume of memory. The difference is which address
space the thread belongs to, and the effect **disappears completely**.

The eight collections span two memory configurations, two governors and four
pressure conditions. The contrast does not move:

| | A | B | C | C′ | E′ | D | E | E″ |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **thread** provoker | 38,135 | 38,104 | 38,375 | 38,342 | 38,385 | 38,294 | 38,206 | 38,221 |
| **process** provoker | 0 | 1 | 0 | 0 | 1 | 0 | 0 | 1 |

The range on the thread side is 281 counts out of 38 thousand — **0.7%** —
while the max stall varied by a factor of 21 across the same collections. An
effect that ignores everything that makes the tail move is a property of the
mechanism, not of the machine state.

That is why no boot parameter reaches this source: it does not come from
outside the process. What removes it is not changing mappings on the hot path.

### 6.3 The source you can count is not the one that hurts most

The provoker multiplies stalls above 2 µs by **43** — from 563 to 24,186 — and
its cell still has a median max stall **below** the clean P0: 24.9 µs against
26.3 µs.

Thirty-eight thousand TLB IPIs produce thirty-eight thousand **short** stalls.
The source easiest to instrument is the one that matters least to the budget,
and the relation repeats in every collection, including those whose medians are
twenty times larger.

The practical consequence is about method, not about the TLB: **counting a
source's events does not measure what it costs**. A dashboard summing
interrupts per second would classify the provoker as the dominant problem, and
would be pointing at the wrong place.

### 6.4 Affinity does not prevent preemption, and that is measured

The probe takes between **6.7 and 7.8 involuntary context switches per second**
across the eight collections, with the thread pinned. The rate is stable; the
max stall, in the same sample, varies by a factor of 21.

`sched_setaffinity` prevents the thread from **migrating**. It does not prevent
the scheduler from **taking it off the CPU** in favour of another runnable
task: the probe is `SCHED_OTHER` like any process. The `/proc/self/status`
counter shows this unambiguously, and costs one read per run.

> **What this number does NOT establish.** The rank correlation between
> preemption count and max stall is **ρ = 0.42** in collection C — positive and
> weak. The count does not carry **duration**, and a long preemption counts the
> same as a short one. Asserting that the max stall *is* a preemption would
> require `osnoise`, which attributes a source per event.

The stability of the rate across collections is itself information about the
mechanism: the **frequency** with which the thread loses the CPU does not track
the tail. If the high mode were simply "some preemption", collections with 1/20
and with 16/20 of high mode would need different preemption rates, and they do
not have them. The discrete event of §6.1 is rarer than an ordinary preemption,
and telling it apart requires a per-event instrument.

### 6.5 What cell P5 did not decide

The median max stall with the SMT sibling busy (31.6 µs) falls inside the clean
P0 range (15.7 to 752.9 µs across the twenty runs). With five repetitions and
that dispersion, the cell does not separate.
[§5.1.1 of module 01](../../../docs/01-fundamentos/README.en.md#511-smt-two-logical-cpus-are-not-two-cores)
measures **2.29×** of sibling effect on **throughput**; on **tail**, this
experiment measures nothing — and those are different questions.

### 6.6 The search for the source of the high mode

§6.1 establishes what is being looked for: a discrete event, of hundreds of
microseconds, that occurs in some runs and not in others. §6.2 to §6.4
eliminate the sources this topic knows how to instrument — TLB IPIs produce
short stalls, and the preemption rate does not track the high mode.

Each candidate below was subjected to **one single-variable intervention**,
with the refutation criterion fixed before the collection.

#### 6.6.1 Deep C-state — eliminated

C3's exit latency on this machine is **350 µs**, the same order of magnitude as
the high mode. The proposed mechanism: preemption takes the probe off the CPU,
the CPU goes idle, `cpuidle` descends to the deep state, and coming back
charges the 350 µs. Every link is plausible, and together they would explain
the high mode without needing a new source.

**Intervention:** `performance` governor and every state with latency ≥ 20 µs
disabled on all 24 CPUs, which on this machine turns off C3 and preserves C2
(18 µs). Collection B against collection C, with no other difference.

**Outcome: eliminated.** 3/20 against 5/20, medians of 29.0 and 25.2 µs,
Mann-Whitney **p = 0.304**. The high mode remains with C3 disabled.

The chain fails at some link — either the CPU does not descend to C3 within
that interval, or it does and the return does not cost what the latency table
declares. Both cases are distinguishable, and require per-event `cpuidle`
instrumentation.

#### 6.6.2 CPU contention from other tasks — eliminated

A concurrent runnable task would explain long stalls without appearing in
`/proc/interrupts`: the probe loses the CPU and waits for the other's slice.

**Evidence:** `sysstat` recorded a **run-queue size of 1** in both collection A
and collection C, with load averages of 1.69 and 1.10. Collection A has 16/20
of high mode and C has 5/20, with the same queue.

**Outcome: eliminated.** The run-queue size does not distinguish the two
regimes.

#### 6.6.3 Memory pressure as a state — not supported

Collection A ran with **2.01 GiB in swap and 4.89 GiB available** out of a
total of 14.20 GiB. Collection C, with no pressure at all. The proposed
mechanism: scarce memory produces page reclaim, swap I/O completion and
`kswapd` work, and one of those is the discrete event.

**Intervention:** a memory consumer reproduces A's state on the current
machine, without rebooting and without changing hardware. Two variants, because
the proposed mechanism has two separable components:

| | how | what it isolates |
|---|---|---|
| **D** | consumer capped at 6 GiB in a cgroup, allocating 12 GiB | there is page reclaim, but the system outside the cgroup does not have scarce memory |
| **E** | global consumer down to `MemAvailable` ≈ 4.9 GiB with ~2 GiB in swap | reproduces A's global state |

**First result:** E gave 11/20 and a median of 153.9 µs, against 5/20 and
25.2 µs for C — Mann-Whitney **p = 0.028**. D did not reach significance
(7/20, p = 0.160).

**The replication brings the result down.** A second collection under the same
state — E″, with 2.51 GiB in swap and 4.87 GiB available — gave **1/20 and a
median of 24.0 µs**, indistinguishable from the no-pressure condition
(p = 0.269). The two pressure cells differ **from each other** at p = 0.0007,
more than either differs from the no-pressure condition.

Pooling the three no-pressure arms (n = 60, median 24.8 µs, 9/60) against the
two with pressure (n = 40, median 26.6 µs, 12/40): **p = 0.156**.

**Outcome: not supported.** The memory state, reproduced twice, does not
reproduce the effect twice.

> **Why the first collection looked decisive.** With 20 points per arm the test
> has little power, and an arm that happens to contain several high-mode events
> produces p below 0.05 without the intervention having caused anything. The
> 0.028 was not wrong as arithmetic; it was wrong as evidence, and only the
> replication could show that. **A pair of collections is not an experiment.**

#### 6.6.4 Reclaim activity — explains E against E″, does not explain A

E and E″ had equivalent memory state and opposite outcomes, which forces a
search for what differed between them. `sysstat` answers:

| | E (11/20) | E″ (1/20) | ratio |
|---|---:|---:|---:|
| `kswapd` `pgscan` per second | 1,112.6 | 279.3 | 4.0× |
| direct `pgscan` per second | 443.2 | 182.6 | 2.4× |
| `pgsteal` per second | 1,566.4 | 557.5 | 2.8× |
| `pswpout` per second | 691.3 | 123.6 | 5.6× |

The cause of the difference comes from the procedure itself: in E the consumer
had to page out 2.19 GiB from zero; in E″ swap was already occupied by
leftovers, and only 0.32 GiB remained to page out. Equal state, unequal work.

This suggests that what matters is reclaim **activity**, not the static
condition — and collection E corroborates in another way: the high mode decays
over the ten minutes, with memory held constant.

```
  E, max stall per repetition (us)
  rep 1:  689  742  714  502      <- all in the high mode
  rep 2:  734  773  795   29
  rep 3:   35   28   22  273
  rep 4:  670  452   27   23
  rep 5:   28   23   26   25      <- none
```

Constant state with a decreasing effect is the signature of transient activity,
not of a static condition.

**But the hypothesis dies on the collection that motivated it.** During the ten
minutes of collection A, `sysstat` recorded `pgscan = 0` and `pgsteal = 0` —
**no reclaim activity at all** — and A has 16/20 of high mode:

| | reclaim activity | above the window |
|---|---|---:|
| A | none | 16/20 |
| E | high | 11/20 |
| E″ | moderate | 1/20 |
| C, C′, E′ | none | 9/60 |

A and E″ have low activity and opposite outcomes. Reclaim activity
distinguishes E from E″ and **does not distinguish A from C**, which is the
pair that needed explaining.

**Outcome: descriptive, not causal.** The observation is recorded because it is
measured and because it points at the next instrument; it is not proposed as a
cause.

#### 6.6.5 Identifying the source by per-event tracing

The four preceding candidates were eliminated by absent correlation. That
method does not permit confirmation: aggregate counts per vector and per
process establish that a given suspect was not present, but do not attribute an
individual event to an origin.

Per-event attribution requires a specific instrument. The `osnoise` tracer,
integrated into the kernel and exposed by the `rtla` tool, measures the same
quantity as this topic's probe — intervals in which the CPU is taken away from
the running task — and classifies each occurrence into five categories:
hardware, NMI, IRQ, softirq and thread.

Agreement between the two instruments was verified beforehand, across three
independent quantities:

| Quantity | `osnoise` (kthread) | `stall_probe` (process) |
|---|---:|---:|
| largest single stall | 717 µs | 632–834 µs |
| thread events per second | 8.45 | 7.2 |
| IRQ per second | 1,999 | ≈ 2,000 (`LOC`) |

These are two distinct programs, one running in kernel space and the other in
user space, converging on all three measures.

##### Attribution by function

Configured with a stall threshold, `osnoise` records the events that occupied
the CPU at the moment of the largest observed stall. Two independent captures
produced the same result:

```
kworker/2:2  workqueue_execute_start: function amdgpu_device_delay_enable_gfx_off [amdgpu]
kworker/2:2  thread_noise: kworker/2:2  duration 808492 ns
```

The function belongs to the `amdgpu` driver and performs the re-enabling of
power gating for the graphics block. The integrated GPU disables the GFX
subsystem when idle; after each period of use the driver schedules deferred
work to re-enable it, and the transition costs hundreds of microseconds.
Execution occurs in a per-CPU workqueue — the category already listed in the
§2 table, for which no boot-line parameter offers removal.

Distribution by function, over thirteen seconds of tracing:

| Function | n | Largest | Sum |
|---|---:|---:|---:|
| `amdgpu_device_delay_enable_gfx_off` | 12 | 808.5 µs | 2,455 µs |
| `vmstat_update` | 7 | 74.2 µs | 291 µs |
| `psi_avgs_work` | 78 | 51.9 µs | 334 µs |
| `blk_mq_timeout_work` | 1 | 8.8 µs | 8.8 µs |
| `pci_pme_list_scan` | 5 | 8.2 µs | 35.8 µs |

The twelve executions of the `amdgpu` function total a duration greater than
the sum of the remaining ninety-one. None of the other functions exceeds 75 µs.

##### Temporal pattern

The longest events show a one-second periodicity and decreasing duration. The
pattern is reproducible across both captures:

```
  29 s trace                13 s trace
  0.20 s -> 333 us          0.26 s -> 325 us
  1.21 s -> 294 us          1.26 s -> 276 us
  2.22 s -> 243 us          2.27 s -> 171 us
  3.22 s -> 216 us          3.28 s -> 200 us
  4.23 s -> 183 us          4.29 s -> 174 us
  5.24 s -> 110 us          (ceases)
  (silence)                 (silence)
  13.30 s -> 707 us         11.34 s -> 808 us
```

The interpretation consistent with the driver's documented behaviour is work
rescheduling: re-enabling is attempted, does not complete while graphics
processing is pending, and is rescheduled at one-second intervals with
decreasing duration until completion. In both captures the pattern was
preceded by terminal activity, which involves screen redraw.

##### Independent record in the kernel journal

During the investigation the kernel emitted, unprompted:

```
kernel: workqueue: dm_irq_work_func [amdgpu] hogged CPU for >10000us 7 times,
        consider switching to WQ_UNBOUND
```

The named function belongs to the same driver and performs distinct work. The
recorded duration — above ten milliseconds — exceeds by an order of magnitude
the largest event measured in this topic. The record coincided with a momentary
interruption of the graphical interface observed in the session.

##### Hardware noise

§8 listed the firmware SMI as unobservable without the `hwlat` tracer.
`osnoise` classifies hardware noise in a column of its own and recorded zero
over ten minutes of collection. The SMI hypothesis is therefore eliminated on
this machine, and the corresponding limitation is withdrawn.

#### 6.6.6 Intervention: collecting without a graphical session

Identifying the function does not by itself demonstrate causality. The
criterion adopted in the preceding subsections requires a single-variable
intervention: suppress the suspect and verify that the effect disappears.

Blacklisting the `amdgpu` driver would make the console unusable. The
alternative adopted was to suspend the graphical session while keeping the rest
of the system in an identical configuration. The machine was rebooted into a
GRUB entry configured for `systemd.unit=multi-user.target`, with no display
manager, and collection ran from a text console.

**Pre-registration.** Written before execution, in the header of
`ferramental/qualidade/campanha.sh`:

> Prediction: if the origin of the high mode is `amdgpu`, then `osnoise` in
> text mode records a thread maximum below 100 µs, the function
> `amdgpu_device_delay_enable_gfx_off` does not appear among the events, and
> stalls above the window fall to zero or near zero.
>
> Refutation: if the maximum remains in the hundreds of microseconds, or if
> stalls above the window persist in the same proportion, the origin is not
> the graphical session and the attribution is incorrect.

**Result.** Both measures moved in the predicted direction:

| Quantity | With graphical session | Text mode |
|---|---:|---:|
| `osnoise`, thread maximum | 711 µs | **25 µs** |
| `stall_probe`, largest stall | 805 µs | **41 µs** |
| stalls above the window (40 µs) | 37 | **0** |
| `amdgpu_device_delay_enable_gfx_off` | 12 occurrences | **absent** |

The bimodal distribution described in §6.6 does not appear in the absence of a
graphical session. The high mode — the set of stalls between 40.0 µs and 631.6 µs —
disappears entirely. The prediction was not refuted on any of the four
quantities.

This is the conclusion of the chain opened in §6.6: the bimodal distribution
observed in earlier collections was produced by the re-enabling of power gating
on the integrated GPU, scheduled in a per-CPU workqueue and therefore not
removable by CPU isolation, `nohz_full` or interrupt affinity.

##### Convergence of the instruments after the intervention

§6.6.4 recorded an unresolved disagreement between the two instruments:
`osnoise` predicted noise sufficient to affect 84% of cells, while the probe
observed 15% affected. The divergence, a factor of 5.6, was provisionally
attributed to a difference in methodology.

In text mode the disagreement does not reproduce: both instruments record
values of the same order (25 µs and 41 µs). The divergence was therefore a
property of the source, not of the instruments. `osnoise` runs a thread that
consumes no useful CPU; the probe runs a load that occupies the CPU
continuously. A CPU saturated by a user task receives less deferred workqueue
work than one alternating between idleness and activity — which reduces the
frequency of power-gating re-enablement and, consequently, the probe's exposure
to the phenomenon.

### 6.7 Summary of candidates and remaining limitations

| Candidate | Outcome | Evidence |
|---|---|---|
| TLB invalidation IPI | produces **short** stalls | §6.2, §6.3 |
| ordinary preemption | rate does not track the high mode | §6.4 |
| deep C-state | **eliminated** | B × C, p = 0.304 |
| CPU contention | **eliminated** | run-queue = 1 in A and C |
| memory pressure as a state | **not supported** | replication E″, p = 0.269 |
| reclaim activity | descriptive, not causal | §6.6.4 |
| firmware SMI | **eliminated** | `HW = 0` over ten minutes |
| ***amdgpu* driver workqueue** | **confirmed** | §6.6.5, §6.6.6 |

The source was present in the §2 table from the outset, in the row *"Per-CPU
workqueues"*. What was missing was not the hypothesis but the instrument
capable of attributing an individual event to an origin. Aggregate counts per
vector and per process — the method of the first eight collections — allow
candidates to be eliminated by absent correlation, but do not identify the
occupant of the CPU.

The four earlier eliminations are not redundant with respect to the final
finding. Two of them had an order of magnitude compatible with the phenomenon:
C3 exit latency is 350 µs, and the high mode reached 800 µs. Compatibility of
scale alone does not establish cause; accepting it would have produced an
incorrect attribution accompanied by correct values.

#### Implications for the collection protocol

The collections in this topic, and the campaigns published earlier, declare
*"exclusive machine, browser closed"*. Measurement shows that this condition
does not eliminate the graphical session: the compositor, the display server
and the GPU driver remain active and produce, on their own, events of up to
800 µs at intervals of a few seconds.

The effect on published results is bounded by the statistical design adopted.
The project reports **median with dispersion**, not mean. A rare 800 µs event
shifts the median of a collection of billions of samples very little: the three
no-pressure arms pooled (C, C′ and E′, n = 60) give a median of 24.8 µs against
21.5 µs in text mode — a 13% reduction in a metric composed entirely of tail.
For metrics drawn from the body of the distribution, the expected shift is
smaller.

**Those 13% do not measure the effect of the graphical session; they measure
its effect on an idle session.** The §6 table records nine collections on the
same machine: eight fall between 21.5 and 30.9 µs, and collection **A** sits at
**515.5 µs**, twenty times the rest. The distance between 24.8 µs and 515.5 µs
exceeds, by an order of magnitude, the distance between 24.8 µs and text mode —
and both ends were measured with an active graphical session.

The reading the data support is that the graphical session's contribution is
**not an additive constant**: it depends on how much the session worked during
the collection. §6.6.5 supplies the mechanism — power-gating re-enablement is
scheduled by graphics activity, and in both traces the periodic pattern was
preceded by screen redraw. A collection running with an idle session pays 13%;
what one running with the session in use pays is not measured, and collection A
is consistent with a much larger value.

The specification was corrected in `metodologia.md`: collections whose quantity
of interest is dispersion, jitter or distribution tail are to be run in text
mode.

#### The confound between memory and reboot, resolved

The previous version of this section recorded as a permanent limitation that
collections A and C differed in two variables — memory configuration and
reboot — and that separating them would require physically removing a module,
an intervention that was not available. The removal was carried out on
24/09/2026, and the pair was measured.

**The design.** Four cells, a factorial of memory profile by number of
modules, all in text mode, with the BIOS configuration checked by program
against what the collection's name declares. The two cells at 4800 MT/s run the
full isolation campaign and differ **only** in the number of modules.

```
  cell                        median    max     above the window
  ------------------------   -------  -------  -----------------
  4800 MT/s, single channel   22.1 us  38.6 us            1 / 20
  4800 MT/s, dual channel     21.5 us  35.1 us            1 / 20

  Mann-Whitney  U = 229   z = +0.784   p = 0.433
```

Both distributions are unimodal between 14 and 38 µs. There is no high mode in
either.

**The outcome.** The difference between single and dual channel is 0.6 µs and
is not supported at the 5% level. For comparison, collections A and C — the
same two memory configurations, measured with a graphical session — differed by
490 µs, from 515.5 to 25.2 µs.

Memory configuration does not produce the effect attributed to it. The
hypothesis recorded on 23/09, that the A×C difference came from graphical
session activity and not from memory, is **supported**: with the graphical
session absent, the remaining variable stops producing a measurable effect.

> **What this cost and what it taught.** The earlier attribution was not
> arbitrary — memory configuration was the only variable known when it was
> written. The error was not in attributing; it was in attributing the only
> observed variable without declaring that an unobserved one existed.
> `ambiente.txt` began to be recorded because of this.

**The factorial, in passing.** The four cells also measure what each factor
buys, and the mechanism checks out:

| factor | 1 core | 4 cores | 12 cores |
|---|---:|---:|---:|
| channel, at 4800 (1 → 2 modules) | −8.4% | −37.6% | −44.6% |
| speed, at 2 modules (4800 → 6000) | −11.0% | −12.1% | −26.3% |

Doubling channels buys **bandwidth**: the effect grows with parallelism and is
nearly nil on a single core. Raising the frequency buys **latency and
bandwidth**: the effect is roughly constant at low core counts and grows at
high ones. The isolated access (`K = 1`), which measures pure latency, moves
−12.6% with speed.

#### Open questions

- **The nature of the work performed by `gfx_off`** over hundreds of
  microseconds. Tracing identifies the entry function, not the internal
  operations.
- **The effect of disabling power gating.** The `amdgpu` driver accepts
  parameters for this purpose. The intervention would separate the attribution
  "GPU" from the attribution "graphical session", which the present measurement
  does not distinguish.
- **The magnitude of the shift between graphical session and text mode.** The
  comparison was made once, on 24/09: ten of the 198 labels moved by more than
  5%, and the reading of the ten is in §6.7 — seven are artefacts of the metric
  or of the frequency regime, not of the graphical session. One comparison is
  not a series, and separating the two effects was not measured with a design
  of its own.
- **Generality of the finding.** The measurement was obtained on one machine,
  with an AMD integrated GPU and the `amdgpu` driver. Platforms with a discrete
  GPU or a different driver are not covered by this evidence.

---

## 7. Validation

```bash
./scripts/test-all.sh l1     # window arithmetic and parser, no privilege
./scripts/test-all.sh l2     # the probe runs and reports coherently
```

**L1** ([`tests/test_l1.cpp`](tests/test_l1.cpp)) checks what does not depend on
the machine: the 67.2 ns per frame, how the window scales with descriptors and
rate, bucket classification, and the three line shapes `/proc/interrupts` has —
including the trap of a vector's description becoming a count in a fifth,
non-existent CPU.

**L2** ([`tests/l2_run.sh`](tests/l2_run.sh)) asserts nothing about the **value**
of the stalls. That value depends on the machine and is the object of the
measurement; a test demanding a bound would be measurement disguised as an
assertion, and would fail on a loaded machine for the right reason. What it
checks is the contract: the probe measures, classifies, reports the window,
rejects invalid parameters with a distinct code, and **declares** when
`/proc/interrupts` is unreadable instead of staying silent.

---

## 8. Limitations

- **There is no `imissed` here.** Linking a stall to a lost packet needs the NIC
  outside the kernel, and this machine does not have it — the same blocker as
  the RX/TX module. The §1 window is the theoretical bridge, and is declared as
  a lower bound.
- **P3 and P4 require a reboot and remain uncollected.** The procedure is
  feasible through a one-shot GRUB entry, the same mechanism used for the
  text-mode collection (§6.6.6).
- **The probe measures one CPU at a time.** Noise correlated across CPUs, which
  matters in a multi-lcore pipeline, does not appear.
- **The source of the high mode is identified but not exhausted.** It is the
  work item `amdgpu_device_delay_enable_gfx_off`, executed in a per-CPU
  workqueue (§6.6.5); suppressing the graphical session eliminates it on both
  instruments (§6.6.6). What the function performs over hundreds of
  microseconds, and whether disabling power gating removes it with the
  graphical session retained, remain undetermined.
- **Collections with a graphical session are subject to a noise source not
  declared in the protocol.** The condition "exclusive machine, browser closed"
  does not exclude the compositor, the display server and the GPU driver. The
  effect on published medians is bounded — the median of the largest stall
  varied by 13% between the two conditions (§6.7) — but high percentiles and
  maxima measured under that condition incorporate the source.
- **The shift between graphical session and text mode was measured once.** On
  24/09, ten of the 198 labels moved by more than 5%; the reading is in §6.7
  and most of it is an artefact of the metric or of the frequency regime. One
  comparison is not a series.
- **The frequency regime changes with the condition, and that is not
  controlled.** With a graphical session the CPU measures at 5.56–5.61 GHz; in
  text mode it starts at 4.33 GHz and climbs during the run, because nothing
  warms it beforehand. Text mode is not merely "cleaner": it swaps the regime,
  and §1.2 of the
  [fundamentals methodology](../../../docs/01-fundamentos/metodologia.en.md)
  requires declaring which of the two was measured.
- **Twenty runs per arm give little power.** Arm E produced p = 0.028 against
  the no-pressure condition and the replication did not confirm it (§6.6.3). No
  conclusion in this topic rests on a single pair of collections.
- **P1 requires privilege** that the reference machine asks by password. **P2
  was collected** and the outcome is in §6.6.1.

---

## 9. References

- [`isolcpus`, `nohz_full`, `rcu_nocbs`, `irqaffinity`][kparams] — kernel
  command-line parameters
- [Tickless mode][nohz] — what `nohz_full` does and what it does not
- [Per-CPU kthreads][kthreads] — how to reduce kernel work on a CPU
- [cgroup v2, cpuset partitions][cgroup] — isolation without a boot line
- [`osnoise` tracer][osnoise] and [`timerlat`][timerlat] — source attribution
- [`hwlat` detector][hwlat] — firmware latency, invisible to the system
- [IEEE 802.3][ieee8023] — the 20-byte per-frame overhead

[kparams]: https://docs.kernel.org/admin-guide/kernel-parameters.html
[nohz]: https://docs.kernel.org/timers/no_hz.html
[kthreads]: https://docs.kernel.org/admin-guide/kernel-per-CPU-kthreads.html
[cgroup]: https://docs.kernel.org/admin-guide/cgroup-v2.html
[osnoise]: https://docs.kernel.org/trace/osnoise-tracer.html
[timerlat]: https://docs.kernel.org/trace/timerlat-tracer.html
[hwlat]: https://docs.kernel.org/trace/hwlat_detector.html
[ieee8023]: https://standards.ieee.org/ieee/802.3/7071/

---

## 10. Exercises

1. Compute the window for 25 GbE with 64 B frames and 2048 descriptors. Compare
   it with the 10 GbE one: what happens to the margin when the link speeds up?
2. Run `stall_probe` for 60 s under P0 and identify the three highest-delta
   sources. Does any of them surprise you?
3. Run `ipi_provoker` on another CPU and watch the `TLB` counter of the probe's
   CPU. Which boot parameter would solve it? Why does none?
4. Compare P5 with the SMT sibling idle and busy. Does the effect appear as an
   interrupt? If not, where does it appear — and what does that say about using
   `/proc/interrupts` as the only evidence?
5. The probe uses `CLOCK_MONOTONIC`. Switch it to `rte_rdtsc` and explain what
   would have to change in the program for the result to stay valid under the
   `powersave` governor.
