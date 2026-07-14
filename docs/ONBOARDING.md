# 新人 Onboarding —— 5 分钟跑通 PR 全流程

> **目标**:让新人 5 分钟内完成"改一处 → 本地 verify → push → 开 PR → CI 绿 → merge"的全流程。
> **适用对象**:第一次接触本仓的开发者(假设你会 git + GitHub + bash 基础)。
> **配套文档**:`docs/GOVERNANCE.md`(设计原理)+ `docs/patch-lifecycle.md`(元数据)+ `docs/ci-github-actions.md`(CI)。

---

## 0. 30 秒速读

- **唯一工具**:`bash tools/verify.sh`(本地必跑,CI 自动跑)
- **唯一元数据**:`versions/<v>/version.yaml`(一版本一 yaml)
- **3 状态**:`pending`(待发 PR)→ `submitted`(已发 PR)→ `accepted`(已合入)
- **patch 分类**:`type=ecological`(需合入上游) / `type=project`(本仓独享)
- **没有** lifecycle 工具、rebase 工具、retired 目录、pre-push 钩子

---

## 1. 准备环境(1 分钟)

### 1.1 克隆仓库

```bash
git clone https://github.com/chaosv598/Redis-mvp-demo.git
cd Redis-mvp-demo
```

### 1.2 验证仓健康度

```bash
bash tools/verify.sh
```

**期望输出**(看到这行就 OK):

```
=== boostkit verify ===
--- 仓根禁放检查 ---
  ✓ 仓根干净
--- version.yaml 校验 + upstream apply ---
  ✓ redis-6.0.20: 1 个 patch 与 version.yaml 一致
  ✓ redis-7.0.15: 4 个 patch 与 version.yaml 一致
  ...
--- 汇总 ---
✓ verify 全部通过(2 个版本,patch overlay 健康)
```

如果失败,看错误信息:
- `仓根发现 .patch 文件` → 有 patch 误放仓根,移到 `versions/<v>/patches/`
- `patches[] 与 patches/ 不一致` → yaml 数组和实际文件对不上
- `type=... 不是 ecological/project` → 看 §5 元数据字段说明

---

## 2. 走一遍全流程(改一个 patch 标题)

**目标**:把 `redis-7.0.15/0001-hw-kunpeng-adapt-iouring` 的 title 从 "Adapt io_uring for Kunpeng ARM" 改成 "Adapt io_uring for Kunpeng ARM(2026 修订)",演示完整 PR 流程。

### 2.1 创建分支

```bash
# 永远不要直接在 master 上改
git checkout master
git pull origin master           # 拉最新
git checkout -b docs/onboarding-demo
```

**分支命名建议**:`<类型>/<简述>`,类型用 `feat-` / `fix-` / `docs-` / `chore-` / `refactor-`。

### 2.2 改文件

打开 `versions/redis-7.0.15/version.yaml`,找到 `0001-hw-kunpeng-adapt-iouring` 那条:

```diff
 patches:
   - name: 0001-hw-kunpeng-adapt-iouring
-    title: Adapt io_uring for Kunpeng ARM
+    title: Adapt io_uring for Kunpeng ARM (2026 修订)
     owner: twwang@boostkit
     type: ecological
     status: submitted
     pr: https://github.com/redis/redis/pull/TBD
     note: Submitted upstream, awaiting review
     dependence: []
```

### 2.3 本地 verify(必跑,CI 必跑,commit 前必跑)

```bash
bash tools/verify.sh
```

**期望输出**:和 §1.2 一致,无 hard error。

### 2.4 commit

```bash
git add versions/redis-7.0.15/version.yaml
git commit -m "docs(0001): refine title for 2026 revision"
```

**commit 规范**(参考历史 `git log`):

- `feat(<版本>): <新功能>`
- `fix(<版本>): <bug fix>`
- `docs(<patch>): <文档/元数据>`
- `chore(<版本>): <rebase / 杂项>`

### 2.5 push

```bash
git push -u origin docs/onboarding-demo
```

> 注意:本仓**没有 pre-push 钩子**(simplify-v3 删了),所以 push 不会自动跑 verify。养成"commit 前手动跑 verify"的习惯。

### 2.6 开 PR

**方法 A:用 GitHub Web**(新人推荐)

浏览器会跳到 GitHub 的 "Compare & pull request" 页面。点 "Create pull request"。标题和描述参考 `.github/PULL_REQUEST_TEMPLATE.md`。

