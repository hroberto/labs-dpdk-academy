# Study plan: DPDK for beginners and advanced readers

*Leia em [português](plano-estudo-dpdk.md).*

## Goal

This plan is designed to build a solid base in DPDK, focused on:

- incremental learning
- technical depth
- practice with runnable code
- a connection with C++23 and software engineering
- a critical view of architecture, latency, throughput and operational cost

## Philosophy

DPDK should not be seen merely as a networking library. It is a set of mechanisms
for:

- controlling memory predictably
- reducing kernel overhead
- exploiting hardware and NUMA consciously
- sizing packet and data-processing pipelines

The study should advance along three simultaneous dimensions:

1. theory and architecture
2. DPDK's mechanism and API
3. practice with benchmarking, measurement and a project

## Structure of the plan

### Level 1 — System fundamentals

Goal: prepare the ground for understanding DPDK.

Topics:
- Linux, user space vs kernel space
- virtual and physical memory
- cache, NUMA, contiguous memory
- processes, threads, CPU affinity
- I/O, polling and interrupts
- notions of packet processing

Deliverables:
- a reading of memory and CPU architecture
- a summary of the differences between kernel and user-space networking
- an analysis of the polling vs interrupt trade-offs

### Level 2 — Networking and data-plane fundamentals

Goal: understand the problem DPDK solves.

Topics:
- high-rate networks and packets
- throughput, loss rate, latency, jitter
- NIC, DMA, ring buffers, queues
- packet lifecycle: RX, parse, decision, TX
- the overhead of a syscall, kernel context and operational cost

Deliverables:
- a network pipeline diagram
- a comparison between the traditional stack and a high-performance data
  architecture

### Level 3 — EAL and the runtime environment

Goal: master DPDK's execution base.

[EAL][cEAL] stands for Environment Abstraction Layer. It is the layer that prepares
the process to run in user space with direct control over memory, threads, I/O and
system resources. The EAL abstracts the host's details and lets DPDK configure CPU,
memory, NUMA, [hugepages][cHuge] and drivers without depending on the kernel's
traditional model.

Topics:
- [`rte_eal_init()`][apiealinit]
- EAL arguments
- hugepages
- lcores (*logical cores*): threads created by the EAL and pinned to logical CPUs
- counting and selecting lcores
- sockets and NUMA
- initialisation and cleanup
- using `--in-memory` in a controlled environment

Deliverables:
- a minimal working program
- reading the logs and the runtime's behaviour
- an analysis of the environment and host requirements
- an understanding of the EAL's role at the start of a DPDK program's execution

### Level 4 — Mempool, mbuf, ring and the data cycle

Goal: understand the fundamental blocks of DPDK's data model.

Topics:
- [`rte_mempool`][guiamempool]
- [`rte_ring`][guiaring]
- [`rte_mbuf`][guiambuf]
- lifetimes and ownership
- allocation-free hot paths
- batch and burst processing
- returning objects to the pool

Deliverables:
- a producer/consumer example with a ring
- an object-pool example with the complete usage cycle
- a comparison with pure C++23 in an in-memory pipeline

### Level 5 — Processing pipeline and software design

Goal: design data software with architectural discipline.

Topics:
- modular software
- separation of responsibilities
- processing logic and I/O
- backpressure and queues
- synchronisation and concurrency
- design by batch
- hot path vs control path

Deliverables:
- a packet pipeline with well-defined stages
- an analysis of bottlenecks
- a design of the module architecture

### Level 6 — RX/TX, I/O and hardware-aware design

Goal: advance into DPDK's I/O layer and understand the hardware decisions.

Topics:
- RX/TX burst
- network interfaces
- batched enqueue/dequeue
- NIC, queues and drivers
- the use of descriptors and memory locality
- trade-offs between batching, latency and throughput

Topics of **offloading to the NIC** — the work that never costs a CPU cycle because
the card already did it:
- RSS (*Receive Side Scaling*): multiple hardware queues fed by a 5-tuple hash, one
  per lcore, with no coordination in software
- checksum offloading (RX and TX)
- TSO (*TCP Segmentation Offload*) and LRO (*Large Receive Offload*)
- [`rte_flow`][guiaflow]: programming classification, filtering, mirroring and
  redirection rules in the NIC's own switch, before the packet reaches the CPU
