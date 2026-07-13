#!/usr/bin/env bash
# release —— 一键发版
set -e
PROJ="${1:?usage: $0 <project> <version> <product>}"
VER="$2"
PROD="$3"
[ -z "$VER" ] || [ -z "$PROD" ] && { echo "usage: $0 <project> <version> <product>"; exit 1; }

echo "=== release $PROJ $VER ($PROD) ==="

# 1. doctor 校验
python tools/doctor.py || { echo "  ✗ doctor 失败"; exit 1; }
python tools/lint.py boostkit.yaml || exit 1

# 2. release 分支
BR="release/${VER}/${PROD}"
git checkout -b "$BR" 2>/dev/null || git checkout "$BR"

# 3. release tag
TAG="bk-${PROD}-${VER}"
git tag -m "$PROJ release $VER ($PROD)" "$TAG"

# 4. 推送(无 push 权限时降级 dry-run)
git push origin "$BR" "$TAG" 2>/dev/null \
    && echo "  ✓ pushed" \
    || echo "  ! 推送失败,请手动 push"

echo "✓ tag: $TAG, branch: $BR"
