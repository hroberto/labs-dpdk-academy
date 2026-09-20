# Validation, data and evolution with hardware

*Leia em [português](validacao.md).*

This page defines the criteria common to the modules. The implementation state
lives in the [track index](../../trilha/README.en.md); future work, in the
[roadmap](../../ROADMAP.en.md). Do not confuse written content, an executed test, and
a published performance result.

## Current version and next stage

The local machine does not yet have the target NIC for the advanced networking
tests. The next stage will use a **Mellanox ConnectX-4 Lx 25GbE dual-port SFP28**,
after installation and confirmation of the capabilities in the effective
configuration.

| Scope | State and criterion |
|---|---|
| Logic, EAL, structures and in-memory pipeline | Executable now; must satisfy the invariants of their respective tests. |
| Multiprocess, hugepages and contention | L3 executable once its local prerequisites are available; does not depend on the target NIC. |
| Physical RX/TX, RSS and scaling by queues | Pending for the next stage with adequate hardware and application. Probing a port does not validate traffic. |
| Throughput, loss and latency of the network system | Not measured; they require a traffic source and a declared methodology. |
| Remote NUMA | Depends on at least two NUMA nodes with memory; the NIC's arrival does not guarantee that topology. |
| AF_XDP zero-copy and offloads | Conditional on support and on working in the real combination of NIC, firmware, driver and software. |

A pending item due to hardware does not fail the current version's scope. Nor is it
equivalent to a zero result or to approval. The in-memory measurements remain
evidence about the components, without anticipating the physical network's
performance.

## L1, L2 and L3

| Level | What it checks | Current examples |
|---|---|---|
| L1 | Logic and tooling without starting the EAL or touching a NIC | Statistics, order book, sizing, packet and the scripts' fixtures. |
| L2 | Execution and integration without special hardware preparation | The EAL's CLI with `--no-huge`, object conservation, mbuf chains and the C/C++ pipeline. Includes programs without an EAL. |
| L3 | Scenarios requiring specific host resources | Shared hugetlbfs, death of the primary, topology and contention. In future, physical networking. |

Apply each level to the behaviour that justifies it. A minimal program that only
calls the EAL does not require an artificial L1. Tests that print timings verify
execution and, where implemented, sanity conditions of the collection; they do not
validate the historical values published.

```bash
./scripts/build-all.sh
./scripts/test-all.sh l1
./scripts/test-all.sh l2
./scripts/test-all.sh l3
meson test -C build --list       # current inventory, no double counting in prose
```

The runner must distinguish:

- **PASS:** the expected behaviour was effectively verified.
- **FAIL:** a violated property, an unexpected error, or an incomplete scenario
  after the prerequisites were satisfied.
- **SKIP (77):** an explicitly identified missing prerequisite; report which
  scenario did not run. A generic EAL failure does not prove hardware is absent.

Do not add up Meson entries, GoogleTest cases and assertions as if they were the
same measure. The project does not publish a code-coverage percentage. When
reporting quality, state the requirements exercised, the failures and the
exclusions, alongside the counts.

## How to publish data

### Editorial conventions for numbers and units

- In Portuguese prose and editorial tables, use the decimal comma: `1,8 ns`.
  Separate thousands with a space when needed: `200 000 objects`.
- Separate number and unit: `25 GbE`, `64 B`, `40,08 ns`, `1,5 %`.
  `GbE` names the technology; a measured rate needs a unit such as `Gbit/s`.
- Use `B` for bytes and `bit` for bits. `MB` and `MiB` are not interchangeable;
  convert only when the decimal or binary base has been established.
- Preserve the decimal point, spacing and precision of literal outputs, CSV,
  commands and historical references. Identify the block as output; do not edit a
  log to make it look like a new editorial table.
- State the unit in the header or alongside the values and explain the operation:
  `ns/objeto` in a get/put cycle is not per-packet latency.
- Name the numerator and denominator of ratios. Declare whether the division uses
  raw or displayed values, and how it was rounded. Do not add decimal places that
  did not exist at the source.
- Distinguish `not measured`, `not applicable` and zero. An absent measurement does
  not supply a value for means, charts or ratios.

### The minimum context for each result

A table must declare **scenario, quantity, experimental unit and aggregation**. For
example, `ns per object in a get/put cycle` differs from `p99 in ns from
publication to observation`. Amortised costs, individual latencies and full
pipeline times are not automatically addable parts.

The numbers already transcribed in the modules are historical records of the
reference machine. Not every table has raw samples and per-run metadata preserved;
in those cases, exactly regenerating them is not assured. Ratios between
implementations may also change with frequency, load and affinity.

For every new publishable collection, preserve in an identified directory:

| Artefact | Minimum content |
|---|---|
| `metadados.md` | Date, code revision, local changes, exact command, variables, compiler, build options, DPDK, kernel and scenario configuration. |
| `ambiente.txt` | The output of `scripts/ambiente.sh` at that run; not the one from the day the table is revised. |
| `saida.txt` and `status.txt` | Full output and return code, including when there is a failure or SKIP. |
| `amostras.csv`, when the measurement produces samples | Individual values and units. If the program only exports aggregates, declare that limitation; do not reconstruct samples from the median. |
| Table and method | The command or calculation to derive it, warm-up, number of samples, discards and dispersion. A link from the table to the record. |

Use a clean revision, or also preserve the unversioned changes and sources used in
the run. Record the environment before the measurement, and keep diagnostic
collection outside the timed window. The `DPDK_ACADEMY_AMOSTRAS` and
`DPDK_ACADEMY_RODADAS` limits used in CI verify execution; they do not replace a
collection intended to compare performance.

## Acceptance for the next version, with networking

Before measuring, record the model and firmware, the negotiated PCIe, topology,
versions, driver/PMD, queues, descriptors, affinity, batch size and active
offloads. Describe the connection between ports and the traffic source. A generator
on the same host consumes resources of the machine being measured; two ports do not
guarantee sufficient load.

| Scenario to implement | Acceptance criterion |
|---|---|
| Basic RX/TX | The content and sequence received correspond to the traffic sent; differences are accounted for as identified losses or drops. |
| Partial TX and pressure on pools | Only objects not accepted remain under the application's ownership; on shutdown, every object is freed after stopping/draining the port. |
| RSS and scaling | The flows and queues observed correspond to the configuration; compare the same work with the number of queues/cores declared. |
| Overload and recovery | Record where dropping occurs and demonstrate a return to processing after removing the overload, within a limit defined before the trial. |
| Performance | Offered load, received throughput, loss and latency distribution have declared unit, duration, population and dispersion. Identify whether the measurement is one-way or round-trip, and the clock method. |
| DPDK, sockets and AF_XDP comparison | The same data and processing, with resources and modes made explicit; unavailable capabilities are pending items, with no winner presumed. |

The numeric limits for loss, latency and recovery must be defined from the system's
requirement before the collection. There is no validated network SLO in this
project yet. The card's nominal 25GbE rate is a scenario target, not a measurement
of the receiver nor a promise of line rate.