- per-device capabilities: [`rte_eth_dev_info_get()`][apidevinfo] and the
  negotiation of which offloads are available

Deliverables:
- the architecture of a simple forwarder
- a comparative benchmark with batch variants
- a survey of the offloads supported by the available NIC, with what changes in the
  code when each is enabled

> **Constraint of the reference environment.** This machine's NIC (Realtek RTL8125)
> supports *checksum offload* and TSO, but reports `large-receive-offload: off
> [fixed]` and `receive-hashing: off [fixed]` — that is, it does **not** do LRO or
> RSS. RSS and `rte_flow` can be studied and coded here, but not measured: for that
> you need a server NIC (Intel E810/X710, NVIDIA ConnectX). Check yours with
> `ethtool -k <iface>`.

### Level 7 — NUMA, cache and real performance

Goal: learn to think about performance correctly.

Topics:
- NUMA awareness
- memory locality
- cache lines and **false sharing** (the most common defect of the per-lcore model)
  — see [01-fundamentos §4.2.1](01-fundamentos/README.en.md)
- contention
- CPU affinity and contention between SMT threads of the same core
- prefetch and the use of contiguous data
- the effect of data stratification on the CPU

Topics of the **bus**, which is left out of the account when you look only at CPU
and memory — already covered in [01-fundamentos §6.2](01-fundamentos/README.en.md):
- PCIe throughput by generation and width, and the ceiling it imposes before any
  software
- TLP (*Transaction Layer Packet*) overhead for small frames
- tuning *Max Payload Size*, *Max Read Request Size* and *Relaxed Ordering*
- IOTLB: the lack of translation on the device side, and why hugepages benefit the
  NIC too

Deliverables:
- a perf analysis of the pipeline
- documentation of memory and CPU observations
- a comparison between multiple processing strategies

### Level 8 — Observability and quality

Goal: go beyond functional code.

Topics:
- `perf`, `VTune`, `gprof`
- sanitizers
- `clang-tidy` and `clang-format`
- unit and integration tests
- benchmark automation
- quality and maintenance in high-performance software

Topics of **memory safety in user space**, a direct consequence of giving up the
kernel's isolation:
- what is lost: in user space, an over-read while parsing a header corrupts the
  **entire** process's memory — including the mempool and other lcores' state. There
  is no barrier between the parser and the rest
- the tools' blind spot: AddressSanitizer intercepts the system allocator, but
  `rte_mempool` objects live in hugepages managed by the EAL and fall outside its
  reach (see [tooling §5](00-visao-geral/ferramental.en.md))
- validating a malformed packet on the hot path: check the length before indexing,
  never trust a size field coming from the network, and do it within the cycle
  budget
- defence in depth where the sanitizer does not reach: `rte_mempool` with debug
  *cookies* (`RTE_LIBRTE_MEMPOOL_DEBUG`), guard pages, and auditing of the parsing
  points

Deliverables:
- a perf collection script
- a quality checklist for DPDK code
- instructions for a reproducible benchmark
- a defensive parsing routine with measured cost, compared to the naive version

### Level 9 — Virtualisation and the path to the cloud

Goal: leave bare metal, which is where DPDK applications rarely run in production.

Topics:
- SR-IOV: dividing one physical NIC into *Virtual Functions* handed directly to
  virtual machines or containers, each with its own queues
- `virtio-net` and `vhost-user`: the high-speed path between guest and host, without
  going through emulation
- Open vSwitch with DPDK as a data-plane switch
- what changes in a container: shared hugepages, `--socket-mem`, `/dev/vfio`
  permissions, and why privileges are usually required
- memif and virtual PMDs for composing topologies without dedicated hardware

Deliverables:
- a lab with two DPDK processes talking over `virtio`/`vhost-user`
- an analysis of the additional cost of each virtualisation layer

> Practicable on the reference machine: the `virtio`, `vhost`, `memif` and `net_tap`
> PMDs are present in the installation. SR-IOV requires a NIC with VF support.

### Level 10 — The final project and the alternatives to DPDK

Goal: consolidate the knowledge and place DPDK among the real options.

The comparison with **pure C++23** (the kernel stack via sockets) shows the cost of
the operating system's abstractions. But the comparison the industry actually makes
today is another: **DPDK against [AF_XDP][cAfxdp]**.

