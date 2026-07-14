#!/usr/bin/env bash
# build-perf —— 干净 upstream apply + 编译 + memtier_benchmark 性能基准
#
# 用法:
#   bash tools/build-perf.sh build <version>      # clone upstream + apply + make
#   bash tools/build-perf.sh bench <version>      # 启动 redis-server + 跑 memtier + 解析
#   bash tools/build-perf.sh all <version>        # build + bench 串行
#
# 退出码:
#   0 = 全部成功(报告可能在末尾)
#   1 = 任何阶段失败
#
# 与 tools/verify.sh 的关系:
#   - verify.sh: dry-run apply,不编不跑(GitHub PR 默认 30s 内完成)
#   - build-perf.sh: 真的编 + 跑(memtier quick smoke,~2-3 分钟)
#
# 输入: versions/<v>/version.yaml (upstream_base.repo / commit / patches[])
# 输出: artifacts/<v>/{redis-bin.tar.gz, memtier.log, summary.md}
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-/tmp/build-perf-work}"
ARTIFACTS="${ARTIFACTS:-$ROOT/artifacts}"
MEMTIER_BIN="${MEMTIER_BIN:-/usr/local/bin/memtier_benchmark}"
REDIS_PORT="${REDIS_PORT:-6399}"
BENCH_TIME="${BENCH_TIME:-30}"
BENCH_THREADS="${BENCH_THREADS:-2}"
BENCH_CLIENTS="${BENCH_CLIENTS:-10}"
BENCH_PIPELINE="${BENCH_PIPELINE:-4}"

cmd="${1:-all}"
ver="${2:-}"

log() { printf '\033[36m[build-perf]\033[0m %s\n' "$*" >&2; }
err() { printf '\033[31m[build-perf ERROR]\033[0m %s\n' "$*" >&2; }

# --- python heredoc: 读 yaml 拿 upstream_base ---
read_yaml() {
    python3 - "$ROOT/versions/$ver/version.yaml" <<'PY'
import sys, yaml, json
m = yaml.safe_load(open(sys.argv[1]))
ub = m['upstream_base']
patches = [p['name'] for p in m['patches']]
print(json.dumps({
    'repo': ub['repo'],
    'commit': ub['commit'],
    'version': ub['version'],
    'patches': patches,
}))
PY
}

