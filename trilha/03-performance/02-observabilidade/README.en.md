# Submodule 02 — Observability

*Leia em [português](README.md).*

> **Level 8** of the [study plan](../../../docs/plano-estudo-dpdk.md) ·
> Prerequisite: [01 — Benchmarking](../01-benchmarking/)

Seeing what a DPDK program is doing **while it runs**, without stopping it and
without instrumenting the hot path.

## 1. Foundation: the CPU profiler does not see what matters

Listing `perf`, *sanitizers* and `clang-tidy` is easy and insufficient: they are
generic C and C++ tools, and the project already covers them in the
[tooling document](../../../docs/00-visao-geral/ferramental.md). What this
submodule covers, and no other does, is **runtime** observability.

The reason is concrete. When the NIC drops a packet for lack of a free descriptor,
**no instruction executes** in your process. There is no stack to sample, no
function to attribute cost to, no line of code to blame. A CPU profiler shows a
healthy, fast program processing everything it received — and what it did not
receive is invisible.

The counter exists. It is called `imissed`, it lives on the NIC, and section 6
reads it with the program running.

## 2. Mechanism: a socket and a line of JSON

The EAL opens a UNIX domain socket in the runtime directory:

```
/run/user/1000/dpdk/<file-prefix>/dpdk_telemetry.v2
```

Whoever connects sends a path as text and receives a JSON object. That is all —
there is no library to link, no secondary process to bring up, and the client does
not have to be DPDK.

**Telemetry is ON BY DEFAULT, and this was measured.** The EAL help shows the two
options side by side, which suggests one enables and the other disables:

```
--no-telemetry             Disable telemetry
--telemetry                Enable telemetry
```

Running the same program with and without `--telemetry`, **the socket appeared in
both cases**. The flag that changes anything is `--no-telemetry`; `--telemetry`
only restates the default. On DPDK 25.11, on this machine.

### Telemetry is not a secondary process

The two get confused, and the difference decides which to use:

| | Telemetry | Secondary process |
|---|---|---|
| Access | counters the library exports | the whole shared memory |
| Client | anything that speaks a UNIX socket | a DPDK process with `--proc-type=secondary` |
| Coupling | none | same DPDK version, same `--file-prefix` |
| Startup cost | connecting | an entire EAL — 123 ms, measured in [runtime §2](../../../docs/02-runtime-dpdk/README.md#2-o-custo-de-existir-quanto-a-eal-leva-para-nascer) |
| Risk | reading | can write into the primary's memory |

For "how many packets were lost", telemetry. For "I want to read the application's
structure", a secondary — which is the path
[runtime §4](../../../docs/02-runtime-dpdk/README.md#4-processos-primário-e-secundário)
already implements and tests.

## 3. Trade-offs: your own counter is expensive in the wrong place

The counter the application keeps is the only one that knows what the application
meant — and it is also the one that can destroy the performance you wanted to
measure.

A `uint64_t` incremented per packet, placed in the same cache line as the hot
path's data, turns every increment into an invalidation for the other cores. It is
the
[false sharing](../../../docs/01-fundamentos/README.md#421-falso-compartilhamento-o-erro-mais-comum-de-quem-escreve-plano-de-dados)
already measured in the fundamentals, now caused by the instrumentation itself.

The defence is the same as there: a per-lcore counter, cache-line aligned,
aggregated only at reporting time. `pipeline_ring.c` already does this — the
`struct consumer_context` is `__rte_cache_aligned` for exactly that reason.

## 4. Implementation

Nothing to compile: the client ships with DPDK.

```bash
# um terminal: o programa, rodando
dpdk-testpmd --no-huge -m 1024 --no-pci --vdev=net_null0 -l 0-1 \
  --file-prefix=obs -- --total-num-mbufs=4096 --forward-mode=rxonly -i

# outro terminal: as perguntas
dpdk-telemetry.py -f obs
```

The client is interactive; `/` lists the available paths — **about a hundred** on
this installation, across `/eal/...`, `/ethdev/...`, `/mempool/...`, `/ring/...`,
`/cryptodev/...` and `/eventdev/...`.

To script it, send the paths on standard input:

```bash
printf '/ethdev/stats,0\n/mempool/info,mb_pool_0\n' | dpdk-telemetry.py -f obs
```

## 5. Validation

```bash
./scripts/ambiente-medicao.sh --uma-linha    # carimbe o ambiente
printf '/eal/params\n' | dpdk-telemetry.py -f obs
```

`/eal/params` returns the **exact** command line the process came up with:

```json
{"/eal/params": ["...feed-primario", "--no-huge", "-m", "512",
                 "--no-pci", "-l", "0", "--file-prefix=telx", "--telemetry"]}
```

It is the first command to run in a diagnosis. Half the problems in DPDK are the
process having come up with arguments different from the ones you believe.

## 6. When it goes wrong — what the counters show

### The drop the profiler does not see

`dpdk-testpmd` with `net_null0` in `rxonly`, four seconds of traffic:

```json
{"/ethdev/stats": {"ipackets": 409697376, "opackets": 0,
                   "ibytes": 26220632064, "obytes": 0,
                   "imissed": 0, "ierrors": 0, "oerrors": 0, "rx_nombuf": 0}}
```

Four hundred and nine million packets, and what matters in a diagnosis are the
three zeros at the end:

- **`imissed`** — the NIC received and had no free descriptor to deliver into. No
  instruction of your process executed because of it.
- **`rx_nombuf`** — there was no mbuf in the pool. The classic symptom of an
  undersized pool, and the [mempool topic](../../../docs/03-mempool-ring-mbuf/README.md)
  has the sizing rules.
- **`ierrors`** — CRC, invalid size, whatever the card rejected.

The three above zero with a healthy `ipackets` is exactly the case where the
program looks fine and is losing data.

`/ethdev/xstats,0` breaks it down per queue (`rx_q0_packets`, `rx_q0_errors`),
which is where you discover the problem is on a single queue — skewed RSS
distribution, for instance.

### Where the objects are, right now

```json
{"/mempool/info": {"name": "mb_pool_0", "size": 4096, "cache_size": 250,
                   "populated_size": 4096,
                   "total_cache_count": 378, "common_pool_count": 3686, ...}}
```

The account closes and says something useful: **378** objects in per-lcore caches,
**3686** in the common pool, and `4096 − 378 − 3686 = 32` in flight — exactly the
batch of 32 testpmd was processing at that instant.

A pool that empties in production shows up here before it becomes `rx_nombuf`.

### Two measured traps

**An unknown path returns `null`, not an error.**

```json
{"/memzone/list": null}          ← caminho que não existe
{"/mempool/list": []}            ← caminho válido, nada a listar
```

The correct one is `/eal/memzone_list`. The protocol *distinguishes* the two cases
— `null` against `[]` — but anyone reading fast sees "empty" in both and concludes
there is no memzone. A wrong conclusion from a typo.

**Queries in the same batch are not atomic.** In the same `printf`, sequentially:

```
/ethdev/stats  → ipackets      = 409 697 376
/ethdev/xstats → rx_good_packets = 409 704 896
```

Seven thousand five hundred packets of difference, because traffic continued
between one answer and the next. Comparing counters from different queries as if
they came from the same instant is a reading error, not a DPDK one.

### The counter that comes back empty

```json
{"/eal/lcore/usage": {"lcore_ids": [], "total_cycles": [],
                      "busy_cycles": [], "usage_ratio": []}}
```

Not a defect: the EAL only fills that in if the application registers the lcore
usage callback (`rte_lcore_register_usage_cb`). With no registration, the endpoint
exists and answers empty — one more case where "empty" does not mean "zero".

## 7. Limitations

**No physical NIC was measured.** All the `ethdev` numbers come from `net_null`,
which has no real hardware descriptor or queue. That is why `imissed` is
structurally zero here: **the mechanism was demonstrated, the value was not
observed happening**. Observing it requires the card outside the kernel, which is
what [pipeline submodule 01](../../02-pipeline/01-rx-tx-burst/) is waiting for.

**Your own counter was not measured.** Section 3 explains the false-sharing risk
and points to the measurement that already exists in the fundamentals; there is no
new experiment here comparing an aligned counter against a misaligned one.

**A secondary process as a diagnostic tool got no experiment.** Section 2's
comparison is about mechanism; the runtime's three L3 tests exercise the path, and
**they skip on this machine** because `/dev/hugepages` is not writable by uid 1000.

**One installation only.** "About a hundred endpoints" is what this DPDK 25.11
exposes; another version or another set of drivers changes the list. `/` is the
source of truth for your machine.

**Nothing here was automated.** There is no test in the suite exercising telemetry
— it would be L3, because it depends on a socket in a runtime directory and on a
live process. It is declared as not covered instead of assumed.

## 8. Where to go from here

| | |
|---|---|
| **Previous** | [01 — Benchmarking](../01-benchmarking/) |
| **Module** | [03 — Performance and observability](../README.md) |
| **Related** | [Runtime §4 — primary and secondary processes](../../../docs/02-runtime-dpdk/README.md#4-processos-primário-e-secundário) |
| **Related** | [Fundamentals §4.2.1 — false sharing](../../../docs/01-fundamentos/README.md#421-falso-compartilhamento-o-erro-mais-comum-de-quem-escreve-plano-de-dados) |
