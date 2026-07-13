#!/usr/bin/env bash
# rebase —— 上游版本升级剧本(redis-7.0.15 → redis-7.0.16)
#
# 流程:
#   1. 解析 boostkit.yaml 拿到 upstream.url
#   2. 拉新版本 upstream SHA(优先 refs/tags/<v>,回退 refs/tags/v<v>)
#   3. 建 versions/<new-v>/ 目录骨架
#   4. 复制所有 patch 文件 + metadata 到新版本(版本号要重写)
#   5. 跑 check-apply 验证
#   6. 通过 → 标 Validated + last_rebased_at;失败 → 标 Rebase-Required(待人工)
#   7. 更新 boostkit.yaml
#
# 用法: bash tools/rebase.sh <new-version>
# 例:   bash tools/rebase.sh 7.0.16
set -e

NEW_VER="${1:?usage: $0 <new-version>,例:$0 7.0.16}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== rebase to $NEW_VER ==="

# 1) 解析 upstream URL
[ -f boostkit.yaml ] || { echo "  ✗ boostkit.yaml 缺失"; exit 1; }
URL=$(grep -E "^\s*url:" boostkit.yaml | head -1 | sed 's/^\s*url:\s*//; s/^"//; s/"$//')
[ -n "$URL" ] || { echo "  ✗ upstream.url 解析失败"; exit 1; }
echo "  upstream: $URL"

# 2) 拉新版本 SHA
NEW_SHA=$(git ls-remote "$URL" "refs/tags/$NEW_VER" 2>/dev/null | awk '{print $1}')
[ -z "$NEW_SHA" ] && NEW_SHA=$(git ls-remote "$URL" "refs/tags/v$NEW_VER" 2>/dev/null | awk '{print $1}')
[ -z "$NEW_SHA" ] && { echo "  ✗ upstream tag $NEW_VER 未找到"; exit 1; }
echo "  new SHA: $NEW_SHA"

# 3) 建目录骨架
NEW_DIR="versions/$NEW_VER"
[ -d "$NEW_DIR" ] && { echo "  ✗ $NEW_DIR 已存在(防误覆盖)"; exit 1; }
mkdir -p "$NEW_DIR/patches" "$NEW_DIR/metadata" "$NEW_DIR/tests" "$NEW_DIR/reports"
echo "  ✓ 建目录 $NEW_DIR/{patches,metadata,tests,reports}"