AF_XDP bypasses the network stack **while keeping the kernel driver**. It requires no
[PMD][cPMD] in user space, does not remove the NIC from the operating system,
preserves the security model — and delivers a significant fraction of the
performance. It is the middle ground that did not exist when DPDK was created, and
ignoring it makes the analysis dated.

Topics:
- a complete pipeline in DPDK
- an equivalent pipeline in pure C++23 over sockets — the cost of the kernel path
- an equivalent pipeline in **AF_XDP** — kernel bypass without giving up the kernel
- axes of comparison: throughput, latency, development cost, operation, security and
  what each approach demands of the environment
- DPDK's own `net_af_xdp` PMD, which allows using AF_XDP underneath DPDK's API — and
  what that reveals about where the cost is

Deliverables:
- a runnable project with documentation
- a benchmark of the three approaches, with a declared methodology
- an architectural analysis: when each one is the correct choice, and why

#### How AF_XDP works

It is worth having the mechanism clear before comparing, because the difference from
DPDK lies precisely in it. AF_XDP is a family of Linux sockets, introduced in kernel
4.18, that delivers packets to user space **without detaching the NIC from the
operating system**. Instead of bypassing the kernel, it opens a fast path *inside*
it.

**1. The trigger, in the driver.** On receiving a packet, the kernel runs an eBPF
program at the lowest point of the driver — before allocating an `sk_buff`, before
the stack. If the program returns `XDP_REDIRECT`, the packet diverts straight to an
`AF_XDP` socket.

**2. UMEM: shared memory.** Application and kernel share a pre-allocated region, the
**UMEM**. It is what allows dispensing with the copy between kernel and user — the
same principle as DPDK's mbufs in hugepages, with a different implementation.

**3. Four lock-free queues**, exchanging descriptors instead of data:

```mermaid
sequenceDiagram
    autonumber
    participant A as application
    participant K as kernel

    Note over A,K: UMEM — shared region; the queues exchange DESCRIPTORS, not data

    A->>K: Fill Ring — empty UMEM buffers
    K-->>A: RX Ring — received packets
    A->>K: TX Ring — packets to transmit
    K-->>A: Completion Ring — freed buffers
```

**The four queues exchange descriptors, not packets.** The data stays in the UMEM the
whole time; what crosses the boundary is the index of whoever owns it now — which is
exactly what dispenses with the copy.

