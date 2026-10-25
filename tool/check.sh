#!/usr/bin/env bash
# One-command local gate for Weft.
#
#   tool/check.sh          format + analyze + all package tests + pixel goldens
#   tool/check.sh --fast   skip the pixel golden gate (layout-only iterations)
#
# Notes:
# - flutter/dart output is stripped of \r so failures grep cleanly on Windows.
# - pubspec.lock is restored at the end unless WEFT_KEEP_LOCK=1: local pub
#   mirrors rewrite package URLs and that churn must not leak into commits.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FAST=0
for arg in "$@"; do
  case "$arg" in
    --fast) FAST=1 ;;
    *) echo "unknown flag: $arg (supported: --fast)" >&2; exit 2 ;;
  esac
done

step() { printf '\n==> %s\n' "$*"; }

step "dart format"
dart format --output=none --set-exit-if-changed .

step "dart analyze"
dart analyze

step "package tests (dart run tool/verify.dart)"
dart run tool/verify.dart 2>&1 | tr -d '\r' | tail -5

if [[ "$FAST" -eq 0 ]]; then
  step "pixel goldens"
  if ! output="$(
    (cd packages/weft_engine &&
      flutter test tool/golden_pixel_test.dart --timeout 120s) 2>&1 | tr -d '\r'
  )"; then
    printf '%s\n' "$output" | tail -40
    exit 1
  fi
  printf '%s\n' "$output" | tail -1
else
  step "pixel goldens skipped (--fast)"
fi

if [[ "${WEFT_KEEP_LOCK:-0}" != "1" ]]; then
  if ! git diff --quiet pubspec.lock -- 2>/dev/null; then
    step "restore pubspec.lock (local mirror churn)"
    git checkout -- pubspec.lock
  fi
fi

printf '\nALL GREEN\n'
