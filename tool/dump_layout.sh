#!/usr/bin/env bash
# Dump Weft layout geometry for a case, optionally diffed against Chrome.
#
#   tool/dump_layout.sh conformance/cases/table_basic.html --diff
#   tool/dump_layout.sh conformance/cases/float_image.html --runs
#
# Extra flags are forwarded: --width <px>, --runs, --diff.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/packages/weft_engine"

HTML=""
WIDTH=""
DIFF=0
RUNS=0
for arg in "$@"; do
  case "$arg" in
    --diff) DIFF=1 ;;
    --runs) RUNS=1 ;;
    --width) : ;;
    *) if [[ -z "$HTML" ]]; then HTML="$ROOT/$arg"; else WIDTH="$arg"; fi ;;
  esac
done

if [[ -z "$HTML" ]]; then
  echo "usage: tool/dump_layout.sh <case.html> [--diff] [--runs] [--width <px>]" >&2
  exit 2
fi

WEFT_DUMP_FILE="$HTML" \
WEFT_DUMP_WIDTH="${WIDTH:-360}" \
WEFT_DUMP_DIFF=$DIFF \
WEFT_DUMP_RUNS=$RUNS \
flutter test tool/dump_layout_test.dart --no-pub --timeout 60s 2>&1 | tr -d '\r' | grep -E "dumped|All tests|failed" || true

cat "$ROOT/build/dump_layout.txt"
