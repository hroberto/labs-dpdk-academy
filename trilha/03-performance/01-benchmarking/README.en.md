# Submodule 01 — Benchmarking

*Leia em [português](README.md).*

> **Level 8** of the [study plan](../../../docs/plano-estudo-dpdk.md) ·
> Prerequisite: [02 — Batching and backpressure](../../02-pipeline/02-batching-backpressure/)

Measuring is easy. Measuring in a way that someone else can repeat, arriving at the
same number, is what this submodule is about.

## 1. Foundation: what a methodological caveat confesses

Five documents in this project publish timings carrying some form of the same
sentence:

> *"best of three per point, with warm-up on both sides, but **without pinning the
> CPU frequency** and without isolating cores — that is why the programs print the
> frequency alongside the time. It serves for order of magnitude and for the ratio
> between the approaches, which is what this section claims."*
> — [C++23 alternative](../../01-fundamentos/02-mempool-ring/alternativas/cpp23/README.md)

The caveat is honest and it is **vague**. It says something was not controlled, and
does not say what was in force at the time. A number published without the
environment it came from is not reproducible, because whoever repeats it does not
know what to compare against.

The central deliverable of this submodule is to replace that sentence with a
**record**: what was pinned, what was varying, and how much that costs in
dispersion.

## 2. Mechanism: where the variation comes from

Four sources, in decreasing order of fame and increasing order of real importance
on this machine:

**Frequency scaling.** The core changes clock according to load. This machine uses
`amd-pstate-epp` with the `powersave` governor and boost enabled, and ranges from
**0.61 GHz to 5.66 GHz — a 9.2× span**. It is the source everyone cites first.

**Low-power states (C-states).** An idle core descends into a deep state, and
leaving it costs. Unlike frequency, that cost is paid **once**, at the start, and
does not repeat.

**Contention for the core.** Without `isolcpus`, the kernel scheduler may put
another task on the same core in the middle of the measurement. This machine
isolates nothing: `/sys/devices/system/cpu/isolated` is empty.

**SMT.** Two logical CPUs share the execution units of one physical core. With SMT
enabled — as here — the neighbour influences the result.

## 3. Trade-offs: pinning costs, and does not always pay

Pinning the governor to `performance` leaves the machine hotter and greedier all
the time, for a measurement that lasts seconds. Isolating cores requires rebooting
with kernel command-line parameters, and takes those cores out of the machine's
normal use. Disabling SMT halves the available logical CPUs.

These are real costs, and the right question is not *"is the environment
rigorous?"* — it is **"how much is the lack of rigour charging on this number?"**.
That is an empirical question, and section 6 answers it with measurement.

## 4. Implementation

[`scripts/ambiente-medicao.sh`](../../../scripts/ambiente-medicao.sh) establishes
the environment and **changes nothing**:

```bash
./scripts/ambiente-medicao.sh              # relatório legível
./scripts/ambiente-medicao.sh --uma-linha  # carimbo, ao lado da medição
```

The `--uma-linha` mode exists to be recorded alongside the number:

```
driver=amd-pstate-epp governor=powersave governors=performance,powersave
freq_min=613954 freq_max=5662016 boost=1 faixa=9,2x_0,61-5,66GHz
isolados=vazio nohz_full=vazio smt=on aslr=2 nmi_watchdog=1 carga=0.62
```

Three design decisions are worth stating:

**It establishes, it does not correct.** Altering the student's machine from a
diagnostic script is the same class of mistake that had `preparar-nic.sh` bringing
an interface down in the middle of a check. The corrective commands are printed;
whoever operates the machine decides.

**Tri-state, like the rest of the project.** Each item comes out established with a
value, or **not established, with the reason**. "I could not read the governor"
never becomes "governor absent", which would become "no frequency scaling" — false
and reassuring, the worst combination. If any item is not established, the script
exits with code 1: an incomplete environment record is a number without
provenance.

**The stamp's keys have no spaces.** `governors=performance,powersave`, not
`governors=performance powersave`. The line exists to be read by a program later,
and a value with a space breaks any reader that splits on whitespace — silently.

## 5. Validation

```bash
./scripts/ambiente-medicao.sh                      # o seu ambiente
./scripts/ambiente-medicao.sh --uma-linha; echo $?  # 0 = apurou tudo
```

To reproduce section 6's experiment on your machine:

