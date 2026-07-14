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

if bash "$ROOT/tools/verify.sh" --e2e unsupported >"$TMP_DIR/e2e-invalid.out" 2>&1; then
    echo "expected unsupported E2E version to fail" >&2
    exit 1
fi
grep -Fq 'unsupported arguments' "$TMP_DIR/e2e-invalid.out"

if VERIFY_E2E_DRY_RUN=1 bash "$ROOT/tools/verify.sh" --e2e redis-7.0.15 >"$TMP_DIR/e2e-dry.out" 2>&1; then
    grep -Fq 'E2E metadata: redis-7.0.15' "$TMP_DIR/e2e-dry.out"
else
    echo "expected E2E dry run to succeed" >&2
    cat "$TMP_DIR/e2e-dry.out" >&2
    exit 1
fi

BROKEN_ROOT="$TMP_DIR/broken-repo"
mkdir -p "$BROKEN_ROOT/tools" "$BROKEN_ROOT/versions/redis-7.0.15"
cp "$ROOT/tools/verify.sh" "$BROKEN_ROOT/tools/verify.sh"
printf 'upstream_base: {}\n' >"$BROKEN_ROOT/versions/redis-7.0.15/version.yaml"
if VERIFY_E2E_DRY_RUN=1 bash "$BROKEN_ROOT/tools/verify.sh" --e2e redis-7.0.15 >"$TMP_DIR/e2e-broken.out" 2>&1; then
    echo "expected broken E2E metadata to fail" >&2
    exit 1
fi
grep -Fq 'failed to read E2E metadata' "$TMP_DIR/e2e-broken.out"
