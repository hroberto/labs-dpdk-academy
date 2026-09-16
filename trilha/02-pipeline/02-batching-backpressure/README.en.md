# Submodule 02 — Batching and backpressure

*Leia em [português](README.md).*

> **Level 5** of the [study plan](../../../docs/plano-estudo-dpdk.md) ·
> Prerequisite: [01 — RX/TX in bursts](../01-rx-tx-burst/)

Answering the question the mempool topic leaves open: **what to do when the queue
fills.**

## 1. Foundation: backpressure is the consumer saying "stop"

A pipeline has a producer and a consumer, and nothing guarantees they move at the
same pace. When the producer is faster, the queue between them grows to its limit —
and then the system needs an answer. There are three, and only three:

**Drop.** The producer throws away what did not fit. It is the data plane's answer
when stale data loses value: in an exchange *feed*, a tick from ten milliseconds
ago is already uninteresting.

**Block.** The producer waits for the queue to open. It risks stalling everything
if the consumer never drains, and that is why this topic's program has a progress
deadline (`-t`).

**Push back.** The producer passes the refusal on to whoever feeds it. It only
exists if there is someone to pass it to — on a NIC receiving multicast, there is
not.

The right answer depends on what the data means, and that is the part code does not
settle.

## 2. Mechanism: who decides whether the queue fills

Here is this submodule's least intuitive result, and it is **not about the queue**.

The program uses an `rte_ring` of configurable depth and an `rte_mempool` of
**4095 objects**. The ring's usable capacity is `depth − 1`: one slot is reserved
to distinguish full from empty.

So when the ring's capacity reaches the pool's size, **the ring comes to hold every
object that exists** — and can no longer fill. No backpressure is possible, not
because the queue is generous, but because nothing was left outside it.

**Backpressure is decided by the ratio between pool and queue, not by the queue
alone.** Section 6 measures the boundary, and it lands exactly where the arithmetic
says.

### A full queue is not loss in transport

The distinction is easily confused, and both appear in this project:

| | Full internal ring | Loss in transport |
|---|---|---|
| Who suffers | the producer, which gets a refusal | the consumer, which never sees the data |
| Detection | the enqueue function's return | a sequence discontinuity |
| Response | retry, drop, or push back | request retransmission, or carry on with an incomplete book |

