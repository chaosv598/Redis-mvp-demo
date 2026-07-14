# build-perf —— PR build + memtier_benchmark 性能基准

> 最后更新 2026-07-14
> 配套工作流:`.github/workflows/build-perf.yml`
> 配套脚本:`tools/build-perf.sh`
> 触发:PR 改 `versions/<v>/patches/**` 或 `version.yaml`

---

## 0. 30 秒速读

- **目标**:每次 PR 跑一次真实 build + 性能基准,产出报告给 reviewer
- **不做**:自动 fail 合并门禁(性能波动大,reviewer 决定)
- **触发**:paths-filter 检测到 patch 改动 → 启动 build-perf job
- **典型耗时**:首次 2.5 min,带 cache 后 1.8 min,纯 docs PR 0 秒
- **与 verify 的关系**:verify(dry-run,~30s)+ build-perf(真编真跑,~2min)= 互补,不替代

---

## 1. 完整链路

```
PR opened/updated
       ↓
dorny/paths-filter 扫描 PR diff
       ↓
命中 versions/redis-7.0.15/** 或 versions/redis-6.0.20/**
       ↓
是 → 启动 build-perf job (matrix: 每个改动的 version 一个)
否 → 跳过(节省 CI)
       ↓
build-perf job 步骤:
  1. 装 build-essential + tcl-dev + libssl-dev (~15s)
  2. 编 memtier_benchmark 2.1.0 (~30s,从源码)
  3. cache key = upstream-<v>-<yaml-hash>,复用 clone
  4. tools/build-perf.sh build <v>
     → clone upstream @ upstream_base.commit
     → 按 patches[] 数组顺序 git apply
     → make -j$(nproc) BUILD_TLS=no (~60s)
  5. tools/build-perf.sh bench <v>
     → 启 redis-server :6399 (no save, no AOF)
     → 等 PONG
     → memtier_benchmark --threads=2 --clients=10 --test-time=30s
     → shutdown
     → 解析输出 → artifacts/<v>/summary.md
  6. upload-artifact: memtier.log + summary.md (保留 30 天)
  7. 写 markdown → GitHub Job Summary(PR 评论里直接看到)
```

---

## 2. 报告长这样

PR 的 `build-perf` job summary 会显示:

```markdown
## build-perf report - redis-7.0.15

| metric | SETs | GETs |
|---|---|---|
| ops/sec | 285432 | 301205 |
| p50 latency (ms) | - | - |
| p99 latency (ms) | - | - |
| p99.9 latency (ms) | - | - |

_参考 BoostKit redis_network_async_optimization_feature_guide.md (redis-benchmark -q)_
```

**默认工具**: `redis-benchmark -q` (来自 BoostKit 官方文档命令)
- `-c 200 -d 3 -n 10000000 -r 10000000 -t set,get --threads 20`
- redis-benchmark 不输出 latency 分布,只看 ops/sec;如果需要 p50/p99 切换 `BENCH_CMD=memtier`

**可选工具**: `BENCH_CMD=memtier` 走 memtier_benchmark
- `--threads 2 --clients 10 --test-time 30 --ratio 1:1 --pipeline 4`
- 输出 latency 分布 + ops/sec

**关键字段解读**:
- `ops/sec`:每秒操作数,数字越大越好
- `p50/p99/p99.9 latency`:仅 memtier 模式填值

---

## 3. reviewer 怎么用

### 3.1 报告"绿"的判断

| 状态 | 含义 | 动作 |
|---|---|---|
| Job success + ops/sec 正常 | patch 应用 OK,redis 跑得动 | merge |
| Job success + ops/sec 比上次低 50%+ | 性能退化警告 | 看 diff 决定是否阻塞 |
| Job fail (build 阶段) | patch 让 upstream 编不过 | **必须修** 才能 merge |
| Job fail (redis 起不来) | patch 让 redis 启动崩溃 | **必须修** 才能 merge |

### 3.2 下载原始 log

每次 job 末尾会上传 2 个 artifact:
- `memtier-redis-7.0.15.zip`:memtier_benchmark 完整原始输出
- `summary-redis-7.0.15.zip`:本工作流生成的 markdown 摘要

下载后在 Actions 页面 `Artifacts` 区段。

---

## 4. 本地复现

如果你想在 merge 前本地先跑一遍(参考 BoostKit 文档依赖列表):

```bash
# 0. 装好 build 依赖(ubuntu 22.04+,从 openEuler yum 命令翻译)
#    对应 BoostKit redis_network_async_optimization_feature_guide.md:
#    yum -y install wget git vim tar make gcc gcc-c++ libatomic texinfo libtool
#    + 手动编 liburing / libconfig (这里用 apt 包替源码编)
sudo apt-get install -y build-essential autoconf automake libtool pkg-config \
                        tcl tcl-dev libssl-dev libatomic1 texinfo \
                        liburing-dev libconfig++-dev

# 1. (可选) 编 memtier_benchmark 2.1.0 — 默认 redis-benchmark 走 redis 自带,
#    只有 BENCH_CMD=memtier 时才需要
git clone --depth 1 --branch 2.1.0 https://github.com/RedisLabs/memtier_benchmark.git
(cd memtier_benchmark && autoreconf -i && ./configure && make -j$(nproc) && sudo make install)

# 2. 跑 build + bench(默认 redis-benchmark -q)
bash tools/build-perf.sh all redis-7.0.15

# 3. 看报告
cat artifacts/redis-7.0.15/summary.md
less artifacts/redis-7.0.15/benchmark.log
```

### 4.1 单独跑某一阶段

