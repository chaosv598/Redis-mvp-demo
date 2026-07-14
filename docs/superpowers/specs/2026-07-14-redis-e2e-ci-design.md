# Redis 指定提交端到端 CI 设计

## 背景

当前仓库以 `tools/verify.sh` 作为唯一验证入口。GitHub Actions 会检查元数据、补丁目录一致性以及补丁能否应用，但不会编译 Redis、启动服务或执行功能和性能验证。现有鲲鹏 KRAIO/DTOE 补丁依赖 ARM64、openEuler 定制内核和专用动态库，无法在标准 `ubuntu-latest` runner 上完成真实运行验证。

本设计在不改变“一版本一 YAML、一个工具、一个 CI job”治理原则的前提下，增加一条可移植的端到端演示链路，证明指定上游提交可以完成下载、打补丁、编译、启动、功能测试和性能 smoke test。

## 目标

- PR 和 `master` push 均运行完整端到端验证。
- 从 `versions/redis-7.0.15/version.yaml` 读取上游仓库和固定 commit SHA。
- 精确下载该 commit，不允许静默回退到 tag 或其他提交。
- 应用一个仅用于 CI 的可移植演示补丁，并在运行时证明补丁已进入二进制。
- 编译 Redis，启动隔离实例，运行基础功能测试。
- 使用 `redis-benchmark` 执行短时性能 smoke test，并设置低噪声健康门槛。
- 把摘要写入 GitHub Job Summary，并保存原始 benchmark 日志为 artifact。
- 任一关键步骤失败时阻塞 PR。

## 非目标

- 不在 GitHub-hosted runner 上模拟或宣称验证 KRAIO/DTOE 的真实性能。
- 不下载闭源或来源不明确的专用依赖。
- 不把演示补丁加入产品补丁 `patches[]`，也不改变现有补丁状态机。
- 不建立跨机器、长时间或可用于容量规划的性能基准。
- 不增加新的生命周期、rebase 或发布工具。

## 方案选择

采用“扩展现有 `verify.sh` + 保持单 CI job”的方案。

备选方案包括新增独立脚本/job，以及使用 Docker 固化环境。独立脚本/job 的职责更直观，但会扩大当前治理表面；Docker 更稳定，但增加镜像维护并弱化 runner 直接源码构建的示范价值。当前目标是最小成本证明全链路，因此保留一个入口和一个 job。

## 架构与数据流

`bash tools/verify.sh` 继续执行现有快速校验。新增 `bash tools/verify.sh --e2e redis-7.0.15` 模式，流程如下：

1. 读取 `version.yaml` 中的 `upstream_base.repo` 和 `upstream_base.commit`。
2. 在临时目录初始化 Git 仓库，只 fetch 指定 SHA，并验证 `HEAD` 与 SHA 完全一致。
3. 使用 `git apply --check` 严格检查并应用 CI 演示补丁。
4. 编译 Redis，并检查 `redis-server --version` 含预期补丁标识。
5. 在非默认端口启动临时 Redis，等待健康检查通过。
6. 运行 `PING`、`SET/GET`、`INCR` 功能用例。
7. 运行 PING、SET、GET benchmark，解析 PING 吞吐量。
8. 要求 PING 至少达到 10,000 requests/s。
9. 写入文本结果；GitHub 环境下同时写入 `$GITHUB_STEP_SUMMARY`。
10. 无论成功失败都通过 trap 停止 Redis 并清理临时目录。

## 组件设计

### `tools/verify.sh`

- 无参数行为保持兼容，继续执行现有仓库结构、元数据和补丁 apply 校验。
- `--e2e redis-7.0.15` 只执行端到端模式。
- 不支持的参数或版本立即返回非零退出码并打印用法。
- 网络失败、SHA 不存在、补丁失败、编译失败、启动失败、功能失败、结果无法解析或性能低于门槛都作为 hard failure。
- E2E 模式不会使用现有“SHA 不可达则回退 tag”逻辑。

为保持脚本边界清晰，E2E 逻辑拆成小函数：元数据读取、源码准备、补丁应用、编译、服务生命周期、功能测试、benchmark 和摘要输出。

### CI 演示补丁

