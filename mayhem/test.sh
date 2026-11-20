#!/usr/bin/env bash
#
# mayhem/test.sh — RUN genann's own test suite (test.c, built by mayhem/build.sh) and report CTRF.
#
# test.c uses minctest: every assertion (lok/lequal/lfequal) checks a known value — fixed-weight
# outputs, backprop deltas, trained XOR/AND/OR results, a genann_write/genann_read round trip,
# genann_copy equality, cached vs exact sigmoid. Each test group prints "pass:N fail:M"; those
# assertion counts are summed here. A suite that prints no results (e.g. a neutered binary) fails.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
: "${SRC:=/mayhem}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

RUNNER="$SRC/mayhem/out/genann_test"
if [ ! -x "$RUNNER" ]; then
  echo "test.sh: $RUNNER missing — mayhem/build.sh must build it" >&2
  emit_ctrf minctest 0 1
  exit 1
fi

# test.c's persist test writes persist.txt into the cwd; run in a scratch dir.
work="$(mktemp -d "${TMPDIR:-/tmp}/genann-test.XXXXXX")"
out="$(cd "$work" && "$RUNNER" 2>&1)"
rc=$?
rm -rf "$work"
printf '%s\n' "$out"

groups=$(grep -cE 'pass: *[0-9]+ +fail: *[0-9]+' <<<"$out" || true)
passed=$(grep -oE 'pass: *[0-9]+' <<<"$out" | grep -oE '[0-9]+' | awk '{s+=$1} END{print s+0}')
failed=$(grep -oE 'fail: *[0-9]+' <<<"$out" | grep -oE '[0-9]+' | awk '{s+=$1} END{print s+0}')

# The suite runs 13 test groups and ends with "ALL TESTS PASSED (n/n)"; anything else
# (missing groups, no summary line, non-zero exit) is a failure.
if [ "$groups" -ne 13 ] || ! grep -qE "^ALL TESTS PASSED \(${passed}/${passed}\)$" <<<"$out" || [ "$rc" -ne 0 ]; then
  echo "test.sh: suite incomplete or failing (groups=$groups rc=$rc)" >&2
  [ "$failed" -gt 0 ] || failed=1
fi
emit_ctrf minctest "$passed" "$failed"
