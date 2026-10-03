# Feature tests plan

**Status:** G0-G1 done (2026-10-03); G2-G9 not started.

The crate's behavior, stated in Gherkin and run against the proven
functions themselves.  `*.feature` files under `tests/features/` say
what the greeks do in the operator's words -- a deep in-the-money put's
delta nears -1, a straddle's deltas sum to zero at the money, the vol
that priced a premium is the vol it implies, a premium with no time
value is classified rather than chased -- and a small Ada step registry
on [fabula](https://github.com/ldm5180/fabula) runs them, each
feature's steps as an sml state machine.  The AUnit suite keeps the
mechanism and the parity fixture; the features keep the story.

This is the third of a family: `fructus/docs/feature-tests-plan.md`
came first and `nuntius/docs/feature-tests-plan.md` (implemented and
merged) settled the shape every later one starts from.  What is
different here is the world: nuntius IS the wire and its world is
sockets; graecus is five pure functions, and its world is five numbers
-- spot, strike, time, vol, rate -- and the right.

## How to use this plan

Work the items in order; each is one TDD cycle (RED first, the exact
assertion given) and one commit, logged in `docs/tdd-log.md`.  G0
decides the dependency question and lands the pin; G1 and G2 are the
runner and the machine shape, with nothing of the crate's behavior in
them; G3-G7 are the five features of the first wave; G8 the living
documentation; G9 the docs.  After each item: `alr --non-interactive
build --validation`, `make test`, `make features`, `make format`.
Nothing in this plan touches `src/`, so `make prove` is never owed by
it -- and `proof/proof.gpr` sources `src/` directly and withs nothing,
so no item may change that.

Five decisions, taken up front:

- **The functions are the seam.**  A feature calls `Price`,
  `Delta_Of`, `Implied_Vol` and `Decay_Weight` directly, on values
  the scenario names.  There is no double to script and no task to
  stop; the `Before` hook resets numbers.
- **A feature binds behavior, never how it is computed.**  Every
  check is something a consumer of graecus observes and wants
  promised -- a price, a delta, a quality, a weight, a refusal --
  never the mechanism beneath it.  `Norm_Cdf` is the mechanism
  beneath `Price` and `Delta_Of`: its fixed points are a unit test
  (G7), not a feature, even though the function is public.
  `Decay_Weight` is what a consumer's skew signal calls and the
  weight it promises, so its behavior is a feature.  The test to
  apply: would the step still hold if the implementation were
  rewritten with the same contract?
- **The steps are sml machines from the first commit.**  Each
  feature's steps are a state machine in its own child of the
  registry (`Graecus_Steps.Flows` the runner, one machine per feature,
  the registry a table of regions); conditions are guards with a
  refusing fallback row; "compute, then judge the result" is a
  follow-up event.  This is the nuntius shape as it was finally built,
  not as it was first built.
- **Decimals are read by the crate's own grammar for them.**  The
  API is `Long_Float` throughout (`Graecus.Real`), so a `{float}`
  capture is the honest reading of a feature's `7500.00`; the step
  reads it through `Fabula.Args.Real`, whose result says `Ok` or why
  not, and a guard refuses what does not read.  What a feature
  asserts is never an exact float but a tolerance the feature names
  (`within 0.005`), the same two the fixture pins.
- **No AUnit test is removed.**  The four tests are a unit test each
  (one function, or two in one call); the testing-layers guidance
  says such tests stay, fully covering their function, whatever a
  feature also states.  The fixture parity test is the crate's
  characterization truth and stays untouched.

### Do not

- Do not let the library depend on anything.  fabula, like aunit, is
  a test-only dependency: `[[depends-on]]` already carries aunit
  under the comment that says the library itself depends on nothing,
  and fabula sits beside it under the same comment.  `graecus.gpr`
  withs nothing but its config; `proof/proof.gpr` withs nothing at
  all.  G0 says what the contract allows and what it does not.
- Do not assert an exact floating-point value in a feature.  A
  scenario says a tolerance, or a classification (`computed`,
  `faint`, `clamped`), or a sign, or an order.  The fixture's
  ten-digit numbers belong to the unit test that reads the fixture.
- Do not put a fixture table in a feature file.  The 36-row parity
  fixture stays `tests/data/options_bot_greeks.csv`; a feature that
  wants a row names it (`the fixture row 4dte_atm PUT`), as nuntius
  names a byte file.
- Do not widen a subtype bound to make a scenario pass.  The bounds
  are the proof envelope; a scenario that steps outside them is
  refused by a guard, and that refusal is itself a feature.
- Do not restate a unit test's assertions line for line.  "a deep
  in-the-money call's delta is 1 to within 0.005" is a feature; "the
  call delta minus the put delta is 1 to within 1e-9" stays a unit
  test.
- Do not remove a test.  See the fourth decision above.
- Do not check how.  A step that wants an intermediate value, an
  internal count, a branch taken or a helper's own numbers is a unit
  test: write or extend the AUnit test for that function and keep
  the feature's step at the outcome.  Setup may be white-box (a
  fixture row, a named contract); the checks stay external.