The mempool topic counts "attempts with a full queue" and retries. In a system
where the producer is an exchange transmitting by multicast, that option does not
exist: the datagram that was not read is lost, and what you detect afterwards is a
**jump in the sequence number** — the mechanism the
[runtime module](../../../docs/02-runtime-dpdk/README.md#4-processos-primário-e-secundário)
already implements and tests.

## 3. Trade-offs: a deep queue is not free

Growing the queue reduces refusal and increases end-to-end latency: an object
queued behind ten thousand others waits for all of them. It is the classic
throughput-versus-latency trade-off, and it has an upper limit section 6 shows —
from the point where the queue holds the entire pool, going deeper **buys nothing**
and pays in cache footprint.

The batch has the opposite effect, and a larger one than expected: large batches
amortise the per-object cost on both sides, and with that the consumer drains
faster — which reduces refusal instead of increasing it.

## 4. Implementation

The queue depth was **fixed at 1024** in the code, which made the first item in
this submodule's scope impossible to measure. It became the `-q` option:

```bash
B=build/trilha/01-fundamentos/02-mempool-ring/pipeline_ring
$B --no-huge -m 512 --no-pci -l 0,2 -- -n 200000 -b 32 -q 1024 -t 8000
```

Two usage refusals, both with the explanation alongside:

```
-q 1000   → deve ser potencia de dois (exigencia do rte_ring)
-q 8 -b 32 → -q 8 nao comporta um lote de 32 (capacidade util e profundidade-1)
```

The second exists because, without it, a batch larger than the queue makes the
producer spin without ever enqueueing, until the progress deadline expires — five
seconds of nothing instead of one line saying what is wrong.

## 5. Validation

```bash
./scripts/ambiente-medicao.sh --uma-linha   # carimbe o ambiente junto
B=build/trilha/01-fundamentos/02-mempool-ring/pipeline_ring
for q in 1024 2048 4096; do
  printf 'prof=%-6s ' "$q"
  $B --no-huge -m 512 --no-pci -l 0,2 --file-prefix=v$q -- \
     -n 200000 -b 32 -q $q -t 8000 2>/dev/null | grep 'nao couberam'
done
```

With **one lcore** (`-l 0`), producer and consumer alternate and the queue never
fills: refusal is **zero at any depth**. Backpressure only appears when the two
sides genuinely run in parallel.

## 6. When it goes wrong — the measured surface

Two CPUs (`-l 0,2`), 200 000 packets, a pool of 4095 objects. Each point is the
median of **seven** runs, discarding the first — for the reason measured in the
[benchmarking submodule](../../03-performance/01-benchmarking/), where the first
run after idle comes out ~30% high. Each cell carries the median and, in brackets,
the **observed range**, because without it the number misleads.

| Depth | Capacity | Batch 8 | Batch 32 | Batch 128 |
|---|---|---|---|---|
| 256 | 255 | 8.4 ns [7.5–9.0] | 5.2 ns [4.6–6.4] | 4.4 ns [3.4–5.0] |
| 1 024 | 1 023 | 7.7 ns [6.5–8.9] | 4.8 ns [4.3–6.3] | 3.2 ns [3.2–4.1] |
| 4 096 | **4 095** | 7.1 ns [6.1–7.4] | 4.9 ns [3.8–6.0] | 4.1 ns [3.0–4.9] |

> **RETRACTION — 16/09/2026.** This table published, on the very day it was
> written, **fifteen point values** of time and refusal, obtained with three runs
> per point. Re-checked with seven runs, **two of the three time values in the 256
> row fell OUTSIDE the measured range** — the published "2.8 ns" against a range of
> 3.4 to 5.0.
>
>
> Worse was the refusal count. Eight runs of the **same** configuration (depth
> 1024, batch 32) gave 118 626 to 286 625: **128% amplitude over the median**.
> Publishing "219 292" and "85 143" as if they were measurements is giving three
> significant figures to a quantity that varies by a factor of two and a half. The
> numbers left the table.
>
>
> **This retraction is NOT machine-checked, and it is worth saying why.**
> `verificar-retratacoes.py` tracks decimals with three or more significant figures
> — `0,115`, `2,18`, `65,84`. The values struck down here fall outside on both
> sides: `8,5` and `2,8` have two significant figures, and the cut exists so that
> "5,0" does not become noise in every document; `219 292` and `62 529` are
> integers with a thousands separator, which the decimal-number pattern does not
> even match.
>
> So the guarantee here is human, not automatic. Recording that is the minimum: an
> inert `<!-- retratado: -->` marker would be worse than none, because it would
> suggest a check that does not happen.
>
> Refusal depends on the race between producer and consumer, which the scheduler
> arbitrates on every run. It serves to answer **whether there was** backpressure —
> and that answer is stable, as the boundary below shows. It does not serve to say
> **how much**.
>
> The defect is mine and it is exactly what the neighbouring benchmarking submodule
> describes: I treated three runs as sufficient without measuring the dispersion.
> The methodology was written in the neighbouring document and was not applied
> here.

### The boundary lands where the arithmetic says

The pool has 4095 objects. A capacity of `4096 − 1 = 4095` is the first value that
reaches the whole pool:

| Depth | Capacity | vs. pool | Any refusal? |
|---|---|---|---|
| 1 024 | 1 023 | smaller | **yes**, in every run |
| 2 048 | 2 047 | smaller | **yes**, in every run |
| 4 096 | **4 095** | **equal** | **no — zero, in every run** |

**This is the stable result**, and the count's instability does not affect it: the
question "was there refusal?" has a binary answer, and it never varied across 7
runs per point. Below the boundary, always; at the boundary, never.

The transition is abrupt and sits exactly at the predicted point. That confirms
section 2's mechanism: **the queue stopped filling because it came to hold
everything that exists**, not because it became "big enough".

It is also a warning about hasty reading. The natural conclusion would be
*"depth ≥ 4096 eliminates backpressure"* — a claim about the queue. The true claim
is about the **ratio**, and in a system with a larger pool the same depth would
refuse again.

### The batch weighs more than the depth

At depth 256, going from batch 8 to 128 takes **8.4 to 4.4 ns** — nearly half. At
1024, from 7.7 to 3.2. The direction is the same at all three depths, and the
ranges do not overlap between batch 8 and batch 128 at any of them: it is a
difference, not noise.

Going deeper, at the same batch, moves far less: from 256 to 4096 at batch 8 goes
from 8.4 to 7.1 ns, and the ranges **touch**. **The batch dominates the depth.**

The reason is that the per-object cost falls on both sides with larger batches, so
the consumer drains faster than the producer fills — the opposite of what intuition
suggests, which is "a larger batch fills the queue faster".

### Going deeper than the boundary: not measured

The previous version of this section compared depth 16 384 against 4 096 and
concluded that the excess cost cache footprint. **The comparison was removed**, for
two reasons:

1. the values came from the same three-run collection the retraction above
   invalidated;
2. on re-check with `-m 512`, the 16 384 configuration **did not complete** — and a
   measurement that does not run does not become a number.

What can be claimed from the seven-run data: from 1 024 to 4 096, at batch 128, the
median **gets worse** (3.2 to 4.1 ns) and the ranges overlap ([3.2–4.1] against
[3.0–4.9]). That is: **crossing the boundary bought nothing measurable here**, and
may have cost. Saying which of the two would require more repetitions than were
made.

## 7. Limitations

**The three policies were not implemented — only one was measured.** The program
returns what did not fit to the pool, which is the *drop* policy. Blocking and
pushing back are described in section 1 and have no experiment here. The skeleton's
deliverable asked for all three; one was delivered, and the gap is stated.

**Dropping with criteria was left out.** Which packet to drop when some must be
dropped is a policy decision, and requires metadata `struct packet` does not carry
today.

**Backpressure reaching the NIC was not touched.** It requires the card outside the
kernel, which is what [submodule 01](../01-rx-tx-burst/) is blocked waiting for.

**One machine, one pair of cores.** Everything measured with `-l 0,2`, inside the
same L3 domain. Crossing domains changes the crossing cost and probably the shape
of the surface — see [fundamentals §4.3](../../../docs/01-fundamentos/README.md#43-numa-quando-a-memória-deixa-de-ser-uma-coisa-só).

**No comparison against pure C++23 was made.** It was in the deliverables and did
not get in.

## 8. Where to go from here

| | |
|---|---|
| **Previous** | [01 — RX/TX in bursts](../01-rx-tx-burst/) |
| **Next** | [03 — Performance and observability](../../03-performance/) |
| **Module** | [02 — Pipeline](../README.md) |
| **Program** | [`pipeline_ring.c`](../../01-fundamentos/02-mempool-ring/pipeline_ring.c) |
