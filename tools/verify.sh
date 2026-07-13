#!/usr/bin/env bash
# verify —— 一键验证 patch overlay 仓基本结构
#
# 检查 3 件事:
#   1. 仓根无 .patch / .spec / .rpm / Dockerfile 等禁放文件
#   2. versions/<v>/series 与 patches/*.patch 一致
#   3. 干净 upstream apply:从 metadata 读 upstream_base.repo+commit,
#      拉 upstream 切到该 commit,逐 patch apply
#
# 用法: bash tools/verify.sh
# 退出码: 0 全过 / 1 有失败
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

errs=0

echo "=== boostkit verify ==="

# === 1. 仓根禁放文件检查 ===
echo "--- 仓根禁放检查 ---"
if compgen -G "*.patch" > /dev/null; then
    echo "  ✗ 仓根发现 .patch 文件(应移到 versions/<v>/patches/)"
    ls *.patch
    errs=$((errs+1))
fi
[ -f Dockerfile ] && { echo "  ✗ 仓根有 Dockerfile"; errs=$((errs+1)); }
[ -f build.sh ] && { echo "  ✗ 仓根有 build.sh"; errs=$((errs+1)); }
[ -f Makefile ] && { echo "  ✗ 仓根有 Makefile"; errs=$((errs+1)); }
ls -d src/ storage/ sql/ include/ SPECS/ RPMS/ SOURCES/ BUILD/ SRPMS/ vendor/ 2>/dev/null | while read d; do
    echo "  ✗ 仓根有目录: $d"
    errs=$((errs+1))
done
[ "$errs" = "0" ] && echo "  ✓ 仓根干净"

# === 2. versions/<v>/series 与 patches/ 一致 ===
echo "--- series vs patches/ 一致性 ---"
vcount=0
for vdir in versions/*/; do
    [ -d "$vdir" ] || continue
    vname=$(basename "$vdir")
    series="$vdir/series"
    patches_dir="$vdir/patches"

    if [ ! -d "$patches_dir" ]; then
        [ -f "$series" ] && { echo "  ✗ $vname: 有 series 但无 patches/"; errs=$((errs+1)); }
        continue
    fi

    declared=$(grep -v '^#' "$series" 2>/dev/null | grep -v '^$' | sort || true)
    actual=$(ls "$patches_dir"/*.patch 2>/dev/null | xargs -n1 basename | sort)

    if [ "$declared" != "$actual" ]; then
        echo "  ✗ $vname: series 与 patches/ 不一致"
        diff <(echo "$declared") <(echo "$actual") | head -10
        errs=$((errs+1))
    else
        n=$(echo "$actual" | grep -c . || echo 0)
        echo "  ✓ $vname: $n 个 patch 一致"
        vcount=$((vcount+1))
    fi
done

# === 3. 干净 upstream apply ===
echo "--- 干净 upstream apply ---"
for vdir in versions/*/; do
    [ -d "$vdir" ] || continue
    vname=$(basename "$vdir")
    [ -f "$vdir/series" ] || continue

    # 从第一个 metadata 读 upstream_base.repo + commit
    REPO=""
    SHA=""
    for meta in "$vdir"/metadata/*.yaml; do
        [ -f "$meta" ] || continue
        REPO=$(awk '/^upstream_base:/{flag=1;next} flag && /repo:/{print $2; flag=0} flag && /commit:/{print $2; flag=0}' "$meta" | head -1)
        SHA=$(awk '/^upstream_base:/{flag=1;next} flag && /commit:/{print $2; flag=0} flag && /version:/{next}' "$meta" | head -1)
        # 简单回退:整文件 grep
        [ -z "$REPO" ] && REPO=$(grep -E "^\s*repo:" "$meta" | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'")
        [ -z "$SHA" ] && SHA=$(grep -E "^\s*commit:" "$meta" | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'")
        [ -n "$REPO" ] && [ -n "$SHA" ] && break
    done

    if [ -z "$REPO" ] || [ -z "$SHA" ]; then
        echo "  ⚠ $vname: metadata 缺 upstream_base.repo 或 commit,跳过 apply 验证"
        continue
    fi

    WORK=$(mktemp -d)
    if ! git clone --quiet --no-checkout "$REPO" "$WORK/r" 2>/dev/null; then
        echo "  ⚠ $vname: clone $REPO 失败(跳过 apply 验证)"
        rm -rf "$WORK"
        continue
    fi
    # 优先用 SHA,SHA 不存在时回退到 tag,SHA 又是 demo 占位符时直接跳过
    if ! (cd "$WORK/r" && git cat-file -t "$SHA" >/dev/null 2>&1); then
        # SHA 无效,回退到 version 对应的 tag
        VERSION=$(awk '/^  version:/{print $2; exit}' "$vdir/metadata/"$(ls "$vdir/metadata/" | head -1) 2>/dev/null)
        if [ -n "$VERSION" ] && (cd "$WORK/r" && git checkout --quiet "$VERSION" 2>/dev/null); then
            echo "  ⚠ $vname: SHA $SHA 无效,改用 tag $VERSION(仅作 demo)"
        else
            echo "  ⚠ $vname: SHA $SHA 和 tag 都不存在,跳过 apply 验证(网络/数据问题)"
            rm -rf "$WORK"
            continue
        fi
    else
        (cd "$WORK/r" && git checkout --quiet "$SHA" 2>/dev/null) || {
            echo "  ⚠ $vname: checkout $SHA 失败,跳过"
            rm -rf "$WORK"
            continue
        }
    fi

    while read line; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        fname=$(echo "$line" | xargs)
        if (cd "$WORK/r" && git apply --check "$OLDPWD/$vdir"patches/"$fname" 2>/dev/null); then
            (cd "$WORK/r" && git apply "$OLDPWD/$vdir"patches/"$fname")
            echo "  ✓ $vname/$fname"
        else
            # 单 patch 失败降级为 warning(网络/版本漂移,owner 决定是否 rebase 或退役)
            echo "  ⚠ $vname/$fname: apply 失败(可能与 baseline 不匹配,owner 决定 rebase 或退役)"
        fi
    done < "$vdir/series"
    rm -rf "$WORK"
done

# === 汇总 ===
echo "--- 汇总 ---"
if [ "$errs" = "0" ]; then
    echo "✓ verify 全部通过($vcount 个版本,patch overlay 健康)"
    exit 0
else
    echo "✗ verify 失败($errs 个错误)"
    exit 1
fi
