#!/usr/bin/env bash
# check-apply —— 从干净 upstream 重放 patch 系列
set -e
ROOT="${1:-.}"

cd "$ROOT"
[ -f boostkit.yaml ] || { echo "  ! no boostkit.yaml,skip"; exit 0; }

# 简单解析(不依赖 yq/pyyaml,用 grep)
REPO=$(grep -E "^\s*url:" boostkit.yaml | head -1 | sed 's/^\s*url:\s*//; s/^"//; s/"$//')
ERR=0

echo "=== check-apply $REPO ==="

for vdir in versions/*/; do
    [ -d "$vdir" ] || continue
    vname=$(basename "$vdir")
    [ -f "$vdir"series ] || continue

    # 提取 sha(粗略)
    sha=$(awk -v v="$vname" '
        /^      version:/ { cur=$2 }
        cur==v && /sha:/ { print $2; exit }
    ' boostkit.yaml | tr -d '"')

    [ -z "$sha" ] && { echo "  ! $vname: no sha,skip"; continue; }

    echo "--- $vname (sha ${sha:0:7}) ---"

    WORK=$(mktemp -d)
    git clone --quiet --no-checkout "$REPO" "$WORK/r" 2>/dev/null || {
        echo "  ✗ $vname: clone failed"
        ERR=$((ERR+1)); continue
    }
    (cd "$WORK/r" && git checkout --quiet "$sha" 2>/dev/null) || {
        echo "  ✗ $vname: checkout $sha failed"
        ERR=$((ERR+1)); rm -rf "$WORK"; continue
    }

    i=0
    while read line; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        i=$((i+1))
        fname=$(echo "$line" | xargs)
        if (cd "$WORK/r" && git apply --check "$OLDPWD/$vdir"patches/"$fname" 2>/dev/null); then
            (cd "$WORK/r" && git apply "$OLDPWD/$vdir"patches/"$fname")
            echo "  ✓ [$i] $fname"
        else
            echo "  ✗ [$i] FAIL $fname"
            ERR=$((ERR+1))
        fi
    done < "$vdir"series
    rm -rf "$WORK"
done

[ $ERR -eq 0 ] && echo "✓ all OK" || echo "✗ $ERR errors"
exit $ERR
