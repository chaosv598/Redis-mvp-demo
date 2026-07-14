#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
workflow="$ROOT/.github/workflows/ci.yml"

job_count=$(awk '
    /^jobs:/ { in_jobs=1; next }
    in_jobs && /^  [A-Za-z0-9_-]+:$/ { count++ }
    END { print count+0 }
' "$workflow")
[ "$job_count" -eq 1 ]

grep -Fq 'bash tools/verify.sh --e2e redis-7.0.15' "$workflow"
grep -Fq 'E2E_RESULTS_DIR:' "$workflow"
grep -Fq 'actions/upload-artifact@v4' "$workflow"
grep -Fq 'if: always()' "$workflow"
