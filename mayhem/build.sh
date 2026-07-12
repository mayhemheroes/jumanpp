#!/usr/bin/env bash
#
# mayhem/build.sh — build jumanpp's fuzz target(s) + its full ctest suite.
#
# Targets:
#   /mayhem/jpp_jumandic_bootstrap             — in-process libFuzzer harness
#       (mayhem/fuzz/bootstrap_fuzz.cc) over the same DictionaryBuilder.importCsv()
#       pipeline the original jpp-jumandic-bootstrap file-input CLI drove. The raw
#       CLI recorded 0 edges under Mayhem once ASan-instrumented (black-box file
#       target), so per SPEC §6.2 item 11 it is converted to an instrumented
#       libFuzzer harness over the same code path; the Mayhem target NAME is kept.
#   /mayhem/jpp_jumandic_bootstrap-standalone  — run-once reproducer (same harness
#       linked against $STANDALONE_FUZZ_MAIN, no libFuzzer runtime).
# Test suite:
#   build-tests/                               — full upstream CMake/Catch test suite
#                                                (normal flags), run by mayhem/test.sh via ctest.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# 1) Sanitized+SanitizerCoverage+DWARF-3 build of the project libraries (fuzzer-no-link adds the
#    coverage guards to the library code without pulling in libFuzzer's main).
#    Protobuf stays off (JPP_USE_PROTOBUF=OFF keeps the build deterministic/offline).
FUZZ_FLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS"
cmake -S . -B build-fuzz \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$FUZZ_FLAGS" \
  -DCMAKE_CXX_FLAGS="$FUZZ_FLAGS" \
  -DJPP_ENABLE_TESTS=OFF -DJPP_USE_PROTOBUF=OFF
cmake --build build-fuzz -j"$MAYHEM_JOBS" --target jpp_jumandic_bootstrap

JPP_INC="-I$SRC/src -I$SRC/libs -I$SRC/libs/pathie-cpp/include \
  -I$SRC/build-fuzz/src/core/cfg -I$SRC/build-fuzz/src/util/cfg"
JPP_LIBS="$SRC/build-fuzz/src/jumandic/libjpp_jumandic.a \
  $SRC/build-fuzz/src/jumandic/libjpp_jumandic_spec.a \
  $SRC/build-fuzz/src/core/libjpp_core.a \
  $SRC/build-fuzz/src/core/codegen/libjpp_core_codegen.a \
  $SRC/build-fuzz/libs/pathie-cpp/libpathie.a \
  $SRC/build-fuzz/src/rnn/libjpp_rnn.a \
  $SRC/build-fuzz/src/util/libjpp_util.a"

# 2) Harness twice: fuzzer binary + standalone run-once reproducer.
#    shellcheck disable=SC2086
$CXX $FUZZ_FLAGS $LIB_FUZZING_ENGINE -std=c++14 $JPP_INC \
  "$SRC/mayhem/fuzz/bootstrap_fuzz.cc" $JPP_LIBS -lpthread \
  -o /mayhem/jpp_jumandic_bootstrap
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o
# shellcheck disable=SC2086
$CXX $FUZZ_FLAGS -std=c++14 $JPP_INC \
  "$SRC/mayhem/fuzz/bootstrap_fuzz.cc" /tmp/standalone_main.o $JPP_LIBS -lpthread \
  -o /mayhem/jpp_jumandic_bootstrap-standalone

# 3) Full upstream test suite with NORMAL flags (independent build; test.sh only RUNS it).
cmake -S . -B build-tests \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
  -DJPP_ENABLE_TESTS=ON -DJPP_USE_PROTOBUF=OFF
cmake --build build-tests -j"$MAYHEM_JOBS"

echo "build.sh: done"
