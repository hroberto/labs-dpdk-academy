# Project tooling: build, compilation and tests

*Leia em [português](ferramental.md).*

This document explains **which tools the project uses, why each was chosen and what
was discarded**. It is part of the study content, not an administrative appendix: the
decisions below are the same ones that appear in any real data-plane project, and the
mistakes they avoid are mistakes that cost hours to a beginner.

---

## 1. Foundation: why the choice of tool matters here

In many projects, the build system is an infrastructure detail. In a DPDK project it
is not — for a specific reason:

> **DPDK is not a library dependency. It is an environment dependency.**

Compiling against DPDK requires the libraries and the headers. *Running* a DPDK
program additionally requires reserved [hugepages][hugepages], the correct driver
([`vfio-pci` or `uio_pci_generic`][drivers]), the NIC detached from the kernel and
adequate permissions. No package manager delivers that second set.

That distinction governs every decision in this document.

---

## 2. Mechanism: the tools in use

| Layer | Tool | Role |
|---|---|---|
| Build configuration | **[Meson][meson]** | describes targets, dependencies and tests |
| Build execution | **[Ninja][ninja]** | runs the compilation in parallel |
| DPDK discovery | **[pkg-config][pkgconfig]** | locates the system's `libdpdk.pc` |
| Test dependencies | **[Meson wrap][wrap]** | downloads and pins GTest by hash |
| L1 tests | **[GoogleTest][gtest]** | assertions over pure logic |
| L2 tests | **[Meson test][mesontest]** + shell | exercises the binary as the user runs it |
| Style and analysis | **[clang-format][clangformat]**, **[clang-tidy][clangtidy]** | consistency and static detection |
| Dynamic diagnosis | the compiler's **sanitizers** | [ASan][asan], [UBSan][ubsan], [TSan][tsan] |

### 2.1 Meson + Ninja

The justification is not a matter of style: **DPDK itself is built with Meson and
Ninja**, and it distributes a `libdpdk.pc` file. That produces a concrete and
verifiable gain — the whole dependency resolves in one line, with
[`dependency()`][mesondep]:

```meson
dpdk_dep = dependency('libdpdk', method : 'pkg-config', required : true)
```

When you open DPDK's source to study a [PMD][pmd], you will find `meson.build` there
too. The tool teaches alongside the content.

Ninja is just the executor: it is not chosen separately, it is Meson's default
backend. Build speed was not the criterion for the decision.

### 2.2 The C language standard: `c11` with `_GNU_SOURCE`

A trap that appears on the first compilation against DPDK. Configuring `c_std=c11`
(strict ISO) makes the compilation **fail** in DPDK's headers:

```
/usr/include/dpdk/rte_ring.h:59: error: unknown type name 'ssize_t'
/usr/include/dpdk/rte_string_fns.h:74: error: implicit declaration of 'strnlen'
```

The reason: `ssize_t` and `strnlen` are POSIX, not ISO C. In strict ISO mode the
compiler defines `__STRICT_ANSI__`, and glibc's [feature test macros][ftm] stop
exposing those declarations.

There are **two possible fixes**, and the difference between them is this section's
content:

| Fix | What it does | Cost |
|---|---|---|
| `c_std=gnu11` | swaps the language standard for C11 plus GNU extensions | fixes the symptom and **hides the mechanism**; it starts accepting extensions you did not intend to use |
| `c_std=c11` + `#define _GNU_SOURCE` per file | keeps the standard and explicitly asks for the POSIX declarations | one line at the top of each source that uses the headers |

**The project uses the second**, which is what DPDK itself does upstream. Both
compile; measured on this machine, with a program that includes `rte_eal.h`,
`rte_mempool.h` and `rte_mbuf.h`:

```console
$ cc -std=c11 $(pkg-config --cflags libdpdk) -c t.c            # 3 erros
$ cc -std=c11 -D_GNU_SOURCE $(pkg-config --cflags libdpdk) -c t.c   # 0 erros
$ cc -std=gnu11 $(pkg-config --cflags libdpdk) -c t.c               # 0 erros
```

The distinction matters because they are things of different natures: `-std=` chooses
the **language dialect**; `_GNU_SOURCE` chooses **which declarations the library
exposes**. Changing the dialect to fix a library problem works for the wrong reason.

> **This section was corrected.** The previous version prescribed `gnu11` and
> concluded that "the correct standard is `gnu11`". An external review pointed out
> that DPDK upstream uses C11 with `_GNU_SOURCE`, and the verification above
> confirmed it. The original diagnosis was right — the remedy was not.

