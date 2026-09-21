# Methodology — mempool, ring and mbuf

*Leia em [português](metodologia.md).*

This file holds the **experimental design** of module 03: what each program
measures, what it deliberately does **not** measure, and how far each result
authorises you to conclude.

It follows the pattern of modules [01](../01-fundamentos/metodologia.en.md) and
[02](../02-runtime-dpdk/metodologia.en.md). The reason to exist is the same:
experimental-design detail interrupts the README without anyone looking for it
there, and separated it stays available to whoever wants to contest a number.

---

## 1. §1 — why the program publishes ratios, not just nanoseconds

This is the module's most consequential methodological decision, and it was
**imposed by the machine**.

The project does not pin the processor's frequency — the
[§5 overview](../00-visao-geral/README.en.md#5-the-measurement-environment)
declares that as a known limitation. The consequence shows up directly in the
measurement: the same binary gave **2.19 ns and 2.77 ns** for `malloc`,
depending on whether turbo engaged.

And the **ratios came out identical** — 2.23× in both.

Hence the rule the module adopts: **the ratio is the claim; the nanosecond is
circumstance.** The text says "twice as fast", not "0.98 nanoseconds", because
the first survives the frequency and the second does not.

The program publishes the observed frequency next to the result, and that is not
ornament: it is what lets whoever reproduces it know whether their collection ran
in the same regime.

> **What this choice costs.** A ratio does not say whether the absolute cost fits
> the budget. For that the nanosecond figure is still needed — which is why the
> program publishes both instead of choosing.

---

## 2. §6.2 — rule 4, and what confronting primary documentation means

[§4 of the sizing header](medicoes/sizing.h) states, **from DPDK's own
documentation**, that with `n % cache_size != 0` some objects *"will always stay
in the pool and will never be used"*.

That was **arithmetic tested at L1** — verified as a calculation, never observed
in a real pool. `pool-esgotado.c` observed it:

| n | cache | predicted stuck | actually obtained |
|---:|---:|---:|---:|
| 4095 | 256 | **255** | **4095** |
| 1023 | 32 | **31** | **1023** |

A single consumer draining the pool obtains **all** objects, including those the
rule gave up for lost.

### What the design required, and where it stops

Finding the discrepancy was the easy part. **Explaining it required reading
DPDK's source**, and that is where it is: in `rte_mempool_do_generic_get()`, when
the cache refill fails because there are not enough objects for a whole batch,
the code does `goto driver_dequeue` and fetches the missing ones straight from
the backing ring.

The published conclusion is that the rule **is not wrong — it is badly stated.**
It does not describe a condition of permanent loss; it describes a regime.

**And the experiment does not cover the regime in which the rule actually
applies**: several lcores, each with its own cache. That is declared in the
README, and it is the difference between "the rule is false" and "the rule does
not hold in the case I measured" — the second is what the evidence supports.

---

## 3. §3 — the ring on a single lcore, and why that is deliberate

Ring measurements run **on a single lcore, with no contention at all**. It is not
accidental: it is what isolates the cost of the MP/MC *path* from the cost of
*contention*.

The result that isolation produces is the interesting one — **there is an MP/MC
cost even without real contention**, and it comes from the atomic operations the
path performs by construction, not from anyone competing.

**What it does not authorise:** saying what the ring costs under contention from
several producers. That is another question, with another design, and the module
does not answer it.

---

## 4. §6 — `pool-esgotado` does not measure time

Worth highlighting because it breaks the pattern of the rest of the repository:
it produces **no median, no IQR, no seal**.

It verifies **boundary behaviour** — how many objects come out, what happens when
the pool runs dry, whether `get_bulk` delivers a partial batch. Those are
deterministic properties, and publishing dispersion over them would invent
uncertainty where there is none.

It is the same distinction [`tlb-real`](../01-fundamentos/medicoes/tlb-real.c)
makes in module 01, and for the same reason: **the statistical instrument depends
on the experimental question**, not on editorial uniformity.

---

## 5. Threats to validity

**Internal validity — did the experiment isolate what it meant to?**

Yes, at the cost of narrowing the scope. One lcore, no contention, warm pool.
Each of those choices removes a variable and, with it, a question.

The most relevant: **the mechanism of the `malloc` step was not investigated,
only observed.** The text says the step appears between 16 and 32, and does not
say why — because it did not measure it.

**External validity — how far does it generalise?**

The **nanoseconds do not generalise**; the **ratios** generalise better, which is
why they are what the module asserts. Neither generalises to a machine with a
different cache hierarchy or a different allocator.

There is **no NIC and no DMA** in any measurement. Everything the module says
about a real packet's life cycle is architecture derived from documentation.

And there is **no comparison between DPDK's *mempool handlers*** — only the
default.

**Construct validity — does the metric represent the phenomenon?**

Here is the caveat that matters most in this module. What is published is **cost
per operation**, not **tail-latency distribution**. A data plane fails by the
tail, not by the mean — and this module measures the mean of a path, not the p99
of a system.

Treating `0.98 ns per operation` as if it said something about a pipeline's worst
case would be swapping one question for the other.

---

## Navigation

- Module: [Mempool, ring and mbuf](README.en.md)
- Methodologies: [Fundamentals](../01-fundamentos/metodologia.en.md) · [Runtime](../02-runtime-dpdk/metodologia.en.md)