**方法 B:用 gh CLI**(本仓 CI 推荐)

```bash
gh pr create --title "docs(0001): refine title for 2026 revision" --body "$(cat <<'EOF'
## 改了什么
- patch name: 0001-hw-kunpeng-adapt-iouring
- 上游版本: redis-7.0.15
- 类型: docs

## 验证
- [x] \`bash tools/verify.sh\` 通过(本地)
- [x] 修改了 versions/redis-7.0.15/version.yaml 的 patches[] 数组
- [x] patch 字段填齐

## 影响
- 影响的版本: redis-7.0.15
- 是否触发上游 PR: no
EOF
)"
```

### 2.7 等 CI

打开 PR 页面,看右下角 GitHub Actions 进度:

```
✓ verify (patch overlay 一键校验) — Running... → Success
```

**~30 秒**完成。看到绿色 ✅ 就说明 CI 过了。

### 2.8 review & merge

- 至少 1 个 OWNER review 即可(simplify-v3 不强制 ≥ 2)
- 点 "Squash and merge"(推荐,把整个 PR 合成 1 个 commit 落 master)
- 点 "Confirm squash and merge"

### 2.9 post-merge 验证

master push 会再触发一次 CI(同一个 workflow,但 group key 不同),自动 verify 一次。

```
✓ verify (patch overlay 一键校验) — Success  ← post-merge
```

**完成**。你已走完完整 PR 流程 🎉

---

## 3. 真实工作流:新增第 N 个 patch

§2 演示的是改元数据。真实场景更常见的是**新增 patch**。

### 3.1 创建 patch 文件

```bash
# 假设要新增 0005-fix-memory-leak.patch
$EDITOR versions/redis-7.0.15/patches/0005-fix-memory-leak.patch
```

**patch 格式规范**:

```diff
From: dev@boostkit
Subject: [PATCH] Fix memory leak in cluster slot update

---
 src/cluster.c | 5 ++++-
 1 file changed, 4 insertions(+), 1 deletion(-)

diff --git a/src/cluster.c b/src/cluster.c
index abc1234..def5678 100644
--- a/src/cluster.c
+++ b/src/cluster.c
@@ -123,6 +123,7 @@ void clusterUpdateSlots(...) {
     ...
     free(old_config);
+    serverLog(LL_WARNING, "freed old config");
     return C_OK;
 }
```

### 3.2 在 version.yaml 添加条目

打开 `versions/redis-7.0.15/version.yaml`,在 `patches[]` 数组**末尾**追加:

```yaml
patches:
  - name: 0001-hw-kunpeng-adapt-iouring
    # ... (已有)
  - name: 0005-fix-memory-leak
    title: Fix memory leak in cluster slot update
    owner: dev@boostkit
    type: ecological               # 或 project
    status: pending                # 初始状态
    note: Fix found during stress test
    dependence: []                 # 依赖前面的 patch(空数组 = 无依赖)
```

### 3.3 verify

```bash
bash tools/verify.sh
```

期望:`redis-7.0.15: 5 个 patch 与 version.yaml 一致`,apply 通过。

### 3.4 commit + push + PR

```bash
git add versions/redis-7.0.15/patches/0005-fix-memory-leak.patch
git add versions/redis-7.0.15/version.yaml
git commit -m "feat(7.0.15): add 0005-fix-memory-leak patch

- Fix memory leak in clusterUpdateSlots when slot migration aborts
- Free old config + log warning to ease diagnosis"
git push -u origin feat/add-0005-memory-leak-fix
gh pr create --title "feat(7.0.15): add 0005-fix-memory-leak patch"
```

---

## 4. 改 patch 状态(从 pending → submitted)

当上游 PR 发出后,把 status 改成 submitted:

```yaml
# versions/redis-7.0.15/version.yaml
  - name: 0005-fix-memory-leak
    # ...
-    status: pending
+    status: submitted
+    pr: https://github.com/redis/redis/pull/12345
```

commit + push + PR,merge 后状态自动落 master。

**没有 lifecycle 工具**:直接改 yaml 字段即可,git commit message 即时间线。

---

## 5. 元数据字段速查

### 5.1 版本字段(version.yaml 顶层)

