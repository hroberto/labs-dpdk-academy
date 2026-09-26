# Module 02 — Pipeline and batch processing

*Leia em [português](README.md).*

> **Levels 5 and 6** of the [study plan](../../docs/plano-estudo-dpdk.en.md) ·
> Prerequisite: [01 — Practical fundamentals](../01-fundamentos/), especially
> [02 — Mempool, ring and batch](../01-fundamentos/02-mempool-ring/)

Organise packet handling as a **staged data path**, and deal with what appears
when the stages run at different speeds: queues, backpressure, and the choice
between latency and throughput.

## State of this module

**Half delivered, and the missing half depends on hardware.**

| Submodule | Level | State |
|---|---|---|
| [01 — RX/TX burst](01-rx-tx-burst/) | 6 | scope and environment measured; **waits for the card to leave the kernel** |
| [02 — Batching and backpressure](02-batching-backpressure/) | 5 | **written**, with the depth × batch surface measured |

Submodule 01 is not a skeleton — the reference NIC's capabilities are measured
with a real tool — and it is not finished content either. What blocks it is one
line: `enp8s0` still has `IFF_UP` set, and the capture guard refuses. A
`sudo ip link set enp8s0 down` unblocks it, and that decision belongs to whoever
operates the machine.

> **About the numbering.** Submodule 01 belongs to level 6 and 02 to level 5 — the
> directory order does not follow the level order, and that is intentional:
> backpressure only makes sense once a real packet source exists, which is what
> RX/TX brings. The irony is that 02 was finished first, because it does not need
> the card. If the order is revisited, revisit this note too.

## Where this module starts

The topic [02-mempool-ring](../01-fundamentos/02-mempool-ring/) already delivered
pieces this module **should not re-present**:

- the object life cycle (borrow from the pool, return to the pool);
- the batch-size curve, measured — and it **depends on the mode**: with one lcore
  the gain is large up to 8, marginal up to 32 and **regresses** at 128; with two
  lcores in the same cache domain it **does not regress**, and 128 and 256 are the
  best points. The batch is the antidote to the crossing cost, and with no
  crossing that benefit does not exist;
- the cost of crossing a cache domain, measured (4.0 to 4.8 times);
- the demonstration that **parallelising can make things worse** when the work per
  packet does not pay for the hand-off.

> This very paragraph once published the curve without the qualifier —
> *"regression at 128"*, as if it always held. The source always separated the two
> modes; it was the compression into an index that lost the distinction, and
> submodule 02, measuring with two lcores, found batch 128 to be the best point.
> An index that summarises a measurement can create a falsehood the source
> document does not contain.

The starting point here is the sentence that topic leaves open: *"when the queue
fills, the producer gets a refusal instead of blocking — that is explicit
backpressure"*. What to do with that refusal is the subject of submodule 02.

## What submodule 02 established

**Backpressure is not decided by the queue.** The ring holds `depth − 1`, and the
pool has 4095 objects. Once the capacity reaches the pool, the ring fits
everything that exists and can no longer fill:

| Capacity | vs. pool | Any refusal? |
|---|---|---|
| 1,023 | smaller | **yes**, in every run |
| 2,047 | smaller | **yes**, in every run |
| **4,095** | **equal** | **no — zero, always** |

The boundary falls exactly where the arithmetic puts it. It is the **ratio**
between pool and queue that governs, not the depth alone — with a larger pool, the
same depth refuses again.

**The batch weighs more than the depth.** At depth 256, going from batch 8 to 128
moves from **8.4 to 4.4 ns** (median of 7 runs, non-overlapping ranges); going
deeper at the same batch moves far less, and the ranges touch.

> The refusal **count** does not appear here, and the reason is in the submodule's
> retraction: eight runs of the same configuration gave 118,626 to 286,625 — 128%
> amplitude. It answers **whether there was** backpressure, not **how much**.
> <!-- retratado: referencia -->
> <!-- This block retracts nothing: it CITES the submodule's retraction. The two
>      numbers are counts of refused objects, and the comma is a thousands
>      separator, not a decimal point. -->

## Commitments already published

These links exist in written documents and point here:

| Origin | What was promised | State |
|---|---|---|
| [02-mempool-ring §3](../01-fundamentos/02-mempool-ring/README.en.md) | real *backpressure* handling, beyond the retry loop | **partial** — of the three policies, only dropping was measured |
| [02-mempool-ring §6](../01-fundamentos/02-mempool-ring/README.en.md) | what to do when the producer never sleeps | **met** — `pipeline_ring.c -t` ends on a progress deadline and declares what it dropped |
| [C++23 alternative §3](../01-fundamentos/02-mempool-ring/alternativas/cpp23/README.en.md) | the honest performance comparison, which only exists with a NIC | **open** — depends on submodule 01 |

## What is still missing

- **block and push back**: described in submodule 02, with no experiment;
- **dropping with criteria** — which packet to sacrifice — requires metadata that
  `struct packet` does not carry;
- **backpressure that reaches the NIC**, which is submodule 01;
- **a pure C++23 alternative** for the same backpressure problem;
- **analysis of when one more stage stops paying off** — the fundamentals already
  have the measurement ("parallelising can make things worse"); the generalisation
  to an N-stage pipeline is missing.

## Navigation

| | |
|---|---|
| **Previous** | [01 — Practical fundamentals](../01-fundamentos/) |
| **Next** | [03 — Performance and observability](../03-performance/) |
| **Index** | [Track](../README.en.md) · [Study plan](../../docs/plano-estudo-dpdk.en.md) |