# --- 子命令: build ---
do_build() {
    [ -z "$ver" ] && { err "用法: $0 build <version>"; exit 1; }
    local meta up_repo up_commit up_ver patches
    meta=$(read_yaml)
    up_repo=$(echo "$meta" | python3 -c 'import json,sys;print(json.load(sys.stdin)["repo"])')
    up_commit=$(echo "$meta" | python3 -c 'import json,sys;print(json.load(sys.stdin)["commit"])')
    up_ver=$(echo "$meta" | python3 -c 'import json,sys;print(json.load(sys.stdin)["version"])')
    patches=$(echo "$meta" | python3 -c 'import json,sys;print("\n".join(json.load(sys.stdin)["patches"]))')

    log "version:   $ver"
    log "upstream:  $up_repo @ $up_commit ($up_ver)"
    log "patches:   $(echo "$patches" | wc -l) 个"

    local src_dir="$WORK/$ver/src"
    local bin_dir="$WORK/$ver/bin"
    mkdir -p "$src_dir" "$bin_dir" "$ARTIFACTS/$ver"

    # clone (cache 复用:同一 commit 已存在则 skip)
    # 用普通 depth=1 clone(不带 filter=blob:none 避免 fetch SHA 'not our ref' 错)
    if [ ! -d "$src_dir/.git" ]; then
        log "clone upstream (depth=1) ..."
        git clone --depth 1 --no-tags "$up_repo" "$src_dir" 2>&1 | tail -3 >&2
    fi

    log "fetch target commit $up_commit (unshallow if needed)"
    # 如果当前 depth=1 拿不到目标 SHA,unshallow 一次
    if ! (cd "$src_dir" && git cat-file -t "$up_commit" 2>/dev/null); then
        log "  target SHA not in shallow clone, fetching unshallow ..."
        (cd "$src_dir" && git fetch --unshallow origin 2>&1 | tail -1 >&2 || true)
        (cd "$src_dir" && git fetch --tags origin 2>&1 | tail -1 >&2 || true)
    fi
    (cd "$src_dir" && git checkout -q "$up_commit" 2>&1) || {
        err "checkout commit 失败: $up_commit"
        exit 1
    }
    log "upstream HEAD: $(cd "$src_dir" && git rev-parse --short HEAD)"

    # apply patches 按数组顺序
    # 设计:patch apply 失败降级为 warning(跟 verify.sh 一致),
    #      因为 patch overlay 仓里可能有已知不匹配的 patch 等待 owner 修复。
    #      但 make build 失败 = fail(说明 patch 让 upstream 编不过,需要人介入)
    local applied=0
    local failed=0
    local pd="$ROOT/versions/$ver/patches"
    while IFS= read -r pname; do
        [ -z "$pname" ] && continue
        local pfile="$pd/$pname.patch"
        if [ ! -f "$pfile" ]; then
            err "  ✗ patch 文件不存在: $pname.patch"
            failed=$((failed+1))
            continue
        fi
        log "  apply: $pname"
        if (cd "$src_dir" && git apply --check "$pfile" 2>&1 | tail -5 >&2) \
           && (cd "$src_dir" && git apply "$pfile" 2>&1 | tail -2 >&2); then
            applied=$((applied+1))
        else
            err "  ⚠ apply 失败(降级 warning,不阻塞 build): $pname"
            failed=$((failed+1))
        fi
    done <<< "$patches"

    log "apply 结果: $applied 成功 / $failed 失败"
    [ "$failed" -gt 0 ] && log "  ⚠ 有 patch apply 失败,继续 build 验证其它 patch 健康度(reviewer 检查)"

    # build (参考 BoostKit redis_network_async_optimization_feature_guide.md)
    # 文档命令:make distclean && make -j (无 BUILD_TLS/MALLOC/USE_SYSTEMD flag,
    # 保留上游默认值 — jemalloc + TLS + systemd-aware 都由系统决定)
    log "make distclean ..."
    (cd "$src_dir" && make distclean 2>&1 | tail -3 >&2) || true
    log "make build (-j$(nproc), ~60s) ..."
    (cd "$src_dir" && set -o pipefail; make -j"$(nproc)" 2>&1 | tail -30 >&2)
    local make_rc=${PIPESTATUS[0]}
    if [ "$make_rc" -ne 0 ]; then
        err "make 失败 (rc=$make_rc),upstream apply 后无法编译"
        err "可能原因:patch 与 upstream SHA 不匹配 / patch 引入语法错 / 缺依赖"
        exit 1
    fi

    # 打包 binary 供 bench 复用
    log "collect binaries → $bin_dir"
    cp "$src_dir"/src/redis-server "$bin_dir/" 2>/dev/null || true
    cp "$src_dir"/src/redis-cli    "$bin_dir/" 2>/dev/null || true
    cp "$src_dir"/src/redis-benchmark "$bin_dir/" 2>/dev/null || true

    log "✓ build OK ($applied patches applied)"
    echo "SRC_DIR=$src_dir"
    echo "BIN_DIR=$bin_dir"
}

