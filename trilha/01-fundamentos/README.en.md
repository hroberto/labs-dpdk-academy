# Module 01 — Practical DPDK fundamentals

> **Levels 3 and 4** of the [study plan](../../docs/plano-estudo-dpdk.en.md) ·
> Matching theory: [01 — Fundamentals](../../docs/01-fundamentos/README.en.md)
> and [02 — DPDK runtime](../../docs/02-runtime-dpdk/README.en.md)

*Leia em [português](README.md).*

This module was the first in the trail to be finished, and for a long time the
only one — modules 02 and 03 gained content on 16/09/2026. It covers the two
things every DPDK program does before handling its first packet: **bringing the
runtime up** and **getting memory without allocating on the hot path**.

## Topics

| Topic | Subject | Level | Tests |
|---|---|---|---|
| [01 — EAL initialisation](01-eal-hello/) | what the EAL decides before your first line runs | 3 | L2 |
| [02 — Mempool, ring and batching](02-mempool-ring/) | borrowing and returning objects; passing batches between cores | 4 | L1 + L2 |
| [Pure C++23 alternative](02-mempool-ring/alternativas/cpp23/) | the same problem without DPDK, under the same verified contract | 4 | L1 + L2 |

## The order matters

The two topics can be read in whichever order you like, but there is a real
dependency between them: topic 02 uses memory that **topic 01's EAL reserved**.
Whoever skips the first will meet, in the second, command-line options
([`--in-memory`][optmem], [`--no-huge`][optdebug], [`-l`][optlcore]) without
knowing what they do or what they cost.

And there is a dependency in the opposite direction, less obvious: topic 02
measures that crossing from one core to another costs 4.0 to 4.8 times more when
the cores are in different cache domains. **Choosing which CPU each lcore runs
on** is the business of the
[runtime module](../../docs/02-runtime-dpdk/README.en.md#51-an-lcore-is-not-a-cpu), in
theory. Measuring without knowing how to control leaves half the lesson out.

## Why each topic has the tests it has

The split is not arbitrary, and explaining it is part of the content:

- **Topic 01 has only L2.** There is no pure logic to isolate — the topic *is*
  runtime initialisation. Testing argument variations demands one process per
  variation, because [`rte_eal_init()`][apiealinit] is not reentrant; hence the
  test being a script, not a GoogleTest case.
- **Topic 02 has L1 and L2.** The packet logic lives in its own file, including
  nothing from DPDK, and so runs in milliseconds at L1. What only exists with the
  runtime up — pool integrity after thousands of reuse cycles — stays at L2.

That separation has a concrete cost worth knowing: bringing the EAL up takes
**123 ms** on this machine
([§2 of the runtime module](../../docs/02-runtime-dpdk/README.en.md#2-the-cost-of-existing-how-long-the-eal-takes-to-be-born)).
A suite that required the runtime for every assertion would pay that price in
every test case.

## How to run it

```bash
./scripts/build-all.sh
./scripts/test-all.sh l1     # pure logic, no EAL
./scripts/test-all.sh l2     # real runtime
```

## Next module

[02 — Pipeline and batch processing](../02-pipeline/), where the ring stops being
an exercise and becomes a stage of a data path.

[apiealinit]: https://doc.dpdk.org/api/rte__eal_8h.html#a5c3f4dddc25e38c5a186ecd8a69260e3

[optdebug]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#debugging-options
[optlcore]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#lcore-related-options
[optmem]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#memory-related-options
