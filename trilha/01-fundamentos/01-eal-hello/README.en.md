# Topic 01 — EAL initialisation

*Leia em [português](README.md).*

> **Level 3** of the [study plan](../../../docs/plano-estudo-dpdk.en.md) ·
> Prerequisite: DPDK installed ([tooling](../../../docs/00-visao-geral/ferramental.en.md))

## 1. Foundation: what the EAL solves

An ordinary program does not need to ask which core it runs on, which memory node
its allocation comes from, or whether the pages are 4 KB or 2 MB. The kernel decides
for it, and the choices are reasonable for general workloads.

For a data plane, those choices stop being reasonable. On 10 GbE with 64-byte frames
14.88 million packets per second arrive — about **67 nanoseconds per packet**. A
single context switch or a TLB miss consumes a good part of that budget. The program
has to decide for itself where it runs and where its memory comes from.

The **[EAL][cEAL]** (*Environment Abstraction Layer*) is the layer that makes those
decisions before the first line of your logic executes. It is what turns an ordinary
process into a data-plane process.

## 2. Mechanism: what [`rte_eal_init()`][apiealinit] does

The call does far more than "initialise":

| Step | Effect |
|---|---|
| Parses the EAL's options | consumes the arguments before `--` |
| Creates the **lcore** threads | one per core requested in [`-l`][optlcore], pinned to it |
| Reserves memory | [hugepages][cHuge] per NUMA node, or anonymous with [`--no-huge`][optdebug] |
| Chooses the IOVA mode | physical or virtual address for DMA |
| Discovers devices | scans the buses (PCI, vdev) |
| Initialises subsystems | logs, timers, primary/secondary mode |

> **lcore** (*logical core*) is DPDK's unit of execution: a thread created by the
> EAL and **pinned** to a logical CPU. The [official glossary][glossario] calls it
> "a logical execution unit of the processor, sometimes called a hardware thread or
> EAL thread". That is why `-l 0` results in one lcore, and not in "one available
> core": you are asking for *pinned threads*, not permission to use cores.

> **Note on the blocks in this English edition.** The measurement programs print in
> Portuguese; this document translates their **labels and captions** so the tables
> and outputs can be read here. Numbers, seals and column positions are exactly what
> the program emitted. When a command in this page greps that output, the pattern
> stays in Portuguese — it has to match what the program really prints.
Two properties of the contract matter from the start:

**It returns how many arguments it consumed, not zero on success.** A common mistake
is treating the return value as a status code. The value is there to advance `argv`:

```c
int consumidos = rte_eal_init(argc, argv);
if (consumidos < 0) {
    fprintf(stderr, "EAL: %s\n", rte_strerror(rte_errno));
    return EXIT_FAILURE;          /* STOP HERE. See the warning below. */
}
argc -= consumidos;
argv += consumidos;   /* argv now points at the APPLICATION's arguments */
```

> **The `return` is not diligence: it is mandatory.** An earlier version of this
> document carried `if (consumidos < 0) { /* rte_errno diz o motivo */ }` — with an
> empty body. On error, `consumidos` is `-1`, execution falls into the next two
> lines, and they do `argc + 1` and `argv - 1`: a pointer **before** the start of
> the array. That is undefined behaviour, and the program carries on as if all were
> well. It was pointed out in an external review that read only the text — the
> published snippet was more dangerous than the real code, because the snippet is
> what gets copied.

**It is global and not reentrant.** It cannot be called twice in the same process —
a fact that determines how this project structures its integration tests (see
section 5).

**And not every error reaches you.** The snippet above handles `consumidos < 0`, and
that branch exists — but there is a class of failure that never reaches it: **an
unknown argument terminates the process inside the EAL itself**, without returning:

```console
$ ./build/trilha/01-fundamentos/01-eal-hello/hello_dpdk -l 0 --opcao-inexistente --no-huge
ARGPARSE: unknown argument --opcao-inexistente!
$ echo $?
234
```

Note what did **not** appear: the message `Erro ao inicializar a EAL`, which is what
[`hello_dpdk.c`](hello_dpdk.c) would print in the error branch. It was not printed
because that branch did not execute. Code 234 comes from the EAL, not the
application.

The practical consequence is that **validating EAL arguments before calling it is
not possible through the EAL itself**: either the argument is right, or the process
dies. Code that must survive an invalid configuration — a supervisor trying several
configurations, for instance — has to validate beforehand, or accept that the
attempt costs a process.

