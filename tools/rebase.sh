#!/usr/bin/env bash
# rebase —— 上游版本升级剧本(从最新版本升到新版本)
#
# 流程:
#   1. 找到最新版本(字典序最大)
#   2. 从该版本第一个 metadata 读 upstream_base.repo
#   3. 拉新版本 SHA
#   4. 建 versions/<new-v>/ 目录骨架
#   5. 复制所有 patch + metadata(版本号替换)
#   6. 跑 verify.sh 验证
#   7. 失败的 patch 保留 pending,通过的标 validated
#
# 用法: bash tools/rebase.sh <new-version>
# 例:   bash tools/rebase.sh 7.0.16
set -e

NEW_VER="${1:?usage: $0 <new-version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== rebase to $NEW_VER ==="

# 1) 找最新旧版本
OLD_VER=$(ls -d versions/*/ 2>/dev/null | sort -V | tail -1 | xargs basename)
[ -z "$OLD_VER" ] && { echo "  ✗ 没有可参照的旧版本"; exit 1; }
echo "  从 $OLD_VER 升级到 $NEW_VER"

# 2) 从 metadata 拿上游 URL
REPO=""
for meta in versions/$OLD_VER/metadata/*.yaml; do
    [ -f "$meta" ] || continue
    REPO=$(grep -E "^\s*repo:" "$meta" | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'")
    [ -n "$REPO" ] && break
done
[ -z "$REPO" ] && { echo "  ✗ 在 $OLD_VER metadata 找不到 upstream_base.repo"; exit 1; }
echo "  upstream: $REPO"

# 3) 拉新版本 SHA
NEW_SHA=$(git ls-remote "$REPO" "refs/tags/$NEW_VER" 2>/dev/null | awk '{print $1}')
[ -z "$NEW_SHA" ] && NEW_SHA=$(git ls-remote "$REPO" "refs/tags/v$NEW_VER" 2>/dev/null | awk '{print $1}')
[ -z "$NEW_SHA" ] && { echo "  ✗ upstream tag $NEW_VER 未找到"; exit 1; }
echo "  new SHA: $NEW_SHA"

# 4) 建新版本目录
NEW_DIR="versions/$NEW_VER"
[ -d "$NEW_DIR" ] && { echo "  ✗ $NEW_DIR 已存在(防误覆盖)"; exit 1; }
mkdir -p "$NEW_DIR/patches" "$NEW_DIR/metadata"
echo "  ✓ 建 $NEW_DIR/{patches,metadata}"

# 5) 复制 patch + metadata,版本号替换
i=0
> "$NEW_DIR/series"
for src in versions/$OLD_VER/patches/*.patch; do
    [ -f "$src" ] || continue
    i=$((i+1))
    base=$(basename "$src")
    cp "$src" "$NEW_DIR/patches/$base"
    echo "$base" >> "$NEW_DIR/series"
done
echo "  ✓ 复制 $i 个 patch"

for src in versions/$OLD_VER/metadata/*.yaml; do
    [ -f "$src" ] || continue
    base=$(basename "$src")
    # 替换版本号
    sed "s/redis-${OLD_VER}-/redis-${NEW_VER}-/g; \
         s/version: ${OLD_VER}/version: ${NEW_VER}/g; \
         s/applies_to: ${OLD_VER}/applies_to: ${NEW_VER}/g" \
        "$src" > "$NEW_DIR/metadata/$base"
    # 替换 upstream_base.commit
    python3 -c "
import yaml
with open('$NEW_DIR/metadata/$base') as f: m = yaml.safe_load(f)
if 'upstream_base' in m:
    m['upstream_base']['version'] = '$NEW_VER'
    m['upstream_base']['commit'] = '$NEW_SHA'
with open('$NEW_DIR/metadata/$base', 'w') as f:
    yaml.dump(m, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
"
done
echo "  ✓ 复制 metadata,版本号 $OLD_VER → $NEW_VER"

# 6) 跑 verify
echo
echo "  --- 跑 verify.sh ---"
TODAY=$(date +%Y-%m-%d)
if bash tools/verify.sh > /tmp/rebase-verify.log 2>&1; then
    echo "  ✓ verify 通过"
    REBASE_OK=1
else
    echo "  ✗ verify 失败,查看 /tmp/rebase-verify.log"
    cat /tmp/rebase-verify.log | tail -20
    REBASE_OK=0
fi

# 7) 标状态
if [ "$REBASE_OK" = "1" ]; then
    for meta in $NEW_DIR/metadata/*.yaml; do
        python3 -c "
import yaml
with open('$meta') as f: m = yaml.safe_load(f)
if 'upstream_plan' not in m: m['upstream_plan'] = {}
m['upstream_plan']['status'] = 'validated'
m['last_rebased_at'] = '$TODAY'
with open('$meta', 'w') as f: yaml.dump(m, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
"
    done
    echo "  ✓ 所有 patch 标 validated + last_rebased_at=$TODAY"
else
    echo "  ! 部分 patch rebase 失败,留 pending 状态"
fi

echo
if [ "$REBASE_OK" = "1" ]; then
    echo "✓ rebase $NEW_VER 完成"
    echo "  后续: git add -A && git commit -m 'chore(rebase): upgrade to $NEW_VER'"
else
    echo "✗ rebase $NEW_VER 部分失败"
    echo "  查看 /tmp/rebase-verify.log 修复,或:"
    echo "    bash tools/lifecycle.sh retire <id>   # 退役"
    echo "    bash tools/lifecycle.sh set <id> pending  # 重新打"
fi
