# graecus

SPARK-proven Black-Scholes IV and delta (Latin: *Greek*), extracted from
arb-ada's `Arb.Greeks` so it is reusable and independently proven.  One
pure package (`Graecus`): the A-S 26.2.17 normal CDF, `Price`, SIGNED
`Delta_Of`, the 60-iteration bisection `Implied_Vol` with its
Computed/Faint/Clamped `Quality` verdict, `Decay_Weight`, and the
`Option_Right` enumeration (homed here; consumers subtype it).

## Commands

- `make build`   — build the library (`alr build`)
- `make test`    — AUnit suite in BOTH modes (release -O3, debug -O0);
  fully offline
- `make features` — the Gherkin features under `tests/features/` in both
  modes, on fabula; checks the summary line, since fabula exits 0 for
  a missing path.  `alr test` runs them too
- `make features-report` — the living documentation: the features with
  `--report-json`, rendered by multiple-cucumber-html-reporter
  (`tools/features-report`, node) into `obj/features-report/html`.  CI
  keeps it with every run and publishes it from main to
  https://ldm5180.github.io/graecus/
- `make prove`   — SPARK proof, `--checks-as-errors=on`; must exit 0
- `make format`  — `gnatformat --check` over all committed Ada sources
- `make run`     — build and run the example
- `alr --non-interactive build --validation` — warnings-as-errors gate (CI)

## Layout

- `src/` — the one library unit (`Graecus`), pure SPARK, zero crate
  dependencies.  The body's `Exp_B`/`Sqrt_B`/`Log_B` are the trusted
  numerics boundary: contracts proved at every call site, bodies
  `SPARK_Mode Off` over `Ada.Numerics.Long_Elementary_Functions` — the
  NUMBERS are pinned by the fixture, the RANGES by the proof.
- `tests/` — AUnit suite (`test_graecus.gpr`, driver `test_runner.adb`)
  + `tests/data/options_bot_greeks.csv`, the 36-row parity fixture,
  and the features: `tests/features/*.feature` run by
  `graecus_features.ads` (Fabula.Main over `Graecus_Steps`).  Each
  feature's steps are an sml machine in its own child -- steps are its
  events, conditions its guards with a refusing fallback row, bodies
  its actions -- and the registry offers every step to each feature as
  a region; a step none takes fails, naming every region's state.  The
  contract a scenario composes, and the fixture reader the parity test
  shares, are `Graecus_World`.
- `proof/` — gnatprove harness; `proof.gpr` sources `../src` directly
  and withs nothing (the library has no dependencies) — the simplest
  proof tree of any sibling.
- `example/` — one demo main (`iv_of_premium`).
- `docs/tdd-log.md` — git-ignored TDD audit log.

## Dependency contract (do not break)

- **Zero crate dependencies, forever.** Consumers (arb-ada's
  `Arb.Theta.Frames`) subtype `Option_Right` from here, which makes
  graecus part of their wire-type substrate — a transitive dependency
  added here becomes theirs.
  The contract is about the library: test-only dependencies (aunit,
  fabula) are not the library's — `graecus.gpr` withs neither, and the
  proof tree withs nothing.
- The fixture is characterization truth: 36 rows dumped through
  options_bot's exact library calls, including the vega-dead rows where
  the Go library returns its own seed (those must classify Faint/Clamped,
  never Computed).  Tolerances: 2e-3 IV / 0.005 delta.
- The subtype bounds are the PROOF ENVELOPE (spot 0.01..1e6, year
  fraction 1e-7..0.2, vol 5e-4..5.0).  Widening any of them is a
  deliberate change: re-prove, and re-examine every clamp comment in
  the body (the "never binds" arguments depend on the bounds).
- Deltas are SIGNED (puts negative).  IV consumers must skip Faint rows.

## Conventions

- Strict TDD (red/green/refactor, logged in `docs/tdd-log.md`), SPARK
  everywhere it can be (`make prove` exit 0 after any src change;
  `SPARK_Mode Off` only at the documented trusted boundary),
  gnatformat-enforced style, Alire validation profile clean.
- Tests are layers -- guidance for judgement, not a mechanical rule.
  A unit test typically tests a single function, or at most a simple
  interaction between two, and the unit tests always cover the function
  they test completely.  A feature (BDD) tests the larger interactions
  that form a higher-level, conceptual feature, in the consumer's
  words, one fact per step, and checks only what a consumer observes --
  a price, a delta, a quality, a refusal -- never how it is computed.
  Coverage is wanted and duplication across the layers is fine: a test
  is removed only when it is an integration test a scenario fully
  supplants, which in a crate of pure functions is none.  A feature
  states a tolerance, a sign or a classification, never an exact
  float.
