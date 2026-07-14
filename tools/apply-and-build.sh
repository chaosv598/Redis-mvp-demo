#!/usr/bin/env bash
# apply-and-build.sh —— 消费侧:把本仓的 patch apply 到上游精确 commit 上并 build
#
# 设计目标(2026-07-14 简化):
#   - 严格按 metadata 的 upstream_base.repo + upstream_base.commit 拉代码
#   - 如果 SHA 不可达(匿名 clone 限制 / 强制 push 后),回退到 upstream_base.version 对应 tag
#   - 按 series 顺序逐 patch git apply(单个失败立即停)
#   - build 用 make(可选:make test 跑单元测试)
#   - 产出留在 /tmp/redis-build-<version>-<pid>/,不污染本仓
#
# 用法:
#   bash tools/apply-and-build.sh <version>                       # 默认 version = redis-<v>
#   bash tools/apply-and-build.sh 7.0.15                          # 拉 redis 7.0.15 + apply patches
#   bash tools/apply-and-build.sh 7.0.15 --skip-build             # 只 apply,不 build(快速验证)
#   bash tools/apply-and-build.sh 7.0.15 --src-dir /opt/redis     # 用已有 src 目录(已 git clone 过,快很多)
#   bash tools/apply-and-build.sh 7.0.15 --smoke                  # build 完跑 ./runtest --single unit/type
#
# 退出码:
#   0 = apply + build 全部成功
#   1 = 任何失败(apply / build / test)
set -e

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
}

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VER=""
SKIP_BUILD=0
SMOKE=0
SRC_DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --skip-build) SKIP_BUILD=1 ;;
        --smoke)      SMOKE=1 ;;
        --src-dir)    SRC_DIR="$2"; shift ;;
        -h|--help)    usage ;;
        -*)           echo "  ✗ 未知参数: $1"; usage ;;
        *)            VER="$1" ;;
    esac
    shift
done

[ -z "$VER" ] && { echo "  ✗ 缺 version(如 7.0.15)"; usage; }

VERDIR="$ROOT/versions/redis-$VER"
SERIES="$VERDIR/series"
METADIR="$VERDIR/metadata"
PATCHDIR="$VERDIR/patches"

[ -d "$VERDIR" ] || { echo "  ✗ 没有 versions/redis-$VER 目录"; exit 1; }
[ -f "$SERIES" ] || { echo "  ✗ 缺 series 文件:$SERIES"; exit 1; }

# 1. 从 metadata 读 repo + commit(取第一个非 retired 的 yaml 作 source of truth)
REPO=""
SHA=""
for yp in "$METADIR"/*.yaml; do
    [ -f "$yp" ] || continue
    REPO=$(grep -E "^\s*repo:" "$yp" | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'")
    SHA=$(grep -E "^\s*commit:" "$yp" | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'")
    [ -n "$REPO" ] && [ -n "$SHA" ] && break
done

if [ -z "$REPO" ] || [ -z "$SHA" ]; then
    echo "  ✗ metadata 缺 upstream_base.repo 或 commit"
    exit 1
fi

echo "=== apply-and-build.sh: redis $VER ==="
echo "  upstream repo : $REPO"
echo "  upstream commit: $SHA"

# 2. 准备 src 目录(复用 / 新 clone)
if [ -n "$SRC_DIR" ] && [ -d "$SRC_DIR/.git" ]; then
    WORK="$SRC_DIR"
    echo "  src dir (复用): $WORK"
else
    if [ -n "$SRC_DIR" ]; then
        echo "  ! --src-dir $SRC_DIR 不是 redis 源码目录(无 .git/),改用新 clone"
    fi
    WORK=$(mktemp -d)/redis
    echo "  src dir (新 clone): $WORK"
    if ! git clone --quiet --no-checkout "$REPO" "$WORK" 2>/dev/null; then
        echo "  ✗ clone $REPO 失败"
        exit 1
    fi
fi

cd "$WORK"

# 3. checkout 精确 commit,SHA 不可达时回退到 tag
if git cat-file -t "$SHA" >/dev/null 2>&1; then
    git checkout --quiet "$SHA"
    echo "  ✓ checkout $SHA"
else
    if git checkout --quiet "$VER" 2>/dev/null; then
        echo "  ⚠ SHA $SHA 不可达,回退到 tag $VER(请更新 metadata upstream_base.commit)"
    else
        echo "  ✗ SHA $SHA 和 tag $VER 都不可达"
        exit 1
    fi
fi

# 4. 按 series 顺序逐 patch apply
i=0
while read line; do
    [[ "$line" =~ ^#.*$ ]] && continue
    [[ -z "$line" ]] && continue
    fname=$(echo "$line" | xargs)
    i=$((i+1))
    pfile="$PATCHDIR/$fname"

    if [ ! -f "$pfile" ]; then
        echo "  ✗ [$i] patch 文件不存在: $pfile"
        exit 1
    fi
    if ! git apply --check "$pfile" 2>/dev/null; then
        echo "  ✗ [$i] $fname: apply --check 失败(可能与 baseline 不匹配,owner 应 rebase 或 retire)"
        exit 1
    fi
    git apply "$pfile"
    echo "  ✓ [$i] applied $fname"
done < "$SERIES"

echo "  ✓ 全部 $i 个 patch apply 成功"

# 5. build(可选跳过)
if [ "$SKIP_BUILD" = "1" ]; then
    echo "  (--skip-build,跳过 make)"
    exit 0
fi

echo "  → make -j$(nproc) ..."
if ! make -j$(nproc) >/tmp/build.log 2>&1; then
    echo "  ✗ build 失败,日志:/tmp/build.log"
    tail -20 /tmp/build.log
    exit 1
fi
echo "  ✓ build OK"

# 6. smoke test(可选)
if [ "$SMOKE" = "1" ]; then
    echo "  → smoke test: ./runtest --single unit/type ..."
    if [ -x ./runtest ]; then
        ./runtest --single unit/type >/tmp/smoke.log 2>&1 && echo "  ✓ smoke OK" || {
            echo "  ⚠ smoke 失败(非阻塞),日志:/tmp/smoke.log"
        }
    else
        echo "  ! ./runtest 不存在,跳过"
    fi
fi

echo "=== apply-and-build.sh done ==="
echo "  src 留在: $WORK"