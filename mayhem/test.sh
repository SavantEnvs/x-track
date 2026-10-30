#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
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

BT="$SRC/mayhem/build-tests"
passed=0; failed=0; skipped=0

# 1) ArduinoJson's own Catch suites. Parse each binary's own summary line (an output assertion,
#    not an exit code): a missing/neutered runner prints nothing and counts as a failure.
mapfile -t runners < <(find "$BT" -type f -name '*Tests' -perm -u+x | sort)
if [ "${#runners[@]}" -lt 10 ]; then
  echo "FAIL: expected >=10 Catch test runners under $BT, found ${#runners[@]} (build.sh bug)" >&2
  emit_ctrf "catch" 0 1 0; exit 1
fi
for r in "${runners[@]}"; do
  out="$("$r" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && grep -Eq 'All tests passed \([0-9]+ assertions? in [0-9]+ test cases?\)' <<<"$out"; then
    n="$(grep -Eo 'in [0-9]+ test case' <<<"$out" | grep -Eo '[0-9]+')"
    passed=$(( passed + n ))
  else
    echo "FAIL: $r (rc=$rc)" >&2; echo "$out" | tail -5 >&2
    failed=$(( failed + 1 ))
  fi
done

# 2) KAT probes: fixed JSON in -> exact canonical JSON + MessagePack bytes out.
probe="$BT/kat_probe"
check_kat() {
  local in="$1" want="$2" got
  got="$("$probe" <<<"$in" 2>&1)" || true
  if [ "$got" = "$want" ]; then passed=$(( passed + 1 )); else
    echo "KAT FAIL for $in" >&2; echo "  want: $want" >&2; echo "  got:  $got" >&2
    failed=$(( failed + 1 ))
  fi
}
check_kat '{ "a" : [1, 2, {"b": null}], "s": "hi" }' \
'{"a":[1,2,{"b":null}],"s":"hi"}
82a16193010281a162c0a173a26869'
check_kat '[true,false,-1,300,1.5,"x"]' \
'[true,false,-1,300,1.5,"x"]
96c3c2ffcd012cca3fc00000a178'
check_kat '{"k":"v"}' \
'{"k":"v"}
81a16ba176'

# 3) KAT probe for X-Track's own GPX_Parser: a fixed GPX document -> exact parsed points.
gpx_want='flag=240 lat=30.2800 lon=120.1600 ele=12.50 time=2021-05-01T08:30:15
flag=240 lat=-33.8651 lon=151.2099 ele=-3.25 time=2021-12-31T23:59:58'
gpx_got="$("$BT/gpx_probe" <<'GPX' 2>&1
<?xml version="1.0"?><gpx><trk><trkseg>
<trkpt lat="30.280001" lon="120.160002"><ele>12.5</ele><time>2021-05-01T08:30:15Z</time></trkpt>
<trkpt lat="-33.865143" lon="151.209900"><ele>-3.25</ele><time>2021-12-31T23:59:58Z</time></trkpt>
</trkseg></trk></gpx>
GPX
)" || true
if [ "$gpx_got" = "$gpx_want" ]; then passed=$(( passed + 1 )); else
  echo "GPX KAT FAIL" >&2; echo "  want: $gpx_want" >&2; echo "  got:  $gpx_got" >&2
  failed=$(( failed + 1 ))
fi

emit_ctrf "arduinojson-catch+kat" "$passed" "$failed" "$skipped"
