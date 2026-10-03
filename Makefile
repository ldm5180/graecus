# Thin wrapper around Alire + gprbuild so the common flows are one word.  Every
# target runs through `alr` (so the aunit/gnatprove dependencies resolve).  The
# example and tests build in two profiles selected with -XMODE (sml-ada
# convention): release (-O3) and debug (-O0).

EX := -P example/example.gpr

.PHONY: all build test features features-report prove format example release debug run bench bench-build clean help

all: build

## build       Build the library
build:
	alr build

## test        Build and run the AUnit suite in both modes (per-test output)
test:
	alr exec -- gprbuild -p -j0 -XMODE=debug -P tests/test_graecus.gpr
	alr exec -- tests/bin/debug/test_runner
	alr exec -- gprbuild -p -j0 -XMODE=release -P tests/test_graecus.gpr
	alr exec -- tests/bin/release/test_runner

## features    Build and run the Gherkin features in both modes, printing
##             the runner's report as it goes -- in colour when make writes
##             to a terminal: fabula colours only a terminal, so the runner
##             then runs under script(1) for a pseudo-terminal while tee
##             keeps a copy.  fabula exits 0 for a missing path or an empty
##             file, so the summary line, not the exit status alone, is
##             what says every scenario passed
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

## features-report  The living documentation: run the features (release)
##             with --report-json and render it into
##             obj/features-report/html with multiple-cucumber-html-reporter
##             (tools/features-report).  The page is made even when a
##             scenario fails -- that is when it is most worth reading --
##             and the target then fails with the runner.
features-report:
	alr exec -- gprbuild -p -j0 -XMODE=release -P tests/test_graecus.gpr
	@rm -rf obj/features-report && mkdir -p obj/features-report/json
	@alr exec -- tests/bin/release/graecus_features tests/features \
	   --report-json obj/features-report/json/features.json; rc=$$?; \
	 npm ci --prefix tools/features-report --no-audit --no-fund && \
	 node tools/features-report/report.js obj/features-report/json \
	   obj/features-report/html && exit $$rc

## prove       Run the SPARK proof (same flags as CI)
prove:
	alr exec -- gnatprove -P proof/proof.gpr -j0 --level=2 --checks-as-errors=on \
	  --warnings=error

## format      Check formatting (per project, explicit files; no warnings)
format:
	alr exec -- gnatformat -P graecus.gpr --check $$(git ls-files 'src/*.ad[sb]')
	alr exec -- gnatformat -P tests/test_graecus.gpr --check $$(git ls-files 'tests/src/*.ad[sb]')
	alr exec -- gnatformat -P example/example.gpr --check $$(git ls-files 'example/src/*.ad[sb]')
	alr exec -- gnatformat -P proof/proof.gpr --check $$(git ls-files 'proof/src/*.ad[sb]')
	alr exec -- gnatformat -P bench/bench.gpr --check $$(git ls-files 'bench/src/*.ad[sb]')

## example     Build the example both ways
example: release debug

## release     Build the example (-O3)
release:
	alr exec -- gprbuild -p -XMODE=release $(EX)

## debug       Build the example (-O0)
debug:
	alr exec -- gprbuild -p -XMODE=debug $(EX)

## run         Build and run the release example
run: release
	./example/bin/release/iv_of_premium

## bench       Build and run the CPU micro-benchmark (-O3, offline)
#  Run it TWICE and take the second: the first after a build reads high.
#  Absolute numbers only compare within one sitting on one box -- what
#  survives across sittings is the ratio between two runs of this same
#  harness.  BENCH_PASSES overrides the pass count (default 40).
bench: bench-build
	./bench/bin/release/bench_graecus $(BENCH_PASSES)

## bench-build Compile the benchmark without running it
#  bench/bench.gpr is in no other build: `alr build` never sees it, and
#  the test suite does not link it.
#
#  `alr build --release` FIRST, and not as a nicety: bench.gpr links
#  graecus.gpr, which compiles with whatever profile the generated
#  config/graecus_config.gpr currently names -- and alr REWRITES that
#  file on every `alr build`, `alr build --validation`, and so on.  A
#  `make prove` or a validation build between two bench runs therefore
#  silently moves the library from -O3 to -Og, and the second run reads
#  2.6x slower for no reason in the source.  Pinning it here is what
#  makes two runs comparable at all.
bench-build:
	alr build --release
	alr exec -- gprbuild -p -j0 -XMODE=release -P bench/bench.gpr

## clean       Remove all build artifacts
clean:
	-alr exec -- gprclean -XMODE=release $(EX)
	-alr exec -- gprclean -XMODE=debug $(EX)
	alr clean

## help        List targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'
