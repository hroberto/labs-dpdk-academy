# Engineering standards of the DPDK Academy

This document states the bar the material is held to. It exists so that anyone
reading, reviewing or contributing knows **what the criterion is** — and so that
disagreeing with it is possible, which requires it to be written down.

It is not a style guide. It is what separates, in this repository, a publishable
number from an anecdote.

---

## 1. The rule that governs the others

**Every published number has a program that produces it.**

Not "it came from a measurement": it came from *that* file, from that run,
archived in `historico/`, with the provenance line naming the binary, the
commit, the kernel and the date. A number transcribed by hand is a number with
nobody to check it, and this repository has paid for every time that rule was
relaxed.

Three operational consequences follow from the same principle:

- **The warm-up run is not provenance.** The campaign labels the first round as
  discarded; publishing from it means publishing the condition the design
  excludes.
- **A binary from a dirty tree is not provenance.** A `-dirty` in `git describe`
  means the commit cited does not describe the program that produced the number.
- **One block, one run.** Mixing one round's table with another round's ratio
  produces a document that contradicts itself, and the arithmetic gives it away.

## 2. Scepticism towards performance claims

The default stance is to **distrust easy gains**. Prefer evidence, correctness
and explainability to dogmatic optimisation.

- Question the assumption before optimising or restructuring.
- Separate correctness, safety and performance into distinct decisions.
- Identify the hot path, allocation pressure, contention and ownership before
  touching code.
- Avoid premature optimisation unless the workload, the constraint or the cost
  model justifies it.
- Evaluate latency, throughput, memory, CPU affinity, NUMA and operational
  complexity **together**.

**A performance claim without context does not go in.** Scenario, assumptions,
hardware, measurement method and limitations are part of the number — not an
appendix to it.

## 3. How a result is presented

- **Median with dispersion**, not mean. And the high-dispersion seal is there to
  be read: where it appears, a single run does not support a conclusion.
- **Ratios hold up better than absolutes** in sub-nanosecond measurement,
  because code layout moves the absolute without touching the measured loop.
  "Holds up better" is not "is stable".
- **Pre-registration with a refutation criterion** before measuring. A
  prediction evaluated after the result becomes interpretation.
- **Negative control** whenever the intervention could move everything. If
  changing one variable moves what does not depend on it, the instrument is
  wrong.
- **A null result is a result**, and the difference between "refuted" and "no
  instrument to decide" has to be stated.

## 4. An impediment requires measurement

Claiming something **is not possible** carries the same burden of proof as
claiming a number. "It would need a different kernel", "the file is read-only",
"the API does not exist" — each of those needs the instrument that measured the
"cannot". Where there is none, the text says "I did not verify".

A false impediment is worse than a wrong number: it closes the investigation
instead of biasing it, and nobody goes back to test what is documented as
impossible.

## 5. Design patterns, sparingly

Use a pattern only when it solves a real problem. Prefer the clearest
abstraction that improves reasoning — not complexity for its own sake.

**Recommended here:** RAII for ownership and lifetime; *Strategy* for runtime
policy selection; *Factory* for environment-specific construction; *Builder* for
complex configuration; dependency injection for testability; *object pool* and
*memory pool* for high throughput; policy-based design for compile-time
specialisation on the hot path; *Observer* only where decoupling is genuinely
needed; layered architecture when separation improves correctness and
operability.

**Avoid:** over-engineering a small hot path; hidden global state; an
abstraction layer with no need; deep inheritance in latency-sensitive code;
generalisation with no demonstrated reuse.

## 6. C++23 in this repository

A modern toolchain is the target, with a preference for:

- RAII and strong ownership semantics; value semantics where meaningful;
  deterministic cleanup.
- Contiguous, cache-friendly, predictable layout.
- `std::span`, `std::ranges`, `std::expected` and modern algorithms where they
  fit.
- `constexpr` when it improves correctness and clarity.
- No dynamic allocation in a performance-sensitive loop.
- `std::optional`, `std::variant` and type-safe patterns where they add clarity.

The modern feature goes in to increase correctness and readability, aligned with
the real runtime constraints — not as a demonstration.

**One specific rule, learned in this repository's own code:** `volatile` does
not close a data race. It stops the compiler from eliding the re-read and does
nothing beyond that — it makes the access neither indivisible nor ordered. A
signal between threads is `_Atomic`/`std::atomic`, with the ordering chosen and
justified.

## 7. DPDK

- Initialise and manage the EAL correctly.
- Be explicit about NUMA, affinity and thread placement. **An lcore is not a
  CPU**, and the identity between them holds only when the command line imposes
  it.
- Prefer batching to per-packet work.
- Keep the hot path allocation-free.
- Be careful with locks, atomics and cache-line contention.
- Understand the real cost of mbufs, metadata and per-core state.

**Typical concerns:** packet lifetime and ownership; mempool sizing and reuse;
batching and backpressure; worker pinning; the trade-off between throughput,
latency, simplicity and maintainability.

## 8. Documentation as an engineering artefact

The structure is: **conceptual foundation → mechanism → constraints and
trade-offs → implementation → validation → limitations**.

- Explain the theory before the implementation detail.
- Teach architecture before API; the memory and execution models before
  optimisation tips.
- Give the cause-and-effect relation, not just the result.
- Say when the technique does **not** apply, and why.
- Distinguish conceptual model, implementation detail and real-world caveat.
- A learning path that grows in complexity without losing rigour.
- Examples that demonstrate **engineering judgement**, not micro-optimisation of
  a trivial loop.

**Comparisons with pure C++ alternatives explain the architectural trade-off
honestly** — including when the conclusion is unfavourable to DPDK.

## 9. When correcting the material

1. Explain the reasoning behind the recommendation.
2. Name the trade-off explicitly.
3. Keep the solution grounded in systems engineering reality.
4. Prefer the robust pattern to the clever, fragile trick.
5. For a performance claim, include scenario, assumptions and limitations.
6. Prefer evidence to speculative optimisation.
7. Where a design decision is not obviously optimal, give cost, benefit and the
   likely failure mode.

**A source fix does not narrate the history of the change.** The comment
qualifies the final work; what changed and why goes in the commit message. And
the transferable reasoning — what someone learns from the defect — goes in the
Markdown, not in the comment.

## 10. Focus of the material

- DPDK architecture and packet processing.
- Performance engineering for data-plane software.
- C++23 in a high-performance environment.
- Comparing DPDK with lighter pure C++ alternatives.
- When to use low-level control versus a higher-level abstraction.
- Architecture decisions under real throughput, latency and operational
  constraints.

---

## The gates that enforce this

The bar above is not honorary: part of it is executed by
`ferramental/qualidade/pre-commit.sh`, which runs about twenty checkers. The
ones that directly enforce the rules in this document:

| checker | what it upholds |
|---|---|
| `verificar-blocos.py` | every published block exists literally in an archived collection, excluding the warm-up round and the dirty tree |
| `relatar-tabelas-medidas.py` | every table cell with a unit has backing, or a declared exception with a reason |
| `comparar-publicado.py` | no published number is contradicted by the current collection |
| `verificar-concordancia.py` | the prose agrees with the block it cites |
| `verificar-retratacoes.py` | a retracted value does not survive outside the block that retracts it |
| `verificar-citacao.py` | `CITATION.cff`, `meson.build` and the tag say the same version |
| `verificar-paridade.py` | the pt/en pairs share the same structure |
| `verificar-autodescricao.py` | what the material claims about itself matches the disk |

The criterion for a checker to enter the bar is the same as for any number: it
has a self-test, and the self-test kills a mutant. A checker that passes on any
code verifies nothing.
