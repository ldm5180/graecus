# Fixed point for graecus: measured, and declined

**Status: evaluated 2026-08-16, NOT adopted.**  The working code is on
branch `fixed-point-spike` (`Graecus.Fixed`, `tests/src/graecus_fixed_tests.adb`).
Nothing consumes it and nothing should.  This document exists so the
question does not get re-opened from scratch.

## The question

Could graecus's arithmetic move from `Long_Float` to fixed point?  Four
things were hoped for: retiring the trusted `Exp_B`/`Sqrt_B`/`Log_B`
boundary (the crate's only `SPARK_Mode Off`), cheaper proofs, faster
runtime, and stronger type discipline at the API.

## The answer

Three of the four are real.  The fourth is not, and it is the one that
matters for this crate.

| axis | fixed point |
|---|---|
| accuracy | **wins** — 1.1e-8 dollars, irrelevant either way |
| proof cost | **wins overwhelmingly** — 248x cheaper per check |
| trusted boundary | **wins** — no `SPARK_Mode Off` at all |
| runtime | **loses 1.33x-1.68x** |

A complete fixed-point `Price`, measured in-process against the float
one on an identical chain (three runs, stable to ±0.5 ns):

| scenario | float | fixed | ratio |
|---|---|---|---|
| 0-DTE (4 h) | 87.5 ns | 116.3 ns | 1.33x slower |
| week (7 d) | 83.7 ns | 140.6 ns | 1.68x slower |

**Recommendation: do not convert graecus.**  It sits in the bot's
hottest path — `Refresh_Skew` is ~1180 µs per publish tick over an
800-row chain, and the hub publishes ~10x/s per root.  Proof time costs
nothing at runtime and is already only ~25 s.  Trading 1.33-1.68x of
runtime to improve it is the wrong way round for this crate.

## Why runtime loses, precisely

Per primitive, same harness, same inputs:

| op | float | fixed | ratio |
|---|---|---|---|
| `Norm_Cdf` | 32.4 ns | **28.0 ns** | fixed **wins** |
| `log` | 2.4 ns | 9.8 ns | 4.1x slower |
| `sqrt` | 2.3 ns | 21.8 ns | **9.4x slower** |

The pattern is consistent and it is not "fixed point is slow":

> Where the work is **arithmetic**, fixed point wins.  Where the work is
> **decomposing a float** — finding an octave, extracting a mantissa —
> IEEE has already done it for free, and fixed point pays full price to
> catch up.

`sqrt` is the extreme case because on the float side it is a single
hardware instruction: there is no library call to beat.  `Norm_Cdf` is
the opposite: pure arithmetic, and fixed point wins outright.

## Findings worth keeping regardless of the verdict

### Ada's `delta` types are unusable on a hot path

Ada computes a fixed-point product in the smallest integer that holds
it, so `A * B` needs `Value_Size (A) + Value_Size (B)` bits.  Past 63
that is a 128-bit intermediate, and GNAT lowers it to a **call to
`System.Arith_64.Scaled_Divide64`** — a general 128-by-64 *division*
for what, at a binary scale, is a shift.  Verify with `objdump -dr` and
count the calls.

This is **not** the non-power-of-two-`Small` trap: `-gnatR3` confirmed
`Small = 1.0*2**(-40)` on every type and the calls were still emitted.

| | ns per multiply |
|---|---|
| Ada fixed-point `*` at 2**(-40) | 12.58 |
| hand-promoted to `Long_Long_Long_Integer`, shifted | **1.17** |

Dropping the scale to 2**(-25) does keep every product inside 64 bits
and does go fast — but at 1.4e-7 of drift, which is *larger* than the
7.5e-8 error of the Abramowitz-Stegun approximation being implemented,
so the arithmetic would become the dominant error.  Accuracy and speed
are only both available by doing the promotion by hand.

### A provable fast path cannot use `delta` types at all

`'Fixed_Value` — the attribute that reinterprets a fixed-point value as
the scaled integer it already is — **is not permitted in SPARK**.  So
the API has to be scaled-integer subtypes with a documented scale,
which is exactly how this codebase already carries money
(`Fructus.Units.Scaled_Price`, 1/10000 $).  The spike arrived at that
shape independently.

### Two places the representation cannot follow the float formulation

Both turn out to be *better* formulations:

- `Log_B (S / K)` has an argument reaching 1e8; scaled by 2**40 that is
  1.1e20, which overflows a 64-bit raw.  A fixed-point `D1` must compute
  `Log (S) - Log (K)` — same number, no division, both arguments stay
  inside `Spot_Range`.
- d1's ratio reaches 3e13 = 3.3e25 raw, which nothing holds.  The divide
  has to saturate **inside** the 128-bit intermediate, before anything
  narrows.

### Money needs its own multiply

A price carries twenty bits above the unit interval.  Money x
probability is fine at 60 + 41 bits of product; money x money would
need 120 and a result that does not exist here.  A separate
`Mul_Money` makes "only one side is ever money" a matter of types
rather than of vigilance.

### Proof: the nonlinear-integer fear did not materialise

The risk going in was that nonlinear *integer* arithmetic would fail to
discharge where floating-point bit-blasting merely crawls.  It did not.
Everything proved, including a `Mul` postcondition over a 128-bit
product.  Final:

| unit | VCs | steps | per VC |
|---|---|---|---|
| `graecus.adb` (float, all six entry points) | 44 | 502,476 | 11,419 |
| `graecus-fixed.adb` (fixed: exp, log, sqrt, Norm_Cdf, D1, Price) | 158 | **7,364** | **46** |

Two proof lessons, both of which cost a measurement:

- **Bound the INPUT of a nonlinear operation, never its result.**  One
  unclamped operand (`W = Mul (Z, Z)`, whose only bound was `Mul`'s
  deliberately loose postcondition) cost **89,483 steps** — more than
  the rest of the unit together.  Clamping it took the unit from 95,680
  steps to 3,982.  This is the same rule `docs/bounded-subtypes-plan.md`
  landed on.
- **`abs X` on an unconstrained `Long_Long_Integer` is itself an
  unproved check** (`abs LLI'First` overflows).  State bounds as ranges.

### Implementation traps, for anyone who writes fixed-point kernels here

- A binary normalise chain testing `M < Q / 4**s` lands at `M >= Q / 4`,
  one level short — every exact power-of-four boundary needs a final
  closing step.  1/16 was the value that exposed it.
- Newton clamps must be derived from the **seed's** error, not the
  converged value's range: a correction clamped at 2.0 that actually
  reaches 2.09 silently truncated the first iteration.
- Accuracy at the bottom of a domain is **grid-limited, not
  algorithm-limited**.  Half an LSB of input magnified by `d(sqrt)/dx`
  is 6.8e-10 at `Year_Fraction`'s floor, and the measured drift there
  was 6.76e-10 — the algorithm was exact to the grid.  Test against the
  input's own quantisation, not a flat tolerance.
- Test a fixed-point port against the **float implementation**, not the
  true function: A-S 26.2.17 carries a 5.3e-9 bias at zero which both
  versions share, so a truth-based assertion measures the approximation
  instead of the arithmetic.
- Sums of measured parts under-predicted the measured whole **twice**.
  Measure the whole.

## Where this WOULD pay

The inverse case: code that is proof-heavy and not hot, or where
bit-identical results across platforms and libm versions matter more
than nanoseconds.  Money arithmetic is exactly that shape, and is
already scaled integers throughout this codebase.

## Reproducing any of it

```sh
git switch fixed-point-spike
make test          # 10 tests, both modes -- the accuracy guards
make bench         # run TWICE, take the second
make prove
```

`bench/src/bench_graecus.adb` prints every number in this document.
Flip `Frac` in `src/graecus-fixed.ads` to reproduce the 2**(-25) end of
the accuracy/speed curve.

**Profile caveat, and it matters.**  These numbers were taken before
`make bench-build` pinned `alr build --release`.  bench.gpr links
graecus.gpr, which compiles with whatever profile the GENERATED
`config/graecus_config.gpr` names, and alr rewrites that file on every
`alr build` / `alr build --validation` -- so a `make prove` between two
runs silently moved the library between -O3 and -Og.  Absolute figures
above are therefore the development profile (-O3 but WITH -gnata, so
contracts are checked at run time); a release build of the same code is
about half of them.

What survives unaffected is every float-vs-fixed RATIO, because both
sides were always compiled in the same profile and timed in the same
process.  What does NOT survive cleanly is the per-primitive comparison
against libm: `log` and `sqrt` there are optimised C measured against
contract-checked Ada, so fixed point's disadvantage on those two is
overstated by an unknown amount.  The verdict rests on the whole-Price
comparison, which is same-profile and in-process, so it stands.