> **Transferable lesson:** on seeing "unknown type" in a third-party header, suspect
> the feature test macros before touching the language standard. Lowering the
> compiler's rigour is the fix that always works and is almost never the right one.

### 2.3 Dependency management: pkg-config and Meson wrap

The project has exactly three dependencies:

| Dependency | Nature | Origin |
|---|---|---|
| DPDK | environment (kernel, [hugepages][cHuge], drivers) | the system, via `pkg-config` |
| GoogleTest | testing, development only | `subprojects/gtest.wrap` |
| [google-benchmark][benchmark] *(planned)* | measurement, development only | a wrap, when Stage 5 arrives |

The [wrap file][wrap] `subprojects/gtest.wrap` is **versioned in the repository** and
pins the version and cryptographic hashes of the downloaded code. The code itself is
not versioned. The result is a reproducible build without bloating the repository.

---

## 3. Trade-offs: what was discarded, and why

Discarding tools is an engineering decision as real as adopting them. These were
evaluated and refused for **this** project.

### 3.1 [CMake][cmake]

It would work. But it would require `FindPkgConfig` plus manually constructing an
imported target, to produce what Meson resolves in one line — and it would take the
student away from the tool DPDK itself uses.

### 3.2 [Conan 2][conan]

It was seriously evaluated and **removed**. Two reasons, one factual and one
conceptual.

