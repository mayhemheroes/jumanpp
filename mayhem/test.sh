#!/usr/bin/env bash
#
# mayhem/test.sh — RUN jumanpp's full upstream ctest (Catch) suite built by mayhem/build.sh.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
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

if [ ! -f build-tests/CTestTestfile.cmake ]; then
  echo "FATAL: build-tests/ missing — mayhem/build.sh must build the test suite" >&2
  emit_ctrf "cmake-ctest" 0 1 0
  exit 1
fi

log=/tmp/ctest.log
( cd build-tests && ctest -j"$MAYHEM_JOBS" -V ) | tee "$log"
ctest_rc=${PIPESTATUS[0]}

# ctest suite-level summary: "100% tests passed, 0 tests failed out of 10"
total=$(sed -n 's/.*out of \([0-9]\+\).*/\1/p' "$log" | tail -1)
failed=$(sed -n 's/.*, \([0-9]\+\) tests failed.*/\1/p' "$log" | tail -1)
if [ -z "${total:-}" ] || [ -z "${failed:-}" ]; then
  echo "FATAL: could not parse ctest summary" >&2
  emit_ctrf "cmake-ctest" 0 1 0
  exit 1
fi

# Behavioral assertion: each passing Catch runner must actually REPORT its assertions
# ("All tests passed (N assertions in M test cases)"). Counts are at Catch test-case
# granularity; a runner that exits 0 without running its cases is a failure.
read -r ok_runners cases assertions < <(sed 's/\x1b\[[0-9;]*m//g' "$log" \
  | sed -n 's/.*All tests passed[^(]*(\([0-9]\+\) assertions\? in \([0-9]\+\) test cases\?).*/\1 \2/p' \
  | awk '{n++; a+=$1; c+=$2} END {print n+0, c+0, a+0}')
echo "catch: $ok_runners runners reported $cases test cases / $assertions assertions"

if [ "$ctest_rc" -ne 0 ] || [ "$failed" -ne 0 ]; then
  emit_ctrf "cmake-ctest" "$cases" "$(( failed > 0 ? failed : 1 ))" 0
  exit 1
fi
if [ "$ok_runners" -ne "$total" ] || [ "$cases" -eq 0 ] || [ "$assertions" -eq 0 ]; then
  echo "FATAL: ctest exited 0 but only $ok_runners/$total runners reported Catch results — behavioral check failed" >&2
  emit_ctrf "cmake-ctest" "$cases" 1 0
  exit 1
fi
emit_ctrf "cmake-ctest" "$cases" 0 0