**And it is not cheap.** Measured with **exactly this topic's configuration**
(`-l 0 --in-memory --no-huge`), `rte_eal_init()` costs a median of **118 ms**,
against **0.30 ms** for [`rte_eal_cleanup()`][apiealclean] — more than two orders of
magnitude between being born and dying. The number is measured by
[`docs/02-runtime-dpdk/medicoes/custo-init.c`](../../../docs/02-runtime-dpdk/medicoes/custo-init.c),
which needs one process per sample precisely because of the non-reentrancy. Keep the
consequence from now on: a DPDK process is a **long-running service**, never
something you spin up per request.

## 3. Trade-offs: the options used here

The study command is:

```bash
./build/trilha/01-fundamentos/01-eal-hello/hello_dpdk -l 0 --no-huge --file-prefix=estudo
```

| Option | What it does | Cost |
|---|---|---|
| `-l 0` | uses only lcore 0 | none, for this example |
| [`--in-memory`][optmem] | does not write runtime files to disk | prevents secondary processes |

> **The two together only work from DPDK 25.11 on, and the message does not help.**
>
> This document used to publish `-l 0 --in-memory --no-huge` as the study command,
> and it works on the reference machine's DPDK 25.11. In CI, with Ubuntu's 23.11,
> the EAL answers:
>
> ```
> EAL: Option --legacy-mem is not compatible with --in-memory
> EAL: FATAL: Invalid 'command line' arguments.
> ```
>
> Note what the message cites: **`--legacy-mem`, which nobody passed.** It is
> switched on internally by `--no-huge` — one option triggering another, and the
> conflict shows up under the implicit option's name, not the one you wrote. It is
> the kind of error that makes you look in the wrong place.
>
> **The boundary is 25.11, not 24.** The releases' `eal_common_options.c` shows
> where it sits: in **23.11, 24.03, 24.11 and 25.07** the test is
> `internal_cfg->legacy_mem && internal_cfg->in_memory` — over the **derived**
> configuration, and `--no-huge` writes `legacy_mem` into it. In **25.11** the same
> test became `CONFLICTING_OPTIONS(args, legacy_mem, in_memory)`, over the
> **typed** arguments — and `args.legacy_mem` stays zero when nobody wrote
> `--legacy-mem`.
>
> That is: what changed was not the incompatibility, it was **where it is
> checked**. A refactor moved the test from the derived configuration to the
> command line, and the conflict stopped firing. It is worth keeping as a lesson
> in method: what a program accepts is not the same as what it supports.
> <!-- retratado: interpretacao -->
>
> **What to do:** use one at a time. To run without hugepages and without privilege,
> `--no-huge` is enough. What you lose is the isolation `--in-memory` gave — no
> runtime files on disk — and you get it back with `--file-prefix`, which is what
> this page's command and this project's tests came to use.
>
> Without a distinct prefix, two simultaneous runs collide on
> `/run/user/<uid>/dpdk/rte/config` with *"Is another primary process running?"* —
> which matters because Meson runs the tests in parallel.
>
> **How this was discovered:** the first CI run in the project's history failed, and
> the test did not show the EAL's message. Only after making the test print the
> captured output did the cause appear. A release defect would never have been found
> running only on the reference machine.
| `--no-huge` | uses anonymous 4 KB memory | **more TLB misses; prevents secondary processes; not every [PMD][cPMD] accepts it** |

> **PMD** (*Poll Mode Driver*) is DPDK's NIC driver, which runs in user space and
> **polls** the card in a loop instead of waiting for an interrupt — hence the name.
> It is what replaces the kernel driver in the data path. No PMD is used in this
> topic; the term appears because the memory choice affects which of them work.

`--no-huge` deserves attention. It exists so this topic can run on any machine,
without privileges. But hugepages are not a configuration detail: they reduce TLB
misses because one 2 MB page covers the same space as 512 pages of 4 KB. In real
workloads, you want hugepages. Here we chose portability because the object of study
is the EAL's life cycle.

Without `--no-huge`, and without reserved hugepages, the EAL aborts with
`EAL: Cannot get hugepage information`.

**On this machine the scenario is different, and worth reproducing.** There are 1024
hugepages reserved, but `/dev/hugepages` belongs to `root` with mode `0755`. The
failure is therefore one of **permission**, not of absence:

```console
$ ./build/trilha/01-fundamentos/01-eal-hello/hello_dpdk -l 0
EAL: Detected CPU lcores: 24
EAL: Detected NUMA nodes: 1
EAL: Detected shared linkage of DPDK
EAL: Selected IOVA mode 'VA'
EAL: get_seg_fd(): open '/dev/hugepages/rtemap_0' failed: Permission denied
EAL: Couldn't get fd on hugepage file
EAL: error allocating rte services array
EAL: rte_service_init() failed
Error initialising the EAL: Cannot allocate memory
```

Two distinct messages, two distinct causes: one says there **is no** hugepage; the
other, that it **cannot be opened**. Confusing the two leads you to reserve more
memory when what is missing is permission.

And there is a third case, which surprises: `--in-memory` **alone**, without
`--no-huge`, works — and uses a real hugepage, obtained via `memfd` without needing
access to `/dev/hugepages`. That is what
[§4.5 of module 02](../../../docs/02-runtime-dpdk/README.en.md#45-what-switches-the-multiprocess-model-off-without-warning)
demonstrates. For file-backed hugepages, without running as `root`, the project
ships [`scripts/preparar-hugepages.sh`](../../../scripts/preparar-hugepages.sh).

> **The two options cost the same thing, and only one warns.** `--in-memory`
> declares the effect in the EAL's own help (`disables secondary process support`).
> `--no-huge` declares nothing: the primary process comes up normally and it is the
> **secondary** that fails later, with `EAL: Cannot init memory` — a message that
> does not mention the responsible option. The reason is the same in both cases:
> with no file backing the memory, there is nothing for a second process to map. The
> demonstration of both failures is in
> [§4.5 of module 02](../../../docs/02-runtime-dpdk/README.en.md#45-what-switches-the-multiprocess-model-off-without-warning).

> **Where the runtime files live.** Almost every text says `/var/run/dpdk`, and for
> `root` that is right. For an ordinary user, the EAL uses the session's runtime
> directory: `$XDG_RUNTIME_DIR/dpdk/<prefixo>/`. Anyone looking in the wrong place
> concludes the EAL wrote nothing. See
> [§3.2 of module 02](../../../docs/02-runtime-dpdk/README.en.md#32-what-the-eal-leaves-on-the-host).

## 4. Implementation

The code is in [`hello_dpdk.c`](hello_dpdk.c). It performs the minimal cycle:
initialise, report what the EAL decided, and shut down with
[`rte_eal_cleanup()`][apiealclean].

Build and run:

```bash
./scripts/build-all.sh
./build/trilha/01-fundamentos/01-eal-hello/hello_dpdk -l 0 --no-huge --file-prefix=estudo
```

Expected output:

```
DPDK Academy: EAL initialised successfully.
DPDK version: DPDK 25.11.0
Lcores available: 1 (main lcore: 0)
NUMA node of the main lcore: 0
Arguments left for the application: 0
```

The lines beginning with `EAL:` come from the layer itself, **they are not errors**.
Note the third line of the application's output: the machine has 24 cores, but
[`rte_lcore_count()`][apilcorecount] answers `1`, because `-l 0` asked for only one.
The EAL does not use what exists; it uses what was asked for.

### Exercises

1. Run with `-l 0-3`. How many lcores does the EAL report?
2. Run with `-- a b c`. What changes in the last line, and why?
3. Run with a non-existent option. What is the exit code — and why does the
   **application's** error message not appear?
4. Swap `--no-huge` for `--in-memory`. Does it work on your machine? If so, where
   did the memory come from — and why did it not need `/dev/hugepages`?
5. Now pass **both together**: `--in-memory --no-huge`. On a release before DPDK 25.11
   this fails, and the message cites `--legacy-mem`, which you did not pass. Check
   your version with `pkg-config --modversion libdpdk` before concluding anything
   about the result.
6. Remove all the memory options, leaving only `-l 0`. The EAL will probably fail.
   Does the message speak of a **missing** hugepage or an **inaccessible** one? The
   two require different fixes.

## 5. Validation

This topic has **only an L2 test**, and the absence of L1 is intentional: there is no
pure logic to isolate — the topic *is* the runtime's initialisation.

```bash
./scripts/test-all.sh l2
```

The test ([`tests/l2_run.sh`](tests/l2_run.sh)) checks the command-line contract:
that `-l 0` results in exactly one lcore, that arguments after `--` reach the
application, and that an invalid option makes the program exit with a non-zero code.

It is a script, and not a GoogleTest case, precisely because of section 2's property:
since `rte_eal_init()` cannot be called twice in the same process, testing *argument
variations* requires one process per variation.

## 6. When it goes wrong

> **This topic's question:** what happens when the EAL does **not** come up?

[Section 2](#2-mechanism-what-rte_eal_init-does) already showed that there are two
failure paths and that only one of them reaches your code. This section closes what
remains: **running them side by side**, seeing what each returns, and knowing how
much of that is dependable.

### 6.1 The two paths, side by side

```console
$ ./build/trilha/01-fundamentos/01-eal-hello/hello_dpdk -l 999
EAL: No valid lcores in core list
EAL: invalid coremask or core-list parameter, please check specified cores are part of 0-23
EAL: Error parsing command line arguments.
Error initialising the EAL: Invalid argument
$ echo $?
1
```

The last line is the **application's** — it is [`hello_dpdk.c`](hello_dpdk.c)'s
`fprintf` printing `rte_strerror(rte_errno)`. Compare with path A from section 2,
where it does not appear:

| | A — `--opcao-inexistente` | B — `-l 999` |
|---|---|---|
| `rte_eal_init()` | does not return | returns `-1` |
| Your `if (consumidos < 0)` | **does not execute** | executes |
| Exit code | 234, chosen by the EAL | `EXIT_FAILURE`, chosen by you |
| Diagnosis available | only what the EAL printed | `rte_errno`, readable by you |

The operational consequence: **a non-zero exit code from a DPDK process may not be
yours**. A supervisor that treats "≠ 0" as "the application failed" gets the
diagnosis wrong on path A, where the application never started.

### 6.2 Where the 234 comes from

It is not arbitrary: it is `-EINVAL` truncated to 8 bits, because the shell only sees
the low byte of what the process returns.

```console
$ python3 -c "print((-22) & 0xFF)"
234
```

### 6.3 How this is captured — and what the test does not guarantee

The [L2 test](tests/l2_run.sh) exercises **both paths**, and the separation cost an
earlier version: it checked only "code ≠ 0", which is true in both and therefore
distinguishes nothing. Today it asserts the exact code and, on path A, also asserts
the **absence** of the application's message — the proof that the error branch did
not run.

> **What that test ties to a release.** The `234` and the `unknown argument` message
> come from `librte_argparse`, not from the EAL — checked with `strings`: the string
> exists in `librte_argparse.so` and not in `librte_eal.so`. That library only exists
> from **DPDK 24.03** on. On an earlier release path A exits with a different code
> and a different message, and the test fails **red with no defect in the program**.
> This machine runs DPDK 25.11; if yours is older, that is the reason.

## 7. Limitations

- No NIC is involved. The EAL discovers devices, but nothing is configured.
- With `--no-huge`, the memory behaviour does not represent production.
- `rte_eal_cleanup()` frees the EAL's resources, but in a real application correct
  shutdown also involves stopping and closing the ports before that.

## 8. Where to go from here

Two paths, and the order between them is yours:

**Go deeper into the runtime** — [Module 02: DPDK runtime](../../../docs/02-runtime-dpdk/README.en.md).
This topic shows the EAL coming up; module 02 treats it as a system: how much
initialisation costs and why, the memory model behind the reservation, primary and
secondary processes sharing memory without copying, the lcore state machine and the
IOVA mode. It is where `--in-memory` and `--no-huge`, used here as a portability
shortcut, appear with the price they charge.

**Continue the practice** — [02 — mempool, ring and batch processing](../02-mempool-ring/),
where the memory reserved by the EAL starts being genuinely used.

[apiealinit]: https://doc.dpdk.org/api/rte__eal_8h.html#a5c3f4dddc25e38c5a186ecd8a69260e3
[apiealclean]: https://doc.dpdk.org/api/rte__eal_8h.html#a7a745887f62a82dc83f1524e2ff2a236
[apilcorecount]: https://doc.dpdk.org/api/rte__lcore_8h.html#a1728dc7f14571ba778d3b5b41aa09283

[cEAL]: https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html
[cHuge]: https://doc.dpdk.org/guides/linux_gsg/sys_reqs.html
[cPMD]: https://doc.dpdk.org/guides/prog_guide/ethdev/ethdev.html

[glossario]: https://doc.dpdk.org/guides/prog_guide/glossary.html

[optdebug]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#debugging-options
[optlcore]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#lcore-related-options
[optmem]: https://doc.dpdk.org/guides/linux_gsg/linux_eal_parameters.html#memory-related-options