补丁放在 `tests/fixtures/redis-7.0.15/0001-ci-version-marker.patch`。它只修改 Redis 版本字符串，加入 `-ci-patched` 标识。编译后通过 `redis-server --version` 检查标识，从而证明运行的二进制来自已应用补丁的源码。

该文件是测试夹具，不是产品补丁：

- 不加入 `versions/redis-7.0.15/version.yaml` 的 `patches[]`。
- 不参与 pending/submitted/accepted 状态机。
- 文档和目录命名必须明确标注 CI/demo/fixture。

### `.github/workflows/ci.yml`

保留现有 `verify` job，在快速校验之后增加 E2E step。工作流安装 Redis 构建所需的最小依赖，然后调用统一工具入口。benchmark 原始日志由 `actions/upload-artifact` 上传；即使 E2E 失败，也尝试上传已产生的诊断文件。

并发取消策略、PR/master 触发器和 `ubuntu-latest` 保持不变。

## 功能与性能测试

功能测试使用刚编译出的 `redis-cli`，至少覆盖：

- `PING` 返回 `PONG`。
- `SET ci:key value` 后 `GET ci:key` 返回 `value`。
- 连续两次 `INCR ci:counter` 后结果为 `2`。

性能 smoke test 使用刚编译出的 `redis-benchmark`：

- 测试类型：PING_INLINE、SET、GET。
- 请求量：每项约 20,000，客户端并发约 20。
- hard gate：PING_INLINE 至少 10,000 requests/s。
- SET/GET 结果仅记录，不设硬门槛。

该门槛只用于发现服务未正常工作、严重退化或 benchmark 输出异常，不代表真实性能承诺。

## 错误处理与诊断

- 所有错误写到 stderr，并包含失败阶段。
- Redis 日志、benchmark 原始输出和摘要保存在统一结果目录。
- CI 使用 `if: always()` 上传结果目录，便于失败排查。
- 服务启动设置有限重试次数，超时后输出 Redis 日志并失败。
- trap 记录 Redis PID，只终止本次脚本启动的进程。
- 临时端口使用高位固定端口并在启动前检查占用；GitHub runner 为单 job 隔离环境。

## 安全与可复现性

- 上游来源和 commit 来自仓库受评审的 `version.yaml`。
- 必须校验完整 SHA，不执行下载内容提供的任意安装脚本。
- 不使用 token、Secrets 或私有依赖。
- GitHub Actions 第三方 action 固定到明确的主版本；仅使用官方 checkout/upload-artifact action。
- 不提交编译产物、临时目录、日志或 benchmark 本地输出。

## 文档同步

更新以下主干设计文档：

- `docs/GOVERNANCE.md`：仍为一个工具和一个 job，但验证范围增加 E2E。
- `docs/ci-github-actions.md`：描述下载、补丁、编译、启动、功能与性能步骤，以及 GitHub Summary/artifact。
- `docs/ONBOARDING.md`：补充本地 E2E 命令和预期输出。
- `.github/PULL_REQUEST_TEMPLATE.md`：增加 E2E 验证项。

## 验证策略

实现遵循测试先行：

1. 先增加脚本接口/静态契约测试，证明当前脚本不支持 `--e2e`，测试应按预期失败。
2. 实现参数解析和 E2E 函数后使契约测试通过。
3. 在本地完整运行 `bash tools/verify.sh`。
4. 在本地完整运行 `bash tools/verify.sh --e2e redis-7.0.15`。
5. 推送分支并创建 PR，通过 `gh pr checks --watch` 验证远端 GitHub Actions。
6. 记录 workflow run URL、最终结论、benchmark 摘要和 artifact 状态。

## 验收标准

- 新分支基于最新 `origin/master`。
- 普通 `verify.sh` 行为兼容且成功。
- E2E 日志明确显示固定 commit、补丁标识、编译成功、Redis 启动成功和三个功能用例成功。
- benchmark 成功解析，PING_INLINE 不低于 10,000 requests/s。
- Job Summary 展示 commit、patch marker、功能结果和性能数据。
- 原始日志 artifact 可在 workflow run 中查看。
- 人为破坏演示补丁、功能断言或性能门槛时，CI 能以非零状态失败。
- 相关治理、CI、onboarding 和 PR 文档同步完成。
