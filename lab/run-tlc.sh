#!/usr/bin/env bash
# Reproduce the lab's TLC runs with pinned tool versions (see LAB.md, "Pinned tools").
#
#   lab/run-tlc.sh e1 [seconds]          bounded model checking of MCetcdraft (default 1200 s)
#   lab/run-tlc.sh e2 [max_lines]        trace validation of tla/example.ndjson (optional prefix)
#
# TOOLS must point at a folder holding the two pinned jars. Run from the repo root.
set -euo pipefail

TOOLS="${TOOLS:-../tools/tla}"
TLA2TOOLS="${TOOLS}/tla2tools-1.8.0.jar"
CM="${TOOLS}/CommunityModules-deps-202611060952.jar"
SEP=":"; case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) SEP=";";; esac
CP="${TLA2TOOLS}${SEP}${CM}"
LAB="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "${LAB}/results" "${LAB}/tmp"

case "${1:-}" in
  e1)
    secs="${2:-1200}"
    cd tla
    timeout "${secs}" java -XX:+UseParallelGC -Xmx8g -cp "${CP}" tlc2.TLC \
      -config MCetcdraft.cfg MCetcdraft.tla -lncheck final \
      -metadir "${LAB}/tmp/states-e1" -fpmem 0.4 -workers 16 \
      > "${LAB}/results/E1-model-check.log" 2>&1 || true
    ;;
  e2)
    # Same preprocessing as tla/validate.sh, applied to a copy (validate.sh edits traces in place).
    cp tla/example.ndjson "${LAB}/tmp/example.ndjson"
    sed -i -E 's/^[^{]+//' "${LAB}/tmp/example.ndjson"
    sort -t":" -k 3 "${LAB}/tmp/example.ndjson" -o "${LAB}/tmp/example.sorted.ndjson"
    cd tla
    if [ -n "${2:-}" ]; then export MAX_TRACE="$2"; fi
    JSON="${LAB}/tmp/example.sorted.ndjson" java -XX:+UseParallelGC -cp "${CP}" tlc2.TLC \
      -config Traceetcdraft.cfg Traceetcdraft.tla -lncheck final \
      -metadir "${LAB}/tmp/states-e2" -fpmem 0.5 -workers 1 \
      > "${LAB}/results/E2-example-trace${2:+-prefix$2}.log" 2>&1 || true
    ;;
  *)
    sed -n '2,7p' "$0"; exit 1;;
esac
