# Methodology — the DPDK runtime

*Leia em [português](metodologia.md).*

This file holds the **experimental design** of module 02: what goes inside the
stopwatch, what stays outside, how many samples and why, and how far each result
authorises you to conclude.

It exists for the same reason as [module 01's](../01-fundamentos/metodologia.en.md):
the README is meant to be read end to end, and experimental-design detail
interrupts that reading without anyone looking for it there. Separated, it can be
consulted by whoever wants to contest a number — the reader who matters most.

---

## 1. §2 — why `custo-init` needs one process per sample

The design was not chosen: **it was imposed by the object of study.**

[`rte_eal_init()`][apiealinit] is not reentrant. A second call in the same
process returns `EALREADY` without reinitialising anything. Measuring N samples
inside a loop, as the rest of the project does, would measure one initialisation
and N−1 error returns.

Hence the structure:

```
  parent   fork() ──► child: rte_eal_init(), times it, rte_eal_cleanup()
                             writes the result to a pipe and exits
  parent   reads the pipe, aggregates, repeats
```

**Each sample costs a whole process**, and that is what caps their number at
**11**. It is not a statistical choice: it is what fits in a time someone will
accept waiting in order to reproduce it.

### What is inside the stopwatch

Only `rte_eal_init()`. The `fork()`, the pipe creation, the result write and
`rte_eal_cleanup()` stay outside — the first because it is instrument cost, the
rest because they answer a different question, and the module publishes shutdown
on its own line.

### What the design charges

Eleven samples support a median and an interquartile range. They **do not
support a high percentile**, and the module publishes none. It is the same ruler
as [§7 of the fundamentals](../01-fundamentos/README.en.md#7-metrics-the-vocabulary-for-not-fooling-yourself):
for p99 to mean anything, 1% of the set has to be at least one sample.

---

## 2. §2.1 — measuring and diagnosing are distinct steps

This is the part of the module most often lost when someone summarises the
result, and the order matters more than the tools.

| Step | Instrument | What it produced |
|---|---|---|
| **measure** | [`custo-init.c`](medicoes/custo-init.c) | the 118 ms, with dispersion |
| **locate** | `strace -T` | *where* 100 of those milliseconds are |
| **explain** | the DPDK source | *why* the wait exists |

**`strace` did not produce the published number.** It came afterwards, to answer
a question the measurement raised and could not settle: a total does not say
where the time went.

And the choice of locating instrument was imposed too. A sampling profiler
**samples the CPU**, and a sleeping process consumes no CPU — the 100 ms of
waiting would be invisible to it. `strace` intercepts the **boundary**, which is
exactly where the wait happens.

> **Why this is methodology and not trivia.** Publishing "118 ms, of which 100
> are waiting" as if it were a single measurement hides that these are two
> experiments with different instruments and different degrees of confidence.
> The first has published dispersion; the second is a single observation.

---

## 3. §2.2 — why 118 ms here, and why that is not a property of DPDK

The ~100 ms calibration runs because this machine **does not expose
`tsc_known_freq`**:

```bash
grep -o 'constant_tsc\|nonstop_tsc\|tsc_known_freq' /proc/cpuinfo | sort -u
```

Without the flag the EAL does not trust the declared frequency and measures it —
and measuring frequency takes wall-clock time, not CPU time.

**On a machine that exposes the flag, the same `rte_eal_init()` would cost
something close to 18 ms.** The 118 ms are a property of this CPU-and-kernel
combination, and the module says so in the section itself.

That is why the program accepts EAL options directly: measuring on your machine
is part of the exercise, not a courtesy suggestion.

---

## 4. §4.6 — the instrument's resolution, and why it is published

The cross-process crossing is measured with the producer stamping each tick with
`rte_rdtsc()` and the consumer reading it. The instrument has a floor, and the
program prints it next to the result: **11.9 ns, one consumer poll**.

**No value below that means anything.** The consumer only observes the tick when
it polls; the interval between polls is the granularity of what it can
distinguish.

Publishing the resolution next to the result is what prevents the most likely
misreading: treating a 5 ns difference between two configurations as an effect,
when it sits below what the instrument resolves.

---

## 5. Threats to validity

Three different questions, and confusing them is what turns measurement into
folklore.

**Internal validity — did the experiment isolate what it meant to?**

`custo-init` isolates well: one process per sample removes interference from
accumulated state, and the timed interval contains only the measured call. The
multiprocess experiment is more fragile — producer and consumer run in the
**same L3 cache domain**, and
[§4.3 of the fundamentals](../01-fundamentos/README.en.md#43-numa-when-memory-stops-being-one-thing)
measures that crossing domains costs four times as much. The published number is
the favourable case.

**External validity — how far does it generalise?**

The 118 ms **do not generalise**, and §2.2 gives the mechanism. What does
generalise is the shape of the argument: the EAL pays for calibration when the
kernel does not declare the TSC frequency, and that is verifiable on any machine
with one `grep`.

The machine has **a single NUMA node** and **no NIC handed to VFIO**. Everything
the module says about `socket_id` and about the data path is architecture derived
from documentation, not measurement.

**Construct validity — does the metric represent the phenomenon?**

Here sits the caveat easiest to lose. "Cost of initialising the EAL" is
**wall-clock** time, not CPU time — and most of it is waiting, not work. In a
system that initialises several instances in parallel, that time **overlaps**;
treating it as CPU cost would lead to sizing the system wrong.

---

## Navigation

- Module: [The DPDK runtime](README.en.md)
- Previous module's methodology: [Fundamentals](../01-fundamentos/metodologia.en.md)

[apiealinit]: https://doc.dpdk.org/api/rte__eal_8h.html#a5c3f4dddc25e38c5a186ecd8a69260e3
