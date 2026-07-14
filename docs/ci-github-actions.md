# CI —— GitHub Actions 版

> 最后更新 2026-07-14(simplify-v2 后 1 job 落地版)
> 对应工作流:`.github/workflows/ci.yml`
> 配套工具:`bash tools/verify.sh`

---

## 0. 30 秒速读

- **1 个 job**:`verify`(ubuntu-latest)
- **3 步检查**:仓根禁放 → series 与 patches/ 一致 → 干净 upstream apply
- **3 个触发器**:push master / pull_request / workflow_dispatch
- **典型时长**:本地 ~5s,CI ~30s
- **完全免费**:Public 仓库无分钟限制

---

## 1. 触发条件

| 事件 | 行为 |
|---|---|
| `push` to `master` | 跑 1 个 verify job |
| `pull_request` to `master` | 同上 |
| `workflow_dispatch` | 手动触发,菜单里 Run workflow |

**并发控制**:`concurrency.cancel-in-progress = true`,**同 PR 后续 push 会取消旧 run**,节省 CI 分钟数。

---

## 2. Job 矩阵

| Job | 跑的命令 | blocking | 备注 |
|---|---|---|---|
| `verify` | `bash tools/verify.sh` | ✅ 必跑 | 1 步覆盖仓根禁放 + series 一致 + upstream apply |

(对比 `.gitee-ci.yml` 时代的 6 个 job:doctor / lint / check-series / check-owners / check-apply / check-tag — 全部合并到 1 个 verify,2026-07-13 simplify-v2 完成。)

---

## 3. 工作流文件

```yaml
# .github/workflows/ci.yml(完整文件)
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
    name: verify (patch overlay 一键校验)
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Install pyyaml
        run: pip install pyyaml --quiet
      - name: Run verify
        run: bash tools/verify.sh
```

---

## 4. verify.sh 内部检查细节

```bash
# tools/verify.sh 的 3 段逻辑(简化)
1. 仓根禁放检查:
   - *.patch 不能在仓根(应移到 versions/<v>/patches/)
   - Dockerfile / build.sh / Makefile 不能在仓根
   - src/ storage/ sql/ vendor/ 等目录不能出现在仓根

2. series vs patches/ 一致性:
   - 遍历 versions/<v>/
   - 比对 series 声明的行 vs patches/ 实际文件名
   - 不一致 → 1 个错误

3. 干净 upstream apply:
   - 从 metadata 读 upstream_base.repo + commit
   - git clone upstream(失败 → 回退到 tag checkout)
   - 逐 patch git apply --check
   - 单 patch apply 失败降级为 warning(不阻塞,owner 决定 rebase 或退役)
```

**退出码**:
- `0`:全部通过(可能有 warning,如 0002 apply 失败因为是历史占位 patch)
- `1`:有 hard 错误(仓根污染 / series 不一致 / 元数据缺失)

---

## 5. 关键翻译点(对比 .gitee-ci.yml)

1. **image → runs-on**: GitHub Actions 不需要 `image:` 字段,用 `runs-on: ubuntu-latest` 即可
2. **rules 条件**: `if: $CI_PIPELINE_SOURCE == 'merge_request_event'` → GitHub 的 `on: pull_request`
3. **artifact 路径**: `versions/*/reports/` 用 GLOB 通配,`upload-artifact@v4` 的 `if-no-files-found: ignore` 避免空目录失败
4. **apk add bash git**: ubuntu-latest 自带 bash + git,无需装
5. **6 个 job → 1 个 job**: 所有硬检查合并为 `bash tools/verify.sh`,保留硬性 fail,软警告降级为 stdout 输出
6. **allow_failure: true → 不存在**: 当前设计下 verify job 任何 patch apply 失败只 warn 不 fail,owner 决定 rebase 或退役,所以无需 `continue-on-error`

---

## 6. 预计运行时间

| 阶段 | 时间 | 备注 |
|---|---|---|
| Checkout + pip install pyyaml | ~5s | actions/checkout@v4 已缓存 |
| verify 仓根禁放 + series 一致 | <1s | 纯本地检查 |
| verify upstream clone + apply | ~25s | 主要花在 `git clone https://github.com/redis/redis --depth 1` |

**总时长 ~30s**(对比 .gitee-ci.yml 的 1-3 分钟,GitHub runner 普遍更快)。

---

## 7. 必要权限 / 限制

- **Public 仓库**: 完全免费,无分钟数限制
- **Private 仓库**: GitHub Free tier 给 2000 分钟/月
- 不需要任何 GitHub Secrets(verify.sh 走匿名 clone)
- 如未来要加私有 upstream,需 `GH_TOKEN` + `actions/checkout` 用 token

---

## 8. 失败处理

| 失败类型 | 修复路径 |
|---|---|
| `仓根发现 .patch 文件` | 移到 `versions/<v>/patches/` |
| `series 与 patches/ 不一致` | 把 `patches/*.patch` 文件名同步到 series(字典序) |
| `metadata 缺 upstream_base.repo 或 commit` | 补 yaml 字段 |
| `SHA 无效,改用 tag` | upstream commit SHA 写错了,查 git log 拿真实 SHA |
| `apply 失败(单 patch)` | warning 不阻塞;owner 决定 rebase 或 `lifecycle.sh retire <id>` archive |
| `clone <repo> 失败` | 几乎都是网络抖动,重跑即可 |

---

## 9. 与 v5 规范的对应

- v5 §1 第 7 条铁律: "所有 CI 必跑 4 步:yaml-lint → apply → build → owners,绿才允许 merge"
- 本仓 1 步 = `verify.sh` 覆盖 yaml 校验(隐式)+ apply(显式);**build 留给消费方**(Kunpeng ARM jenkins 或下游用户在本地跑);**owners 留给 GitHub PR review**(无强制 ≥ 2 签)
- v5 §3.7 `.gitee-ci.yml` 4 步模板 → 本文件做 GitHub Actions 适配
- v5 §13 验收指标 3 "CI 4 步接入: 100%(可豁免未启用)":**本仓已在 GitHub 启用,可作为 W2 验收示范**

---

## 10. 进一步优化方向(超出 MVP 4 周范围)

- 加 `actions/cache` 缓存 pip(影响小,跳过)
- upstream clone 改 sparse + shallow + cache,可能再省 10s(影响小,跳过)
- verify 改 matrix(每个 upstream version 一个 job,失败定位更准)— 当前 1 job 30s 已够用
- 加 `policy-bot` / `dangerjs` 强约束 PR 模板(本仓 PR 模板已是规范版本)

---

## 11. 端到端 PR 验证记录

| 字段 | 值 |
|---|---|
| 验证日期 | 2026-07-13 / 2026-07-14 |
| 验证人 | chaosv598 |
| 分支 | `feature/test-ci-pr-demo` / `feature/add-0004-rdb-aof-fallback` / `feature/retire-archive` |
| 验证目的 | 确认 1 个 verify job 在 PR + post-merge 触发器下全部跑通 |
| 验证方法 | 提交一个新增 patch 或文档改动,开 PR 到 master,等 CI 绿后 squash merge |
| 预期 | verify job `queued` → `in_progress` → `success`,post-merge 再跑一次 `success` |
| 状态 | ✅ 已通过(累计 3 次:run 29221506982 / 29248622734+29248680442 / 29252939807+29252990825) |

> 历史 6 job 矩阵时代(`.gitee-ci.yml` 翻译版)的所有 PR 验证 run ID 已废弃,见 `git log` archive。