| 字段 | 必填 | 示例 |
|---|---|---|
| `version_id` | ✅ | `redis-7.0.15` |
| `description` | ✅ | `Redis 7.0.15 patch overlay (BoostKit)` |
| `owner` | ✅ | `chaosv598@boostkit` |
| `upstream_base.repo` | ✅ | `https://github.com/redis/redis` |
| `upstream_base.version` | ✅ | `7.0.15` |
| `upstream_base.commit` | ✅ | `<commit SHA>` |

### 5.2 patches 数组元素

| 字段 | 必填 | 枚举 | 示例 |
|---|---|---|---|
| `name` | ✅ | 字符串 | `0005-fix-memory-leak` |
| `title` | ✅ | 字符串 | `Fix memory leak in cluster slot update` |
| `owner` | ✅ | 邮箱 | `dev@boostkit` |
| `type` | ✅ | `ecological` / `project` | `ecological` |
| `status` | ✅ | `pending` / `submitted` / `accepted` | `pending` |
| `pr` | ⬜ | URL | `https://github.com/...` |
| `note` | ⬜ | 文本 | `Fix found during stress test` |
| `dependence` | ⬜ | 数组 | `["0004-perf-rdb-fallback-aof"]` |

**verify.sh 校验 enum**:填错会 hard error 立刻报错。

---

## 6. 常见错误与排查

| 报错 | 原因 | 修复 |
|---|---|---|
| `✗ 仓根发现 .patch 文件` | patch 误放仓根 | `mv *.patch versions/<v>/patches/` |
| `✗ version.yaml 缺 upstream_base.repo` | 顶层字段没填 | 补 yaml 字段 |
| `✗ patches[] 与 patches/ 不一致` | yaml 数组声明的文件名 ≠ 实际文件 | 同步 yaml 数组或补文件 |
| `✗ type=foo 不是 ecological/project` | enum 填错 | 改成 `ecological` 或 `project` |
| `⚠ SHA 不可达,改用 tag` | upstream_base.commit 写错 | `git ls-remote <repo> <version>` 拿真实 SHA |
| `⚠ <patch>: apply 失败` | baseline 不匹配 | 检查 patch 内容,可能要 rebase |

---

## 7. 不要做的事(避免 PR 被拒)

1. ❌ **不要在 master 上直接改** — 必须开分支
2. ❌ **不要直接 push 到 master** — 必须通过 PR
3. ❌ **不要绕过 verify.sh** — 改完必跑
4. ❌ **不要加 enum 之外的状态字段**(如 `rejected` / `in_review`)— verify.sh 会硬错
5. ❌ **不要把 .patch 文件放在仓根** — 必须在 `versions/<v>/patches/`
6. ❌ **不要在 patches[] 数组中间插入** — 永远在末尾追加(数组顺序 = apply 顺序)
7. ❌ **不要 commit 大量混改** — 一个 PR 一个主题(新增/修改/状态变更,分开)

---

## 8. 工具速查

```bash
# 唯一本地工具
bash tools/verify.sh        # 4 步验证(仓根 / 字段 / 一致性 / apply)

# CI 工具
# GitHub Actions 1 个 job:verify
# 触发:push master / pull_request / workflow_dispatch
# 详情:docs/ci-github-actions.md

# Git 工具(标准)
git status
git diff
git add -A
git commit -m "..."
git push -u origin <branch>

# gh CLI(可选)
gh pr create
gh pr list
gh pr checks
```

---

## 9. 完成清单

新人跑完这个 onboarding 后应能:

- [ ] 克隆仓 + 跑 `verify.sh` 看到绿色
- [ ] 创建分支 + 改一个 patch 标题 + commit + push
- [ ] 用 `gh pr create` 或 GitHub Web 开 PR
- [ ] 等 CI 看到绿色 ✅
- [ ] 走完 review → squash merge → post-merge CI
- [ ] 新增一个 patch(文件 + yaml)通过 verify
- [ ] 把一个 patch 状态从 pending 改成 submitted

---

## 10. 下一步深入

- `docs/GOVERNANCE.md` — 仓设计原理(为什么 1 工具 / 3 状态 / 一版本一 yaml)
- `docs/patch-lifecycle.md` — 元数据格式 + 4 个常见场景
- `docs/ci-github-actions.md` — CI 内部细节
- `docs/PATCH_OVERLAY_PATTERNS.md` — 与业界 6 个方案对比,理解本仓轻量化定位