- Do not fix fabula's `-gnatwu` warning (`fabula-run.adb:258`, a GNAT
  15 false positive) from here; it is a warning under the dependency
  profile and this crate builds clean with it under `--validation`
  (section 5).

## 1. What fabula is, in the terms this crate uses

A fabula binary is one instantiation of `Fabula.Main` over a
`Fabula.Registry` instance: an enumeration of step kinds, a table
mapping a Cucumber-expression pattern to a kind
(`Step ("the delta is {float} within {float}") >= E_Check_Delta`), an
enumeration of hook kinds with its table, a `Context` record one
scenario owns, and two procedures, `Execute` and `Run_Hook`.  Checks
record into an `Outcome` (`Fabula.Check.Reals.Equal`,
`Fabula.Check.Is_True`, `Fail_Step`); a step body that raises becomes
a failed step and the run goes on.  Captures read 1-based
(`Fabula.Args.Real`, `.Int`, `.Word`), each returning a result that
says `Ok` or `Malformed` / `Out_Of_Range`; a `{float}` is
`-?[0-9]*\.?[0-9]+`, so `7500`, `0.18` and `-0.5` read and `1e-3` does
not.  The binary walks its paths sorted, exits 1 on any failed
scenario, and prints `N Scenarios (...)`.

The step code is sml machines (the shape nuntius settled): each
feature's steps are the events of one `Sml.Simple_Machines` instance
over the whole `Step_Kind` and a `Step_Context` (the world, the
step's arguments, frame and outcome, and an optional follow-up event);
the table reads like the feature, with a guarded row and a refusing
fallback row wherever a condition chose a body; a step taken out of
order fails, naming every feature's state.  `Graecus_Steps.Flows` is
that runner, copied from `Nuntius_Steps.Flows` with the names changed.

Two fabula limits matter.  `Fabula.Limits.Max_Message_Length` is
512, so a failed check quotes a number, not a table; and a `{float}`
capture cannot carry an exponent, so a feature writes `0.0007392197`
rather than `7.392197e-4` -- the fixture's own spelling.

## 2. Where things live

```
tests/
  features/
    pricing.feature            G3
    delta.feature              G4
    implied-vol.feature        G5
    parity.feature             G6
    smoothing.feature          G7
  src/
    graecus_features.ads       G1  the main: Fabula.Main instantiated
    graecus_steps.ads/.adb     G1  Step_Kind, Hook_Kind, the tables, the regions
    graecus_steps-flows.ads/.adb  G2  the sml runner over Step_Kind
    graecus_steps-pricing.adb  G3  one machine per feature, one child each
    graecus_steps-delta.adb    G4
    graecus_steps-implied.adb  G5
    graecus_steps-parity.adb   G6
    graecus_steps-smoothing.adb  G7
    graecus_world.ads/.adb     G2  the contract a scenario names, and the fixture reader
    graecus_tests.ads/.adb         all four tests stay; G7 adds Test_Norm_Cdf
  data/options_bot_greeks.csv    unchanged; G6 reads a row by name
  test_graecus.gpr             G1  with "fabula"; a second main
tools/
  features-report/             G8  package.json, package-lock.json, report.js
```

## 3. The step vocabulary

Every pattern, the kind it names, and what the body does.  Numbers
are written as the operator reads them (`7500`, `0.18`, `4` days);
the step reads a `{float}` through `Fabula.Args.Real` and a guard
refuses one that does not read or lies outside the crate's subtype
for it.  A contract is composed from sentences and priced at the
first check, the same follow-up the nuntius request uses.

| Pattern | Kind | Body |
|---|---|---|
| `an SPX at {float}` | `E_Set_Spot` | `Spot`; guard: reads and in `Spot_Range` |
| `a {word} struck at {float}` | `E_Set_Contract` | `Right` from `call`/`put`, `Strike`; guards: a right the crate names, a strike in range |
| `{float} days to expiry` | `E_Set_Days` | `T := Days / 365.25`; guard: in `Year_Fraction` after the division |
| `a vol of {float}` | `E_Set_Vol` | guard: in `Vol_Range` |
| `a vol of {float} is refused` | `E_Check_Vol_Refused` | guard: reads and OUTSIDE `Vol_Range`; the refusal as a stated feature |
| `a rate of {float}` | `E_Set_Rate` | guard: in `Rate_Range` |
| `a premium of {float}` | `E_Set_Premium` | guard: in `Premium_Range` |
| `the fixture row {word} {word}` | `E_Load_Row` | the named row of `options_bot_greeks.csv` into the contract; guard: the row exists |
| `it is priced` | `E_Price` | `Price` into the world; guard: spot, strike, days, vol, rate all set |
| `its delta is taken` | `E_Delta` | `Delta_Of` into the world; same guard |
| `the vol it implies is sought` | `E_Implied` | `Implied_Vol`; guard: premium set; follow-up `E_Judged` carries the `Quality` |
| `the price is {float} within {float}` | `E_Check_Price` | `Fabula.Check.Reals` over the tolerance |
| `the price is at least {float}` | `E_Check_Price_Floor` | |
| `the delta is {float} within {float}` | `E_Check_Delta` | |
| `the delta is {word}` | `E_Check_Delta_Sign` | `positive` / `negative`; guard: one of the two words |
| `the call and put deltas sum to {float} within {float}` | `E_Check_Delta_Sum` | both rights priced from the same contract |
| `the implied vol is {float} within {float}` | `E_Check_Iv` | |
| `the implied vol is {word}` | `E_Check_Quality` | `computed` / `faint` / `clamped`; guard: a `Quality` name |
| `the implied vol recovers the vol that priced it within {float}` | `E_Check_Round_Trip` | price at the set vol, invert, compare |
| `a sample {float} time constants after the last weighs {float} within {float}` | `E_Check_Weight` | `Decay_Weight`; guard: the gap reads and is not negative |
| `a sample {float} time constants after the last is refused` | `E_Check_Weight_Refused` | guard: reads and IS negative; the `Pre` as a stated feature |
| `the fixture's IV is matched within {float}` / `delta is matched within {float}` | `E_Check_Row_Iv` / `E_Check_Row_Delta` | the loaded row's Go numbers |

### 3.1 The contract, and when it is priced

A scenario builds a contract from `Given` sentences in any order, and
the first `Then` prices it: the `Priced` state is entered by a
follow-up from the check that needed a price, exactly as nuntius sends
its composed request from the first check.  So this reads naturally:

```gherkin
Given an SPX at 7500
And a put struck at 7300
And 0.27 days to expiry
And a vol of 0.12
And a rate of 0.045
Then the delta is -1 within 0.005
```

A guard on every `Set_*` row refuses a number outside the crate's
subtype, with the bound in the message (`a vol must be in 0.0005 ..
5.0`), and the proof envelope stays what it is: the scenario that
steps outside it is refused, and `pricing.feature` has one such
scenario on purpose, so the refusal is stated too.

### 3.2 Numbers that do not fit a line

Nothing here needs a byte file: the longest feature line is a row of
five numbers.  What does not belong in a feature is the parity
fixture, 36 rows of ten-digit Go output.  It stays on disk where it
is, `tests/data/options_bot_greeks.csv`, and `parity.feature` names a
row (`the fixture row 4dte_atm PUT`); `Graecus_World.Load_Row` reads
it with the same field splitter the AUnit test has, lifted into the
world so both read one file one way.  This is the nuntius rule --
the feature names the data, it never spells it -- with the crate's
existing fixture as the named file.

## 4. Items

### G0 -- fabula is a test dependency, and the contract allows it

- **Where:** `alire.toml:14-18` (the comment "The library itself
  depends on nothing but the Ada standard library ... AUnit is
  tests-only", then `[[depends-on]]` and `aunit`); `CLAUDE.md:35-41`
  ("Dependency contract (do not break): Zero crate dependencies,
  forever"); `graecus.gpr:1` (`with "config/graecus_config.gpr"` --
  the one with, which Alire generates and which withs every
  dependency's project); `proof/proof.gpr:10-12` (sources `../src`
  directly, withs nothing).
- **What is wrong:** nothing runs a `.feature` file -- and the
  contract reads, at first sight, as if nothing may be added.
- **Why:** the contract exists because consumers subtype
  `Option_Right` from here, so any dependency of the LIBRARY becomes
  theirs.  It is stated about the library, and the manifest already
  carries aunit as a tests-only dependency under that very comment.
- **The question, and the answer:** does fabula (which brings
  `sml 3ccd0e4` and aunit) break "zero crate dependencies, forever"?
  No, on the same reading aunit does not: `graecus.gpr` withs no
  crate, so a consumer's build of graecus links nothing new; the
  proof tree withs nothing and stays the simplest of any sibling.
  What changes is `alire.toml`'s solution, which a consumer's
  workspace resolves (it must pin the same `sml` -- every ldm5180
  crate has pinned `3ccd0e4` since the 2026-10-03 chain, and fructus
  pins fabula at `746a234` itself when its own plan lands).  The
  alternative, if the maintainer reads the contract more strictly: a
  separate test-only workspace (`tests/alire.toml` with its own
  manifest pinning graecus by path, fabula and aunit), which keeps the
  crate's manifest at aunit alone at the cost of a second `alr`
  workspace to keep in step.  **Recommendation: the same manifest, as
  aunit already is** -- the contract is about the library, the
  README's "zero crate dependencies" paragraph says so in its first
  line ("one pure package, zero crate dependencies"), and a second
  workspace is a maintenance cost the siblings do not pay.  G0's
  commit says this in its message and adds one sentence to the
  CLAUDE.md contract: "test-only dependencies (aunit, fabula) are
  not the library's".
- **Decided 2026-10-03:** the same manifest, as recommended -- the
  contract is about the library, and the CLAUDE.md sentence says so.
- **Fix:** `fabula = "*"` after `aunit`, and a new `[[pins]]` table
  (the crate has none today) with
  `fabula = { url = "https://github.com/ldm5180/fabula.git", commit = "746a234df5581c2e38c4202aeee8b07473fb6a51" }`
  and a comment in the house shape: pinned by commit, test-only, and
  its `sml` pin is the one every sibling carries.
- **RED first:** `alr --non-interactive build --validation` with
  only the dependency line warns `Generating possibly incomplete
  configuration because of missing dependencies` (fabula is in no
  index; nothing withs it yet, so the build still succeeds -- the
  warning is the RED, as in nuntius); with the pin it builds clean,
  verified in section 5.

### G1 -- The feature binary builds and runs a smoke feature

- **Where:** `tests/test_graecus.gpr:1-2` (`with "aunit"; with
  "../graecus.gpr";`) and `:16` (`for Main`); `alire.toml:29-43` (the
  four `[[actions]]` of type `test`); `Makefile:8` (`.PHONY`),
  `:16-21` (`test:`), `:29-34` (`format:`, whose `tests/src/*.ad[sb]`
  glob covers the new packages); `.github/workflows/ci.yml:44`
  (the `alr test` step).
- **Fix:** `with "fabula";` beside `aunit` and
  `for Main use ("test_runner.adb", "graecus_features.ads");` -- a
  generic instantiation is a spec, so the main is an `.ads`.
  `tests/src/graecus_features.ads` instantiates `Fabula.Main` over
  `Graecus_Steps`; `tests/src/graecus_steps.ads/.adb` is a three-step
  registry whose steps ALREADY run through a two-state sml machine
  (`Empty`, `Summed`), with a guarded row and a refusing fallback --
  the smoke proves the machine shape, not only the wiring, so G2 has
  nothing to re-plumb.  `tests/features/smoke.feature` holds two
  scenarios: the sum, and a check taken before anything was added,
  which the machine refuses.  Two more `[[actions]]` after the
  existing four, argv-only like them:
  `["alr", "exec", "--", "tests/bin/release/graecus_features", "tests/features"]`
  and its `debug` twin.  The `features` target streams the runner's
  report, in colour on a terminal, and checks the summary line
  (fabula exits 0 for a missing path):

  ```make
  ## features    Build and run the Gherkin features in both modes, printing
  ##             the runner's report as it goes -- in colour when make writes
  ##             to a terminal (fabula colours only a terminal, so the runner
  ##             then runs under script(1) for a pseudo-terminal while tee
  ##             keeps a copy).  fabula exits 0 for a missing path or an
  ##             empty file, so the summary line is what says every
  ##             scenario passed
  features:
  	alr exec -- gprbuild -p -j0 -XMODE=debug -P tests/test_graecus.gpr
  	alr exec -- gprbuild -p -j0 -XMODE=release -P tests/test_graecus.gpr
  	@log=$$(mktemp) && rc=$$(mktemp) && trap 'rm -f $$log $$rc' EXIT && \
  	if [ -t 1 ]; then tty=yes; else tty=; fi; \
  	for mode in debug release; do \
  	  echo "== features ($$mode)"; \
  	  run="alr exec -- tests/bin/$$mode/graecus_features tests/features"; \
  	  { if [ -n "$$tty" ]; then script -qefc "$$run" /dev/null; \
  	    else $$run; fi; echo $$? > $$rc; } | tee $$log; \
  	  [ "$$(cat $$rc)" = 0 ] || \
  	    { echo "features: $$mode: the runner failed"; exit 1; }; \
  	  sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\r$$//' $$log | \
  	    grep -qE '^[1-9][0-9]* Scenarios? \([0-9]+ passed\)$$' || \
  	    { echo "features: $$mode: a scenario did not pass"; exit 1; }; \
  	done; echo 'features: every scenario passed in both modes'
  ```

  The CI workflow needs no new step for the features: `alr test`
  runs the actions.  `make format` already covers `tests/src/`; new
  files need `git add -N` before it runs, or it does not see them.
- **RED first:** `make features` -- "No rule to make target".  Then,
  with the target and an empty step table, the smoke scenario's steps
  are `UNDEFINED` and the binary exits 1; the rows and the machine
  turn it green.  The smoke feature, verified in section 5:

  ```gherkin
  Feature: The feature runner runs
    Scenario: Dollars are summed
      Given nothing has been priced
      When 3 dollars are added
      And 4 dollars are added
      Then the total is 7 dollars
    Scenario: A check before anything was added is refused
      Then the total is 0 dollars
  ```

  The second scenario FAILS by design (`E_CHECK_DOLLARS is not a step
  this scenario can take now`), which is the proof the machine
  refuses out-of-order steps.  **As implemented:** it runs from a
  scratch feature directory, not from `tests/features/` -- a committed
  failing scenario would fail `make features` and `alr test` at this
  commit -- and the committed smoke is the first scenario alone, which
  `pricing.feature` replaces in G3.

### G2 -- The runner, the regions and the world

- **Where:** nuntius `tests/src/nuntius_steps-flows.ads/.adb` (the
  runner to copy: a `Simple_Machines` instance over `Step_Kind` and
  `Step_Context`, the operator layer, `Take` with bounded follow-ups),
  `nuntius_steps.adb:43-110` (the region table, `Phases`, the
  `Execute` that offers each step to every region and fails one none
  took); graecus `tests/src/graecus_tests.adb:30-47` (`Field`, the
  fixture's comma splitter, to lift) and `:50-51` (the open and the
  header skip).
- **What is wrong:** after G1 the registry is one machine; five
  features need the runner shared, the dispatch as regions, and the
  fixture readable by name.
- **Why:** G1 proves the shape on one machine so this item is a
  lift, not a design.
- **Fix:** `Graecus_Steps.Flows` is nuntius's runner renamed
  (`with Sml.Machines.Operators` is needed to instantiate an
  instance's operator child).  `Step_Context` gains `Then_Take` and
  the helpers every machine's guards share: `Real_Read (Ctx, N)`,
  `Real_Of (Ctx, N)`, `Refuse_Real (Ctx, N)` (the `Count_Read` /
  `Count` / `Refuse_Count` trio of nuntius, over `Fabula.Args.Real`).
  `Graecus_World` holds the contract record one scenario names
  (`Spot`, `Strike`, `Days`, `Vol`, `Rate`, `Right`, `Premium`, each
  with a `Set` flag), what was computed (`Price`, `Delta`, `Iv`,
  `Quality`), and `Load_Row (Name, Right, Row, Found)` over the
  fixture file, `Field` lifted from the AUnit test and that test
  calling it from the world.  The registry body becomes the region
  table.
- **RED first:** the AUnit suite with its `Field` deleted and
  `with Graecus_World;` added fails to compile on the first missing
  name; green when `make test` passes 4/4 both modes with no
  assertion changed, and the smoke feature still runs through
  `Flows.Take`.

### G3 -- `pricing.feature`: a premium is never negative, and intrinsic is a floor

- **Where:** `src/graecus.ads:74-81` (`Price` and its `Post`),
  `:31-45` (the five subtypes, the proof envelope);
  `tests/src/graecus_tests.adb:144-166` (`Test_Properties`, the
  put-call parity check).
- **What is wrong:** that a price is never negative, that an
  in-the-money contract is worth at least its intrinsic value, that
  the proof envelope refuses what lies outside it, and that two
  calls with the same inputs price the same, are stated as a `Post`
  and a comment a consumer has to find.
- **Why:** they were proved, not told.
- **Fix:** the first feature, and the one that defines the
  vocabulary of section 3.1:

  ```gherkin
  Feature: A premium is a price, never a debt

    Background:
      Given an SPX at 7500
      And a rate of 0.045

    Scenario Outline: An option is worth at least its intrinsic value
      Given a <right> struck at <strike>
      And 4 days to expiry
      And a vol of 0.18
      Then the price is at least <intrinsic>

      Examples:
        | right | strike | intrinsic |
        | call  | 7300   | 200       |
        | call  | 7700   | 0         |
        | put   | 7700   | 200       |
        | put   | 7300   | 0         |

    Scenario: Far out of the money and about to expire, a call is worth nothing
      Given a call struck at 8000
      And 0.27 days to expiry
      And a vol of 0.12
      Then the price is 0 within 0.0001

    Scenario: A vol outside the envelope is refused, not clamped
      Given a call struck at 7500
      And 4 days to expiry
      Then a vol of 7 is refused
  ```

  The last scenario cannot be written as a refused `Given` -- a
  feature suite must pass, and fabula has no expected-failure marker
  (section 5, item 4).  It becomes `Then a vol of 7 is refused`: a
  step whose guard passes on a number OUTSIDE `Vol_Range` and whose
  action checks the refusal's bound, so the envelope is a stated
  feature and the suite stays green.  The same shape serves G7's
  negative gap.
- **RED first:** `make features` reports `an SPX at 7500`
  `UNDEFINED`; each row turns one step green, Background first.  The
  intrinsic values are what `Test_Properties` implies (a 7480 call
  on a 7500 spot is worth more than 20).

### G4 -- `delta.feature`: signed, bounded, and 1 apart

- **Where:** `src/graecus.ads:84-91` (`Delta_Of`, SIGNED, puts
  negative, `Post` in `-1.0 .. 1.0`);
  `tests/src/graecus_tests.adb:163-165` (the sign and the
  `Dc - Dp = 1` checks).
- **What is wrong:** that puts are negative, that a deep
  in-the-money contract's delta nears +/-1 and a far out-of-the-money
  one nears 0, and that the call and put deltas of one contract
  differ by exactly 1, are the facts a stop logic depends on, stated
  in a comment and three asserts.
- **Fix:** scenarios over the composed contract: an outline of
  `(right, strike) -> sign`; a deep call at 7300 on 7500 with 0.27
  days is `1 within 0.005` and the matching put `-1 within 0.005`
  (the fixture's `0dte_calm_deep` pair says so to ten digits); a far
  OTM call is `0 within 0.005`; "the call and put deltas sum to 0
  within 0.01" for the at-the-money contract (the straddle).  The
  identity `Dc - Dp = 1` to 1e-9 is the mechanism's own property and
  stays in `Test_Properties`, as the Do-not list says.
- **RED first:** `its delta is taken` is `UNDEFINED`; green on the
  sign outline.

### G5 -- `implied-vol.feature`: a premium's vol, or why there is none

- **Where:** `src/graecus.ads:47-55` (`Quality` and its three
  meanings), `:99-107` (`Implied_Vol`, the bisection and the band);
  `tests/src/graecus_tests.adb:175-207` (`Test_Round_Trip`, up to 656
  rows of price-then-invert, the `Computed` ones checked).
- **What is wrong:** the crate's most important sentence --
  "trust V only when Q = Computed" -- and the three regimes behind
  it are stated in the README and nowhere a gate reads them.
- **Why:** the regimes were ported from a Go library's behavior and
  pinned by fixture rows.
- **Fix:** scenarios: the vol that priced a premium is the vol it
  implies (`recovers the vol that priced it within 0.00000001`, the
  round trip's own tolerance); a premium at intrinsic is `clamped`
  and its delta still `1 within 0.005`; a zero premium on an OTM call
  is `clamped` with delta `0 within 0.005`; a deep ITM contract near
  expiry is `faint` -- the IV untrustworthy while the delta holds.
  The quality word is a guard with a refusing fallback
  (`no quality named cheap`).  The `Implied` action posts `E_Judged`
  and the next row's guard reads the `Quality` -- the follow-up
  pattern -- so "sought, then judged" is two rows, not an if.
- **RED first:** `the vol it implies is sought` is `UNDEFINED`;
  green on the round trip at the `Test_Properties` contract (7500 /
  7480 / 4 days / 0.18).

### G6 -- `parity.feature`: the fixture, by name

- **Where:** `tests/data/options_bot_greeks.csv` (36 rows, the Go
  library's own output); `tests/src/graecus_tests.adb:21-139`
  (`Test_Fixture_Parity`: every row within 2e-3 IV / 0.005 delta,
  the Faint/Clamped rows classified).
- **What is wrong:** the parity contract is the reason the crate can
  be trusted, and the only place it is stated is inside a 120-line
  test with a hand-written CSV splitter.
- **Why:** the fixture arrived with the port, as a test.
- **Fix:** an outline over named rows -- `the fixture row <case>
  <right>` loads spot, strike, time, premium and the Go numbers; `the
  fixture's IV is matched within 0.002` and `delta is matched within
  0.005` check them; a `Scenario Outline` lists the twelve cases a
  reader learns the regimes from (`0dte_calm_*`, `4dte_*`,
  `8dte_badseed_atm`, `xsp_atm`, `at_intrinsic`, `below_intrinsic`,
  `zero_premium`).  The AUnit test still walks all 36 rows; the
  feature tells the story of twelve.  A row name the file does not
  hold fails the step with the name.
- **RED first:** `the fixture row 4dte_atm PUT` is `UNDEFINED`; green
  when the row's IV matches within 0.002.

### G7 -- `smoothing.feature`: how fast a new sample takes over

- **Where:** `src/graecus.ads:70` (`Decay_Weight`, the EMA weight of
  a new sample X time constants after the last; `Pre => X >= 0.0`);
  `tests/src/graecus_tests.adb:211-220` (`Test_Decay`); `:64`
  (`Norm_Cdf`), which this item gives a unit test of its own.
- **What is wrong:** what a consumer's IV-skew smoothing can rely on
  -- a sample arriving at once has no weight, one arriving a time
  constant later weighs about 0.632, one after a long gap replaces
  the signal outright, and a gap cannot be negative -- is stated in a
  comment and one assert.
- **Why:** the function was ported as a helper, with the signal that
  calls it living in another crate.
- **Fix:** one outline in the consumer's words, each row a gap and
  the weight it earns within a tolerance (`0` -> `0`, `1` -> `0.632
  within 0.001`, `800` -> `1 within 0.000001`), and one scenario
  stating that a negative gap is refused (the `Pre` as a feature,
  the G3 shape).  `Norm_Cdf`'s fixed points -- 0.5 at zero,
  saturation at +/-40 -- are how `Price` and `Delta_Of` compute, not
  what a consumer calls; they get `Test_Norm_Cdf` in the AUnit suite
  beside `Test_Decay` (the same three rows, to 1e-6) and no feature.
- **RED first:** `a sample 1 time constants after the last weighs
  0.632 within 0.001` is `UNDEFINED`; green on that row.  The unit
  side: `Test_Norm_Cdf` registered and asserting 0.5 at zero.

### G8 -- The living documentation

- **Where:** `.github/workflows/ci.yml:22-47` (the `build-and-test`
  job: validation build, `alr test`, `make run`), `:26` and `:29`
  (`actions/checkout@v5`, `alire-project/setup-alire@v6`);
  `Makefile:24` (`prove:`, before which the new target sits);
  `.gitignore` (gains `/tools/features-report/node_modules/`).
- **What is wrong:** the features are the readable statement of what
  the greeks do, and they are readable only with a checkout.
- **Fix:** `tools/features-report/` (`package.json` with
  multiple-cucumber-html-reporter, its committed `package-lock.json`,
  and `report.js` -- nuntius's, with the names changed); a
  `features-report` target that runs the release features with
  `--report-json obj/features-report/json/features.json`, renders
  `obj/features-report/html`, and exits with the runner's status
  AFTER rendering (the page is most worth reading when a scenario
  failed); in CI, `actions/setup-node@v7` (node 22, npm cache on the
  lockfile), `make features-report` and `actions/upload-artifact@v7`
  on every run (`if: success() || failure()`), then
  `actions/upload-pages-artifact@v5` on a push to `main` and a
  `pages` job (`needs: build-and-test`, `permissions: pages: write,
  id-token: write`, `environment: github-pages`,
  `actions/deploy-pages@v5`).  Pages is enabled once with
  `gh api -X POST repos/ldm5180/graecus/pages -f build_type=workflow`;
  the page lands at `https://ldm5180.github.io/graecus/`.
- **RED first:** `make features-report` -- "No rule to make target";
  then the target with no `tools/features-report` fails on `npm ci`;
  green when `obj/features-report/html/index.html` exists and names
  five features.  Then break one expectation: the page is still
  rendered and the target exits non-zero.

### G9 -- The docs say so

- **Where:** `CLAUDE.md:10-18` ("Commands"), `:27` (the `tests/`
  layout line), `:35-49` ("Dependency contract", which G0 touched),
  `:51-57` ("Conventions", the file's last section);
  `README.md:58-68` ("Develop").
- **Fix:** `make features` and `make features-report` lines in both;
  the layout line names `tests/features/`, `graecus_features.ads`,
  the machines and the world; "Conventions" gains the testing-layers
  guidance in the house words: a unit test typically tests a single
  function or a simple interaction between two and always covers it
  completely, a feature tests the larger interactions that form a
  higher-level conceptual feature, duplication across the two is
  fine, and a test goes only when it is an integration test a
  scenario fully supplants -- which, in a crate of five pure
  functions, is none.  The README links the published page.

## 5. Verified in a scratch worktree (iteration 3)

Against the tree at `6913425`, in a detached worktree under the
session scratchpad, GNAT 15.2.0, gprbuild 26.0.1, 2026-10-03:

1. `fabula = "*"` pinned at `746a234` beside `aunit`, in a new
   `[[pins]]` table: `alr --non-interactive build --validation`
   succeeds -- build 1.96 s, 3.9 s wall -- with no pin conflict and no
   warning.  graecus pins no `sml` of its own, so fabula's `3ccd0e4`
   is the only link and the question the nuntius chain had to settle
   does not arise here.
2. The G1 sketch typed in: `with "fabula"`, the second main
   `graecus_features.ads`, `graecus_steps.ads/.adb` as a two-state
   sml machine (`Empty`, `Summed`; `Count_Read` guard with a refusing
   fallback; `Sml.Simple_Machines` over `Step_Kind`, the operator
   layer on the instance), `tests/features/smoke.feature` with two
   scenarios.  `gprbuild -P tests/test_graecus.gpr` builds both mains
   in 2.2 s.  The run: scenario one `4 Steps (4 passed)`; scenario two
   fails on `E_CHECK_DOLLARS is not a step this scenario can take
   now` -- the refusal the machine shape is for, exactly as G1 says.
   Exit 1, as a failing scenario must.
3. The AUnit suite, rebuilt against the same gpr with fabula in it:
   `Successful Tests: 4`, `Failed Assertions: 0`.
4. Not verified here: the `@refused` idea in G3 (a scenario whose
   refusal is its pass).  fabula has no "expected failure" marker;
   the RED of G3 decides between dropping that scenario and a
   `the vol {float} is refused` step whose GUARD passes on an
   out-of-range number and whose action checks the bound -- the
   second keeps the refusal a stated feature and is the likelier
   outcome.

## 6. The second wave, sketched

- **The envelope, as outlines.**  Each subtype bound as a scenario
  pair (`just inside` passes, `just outside` is refused), so a
  widening of the proof envelope is a feature change a reader sees.
- **The bench.**  `bench/` measures microseconds per `Implied_Vol`;
  a feature cannot assert a timing, and should not.  Out of scope.
- **The example.**  `example/src/iv_of_premium.adb` is the consumer
  story end to end; once `implied-vol.feature` states the same, the
  example is a demo, not a test.

## Revision notes

- **Iteration 1 (draft):** the seam (the five functions), the
  layout, the step table with the composed contract, ten items, a
  second wave; the nuntius plan's shape with its world replaced by
  numbers, and the three adjustments the nuntius work settled -- sml
  machines from the first commit, a streaming coloured `make
  features`, the living documentation -- as items of their own (G1,
  G2, G8).
- **Iteration 2 (as a newcomer):** added "How to use this plan" with
  the four up-front decisions, the "Do not" list, section 1 (fabula
  in this crate's terms, with the two limits that bite: no exponent
  in a `{float}`, a 512-byte failure message), 3.1 (the contract
  composed from sentences and priced at the first check, the
  follow-up pattern), 3.2 (the fixture as the named file, no byte
  files needed), a full Gherkin sketch for G3 and the Makefile for
  G1, and a RED per item.  Made the dependency question G0's whole
  "What is wrong" after reading the contract as a newcomer would and
  stopping at "forever".  Noted the `@refused` scenario in G3 as a
  decision for the RED, not a promise.
- **Iteration 3 (against the tree at `6913425`, and the scratch
  builds of section 5):** every `file:line` re-located.
  Corrected: `Price` is `graecus.ads:74-81`, not `67-77`; `Delta_Of`
  `84-91`, not `79-89`; `Implied_Vol` `99-107`, not `91-105`;
  `Quality` is one line, `:55`, and its explanation `:47-54`;
  `Norm_Cdf` and `Decay_Weight` are `:64` and `:70`, not `59-65`; the
  subtypes `:31-45`, not `28-45`.  In the suite, `Field` is `30-47`
  (not `33-50`), the open and header skip `50-51`, `Test_Properties`
  `144-166` (not `173`), the two delta checks `163-165`,
  `Test_Round_Trip` `175-207`, `Test_Decay` `211-220`,
  `Test_Fixture_Parity` `21-139` (not `142`).  `CLAUDE.md`'s
  "Conventions" starts at 51 and the contract's four bullets are
  `37-49`; `ci.yml`'s `build-and-test` job is `22-47` and its `alr
  test` step line 44.  The G0 RED was first written as "fails to
  resolve"; the scratch shows the nuntius behavior instead -- a
  warning and a successful build, since nothing withs fabula yet --
  and the text now says so.  Confirmed: `aunit` at `alire.toml:18`,
  the four actions `29-43`, `for Main` at `tests/test_graecus.gpr:16`,
  `test:` at `Makefile:17`, `prove:` at `:24`.
- **After the behavior guidelines (2026-10-03):** a fifth up-front
  decision and a Do-not entry -- a feature binds behavior, never how
  it is computed.  G7 was `weights.feature` over both helpers; the
  CDF's fixed points are the mechanism beneath `Price` and
  `Delta_Of`, so they leave the feature for a new `Test_Norm_Cdf`
  in the AUnit suite, and the item becomes `smoothing.feature` over
  `Decay_Weight` alone, worded as what a consumer's skew signal
  relies on (two vocabulary rows replace two).  G4's "differ by 1"
  second check contradicted the Do-not list that already placed the
  `Dc - Dp = 1` identity in `Test_Properties`; dropped from the
  feature.  G3, G5 and G6 were already clean: prices, deltas, the
  `Quality` a consumer receives, and the parity contract are the
  crate's externally visible promises; the fixture setup stays
  white-box by design.
- **As implemented (2026-10-03):** G0 decided as recommended (the same
  manifest).  G1's out-of-order smoke scenario ran from a scratch
  directory instead of `tests/features/`, so every commit keeps the
  features green; it reported `E_CHECK_DOLLARS is not a step this
  scenario can take now: EMPTY`, as section 5 had.