The symmetry with `rte_ring` is no coincidence: it is the same lock-free
producer/consumer pattern from [Level 4](#level-4--mempool-mbuf-ring-and-the-data-cycle),
here crossing the user/kernel boundary instead of cores.

#### DPDK and AF_XDP side by side

| Criterion | DPDK | AF_XDP |
|---|---|---|
| Relationship with the kernel | ignores it completely | a fast path inside it |
| Driver | an exclusive user-space PMD | Linux's standard driver |
| The NIC in the system | disappears (`vfio-pci`) | remains visible and manageable |
| Non-critical traffic | the application handles **everything** | eBPF filters; the rest goes on to the native stack |
| Tooling | loses `tcpdump`, `iproute2` on the data path | `ip`/`ethtool` remain; see the caveat |
| Learning curve | high: hugepages, NUMA, binding | medium: the sockets API |
| Performance ceiling | higher | lower, but close with zero-copy |

Two caveats the table alone hides:

**Zero-copy depends on the driver.** Without native support, AF_XDP falls back to
*copy mode* and to generic XDP, which runs the eBPF after the `sk_buff` allocation —
losing most of the gain. Verifiable in the driver's module:

```bash
m=$(modinfo -n r8169)                      # path to the module
tmp=$(mktemp); zstdcat "$m" > "$tmp"       # DECOMPRESSING first is mandatory
nm "$tmp" | grep -c 'xdp_'                 # 0 aqui; 37 no i40e
rm -f "$tmp"
```

The decompression is not a detail: kernel modules come compressed, `nm` refuses the
file and `grep -c` returns `0` — the same answer a driver genuinely without support
would give. The direct form over the `.ko.zst` answers `0` for **every** driver on
the system, including those that do have support. The complete table, with the three
columns that separate "no XDP" from "XDP, no zero-copy", is in the
[final project](../trilha/04-projeto-final/README.en.md#4-af_xdp-the-decision-taken).

**`tcpdump` does not see what was redirected.** The interface remains manageable, and
traffic that is *not* redirected goes through the stack normally — but the packet the
eBPF diverted never reaches the point where `tcpdump` listens. The real advantage is
traffic coexistence, not total observability.

> **Practicability on the reference machine — and the honest limit.** The
> `net_af_xdp` PMD is present, with `libxdp` 1.6.2, `libbpf` 1.6.3 and kernel 7.0.
> But the NIC is a Realtek RTL8125 with the `r8169` driver, which **has no native XDP
> or zero-copy support** — verified: zero `xsk_*` symbols in the module, against 7 in
> `i40e`, 7 in `ice` and 8 in `ixgbe`. Here AF_XDP runs in generic mode with copying,
> which serves to learn the API and see the flow working, **but not to measure**.
> Level 10's performance comparison requires a NIC with native XDP — Intel
> i40e/ice/ixgbe or NVIDIA mlx5.

#### The hybrid case that reveals where the cost is

DPDK includes the `net_af_xdp` PMD, which allows writing the application with
`rte_mbuf` and `rte_ring` as usual, but with AF_XDP as the *backend* instead of a
hardware PMD. Comparing that configuration against DPDK over `vfio-pci` **isolates**
the cost: same API, same data structures, only the path to the NIC changes. It is the
most informative of the three experiments.

## Mapping to the track

- [../docs/00-visao-geral](../docs/00-visao-geral) -> overview and context
- [../docs/01-fundamentos](../docs/01-fundamentos) -> levels 1 and 2
- [../docs/02-runtime-dpdk](../docs/02-runtime-dpdk) -> level 3
- [../docs/03-mempool-ring-mbuf](../docs/03-mempool-ring-mbuf) -> level 4
- [../trilha/01-fundamentos](../trilha/01-fundamentos) -> implementation of levels 1 to 4
- [../trilha/02-pipeline](../trilha/02-pipeline) -> levels 5 and 6
- [../trilha/03-performance](../trilha/03-performance) -> level 8
- virtualisation (level 9) -> module not yet created
- [../trilha/04-projeto-final](../trilha/04-projeto-final) -> level 10

## Study strategy

- Study one topic at a time
- Always connect theory, API and benchmark
- Read the DPDK documentation as a reference, but validate it in runnable examples
- Implement small modules and study a complete pipeline
- Compare against C++23 versions to build critical engineering judgement

## Suggested schedule

### Stage 1 — 2 to 4 weeks
- Levels 1 to 3

### Stage 2 — 4 to 6 weeks
- Levels 4 to 6

### Stage 3 — 4 to 6 weeks
- Levels 7 to 8

### Stage 4 — 4 to 6 weeks
- Levels 9 and 10

## Expected outcome

By the end, the student should be able to:

- understand DPDK's runtime
- configure and run data-plane programs in a DPDK environment
- explain mempool, ring, mbuf and the packet lifecycle
- size pipelines in real terms of throughput, latency and cost
- compare DPDK with the kernel stack (C++23 over sockets) and with AF_XDP, knowing in
  which scenario each approach is the correct choice
- write technical documentation with rigour and depth

[apiealinit]: https://doc.dpdk.org/api/rte__eal_8h.html#a5c3f4dddc25e38c5a186ecd8a69260e3
[guiamempool]: https://doc.dpdk.org/guides/prog_guide/mempool_lib.html
[guiaring]: https://doc.dpdk.org/guides/prog_guide/ring_lib.html
[guiambuf]: https://doc.dpdk.org/guides/prog_guide/mbuf_lib.html
[guiaflow]: https://doc.dpdk.org/guides/prog_guide/ethdev/flow_offload.html
[apidevinfo]: https://doc.dpdk.org/api/rte__ethdev_8h.html#a47933dd514cda48f158117ddfa139658

[cEAL]: https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html
[cHuge]: https://doc.dpdk.org/guides/linux_gsg/sys_reqs.html
[cAfxdp]: https://doc.dpdk.org/guides/nics/af_xdp.html
[cPMD]: https://doc.dpdk.org/guides/prog_guide/ethdev/ethdev.html
