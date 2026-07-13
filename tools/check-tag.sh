#!/usr/bin/env bash
# check-tag —— tag 命名规范
set -e
REPO="${1:-.}"
cd "$REPO"
ERR=0
for ref in $(git for-each-ref --format='%(refname:short)' refs/tags/ 2>/dev/null); do
    if [[ "$ref" =~ ^[0-9]+$ ]]; then
        echo "  ✗ tag 是纯数字(误打): $ref"
        ERR=$((ERR+1))
    fi
done

N_UPSTREAM=$(git for-each-ref --format='%(refname:short)' refs/tags/ 2>/dev/null | grep -c '^upstream-' || true)
if [ -f boostkit.yaml ] && [ "$N_UPSTREAM" = "0" ]; then
    echo "  ⚠ 没有 upstream-<v>-<sha7> tag(推荐打一个)"
fi

exit $ERR
