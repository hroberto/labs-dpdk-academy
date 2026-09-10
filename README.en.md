# DPDK Academy

A study guide for DPDK built on one rule: **every number here has a program that
produces it.**

> **Language.** The teaching prose is in Brazilian Portuguese. The code is not:
> identifiers, types and file names are in English, so the programs and their
> results are readable without translation. This asymmetry is deliberate — see
> [Why the prose is not translated](#why-the-prose-is-not-translated).

## What makes this different

Most DPDK material tells you that DPDK is fast. This one measures how much, on a
named machine, with the method published — and **corrects itself when the
measurement disagrees**. Three examples that survived into the text:

| Claim that circulates | What we measured |
|---|---|
| `malloc()` costs "tens of nanoseconds", which is why mempools exist | **2.18 ns.** glibc has a per-thread cache and the alloc/free pair lands in it. The real case for mempools appears under *contention*, not in isolation |
| A syscall costs ~294× a function call | **36×.** The old baseline measured nothing: GCC const-folded the reference function and hoisted the call out of the loop. Verified by disassembly |
| DPDK's mempool wins by 91× under contention | **32×.** The old figure was an affinity artifact — `pthread_create` inherits the EAL-pinned mask, so 8 `malloc` threads shared one core while the mempool used eight |

The fourth is the one we like most: the DPDK documentation says that with
`n % cache_size != 0` some mempool objects *"will always stay in the pool and
will never be used"*. Measured against a real pool, a single consumer obtains
**all** of them — `rte_mempool_do_generic_get()` falls back to the backing ring
when the cache cannot be refilled. The rule is about efficiency, not
reachability, and the material now says so.

**Primary sources get checked too.** That is the point.

## What is inside

```
docs/      theory: the problem, the mechanism, and the numbers behind decisions
trilha/    practice: runnable code, tests and exercises, per topic
scripts/   environment, measurement and verification tooling
```

Each topic is self-contained — document, code, tests, and where it exists, a
**no-DPDK alternative solving the same problem under the same contract**. That
alternative is not a strawman: at level 1 it *beats* DPDK, and the material
publishes that.

| Level | State |
|---|---|
| 1–2 · system and network fundamentals | written, with reproducible measurements |
| 3 · EAL and runtime | written, incl. primary/secondary shared memory |
| 4 · mempool, ring, mbuf | written, incl. sizing rules verified against a live pool |
| 4.5 · RX/TX and ethdev | planned; NIC probed, hardware limits documented |
| 5–10 · pipeline, performance, virtualization, final project | scope declared, not written |

7 of 19 documents are still scope skeletons, and each one says so at the top.

## Running it

```bash
./scripts/check-env.sh      # what is installed and what is missing
./scripts/ambiente.sh       # records the machine the numbers came from
./scripts/build-all.sh
./scripts/test-all.sh       # 29 tests
```

Requires Linux, GCC 14+ or Clang 18+, DPDK via `pkg-config`, Meson and Ninja.
GoogleTest is fetched by Meson with a pinned hash.

Tests are split by what they need, and a test that cannot run **says so** rather
than passing quietly: L1 is pure logic (no EAL), L2 needs the EAL but no
privilege, L3 needs the host (hugetlbfs, multiple cache domains). Missing
requirements exit 77, which Meson reports as SKIP.

## Why the prose is not translated

The value of this material is the measured numbers and the reasoning around
them. A stale English translation would not make a reader think *the translation
is behind* — it would make them think **the numbers are unreliable**. So the
Portuguese text is the single source of truth, and English covers the surface
that matters for reading and reuse: code, file names, this page, and a short
summary at the top of each written module.

If you do not read Portuguese, the code and the measurement programs still work
for you: run them, read the output, compare with your machine. That was always
the point.

## License

MIT for the code. Content published for educational purposes — see
[LICENSE](LICENSE).

---

*Portuguese README: [README.md](README.md) · Roadmap: [ROADMAP.md](ROADMAP.md)*
