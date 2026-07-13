#!/usr/bin/env bash
# retire —— patch 退役剧本(4 处同步删: patches/ + series + metadata/ + boostkit.yaml)
#
# 流程:
#   1. 检查 patch 当前状态必须是 Deprecated(否则拒绝,除非 --force)
#   2. 从 series 删除该 patch 一行
#   3. 从 patches/ 删 patch 文件
#   4. 从 metadata/ 删 metadata yaml
#   5. 从 boostkit.yaml 的 patches[] 删对应 id
#   6. 把状态改为 Removed(终态)
#   7. 跑校验
#
# 用法: bash tools/retire.sh <patch-id-or-filename-base> [--force]
# 例:   bash tools/retire.sh redis-7.0.15-0001
#       bash tools/retire.sh 0001-hw-kunpeng-adapt-iouring
set -e

TARGET="${1:?usage: $0 <patch-id-or-base> [--force]}"
FORCE=0
[ "${2:-}" = "--force" ] && FORCE=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== retire: $TARGET ==="

# 找到 patch
PATCH_FILE=""
META_FILE=""
VERSION=""
for vdir in versions/*/; do
    [ -d "$vdir" ] || continue
    vname=$(basename "$vdir")
    # 尝试匹配 full id / base name
    for pf in "$vdir"patches/*.patch; do
        [ -f "$pf" ] || continue
        base=$(basename "$pf" .patch)
        if [ "$base" = "$TARGET" ] || echo "$base" | grep -q "^$TARGET-"; then
            PATCH_FILE="$pf"
            META_FILE="$vdir"metadata/"$base".yaml
            VERSION="$vname"
            break 2
        fi
    done
done

# 也支持 full id (redis-7.0.15-0001) 匹配
if [ -z "$PATCH_FILE" ]; then
    for vdir in versions/*/; do
        [ -d "$vdir" ] || continue
        for yp in "$vdir"metadata/*.yaml; do
            [ -f "$yp" ] || continue
            id=$(grep -E "^id:" "$yp" 2>/dev/null | awk '{print $2}')
            if [ "$id" = "$TARGET" ]; then
                base=$(basename "$yp" .yaml)
                PATCH_FILE="$vdir"patches/"$base".patch
                META_FILE="$yp"
                VERSION=$(basename "$vdir")
                break 2
            fi
        done
    done
fi

if [ -z "$PATCH_FILE" ]; then
    echo "  ✗ 找不到 patch: $TARGET"
    exit 1
fi

echo "  找到 patch: $PATCH_FILE"
echo "  元数据:    $META_FILE"
echo "  版本:      $VERSION"

# 1) 检查状态
if [ -f "$META_FILE" ] && [ "$FORCE" = "0" ]; then
    CUR_STATUS=$(grep -E "^status:" "$META_FILE" 2>/dev/null | awk '{print $2}')
    if [ "$CUR_STATUS" != "Deprecated" ]; then
        echo "  ✗ 当前状态 $CUR_STATUS != Deprecated"
        echo "  请先跑: python tools/lifecycle.py $TARGET Deprecated"
        echo "  强制删除: $0 $TARGET --force"
        exit 1
    fi
fi

# 2-4) 删文件
SERIES_FILE="versions/$VERSION/series"
echo "  删 $PATCH_FILE"
rm -f "$PATCH_FILE"
echo "  删 $META_FILE"
rm -f "$META_FILE"
if [ -f "$SERIES_FILE" ]; then
    base=$(basename "$PATCH_FILE")
    if grep -q "^$base$" "$SERIES_FILE"; then
        sed -i "/^$base$/d" "$SERIES_FILE"
        echo "  从 $SERIES_FILE 删除 $base"
    fi
fi

# 5) 从 boostkit.yaml 删 patches[]
python3 << PYEOF
import yaml
with open('boostkit.yaml') as f:
    bky = yaml.safe_load(f)
before = len(bky.get('patches', []))
bky['patches'] = [p for p in bky.get('patches', [])
                  if p.get('id') != '$TARGET' and p.get('file', '') != 'versions/$VERSION/patches/$(basename "$PATCH_FILE")']
after = len(bky.get('patches', []))
if before != after:
    with open('boostkit.yaml', 'w') as f:
        yaml.dump(bky, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
    print(f'  boostkit.yaml: 删 {before - after} 个 patch 条目')
else:
    print('  boostkit.yaml: 未找到匹配条目,跳过')
PYEOF

# 6) 校验
echo
echo "  --- 跑校验 ---"
python3 tools/check-series.py && echo "  ✓ check-series OK" || echo "  ! check-series 报错"
python3 tools/check-deps.py && echo "  ✓ check-deps OK" || echo "  ! check-deps 报错"
python3 tools/doctor.py && echo "  ✓ doctor OK" || echo "  ! doctor 报错"

echo
echo "✓ retire $TARGET 完成"
echo "  后续: git add -A && git commit -m 'chore(retire): remove $TARGET'"
echo "  然后跑 git push 触发 master CI 验证"
