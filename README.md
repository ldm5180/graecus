# graecus

SPARK-proven Black-Scholes implied volatility and delta for Ada 2022.

`graecus` (Latin: *Greek*) computes the two greeks a 0-DTE index-options
strategy actually decides by — implied vol and signed delta — with proof
where proof works and characterization where it doesn't: every function is
total (inputs clamped by subtype, the normal CDF saturated at ±40), the
run-time-error freedom and result ranges are **proved** at SPARK level 2
with `--checks-as-errors=on`, and the numerical accuracy is **pinned** by
a 36-row fixture dumped through the exact Go library calls a production
trading bot trades by (2e-3 IV / 0.005 delta parity).

## What's in it

- **`Graecus`** — one pure package, zero crate dependencies:
  - `Implied_Vol` — 60-iteration bisection over `[5e-4, 5.0]` with a
    `Quality` verdict: `Computed`, `Faint` (vega below the floor — the
    IV number is untrustworthy while the delta remains solid; the Go
    reference returns its *seed* in this regime, which the fixture
    pins), or `Clamped` (no time value / absurd premium — classified,
    never chased)
  - `Price` / `Delta_Of` — Black-Scholes with SIGNED deltas (puts
    negative), the convention stop logic depends on
  - `Norm_Cdf` — Abramowitz-Stegun 26.2.17 (|error| < 7.5e-8)
  - `Decay_Weight` — the `1 - exp(-x)` EMA weight for IV-skew smoothing
  - `Option_Right is (Call, Put)` — homed here so consumers' wire types
    can subtype it without this crate ever growing a dependency
- The elementary functions (`Exp`/`Sqrt`/`Log`) sit behind a trusted
  boundary: contracts carry the ranges (proved at every call site),
  bodies are `SPARK_Mode Off`, and the fixture carries the accuracy.
- The subtype bounds are a deliberate proof envelope (spot to 1e6, year
  fraction ≤ 0.2 — 0-8 DTE index options); widening them is a real
  change with its own re-prove, not a tweak.

## Use it

Add the dependency (via a git pin until it is in the community index):

```toml
[[depends-on]]
graecus = "*"
```

```ada
with Graecus;

V : Graecus.Vol_Range;
Q : Graecus.Quality;

Graecus.Implied_Vol
  (Premium => 42.5, S => 7_500.0, K => 7_480.0,
   T => 4.0 / 365.25, R => 0.045, Right => Graecus.Call,
   V => V, Q => Q);
--  Trust V only when Q = Computed.
```

## Develop

```sh
make build    # build the library
make test     # AUnit suite, both -O modes (fully offline)
make prove    # SPARK proof, --checks-as-errors=on
make format   # gnatformat --check
make run      # build and run the example
make help     # all targets
```

Conventions (SPARK, strict TDD, commit style) live in [CLAUDE.md](CLAUDE.md).
