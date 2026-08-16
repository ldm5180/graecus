# Thin wrapper around Alire + gprbuild so the common flows are one word.  Every
# target runs through `alr` (so the aunit/gnatprove dependencies resolve).  The
# example and tests build in two profiles selected with -XMODE (sml-ada
# convention): release (-O3) and debug (-O0).

EX := -P example/example.gpr

.PHONY: all build test prove format example release debug run bench bench-build clean help

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
bench-build:
	alr exec -- gprbuild -p -j0 -XMODE=release -P bench/bench.gpr

## clean       Remove all build artifacts
clean:
	-alr exec -- gprclean -XMODE=release $(EX)
	-alr exec -- gprclean -XMODE=debug $(EX)
	alr clean

## help        List targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'
