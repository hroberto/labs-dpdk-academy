# Submodule 01 — RX/TX in bursts

*Leia em [português](README.md).*

> **Level 6** of the [study plan](../../../docs/plano-estudo-dpdk.en.md) ·
> Prerequisite: [02 — Mempool, ring and batch](../../01-fundamentos/02-mempool-ring/)

> **No code, but with measurement.** This topic has no program yet: the directory
> contains only this document. But it is **not** a skeleton — the sections
> [Environment constraints](#environment-constraints-verified) and
> [NIC capabilities](#capabilities-of-the-reference-nic-measured) publish real
> verification and measurement, done with `scripts/diagnostico-nic.sh` on this
> machine. What is missing is the RX/TX implementation, which depends on a NIC
> with several queues.
>
> The previous banner said "the content has not been written yet" on a document
> with 171 lines of measured content. A document that is wrong about itself is the
> same defect this material fights in the numbers.

> **Note on the blocks in this English edition.** The measurement programs print in
> Portuguese; this document translates their **labels and captions** so the tables
> and outputs can be read here. Numbers, seals and column positions are exactly what
> the program emitted. When a command in this page greps that output, the pattern
> stays in Portuguese — it has to match what the program really prints.
## Objective

Bring **real** packets into the project. Up to here every packet was synthetic;
from here on there is a NIC, DMA, descriptors and [`rte_mbuf`][guiambuf].

## Why this is the most awaited topic in the track

Four already-written documents defer questions to here, and none of them is
settled without real traffic:

| Origin | Deferred question |
|---|---|
| [C++23 alternative](../../01-fundamentos/02-mempool-ring/alternativas/cpp23/README.en.md) | the honest performance comparison: today DPDK "loses" because the test removes everything it charges for |
| [02-mempool-ring §6](../../01-fundamentos/02-mempool-ring/README.en.md) | [`rte_mbuf`][guiambuf], which has not yet appeared |
| [02-mempool-ring §2](../../01-fundamentos/02-mempool-ring/README.en.md) | the **opposite** semantics of [`rte_eth_tx_burst()`][apitxburst]: it takes ownership of what it accepted |
| [Fundamentals §6](../../../docs/01-fundamentos/README.en.md#6-inside-the-nic-dma-descriptors-and-queues) | descriptors, RX/TX rings and the IOMMU, described but never exercised |

## Scope

- port configuration, RX and TX queues
- [`rte_pktmbuf_pool_create()`][apipoolcreate] and the port's NUMA node
- receiving and transmitting in bursts, and what the return values mean
- the ownership difference between the ring and TX, which is a source of *double
  free*
- dropping: when the packet is not transmitted, who returns it

## Environment constraints, verified

> **This section once published three impediments, and two were false.** They were
> recorded as a precaution, before any verification — and an unverified precaution
> becomes folklore just like unverified optimism. The 2026-09-10 review checked all
> three against the reference machine.

**What was false.**

- *"The NIC has no PMD, so the module needs `--vdev` as its main path."* DPDK
  25.11 ships `librte_net_r8169.so`, a native PMD for the RTL8125/8126 family, and
  the PCI pair `10ec:8125` — this card's — is in the driver's image. Check with:

  ```bash
  ls /usr/lib/*/dpdk/pmds-*/librte_net_r8169.so
  lspci -n -s 08:00.0        # 08:00.0 0200: 10ec:8125
  ```

- *"The shared IOMMU group complicates `vfio-pci` without `unsafe_interrupts`."*
  Group 17 has two members, and the second is a **bridge**: `03:07.0`, a *PCIe
  Switch Downstream Port* on `pcieport`. VFIO allows that driver, so the group has
  a single *endpoint* — the NIC itself. There is no need for
  `unsafe_interrupts`.

  ```bash
  ls /sys/kernel/iommu_groups/17/devices/
  lspci -k -s 03:07.0 | grep 'Kernel driver'
  ```

**What remains true, and is the real constraint.** The RTL8125 sits on a **PCIe
Gen2 x1** link, a ceiling of about 0.5 GB/s — below 10 GbE by bus limit, before any
software consideration
([Fundamentals §6.2](../../../docs/01-fundamentos/README.en.md#62-the-bus-has-a-budget-too)).

That limits the **performance claims**, not the teaching: port and queue
configuration, descriptors, `rx_burst`/`tx_burst`, partial return, mbuf ownership
in TX and counters all work. What this machine **cannot** do is demonstrate 10 GbE
line rate, and the module needs to say so rather than work around it.

## Capabilities of the reference NIC, measured

These are not a forecast: they came from `sudo ./scripts/diagnostico-nic.sh`, which
binds, probes with `testpmd` and returns the card to the kernel. The PMD **claimed**
the device — `Driver name: net_r8169`, firmware `0x00000b99` — which settles the
doubt this section used to carry.

| Capability | Value | What it decides in the module |
|---|---|---|
| **Maximum RX / TX queues** | **1 and 1** | there is no multi-queue, and therefore no effective RSS nor scaling per queue |
| Descriptors per queue | 64 to 4096, alignment 64 | there is room for the ring-size experiment |
| MTU | 1500 (min. 68, **max. 9172**) | *jumbo frames* are possible |
| Segments per packet | up to 64 | a chained mbuf is exercisable |
| `Device capabilities` | `0x0` | no optional capability |
| VLAN offload | everything `off` | *offload* here is another card's business |
| MAC addresses | 1 | no multi-MAC filtering |
| RSS | 40 B key, 128-entry table | **inert**: RSS distributes among queues, and there is only one |
| Link | `down`, `speed None` | there is no cable connected on this machine |

### The limit that weighs most is not the bus

I expected the dominant constraint to be the PCIe Gen2 x1 ceiling. It is not: it is
the **single queue**.

A card with one RX queue and one TX queue does not allow teaching the part of RX/TX
that matters most for a data plane — distributing traffic among queues with RSS,
giving one queue per lcore, and measuring how that scales. The table above lists RSS
with a key and a redirection table, and that misleads: **RSS splits among queues,
and with one queue there is nothing to split.**

Consequences, and none is fatal:

- the **single-queue** path — port configuration, descriptors,
  `rx_burst`/`tx_burst`, partial return, mbuf ownership — is teachable here, with
  real hardware, real DMA and a real IOMMU;
- **multi-queue and RSS** need another card, or `--vdev=net_null`, which accepts as
  many queues as you ask for because it is software. It is the inverse of what is
  assumed: the virtual device serves for what the hardware **does not** cover, and
  not as a low-quality substitute;
- **link `down`** means that RX/TX of real traffic requires a cable. Without one you
  can configure the port, allocate queues and read counters — not receive.

### What changes when adequate hardware arrives

The limitations above are physical: there is nothing to fix in software. What can be
done is **to be ready**, and it is.

[`scripts/diagnostico-nic.sh`](../../../scripts/diagnostico-nic.sh) takes the BDF as
an argument and knows nothing about this card: on a NIC with several queues it
produces the same table with that card's values. Running

```bash
sudo ./scripts/diagnostico-nic.sh 0000:XX:00.0
```

on a suitable machine is enough to know, before writing any code, what that hardware
allows you to teach.

**The hardware is already decided:** a **Mellanox ConnectX-4 Lx 25 GbE dual-port
SFP28**, expected within weeks. When it arrives, this section and the capability
table are revised with its numbers.

What it closes, and the Realtek does not allow:

| Pending today | What the ConnectX-4 Lx brings |
|---|---|
| RSS and distribution among queues | several RX/TX queues — RSS stops being inert |
| one queue per lcore, and how that scales | likewise, with cores to spare |
| checksum *offloads*, TSO, LRO | `Device capabilities` stops being `0x0` |
| `rte_flow` | `mlx5` is the reference implementation of hardware *flow rules* |
| line rate | 25 GbE per port, against the ~0.5 GB/s ceiling of the PCIe Gen2 x1 here |
| SR-IOV and *Virtual Functions* | it also unblocks [Stage 6](../../../ROADMAP.en.md) |

### The procedure changes, and this is the point that misleads most

**The ConnectX-4 Lx is not prepared with `vfio-pci`.** The `mlx5` PMD is a
**bifurcated** driver: the DPDK documentation says *"the same device is managed by
both kernel and DPDK drivers"*. The interface remains visible in `ip link`,
`dpdk-devbind.py` is not used, and
[`scripts/preparar-nic.sh`](../../../scripts/preparar-nic.sh) — built for the
`vfio-pci` path — **is the wrong tool for it**.

What it requires instead is the RDMA userspace stack:

```bash
# Debian/Ubuntu
sudo apt install rdma-core libibverbs1 ibverbs-providers
ibv_devinfo                    # should list the card
```

On this machine `libibverbs.so.1` and `libmlx5.so.1` already exist, and
`librdmacm.so.1` **is missing** — that is what needs to go in before the card. The
PMD `librte_net_mlx5.so` is already present in the installed DPDK 25.11.

**The tooling already knows this, and was tested before the card.**
[`scripts/lib-nic.sh`](../../../scripts/lib-nic.sh) classifies the device by its PCI
*vendor* (`0x15b3` → bifurcated) and both scripts inherit the decision:

- `preparar-nic.sh` **refuses** to bind a bifurcated card, with the explanation of
  why, instead of breaking it;
- `diagnostico-nic.sh` skips the `modprobe`/bind steps, checks `rdma-core` and
  `ibv_devinfo` in their place, and does not try to "restore" a card that never left
  the kernel;
- `preparar-nic.sh --status` shows each NIC's model on the machine.

The classification receives the *vendor* as an argument instead of reading `sysfs`,
precisely so it can be tested **without** the hardware — and it is:
[`scripts/tests/l1_lib_nic.sh`](../../../scripts/tests/l1_lib_nic.sh) runs at L1, in
milliseconds, with 15 assertions. Without it, the first run of the Mellanox path
would be on installation day, and an error there would mean binding a card that
cannot be bound to `vfio-pci`.

The didactic consequence, and it is a good one: the module comes to have **two
driver models** to teach instead of one — full capture (`vfio-pci`, the card leaves
the kernel) and bifurcated (`mlx5`, kernel and DPDK coexist, with isolation
configurable via `rte_flow_isolate()`). That distinction is structural in DPDK and
today appears nowhere in the material.

Until the card arrives, the material must say it did not measure — and not fill the
gap with `net_null`, which would answer anything without proving anything.

### A note on reproducibility

`/dev/vfio/17` is `crw------- root:root`. Running as root that does not matter, but
the whole track runs without privilege up to here — this is the first topic that
breaks that property, and the module needs to say so rather than assume. `ulimit -l`
on this machine is 8192 KB; as root it does not bite, but it is the limit that brings
down VFIO without privilege.

**The consequence for the module's design.** The physical NIC becomes the main path,
and the virtual device the privilege-free alternative — the inverse of what this
section used to say. And each one needs to declare what it proves:

| Path | Proves | Does not prove |
|---|---|---|
| physical NIC + `vfio-pci` | descriptors, DMA, PCIe, link, `xstats`, real *offloads* | 10 GbE line rate (the bus ceiling) |
| `--vdev=net_null` | mbuf flow, burst semantics, ownership | descriptor, DMA, PCIe — it returns empty packets and frees everything on TX |
| `--vdev=net_tap` | integration with the kernel stack | the fast data path: it pays a syscall and a copy, the opposite of what is measured |

**Binding sequence, reversible.**

```bash
./scripts/preparar-nic.sh --status        # what exists, changing nothing
sudo ./scripts/preparar-nic.sh 08:00.0    # binds, with the safety locks
sudo ./scripts/preparar-nic.sh --desfazer 08:00.0
```

[`scripts/preparar-nic.sh`](../../../scripts/preparar-nic.sh) **refuses before
trying** when the interface carries the default route, when it is UP, when it has an
address configured (overridable with `--forcar`), when there is no IOMMU group link,
when there is another *endpoint* in the group, and when no PMD declares support for
the complete PCI identity. It also refuses — and this is the part `dpdk-devbind.py`
has no way of having — when it **could not establish** any of those things: a route
that could not be queried, unreadable `flags`, a group neighbour's driver that does
not resolve. `dpdk-devbind.py` warns in some cases and obeys in all.

**On this machine, today, the guards do NOT pass — and that is the correct result.**
`enp8s0` has `operstate` `down` and nonetheless `flags = 0x1003`: the `IFF_UP` bit is
set, the interface is administratively up and only *carrier* is missing. "No cable"
is not "out of use", and capturing an interface the kernel considers active is
exactly what the guard exists to prevent:

```
0000:07:00.0: refused -- interface wlp7s0 carries the default route
0000:08:00.0: refused -- interface enp8s0 is UP; capture refused
```

To proceed, `sudo ip link set enp8s0 down` — an explicit command, from whoever
operates the machine, and not a mutation the script performs on its own. The previous
version of this script called `ip link set down` by itself; today that is a
precondition, not a side effect, because bringing an interface down in the middle of
a verification sequence changes what is still being verified.

What `--status` shows here, without changing anything:

```
  rota default: default via 192.168.1.1 dev wlp7s0 proto dhcp src 192.168.1.224 metric 600
  IOMMU groups on the system: 28

  driver model per device:
    0000:07:00.0   captura
    0000:08:00.0   captura

  0000:07:00.0 'MT7925 (RZ717) Wi-Fi 7 160MHz 0717' if=wlp7s0 drv=mt7925e unused= *Active*
  0000:08:00.0 'RTL8125 2.5GbE Controller 8125' if=enp8s0 drv=r8169 unused=
```

Two things in that output are worth more than the rest:

**IOMMU group 17 has two members**, `0000:08:00.0` and `0000:03:07.0`. The second is
a bridge (`pcieport`), and VFIO allows those in the group — which is why the script
counts *endpoints*, not members. Requiring a group with a single member would refuse
this machine for no reason. A member whose driver **cannot be read**, however, counts
as an *endpoint*: it is not known what it is, and not knowing does not release.

**The `unused=` field is empty on both cards.** It is the field from which the
previous version of this script deduced the original driver when undoing — on this
machine it would have said nothing. Today the original driver is **written to disk**
(`/var/lib/dpdk-academy/nic/<BDF>.state`, mode 700) before the bind, together with
the PCI identity, and `--desfazer` reads it from there. With no record, the script
does not guess: it requires an explicit `--driver=<nome>`.

And the PMD confirmation, which is the guard separating "it bound" from "it is good
for something", matches the **complete** identity — *vendor*, *device* and both
*subsystem* fields:

```
0000:08:00.0 0x10ec 0x8125 0x1849 0x8125 -> declared PCI support: net_r8169
0000:07:00.0 0x14c3 0x0717 0x14c3 0x0717 -> PMD not confirmed
```

The Wi-Fi has no PMD, and is refused for that — before leaving the kernel, not after.
The previous version merely warned and bound anyway, which left the card outside the
kernel and invisible to any application.

## Out of scope

- *Offload* and [`rte_flow`][guiaflow] — assigned to
  [Stage 4.5](../../../ROADMAP.en.md) and no longer orphaned; if they enter this
  submodule, they enter as a declared section, never smuggled in.
- Virtualisation and SR-IOV, which are level 9.

## Deliverables

- an RX/TX program on the physical NIC, with the virtual device as the alternative
  path for anyone who cannot bind
- documentation in the project's framework
- L1 over the handling logic; L2 over the path with the EAL and the vdev
- the performance comparison the previous documents deferred

## Navigation

| | |
|---|---|
| **Previous** | [02 — Mempool, ring and batch](../../01-fundamentos/02-mempool-ring/) |
| **Next** | [02 — Batching and backpressure](../02-batching-backpressure/) |
| **Module** | [02 — Pipeline](../README.en.md) |

[guiambuf]: https://doc.dpdk.org/guides/prog_guide/mbuf_lib.html
[guiaflow]: https://doc.dpdk.org/guides/prog_guide/ethdev/flow_offload.html
[apitxburst]: https://doc.dpdk.org/api/rte__ethdev_8h.html#a83e56cabbd31637efd648e3fc010392b
[apipoolcreate]: https://doc.dpdk.org/api/rte__mbuf_8h.html#a8f4abb0d54753d2fde515f35c1ba402a
