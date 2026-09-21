# The DPDK runtime — the EAL as an execution system

*Leia em [português](README.md).*

> **Level 3** of the [study plan](../plano-estudo-dpdk.en.md) ·
> Prerequisite: [Fundamentals](../01-fundamentos/README.en.md) and the practical topic
> [01 — EAL initialisation](../../trilha/01-fundamentos/01-eal-hello/)

Topic 01 of the track shows a minimal program bringing the [EAL][cEAL] up and
shutting it down. This module deals with what comes after that first run: how the
runtime behaves as a **system**, what it costs, what it leaves on the host, and which
decisions it imposes on anyone who is going to put a data-plane process into
production and keep it there.

The guiding example is the same as the fundamentals': a ***market data* server**
receiving an exchange's *feed* for a heavily traded instrument. It was chosen in
[§6.2 of the fundamentals](../01-fundamentos/README.en.md#62-the-bus-has-a-budget-too)
as the canonical ultra-low-latency case, and it serves well here because it forces
all of this level's questions at once: how long the process takes to be ready, where
memory is reserved, how a strategy reads the book without copying data, and what
happens when one of the processes dies mid-session.

## By the end of this module you will be able to

1. **explain what `rte_eal_init()` decides** before the first line of your logic
   executes, and measure how much that costs;
2. **diagnose why the EAL does not come up**, distinguishing a missing hugepage from
   an inaccessible one — which require different fixes;
3. **choose between `--in-memory`, `--no-huge` and hugetlbfs** knowing what each one
   switches off;
4. **design a system using primary and secondary processes**, and say what crosses the
   boundary and what does not;
5. **isolate instances on the same machine** with `--file-prefix`, and explain the
   rule about disjoint lcore lists;
6. **map lcores to CPUs explicitly**, and not confuse an lcore identifier with a CPU
   number;
7. **justify why a DPDK process is a long-running service**, from the measured cost of
   initialisation.

## Contents

1. [What this module adds to the existing sources](#1-what-this-module-adds-to-the-existing-sources)
2. [The cost of existing: how long the EAL takes to be born](#2-the-cost-of-existing-how-long-the-eal-takes-to-be-born)
3. [The EAL's memory model](#3-the-eals-memory-model)
4. [Primary and secondary processes](#4-primary-and-secondary-processes)
5. [lcores: identity, mapping and states](#5-lcores-identity-mapping-and-states)
6. [IOVA: the address the device sees](#6-iova-the-address-the-device-sees)
7. [Shutdown: what is left behind](#7-shutdown-what-is-left-behind)
8. [Synthesis: the feed handler's runtime](#8-synthesis-the-feed-handlers-runtime)
9. [Validation: reproduce it on your machine](#9-validation-reproduce-it-on-your-machine)
10. [When it goes wrong](#10-when-it-goes-wrong)
11. [Limitations of this document](#11-limitations-of-this-document)
12. [External references](#12-external-references)
13. [Navigation](#13-navigation)

---

## 1. What this module adds to the existing sources

There is no shortage of material on the EAL. There is the official documentation,
there is a strong tradition of *source-code analysis* (源码分析) in Chinese, and
there are dozens of tutorials in English. Before writing one more, it is worth saying
where the existing ones are better than this document — and where they have become outdated.

**Where the existing sources are better.** The official documentation is the authority
and should be the first stop; nothing here replaces it. And the Chinese tradition of
source-code analysis covers ground this module does not attempt to cover:
`rte_eal_init()`'s internal sequence, function by function, with the names of the
internal structures. For anyone who needs to debug the EAL, that material is more
useful than anything written here.

**Where they have aged.** DPDK changes its API frequently, and technical material does
not correct itself. The points below were **verified on this machine**, against the
installed DPDK 25.11, and each appears in its old form in material that is still
widely cited:

| What changed | The old form, still common | The current form (25.11) | The consequence of copying the old one |
|---|---|---|---|
| lcore vocabulary | *master* / *slave*, 主核 / 从核 | *main* / *worker* | `--master-lcore` is rejected: `ARGPARSE: unknown argument --master-lcore!`, exit 234 |
| lcore iterator | `RTE_LCORE_FOREACH_SLAVE` | `RTE_LCORE_FOREACH_WORKER` | does not compile |
| Getting the main lcore | `rte_get_master_lcore()` | [`rte_get_main_lcore()`][apimainlcore] | does not compile |
| lcore states | `WAIT`, `RUNNING`, `FINISHED` | `WAIT`, `RUNNING` | code expecting `FINISHED` never sees it |
| Memory per node | [`--socket-mem`][optlinux] | [`--numa-mem`][optlinux] (`--socket-mem` became an alias) | still works, but the current documentation is under the other name |

The first three lines come from the renaming done in **DPDK 20.11**, which the release
notes record like this: *"Replaced the function `rte_get_master_lcore()` with
`rte_get_main_lcore()`. The old function is deprecated"*, and
*"`RTE_LCORE_FOREACH_SLAVE` is replaced with `RTE_LCORE_FOREACH_WORKER`"*
([20.11 release notes][rel2011]). The fourth is verifiable in the installed header:
`enum rte_lcore_state_t` had three values in the [19.11 API][api1911] and has **two**
in 25.11.

**Three subjects almost no source covers.** Not through carelessness: they require
measuring or testing, and do not appear from reading the source.

1. **How much `rte_eal_init()` costs.** It is a number that decides architecture, and
   it is not found published.
   [§2](#2-the-cost-of-existing-how-long-the-eal-takes-to-be-born) measures it, and
   shows that 83% of it on this machine is not work — it is a wait.
2. **Which EAL options are mutually incompatible.** Tutorials present
   [`--in-memory`][optmem] and [`--no-huge`][optdebug] as convenient shortcuts for
   running without privilege. Both **disable secondary process support**, and most
   material does not say so.
   [§4.5](#45-what-switches-the-multiprocess-model-off-without-warning) demonstrates
   both failures.
3. **Where the EAL writes its runtime files.** Practically every tutorial says
   `/var/run/dpdk`. For an ordinary user the path is different, and
   [§3.2](#32-what-the-eal-leaves-on-the-host) shows which.

There is also a naming trap that survives in any version:
[`rte_lcore_to_cpu_id()`][apitocpuid] **does not return the CPU number**. It is in
[§5.1](#51-an-lcore-is-not-a-cpu).

> This document is a critical reading, not a correction of third parties. It names no
> authors or articles: the goal is to give the reader the criterion for evaluating the
> material they find, starting with a simple question — *which version of DPDK was
> this written for?*

---

## 2. The cost of existing: how long the EAL takes to be born

Topic 01 describes what [`rte_eal_init()`][apiealinit] does. This module's question is
another: **how long that takes**, and what that time implies.

The program [`medicoes/custo-init.c`](medicoes/custo-init.c) measures it. The
methodology is imposed by the object of study itself: `rte_eal_init()` is not
reentrant — the second call in the same process returns `EALREADY` — so **each sample
requires a process**. The program does a `fork()` per sample; the child initialises,
times it and returns the result through a *pipe*; the parent only aggregates.

```
== Cost of initialising and shutting down the EAL ==

  configuration measured: -l 0 --in-memory
  samples: 11 (one per process; rte_eal_init is not reentrant)

  warning: "rte_eal_cleanup()" has disp 6.0% with 11 samples -- in that band the seal
           does not decide. Raise it to 20+ before explaining the result.
  values in MILLISECONDS

  measurement                           median  p25-p75 (IQR)   range min-max      disp    CV
  ---------------------------------- ---------  --------------- ----------------- ----- -----
  rte_eal_init()                         118.8  118.3-121.4     117.8-122.1         2.6%   1.4%  
  rte_eal_cleanup()                      0.094  0.090-0.096     0.055-0.133         6.0%  20.1% ~

  Reading:
    At 10 GbE with 64 B frames one packet arrives every 67.2 ns.
    The 119 ms initialisation window is worth 2 million packets
```

Bringing the EAL up costs **123 ms**; shutting it down costs **0.12 ms** — three
orders of magnitude less. The asymmetry is the first relevant fact: being born is
expensive, dying is cheap.

**And "dying" costs different things depending on what was reserved.** The same
measurement, with the memory mode of the EAL as the only difference:

```
  configuration       rte_eal_init()   rte_eal_cleanup()   ratio
  -----------------   --------------   -----------------   -------
  -l 0 --in-memory      118.8 ms         0.094 ms  ~  6%    1264x
  -l 0 --no-huge        121.9 ms         0.577 ms  ~  5%     211x
```

Initialisation does not move — 122.4 against 122.5 ms. Shutdown changes by a factor
of **5.5**, and with it the ratio goes from three orders of magnitude to two. That
makes sense: shutting down gives back what was mapped, and `--no-huge` maps it
differently. **The shutdown number does not exist without the configuration next to
it.**

> **Retracting a number requires reproducing its configuration.** This section
> once declared that the 0.08 ms of `--in-memory` "did not reproduce", having
> measured `--no-huge` — a different configuration, and the table above shows
> the difference between them is 5.5×. Measuring something else and not finding
> the same value is not a refutation; it is a different measurement.
> <!-- retratado: 0.082 0,082 0.30 0,30 195 -->

### 2.1 Where the 123 ms come from

The first natural hypothesis is that the cost is in memory or in the device scan. Both
are wrong:

| Configuration | `rte_eal_init()` median | range |
|---|---:|---|
| `-l 0 --in-memory` | 122.4 ms | 121.6–123.7 |
| `-l 0 --in-memory --no-pci` | 121.1 ms | 120.0–122.5 |
| `-l 0 --no-huge --in-memory --no-pci` | 120.8 ms | 120.2–121.8 |
| `-l 0-3 --in-memory` | 123.5 ms | 122.8–125.7 |

Turning off the PCI scan changes nothing. Swapping hugepages for ordinary memory
changes nothing. Using four lcores instead of one changes nothing. The cost is a
**fixed floor**, and a fixed floor with that dispersion does not look like work: it
looks like a wait.

> **This table measures `-l 0-3` for real**, and the median of
> `-l 0 --in-memory` (122.4, range 121.6–123.7) **contains** the 123.1 of the
> section's opening table: the two collections agree.
> <!-- retratado: 122,3 120,7 -->

**Working or waiting?** The distinction is the problem, and the previous measurement
cannot make it: 123 ms of wall clock are identical in both cases. Choosing the right
instrument here is half the lesson.

A CPU profiler — `perf`, for instance — is the wrong choice, and for a reason worth
understanding: it **samples the CPU**, and a sleeping process consumes no CPU. It
would show an absence of work during the 100 ms and leave the elapsed time
unexplained. A profiler sees work; what is being looked for here is a wait.

`strace` answers on exactly that axis. It intercepts the boundary with the kernel —
the same one from
[§2 of the fundamentals](../01-fundamentos/README.en.md#2-the-user-space--kernel-space-boundary)
— and the `-T` option reports how long each call was blocked. Since the hypothesis was
already formed, the filter `-e trace=clock_nanosleep` reduces thousands of calls to the
only one that matters:

```console
$ strace -T -e trace=clock_nanosleep ./hello_dpdk -l 0 --in-memory --no-huge --no-pci
...
clock_nanosleep(CLOCK_REALTIME, 0, {tv_sec=0, tv_nsec=100000000}, NULL) = 0 <0.100083>
```

A single wait of **exactly 100 ms**. It is the calibration of the TSC's frequency, and
it is in the EAL's code — `lib/eal/linux/eal_timer.c`, the function `get_tsc_freq()`,
which declares `struct timespec sleeptime = {.tv_nsec = NS_PER_SEC / 10 }`, with the
comment `/* 1/10 second */` ([source][fonteeal]). DPDK measures the TSC against the
system clock for a tenth of a second to discover its frequency — the same one
[`rte_get_tsc_hz()`][apitschz] returns afterwards, and which all code converting
cycles into nanoseconds uses.

**That is: 100 of the 123 ms, 81% of the cost of initialising the EAL on this machine,
is not work — it is a clock measurement.**

> **What `strace` did not settle.** It showed *that* there is a 100 ms wait and *where*
> it occurs; **why** it exists came from reading the EAL's code, and the condition
> under which it is skipped, from
> [§2.2](#22-why-that-wait-exists-and-when-it-does-not-happen). And it produced none of
> the numbers published here: instrumenting every system call has its own cost, which
> would distort the measurement. The 123 ms come from
> [`custo-init.c`](medicoes/custo-init.c); `strace` came afterwards, to explain them.
> Measuring and diagnosing are distinct steps, with distinct tools.

### 2.2 Why that wait exists, and when it does not happen

The calibration is conditional. The same file has:

```c
if (arch_hz && is_tsc_known_freq())
    return arch_hz;
```

`is_tsc_known_freq()` looks for the `tsc_known_freq` flag in `/proc/cpuinfo`. When the
kernel already knows the TSC's frequency — because it read it from the hardware, and
not by estimation — DPDK trusts it and **skips the 100 ms**. On this machine the flag
does not exist:

```console
$ grep -o 'constant_tsc\|nonstop_tsc\|tsc_known_freq' /proc/cpuinfo | sort -u
constant_tsc
nonstop_tsc
```

There is `constant_tsc` and `nonstop_tsc` — the TSC is dependable — but no
`tsc_known_freq`. That is why the calibration runs.

The practical consequence is that **the number 123 ms is not a property of DPDK**: it
is a property of this combination of CPU and kernel. On a machine that exposes
`tsc_known_freq`, the same `rte_eal_init()` would cost something close to 23 ms.
Measuring on your machine is part of the exercise, and the program accepts the EAL's
options directly for that.

### 2.3 What this decides in the architecture

A startup cost of tens to hundreds of milliseconds rules out an entire class of
designs:

- **There is no DPDK process per request, per connection or per task.** The model is a
  long-running service; anything that brings the runtime up and down frequently pays
  the cost every time.
- **Restarting in production is an event, not a routine.** Back to the example:
  restarting the *feed handler* during the trading session means 123 ms without
  receiving, plus the time to re-subscribe to the *feed* and rebuild the book.
  [§7 of the fundamentals](../01-fundamentos/README.en.md#7-metrics-the-vocabulary-for-not-fooling-yourself)
  treats latency by percentiles precisely because rare, expensive events are what
  define observed behaviour — and 123 ms is an extremely expensive event in a system
  whose requirement is measured in microseconds.
- **The separation between what restarts and what does not becomes a design
  decision.** It is exactly the argument for the multiprocess model of
  [§4](#4-primary-and-secondary-processes): keep standing the process that cannot fall,
  and leave restartable what changes often.

> **An honest caveat.** 123 ms measures `rte_eal_init()` in isolation. A real
> application will still configure ports, allocate mempools and queues, and start the
> workers — work this number does not include. The total time to the first processed
> packet is larger, not smaller.

---

## 3. The EAL's memory model

Topic 01 says the EAL "reserves memory". This module needs to be more specific,
because secondary processes, NUMA alignment and the host's operational behaviour all
depend on that specificity.

### 3.1 Memzone: memory with a name

`malloc()` returns a pointer. A pointer is valid **inside one process**, and vanishes
when it ends. That is enough for almost all software, and it is not enough here.

The EAL offers the **memzone**: a contiguous region of memory, reserved in the pages
the EAL administers, identified by a **name**. You reserve it with
[`rte_memzone_reserve()`][apimzreserve] and recover it with
[`rte_memzone_lookup()`][apimzlookup]:

```c
/* in the process that creates it */
const struct rte_memzone *mz =
    rte_memzone_reserve("academia_feed_marketdata", tamanho, rte_socket_id(), 0);

/* in ANOTHER process, which only attaches */
const struct rte_memzone *mz = rte_memzone_lookup("academia_feed_marketdata");
```

Three properties matter:

**The name is the contract.** It is the only thing the two processes need to agree on
beforehand. There is no socket, no port, no file path in the application — there is a
string. Every high-level DPDK structure that is shareable between processes (mempool,
ring, hash table) is built on that same naming mechanism.

**The NUMA node is chosen at reservation, not discovered afterwards.** The third
argument is the *socket id*. Passing [`rte_socket_id()`][apisocketid] reserves on the
current lcore's node; in a *market data* server the correct value is the **NIC's**
node, so that card, memory and core sit on the same node — the requirement that closes
the configuration table in
[§6.2 of the fundamentals](../01-fundamentos/README.en.md#62-the-bus-has-a-budget-too).
The alternative `SOCKET_ID_ANY` lets the EAL choose, which is acceptable in a lab and
is not in production.

**A memzone knows its physical address.** The returned structure carries `addr` (the
virtual address) and `iova` (the address a device would use for DMA). That second
column is the subject of [§6](#6-iova-the-address-the-device-sees).

### 3.2 What the EAL leaves on the host

A memzone needs to outlive the process that created it so that another process can
find it. The EAL achieves that by writing files, and it is useful to know where:

```console
$ ./estado-lcore -l 0 --no-huge --file-prefix=demo_estrutura &
$ find /run/user/1000/dpdk/demo_estrutura -type f
  $XDG_RUNTIME_DIR/dpdk/demo_estrutura/fbarray_nohugemem
  $XDG_RUNTIME_DIR/dpdk/demo_estrutura/fbarray_memzone
  $XDG_RUNTIME_DIR/dpdk/demo_estrutura/config
```

Two details that usually surprise:

**The path is not `/var/run/dpdk`.** Almost all material says it is, and for `root` it
is. For an ordinary user, the EAL uses the session's runtime directory —
`$XDG_RUNTIME_DIR/dpdk/<prefixo>/`, which on this machine resolves to
`/run/user/1000/dpdk/<prefixo>/`. Anyone looking in the wrong place concludes the EAL
wrote nothing.

**The files remain after the process exits.** Listing the directory after shutdown,
`config`, `fbarray_memzone` and `fbarray_nohugemem` are still there. That is
intentional — a secondary may come up later — but it means repeated runs accumulate
runtime directories, and that a process killed abruptly leaves state behind. That is
the subject of [§7](#7-shutdown-what-is-left-behind).

The `mp_socket` that appears in the EAL's log (`EAL: Multi-process socket
/run/user/1000/dpdk/academia/mp_socket`) lives in the same directory: it is the channel
through which primary and secondaries exchange control messages — not data.

### 3.3 The three degrees of "leave no trace"

There are three EAL options that reduce what is left on the host, and they are
frequently confused because their descriptions look alike. They are not equivalent:

| Option | What it removes | Is a secondary process still possible? |
|---|---|---|
| [`--huge-unlink`][optmem] | the hugepage files, on exit | **yes** (in the `existing`/`never` variants) |
| [`--no-shconf`][optmem] | the shared configuration files | **no** |
| `--in-memory` | everything: nothing is written to a filesystem | **no** |

`--in-memory` is the strongest, and the EAL's own help declares the side effect without
mincing words:

```
--in-memory   DPDK should not create shared mmap files in filesystem
              (disables secondary process support)
```

It is the option topic 01 uses, and which much of the material recommends as a
shortcut for "running without mess". The shortcut is legitimate — and it switches off
half of this module.

### 3.4 Reserving memory per node

By default the EAL reserves whatever it finds available. Two options give control:

- **`-m <MB>`** — the total to reserve, without saying from where.
- **`--numa-mem <lista>`** — how much to reserve on **each node**, in node order:
  `--numa-mem 2048,2048` asks for 2 GiB on each of two nodes.

On a single-node machine, like this project's reference, the two do practically the
same thing. On a multi-socket machine, `--numa-mem` is the option that prevents the
scenario described in
[§4.3 of the fundamentals](../01-fundamentos/README.en.md#43-numa-when-memory-stops-being-one-thing):
the process reserving everything on the wrong node and paying for remote access on
every packet.

> **Careful with the naming.** In DPDK 25.11 the canonical name is `--numa-mem`;
> `--socket-mem` still works, but the help describes it as `Alias for --numa-mem`.
> Material written before that change uses only the old name — which is not wrong, it
> is simply no longer the main name.

---

## 4. Primary and secondary processes

This is the module's central subject, and what no other topic in the project covers. It
is also where the *market data* example stops being an illustration and becomes the
design's justification.

### 4.1 Why two processes

Consider the trading desk. On one side, the **feed handler**: it receives the
exchange's multicast, normalises each update and maintains the book. On the other, the
**strategies**: they read the book and decide. A naive design puts everything in a
single process, with threads. Three forces push the other way:

**Failure isolation.** A strategy is code that changes every week. An invalid pointer
in it brings down the entire process — and with it the *feed handler*, which loses its
subscription and its book. With the processes separated, the strategy falls alone.

**Different life cycles.** The strategy is recompiled and restarted several times a
day; the *feed handler* should come up once.
[§2](#2-the-cost-of-existing-how-long-the-eal-takes-to-be-born) gives the number that
makes that concrete: each restart costs 123 ms of EAL. Restarting only what needs
restarting stops being a preference and becomes a requirement.

**Organisational boundaries.** Different teams, different permissions, sometimes
different languages. The process is the unit the operating system knows how to isolate.

The price is that communication stops being a shared variable and comes to require
explicit shared memory. That is exactly what the EAL offers — and without copying,
which is what distinguishes it from a *pipe* or a local socket.

### 4.2 How the secondary finds the memory

The EAL classifies each process into one of two roles, chosen by
[`--proc-type`][optmulti]:

| Role | Can create shared memory | Can attach to existing memory |
|---|---|---|
| **primary** (`--proc-type=primary`, the default) | yes | — |
| **secondary** (`--proc-type=secondary`) | **no** | yes |

The official documentation summarises: *"secondary processes, which cannot initialize
shared memory, but can attach to pre-initialized shared memory and create objects in
it"* ([multi-process guide][cmultiproc]).

The mechanism is the one described in [§3.2](#32-what-the-eal-leaves-on-the-host): the
primary records in mapped files which hugepages it uses and at which virtual addresses
it mapped them; the secondary reads those files and **recreates the same mapping**. The
result is the property that makes the whole model work:

> The same region appears at the **same virtual address** in both processes.

That is what allows reading a shared structure as if it were local, without translating
offsets. It is also what makes the secondary's start sensitive to ASLR — see
[§4.4](#44-what-does-not-cross-the-boundary).

This module's example is two independent binaries:

- [`medicoes/feed-primario.c`](medicoes/feed-primario.c) — reserves the memzone,
  publishes ticks into a ring and waits for them to be consumed;
- [`medicoes/feed-secundario.c`](medicoes/feed-secundario.c) — finds the memzone by
  name, consumes the ticks, rebuilds the book and measures the crossing's latency.

The contract between them is a header, [`medicoes/feed.h`](medicoes/feed.h), and what
it decides is worth reading:

```c
struct feed_compartilhado {
    /* --- written ONLY by the producer (primary) --- */
    _Alignas(FEED_LINHA) _Atomic uint64_t publicados;

    /* --- written ONLY by the consumer (secondary) --- */
    _Alignas(FEED_LINHA) _Atomic uint64_t consumidos;
    ...
};
```

The `_Alignas(64)` separating `publicados` from `consumidos` is not decorative care. It
is the direct fix for the problem measured in
[§4.2.1 of the fundamentals](../01-fundamentos/README.en.md#421-false-sharing-the-most-common-mistake-of-data-plane-programmers),
where two variables in the same cache line took an operation from 8 ns to 53 ns. Here
the error would be worse: the contended line would cross the process boundary, and the
symptom would appear as "DPDK multiprocess is slow", with no clue about the real
reason.

The other detail of the contract is the absence of pointers. `struct tick` holds only
fixed-size integers, and the ring is indexed by position, never by address. Even though
the EAL promises the same virtual address on both sides, depending on that in the data
structure trades a strong guarantee (an index) for a fragile one.

### 4.3 `--file-prefix`: isolation between instances

Nothing prevents the same machine from running two independent DPDK systems — the
production instance and the previous day's replay, for example. Without separation, the
two would contend for the same runtime files and the same hugepages.

[`--file-prefix`][optlinux] is that separation. It names the set of runtime files, and
therefore defines **the group**: processes with the same prefix see each other;
processes with different prefixes are invisible to one another. The official
documentation describes the option as the one that allows *"processes that do not want
to co-operate to have different memory regions"*, and is explicit about the
corresponding rule: *"secondary processes must use the same `--file-prefix` parameter
as the primary process whose shared memory they are connecting to"*
([multi-process guide][cmultiproc]).

Translated into the example:

```bash
# production instance
./feed-primario   -l 0 --file-prefix=producao  ...
./feed-secundario -l 1 --file-prefix=producao  --proc-type=secondary

# replay instance, on the SAME machine, without interfering
./feed-primario   -l 2 --file-prefix=replay    ...
./feed-secundario -l 3 --file-prefix=replay    --proc-type=secondary
```

There is a second rule, easy to violate and hard to diagnose: processes that share
memory need **disjoint lcore lists**. The documentation leaves no margin — *"All DPDK
processes running as a single application and using shared memory must have distinct
corelist arguments"*. Note that the example above respects that: `-l 0` and `-l 1` for
production, `-l 2` and `-l 3` for the replay.

### 4.4 What does not cross the boundary

The model shares memory, not the process. Some things stay outside, and the official
guide's limitations section lists them:

- **Interrupts only work in the primary.** The secondary does not receive the device's
  interrupt events.
- **Function pointers between different binaries are not supported.** Storing a
  `void (*)(void)` in a shared structure and calling it from the other side is
  undefined behaviour: the two binaries are compiled separately and do not have the
  same map of code addresses.
- **The DPDK version must be the same** in both processes, and the device options
  ([`--allow`][optdev] / [`--block`][optdev]) must match when the secondary accesses
  physical devices.
- **ASLR gets in the way.** Since the secondary needs to recreate exactly the same
  mappings, address space randomisation makes its start, in the documentation's own
  words, *"generally unreliable"* — and the guide is honest about the remedy: disabling
  ASLR *"may help getting more consistent mappings, but not necessarily more
  reliable"*.

That last point deserves a calm reading, because it is the main argument against using
the multiprocess model where it is not necessary. It is not a general-purpose IPC
mechanism: it is an optimisation with environmental requirements.

### 4.5 What switches the multiprocess model off without warning

Here is this module's most useful operational point, and the least documented.

The two options tutorials recommend for "running without privilege" — `--in-memory` and
`--no-huge` — are incompatible with a secondary process. The first warns; the second
does not.

**With `--in-memory`** the EAL's help declares the effect, as seen in
[§3.3](#33-the-three-degrees-of-leave-no-trace). There is no file to map, so there is
no way for a second process to attach.

**With `--no-huge` there is no warning at all.** The primary comes up normally, creates
the memzone, prints everything one expects. The secondary fails:

```console
$ ./probe -l 0 --no-huge --file-prefix=academia --no-pci &      # primary
PROBE: init ok, consumed 5 args, proc_type=PRIMARY
PROBE: memzone created at 0x1040f2f80 (iova=0x1040f2f80), sleeping 8s

$ ./probe -l 1 --no-huge --file-prefix=academia --no-pci --proc-type=secondary
EAL: Cannot init memory
PROBE: init failed: Cannot allocate memory
```

The underlying reason is the same: `--no-huge` makes the EAL use ordinary anonymous
memory, which is not file-backed and therefore not mappable by another process. The
message `Cannot init memory` never mentions `--no-huge`.

That leads to a triangle of trade-offs worth memorising:

| Mode | Real hugepages | Secondary process | Requires privilege |
|---|---|---|---|
| `--in-memory` | **yes** (via `memfd`) | no | **no** |
| `--no-huge` | no | no | **no** |
| hugetlbfs + `--file-prefix` | **yes** | **yes** | write access to the hugetlbfs |

The first row is surprising and verifiable: with `--in-memory`, the EAL obtains
hugepages without needing write access to `/dev/hugepages`, using `memfd_create` with
`MFD_HUGETLB`. You can observe the effect in the kernel's counter while the process
runs:

```console
$ grep HugePages_Free /proc/meminfo     # antes
HugePages_Free:     1024
$ grep HugePages_Free /proc/meminfo     # durante, com --in-memory
HugePages_Free:     1023
$ grep HugePages_Free /proc/meminfo     # after exiting
HugePages_Free:     1024
```

One 2 MB hugepage is taken from the pool and returned on shutdown. That is why
`--in-memory` is a good default for study: it gives real memory without requiring
privilege. What it does not give is the multiprocess model — and that is the trade.

For the third row's exercises, the project ships
[`scripts/preparar-hugepages.sh`](../../scripts/preparar-hugepages.sh), which mounts a
dedicated `hugetlbfs` with the correct owner instead of running everything as `root`:

```bash
sudo mount -t hugetlbfs -o pagesize=2M,uid=$(id -u) nodev /mnt/huge-academia
```

The choice is deliberate. Running a data-plane process as `root` because a directory
has mode `0755` is solving a permission problem by creating a security one.

### 4.6 How much crossing the boundary costs

With the requirement satisfied, the example runs and the remaining question is the only
one that matters to anyone adopting the model: **how much does it cost for a piece of
data to leave one process and arrive at the other?**

The producer stamps each tick with `rte_rdtsc()` — the direct read of the cycle counter,
whose portable form in the API is [`rte_get_tsc_cycles()`][apitsccycles] — immediately
before publishing it; the consumer reads the stamp and compares it with its own clock.
Two hundred thousand ticks, producer on lcore 0 and consumer on lcore 1:

```
  --- cross-process traversal, per tick (nanoseconds) ---

  measurement                      minimum    median       p75       p99  samples
  ------------------------------ --------- --------- --------- ---------  -------
  publication -> observation         10.02     20.04     30.06    110.21   200000

    instrument resolution: 11.9 ns (one consumer poll).
    degenerate samples: 0 of 200000 (TSC aligned across the two cores)
    The values above are an UPPER BOUND: between two polls the
    consumer is blind, so the real traversal fits inside the
    last step. Differences smaller than 11.9 ns are not measurable here.
```

**Ten nanoseconds in the best case, one hundred and ten at this run's p99.** For
scale: the budget of a 64 B packet on 10 GbE is 67.2 ns
([§1 of the fundamentals](../01-fundamentos/README.en.md#1-the-budget-how-much-time-exists-per-packet)).
The minimum consumes 15% of that budget; this run's p99 consumes **1.6 whole
budgets**.

> **And the p99 is the least stable number in the table.** Across the six archived
> repetitions it is 50.1 / 110.2 / 60.1 / 59.9 / 60.1 / 60.1 ns — the run published
> above is the highest of the six. The minimum and the median barely move (10.0 and
> 20.0 to 30.1 ns); the tail varies by a factor of 2.2. This is not a flaw in the
> collection: it is the property that makes the tail expensive to size for, and the
> reason this project publishes percentiles rather than means.

Expensive enough not to be done per packet without thinking, cheap enough to make
the separation between *feed handler* and strategy viable, which is what you get in
return — provided the sizing uses the tail, not the minimum.

Three methodological observations, and the third is the one that prevents a wrong
conclusion:

**No copy happens.** The tick is written once, into shared memory, and read from there.
What the 10 ns measure is the cache line migrating from one core to the other — not a
kernel crossing, not a `memcpy`. A `pipe` or a local socket in the same scenario would
cost two copies and two privilege-boundary crossings.

**The two clocks needed to be aligned, and the program checks.** Producer and consumer
run on different cores and compare TSC stamps. If the counters were skewed, the
subtraction would produce impossible values. The program counts those cases and
publishes the count: **0 of 200 000**.

**All the values are multiples of ~10 ns, and that is no coincidence.** The consumer
discovers a new tick by *polling*; between two polls it is blind. That ruler's step is
the cost of one iteration of the wait loop — which the program measures and publishes:
11.9 ns, dominated by [`rte_pause()`][apipause], which on this CPU costs about 55
cycles. That is, the table says "the tick was seen at the 1st, 2nd, 3rd or 4th poll
after being published", and the values are an **upper bound** on the real crossing.

> This is the same phenomenon as
> [§5.2 of the fundamentals](../01-fundamentos/README.en.md#52-polling-the-question-the-data-plane-answers-differently),
> seen from the other side. There, polling appears as the choice that trades CPU for
> deterministic latency. Here it appears as the **measuring instrument**: a consumer
> that polls cannot resolve differences smaller than its own polling period. Publishing
> the resolution alongside the result is what separates a measurement from a decorative
> number.

---

## 5. lcores: identity, mapping and states

Topic 01 defines an lcore (*logical core*) as a thread created by the EAL and pinned to
a logical CPU. This module deals with the three confusions that definition does not
resolve on its own.

### 5.1 An lcore is not a CPU

DPDK's lcore identifier and the system's CPU number are different things that coincide
by default. With `-l 0-3`, lcore 2 runs on CPU 2 — and it is precisely that coincidence
that hides the distinction until the day it matters.

The program [`medicoes/estado-lcore.c`](medicoes/estado-lcore.c) shows the two columns
side by side. With `-l 0-3`:

```
  lcore    real CPU(s)    role         index in node  NUMA no 
  -----    ------------   -----        ------------   ------- 
  0        0              main         0              0       
  1        1              worker       1              0       
  2        2              worker       2              0       
  3        3              worker       3              0       
```

With `--lcores '0@6,1@7,2@18'`, the same machine:

```
  lcore    real CPU(s)    role         index in node  NUMA no 
  -----    ------------   -----        ------------   ------- 
  0        6              main         0              0       
  1        7              worker       1              0       
  2        18             worker       2              0       
```

Lcore 0 now executes on CPU 6. And note the fourth column: it did **not** change.

That fourth column comes from [`rte_lcore_to_cpu_id()`][apitocpuid], and the function's
name misleads. The API's own documentation says what it returns: *"Return the id of the
lcore on a socket starting from zero"* — an **index relative to the NUMA node**, not
the CPU number. Anyone using that value to pin a thread, choose where to steer an IRQ or
decide affinity ends up with the work on the wrong core, and the only symptom is
performance.

The function that returns the real CPU is [`rte_lcore_cpuset()`][apicpuset], which
delivers the set of CPUs the lcore is pinned to — the table's third column.

The syntax of [`--lcores`][optlcore] matters on a machine with relevant topology. The
one in
[§4.3 of the fundamentals](../01-fundamentos/README.en.md#43-numa-when-memory-stops-being-one-thing)
has two CCDs, and communication between them cost 82 to 99 ns against 20 to
22 ns within the same CCD, across the five archived repetitions.5 ns within
the same CCD. With [`-l`][optlcore], lcores fall wherever the numbers dictate; with
`--lcores`, the mapping is chosen — and that is how you guarantee that the producer and
consumer of the same ring stay in the same cache domain.


#### What an lcore is, on the inside

The two tables show that the identifier and the CPU are different things. They
do not say what the identifier **is** — and that is where the most expensive
consequence comes from, one that shows up a module away.

An lcore is an index kept in **thread-local storage**. The declaration is in
[`rte_per_lcore.h`][ringperlcore], and it is literally this:

```c
#define RTE_DEFINE_PER_LCORE(type, name)   __thread type per_lcore_##name
#define RTE_PER_LCORE(name)                (per_lcore_##name)
```

And `rte_lcore_id()` does nothing but read it:

```c
static inline unsigned rte_lcore_id(void) { return RTE_PER_LCORE(_lcore_id); }
```

What writes to that variable is the EAL, in `__rte_thread_init()`, and what it
does there defines what "being an lcore" means:

```c
RTE_PER_LCORE(_lcore_id) = lcore_id;   /* the index, in TLS */
rte_gettid();                          /* system id */
thread_update_affinity(cpuset);        /* the affinity */
__rte_trace_mem_per_thread_alloc();    /* per-thread trace memory */
```

**Being an lcore is not a property of the CPU; it is state installed into the
thread.** The inverse function, `__rte_thread_uninit()`, restores
`LCORE_ID_ANY` — and an ordinary thread, which went through neither, is born
with that value.

#### The cost of reading the identifier

For an audience that cares about the hot path, the next question is what that
read costs. C's `__thread` has different access models, and they do not cost the
same — the general-dynamic model requires **calling** `__tls_get_addr`, which
would be unacceptable in a function called per packet. The reference work on
this is Drepper's on TLS in ELF ([`tls.pdf`][dreppertls]).

Disassembling a binary from this repository that uses a mempool with a
per-lcore cache:

```bash
objdump -d custo-contencao | grep -cE '%fs:|__tls_get_addr'
```

```
24 accesses via %fs
 0 calls to __tls_get_addr
```

and the instruction that reads the identifier is a single one:

```
64 8b 38    mov %fs:(%rax),%edi
```

The `64` prefix is the `%fs` segment, which on x86-64 points to the thread's TLS
block. Reading the lcore id is **one memory access with a displacement** — no
function call and no run-time lookup. The operand is a register rather than a
constant, which indicates the *initial-exec* model, with the displacement
resolved when the binary is loaded, and not pure *local-exec*.

#### The consequence, which lives in module 03

The index is **dense** on purpose: it starts at zero and has no holes. System
CPU numbers are sparse — `--lcores '0@6,1@7,2@18'` puts lcores 0, 1 and 2 on
CPUs 6, 7 and 18. If the library indexed arrays by CPU number, it would need an
array the size of the largest existing CPU.

And that is exactly what the mempool does
([`rte_mempool.h`][guiamempool], `rte_mempool_default_cache`):

```c
if (unlikely(mp->cache_size == 0))      return NULL;
if (unlikely(lcore_id == LCORE_ID_ANY)) return NULL;
return &mp->local_cache[lcore_id];      /* direct indexing */
```

Put the two ends together and the whole chain appears:

    thread registered by the EAL
            ↓
    __thread per_lcore__lcore_id  ←  dense index
            ↓
    rte_lcore_id()  →  mov %fs:(%rax)
            ↓
    &mp->local_cache[lcore_id]
            ↓
    mempool fast path

    ordinary thread, unregistered
            ↓
    LCORE_ID_ANY
            ↓
    NULL cache  →  straight to the shared ring

**Two threads with the same code take different paths through the library**,
and the variable is not in the code: it is in who registered the thread.
[Module 03](../03-mempool-ring-mbuf/README.en.md#1-why-not-use-malloc--the-measured-answer)
measures what that cache is worth — about 30× — and that is the difference
between having it and not.

> **Registering a non-EAL thread and using multiprocess exclude each other.** An
> ordinary thread can acquire an lcore through
> [`rte_thread_register()`][apiregister], but the function refuses when the
> multiprocess model is in use:
>
> ```c
> if (!rte_mp_disable()) {
>     EAL_LOG(ERR, "Multiprocess in use, registering non-EAL threads is not supported.");
>     rte_errno = EINVAL;
>     return -1;
> }
> ```
>
> This matters in this module in particular, because it is the module of the
> primary/secondary model. Whoever follows [§4](#4-primary-and-secondary-processes)
> and then tries to register an application thread gets `EINVAL`, and the
> message only appears in the EAL log.

> **What transfers outside DPDK.** The pattern is *per-thread state indexed by a
> dense identifier, installed at registration and read from TLS*. It shows up in
> allocators with per-thread caches, in per-thread metric collectors, and in any
> structure that wants to avoid coordination by trading memory for parallelism.
> What DPDK adds is the awkward part: **whoever does not register does not take
> part**, and the library does not warn — it merely gets slower.

### 5.2 The state machine has two states, not three

A worker lcore receives work through [`rte_eal_remote_launch()`][apiremotelaunch] and is
awaited with [`rte_eal_wait_lcore()`][apiwaitlcore]. Between the two, its state is
observable through [`rte_eal_get_lcore_state()`][apilcorestate].

The direct observation, in `estado-lcore`'s output:

```
  after rte_eal_init:    lcore 1: WAIT     lcore 2: WAIT     lcore 3: WAIT    
  after remote_launch:   lcore 1: RUNNING  lcore 2: RUNNING  lcore 3: RUNNING 
  during the work:       lcore 1: RUNNING  lcore 2: RUNNING  lcore 3: RUNNING 

  values returned by the workers:
    lcore 1 -> 107
    lcore 2 -> 207
    lcore 3 -> 307

  after wait_lcore:      lcore 1: WAIT     lcore 2: WAIT     lcore 3: WAIT    
```

Two points:

**After `rte_eal_init()`, the workers are already in `WAIT`.** It is not a generic idle
state: initialisation is what puts them there. The API's header is literal — *"It puts
the WORKER lcores in the WAIT state"*. The lcores exist before the application asks for
anything.

**There is no `FINISHED`.** The state returns to `WAIT` on its own. That is a version
change, not an implementation detail: the [19.11 API][api1911] declares three values —
`WAIT`, `RUNNING`, `FINISHED` — and describes `rte_eal_wait_lcore()` as the function
that, finding an lcore in `FINISHED`, *"switch[es] to the WAIT state"*. In 25.11 the
enum has two values, and the installed header describes the function without any
mention of a third state.

What did **not** change is the reason for calling `rte_eal_wait_lcore()`: it is the
return channel. The value returned by the worker's function reaches the main lcore
through it — in the output above, `107`, `207` and `307`. Ignoring that return value is
discarding the only result the worker had to deliver.

### 5.3 Service lcores

There is a third category besides main and worker. `-S` /
[`--service-corelist`][optlcore] reserves lcores for **service cores** — background
tasks DPDK libraries register to run periodically, without the application calling
them.

It deserves a mention here for an operational reason: if the application does not
reserve service lcores and some library needs one, that work will compete with the hot
path. In a system whose requirement is the latency tail, unannounced background work is
exactly the kind of thing that produces a p99 nobody can explain.

---

## 6. IOVA: the address the device sees

A NIC writing by DMA into the process's memory needs an address. That address is not
necessarily the same one the CPU uses, and DPDK calls what the device uses the **IOVA**
(*I/O virtual address*). The EAL chooses between two modes at initialisation, and
reports the choice:

```
EAL: Selected IOVA mode 'VA'
```

| Mode | What the device receives | Requires |
|---|---|---|
| **PA** (*physical address*) | a real physical address | access to `/proc/self/pagemap`, typically privilege; physically contiguous memory |
| **VA** (*virtual address*) | a virtual address, translated by the IOMMU | an active IOMMU, with the device in a usable group |

VA mode is what makes running a data plane without privilege viable, and it depends
directly on the IOMMU described in
[§6.1 of the fundamentals](../01-fundamentos/README.en.md#61-iommu-how-to-hand-dma-to-a-process-without-opening-up-the-system).
The IOMMU translates the address the device presents, the same way the MMU translates
the CPU's — and, like any translation, it has its own cache and its own miss cost,
which is the IOTLB discussed there.

Querying the mode at runtime is one line, [`rte_eal_iova_mode()`][apiiovamode], and
forcing it is `--iova-mode=pa|va`. Forcing it is rarely the right answer: when the EAL
chooses PA on a machine that should use VA, the problem is usually in the IOMMU (off in
the BIOS, or without `amd_iommu=on` / `intel_iommu=on` on the kernel command line), and
the mode is the symptom, not the cause.

In the *market data* example's output an instructive detail appears: with `--no-huge`,
the memzone reported `addr` and `iova` as **equal** (`0x1040f2f80` for both). It makes
sense — in VA mode, the address the device uses *is* the virtual one. In PA mode the two
values would differ, and the difference would be precisely the work the EAL does to
discover each page's physical address.

---

## 7. Shutdown: what is left behind

[`rte_eal_cleanup()`][apiealclean] costs **0.12 ms with `-l 0 --in-memory`** and
**0.65 ms with `-l 0 --no-huge`** — three and two orders of magnitude below
initialisation, respectively. The number does not exist without the configuration
next to it, and
[§2](#2-the-cost-of-existing-how-long-the-eal-takes-to-be-born) shows why. Being so
cheap in both cases, the question is what happens when it is not called.

**Order matters.** Resources created over the EAL's memory should be freed **before**
it:

```c
rte_memzone_free(mz);
rte_eal_cleanup();
```

Inverting that is using memory already returned. In an application with configured
ports, correct shutdown begins even earlier: stop the ports, close them, and only then
clean up the EAL.

**And in multiprocess there is one more restriction, which only appears when you run
it.** Freeing a shared memzone is not a local operation: it triggers a synchronisation
with the secondary processes (`mp_malloc_sync`). If one of them is already shutting
down, the request goes unanswered:

```
EAL: Fail to recv reply for request /run/user/1000/dpdk/academia/mp_socket_...:mp_malloc_sync
EAL: Could not send sync request to secondary process
```

Nothing is corrupted, but the message denounces an out-of-order shutdown. The rule that
solves it has two parts, and the second is usually the one missing:

1. **The primary exits last.** It owns the memory and the control socket.
2. **"Last" means after the secondary process has DISAPPEARED**, not after it has
   finished reading. Between those two things the secondary is still tearing down its
   mappings — and it is exactly in that window that the synchronisation fails.

This module's example waits for both: a signal in shared memory ("I have finished
reading") and the disappearance of the secondary's control socket from the runtime
directory ("I have exited"). With both, the shutdown is silent. In production, whoever
guarantees that order is usually the orchestrator that stops the secondaries before
stopping the primary — the EAL does not do it on its own.

**What is left when the process dies abruptly.** A `SIGKILL` does not run
`rte_eal_cleanup()`. What remains:

- the runtime files in `$XDG_RUNTIME_DIR/dpdk/<prefixo>/`, including the `mp_socket`;
- the hugepage files in `/dev/hugepages/<prefixo>map_*`, and therefore the hugepages
  still accounted for as in use;
- possibly, a device still bound to the dead process.

The practical consequence is the usual one in systems with state outside the process:
coming up again with the same `--file-prefix` may find the old state. That is why this
module's L2 test uses a prefix derived from the PID (`academia_l2_$$`) and removes the
directory at the end — each run is a new instance, inheriting nothing.

It is worth recording the complete asymmetry, because it explains the architectural
choice in [§2.3](#23-what-this-decides-in-the-architecture):

| Operation | Median cost | Order of magnitude |
|---|---|---|
| `rte_eal_init()` | 123 ms | 10⁵ µs |
| `rte_eal_cleanup()` | 0.12 to 0.65 ms, depending on the memory mode | 10² µs |
| per-packet budget on 10 GbE, 64 B frame | 67.2 ns | 10⁻¹ µs |

A data-plane process spends its whole life operating on the third row. It only touches
the first once — and that is why it can cost what it costs.

---

## 8. Synthesis: the feed handler's runtime

Bringing this module's decisions together in the guiding example, the command line of a
*market data* *feed handler* stops being a list of options and becomes a set of
justified choices:

```bash
# --lcores '0@2,1@3'      lcores in the SAME cache domain    (§5.1)
# --numa-mem 4096         memory on the NIC's node           (§3.4)
# --file-prefix=producao  isolates this instance             (§4.3)
# --huge-dir=/mnt/huge-md its own hugetlbfs, no root         (§4.5)
# -a 0000:c1:00.0         only the feed's NIC
./feed-primario \
    --lcores '0@2,1@3' \
    --numa-mem 4096 \
    --file-prefix=producao \
    --huge-dir=/mnt/huge-md \
    -a 0000:c1:00.0 \
    -- 200000 cadencia
```

> **The comments go above, not beside.** In a line continuation the `\` has to
> be the **last** character: `\ # comment` escapes the space, not the newline,
> and `bash` then treats the next line as a new command.

| Choice | Why | Where it was established |
|---|---|---|
| lcores mapped explicitly | avoids the cost of crossing a cache domain | [§5.1](#51-an-lcore-is-not-a-cpu) |
| memory reserved per node | avoids remote access per packet | [§3.4](#34-reserving-memory-per-node) |
| a named `--file-prefix` | allows production and replay on the same machine | [§4.3](#43---file-prefix-isolation-between-instances) |
| a dedicated hugetlbfs | multiprocess without running as `root` | [§4.5](#45-what-switches-the-multiprocess-model-off-without-warning) |
| a single, long-lived process | initialising costs 123 ms | [§2.3](#23-what-this-decides-in-the-architecture) |
| a secondary for the strategy | failure isolation and its own life cycle | [§4.1](#41-why-two-processes) |

None of those options is about code performance. All are about **the environment** —
which is precisely the definition of the EAL: *Environment Abstraction Layer*.

---

## 9. Validation: reproduce it on your machine

Every number in this document comes from programs in [`medicoes/`](medicoes/), compiled
along with the project.

```bash
./scripts/build-all.sh
```

**Initialisation cost** — change the options and compare:

```bash
./build/docs/02-runtime-dpdk/medicoes/custo-init -l 0 --in-memory
./build/docs/02-runtime-dpdk/medicoes/custo-init -l 0 --no-huge --in-memory --no-pci
```

**What the EAL decided, and the lcore states**:

```bash
./build/docs/02-runtime-dpdk/medicoes/estado-lcore -l 0-3 --in-memory
./build/docs/02-runtime-dpdk/medicoes/estado-lcore --lcores '0@6,1@7' --in-memory
```

**Primary and secondary** — requires a writable hugetlbfs:

```bash
./scripts/preparar-hugepages.sh
export DPDK_ACADEMY_HUGE_DIR=/mnt/huge-academia
./scripts/test-all.sh l2
```

Without that requirement, the test reports what is missing and is counted as **skipped**
(`SKIP`), not as a success: a lack of privilege on the host is not a defect in the code,
but it is also not a verification performed.

**Tests:**

```bash
./scripts/test-all.sh l1    # order-book logic, without the EAL
./scripts/test-all.sh l2    # runtime real
```

The L1 ([`medicoes/tests/test_l1_order_book.cpp`](medicoes/tests/test_l1_order_book.cpp))
covers the *market data* logic without touching DPDK: datagram loss, repeated
retransmission, level cancellation and the layout stability of `struct tick`, which
crosses the process boundary.

The **L3** ([`medicoes/tests/l3_multiprocesso.sh`](medicoes/tests/l3_multiprocesso.sh))
verifies what only exists with two processes, including that the memzone appears at the
same virtual address on both sides.

> **Why L3, and not L2.** This test requires something of the host that the host has to
> grant: a hugetlbfs with write permission. Where that is missing, it exits with code
> **77**, which Meson reports as `SKIP` and counts separately.
>
> It used to exit with **0**, and Meson reported `OK` — with the script's nine checks
> **not evaluated**. On the CI runner the requirement never exists, so this test never
> verified anything and always appeared green. A test that passes without testing is
> worse than an absent test: it consumes the confidence it should build.

### Exercises

1. Run `custo-init` and check whether your machine has `tsc_known_freq` in
   `/proc/cpuinfo`. Does the `rte_eal_init()` time match the prediction in
   [§2.2](#22-why-that-wait-exists-and-when-it-does-not-happen)?
2. Confirm the 100 ms wait with `strace -T -e trace=clock_nanosleep`. Does it appear
   more than once?
3. Start `feed-primario` with no secondary at all. What does it do after 15 s, and why
   does the wait need to be generous?
4. Start the secondary **without** `--proc-type=secondary`. Read the message: why would
   `--proc-type=auto` be worse than the error?
5. Start two primaries with the same `--file-prefix`. What is the error, and does it say
   what to do?
6. Run `feed-primario` in `rajada` mode instead of `cadencia` and compare the median
   with the crossing's p99. What changed, and why?
7. On a machine with several cache domains, place producer and consumer on different
   CCDs with `--lcores` and redo the crossing measurement. Compare with the values in
   [§4.3 of the fundamentals](../01-fundamentos/README.en.md#43-numa-when-memory-stops-being-one-thing).

---

## 10. When it goes wrong

> **This module's question:** what happens when the primary process dies with
> secondaries still alive?

[§4](#4-primary-and-secondary-processes) showed the happy path: the secondary finds the
memzone by name, maps it at the same virtual address, reads without copying. The model
is elegant precisely because the secondary does not need to know anything about the
primary beyond the `--file-prefix`.

That same independence is the problem.

### 10.1 The experiment

[`medicoes/tests/l3_primario_morre.sh`](medicoes/tests/l3_primario_morre.sh) starts the
pair, waits for the secondary to attach, and kills the primary with **SIGKILL** — sudden
death, with no orderly shutdown, as the *OOM killer* or a hardware failure would.

```
== L3: the primary dies, the secondary carries on ==

  ok    - secondary attached to the primary's memory

  killing the primary (SIGKILL, no orderly shutdown)...
  ok    - primary died by signal (code 137, expected != 0)
  ok    - secondary survived the primary's death (no segfault)
  ok    - secondary did NOT detect the death after 5s: still waiting
  ok    - secondary issued no warning about the missing producer
  ok    - secondary did not finish: stuck in 'while (lidos < total)'
  ok    - only an external signal ends the secondary
```

### 10.2 What is learned from it

**The memory outlives its owner.** The hugetlbfs pages remain mapped and readable after
the process that reserved them has ceased to exist. The secondary does not lose the
mapping and does not receive `SIGSEGV`: it goes on reading, and what it reads is the
**last published state**, indefinitely.

**Nothing warns.** There is no heartbeat, no *liveness* contract, no signal. The
secondary stays stuck in [`while (lidos < total)`](medicoes/feed-secundario.c#L150),
waiting for data that will not come. The process did not hang because of a defect — it
waits correctly and indefinitely for a producer that no longer exists.

**This is worse than a crash.** A process that dies is observable: the supervisor
notices, the alert fires, someone acts. A consumer that goes on serving stale data with
the appearance of fresh data is not observable from outside — and in a *market data*
server, trading on a frozen order book is worse than not trading.

> **The responsibility is the application's, and DPDK does not take it on.** Detecting
> an absent producer requires a sequence number, a publication *timestamp* or a
> *watchdog* — all three built by you. DPDK's multiprocess model delivers memory
> sharing, not an availability contract.

### 10.3 What this experiment does not cover

Not measured here is the case of the **secondary** dying with the primary alive, nor
that of a primary that restarts and tries to recreate a memzone whose name still exists.
Both are recorded as pending, not as results.

> **This section used to state that there was no supervisor.** There is now:
> [`scripts/feed-supervisor.py`](../../scripts/feed-supervisor.py) restarts the
> session in a new generation after a failure, and the test
> [`l3_recuperacao.sh`](medicoes/tests/l3_recuperacao.sh) verifies that the
> next session comes up with a different generation, that the old processes
> died, and that the order of events holds. What follows replaces the old
> statement.

### 10.4 Detecting that the producer stopped is two questions, not one

Killing the primary and watching the secondary answers *"does the consumer
survive?"*. It does not answer the question operations asks: *"is the feed still
good?"* — and that one has two halves the same symptom does not separate.

[`medicoes/feed-health.h`](medicoes/feed-health.h) separates them with **two
clocks and two thresholds**:

```c
if (gen != w->generation || gen == 0)     return FEED_WRONG_GENERATION;
if (now - w->last_heartbeat >= silence)   return FEED_SILENT;
if (now - w->last_data     >= freshness)  return FEED_STALE;
return FEED_HEALTHY;
```

`last_heartbeat` advances when the producer shows signs of life; `last_data`
advances when it publishes **new data**. They are independent instants with
independent thresholds, and it is that independence that produces the state
intuition does not predict:

| state | heartbeat | data | what happened |
|---|---|---|---|
| `FEED_HEALTHY` | advances | advances | nothing |
| `FEED_SILENT` | stopped | — | the producer died |
| `FEED_STALE` | **advances** | stopped | the producer is alive and the feed stopped |
| `FEED_WRONG_GENERATION` | — | — | whoever answers is not who was being watched |

The third is the interesting one. A supervisor watching only the heartbeat
declares the system healthy while no new data has arrived for minutes — because
the process responds, the socket is open and the thread did not hang. **Alive
and stalled are different states, and only the second clock separates them.**

The L1 test ([`tests/test_l1_feed_health.cpp`](medicoes/tests/test_l1_feed_health.cpp))
demonstrates it in three lines, with the heartbeat going from 1 to 3 and the
data stuck at 1:

```cpp
EXPECT_EQ(feed_watch_update(&w, 7, 1, 1,  1, 10, 30), FEED_HEALTHY);
EXPECT_EQ(feed_watch_update(&w, 7, 2, 1,  9, 10, 30), FEED_HEALTHY);
EXPECT_EQ(feed_watch_update(&w, 7, 3, 1, 31, 10, 30), FEED_STALE);
```

#### The generation, and why the observer does not adopt it

The fourth line of the other case is the subtlest in the module:

```cpp
EXPECT_EQ(feed_watch_update(&w, 8, 2, 2, 12, 10, 30), FEED_WRONG_GENERATION);
EXPECT_EQ(w.generation, 7u);
```

On receiving generation 8, the observer **refuses and keeps its own**. It does
not reconfigure itself. If it did, the producer's restart would become a silent
transition — and the event operations most needs to see would be precisely the
one that disappeared from the report.

It is the same idea the supervisor uses from the other side: each session is
born with a new generation, and `l3_recuperacao.sh` requires the two to differ.
An incarnation identifier is what prevents confusing *"it came back"* with *"it
never left"*.

> **What transfers outside DPDK.** This is a **failure detector** with two
> dimensions — liveness and freshness — and an incarnation number. The pattern
> holds for any stream consumer: a database replica, a message queue, a market
> session, a lease in a distributed service. The error it avoids is not one of
> performance; it is publishing "healthy" about a system that stopped making
> progress.
>
> The DPDK-specific part is small: the instants come from
> [`feed-clock.h`](medicoes/feed-clock.h), with `CLOCK_MONOTONIC` and `abort()`
> if the clock fails — because measuring time with a broken clock is worse than
> not measuring.

#### What is still not covered

Coordinated recovery remains out of scope: who restarts first, how the secondary
decides it can reconnect, what to do with the stale state. The supervisor
restarts the **whole session** in a new generation, which is the simplest choice
and the one that discards the most work.

Also not measured is the case of the **secondary** dying with the primary alive,
nor that of a primary that restarts and tries to recreate a memzone whose name
still exists. Both are recorded as pending, not as results.

## 11. Limitations of this document

- **No NIC is involved.** The ticks are generated by a deterministic PRNG. The object of
  study is the runtime; real reception is level 4.
- **A single-NUMA-node machine.** Everything this document says about `--numa-mem` and
  node alignment is reasoning resting on the fundamentals, not a local measurement. On a
  single-socket machine, the option has nothing to separate.
- **The process crossing was measured with producer and consumer in the same cache
  domain** (lcores 0 and 1, both on CCD 0). On different CCDs the cost rises, and by how
  much is exercise 7 — the practical topic measured 4.0 to 4.8 times for the analogous
  crossing within one process.
- **The crossing measurement's resolution is ~12 ns**, one of the consumer's polling
  periods. Smaller differences are not observable with this instrument, and the published
  values are an upper bound, not the exact cost.
- **123 ms is this machine's.** It is the result of a CPU without `tsc_known_freq` with
  this kernel, and [§2.2](#22-why-that-wait-exists-and-when-it-does-not-happen) explains
  why. Do not use the number as a characteristic of DPDK.
- **The comparison with other sources is about versions, not about authors.** What
  [§1](#1-what-this-module-adds-to-the-existing-sources) documents are verifiable API
  changes; material written before them was correct when it was written.

---

## 12. External references

**DPDK's official documentation**

- [Environment Abstraction Layer][cEAL] — the runtime's reference chapter
- [Multi-process Support][cmultiproc] — the primary/secondary model, limitations and
  requirements, including the quotations about ASLR and `--file-prefix`
- [EAL parameters][cparams] — the normative list of command-line options
- [Release Notes 20.11][rel2011] — the master/slave to main/worker renaming
- [19.11 API for `rte_launch.h`][api1911] — the three-state enum, for comparison
- [System requirements][cHuge] — hugepages and host configuration

**Source code cited**

- [`lib/eal/linux/eal_timer.c`][fonteeal] — `get_tsc_freq()` and the 100 ms wait

**From this project**

- [Fundamentals](../01-fundamentos/README.en.md) — per-packet budget, cache, NUMA, false
  sharing and metrics
- [Topic 01 — EAL initialisation](../../trilha/01-fundamentos/01-eal-hello/) — the
  minimal program and `rte_eal_init()`'s contract
- [DPDK link map](../../ferramental/qualidade/mapa-links-dpdk.md) — the canonical record
  of the symbols cited

---

## 13. Navigation

| | |
|---|---|
| **Previous** | [01 — Fundamentals](../01-fundamentos/README.en.md) |
| **Practical** | [Topic 01 — EAL initialisation](../../trilha/01-fundamentos/01-eal-hello/) |
| **Next** | [03 — Mempool, ring and mbuf](../03-mempool-ring-mbuf/) |
| **Plan** | [Study plan](../plano-estudo-dpdk.en.md) |

[apiealinit]: https://doc.dpdk.org/api/rte__eal_8h.html#a5c3f4dddc25e38c5a186ecd8a69260e3
[apiealclean]: https://doc.dpdk.org/api/rte__eal_8h.html#a7a745887f62a82dc83f1524e2ff2a236
[apiiovamode]: https://doc.dpdk.org/api/rte__eal_8h.html#a1e1ff16a6096013452673ea31ea16aa8
[apimzreserve]: https://doc.dpdk.org/api/rte__memzone_8h.html#a58c7cd707097b56e3ca29fb3c172565e
[apimzlookup]: https://doc.dpdk.org/api/rte__memzone_8h.html#ac7fc18c445135eb2e91a1f2ab989cdde
[apiremotelaunch]: https://doc.dpdk.org/api/rte__launch_8h.html#a2bf98eda211728b3dc69aa7694758c6d
[apiwaitlcore]: https://doc.dpdk.org/api/rte__launch_8h.html#ae9500e1d35bd4cfb95d18c0be863cb1e
[apilcorestate]: https://doc.dpdk.org/api/rte__launch_8h.html#a66d883d90f6112489b69c996a2f6f2ab
[apitocpuid]: https://doc.dpdk.org/api/rte__lcore_8h.html#acbf23499dc0b2d223e4d311ad5f1b04e
[apicpuset]: https://doc.dpdk.org/api/rte__lcore_8h.html#a830bea1c9dda2c18d04252f297e25721
[apimainlcore]: https://doc.dpdk.org/api/rte__lcore_8h.html#a5449c6ee062fe3641520374152ce6c67
[apisocketid]: https://doc.dpdk.org/api/rte__lcore_8h.html#a7c8da4664df26a64cf05dc508a4f26df
[apitschz]: https://doc.dpdk.org/api/rte__cycles_8h.html#ae016e608f344823e677819d8f04264c5
[apitsccycles]: https://doc.dpdk.org/api/rte__cycles_8h.html#a34aaedfb8b9fa4f83d4cb3108cda2041
[apipause]: https://doc.dpdk.org/api/rte__pause_8h.html#ad59aa7777c93d3cfd5f10617a3acd1c5

[cEAL]: https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html
[cHuge]: https://doc.dpdk.org/guides/linux_gsg/sys_reqs.html
[cmultiproc]: https://doc.dpdk.org/guides/prog_guide/multi_proc_support.html
[cparams]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html

[optlcore]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#lcore-related-options
[optmem]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#memory-related-options
[optmulti]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#multiprocessing-related-options
[optdev]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#device-related-options
[optdebug]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#debugging-options
[optlinux]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#linux-specific-eal-parameters

[rel2011]: https://doc.dpdk.org/guides/rel_notes/release_20_11.html
[api1911]: https://doc.dpdk.org/api-19.11/rte__launch_8h.html
[fonteeal]: https://github.com/DPDK/dpdk/blob/v25.11/lib/eal/linux/eal_timer.c
[ringperlcore]: https://github.com/DPDK/dpdk/blob/v25.11/lib/eal/include/rte_per_lcore.h
[guiamempool]: https://doc.dpdk.org/guides/prog_guide/mempool_lib.html
[dreppertls]: https://www.uclibc.org/docs/tls.pdf
[apiregister]: https://doc.dpdk.org/api/rte__thread_8h.html
