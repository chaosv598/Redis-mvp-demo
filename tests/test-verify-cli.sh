#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

help_output=$(bash "$ROOT/tools/verify.sh" --help)
grep -Fq 'verify.sh --e2e redis-7.0.15' <<<"$help_output"

if bash "$ROOT/tools/verify.sh" --unknown >"$TMP_DIR/unknown.out" 2>&1; then
    echo "expected --unknown to fail" >&2
    exit 1
fi
grep -Fq 'unsupported arguments' "$TMP_DIR/unknown.out"