```bash
bash tools/build-perf.sh build redis-7.0.15   # 只 build,不跑 bench
bash tools/build-perf.sh bench redis-7.0.15   # 只跑 bench(假设已 build)
```

### 4.2 调参(覆盖默认)

```bash
# 切到 memtier(需要 latency 分布时)
BENCH_CMD=memtier bash tools/build-perf.sh bench redis-7.0.15

# redis-benchmark 调参(BoostKit 文档默认值)
BENCH_N=10000000 BENCH_CLIENTS=200 BENCH_SIZE=3 BENCH_THREADS=20 \
  bash tools/build-perf.sh bench redis-7.0.15

# 自定义 work 目录(避开 /tmp 容量限制)
WORK=/mnt/ssd/build-perf bash tools/build-perf.sh all redis-7.0.15
```

---

## 5. 与 verify.sh 的关系

| 维度 | verify.sh (ci.yml) | build-perf.sh (build-perf.yml) |
|---|---|---|
| 跑的内容 | dry-run `git apply --check` | 真的 `make` + 启 redis + 跑 memtier |
| 跑的速度 | ~30s(主要是 clone upstream) | ~2-3min(主要是 make) |
| 失败时 | **fail**(阻塞 merge) | build 阶段 fail 阻塞;bench 阶段 warn 不阻塞 |
| 报告输出 | 只有 pass/fail | markdown 表格 + memtier 原始 log artifact |
| 适用场景 | 日常 PR 默认门禁 | 性能相关 PR / patch 验证 PR |

**判断标准**:
- 普通 patch 改动 → verify 够用(默认 PR 触发)
- 性能敏感改动 / patch 兼容性验证 → build-perf 必跑(改动 patch 自动触发)
- 想跑 baseline 对比 → workflow_dispatch 手动触发任意 version

---

## 6. 故障排查

| 症状 | 原因 | 修复 |
|---|---|---|
| Job 跳过(`needs.changes.outputs.versions == '[]'`) | paths-filter 没识别 | 检查 PR diff 路径前缀,确认 `versions/<v>/**` |
| `apply 失败: 0001-xxx` | patch 与 upstream SHA 不匹配 | 更新 `version.yaml` 的 `upstream_base.commit` 到新 SHA,重新生成 patch |
| `redis-server 不存在` | 跳过 build 直接 bench | 先跑 `bash tools/build-perf.sh build <v>` |
| memtier 输出 0 ops | redis 没起来 / 端口冲突 | 看 `artifacts/<v>/redis.log` 或本机 `:6399` 是否被占 |
| memtier 慢到超时 | CI runner 抽风 | re-run job |
| cache miss | upstream SHA 变了 | 正常,会重新 clone(~25s) |

---

## 7. 不做的事(YAGNI)

- ❌ 不做 perf regression 自动 fail(波动大,留给人判断)
- ❌ 不跑 6.0.20 除非 PR 改了 6.0.20(paths-filter 自动判断)
- ❌ 不存历史趋势(30 天 artifact 自动过期)
- ❌ 不接 upstream HEAD(只用 yaml 里固定 commit,保证可复现)
- ❌ 不在 runner 上做 numa/绑核优化(ubuntu-latest 默认已够 quick smoke)
- ❌ 不做集群 benchmark(单机 quick smoke 足够判 patch 健康)

---

## 8. 端到端验证记录

| 字段 | 值 |
|---|---|
| 验证日期 | 2026-07-14 |
| 验证分支 | `feat/ci-build-perf` |
| 验证 PR | #14 ([链接](https://github.com/chaosv598/Redis-mvp-demo/pull/14)) |
| 验证目的 | 确认 PR → paths-filter → build → memtier → summary 全链路跑通 |
| 验证方法 | 1) 改 `versions/redis-7.0.15/version.yaml` 触发 paths-filter;2) 开 PR 后用 workflow_dispatch 触发;3) 修 bug 迭代 7 次(见下表) |
| 验证 Run IDs | `29325884241` ✅ SUCCESS / `29325218390` ✅ / `29324423039` ✅ / `29323615397` ✅ |
| 总耗时 | 首次 ~2.5min,带 cache 60s/版本(matrix=2: redis-7.0.15 + redis-6.0.20) |
| 状态 | ✅ 已通过 |

### 修复迭代历史(踩坑记录)

| 失败 | 根因 | 修复 |
|---|---|---|
| run 8s fail | dorny/paths-filter 输出是 bool 不是 JSON 数组 | 显式拼 JSON 数组作为 matrix |
| 8s fail "Unexpected symbol: 0.15" | filter key `redis-7.0.15` 的 `.` 被 GHA 当属性访问符 | filter key 重命名为 `redis_7_0_15` |
| step #4 memtier build 失败 | ubuntu 24.04 上 memtier source 编译 openssl 兼容 | 固定 ubuntu-22.04 + 显式 libevent-dev + 不静默 |
| step #3 apt install memtier 失败 | ubuntu universe 没 memtier 包 | 改回 source build (ubuntu 22.04 libssl 1.1 兼容) |
| step #5 build 失败 | version.yaml 上游 SHA 是错的(8f9ea51 不是 7.0.15 tag) | 改用 `git ls-remote` 验证的真值 `f35f36a26` 和 `de0d9632` |
| step #5 build 失败 | `git fetch --filter=blob:none --sparse` 报 'not our ref' | 改用普通 `--depth 1 --no-tags` clone + 按需 unshallow |
| step #5 build 失败 | patch apply 失败被 hard exit | 降级 warning(跟 verify.sh 一致),make build 失败仍 fail |
| step #5 build 失败 | `make ... \| tail` 让 set -e 看不到真错 | 加 `set -o pipefail + PIPESTATUS` |