# 4) 复制所有现存版本的所有 patch + metadata,版本号替换
# 策略:从最新的旧版本(按字典序最大)复制
OLD_VER=$(ls -d versions/*/ 2>/dev/null | sort -V | tail -1 | xargs basename)
[ -z "$OLD_VER" ] || [ "$OLD_VER" = "$NEW_VER" ] && { echo "  ✗ 没有可参照的旧版本"; exit 1; }
echo "  从 $OLD_VER 复制 patch + metadata(版本号 $OLD_VER → $NEW_VER)"

# 复制并替换版本号
i=0
> "$NEW_DIR/series"
for src in "$OLD_VER"/patches/*.patch; do
    [ -f "$src" ] || continue
    i=$((i + 1))
    base=$(basename "$src")
    # 在 patch 内部用 sed 替换旧版本号 → 新版本号(谨慎,只换出现在 git header 里的)
    # 实际更安全的做法是直接复制(因为 patch 的 +++/--- 行是相对路径,不需要改)
    cp "$src" "$NEW_DIR/patches/$base"
    echo "$base" >> "$NEW_DIR/series"
done
echo "  ✓ 复制 $i 个 patch"

# 复制 metadata,版本号要改
for src in "$OLD_VER"/metadata/*.yaml; do
    [ -f "$src" ] || continue
    base=$(basename "$src")
    # 把 metadata 里的旧版本号替换成新版本号
    sed "s/version: $OLD_VER/version: $NEW_VER/g; \
         s/- $OLD_VER$/- $NEW_VER/g; \
         s|redis-${OLD_VER}-|redis-${NEW_VER}-|g" \
        "$src" > "$NEW_DIR/metadata/$base"
done
echo "  ✓ 复制 metadata"

# 5) 跑 check-apply 验证
echo
echo "  --- 跑 check-apply.sh 验证 ---"
# check-apply.sh 依赖 boostkit.yaml 里有 new version,所以先临时加再删
TEMP_BKY=$(mktemp)
python3 -c "
import yaml
with open('boostkit.yaml') as f: bky = yaml.safe_load(f)
bky['upstream']['versions'].append({
    'version': '$NEW_VER',
    'baseline': {'ref': '$NEW_VER', 'sha': '$NEW_SHA', 'fetchedAt': '$(date +%Y-%m-%d)'}
})
with open('$TEMP_BKY', 'w') as f: yaml.dump(bky, f, allow_unicode=True, sort_keys=False)
"
cp boostkit.yaml boostkit.yaml.bak.rebase
cp "$TEMP_BKY" boostkit.yaml
rm "$TEMP_BKY"

if bash tools/check-apply.sh > /tmp/rebase-check.log 2>&1; then
    echo "  ✓ check-apply 通过"
    REBASE_OK=1
else
    echo "  ✗ check-apply 失败,查看 /tmp/rebase-check.log"
    REBASE_OK=0
fi

# 恢复 boostkit.yaml(让下面的 metadata 标记独立判断)
cp boostkit.yaml.bak.rebase boostkit.yaml
rm boostkit.yaml.bak.rebase

# 6) 标记 status
TODAY=$(date +%Y-%m-%d)
if [ "$REBASE_OK" = "1" ]; then
    # 全部 patch 标 Validated + last_rebased_at
    for meta in "$NEW_DIR"/metadata/*.yaml; do
        python3 -c "
import yaml, sys
with open('$meta') as f: m = yaml.safe_load(f)
m['status'] = 'Validated'
m['last_rebased_at'] = '$TODAY'
m['last_updated_at'] = '$TODAY'
with open('$meta', 'w') as f: yaml.dump(m, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
"
    done
    echo "  ✓ 所有 patch 标 Validated + last_rebased_at=$TODAY"
else
    # 失败的 patch 留在 New 状态,需要人工 rebase
    echo "  ! 部分 patch rebase 失败,保留在 New 状态,待 owner 处理"
fi

# 7) 更新 boostkit.yaml(添加新版本)
python3 -c "
import yaml
with open('boostkit.yaml') as f: bky = yaml.safe_load(f)
# 已存在则跳过
if not any(v.get('version') == '$NEW_VER' for v in bky.get('upstream', {}).get('versions', [])):
    bky['upstream']['versions'].append({
        'version': '$NEW_VER',
        'baseline': {'ref': '$NEW_VER', 'sha': '$NEW_SHA', 'fetchedAt': '$TODAY'}
    })
with open('boostkit.yaml', 'w') as f: yaml.dump(bky, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
"
echo "  ✓ boostkit.yaml 已添加 $NEW_VER"

# 8) 跑校验
echo
echo "  --- 跑 doctor / check-deps / check-series 校验 ---"
python3 tools/doctor.py && echo "  ✓ doctor OK" || echo "  ! doctor 报错"
python3 tools/check-deps.py && echo "  ✓ check-deps OK" || echo "  ! check-deps 报错"
python3 tools/check-series.py && echo "  ✓ check-series OK" || echo "  ! check-series 报错"

echo
if [ "$REBASE_OK" = "1" ]; then
    echo "✓ rebase $NEW_VER 完成"
    echo "  后续: git add -A && git commit -m 'chore(rebase): upgrade to $NEW_VER'"
    echo "  然后跑 git push 触发 master CI 验证"
else
    echo "✗ rebase $NEW_VER 部分失败"
    echo "  后续: 查看 /tmp/rebase-check.log 修复失败的 patch,或跑:"
    echo "    python tools/lifecycle.py <patch-id> Deprecated  # 不再维护"
    echo "    python tools/lifecycle.py <patch-id> New  # 重新打"
fi