```bash
B=build/docs/01-fundamentos/medicoes/custo-syscall
for i in $(seq 12); do
  printf '%s ' "$(awk '{printf "%.2f", $1/1e6}' \
    /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)"
  $B | awk '/chamada de funcao/{print $5}'
done
```

The first column is the clock at the instant the process started; the second, the
result. Compare the dispersion of one with that of the other.

## 6. When it goes wrong — and intuition goes wrong first

The experiment has a single question: **how much does a free-running frequency
charge?**

Twelve runs of `custo-syscall`, with the frequency at the starting instant varying
between **0.61 and 5.62 GHz**:

| Frequency at start | ns per function call |
|---|---|
| 4.58 GHz | 0.725 |
| 5.60 GHz | 0.714 |
| 4.75 GHz | 0.745 |
| 4.38 GHz | 0.745 |
| 4.63 GHz | 0.747 |
| **0.61 GHz** | 0.724 |
| 5.61 GHz | 0.746 |
| 5.61 GHz | 0.714 |
| 3.18 GHz | 0.746 |
| 5.62 GHz | 0.720 |
| 5.60 GHz | 0.716 |
| 2.95 GHz | 0.746 |

**A 9× variation in the starting clock produced 4.6% amplitude in the result**
(0.714 to 0.747 ns). The run that started at 0.61 GHz — the bottom of the scale —
measured 0.724, inside the range of those that started above 5 GHz.

The reason is mechanical: the measurement loop is 2 000 000 iterations per sample,
25 samples. The core reaches its ceiling in microseconds, and the median absorbs
the rest. **The starting frequency barely survives the experiment itself.**

### What charges dearly is something else

The **first run after a prolonged idle** measured, across three independent
observations:

| Observation | 1st run | subsequent runs | excess |
|---|---|---|---|
| series of 12 | 0.926 ns | 0.713 – 0.750 | **29.9%** |
| series of 6 | 0.927 ns | 0.716 – 0.748 | **29.5%** |
| isolated run | 0.930 ns | 0.715 | **30.1%** |

Thirty per cent, on the shortest operation in the set — and **reproducible**.

The consequence inverts the caveat's intuition: for these programs, **pinning the
governor helps little; discarding the first run after idle helps a lot**. Anyone
who spent the afternoon configuring `isolcpus` and `performance` without discarding
the first run would go on publishing a number 30% high.

### The methodological error that almost got in here

The first control test for this section was invalid, and it is worth recording
because it is the experiment's natural trap. I ran a series, analysed it, and ran
another "right afterwards" to compare — but between the two there were tens of
seconds of analysis, enough time for the core to go idle again. Both series were
"first run after idle", and the conclusion that the effect was per-process was
wrong.

The valid control runs the batches **within the same invocation**, with no gap.
That is what produced the twelve-row table above, and it is what refuted the
frequency hypothesis.

## 7. Limitations

**The mechanism behind the 30% excess was not isolated.** Coming out of a deep
C-state and pages out of cache are the candidates; telling the two apart requires
`perf` with C-state counters, which this submodule does not yet do. What is
established is the **effect**, measured three times, not the cause.

**One machine only.** All numbers come from a Ryzen 9 9900X with
`amd-pstate-epp`. An Intel with `intel_pstate`, or a virtual machine with no
frequency control, may have different proportions — it may even invert the
conclusion. The script exists precisely so you can measure yours.

**One program only.** `custo-syscall` measures operations from 0.7 to 33 ns. The
30% effect appears on the shortest and vanishes on the longer ones; for work on the
order of milliseconds it is probably irrelevant. The conclusion holds for the range
measured.

**Core isolation was not tested.** This machine has no `isolcpus`, and checking the
gain would require a reboot. The claim "isolating helps" remains theory in this
document — and that is why it does not appear as a number.

**`google-benchmark` has not come in yet.** [Stage 5 of the ROADMAP](../../../ROADMAP.md)
foresees the formal suite; what exists today is `statistics.h`, with median, IQR,
amplitude and coefficient of variation per point.

## 8. Where to go from here

| | |
|---|---|
| **Previous** | [03 — Performance and observability](../) |
| **Next** | [02 — Observability](../02-observabilidade/) |
| **Tool** | [`scripts/ambiente-medicao.sh`](../../../scripts/ambiente-medicao.sh) |
| **Base** | [`docs/01-fundamentos/medicoes/statistics.h`](../../../docs/01-fundamentos/medicoes/statistics.h) |
