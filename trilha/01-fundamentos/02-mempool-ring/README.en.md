# Topic 02 — Mempool, ring and batch processing

*Leia em [português](README.md).*

> **Level 4** of the [study plan](../../../docs/plano-estudo-dpdk.md) ·
> Requires [topic 01](../01-eal-hello/) · Has a [DPDK-free alternative](alternativas/cpp23/)

## 1. Foundation: why not use `malloc()`

With a budget of 67 ns per packet on 10 GbE, allocating dynamically on the data
path is risky: `malloc()` has high variance and fragments memory over time. But the
program needs objects per packet.

> **Beware of the folkloric version of this argument.** It is commonly said that
> `malloc()` "costs tens of nanoseconds", and this was measured in this project:
> allocating and freeing one object at a time costs **2.18 ns**, because glibc has a
> per-thread cache and the pair falls into it. The mempool's real justification is
> another, and it appears when you work in **batches** — the data plane's regime. The
> numbers are in [§1 of the theory module](../../../docs/03-mempool-ring-mbuf/README.md#1-por-que-não-usar-malloc--a-resposta-medida).

DPDK's solution inverts the problem: **allocate everything once, at the start, and
then only borrow and return**. It is the *object pool* pattern, with two pieces:

- **[`rte_mempool`][guiamempool]** — a set of fixed-size objects, allocated at
  initialisation. Borrowing (`get`) and returning (`put`) cost a few nanoseconds,
  with a per-**lcore** cache — the thread the EAL creates and pins to a logical CPU
  ([glossary][glossario]) — which avoids contention between cores.
- **[`rte_ring`][guiaring]** — a circular queue of pointers, of fixed size, used to
  pass objects between stages without a lock when there is one producer and one
  consumer.

The third concept is **batch processing (burst)**: moving *n* objects per call
instead of one. The fixed cost of each operation — index checks, memory barriers —
is amortised over the whole batch.

## 2. Mechanism: the object's life cycle

This is the topic's central concept, and the one that generates the most errors:

```mermaid
flowchart LR
    POOL[("mempool")]
    PROD["producer"]
    RING[["ring"]]
    CONS["consumer"]

    POOL -->|"get_bulk"| PROD
    PROD -->|"enqueue_burst"| RING
    RING -->|"dequeue_burst"| CONS
    CONS -->|"put_bulk"| POOL

    classDef fonte fill:#e8f0fe,stroke:#1a5490,color:#0d2b4e
    classDef fila fill:#fdf6e3,stroke:#b7950b,color:#7d6608
    class POOL fonte
    class RING fila
```

**Every object taken out has exactly one destination: back to the pool.** There is
no automatic collection. If a code path forgets the return, the pool empties, the
producer stops getting objects and the pipeline stops — silently, with no error.

The easiest point to get wrong is the partial return.
[`rte_ring_enqueue_burst`][apienqburst] returns **how many objects actually fitted**,
which may be fewer than requested:

```c
unsigned enq = rte_ring_enqueue_burst(fila, (void *const *)lote, n, NULL);
if (enq < n) {
    /* os que NÃO couberam continuam sendo seus: devolva-os */
    rte_mempool_put_bulk(pool, (void *const *)&lote[enq], n - enq);
}
```

Ignoring that return value is this subject's classic leak.

> **Anticipating RX/TX:** [`rte_eth_tx_burst`][apitxburst] has the **opposite**
> semantics — it *takes ownership* of the packets it accepted, and the driver
> returns them to the pool after transmitting. Freeing an mbuf accepted by TX is a
> *double free*. You free only the ones **not** accepted. Keep the difference: in the
> ring, what did not fit is yours; in TX, what was accepted is no longer yours.

## 3. Trade-offs

**Batch size.** Larger batches amortise the fixed cost better, but increase the
first packet's latency and the cache usage. Measurement in this project, with 5
million packets:

| Batch | ns/packet (DPDK) |
|---:|---:|
| 1 | 5.3 |
| 8 | 2.3 |
| 32 | **1.8** |
| 128 | 2.2 |

The gain is large up to 8, marginal up to 32, and it **regresses** at 128 — the
batch stops fitting comfortably in cache. There is no "the bigger the better"; there
is an optimum point that you measure.

> **This result is for ONE lcore, and does not hold for two.** [§3](#3-trade-offs)
> measures the same curve with the consumer on its own core, and there it **does not
> regress**: 128 and 256 are the best points. The batch is the antidote to the
> crossing cost, and with no crossing that benefit does not exist.
>
> The sentence above was once repeated without the qualifier in the index of
> [module 02](../../02-pipeline/), where it became "regression at 128" as if it
> always held — and the backpressure submodule, measuring with two lcores, found the
> opposite. A correct measurement, compressed without its regime, becomes a falsehood
> the source document does not contain.

> **How these numbers were obtained.** `-n 5000000` per point, with the warm-up the
> program performs before timing. Three consecutive runs gave identical values at
> each batch (1.8/1.8/1.8 at batch 32), which did not happen before the warm-up
> existed.
>
> What is still **not** controlled is the processor's frequency: this machine's
> governor is `powersave` with turbo on, and the program came to print the frequency
> alongside the time for exactly that reason. Compare the *shape* of the curve with
> your machine's; the absolute values will differ. Measurement with a pinned
> environment enters at Stage 5.

**Where the lcores are.** This is the trade-off that only appears when the ring
really crosses cores, and it is bigger than the batch-size one.

> This topic's consumer is dispatched with `rte_eal_remote_launch()` and collected
> with `rte_eal_wait_lcore()` (see [`pipeline_ring.c`](pipeline_ring.c)). What those
> two functions do with the lcore's state, and why the second remains mandatory even
> after the worker has finished, is in
> [§5.2 of module 02](../../../docs/02-runtime-dpdk/README.md#52-a-máquina-de-estados-tem-dois-estados-não-três).

With two or more lcores (`-l 0,2`), the consumer gets its own core and every batch
travels from one cache to the other. How much that trip costs depends on **which**
cores you chose: modern CPUs group cores into blocks sharing an L3, and crossing
from one block to another goes through the chip's internal interconnect.

On this machine (Ryzen 9 9900X) the blocks are `0-5,12-17` and `6-11,18-23`.
Measuring with [`scripts/bench-ccd.sh`](../../../scripts/bench-ccd.sh), 3 million
packets:

| Batch | 1 lcore | 2 lcores, same block | 2 lcores, different blocks | Ratio |
|---:|---:|---:|---:|---:|
| 1 | 5.3 ns | 16.0 ns | 64.3 ns | 4.0× |
| 8 | 2.3 ns | 5.1 ns | 24.3 ns | 4.8× |
| 32 | 1.8 ns | 3.6 ns | 16.1 ns | 4.5× |
| 128 | 2.2 ns | 2.6 ns | 12.0 ns | 4.6× |
| 256 | 2.4 ns | 2.3 ns | 9.3 ns | 4.0× |

> **Why the "1 lcore" column does not match the previous table** (5.3 against ~5.9 at
> batch 1): they are different measurements. The first table comes from a single run
> of the binary; this one comes from `bench-ccd.sh`, which takes the **best of
> several repetitions** to reduce noise. The difference between the two is this kind
> of measurement's own margin of error, and seeing it is more useful than hiding it
> by publishing only one.

Three readings, and none of them is obvious:

**The choice of core weighs more than any other decision here.** Moving the consumer
from the neighbouring block to the distant one costs 4.0 to 4.8 times, without
changing a line of code. At batch 1, the 64.3 ns consume **96%** of the 67.2 ns
budget of a 64 B packet on 10 GbE — almost everything, just to hand the packet to the
other core.

**The batch is the antidote to the crossing cost.** Each batch crosses the
interconnect once, regardless of how many objects it carries. That is why batching's
gain is far larger when there is a crossing: between distinct blocks, going from
batch 1 to 256 saves 55 ns per packet; on a single lcore, it saves 2.9 ns. Batching
does not only amortise calls — it amortises **distance**.

**Parallelising can make things worse.** Note that a single lcore beats two lcores
across almost the whole table. The work per packet here is an XOR; it does not pay
for the cost of handing it to another core. Only at batch 256 and the same block do
the two cores finally win (2.3 against 2.4 ns). The lesson transfers to any pipeline:
**one more stage only pays off if the work it does exceeds the cost of the hand-off**
— and you have just measured that cost.

> Reproduce it on your machine with `./scripts/bench-ccd.sh`. The script discovers
> the blocks from sysfs and adapts; on a single-block CPU it warns and measures what
> it can.

**And how do you choose the core, in practice?** This table measures the cost of the
choice; what gives you control over it is the EAL. With `-l 0,2` you ask for lcores
and accept the default mapping; with `--lcores '0@6,1@7'` you declare which CPU each
lcore runs on. The difference between the two forms — and an API trap along the way,
the function `rte_lcore_to_cpu_id()`, which despite its name does not return the CPU
number — is in [§5.1 of module 02](../../../docs/02-runtime-dpdk/README.md#51-lcore-não-é-cpu).

**Pool size.** The pool here has 4095 objects to process up to millions of packets.
That is deliberate: it only finishes if the return is correct on every cycle. An
oversized pool would hide leaks.

**Fixed-size ring.** When it fills, the producer gets a refusal instead of blocking.
That is explicit *backpressure* — the subject of the
[pipeline topic](../../02-pipeline/).

## 4. Implementation

| File | Role |
|---|---|
| [`packet.h`](packet.h) / [`packet.c`](packet.c) | pure logic, **without DPDK** |
| [`pipeline_ring.c`](pipeline_ring.c) | runtime: EAL, mempool, ring |

That separation is deliberate. Packet logic does not need DPDK to exist, so it should
not depend on it to be tested. That is what makes the L1 test possible.

> **Note that mempool and ring are created by NAME.** That is not a debugging label:
> the name is the EAL's memory identification mechanism, the same as memzones. It is
> by name that a second process would find this pool without receiving any pointer —
> the model in
> [§3.1 of module 02](../../../docs/02-runtime-dpdk/README.md#31-memzone-memória-com-nome).
> Here there is only one process, so the name looks decorative; it stops looking that
> way the day the strategy becomes a separate process.

```bash
./scripts/build-all.sh
./build/trilha/01-fundamentos/02-mempool-ring/pipeline_ring \
    -l 0 --no-huge --file-prefix=topico02 -- -n 10
```

Expected output (omitting the `EAL:` lines):

```
Pacotes processados: 10
Total de bytes: 695
Lote (burst): 32 | objetos que nao couberam na fila: 0
Modo: 1 lcore (0), produtor e consumidor alternados
Objetos livres no pool ao final: 4095 de 4095
Tempo medio: 52.1 ns/pacote  <- NAO E MEDICAO
  10 pacotes sao poucos demais: o custo de ler o relogio e da mesma
  ordem do trabalho medido. Use -n 10000 ou mais para um numero defensavel.
```

The decisive line is the **fifth**: `4095 de 4095` means every object came back. Any
smaller number is a leak.

The first five lines are **deterministic** — repeat as often as you like and they do
not change.

**And note what the program does with the sixth.** It refuses to present it as a
measurement, and the reason is not a lack of warm-up — the program warms up with 4096
packets before starting the clock. It is that 10 packets represent about 20 ns of
real work, measured with a clock whose reading costs the same order of magnitude:
**the instrument dominates the phenomenon**. On this machine, three consecutive runs
of the same command give:

| `-n` | three runs | verdict |
|---:|---|---|
| 10 | 40 / 55 / 134 ns | unusable |
| 100 | 10 / 15 / 16 ns | still ±50% |
| 10 000 | 2.2 / 2.4 / 2.4 ns | stable |

Publishing the first case with one decimal place would be invented precision. A
program that prints a number it cannot support teaches the reader to trust numbers
that cannot be supported — which is why the threshold is in the code, and not only in
the text. The number with meaning is in section 3, and it requires a large `-n`.

### Exercises

1. Run with `-n 5000000 -b 1` and then `-n 5000000 -b 128`, and compare with section
   3's table. Then repeat both with `-n 10`: why does neither number look like the
   table? (The measurement starts **after** the EAL, in
   [`pipeline_ring.c`](pipeline_ring.c) — so what distorts it is not the cost of
   initialising.)
2. Increase to `-n 1000000`. Is the pool still intact?
3. **Provoke the bug:** comment out the [`rte_mempool_put_bulk`][apiputbulk] on the
   partial-return path and run with `-b 256`. What happens to the pool's final count?
4. Why is the total 695 bytes and not 690? (Hint: look at `pacote_processar`.)

## 5. Validation

This topic has both levels, and the division shows what each one reaches.

```bash
./scripts/test-all.sh l1     # 13 casos, sem EAL, milissegundos
./scripts/test-all.sh l2     # runtime real
```

**L1** ([`tests/test_l1.cpp`](tests/test_l1.cpp)) — GoogleTest over `packet.c`, via
`extern "C"`. Besides the behavioural assertions, it expresses an invariant of the
topic with a parameterised test: processing 10 packets in batches of 1, 2, 3, 4, 8,
10 or 32 **always** gives 695 bytes. Batch size is a performance knob, never a
semantic one.

**L2** ([`tests/l2_run.sh`](tests/l2_run.sh)) — exercises the binary under the
[EAL][cEAL]. The central assertion is the pool's integrity after ~25 cycles of
complete reuse (100 000 packets with 4095 objects). No L1 test could detect this: the
leak only exists at runtime.

## 6. When it goes wrong

> **This topic's question:** what does the **partial** return of
> [`rte_ring_enqueue_burst()`][apienqburst] oblige you to do, and what happens to the
> objects if it is not done?

### 6.1 The mechanism

`rte_ring_enqueue_burst(fila, objs, n, NULL)` returns **how many** objects could be
enqueued, and that number may be smaller than `n`. It is not an error: it is the ring
saying it filled up. The `n - enq` left over are still **yours** — they came out of
the pool and have not yet been handed to anyone.

The pool has no garbage collector. If you do not return those objects, they do not
come back on their own: they leave circulation for good. It is one line of code:

```c
if (enq < n)
    rte_mempool_put_bulk(pool, (void *const *)&lote_prod[enq], n - enq);
```

### 6.2 The experiment

The topic compiles the **same source** twice. `pipeline_ring_vazado` is
`pipeline_ring.c` with that return removed by `#ifdef` — nothing else changes.

```bash
./build/trilha/01-fundamentos/02-mempool-ring/pipeline_ring_vazado \
    -l 0,2 --no-huge --file-prefix=topico02 -- -n 2000000 -b 256
```

```
INVARIANTE VIOLADO: 1403 de 4095 objetos no pool ao final. 2692 objeto(s)
vazaram: algum caminho de retorno nao devolveu ao pool.
Pacotes processados: 2000000
Total de bytes: 161000000
Lote (burst): 256 | objetos que nao couberam na fila: 2692
Objetos livres no pool ao final: 1403 de 4095
```

### 6.3 What the measurement shows

On this machine, with 2 000 000 packets and the consumer on another core:

| Batch | Did not fit | Leaked | Pool at the end | Packets |
|---:|---:|---:|---:|---:|
| 32 | 2979 | 2979 | 1116 of 4095 | 2 000 000 |
| 64 | 2946 | 2946 | 1149 of 4095 | 2 000 000 |
| 128 | 2945 | 2945 | 1150 of 4095 | 2 000 000 |
| 256 | 2692 | 2692 | 1403 of 4095 | 2 000 000 |

Three readings, and the third is the one that matters:

**1. Exactly the ones that did not fit leak.** The ratio is 1.00 at all four batch
sizes, and not by coincidence: they are the same quantity. The counter publishes
`n - enq`, which is precisely the set the removed line would return.

**2. The program finishes fine.** The same 2 000 000 packets, the same
161 000 000 bytes, output identical to the correct binary's in everything a user would
look at. No hang, no `SIGSEGV`, no message from DPDK. **The only evidence is the
invariant checked in the output** — and that is why it exists.

**3. The defect hides its own symptom.** Compare with the same invocation on the
correct binary:

```
Lote (burst): 256 | objetos que nao couberam na fila: 905604
Objetos livres no pool ao final: 4095 de 4095
```

The **correct** program had 905 604 objects with no place in the queue; the
**defective** one, 2 692 — about 336 times fewer. Intuition says the opposite, and
intuition is wrong because [`rte_mempool_get_bulk()`][apigetbulk] is **all or
nothing**: with the pool drained, it does not return a smaller batch, it returns
`-ENOBUFS` and the producer produces nothing on that turn. Fewer objects in
circulation means less pressure on the ring, which fills less, which overflows less.

That is: the leak consumes the capacity that caused the overflow, and with that it
erases the trace that would denounce the leak. A system like that does not degrade
with an alarm — it degrades in silence, losing margin until it stops.

### 6.4 How this is captured

The [L2 test](tests/l2_run.sh) requires the defective binary to **fail**, and that
inversion is deliberate: a check that has never failed is indistinguishable from one
that never fires.

The test also checks the **precondition** before accusing, and that cost an earlier
version: the leak only exists on the partial-return path, which only executes when
the ring fills. If the consumer keeps up with the producer, the ring does not fill,
the path does not run and nothing leaks — the test failed in one run out of four,
accusing a defect where there was none. Today it only asserts the leak after
confirming, from the program's output, that there were objects with no place in the
queue.

> **Outside this topic.** Returning to the pool settles the object's **ownership**,
> not the **policy**: the packet that did not fit still has not been sent. Choosing
> between dropping, blocking or pushing the pressure back is the subject of the
> [batching and backpressure topic](../../02-pipeline/02-batching-backpressure/).

## 7. Limitations

- There is no network. The "packets" are synthetic structures; there is no mbuf, NIC
  or DMA. [`rte_mbuf`][guiambuf] arrives in the RX/TX topic.
- The ring is in SP/SC mode (one producer, one consumer), which suffices for this
  topic's two modes. With several producers or several consumers you would need
  MP/MC, whose cost is higher because it requires contended atomic operations.
- In the two-lcore mode the producer never sleeps: if the queue fills, it retries in
  a tight loop. Real backpressure is the subject of the
  [pipeline topic](../../02-pipeline/).
- With `--no-huge`, the pool's memory does not come from [hugepages][cHuge], which
  changes TLB behaviour relative to production — and also prevents a second process
  from attaching to this pool, because anonymous memory is not mappable from outside.
  Mempool and ring **are** shareable between processes when the memory comes from
  hugepages; that is the model in
  [§4 of module 02](../../../docs/02-runtime-dpdk/README.md#4-processos-primário-e-secundário).

## 8. Comparison and the next step

The [pure C++23 alternative](alternativas/cpp23/) solves **the same problem** without
DPDK, with the same verified contract (10 packets, 695 bytes) — it is where each
approach's gains and losses become explicit.

Then: [pipeline and backpressure](../../02-pipeline/).

[guiamempool]: https://doc.dpdk.org/guides/prog_guide/mempool_lib.html
[guiaring]: https://doc.dpdk.org/guides/prog_guide/ring_lib.html
[apienqburst]: https://doc.dpdk.org/api/rte__ring_8h.html#a85ad08ed07e2e485c94466e03bf252c4
[apitxburst]: https://doc.dpdk.org/api/rte__ethdev_8h.html#a83e56cabbd31637efd648e3fc010392b
[apiputbulk]: https://doc.dpdk.org/api/rte__mempool_8h.html#a5e46fc827d764e516e8ff0c3f00e33fc
[apigetbulk]: https://doc.dpdk.org/api/rte__mempool_8h.html#a0d326354d53ef5068d86a8b7d9ec2d61
[guiambuf]: https://doc.dpdk.org/guides/prog_guide/mbuf_lib.html

[cEAL]: https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html
[cHuge]: https://doc.dpdk.org/guides/linux_gsg/sys_reqs.html

[glossario]: https://doc.dpdk.org/guides/prog_guide/glossary.html
