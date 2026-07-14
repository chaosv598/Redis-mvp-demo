# CI —— GitHub Actions 版

> 最后更新：2026-07-14
> 工作流：`.github/workflows/ci.yml`
> 唯一工具：`tools/verify.sh`

## 1. 目标

GitHub Actions 在 PR 和 `master` push 上验证两类能力：

1. patch overlay 的结构、元数据、一致性和上游 apply 健康度。
2. 从 Redis 官方仓库下载固定 commit，应用可移植演示补丁，完成编译、启动、功能测试和
   `redis-benchmark` 性能 smoke test。

仓库仍保持 **1 个工具 + 1 个 CI job**。E2E 是 `verify.sh` 的另一种模式，不增加生命周期
或构建工具。

## 2. 触发器与并发

| 事件 | 行为 |
|---|---|
| `pull_request` to `master` | 运行完整 verify job，失败时阻塞 PR |
| `push` to `master` | 合并后重新运行完整 verify job |
| `workflow_dispatch` | 手动运行 |

`concurrency.cancel-in-progress: true` 会取消同一分支或 PR 的旧 run。

## 3. 单 job 两阶段

### 3.1 快速 patch overlay 校验

```bash
bash tools/verify.sh
```

检查：

- 仓根禁放文件。
- `version.yaml` 必填字段和枚举。
- `patches[]` 与 `patches/` 文件一致。
- 按数组顺序尝试应用产品补丁。

为兼容当前主干治理，产品补丁 apply 失败仍输出 warning，不在这一阶段 hard fail。

### 3.2 patched Redis E2E

```bash
bash tools/verify.sh --e2e redis-7.0.15
```

严格步骤：

1. 从 `versions/redis-7.0.15/version.yaml` 读取上游仓库和完整 SHA。
2. shallow fetch 该 SHA，并验证 checkout 后的 `HEAD` 完全一致；不回退 tag。
3. 应用 `tests/fixtures/redis-7.0.15/0001-ci-version-marker.patch`。
4. 编译 Redis，检查 `redis-server --version` 含 `7.0.15-ci-patched`。
5. 启动仅监听 `127.0.0.1` 的临时实例。
6. 验证 PING、SET/GET 和 INCR。
7. 运行 PING_INLINE、SET、GET benchmark。
8. PING_INLINE 必须达到 **10,000 requests/s**；SET/GET 只记录，不设门槛。

任一下载、SHA、补丁、编译、版本标识、启动、功能、解析或性能步骤失败，job 都返回非零。

## 4. 工作流

```yaml
name: verify

on:
  push:
    branches: [master]
  pull_request:
    branches: [master]
  workflow_dispatch:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pip install pyyaml --quiet
      - run: bash tools/verify.sh
      - run: |
          sudo apt-get update
          sudo apt-get install -y build-essential pkg-config tcl
      - env:
          E2E_RESULTS_DIR: ${{ runner.temp }}/redis-e2e-results
        run: bash tools/verify.sh --e2e redis-7.0.15
      - if: always()
        uses: actions/upload-artifact@v4
        with:
          name: redis-e2e-results
          path: ${{ runner.temp }}/redis-e2e-results
```

典型耗时约 3-5 分钟，主要是 Redis 依赖和源码编译。Public 仓库使用标准 GitHub-hosted
runner，无需项目 Secrets。

## 5. 结果与证据

E2E 成功后会把以下内容写入 GitHub Job Summary：

- Redis 版本与固定 commit。
- `7.0.15-ci-patched` 补丁标识。
- 功能测试结论。
- PING_INLINE 吞吐量和 10,000 requests/s 门槛。
- PING_INLINE、SET、GET 原始 CSV。

`actions/upload-artifact@v4` 使用 `if: always()` 上传 `redis-e2e-results`，其中包括：

- `summary.md`
- `benchmark.csv`
- `version.txt`
- `redis.log`

失败时先看对应 step，再下载 artifact 获取已有诊断文件。

## 6. 本地复现

依赖：

```bash
sudo apt-get install -y build-essential pkg-config python3 python3-yaml
```

运行：

```bash
bash tests/test-verify-cli.sh
bash tests/test-ci-contract.sh
bash tools/verify.sh
E2E_RESULTS_DIR="$PWD/e2e-results" bash tools/verify.sh --e2e redis-7.0.15
```

`e2e-results/` 已加入 `.gitignore`。

## 7. 能力边界

CI 演示补丁只是可移植的版本标识，不是产品补丁，也不加入 `patches[]` 或 patch 状态机。

GitHub-hosted `ubuntu-latest` **不验证 KRAIO/DTOE 功能或性能**。真实鲲鹏验证需要：

- ARM64 鲲鹏服务器。
- openEuler 和适配内核。
- `libkraio`、DTOE 相关专用库。
- GitHub self-hosted runner。
- 与生产网络拓扑一致的独立性能方案。

当前 PING_INLINE 门槛只用于发现服务未启动、严重退化或 benchmark 输出异常，不能用于容量
规划，也不构成产品性能承诺。

## 8. 常见失败

| 现象 | 处理 |
|---|---|
| exact SHA fetch 失败 | 核对 `upstream_base.commit` 是否为官方仓库可达的 40 位 SHA |
| demo patch apply 失败 | 基于固定 SHA 重新生成 `tests/fixtures/` 补丁 |
| patched marker 缺失 | 确认编译使用的是临时源码目录而非系统 Redis |
| Redis readiness 超时 | 查看 artifact 中的 `redis.log` |
| benchmark 无 PING_INLINE | 查看 `benchmark.csv`，核对 Redis 版本输出格式 |
| PING_INLINE 低于门槛 | 重跑一次排除 runner 抖动；持续失败时检查日志和 runner 负载 |
