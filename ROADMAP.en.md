# Project roadmap

*Leia em [português](ROADMAP.md).*

## Strategic view

This project aims to build a concrete and didactic base for professional study of
DPDK, covering everything from the fundamentals to high-performance data pipeline
architectures.

## Stages

### Stage 1 — Conceptual base
- Linux, memory, cache, NUMA
- user space and kernel space
- networks and packets
- performance and latency

### Stage 2 — DPDK runtime
- [EAL][cEAL]
- lcore
- [hugepages][cHuge]
- pools and queues
- packet lifecycle

### Stage 3 — Fundamental modules
- mempool
- ring
- mbuf
- burst processing
- producer/consumer

### Stage 4 — Software architecture
- data pipeline
- modularisation
- hot path and control path
- limits and trade-offs

### Stage 4.5 — RX/TX and ethdev

Inserted between 4 and 5 after a 2026-09-10 review found that the ROADMAP jumped
from level 5 to level 8: **there was no stage committing to
`rte_eth_dev_configure()`**, although four documents defer questions to it and the
[plan](docs/plano-estudo-dpdk.en.md) promises the *offloads* as a level 6 deliverable.
It was possible to execute the whole roadmap without ever configuring a port.

It comes before Stage 5 by dependency, not by preference: *backpressure* is only
measured with a real packet source, as the
[pipeline module](trilha/02-pipeline/README.en.md) itself argues, and the performance
comparison deferred by four documents needs RX/TX to exist.

- port and queue configuration, descriptors, `rx_burst` / `tx_burst`
- the partial return of TX and the ownership inversion it creates — in the ring what
  **did not** fit is yours; in TX what **was accepted** is no longer yours