# --- 子命令: bench ---
do_bench() {
    [ -z "$ver" ] && { err "用法: $0 bench <version>"; exit 1; }

    local bin_dir="$WORK/$ver/bin"
    local redis_server="$bin_dir/redis-server"
    local redis_bench="$bin_dir/redis-benchmark"
    [ ! -x "$redis_server" ] && { err "redis-server 不存在,请先跑 build: $redis_server"; exit 1; }
    # memtier 可选,只在 BENCH_CMD=memtier 时强制要求
    if [ "${BENCH_CMD:-redis-benchmark}" = "memtier" ]; then
        [ ! -x "$MEMTIER_BIN" ] && { err "memtier_benchmark 不存在: $MEMTIER_BIN(BENCH_CMD=memtier)"; exit 1; }
    fi
    [ ! -x "$redis_bench" ] && { err "redis-benchmark 不存在: $redis_bench"; exit 1; }

    local artdir="$ARTIFACTS/$ver"
    mkdir -p "$artdir"
    local log_file="$artdir/memtier.log"
    local summary_file="$artdir/summary.md"

    local pidfile="$WORK/$ver/redis.pid"
    local datadir="$WORK/$ver/data"
    mkdir -p "$datadir"

    # 启动 redis-server (后台)
    log "start redis-server :$REDIS_PORT"
    "$redis_server" \
        --port "$REDIS_PORT" \
        --bind 127.0.0.1 \
        --daemonize yes \
        --pidfile "$pidfile" \
        --dir "$datadir" \
        --dbfilename dump.rdb \
        --save '' \
        --appendonly no \
        --maxmemory 256mb \
        --maxmemory-policy allkeys-random \
        --logfile "$WORK/$ver/redis.log"

    # 等服务起来
    local retries=30
    while [ $retries -gt 0 ]; do
        if "$bin_dir/redis-cli" -p "$REDIS_PORT" ping 2>/dev/null | grep -q PONG; then
            log "redis-server up (PONG)"
            break
        fi
        sleep 0.5
        retries=$((retries-1))
    done
    [ $retries -eq 0 ] && { err "redis-server 启动超时"; cat "$WORK/$ver/redis.log" >&2; exit 1; }

    # 跑性能基准
    # 参考 BoostKit redis_network_async_optimization_feature_guide.md:
    #   redis-benchmark -h IP -p PORT -c client -d size -n 10000000
    #                     -r 10000000 -t set,get --threads 20 -q
    # 默认 30s quick smoke; 通过环境变量覆盖:
    #   BENCH_CMD=memtier|redis-benchmark (默认 redis-benchmark)
    #   BENCH_N=10000000  BENCH_CLIENTS=200  BENCH_SIZE=3  BENCH_THREADS=20
    #   BENCH_TIME=30 (memtier 模式用)
    local bench_cmd="${BENCH_CMD:-redis-benchmark}"
    local bench_n="${BENCH_N:-10000000}"
    local bench_clients="${BENCH_CLIENTS:-200}"
    local bench_size="${BENCH_SIZE:-3}"
    local bench_threads="${BENCH_THREADS:-20}"
    log "benchmark: cmd=$bench_cmd clients=$bench_clients size=${bench_size}B n=$bench_n threads=$bench_threads"
    log "  log_file=$log_file"
    set +e
    if [ "$bench_cmd" = "memtier" ]; then
        "$MEMTIER_BIN" \
            -s 127.0.0.1 -p "$REDIS_PORT" \
            --threads="$bench_threads" \
            --clients="$bench_clients" \
            --test-time="$BENCH_TIME" \
            --ratio=1:1 \
            --pipeline="$BENCH_PIPELINE" \
            --data-size="$bench_size" \
            --key-pattern=R:R \
            --key-maximum=100000 \
            --hide-histogram=0 \
            2>&1 | tee "$log_file"
    else
        # redis-benchmark 路径(参考 BoostKit 文档命令)
        "$bin_dir/redis-benchmark" \
            -h 127.0.0.1 -p "$REDIS_PORT" \
            -c "$bench_clients" -d "$bench_size" \
            -n "$bench_n" -r "$bench_n" \
            -t set,get --threads "$bench_threads" \
            -q 2>&1 | tee "$log_file"
    fi
    local bench_rc=${PIPESTATUS[0]}
    set -e
    log "  benchmark exit code: $bench_rc"
    log "  log_file size: $(wc -c < "$log_file" 2>/dev/null || echo 'NOT FOUND')"

    # 关 redis
    log "shutdown redis-server"
    "$bin_dir/redis-cli" -p "$REDIS_PORT" shutdown nosave 2>/dev/null || true
    sleep 1
    [ -f "$pidfile" ] && kill -9 "$(cat "$pidfile")" 2>/dev/null || true

    # 解析 memtier 输出 → markdown summary
    parse_summary "$log_file" "$summary_file"

    # 调试:列 artifacts 目录,排查为什么 CI 找不到 summary.md
    log "artifacts dir contents:"
    ls -la "$artdir" >&2 || true
    log "summary_file=$summary_file exists=$( [ -f "$summary_file" ] && echo yes || echo no ) size=$( wc -c < "$summary_file" 2>/dev/null || echo 0 )"

    # 同时把 summary 写到 GitHub Step Summary(显示在 PR 评论)
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ] && [ -f "$summary_file" ]; then
        {
            echo "### build-perf · $ver"
            echo
            echo "\`pwd=$PWD\`, artifacts=\`$artdir\`"
            echo
            cat "$summary_file"
        } >> "$GITHUB_STEP_SUMMARY"
    fi

    log "✓ bench OK → $summary_file"
}

