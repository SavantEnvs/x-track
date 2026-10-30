#!/usr/bin/env bash
#
# mayhem/build.sh — builds the sanitized fuzz harnesses (json_fuzzer, msgpack_fuzzer) + their
# -standalone reproducers, and ArduinoJson's own Catch test suite with NORMAL flags (run by test.sh).
# Runs in the commit image as `mayhem` in /mayhem. ArduinoJson is header-only, so the "project"
# is instrumented by compiling the harnesses with $SANITIZER_FLAGS. Fully offline, idempotent.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
AJ="$SRC/Software/X-Track/USER/App/Utils/ArduinoJson"
OUT="$SRC"

# 1) Fuzz harnesses (libFuzzer + standalone), with the leak-sanitizer hook linked in.
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o /tmp/lsan_off.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o
for h in json_fuzzer msgpack_fuzzer; do
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS -std=c++11 -I"$AJ/src" $LIB_FUZZING_ENGINE \
      "$SRC/mayhem/$h.cpp" /tmp/lsan_off.o -o "$OUT/$h"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS -std=c++11 -I"$AJ/src" \
      "$SRC/mayhem/$h.cpp" /tmp/standalone_main.o /tmp/lsan_off.o -o "$OUT/$h-standalone"
done

# 1b) X-Track's own GPX_Parser (+ the Stream/WString utilities it sits on) instrumented, linked into
#     the gpx_parser_fuzzer harness. gpx_support.h stubs the few LVGL symbols those utilities use.
XT="$SRC/Software/X-Track"; UT="$XT/USER/App/Utils"
GPX_INC="-I$XT/USER/App -I$UT -I$XT/Simulator/LVGL.Simulator -I$SRC/mayhem"
GPX_CXX_SRCS="$UT/GPX_Parser/GPX_Parser.cpp $UT/Stream/Stream.cpp $UT/Stream/Print.cpp $UT/WString/WString.cpp"
GPX_C_SRCS="$UT/WString/dtostrf.c $UT/WString/itoa.c"
gpx_objs() {  # <flags> <objdir>: compile the GPX library sources to objects, print their paths
  local flags="$1" dir="$2" s o; mkdir -p "$dir"
  for s in $GPX_CXX_SRCS; do o="$dir/$(basename "$s").o"; $CXX $flags $GPX_INC -c "$s" -o "$o"; echo "$o"; done
  for s in $GPX_C_SRCS;   do o="$dir/$(basename "$s").o"; $CC  $flags $GPX_INC -c "$s" -o "$o"; echo "$o"; done
}
# The libFuzzer build compiles the library sources with -fsanitize=fuzzer-no-link: $LIB_FUZZING_ENGINE
# only instruments the harness TU, so without it libFuzzer sees no coverage inside GPX_Parser.
GPX_OBJS=$(gpx_objs "$SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link" /tmp/gpx-fuzz)
GPX_OBJS_SA=$(gpx_objs "$SANITIZER_FLAGS $DEBUG_FLAGS" /tmp/gpx-san)
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $GPX_INC $LIB_FUZZING_ENGINE "$SRC/mayhem/gpx_parser_fuzzer.cpp" \
    $GPX_OBJS /tmp/lsan_off.o -o "$OUT/gpx_parser_fuzzer"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $GPX_INC "$SRC/mayhem/gpx_parser_fuzzer.cpp" \
    $GPX_OBJS_SA /tmp/standalone_main.o /tmp/lsan_off.o -o "$OUT/gpx_parser_fuzzer-standalone"

# 2) The project's own Catch test suite, NORMAL flags (no sanitizers, not DEBUG_FLAGS).
# Fresh configure every run: a re-run may resolve the compiler through a different PATH (ccache
# masquerade vs /usr/bin), and cmake then discards the cached flags mid-build.
rm -rf "$SRC/mayhem/build-tests"
env -u CFLAGS -u CXXFLAGS -u LDFLAGS cmake -S "$AJ" -B "$SRC/mayhem/build-tests" -G Ninja \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS="-Wno-error -DCATCH_CONFIG_NO_POSIX_SIGNALS $COVERAGE_FLAGS" -DCMAKE_EXE_LINKER_FLAGS="$COVERAGE_FLAGS"
cmake --build "$SRC/mayhem/build-tests" -j"$MAYHEM_JOBS"

# 3) KAT probe: fixed input -> asserted output, built with normal flags, dynamically linked.
$CXX -O1 -std=c++11 -I"$AJ/src" "$SRC/mayhem/kat_probe.cpp" -o "$SRC/mayhem/build-tests/kat_probe"

# 4) KAT probe for GPX_Parser, normal flags.
PROBE_OBJS=$(gpx_objs "-O1" /tmp/gpx-plain)
$CXX -O1 $GPX_INC "$SRC/mayhem/gpx_probe.cpp" $PROBE_OBJS -o "$SRC/mayhem/build-tests/gpx_probe"
