# Final project

*Leia em [português](README.md).*

> **Level 10** of the [study plan](../../docs/plano-estudo-dpdk.en.md) ·
> Prerequisite: every previous module

Consolidate the material into a runnable, documented and measured system, and use
it to answer the question that runs through the whole project: **when DPDK pays
off, and when it does not.**

## The state of this document, without euphemism

**The consolidation is written. The application does not exist.**

They are different things, and the document should not conflate them. What follows
is the balance of what the previous modules demonstrated, the explicit decision
about the AF_XDP comparison, and the inventory of what is missing. What there is
not is a *market data* receiver running end to end over a NIC — and section 6 says
exactly what prevents it.

## 1. What the project demonstrated, in numbers

Every row has a program that produces it and is measured on this machine. None is
a citation.

| Finding | Number | Where |
|---|---|---|
| A syscall costs dozens of function calls | 33.8 ns against 0.73 ns warm (**46×**) or 0.92 cold (36×) | [fundamentals §2](../../docs/01-fundamentos/README.en.md) |
| Bringing up the EAL is not free | **118 ms** | [runtime §2](../../docs/02-runtime-dpdk/README.en.md#2-the-cost-of-existing-how-long-the-eal-takes-to-be-born) |
| Crossing a cache domain dominates everything | **4.0 to 4.8×** | [mempool-ring](../01-fundamentos/02-mempool-ring/) |
| Parallelising can make things worse | 1 lcore beats 2 across almost the whole table | [mempool-ring](../01-fundamentos/02-mempool-ring/) |
| Backpressure is the pool/queue ratio, not the queue | boundary at capacity = 4 095 | [backpressure §6](../02-pipeline/02-batching-backpressure/) |
| A free-running clock charges little | 9× in clock → **4.6%** in the result | [benchmarking §6](../03-performance/01-benchmarking/) |
| The first run after idle lies | ~**30%** more | [benchmarking §6](../03-performance/01-benchmarking/) |
| The CPU profiler does not see the drop at the NIC | `imissed`, readable only through telemetry | [observability §6](../03-performance/02-observabilidade/) |

**The thesis that survives all of this is modest and useful:** DPDK removes the
syscall and the copy, and delivers the packet wherever the program wants it. What
it does **not** remove is the physics of the machine — cache crossing, NUMA
locality, bus budget. Three of the eight findings above are about the machine, not
about DPDK, and none of them improves by switching framework.

## 2. The system, when it exists

The scenario from the fundamentals and the runtime is the natural candidate: a
***market data* receiver**, with the feed handler as the primary process and a
consumer as the secondary. It already has written and tested pieces — order book,
loss detection by sequence number, measured cross-process traversal — in
[`docs/02-runtime-dpdk/medicoes/`](../../docs/02-runtime-dpdk/medicoes/).

This is a suggested continuation, not an obligation. If another domain teaches what
is left to teach better, the other domain wins: the object of study is DPDK.

## 3. The three comparisons

| Approach | What it costs | What it delivers |
|---|---|---|
| **DPDK** | hugepages, dedicated cores, driver bound to the process, 118 ms to come up | lower latency and higher packet rate |
| **C++23 over sockets** | a syscall and a copy per packet | runs anywhere, without privilege |
| **AF_XDP** | driver and kernel requirements | partial *bypass* keeping the kernel's driver and security model |

The second already has a partial measurement in the
[C++23 alternative](../01-fundamentos/02-mempool-ring/alternativas/cpp23/), and the
caveat there still holds: that test compares in-memory structures, not the network
stack.

## 4. AF_XDP: the decision, taken

The skeleton left two ways out open and required choosing one. **The second was
chosen: AF_XDP enters as a conceptual comparison, with attributed third-party
numbers, and the measurement is left to whoever has adequate hardware.**

The reason is measured, not a preference. Queried with privilege, the netdev itself
answers:

```
NETDEV_XDP_ACT_BASIC:         no
NETDEV_XDP_ACT_REDIRECT:      no
NETDEV_XDP_ACT_XSK_ZEROCOPY:  no
```

`BASIC: no` means the NIC **has no native XDP at all** — this is not the "has XDP,
lacks zero-copy" case. Here AF_XDP only works in **generic (SKB) mode**, in which
the eBPF runs *after* the `sk_buff` allocation, inside the stack: the slowest of
the modes, and the one that least represents AF_XDP.

Measuring that and calling it AF_XDP would repeat the mistake the C++23 alternative
already documents: **measuring a scenario that removes the very thing the
technology charges for.** A number like that is worse than none, because it looks
like an answer.

### The evidence, reproducible

The driver module confirms it independently — which matters because the interface
here is *down*, and someone could attribute the "no" to the dead link:

```bash
for d in r8169 i40e ice ixgbe mlx5_core; do
  m=$(modinfo -n "$d") || continue
  tmp=$(mktemp)
  case "$m" in *.zst) zstdcat "$m" >"$tmp";; *.xz) xzcat "$m" >"$tmp";; *) cp "$m" "$tmp";; esac
  printf '%-10s xdp_=%-4s xsk_ chamados=%-3s xsk_ definidos=%s\n' "$d" \
    "$(nm "$tmp" | grep -c 'xdp_')" \
    "$(nm "$tmp" | awk '$1=="U" && $2 ~ /xsk_/' | wc -l)" \
    "$(nm "$tmp" | awk '$1!="U" && $NF ~ /xsk_/' | wc -l)"
  rm -f "$tmp"
done
```

| driver | `xdp_` (native XDP) | calls into the XSK core | own XSK code | diagnosis |
|---|---:|---:|---:|---|
| `r8169` (the NIC here) | **0** | 0 | 0 | **no XDP at all** |
| `i40e` | 37 | 7 | 13 | XDP + zero-copy |
| `ice` | 83 | 7 | 13 | XDP + zero-copy |
| `ixgbe` | 38 | 8 | 12 | XDP + zero-copy |
| `mlx5_core` | 59 | 8 | 43 | XDP + zero-copy |

The three columns separate situations a single number would conflate:

- **`xdp_`** distinguishes "has no XDP" from "has XDP, lacks zero-copy" — it is the
  column that classifies the RTL8125;
- **calls** are *undefined* symbols: XSK core functions the driver invokes;
- **own code** are XSK functions it *defines*.

Real support has all three.

> **Decompression is not a detail.** This document once published
> `nm -D .../r8169.ko.zst | grep -c xsk_`, and it **does not work**: modules come
> compressed with zstd, `nm` refuses the file, `grep -c` swallows the error and
> returns `0`. Run against `i40e`, which does have support, the result was also
> `0` — the command said "no zero-copy" for every driver on the system, and the
> conclusion about the RTL8125 was right by coincidence. Checked again on
> 16/09/2026: the direct form returns `0` for `r8169` and `i40e`; the one that
> decompresses first reproduces the table above.

> **And this evidence proves less than it appears to — it is not even a necessary
> condition.** A symbol in the module is indirect: inlining, renaming and
> implementation changes produce false negatives. It answers "is it worth
> trying?", not "this works".
>
> The hierarchy, from weakest to strongest:
>
> 1. **symbols in the module** — a heuristic, no privilege needed;
> 2. **`NETDEV_XDP_ACT_XSK_ZEROCOPY`** announced by the netdev, via
>    `xdp-loader features` — **requires root**;
> 3. **a real bind with `XDP_ZEROCOPY`** — the only proof:
>    `sudo xdpsock -i <iface> -q 0 -N -z -r`. Running **without** `-z` proves
>    nothing: there is a silent fallback to copy mode.

## 5. What this project teaches about technical honesty

Worth recording, because it is what was learned most here and was not in the plan.

**Not established is not a negative fact.** Most of the defects fixed in this
repository are from the same family: `ls | wc -l` returning `0` for "I could not
look"; `%G?` returning `N` for "I could not verify"; `nm` failing silently and
`grep -c` publishing `0`. In all of them, the absence of an answer came out as a
negative answer — which is the most reassuring and the most dangerous.

**Verification that does not run is worse than none.** A test left unregistered, a
gate that fails by construction in CI, a rule whose pattern stopped matching after
a rewrite: all three emit green and check nothing.

**Compression creates falsehood.** An index that summarises "regression at 128"
from a table that separates one lcore from two publishes something the source does
not say.

## 6. What is missing, and why

**The application.** There is no end-to-end *market data* receiver. The pieces
exist in `docs/02-runtime-dpdk/medicoes/` and were never assembled into a system.

**The NIC outside the kernel.** The submodule
[01 — RX/TX](../02-pipeline/01-rx-tx-burst/) has the card's scope and capabilities
measured, and is blocked by one line: `enp8s0` has `IFF_UP` set, and the capture
guard refuses. `sudo ip link set enp8s0 down` unblocks it — that is a decision for
whoever operates the machine, and that is why the script does not take it.

**The fair comparison against sockets.** The C++23 alternative compares in-memory
structures; the comparison that matters is against the kernel's network stack, and
it needs the NIC.

**`imissed` observed happening.** The mechanism is demonstrated with `net_null`,
which has no hardware descriptor. The value requires the card.

**A benchmark with a pinned environment.** Performance submodule 01 measured that
pinning the frequency changes little; measuring the effect of `isolcpus` is
missing, and it requires a reboot.

## 7. Navigation

| | |
|---|---|
| **Previous** | [03 — Performance and observability](../03-performance/) |
| **Index** | [Track](../README.en.md) · [Study plan](../../docs/plano-estudo-dpdk.en.md) · [Roadmap](../../ROADMAP.en.md) |
