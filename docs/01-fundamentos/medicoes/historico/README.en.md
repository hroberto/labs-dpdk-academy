# Hardware configuration history

*Leia em [português](README.md).*

One directory per **hardware configuration of the reference machine**, holding
the raw output of the measurement programs.

## Why this exists

This project treated the machine as a constant. It is not.

On 2026-09-20 the EXPO 6000 profile was enabled on the board. RAM latency fell
15%, the aggregate throughput of twelve cores improved 42% — and **nothing in
the repository recorded the previous configuration**, because
`scripts/ambiente.sh` had no such field. The published numbers described
hardware that had ceased to exist, with nothing to compare against.

The failure was not one of measurement. It was presenting as a property of the
architecture what was a property of the configuration.

## What each directory holds

| File | What it is |
|---|---|
| `<program>.r<N>.txt` | raw output, one per run; **`r0` is warm-up and is discarded** |
| `diario.txt` | time and load of each round, and deliberate perturbations |
| `ambiente.md` | `scripts/ambiente.sh --markdown` at collection time |
| `teste-reparo.txt`, `controle.txt` | when the collection accompanied an instrument repair |

## How to compare

```bash
./ferramental/qualidade/comparar-hardware.py \
    docs/01-fundamentos/medicoes/historico/<config-a> \
    docs/01-fundamentos/medicoes/historico/<config-b>
```

**The table is deliberately not written here.** It comes out of the raw outputs
on every run of the command. A typed comparison would be the third place a
number is copied in this repository, and the first two each cost a gate — pt/en
parity and the bibliographic-label divergence. A typed number ages silently; an
extracted one ages together with its source, which is the correct behaviour.

## What is still missing

Dual channel. The second stick goes into slot B2, and the predictions are
registered **before** the measurement in
[metodologia.en.md §6](../../metodologia.en.md#6-pre-registration-the-second-memory-stick),
each with its refutation criterion.
