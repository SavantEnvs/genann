#!/usr/bin/env bash
#
# mayhem/build.sh — build genann's fuzz harnesses and its test suite.
#
# genann is a single C99 file (genann.c) with libm as its only dependency; upstream's Makefile
# hard-codes -O3 -march=native, so the library is compiled directly here instead.
#   * fuzz harnesses (libFuzzer + -standalone reproducers) -> /mayhem/fuzz_*  with genann.c
#     compiled under $SANITIZER_FLAGS $DEBUG_FLAGS (the fuzzed code is instrumented).
#   * upstream's test suite (test.c, minctest) with normal flags -> mayhem/out/genann_test.
# No network access; re-runnable on an already-built tree.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
OUT="$SRC/mayhem/out"
mkdir -p "$OUT"

# 1) The library, sanitized + DWARF 3, twice: with SanCov (-fsanitize=fuzzer-no-link, so the
#    libFuzzer binaries get coverage feedback from genann.c itself, not only the harness TU) and
#    without it (for the -standalone reproducers, which link no libFuzzer runtime). Plus the
#    LeakSanitizer opt-out (leaks are not the bug class fuzzed here; ASan and UBSan stay fully on).
COV="-fsanitize=fuzzer-no-link"
LIBFLAGS="-O1 -std=c99 -D_POSIX_C_SOURCE=200809L -I$SRC"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS $COV $LIBFLAGS -c "$SRC/genann.c" -o "$OUT/genann_fuzz.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIBFLAGS -c "$SRC/genann.c" -o "$OUT/genann_standalone.o"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$OUT/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -x c -c "$STANDALONE_FUZZ_MAIN" -o "$OUT/standalone_main.o"

# 2) Each harness twice: libFuzzer binary and run-once standalone reproducer.
for h in fuzz_read fuzz_train; do
    $CC $SANITIZER_FLAGS $DEBUG_FLAGS $COV -O1 -D_GNU_SOURCE -I"$SRC" \
        -c "$SRC/mayhem/harnesses/$h.c" -o "$OUT/$h.o"
    $CC $SANITIZER_FLAGS $DEBUG_FLAGS -O1 -D_GNU_SOURCE -I"$SRC" \
        -c "$SRC/mayhem/harnesses/$h.c" -o "$OUT/$h-standalone.o"
    $CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
        "$OUT/$h.o" "$OUT/genann_fuzz.o" "$OUT/lsan_off.o" -lm -o "$SRC/$h"
    $CC $SANITIZER_FLAGS $DEBUG_FLAGS \
        "$OUT/standalone_main.o" "$OUT/$h-standalone.o" "$OUT/genann_standalone.o" "$OUT/lsan_off.o" -lm \
        -o "$SRC/$h-standalone"
done

# 3) Upstream's own test suite (test.c + minctest.h), normal flags (no sanitizers).
$CC -O2 -Wall $COVERAGE_FLAGS -I"$SRC" "$SRC/test.c" "$SRC/genann.c" -lm -o "$OUT/genann_test"