The factual one: **there is no DPDK recipe in [Conan Center][conancenter]**. Searching
for `dpdk` in the ConanCenter API returns an empty list (against six versions for
`zlib`, used as a control), the `recipes/dpdk` directory does not exist in
[conan-center-index][cci], and the two proposals to add it ([PR #7518][pr7518] and
[PR #24817][pr24817]) were closed without merging. A `requires = "dpdk/22.11"`
declaration simply does not resolve.

The conceptual one, more important: even if the recipe existed, it would deliver
libraries — and the student would still have to configure hugepages, load `vfio-pci`
and bind the NIC. **Packaging DPDK would hide exactly what this track exists to
teach.**

### 3.3 [vcpkg][vcpkg]

This one deserves nuance, because the easy answer is wrong: **vcpkg does have a
[DPDK port][vcpkgdpdk]** (version 26.3), maintained and functional. It compiles DPDK
from source — using Meson internally — and generates `libdpdk.pc`, so it would
integrate with this project without changing a line of `meson.build`.

Even so, it was not adopted, for three concrete costs:

1. **An expensive first contact.** `apt install dpdk-dev` delivers around sixty
   `librte_*` libraries in seconds; vcpkg compiles everything from source. In a track
   whose goal is to reach [`rte_eal_init()`][apiealinit] quickly, that is a tax
   charged before the first lesson.
2. **It does not solve the real problem.** It delivers libraries and a `.pc`;
   hugepages, `vfio-pci` and binding remain up to the student.
3. **Reduced drivers by default.** The port disables `net/pcap`, mlx4/mlx5, QAT and
   others unless the *feature* is requested — a wall that is not DPDK's, it is
   packaging's.

**When to reconsider:** if the project comes to require a reproducible benchmark
across machines ("measured against DPDK 26.3, exactly"), pinning the version becomes
worth the build cost. That is planned for Stage 5 and will be re-evaluated there.

---

## 4. Practice: the two levels of tests

The separation between L1 and L2 is not test bureaucracy; it reflects an
architectural separation in the code.

### 4.1 L1 — pure logic, no runtime

**What it is:** tests over the logic that does not depend on DPDK. In topic 02 that
is `packet.c`, deliberately separated from `pipeline_ring.c`.

**Why it exists:** it runs on any machine, in milliseconds, without hugepages,
without privileges and without a NIC. If a test needs the [EAL][cEAL] to verify a
business rule, the rule is coupled to the runtime unnecessarily — the L1 test becomes
a coupling detector.

**Tool:** [GoogleTest][gtest], obtained through Meson's wrap. It tests C code through
`extern "C"`.

The most relevant gain from GTest here is
[parameterised tests][gtestparam], which let you express an invariant of the topic
itself:

```cpp
INSTANTIATE_TEST_SUITE_P(TamanhosDeLote, ResultadoIndependeDoLote,
                         ::testing::Values(1u, 2u, 3u, 4u, 8u, 10u, 32u));
```

That test asserts that **batch size is a performance knob, never a semantic one**. If
processing in batches of 1 and in batches of 32 produced different results, there
would be a logic bug disguised as an optimisation. Seven batch sizes, one test body.

### 4.2 L2 — integration with the real runtime

**What it is:** running the binary as the student runs it, including the EAL's
arguments.

**Why it does NOT use GTest:** [`rte_eal_init()`][rteeal] is global and cannot be
called twice in the same process. GTest runs every case in a single process, which
would force sharing one EAL across all tests — preventing exactly what L2 needs to
verify: *variations* of arguments (`-l 0`, `--no-huge`, an invalid option, arguments
after `--`).

That command-line contract is content of the topic. That is why L2 is a script that
treats the binary as a black box.

**What L2 verifies that L1 cannot:** in topic 02, the central assertion is
`Free objects in the pool at the end: 4095 of 4095`. Leaking a [mempool][mempool] object
is the classic failure of this subject — the pool empties, reception starts returning
zero and the pipeline stops in silence. Only the runtime reveals that.

### 4.3 Running

```bash
./scripts/build-all.sh          # configures and compiles
./scripts/test-all.sh           # everything
./scripts/test-all.sh l1        # pure logic only (fast, no DPDK)
./scripts/test-all.sh l2        # integration only
```

Or directly through Meson:

```bash
meson setup build && meson compile -C build
meson test -C build --suite l1 --print-errorlogs
meson test -C build --suite l2 --print-errorlogs
```

> **A note on CTest:** [`ctest`][ctest] is CMake's runner and does not apply here.
> The Meson equivalent is [`meson test`][mesontest], used above.

---

## 5. Validation: sanitizers and static analysis

Meson exposes the compiler's sanitizers natively through the built-in option
[`b_sanitize`][mesonopts] — no project-specific option is needed:

```bash
meson setup build-asan -Db_sanitize=address,undefined
meson test -C build-asan
```

Be careful applying sanitizers to DPDK code, and the care is **not** what it looks
like.

**Hugepages are not the obstacle.** The [DPDK documentation][asandpdk] states that
*"ASan is aware of DPDK memory allocations, thanks to added instrumentation"*: the
[EAL][eal] allocator is instrumented through `RTE_MALLOC_ASAN`, and `rte_malloc`,
`rte_zmalloc` and memzones enter [ASan][asan]'s radar like any allocation.

The two real concerns are different ones:

- **DPDK itself must be compiled with the sanitizer.** `-Db_sanitize=address` on the
  *application's* build instruments none of DPDK's memory — the instrumentation lives
  inside the library, and without rebuilding it there is no coverage.
- **An object inside a mempool stays out.** There is no per-object marking in
  `lib/mempool` or `lib/mbuf`: a `get`/`put` neither poisons nor releases the region, so
  use-after-`put` or a write past `data_len` do not fire. The whole pool is one
  allocation to ASan; the objects inside it are not.

That is why ASan catches errors in your logic and does **not** replace the pool
integrity check done at L2 — which is precisely per-object.

Style and static analysis are governed by [`.clang-format`][clangformat] and
[`.clang-tidy`][clangtidy] at the repository root.

---

## 5.1 Measurement: how this project produces numbers

Measuring is a tool as much as compiling, and here it obeys three rules.

**Sampling, not a single measurement.** The programs in
[`docs/01-fundamentos/medicoes/`](../01-fundamentos/medicoes/) share
[`statistics.h`](../01-fundamentos/medicoes/statistics.h), which collects several
samples and publishes median, interquartile range, amplitude and coefficient of
variation. The `~` and `!` seals come from the dispersion of the middle — robust,
because it ignores the tails — and the coefficient of variation is read relative to
it: much larger denounces isolated outlying samples. This way **the result itself
warns when it does not deserve trust**, and distinguishes real oscillation from a
one-off interference. A single measurement hides dispersion and has already produced,
in this repository, numbers that varied 40% between runs without that showing.

**Warm up before measuring.** Without it, the first measurement captures the CPU's
start-up — low frequency and cold caches — and not the steady state.

**Sources have a hierarchy.** A technical requirement comes from a standards body,
and the document names which: **IEEE 802.3** for the Ethernet frame format,
**ITU-T G.114** for delay in telephony, the IETF's **RFC 2544** for throughput
measurement methodology. Below that come each project's official documentation and
peer-reviewed academic literature. Technical press enters only when it is the sole
source of a specific hardware measurement, and it comes labelled as such. A
collaborative encyclopedia is not used as a source.

**Comparison with the literature.** Numbers from one machine carry that machine's
biases. That is why the measurements are compared with the field's accepted
references: the book by **Paul McKenney**, the kernel's RCU maintainer
([*Is Parallel Programming Hard*][perfbook]), the paper by **David, Guerraoui and
Trigonakis** at [SOSP 2013][sosp], and the original futex paper by **Franke, Russell
and Kirkwood** ([OLS 2002][futex]). The complete comparison, including the
discrepancies it explained, is in
[§10 of the Fundamentals](../01-fundamentos/README.en.md#10-comparison-with-the-literature).

> For CI, `DPDK_ACADEMY_AMOSTRAS=3` shortens the collection: there the goal is to
> verify that the programs run, not to produce statistics nobody will read.

**Line anchors into the code.** When a document cites a number, the link leads
**straight to the line** of the function that produced it — a smoother read than
"find the function in the file". The cost is maintenance: line numbers change when
the code changes, and an outdated link does not break, it silently points at the
wrong passage. That is why the convention requires the **link text to be the symbol's
name**, and [`ferramental/qualidade/verificar-ancoras.py`](../../ferramental/qualidade/verificar-ancoras.py)
checks whether each anchor still lands on it. It runs as a test in the suite
(`meson test --suite docs`), so an outdated anchor breaks CI instead of misleading the
reader.

**References to the official documentation.** The DPDK symbols and concepts cited in
the documents point to the official documentation, following a canonical map in
[`scripts/mapa-links-dpdk.md`](../../ferramental/qualidade/mapa-links-dpdk.md): the
same symbol, the same destination, one reference per file at the first occurrence.
The map also records two traps — a link in a heading breaks the section's anchor, and
a wrong Doxygen anchor returns HTTP 200 all the same.

---

## 6. Known limitations

- **Hugepages are not exercised in the tests.** All tests use `--no-huge` to run on
  any machine and in CI. That is a portability choice, not a claim that
  [hugepages][hugepages] are dispensable — under real load they reduce *TLB misses*
  significantly. A dedicated topic will address this.
- **No test touches network hardware.** There is no NIC or physical [PMD][cPMD]
  involved until the RX/TX topics, which will use virtual PMDs
  ([`net_null`][netnull], [`net_ring`][netring], [`net_tap`][nettap],
  [`net_af_packet`][netafpacket]).
- **The timings printed by the examples are not a benchmark.** They are a
  single-run order of magnitude, with no control of frequency, affinity or cache
  warm-up. Serious measurement enters at Stage 5, with [google-benchmark][benchmark]
  and a documented methodology.
- **The reference environment is Linux.** DPDK supports FreeBSD and Windows, but
  nothing here has been verified on those platforms.

---

## 7. External references

Official documentation for each tool and concept cited above.

### DPDK

| Subject | Reference |
|---|---|
| Installation on Linux | [Getting Started Guide][gsg] |
| Requirements and hugepages | [System Requirements][hugepages] |
| `vfio-pci` / `uio_pci_generic` drivers | [Linux Drivers][drivers] |
| EAL (abstraction layer) | [Environment Abstraction Layer][eal] |
| Mempool | [Mempool Library][mempool] |
| Ring | [Ring Library][ring] |
| mbuf | [Mbuf Library][mbuf] |
| Poll Mode Drivers | [Ethdev / PMD][pmd] |
| Virtual PMDs | [null][netnull] · [ring][netring] · [tap][nettap] · [af_packet][netafpacket] · [af_xdp][netafxdp] |
| API reference | [DPDK API][dpdkapi] · [`rte_eal.h`][rteeal] |
| Diagnostic tool | [testpmd][testpmd] |

### Build and dependencies

| Subject | Reference |
|---|---|
| Meson | [Manual][meson] · [Function reference][mesondep] · [Built-in options][mesonopts] |
| Wrap system | [Wrap dependency system][wrap] |
| Ninja | [ninja-build.org][ninja] |
| pkg-config | [freedesktop.org][pkgconfig] |
| CMake (not used) | [cmake.org][cmake] · [ctest][ctest] |
| Conan (evaluated, discarded) | [Documentation][conan] · [Conan Center][conancenter] · [conan-center-index][cci] |
| vcpkg (evaluated, discarded) | [vcpkg.io][vcpkg] · [DPDK port][vcpkgdpdk] |

### Tests and quality

| Subject | Reference |
|---|---|
| GoogleTest | [Documentation][gtest] · [Parameterised tests][gtestparam] · [Assertion reference][gtestref] |
| Tests in Meson | [Unit tests][mesontest] |
| google-benchmark | [Repository][benchmark] |
| clang-format | [Documentation][clangformat] |
| clang-tidy | [Documentation][clangtidy] |
| Sanitizers | [AddressSanitizer][asan] · [UndefinedBehaviorSanitizer][ubsan] · [ThreadSanitizer][tsan] |

### Language

| Subject | Reference |
|---|---|
| C language standards in GCC | [Standards][gccstd] |
| glibc feature test macros | [Feature Test Macros][ftm] |
| C++23 features | [cppreference][cpp23] |

## 8. Internal navigation

- [Project overview](README.en.md)
- [Study plan](../plano-estudo-dpdk.en.md)
- [Topic 01 — EAL](../../trilha/01-fundamentos/01-eal-hello/)
- [Topic 02 — mempool and ring](../../trilha/01-fundamentos/02-mempool-ring/)

<!-- ------------------------------------------------------------------- -->
<!-- Definitions of the reference links used throughout this document.   -->
<!-- ------------------------------------------------------------------- -->

[gsg]: https://doc.dpdk.org/guides/linux_gsg/
[hugepages]: https://doc.dpdk.org/guides/linux_gsg/sys_reqs.html
[drivers]: https://doc.dpdk.org/guides/linux_gsg/linux_drivers.html
[eal]: https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html
[mempool]: https://doc.dpdk.org/guides/prog_guide/mempool_lib.html
[ring]: https://doc.dpdk.org/guides/prog_guide/ring_lib.html
[mbuf]: https://doc.dpdk.org/guides/prog_guide/mbuf_lib.html
[pmd]: https://doc.dpdk.org/guides/prog_guide/ethdev/ethdev.html
[netnull]: https://doc.dpdk.org/guides/nics/null.html
[netring]: https://doc.dpdk.org/guides/nics/ring.html
[nettap]: https://doc.dpdk.org/guides/nics/tap.html
[netafpacket]: https://doc.dpdk.org/guides/nics/af_packet.html
[netafxdp]: https://doc.dpdk.org/guides/nics/af_xdp.html
[dpdkapi]: https://doc.dpdk.org/api/
[rteeal]: https://doc.dpdk.org/api/rte__eal_8h.html
[testpmd]: https://doc.dpdk.org/guides/testpmd_app_ug/

[meson]: https://mesonbuild.com/
[mesondep]: https://mesonbuild.com/Reference-manual_functions.html
[mesonopts]: https://mesonbuild.com/Builtin-options.html
[mesontest]: https://mesonbuild.com/Unit-tests.html
[wrap]: https://mesonbuild.com/Wrap-dependency-system-manual.html
[ninja]: https://ninja-build.org/
[pkgconfig]: https://www.freedesktop.org/wiki/Software/pkg-config/
[cmake]: https://cmake.org/
[ctest]: https://cmake.org/cmake/help/latest/manual/ctest.1.html
[conan]: https://docs.conan.io/2/
[conancenter]: https://conan.io/center
[cci]: https://github.com/conan-io/conan-center-index
[pr7518]: https://github.com/conan-io/conan-center-index/pull/7518
[pr24817]: https://github.com/conan-io/conan-center-index/pull/24817
[vcpkg]: https://vcpkg.io/
[vcpkgdpdk]: https://github.com/microsoft/vcpkg/tree/master/ports/dpdk

[gtest]: https://google.github.io/googletest/
[gtestparam]: https://google.github.io/googletest/advanced.html
[gtestref]: https://google.github.io/googletest/reference/testing.html
[benchmark]: https://github.com/google/benchmark
[clangformat]: https://clang.llvm.org/docs/ClangFormat.html
[clangtidy]: https://clang.llvm.org/extra/clang-tidy/
[asan]: https://clang.llvm.org/docs/AddressSanitizer.html
[asandpdk]: https://doc.dpdk.org/guides/prog_guide/asan.html
[ubsan]: https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html
[tsan]: https://clang.llvm.org/docs/ThreadSanitizer.html

[gccstd]: https://gcc.gnu.org/onlinedocs/gcc/Standards.html
[ftm]: https://www.gnu.org/software/libc/manual/html_node/Feature-Test-Macros.html
[cpp23]: https://en.cppreference.com/w/cpp/23
[perfbook]: https://arxiv.org/abs/1701.00854
[sosp]: https://dblp.org/rec/conf/sosp/DavidGT13.html
[futex]: https://www.kernel.org/doc/ols/2002/ols2002-pages-479-495.pdf

[apiealinit]: https://doc.dpdk.org/api/rte__eal_8h.html#a5c3f4dddc25e38c5a186ecd8a69260e3

[cHuge]: https://doc.dpdk.org/guides/linux_gsg/sys_reqs.html
[cEAL]: https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html
[cPMD]: https://doc.dpdk.org/guides/prog_guide/ethdev/ethdev.html
