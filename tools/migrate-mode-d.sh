#!/usr/bin/env bash
# migrate-mode-d —— 把散落仓一次升级到 v5 模式 I
# 用法:bash tools/migrate-mode-d.sh <upstream-url> <version>
# 例:  bash tools/migrate-mode-d.sh https://github.com/redis/redis.git 7.0.15
set -e
URL="${1:?usage: $0 <upstream-url> <version>}"
VER="${2:?usage: $0 <upstream-url> <version>}"
echo "=== migrating: $URL @ $VER ==="

# 1. 暂存
mkdir -p .migration-backup
mv *.patch .migration-backup/ 2>/dev/null || true

# 2. 拉 baseline SHA
SHA=$(git ls-remote "$URL" "refs/tags/$VER" 2>/dev/null | awk '{print $1}')
[ -z "$SHA" ] && SHA=$(git ls-remote "$URL" "refs/tags/v$VER" 2>/dev/null | awk '{print $1}')
[ -z "$SHA" ] && { echo "  ✗ upstream tag $VER not found"; exit 1; }
echo "  upstream SHA: $SHA"

# 3. 创建 versions/<v>/ 目录
mkdir -p "versions/$VER/patches"
mkdir -p "versions/$VER/metadata"
mkdir -p "versions/$VER/tests"
mkdir -p "versions/$VER/reports"

# 4. 移动 patch + 系列化重命名
cd .migration-backup
i=0
: > "../versions/$VER/series"
for f in *.patch; do
    [ -f "$f" ] || continue
    i=$((i+1))
    idx=$(printf "%04d" $i)
    type="perf"
    case "$f" in
        *iouring*|*arm*|*hw*) type="hw";;
        *aes*|*crypto*|*opt*|*kzl*|*fastpath*) type="perf";;
        *fix*|*bug*) type="bugfix";;
        *build*|*compile*) type="build";;
        *cve*) type="cve";;
        *compat*) type="compat";;
    esac
    desc=$(echo "$f" | sed 's/\.patch$//; s/[^a-zA-Z0-9-]/-/g')
    newname="${idx}-${type}-${desc}.patch"
    mv "$f" "../versions/$VER/patches/$newname"
    echo "$newname" >> "../versions/$VER/series"
done
cd ..

# 5. metadata 草稿
cd "versions/$VER"
i=0
while read line; do
    [[ "$line" =~ ^#.*$ ]] && continue
    [[ -z "$line" ]] && continue
    i=$((i+1))
    fname=$line
    base=${fname%.patch}
    type=$(echo "$base" | cut -d- -f2)
    cat > "metadata/${base}.yaml" <<YAML
id: $(basename "$VER")-$(printf '%04d' $i)
title: $(echo $base | sed 's/^[0-9]*-//' | sed 's/-/ /g')
project: $(echo $VER | cut -d- -f1)
type: $type
status: Validated
risk_level: medium
upstream_base:
  repo: $URL
  version: $VER
  commit: $SHA
owner:
  team: 待填
  person: 待填
created_at: $(date +%Y-%m-%d)
applies_to:
  - $VER
upstream:
  status: Not-Submitted
  url: null
  issue: null
  pr: null
validation:
  build:
    required: true
    matrix: [kunpeng-arm64-gcc]
  tests: [redis-smoke]
  performance:
    required: false
removeWhen:
  condition: 待填
  versionGte: null
YAML
done < series
cd ../..

# 6. OWNERS 占位
[ -f OWNERS ] || cat > OWNERS <<'EOF'
approvers:
  - <your.email@boostkit>
  - <approver2.email@boostkit>
reviewers:
  - <reviewer1>
  - <reviewer2>
  - <reviewer3>
emergencyContacts:
  - <your.email@boostkit>
  - <approver2.email@boostkit>
labels:
  - sig/multimedia
  - area/patch
EOF

# 7. .gitignore 占位
[ -f .gitignore ] || cat > .gitignore <<'EOF'
# 上游源码(任何人都不应该 commit)
/src/
/storage/
/sql/
*.tar.gz
*.tar.xz
# OS 打包
*.spec
*.rpm
*.deb
Dockerfile
build.sh
# CI 产物
versions/*/reports/*.json
EOF

# 8. boostkit.yaml 占位(本仓实际版本可手工细化)
[ -f boostkit.yaml ] || cat > boostkit.yaml <<EOF
apiVersion: boostkit.io/v1
kind: PatchOverlay
metadata:
  name: $(basename $(pwd))
  owner: sig-<your-sig>@boostkit
  owners:
    - <your.email@boostkit>
    - <approver2.email@boostkit>
  lastReviewed: $(date +%Y-%m-%d)
  mode: standard
upstream:
  type: tarball
  url: $URL
  versions:
    - version: $VER
      baseline:
        ref: $VER
        sha: $SHA
        fetchedAt: $(date +%Y-%m-%d)
patches:
$(cd versions/$VER && cat metadata/*.yaml | grep -E "^id:" | sed 's/^/  - /' | head -5)
ci:
  gates:
    - name: doctor        cmd: python tools/doctor.py     blocking: true
    - name: lint          cmd: python tools/lint.py boostkit.yaml  blocking: true
    - name: check-series  cmd: python tools/check-series.py  blocking: true
    - name: check-owners  cmd: python tools/check-owners.py OWNERS  blocking: true
    - name: check-apply   cmd: bash tools/check-apply.sh   blocking: true
kernelSupport:
  enabled: false
EOF

echo "=== 骨架生成完毕,接下来手动编辑 OWNERS / boostkit.yaml ==="
