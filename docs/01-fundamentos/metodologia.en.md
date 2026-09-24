# Methodology and reproducibility — module 01

*Leia em [Português](metodologia.md).*

> Annex to [Fundamentals](README.en.md). The module's body publishes **what
> changes the reader's mental model**; this file keeps **what proves the
> measurement was done right**.
>
> The separation is not cosmetic. A benchmark autopsy teaches a great deal —
> "disassemble before publishing a microbenchmark" is among the most useful
> lessons here — but it teaches *about measurement*, not about the cost of the
> kernel/user boundary. In the middle of the lesson, it hijacks the lesson.
> Here, it is the lesson.

---

## 1. §2 — the two corrections to `custo-syscall`

The table in [§2](README.en.md#2-the-user-space--kernel-space-boundary) publishes
three numbers: a function call, `clock_gettime` through the vDSO, and a real
syscall. Getting to them took two corrections, instructive for different
reasons: the first is an **instrument** error, the second a failure to **declare
the regime**.

### 1.1 The compiler deleted the call

> **This table once published 0,115 ns and "294×", and both were wrong.** The
> reference function took no argument, had no side effect and returned a constant, so
> GCC classified it as `const`, folded the call into the literal and hoisted it out of
> the loop — `__attribute__((noinline))` prevents *inlining*, not interprocedural
> constant propagation. The measured loop was `movq $0x2a, sumidouro` twice, with no
> `call` instruction at all, and the ratio compared a syscall against two *stores*.
>
> The fix was to make the function opaque to the compiler, with `asm volatile` and a
> memory clobber. Check that the call exists before trusting the number:
>
> ```bash
> objdump -d build/docs/01-fundamentos/medicoes/custo-syscall | \
>     awk '/<m_funcao>:/,/^$/' | grep call
> ```
>
> What remains is the method, which is worth more than this case: **in a
> microbenchmark, disassemble before publishing.** A loop that is too fast is a
> hypothesis of measurement error before it is a result.

### 1.2 The published ratio belonged to another regime

> **THE 36× RATIO IS FROM THE COLD REGIME, and this was measured on 16/09/2026.** The
> table above is a faithful transcription of one run — but of a **first run after
> idle**, and in that regime the function call measures 0.92 ns. Eight consecutive
> runs, with the machine already in use, give 0.72 to 0.75 ns for the same call, and
> the ratio rises to **45× to 49×** (median 46×).
>
> Both regimes are real and reproducible, each with low internal dispersion — the
> table above shows 0.4% amplitude. What was missing was **declaring which one the
> measurement came from**.
>
> The effect is the same one the
> [benchmarking submodule](../../trilha/03-performance/01-benchmarking/) measures and
> explains: the first run after idle comes out ~30% high on the shortest operation.
> Here it did not inflate a loose number — it inflated the **denominator** of a ratio,
> and so the ratio came out **low**: 33,5/0,92 = 36, against 33,8/0,73 = 46.
>
> **This section's argument does not change**, because it never depended on the ratio:
> it comes from 33.8 ns against a 67.2 ns budget, and the function call does not enter
> the account. But the ratio is the sentence people repeat, and it was 22% low.
>
> Reproduce it: run `custo-syscall` once after a few minutes of an idle machine, and
> then eight times in a row. The difference shows in the first line.

### 1.3 What survives from both

| Correction | Class of error | Lesson that survives |
|---|---|---|
| 0.115 ns / 294× | the instrument did not measure what it claimed | disassemble the binary before publishing |
| 36× against 46× | the measurement was right, the regime was undeclared | say whether you measured cold or in steady state |

And an observation that holds for the whole document: **neither changed §2's
conclusion**. It comes from 33.8 ns against a 67.2 ns budget, and the function
call does not enter that account. What both hit was the **ratio**, which is the
soundbite — exactly the part people repeat, and therefore the part that most
needs to be right.

---

## 2. §4.1 — the design of `custo-traducao`

[§4.1](README.en.md#41-virtual-memory-what-translating-an-address-means)
publishes the difference between 4 KB pages and 2 MB hugepages. Three design
decisions support that number, and none of them changes the reader's mental
model — they prove the measurement isolates the *page walk* from everything
else.

### 2.1 What is left outside the stopwatch

**What is left outside the stopwatch, on purpose.** Measured on the reference
machine, for one 512 MB sample:

| Step | Cost | Why it stays out |
|---|---|---|
| `mmap` of 512 MB | ~0 ms | it only creates the mapping; no memory exists yet |
| `memset` of the region | 88 ms (4 KB) / 46 ms (2 MB) | **forces the page faults here**, not in the loop |
| shuffle and chain construction | ~215 ms | writing 8.4 M pointers is not the object of the test |
| `free` of the order array (64 MB) | — | returned before the first timestamp |
| **timed loop** | **~3 500 ms** | ← this alone enters the calculation |

The `memset` is the important item on that list, and the number of page faults it
triggers is the section's own arithmetic showing up in the system counters:

```
  4 KB pages:       131 072 page faults   (512 MB ÷ 4 KB)
  2 MB hugepages:       256 page faults   (512 MB ÷ 2 MB)
```

Without that pre-touch, the first lap around the cycle would pay one page fault
for every new page — microseconds each — and the measurement would publish the
cost of **creating** the mapping, not of **translating** it. Note in passing that
the `memset` itself already costs nearly twice as much with 4 KB pages: 131 072
entries into the kernel against 256.

### 2.2 Why the region is exactly 512 MB

The size is not arbitrary. It is the one value that satisfies four constraints at
the same time, and understanding that is understanding the experiment:

| The region must be… | Otherwise… | On this machine |
|---|---|---|
| much larger than L3 | the walk measures cache, not memory | L3 = 32 MB per block |
| much larger than TLB reach with 4 KB | the "bad" side does not miss, and there is nothing to measure | needs 131 072 entries |
| small enough to fit TLB reach with 2 MB | the "good" side misses too, and the difference vanishes | needs 256 entries |
| small enough for the reservation to be practical | the test becomes a privilege of big machines | 256 hugepages = 512 MB |

The two middle rows are the heart of the design. No second-level TLB on current
x86 holds more than a few thousand entries — that is, **131 072 entries do not fit
by any stretch**, and nearly every access on the 4 KB side pays the walk. Whereas
**256 entries fit comfortably in any of them**, and the 2 MB side hits nearly
always. The experiment forces both extremes and publishes the distance between
them.

This is also the answer to [exercise 6](README.en.md#exercises): shrinking the region to 4 MB
makes the advantage disappear, because then both sides fit — 1 024 entries of
4 KB still fit in the TLB, and the whole 4 MB fits in L3.

### 2.3 The reserved area: 256 hugepages, and why the recipe asks for 512

**`MAP_HUGETLB` does not negotiate.** Unlike *transparent hugepages*, which the
kernel promotes in the background when it can, that flag serves itself from a
**pool reserved in advance** and **does not fall back to 4 KB** when the pool is
not enough: the `mmap` fails with `ENOMEM`, and that is that.

It is that absence of silence that lets the program use a real measurement as a
capability test — if `amostra_2m()` returns an error, it is because the
reservation does not exist:

```c
if (amostra_2m() < 0) { /* ... */ return 77; }   /* 77 = SKIPPED in Meson */
```

Exit code 77 is there for a reason documented in
[`meson.build`](medicoes/meson.build): exiting with 0 made the suite report green
**without anything having been measured**, and since `HugePages_Total=0` is the
default on most machines and on the CI runner, the false green was the rule, not
the exception.

**The reservation arithmetic:**

```
measured region        512 MB
hugepage size            2 MB
                      ────────
minimum required        256 hugepages
```

The document's recipe asks for **512** (`sudo sysctl -w vm.nr_hugepages=512`),
twice the minimum. The slack is not waste; it covers three real situations:

- **the pool is global.** Another process — a running DPDK, an earlier test that
  did not shut down — may be holding part of it.
- **on a machine with more than one NUMA node the pool is split across nodes.** An
  `mmap` of 512 MB needs 256 pages **on the node where the memory will be
  touched**; with 512 pages split across two nodes, exactly the minimum is left
  and no margin at all.
- **the reservation can be partially satisfied** — the next point.

**`sysctl` does not fail loudly, and this is the most common operational
mistake.** If memory is fragmented, the kernel reserves *whatever it can* and the
command succeeds anyway. The only way to know is to read it back:

```bash
sudo sysctl -w vm.nr_hugepages=512
grep -E "HugePages_Total|HugePages_Free|HugePages_Rsvd|Hugepagesize" /proc/meminfo
#   Total = what the kernel MANAGED to reserve (may be less than 512)
#   Free  = not yet handed to anyone
#   Rsvd  = promised to an mmap that has not touched them yet
```

If `HugePages_Total` comes back below 256, the measurement will skip. On a machine
that has been up for a long time, reserving early solves it — or at boot, which is
the only reliable way under fragmented memory:

```bash
# persistent, applied at boot
echo "vm.nr_hugepages = 512" | sudo tee /etc/sysctl.d/10-hugepages.conf
# or on the kernel command line: hugepagesz=2M hugepages=512
# per NUMA node, when there is more than one:
echo 256 | sudo tee /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages
```

**The reservation comes out of system memory.** Reserved pages stop being
available for anything else: they do not count towards `MemAvailable`, they are not
reclaimed under pressure, and they never go to swap. 512 pages of 2 MB are **1 GB
taken away from the machine** for as long as the reservation exists.

> **This reservation is not the same one as
> [`preparar-hugepages.sh`](../../scripts/preparar-hugepages.sh).** That script
> mounts a **writable hugetlbfs**, which the primary/secondary model of module 02
> needs, where two processes must map the same *file*. `custo-traducao.c` uses
> **anonymous** memory (`MAP_ANONYMOUS | MAP_HUGETLB`) and needs no mount point at
> all: it only needs the **pool to exist**. Reserving without mounting is enough
> here; mounting without reserving is not.

---

## 3. §5.2 — why the single-threaded regime was discarded

[§5.2](README.en.md#how-much-sleeping-costs--and-what-exactly-is-expensive)
measures the uncontended mutex at **8.5 ns**, and states that every measurement
runs with another thread present in the process. A smaller number was available,
and it was discarded — the reason is methodological, and among the most
instructive in the module.

> **Aside: glibc's fast path, and why it was discarded.**
>
> glibc keeps a shortcut for **single-threaded** processes, in which the same mutex costs
> ~2 ns instead of 8.5 — there is no one to compete with, so the atomic instruction is
> skipped. The number is real, and even so invalid as a reference.
>
> The first reason is that no concurrent program enjoys it. The second is worse: the
> shortcut is lost **permanently** on the first thread creation, and does not come back
> even after the thread is joined.
>
> ```
>   before any thread             :  2.40 ns
>   after creating AND JOINING one:  8.99 ns
>   __libc_single_threaded = 0
> ```
>
> The practical consequence is fatal for the measurement: the value depended on the
> **order** in which the measurements ran within the program, varying from 2.4 to 9.0 ns
> according to position in the file. **A measurement that depends on the order in which
> you measure is not a measurement** — so the single-threaded regime was abandoned, and
> the table above reports only the realistic case.

---

## 4. §10 — this machine's PTI state

[§10](README.en.md#why-the-syscall-is-so-cheap-here) states that PTI is not
active on this machine, and that the 33.8 ns syscall is therefore not a
universal cost. The statement is **measured**, not inferred from the
architecture — being AMD does not imply PTI is off, because the mitigation is
configurable by boot parameter.

The three checks, with literal output. None of them needs privileges:

```bash
$ cat /sys/devices/system/cpu/vulnerabilities/meltdown
Not affected

$ grep -o '\bpti\b' /proc/cpuinfo
        (no output — the `pti` flag only appears when PTI is active)

$ cat /proc/cmdline
BOOT_IMAGE=/boot/vmlinuz-7.0.0-31-generic root=UUID=<omitted: identifies the machine> ro quiet splash amd_iommu=on iommu=pt crashkernel=2G-4G:320M,4G-32G:512M,32G-64G:1024M,64G-128G:2048M,128G-:4096M
```

The three say different things, and all three are needed:

| Check | What it establishes |
|---|---|
| `vulnerabilities/meltdown` | the kernel classifies this CPU as unaffected by classic Meltdown |
| `pti` flag in `/proc/cpuinfo` | **PTI is not active** — this is what proves the state, not the previous one |
| `/proc/cmdline` | nothing was forced by parameter: no `pti=on`, `pti=off` or `nopti` |

The third closes the obvious objection. Without it, a reader could assume the
observed state came from manual configuration rather than the kernel's default
for this CPU.

> **A distinction worth keeping separate.** "This CPU is not affected by classic
> Meltdown" is **not** the same as "this CPU has no speculative-execution
> vulnerabilities". They are different claims, and only the first one is here.

---

## 5. The `0.397` of the `relaxed atomic`, and who explained it

The between-runs campaign of 19/09/2026 found in `custo-espera` a value that
**no measurement from inside the machine explained** — and the cause turned out
to come from outside it. The case is recorded because how the answer was found
is worth more than the number.

**What was observed.** Nine runs of the same binary, with one discarded warm-up
run, nine samples each:

```
with ASLR:     0.270  0.205  0.397  0.205  0.205  0.205  0.397  0.205  0.262
without ASLR:  0.206  0.397  0.205  0.206  0.206  0.205  0.206  0.206  0.206
```

Turning address-space randomisation off with `setarch -R` eliminates the
**intermediate** values (0.262 and 0.270) — layout bias, which
[§9.1](README.en.md#91-the-four-scales-of-dispersion-and-what-each-one-cannot-reach)
describes. What remained was the `0.397`, **1.94 times** the modal value, too
large for the frequency ramp, whose amplitude here is 29%.

**What the instrumentation did not find.** Measuring frequency before, after and
maximum during each run, plus context switches and interrupts, the phenomenon
did not recur in 14 runs. Without the probe, another 14 also clean. Twenty-eight
in a row without an occurrence, against a base rate of 1 to 2 in 9 in the
campaigns.

**The missing variable was environmental.** During the campaigns there was
**video being decoded** on the machine; during the investigation, there was not.
That is testable, and the test closes it:

```
  no external load        0.205  0.206  0.206  0.208  0.206
  load on SMT siblings    0.346  0.347  0.345  0.347  0.346
```

The ratio under load is **1.69×**; the one observed in the campaign, **1.94×**.
Both fall between 1 and the **2.29×** that
[§5.1.1](README.en.md#511-smt-two-logical-cpus-are-not-two-cores) measures for an
SMT sibling saturating the ALUs — which is the interval a video decoder falls
into, occupying the sibling part of the time.

**What remains as method, and it is why this section exists.** No instrument
internal to the process could see this: frequency, context switches and
interrupts are consequences, not the cause. **The omitted variable was neither in
the program nor in the machine — it was in whoever else was using the machine.**
That is the practical limit of the ruler in
[§9.1](README.en.md#91-the-four-scales-of-dispersion-and-what-each-one-cannot-reach):
the first three scales of dispersion presuppose that the rest of the system did
not change, and that premise is not verifiable from the inside.

**The fourth scale was born of this gap, and does not close it.** It measures the
effect of machine state by alternating idleness and measurement — which reaches a
state the protocol itself produces. External, unpredictable load, like this
case's, remains outside: seeing it requires looking outside the process, and none
of the four instruments does that.

---

## 6. Pre-registration: the second memory stick

This section is written **before** the measurement, and it is the first time
this repository does that. The reason is that the opportunity is too good to
waste: on 2026-09-20 EXPO 6000 was enabled on the board, and in three days a
second stick goes into slot B2 — same CPU, same kernel, same binary, same
memory speed. **One variable changes: the number of channels.**

Isolation like that is rare. And it answers a question that §4.2 of module 01
answers today without having measured it.

### What §4.2 claims, and what EXPO already hinted

The published text says, about the ~21 GB/s twelve cores reach together:

> *"it is the memory bandwidth, and both paths reach it. One sequential core
> saturates it alone; eight scattered cores have to join forces for that."*

EXPO gave the first hint against the second sentence. It raised the per-channel
rate by 25%, and the sequential access of **one** core did not move:

| RAM, one core | before EXPO | after | change |
|---|---:|---:|---:|
| `sequential` (amortised) | 0.200 ns | **0.195 ns** | **−2.5%** |
| `random` (amortised) | 7.09 ns | 6.45 ns | −9.0% |
| `dependent` (latency) | 98.73 ns | 88.00 ns | −10.9% |

Latency fell 11%, scattered access 9% — and sequential barely moved. A number that does not respond to faster memory **is not limited by
memory**.

### The predictions, and what refutes each

Declared now, with the refutation criterion alongside. This is the part
[§9.1](README.en.md#91-the-four-scales-of-dispersion-and-what-each-one-cannot-reach)
demands and the document had been owing: claiming that two numbers are equal
requires saying **beforehand** which difference would count as relevant.

| # | Prediction with dual channel | Refuted if |
|---|---|---|
| 1 | `sequential` on **one** core **does not move** (< 5%) | it rises more than 20% |
| 2 | aggregate throughput of twelve cores **rises a lot** (> 40%) | it rises less than 10% |
| 3 | `dependent` latency changes little (< 5%) | it changes more than 10% |
| 4 | `custo-comunicacao` does not move (< 5%) | it changes more than 10% |

Number 4 is the negative control: core-to-core communication does not touch
DRAM, so if it moves, something changed that is not the channel, and the other
three lose their value.

### What each outcome obliges

**If 1 and 2 hold**, §4.2 becomes more precise and shorter: the ~21 GB/s
aggregate **is** a bandwidth ceiling, and the sentence *"one sequential core
saturates it alone"* is **wrong** — that core is limited by itself, not by
memory. The text then separates two things it currently merges.

**If 2 fails** — if the aggregate does not rise either —, the ceiling is not
the memory's, and that subsection's whole explanation has to be redone, not
corrected.

**If 1 fails**, EXPO and the channel move the same number in inconsistent
directions, and the first suspect becomes the instrument.

### What EXPO already decided, before the stick

The pre-registration was written for the second stick. EXPO answered **two of
the four predictions** before that, and it is worth recording that it went this
way — a declared prediction kept serving an experiment that was not the one
foreseen.

The campaign of 2026-09-20, five rounds on an idle machine, warm-up discarded,
against the published values:

```
  12 cores (aggregate)       30.92 -> 21.27 ns/access    -31.2%   RESPONDS
  1 core, sequential          0.200 -> 0.195 ns/access     -2.5%   does not
```

**Prediction 1 confirmed, prediction 2 confirmed.** Memory 25% faster improved
the aggregate by 45% in throughput and did nothing for the lone core. The two halves of the
§4.2 sentence come apart: the aggregate **is** bandwidth-limited; the lone
sequential core **is not** — it is limited by itself.

The sentence *"one sequential core saturates it alone"* is therefore **wrong**,
and the second stick need not decide it: it will serve as independent
confirmation, with a different intervention on the same quantity.

### And a confirmation §4.1 declared it did not have

[§4.1](README.en.md#why-the-difference-is-11-ns-and-not-three-trips-to-ram)
explains that the extra translation cost is served by the L3, and labels the
explanation *"consistent, not demonstrated"* — because demonstrating it would
require a hardware counter.

EXPO produced the evidence by another route. If the penalty is served by the
L3, faster memory **should not** make it cheaper:

```
  L3 dependent                   9.71 ->  9.73 ns    +0.2%
  translation DIFFERENCE        10.65 -> 10.94 ns    +2.7%
  RAM dependent                 98.73 -> 88.00 ns   -10.9%
```

DRAM improved 11%, the L3 stayed at 0.2%, and translation **followed the L3** at 2.7%. It
is not the hardware counter the section asks for, and it does not prove the
path taken; but it is a risky prediction that held, and the original experiment
could not produce it.

### The dividing line, as validation of the instrument set

The general record is worth keeping, because it says more about the instruments
than about the hardware. Of the **56** measurements `comparar-hardware.py`
confronts today:

| Band | How many | What is in it |
|---|---:|---|
| up to 1.5% | **24** | cache, atomics, local locks — nothing touching DRAM |
| 1.6% to 9.0% | 16 | mixed paths: part of the work in cache, part outside |
| 10.9% to 31.2% | **16** | DRAM and the inter-CCD fabric |

> **The middle band exists, and an earlier version of this section omitted it.**
> The text said "twelve did not move, ten moved", as if the split were clean. It
> was clean in the smaller set the tool covered then; with 56 comparisons there
> are sixteen measurements between 1.6% and 9.0%, and erasing them would make
> the argument prettier than the data allows.

What sustains the validation is not the absence of a middle, but **the extremes
landing where the mechanism predicts**. The in-core ALU loop, the paired SMT
ratio, and the `L1d` and `L3` dependent columns all came out at **0.0%** — none
of them touches main memory. The twelve-core aggregate came out at **31.2%**,
the largest of all, and it is the one that competes hardest for bandwidth.

An instrument that responds where it should and stays quiet where it should is
the only possible evidence that it measures what it claims to measure.

### The second stick's confound, and how it is handled

Adding the stick changes **two** things at once: capacity goes from 16 to 32 GB
and the channel goes from single to dual. Attributing the whole difference to
bandwidth would be exactly the error this section exists to avoid.

**What can be asserted today, on the record.** The largest working set across
the programs is **512 MB** — `REGIAO_BYTES` in `custo-traducao.c`, a constant in
the source that does not grow with installed RAM. During the 4800 collection,
available memory stayed between 7.0 and 7.5 GiB. A factor of fourteen.

`scripts/ambiente.sh` now records available alongside total, and each arm
carries samples taken during collection. Before that, the claim "capacity was
never binding" rested on my word.

**What this is, and what it is not.** It is a mechanism argument plus a recorded
fact: spare capacity has no route by which to change the latency of a 512 MB
dependent chain. **It is not a control** — a control would change capacity while
holding the channel fixed.

**The control exists, and carries its own cost.** Both sticks in the same
channel (A1+A2) would give 32 GB in single channel, isolating capacity. But DDR5
with two modules per channel usually forces a speed derating, which would
introduce a third variable — trading one confound for another.

**The design I propose instead** uses what already exists: a 2×2 factorial,
speed crossed with channel.

| | 4800 MT/s | 6000 MT/s |
|---|---|---|
| **16 GB, single channel** | collected | collected |
| **32 GB, dual channel** | to collect | to collect |

It does not separate capacity from channel — no feasible design here does. What
it delivers is better than it looks: **the speed effect measured in both channel
configurations**. If the same 4800-to-6000 change produces the same effect with
one stick and with two, the instrument is consistent, and the remaining
difference between rows is attributable to the capacity+channel pair — declared
as a pair, not as bandwidth.

### Outcome: the four predictions, measured

The second stick went in on 2026-09-23. The collection is
`2026-09-23-expo6000-canal-duplo`, same protocol and same machine state as the
baseline — `powersave`, C3 active, six rounds with the warm-up discarded. One
variable: the number of channels.

| # | Prediction | Declared limit | Measured | Outcome |
|---|---|---|---:|---|
| 1 | one core's `sequential` does not move | < 5% | −4.1% | **NOT TESTABLE** |
| 2 | twelve cores' aggregate throughput rises a lot | > 40% | **+68.0%** | **confirmed** |
| 3 | `dependent` latency changes little | < 5% | **−1.8%** | **confirmed** |
| 4 | `custo-comunicacao` does not move | < 5% | **largest deviation 4.2%** | **confirmed** |

```
  1 core, sequential          0.195 -> 0.187 ns/access    -4.1%   <- instrument
  12 cores, aggregate         21.27 -> 12.66 ns/access   -40.5%
                              564.2 -> 947.9 M accesses/s +68.0%
  RAM dependent               88.00 -> 86.38 ns           -1.8%
  1 core, custo-paralelismo    6.20 ->  5.85 ns/access    -5.6%   <- replacement
```

> **Prediction 1 could not fail, and therefore does not count.** The
> `efeito-cache` `sequential` column is limited by the loop that measures it,
> not by memory: the accumulator forms a loop-carried chain with a ceiling of
> about one element per cycle, and that ceiling is the same with the working
> set in L1d and with it in DRAM. A number that cannot move cannot refute a
> prediction that it does not move.
>
> The prediction was registered in good faith and the measured outcome is
> correct as arithmetic. What does not exist is the **evidential value**: the
> refutation criterion — "rises by more than 20%" — was unreachable by
> construction. §4.2 of module 01 carries the instrument's caveat, and an
> [L2 test](README.en.md#42-cache-and-locality) locks the trap.
>
> **The replacement is on the last line of the block.** `custo-paralelismo`
> measures a single core with the same instrument that measures the twelve, and
> there the number **can** move: it moved 14.5% when the frequency changed. That
> it moved only 5.6% with the channel is a result, not a ceiling. Prediction 1
> would be better served by that instrument, and that is how it is recorded for
> the next hardware configuration.

**Prediction 4 is what gives the other two their value.**
`custo-comunicacao` measures cache-line traffic between cores, which does not
touch DRAM: if the channel moved it, the intervention would have an effect
where it should not, and the others would lose their meaning. The program's
five measurements came out between 0.0% and 4.2%, with the ratio between SMT
sibling and distinct core standing still at **2.29 → 2.29**.

An instrument that responds where it should and stays quiet where it should is
the only possible evidence that it measures what it says it measures — and this
time that was declared beforehand, not observed afterwards.

> **And the negative control did not protect against prediction 1's defect.**
> It checks whether the **intervention** leaks where it should not. What brought
> prediction 1 down was something else: its **instrument** having a ceiling of
> its own, which no intervention reaches. They are failures of different
> families, and a well-built negative control passes green over the second.
>
> The question that would have caught the defect is not "did the intervention
> leak?", but **"what would this number do if the hypothesis were false?"**. For
> prediction 1 the answer was "the same", and that could have been answered
> before measuring — or after, by varying the cache level and observing that the
> value does not move. It is recorded as the question to ask in every future
> pre-registration.

#### What the outcome obliged us to change

The section predicted: *"if 1 and 2 are confirmed, §4.2 becomes more precise and
shorter"*. That is what happened. The phrase *"one sequential core saturates it
alone"* left module 01, and the subsection now publishes **both** interventions
side by side, because they measure the same quantity by independent paths:

| Intervention | 12 cores | 1 core | ratio |
|---|---:|---:|---:|
| 4800 → 6000 MT/s | −31.2% | −14.5% | 2.2× |
| 1 → 2 sticks | −40.5% | −5.6% | 7.2× |

The second intervention is the cleaner of the two, for a reason of mechanism:
**doubling the channels doubles bandwidth without touching latency**, whereas
changing the frequency moves both things at once. Confirming the same asymmetry
by both paths is stronger than confirming it by one.

#### The 2×2 factorial has three cells of four

The design proposed above crossed speed with channel. With this collection it
stands as:

| | 4800 MT/s | 6000 MT/s |
|---|---|---|
| **16 GB, single channel** | collected | collected |
| **32 GB, dual channel** | **missing** | collected |

The missing cell requires taking the BIOS back to 4800 with both sticks
installed. It decides none of the four predictions — all of them are already
resolved — but it answers a different question: **whether the effect of speed
is the same in both channel configurations**, which would test the instrument's
consistency across a hardware change. It is recorded as an available collection,
not as a pending conclusion.

#### The capacity+channel confound remains declared

Adding the stick changed capacity and channel together, and **that was not
resolved** — no viable design on this machine separates them without removing
the stick, an intervention whoever answers for the machine declined. It is a
recorded decision, not a technical blocker. What the outcome
adds is that prediction 3 constrains the space: if capacity were what moves the
aggregate, it would have to do so **without** altering the latency of a
512 MB dependent chain, which is what prediction 3 measured standing still at
−1.8%.

Spare capacity has no way to speed up a chain that already fit in the available
memory — free memory during the single-channel collection sat around 7 GiB,
fourteen times the working set. It is a mechanism argument plus a recorded fact,
and it continues **not to be a control**.

#### One NUMA node, and what that closes

With both sticks, `numactl --hardware` still reports **a single node**, and
`/sys/devices/system/node/` has only `node0`. This CPU presents all memory as a
single domain.

Any experiment that depends on **more than one NUMA node** — per-node pool
locality, remote access cost, per-node lcore placement — remains impossible on
this machine, and not for lack of sticks.
[§4.3 of module 01](README.en.md#43-numa-when-memory-stops-being-one-thing)
already declares that the NUMA numbers there come from the literature and that
measuring them requires two-socket hardware. This record closes a door the
hardware change appeared to open: **dual channel is a property of the memory
controller, not of the NUMA topology**, and the two are easily confused
precisely because both talk about "how many paths to memory".

### What is now recorded as a limitation

The machine measured **in single channel** everything published so far, and the
document did not say so — nor did `scripts/ambiente.sh`, which exists precisely
so the environment is not described in prose. Both fields landed together with
this section; when they need privilege, they **declare that they were not read**
instead of disappearing.

---

## 7. The collection condition: why the graphical session was excluded

This repository's measurement protocol specifies a dedicated machine with no
concurrent load, and the campaign scripts declare it in their headers — *"the
machine is exclusive to this purpose"*. The condition was treated as sufficient
until per-event tracing contradicted it.

### What the measurement showed

The `osnoise` tracer attributed the longest stalls on an idle CPU to the
function `amdgpu_device_delay_enable_gfx_off`, which re-enables power gating
for the integrated GPU's graphics block. Execution occurs in a per-CPU
workqueue and costs hundreds of microseconds. With the graphical session
suspended, the same CPU showed a maximum of 25 µs against 711 µs — and the
function disappeared from the trace. The full chain, with pre-registration and
refutation criterion, is in [§6.6.5 and §6.6.6 of the CPU isolation
module][iso].

The consequence for the protocol is direct: **closing the browser does not
suspend the graphical session**. The compositor, the display server and the GPU
driver remain active and produce, on their own, events of up to 800 µs at
intervals of a few seconds. The declaration of exclusivity described a
condition that was not the condition measured.

### What this requires, and what it does not

The effect on already published results is bounded by the statistical design.
The project reports **median with dispersion**, not mean; a rare 800 µs event
shifts the median of a collection of billions of samples very little. The
direct measurement of that shift, on the most sensitive metric available — the
median of the largest stall, composed entirely of tail — was from 24.8 µs to
21.5 µs, or 13%. Metrics from the body of the distribution shift less.

Those 13% hold for a collection running with an **idle graphical session**, and
do not generalise. Among the nine collections of the isolation topic, eight sit
between 21.5 and 30.9 µs and one sits at 515.5 µs — all on the same machine,
both ends with an active graphical session. The session's contribution is not
an additive constant: it depends on how much it worked during the measurement,
because power-gating re-enablement is scheduled by graphics activity.

The specification now distinguishes two regimes:

| Quantity of interest | Required condition |
|---|---|
| median, mean, ratio between medians | dedicated machine, graphical session allowed |
| dispersion, jitter, p99, p99.9, maximum | **text mode**, no display manager |

Text mode is obtained through a one-shot GRUB entry with
`systemd.unit=multi-user.target`. The script
[`ferramental/qualidade/campanha-modo-texto.sh`][cmt] refuses to run while
any graphical process is alive, so that the condition is verified by the
program rather than by the operator's memory.

### The limit of this correction

The 198 labels confronted by `comparar-hardware.py` were **not re-run** in
text mode. By the median argument a small shift is expected, but this is an
expectation, not a measurement. The finding also comes from one machine, with
an AMD integrated GPU: platforms with a discrete GPU or a different driver are
not covered.

[iso]: ../../trilha/03-performance/03-isolamento-cpu/README.en.md#665-identifying-the-source-by-per-event-tracing
[cmt]: ../../ferramental/qualidade/campanha-modo-texto.sh

---

## Navigation

- Back to: [Fundamentals](README.en.md)
- The program: [`medicoes/custo-syscall.c`](medicoes/custo-syscall.c)