- `stats` and `xstats`: where each loss is accounted for
- *offloads* and [`rte_flow`][cflow] — assigned to this stage, and no longer orphaned
- the failure question from the [axis](#stage-75--failure-axis-executed-on-the-written-modules):
  what happens when there is no mbuf to receive into

**This machine's hardware is adequate, contrary to what the material published.**
The review checked the three recorded impediments and none holds up:

| Published impediment | Verification |
|---|---|
| the NIC would require `--vdev` for lack of a PMD | DPDK 25.11 ships `librte_net_r8169.so`, and the pair `10ec:8125` is in the PMD's image |
| the shared IOMMU group would complicate `vfio-pci` | the other member of group 17 is a PCIe bridge on `pcieport`, a driver VFIO allows — the group has a single *endpoint* |
| binding would take down access to the machine | `enp8s0` is DOWN and not connected; the default route goes over Wi-Fi |

**Probed end to end** with `scripts/diagnostico-nic.sh`, which binds, runs `testpmd`
and returns the card to the kernel: the PMD claims the device
(`Driver name: net_r8169`, firmware `0x00000b99`). The doubt is settled.

The probing revealed the limit that actually governs, and **it is not the bus**: the
card exposes **one** RX queue and **one** TX queue. That does not prevent the
single-queue path — port, descriptors (64 to 4096), `rx_burst`/`tx_burst`, partial
return, mbuf ownership — but it does prevent RSS and per-queue scaling, which is the
part of RX/TX that matters most in a data plane. `--vdev=net_null` comes to serve for
what the hardware **does not** cover (multi-queue), and not as a low-quality
substitute.

**Hardware on the way:** a **Mellanox ConnectX-4 Lx 25 GbE dual-port SFP28**,
expected within weeks. It closes the gaps in multi-queue, RSS, *offloads*, `rte_flow`
and line rate, and also unblocks Stage 6 by bringing SR-IOV. Its arrival is a
**revision** of this stage and of the capability table in
[01-rx-tx-burst](trilha/02-pipeline/01-rx-tx-burst/README.en.md), not a new module.

And it changes the procedure: the `mlx5` PMD is **bifurcated** — kernel and DPDK
manage the same device — so it uses neither `vfio-pci` nor
`scripts/preparar-nic.sh`. It requires `rdma-core`, which on this machine is
incomplete (`librdmacm` missing). The didactic gain is having **two driver models**
to teach, instead of one.

Still true are the PCIe Gen2 x1 ceiling (~0,5 GB/s, which prevents 10 GbE line rate)
and the `down` link for lack of a cable — you can configure the port and read
counters, not receive traffic. And this is the first topic in the track that
**requires privilege**: `/dev/vfio/17` is `root:root`.

[cflow]: https://doc.dpdk.org/guides/prog_guide/ethdev/flow_offload.html

### Stage 5 — Benchmarking and quality
- perf and VTune
- sanitizers
- clang-tidy and clang-format
- tests and CI

### Stage 6 — Virtualisation
- SR-IOV and *Virtual Functions*
- `virtio-net` and `vhost-user`
- containers and what changes in them

### Stage 7 — Final project
- a working DPDK app
- comparison with the alternatives: C++23 over sockets, and AF_XDP
- documentation and performance analysis

### Stage 7.5 — Failure axis (executed on the written modules)

An editorial review on 2026-09-09 identified the material's biggest gap: it answers
*"what happens when everything works?"* very well and almost nothing of **"what
happens when something goes wrong?"**

The evidence was in the structure of the documents themselves: the five written
modules **all** had a *Limitations* section, and **none** had a section answering
what the software does when the resource runs out, the queue fills or the
neighbouring process dies.

They are different things, and that is why the first did not cover the second:
*Limitations* records **what the numbers do not authorise you to conclude**; the
failure axis records **what the system does outside the happy path**.

Today all five have both — that is what this stage delivered, and it is checked like
this:

```bash
grep -l '^## .*Limitaç'          docs/0*/README.md trilha/01-fundamentos/*/README.md | wc -l  # 5
grep -l '^## .*Quando dá errado' docs/0*/README.md trilha/01-fundamentos/*/README.md | wc -l  # 5
```

The fix is **not** to create a parallel track of critical systems, nor to adopt FMEA
and fault trees, which are functional-safety instruments (IEC 61508) out of
proportion to a study guide. It is to add a recurring question to each module,
answered with an experiment, in the same pattern as the rest.

**In the modules that already exist.** This is where the stage starts, because the
question can be answered today, with code that is already written:

| Module | Failure question | The experiment that answers it |
|---|---|---|
| [Fundamentals §11](docs/01-fundamentos/README.en.md#11-when-it-goes-wrong) | what happens when the per-packet budget is exceeded? | [`orcamento-estourado.c`](docs/01-fundamentos/medicoes/orcamento-estourado.c) — sweeps ρ from 0,50 to 1,58 and shows that the tail degrades before the median |
| [Runtime §10](docs/02-runtime-dpdk/README.en.md#10-when-it-goes-wrong) | what happens when the primary dies with secondaries alive? | [`l3_primario_morre.sh`](docs/02-runtime-dpdk/medicoes/tests/l3_primario_morre.sh) — SIGKILL on the primary; 7 assertions about what the secondary does **not** notice |
| [Mempool §6](docs/03-mempool-ring-mbuf/README.en.md#6-when-it-goes-wrong) | what happens when the pool runs out mid-batch? | [`pool-esgotado.c`](docs/03-mempool-ring-mbuf/medicoes/pool-esgotado.c) — the all-or-nothing step, and rule 4 confronted and corrected |
| [Topic 01 §6](trilha/01-fundamentos/01-eal-hello/README.en.md#6-when-it-goes-wrong) | what happens when the EAL does not come up? | [`tests/l2_run.sh`](trilha/01-fundamentos/01-eal-hello/tests/l2_run.sh) — both paths, and only one reaches your code |
| [Topic 02 §6](trilha/01-fundamentos/02-mempool-ring/README.en.md#6-when-it-goes-wrong) | what does the **partial** return oblige you to do? | [`pipeline_ring_vazado`](trilha/01-fundamentos/02-mempool-ring/pipeline_ring.c) — the same source without the return, which the suite requires to fail |

**In the modules that do not yet exist**, the question is born with the text, not
afterwards — it is cheaper to write that way than to come back and add it:

| Pending module | Failure question |
|---|---|
| [RX/TX](trilha/02-pipeline/01-rx-tx-burst/README.en.md) | what happens when there is no mbuf to receive into? |
| [Pipeline](trilha/02-pipeline/README.en.md) | how does backpressure reach the NIC, and what does it bring down first? |

Each one leads naturally to *overload*, *starvation*, exhaustion, detection,
isolation, degradation and recovery — with no imported formalism.

**Definition of done — met for the five written modules.** The rule was to answer
each question **with a runnable experiment** — a program, a measured number and a
test — never in prose: describing a failure mode without provoking it is the kind of
folklore the rest of the material refuses to repeat.

Two results of the execution deserve recording, because they changed the material:

- **Sizing rule 4 was badly stated.** The DPDK documentation says that objects
  outside the cache multiple *"will never be used"*; `pool-esgotado.c` measures a
  single consumer obtaining **all** of them, via the `driver_dequeue` path. The rule
  holds for efficiency, not for reachability, and
  [`sizing.h`](docs/03-mempool-ring-mbuf/medicoes/sizing.h) was corrected. It is the
  second piece of folklore this material brings down by measuring — and the first
  coming from a primary source, not from oral culture.
- **Sixteen assertions were not being executed.** The two multiprocess L3 tests
  required `DPDK_ACADEMY_HUGE_DIR` exported by hand and exited with 77 on a machine
  that had a writable hugetlbfs. Skipping for a missing requirement is correct;
  skipping for a missing environment variable is coverage lost in silence. Solved by
  autodetection in
  [`lib-hugetlbfs.sh`](docs/02-runtime-dpdk/medicoes/tests/lib-hugetlbfs.sh).

Alongside that, three items from the same review, accepted and pending:

- **measurable requirements** before the benchmark (throughput, p99, jitter, loss,
  startup time), so that measuring stops being "let's see what we get" and becomes
  "does the system satisfy the requirement?";
- **fault injection** as a validation technique, alongside the L1/L2/L3 tests. Topic
  02's negative test is already an instance of this and serves as the model:
  `pipeline_ring_vazado` is the same source with the partial-return release removed,
  and the suite **requires it to fail** — a check that has never failed is
  indistinguishable from one that never fires;
- **security as an architectural property** — malformed packet, resource exhaustion,
  privilege boundary, VFIO — and not only the absence of buffer overflows.

What was **refused** in the same review, and why:

| Refused | Why |
|---|---|
| the formalism of FMEA and fault-tree analysis (FTA) | they are functional-safety instruments (IEC 61508), sized for systems where failure kills. In a study guide they cost more ceremony than they teach, and shift the effort from the question ("what breaks?") to filling in the spreadsheet |
| a mandatory 16-section template per experiment | it forces short and long modules into the same mould. The path already declared in [overview §3](docs/00-visao-geral/README.en.md#3-the-method) — problem, mechanism, trade-offs, implementation, measurement, comparison, decision — does the job without counting sections |
| FACT / MEASUREMENT / INFERENCE tagging throughout the text | the distinction is necessary and **is already made**, in the language, by the convention in [overview §4](docs/00-visao-geral/README.en.md#4-how-to-read-the-numbers). Tagging every sentence trades reading for bureaucracy and still gives false precision: the label becomes a ritual and stops being thought about |

### Stage 8 — Adaptation for international reach
> **Deliberately the last stage.** Decided on 2026-09-09: adaptation into English
> only begins after the Portuguese content is mature, to avoid loss of content and
> rework.

What is decided about **how** to do it, when the time comes:

- **~~Deliberate asymmetry, not a bilingual project.~~ FULL PARITY**, decided on
  16/09/2026. The didactic body in both languages, document by document.

  > **The earlier decision was the asymmetry, and the reason against parity remains
  > true** — it is three items below, and it has not been erased: an outdated English
  > version makes the reader conclude that the numbers are not trustworthy.
  >
  > What changed was not the assessment of the risk; it was the **countermeasure**.
  > While parity depended on discipline, asymmetry was the safe choice. With parity
  > **machine-verified** — every module needs its English counterpart, and no number
  > published in English may be missing from the Portuguese, with mutation measured —
  > the risk stops depending on someone remembering.
  >
  > What the verification **does not** cover remains the real risk: whether the
  > English text *says the same thing*. That is semantics, no syntactic pattern
  > decides it, and it is declared in the verifier's header. The guarantee there is
  > human, with a date.
- **In English:** `README.en.md` at the root and **one `README.en.md` per document**,
  code identifiers, and the repository's `description` + `topics`. **Done on
  2026-09-10, except `description`/`topics`,** which depend on the repository
  existing remotely. The identifiers migrated in a pass verified by the suite: the
  programs' output and the prose remain in Portuguese, and that is what the asymmetry
  meant in practice. GoogleTest case names stayed in Portuguese because they are
  **prose** — they are sentences read in the test report
  (`ResultadoIndependeDoLote.DezPacotesSempreSomam695Bytes`), not symbols anyone
  calls.
- ~~**Do not translate** the didactic prose.~~ **Revoked on 16/09/2026** — see the
  first line of this list. The argument remains on record because it remains correct,
  and it is what defines what the verification needs to cover: the value of this
  material is the measured numbers, and an outdated English version makes the reader
  conclude that *the numbers are not trustworthy*, not that the translation is
  behind. That is why parity came in together with the rule that checks it, and not
  before it.
- **Discarded:** `docs/pt-br/` + `docs/en/` — the `docs/` folder is a build tree,
  with its own `meson.build` and a good part of the tests registered there, and the
  topics' READMEs live in `trilha/` next to the code, by the rule of keeping document
  and code in the same topic. Also discarded were automatic translation by Action and
  a static site, for now.

  > This sentence published "16 of the 23 tests" until 16/09/2026. Both numbers aged
  > without anyone noticing — the suite went from 23 to 52 — and no verifier checked
  > them: they are neither a skeleton census nor an arithmetic sum. The count was
  > removed because it did not support the argument, which is about **where** things
  > live. A number nobody re-checks is a scheduled retraction.
- **Reopen a complete `docs/en/`** only if a second person appears who takes on
  maintaining the English.

**Prerequisite for starting this stage:** the Portuguese content needs to be mature.
None of the 21 documents is a skeleton: the last one, `trilha/04-projeto-final/`,
became content on 16/09/2026. What is still missing there is the end-to-end
application, and the document says so in its first section instead of declaring
itself finished.

> Counts age in silence, and these have aged TWICE already: on 15/09/2026 all four
> numbers in this sentence were wrong at the same time, with this very warning right
> below. Declared scepticism checks nothing — which is why the sentence came to be
> re-checked by
> [`verificar-autodescricao.py`](ferramental/qualidade/verificar-autodescricao.py)
> (rule 3), which runs in the `l1+docs` suite and goes red when the disk diverges
> from the text. To re-check it yourself, these are the same commands it runs:
>
> ```bash
> grep -rlE '^> \*\*Esqueleto\.\*\*' docs trilha --include='*.md' | wc -l   # esqueletos
> find docs trilha -name '*.md' ! -name '*.en.md' | wc -l                  # documentos
> ```
>
> The `! -name '*.en.md'` is not a nicety. Since the parity of 16/09/2026 every
> document has an English counterpart, and counting it would double the total without
> there being a new document: without the filter this command returns 37 for 21
> documents. The verifier applies the same cut, and that is why the two agree.

## Final goal

To produce technical and pedagogical material capable of serving as a reference for:

- beginners in DPDK
- software and systems professionals
- students interested in high performance, networking and architecture
- people wishing to go deeper into C++23 and software engineering for the data plane

[cEAL]: https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html
[cHuge]: https://doc.dpdk.org/guides/linux_gsg/sys_reqs.html
