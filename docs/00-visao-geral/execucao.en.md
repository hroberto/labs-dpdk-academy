# First run and reading the results

*Leia em [português](execucao.md).*

This walkthrough exercises the in-memory version. Use Linux with a C/C++23
compiler, DPDK, Meson and Ninja, per the [tooling document](ferramental.md). Run
the commands from the repository root. The future NIC is not needed for this
walkthrough.

## Build and check

```bash
./scripts/check-env.sh
./scripts/build-all.sh
./scripts/test-all.sh l1
./scripts/test-all.sh l2
```

L1 checks logic and tooling; L2 integrates the available executables without
preparing hardware. `OK` means that entry was exercised; `SKIP` identifies a
missing requirement. `EXPECTEDFAIL` is only expected in the registered negative
controls. Consult the diagnosis of any `FAIL` before interpreting measurements.
Logs live in `build/meson-logs/`.

## Run the pipeline

```bash
./build/trilha/01-fundamentos/02-mempool-ring/pipeline_ring \
  -l 0 --no-huge --no-pci --file-prefix=academia_leitura \
  -- -n 10 -b 8 -t 2000
```

CPU 0 must belong to the process's allowed mask; adjust `-l` if necessary. The
expected functional result is 10 packets, 695 bytes and every object returned to
the pool. Ten packets do not constitute a performance measurement. The `-t`
parameter bounds the wait without progress; failing that deadline ends the
pipeline after draining the pending objects.

To understand the **ownership** half — who frees the object, and why freeing the
second segment of a chain is a mistake — read
[§2.4 Ownership: who frees](../03-mempool-ring-mbuf/README.md#24-posse-quem-libera).
The **progress** half (the `-t` deadline, and what happens when it expires) is
described in the paragraph above and **does not yet have its own section** in the
module: the previous link pointed to a "§6.4 Ownership and progress policy" that
was never written.
To study the complete mechanism, follow the [practical topic](../../trilha/01-fundamentos/02-mempool-ring/README.md).

## Reading a table

Start with the module's own tables: the
[cost of the ring](../03-mempool-ring-mbuf/README.md#3-o-anel-o-preço-da-generalidade)
carries the numbers with the amplitude between runs.
Identify the API, the batch, the CPUs, the number of repetitions and the unit. The
rows describe amortised cost; they are not per-packet latency p99 nor NIC
performance. Use the table's links to check the environment, sources and samples.

## Moving on into the runtime

The [runtime module](../02-runtime-dpdk/README.md#10-quando-dá-errado) describes
silence, book validity and session restart. Its real L3 tests require a writable
hugetlbfs with free pages. If that requirement is missing, the SKIP is an
identified pending item; the logic and supervisor tests do not replace it.

Continue through the [track](../../trilha/README.md) according to the mechanism you
want to investigate. The [validation policy](validacao.md) distinguishes what was
written, implemented, tested and measured.

Follow the contracts and pending items in the
[ROADMAP](../../ROADMAP.md). The campaigns that support quantitative comparisons
live in the [validation matrix](validacao.md).