# --- 解析 benchmark 输出 ---
parse_summary() {
    local log_file="$1"
    local out_file="$2"

    # 支持两种 benchmark 工具:
    # 1) memtier_benchmark: 多行 Totals,带 p50/p99/p99.9
    # 2) redis-benchmark (BoostKit 文档): "-q" 模式输出
    #      "SET: 123456.78 requests per second"
    #      "GET: 130000.00 requests per second"
    # 兼容策略:先试 redis-benchmark 格式(两行),失败再降级 memtier 解析
    python3 - "$log_file" "$ver" > "$out_file" <<'PY'
import sys, re

log_path, version = sys.argv[1], sys.argv[2]
text = open(log_path).read()

# === 优先: redis-benchmark -q 格式 ===
def grab_redis_bench():
    set_m = re.search(r'^\s*SET\s*:\s*([\d.]+)\s+requests per second', text, re.M | re.I)
    get_m = re.search(r'^\s*GET\s*:\s*([\d.]+)\s+requests per second', text, re.M | re.I)
    if set_m and get_m:
        return {
            'set': {'ops': float(set_m.group(1)), 'p50': 0, 'p99': 0, 'p999': 0},
            'get': {'ops': float(get_m.group(1)), 'p50': 0, 'p99': 0, 'p999': 0},
        }
    return None

# === 降级: memtier Totals 行格式 ===
def grab_memtier(label):
    pattern = rf'^\s*{re.escape(label)}\s*\n\s*Totals\s+(.+?)(?:\n\s*\n|\n\s*[A-Z]|\Z)'
    m = re.search(pattern, text, re.M | re.S)
    if not m:
        return None
    nums = re.findall(r'\b(\d+\.\d+)\b', m.group(1))
    if len(nums) < 2:
        return None
    return {
        'ops':  float(nums[0]) if nums else 0,
        'p50':  float(nums[-4]) if len(nums) >= 4 else 0,
        'p99':  float(nums[-3]) if len(nums) >= 3 else 0,
        'p999': float(nums[-2]) if len(nums) >= 2 else 0,
    }

result = grab_redis_bench()
if not result:
    set_r = grab_memtier('SETs') or {}
    get_r = grab_memtier('GETs') or {}
    result = {'set': set_r, 'get': get_r}

set_r = result.get('set', {})
get_r = result.get('get', {})

def cell(v):
    return f"{v:.2f}" if v else '-'

print(f"## build-perf report - {version}")
print()
print("| metric | SETs | GETs |")
print("|---|---|---|")
print(f"| ops/sec | {set_r.get('ops', 0):.0f} | {get_r.get('ops', 0):.0f} |")
print(f"| p50 latency (ms) | {cell(set_r.get('p50'))} | {cell(get_r.get('p50'))} |")
print(f"| p99 latency (ms) | {cell(set_r.get('p99'))} | {cell(get_r.get('p99'))} |")
print(f"| p99.9 latency (ms) | {cell(set_r.get('p999'))} | {cell(get_r.get('p999'))} |")
print()
print("_参考 BoostKit redis_network_async_optimization_feature_guide.md (redis-benchmark -q)_")
PY
}

# --- 主入口 ---
case "$cmd" in
    build) do_build ;;
    bench) do_bench ;;
    all)
        do_build
        do_bench
        ;;
    *)
        err "未知子命令: $cmd (支持: build / bench / all)"
        exit 2
        ;;
esac
