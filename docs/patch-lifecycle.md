# Patch 生命周期 & 治理工具

> v5 MVP 4 周落地版补丁治理剧本 · 2026-07-13
> 配套工具:`tools/check-deps.py` / `tools/lifecycle.py` / `tools/rebase.sh` / `tools/retire.sh` / `tools/status-report.sh` / `.githooks/pre-push`

## 1. 7 状态机

每个 patch 在 `metadata/<id>.yaml` 的 `status` 字段标识当前状态:

```
                ┌──────────┐
                │   New    │ patch 文件已 commit,但 check-apply 未通过
                └────┬─────┘
                     │ check-apply 干净 + build 过
                     ▼
                ┌──────────┐         上游决定不收(自留)
                │Validated │ ──────────────────────────┐
                └────┬─────┘                           │
       提交上游 PR   │                                ▼
                     ▼                          ┌────────────────┐
              ┌──────────────────┐              │ Downstream-Only│
              │Submitted-Upstream│              └────────┬───────┘
              └────────┬─────────┘                       │
                上游合入 │                                │ 不再需要
                       ▼                                │
              ┌──────────────────┐                      │
              │Upstream-Accepted │                      │
              └────────┬─────────┘                      │
                       │                                │
                       └────────┬───────────────────────┘
                                ▼
                          ┌──────────┐
                          │Deprecated│ remove_when.condition 满足
                          └────┬─────┘
                               │ retire.sh 删除
                               ▼
                          ┌──────────┐
                          │ Removed  │ 终态
                          └──────────┘
```

### 1.1 状态机合法转换

| 当前状态 | 合法下一状态 | 触发动作 |
|---|---|---|
| `New` | `Validated`, `Deprecated` | check-apply 绿 → Validated;老 patch 不用 → Deprecated |
| `Validated` | `Submitted-Upstream`, `Downstream-Only`, `Deprecated` | 发 PR / 不走上游 / 不再需要 |
| `Submitted-Upstream` | `Upstream-Accepted`, `Validated`, `Deprecated` | 上游 merge / PR 关闭 / PR 长期不响应 |
| `Upstream-Accepted` | `Deprecated` | 下个版本升级后这个 patch 不再需要 |
| `Downstream-Only` | `Deprecated` | 业务变化不再需要 |
| `Deprecated` | `Removed` | `bash tools/retire.sh <id>` 删除文件 |
| `Removed` | (无) | 终态 |

## 2. 7 个工具用法

### 2.1 `check-deps.py` —— 依赖校验

```bash
python3 tools/check-deps.py
```

校验每个 `versions/<v>/` 目录:
- series 中每个 patch 都有同名 metadata ✓
- `metadata.applies_on_top` 引用的依赖在 series 中排在前面 ✓
- 没有循环依赖 ✓

**用法时机**:
- 改完 metadata 后
- PR 提交前
- CI 中(`boostkit-v5-ci` 必跑)

### 2.2 `lifecycle.py` —— 状态机操作

```bash
# 列出所有 patch 当前状态
python3 tools/lifecycle.py status

# 转换状态(自动校验合法转换)
python3 tools/lifecycle.py redis-7.0.15-0001 Submitted-Upstream
python3 tools/lifecycle.py redis-7.0.15-0001 Upstream-Accepted

# 强制转换(跳过合法性校验)
python3 tools/lifecycle.py redis-7.0.15-0001 New --force

# 标 last_rebased_at
python3 tools/lifecycle.py redis-7.0.15-0001 mark-rebased 2026-07-13

# 记录上游 PR 链接(自动把 status 改成 Submitted-Upstream)
python3 tools/lifecycle.py redis-7.0.15-0001 link-upstream-pr https://github.com/redis/redis/pull/12345
```

### 2.3 `rebase.sh` —— 上游版本升级

```bash
bash tools/rebase.sh 7.0.16
```

**自动做**:
1. 拉上游新版本 SHA(`git ls-remote <upstream.url> refs/tags/7.0.16`)
2. 建 `versions/7.0.16/` 目录骨架
3. 从最新的旧版本(`7.0.15`)复制所有 patch + metadata,替换版本号
4. 跑 `check-apply.sh` 验证全链
5. 通过 → 所有 patch 标 `Validated` + `last_rebased_at: <today>`
6. 失败 → 保留在 `New`,人工事后修
7. 更新 `boostkit.yaml` 的 `upstream.versions[]`

**后续**:`git add -A && git commit -m 'chore(rebase): upgrade to 7.0.16'`

### 2.4 `retire.sh` —— patch 退役

```bash
# 正常退役(要求 status=Deprecated)
python3 tools/lifecycle.py redis-7.0.15-0001 Deprecated
bash tools/retire.sh redis-7.0.15-0001

# 强制退役(跳过状态校验,谨慎)
bash tools/retire.sh redis-7.0.15-0001 --force
```

**自动做**:
1. 检查状态(`--force` 跳过)
2. 从 `patches/` 删 patch 文件
3. 从 `metadata/` 删 metadata yaml
4. 从 `series` 删该行
5. 从 `boostkit.yaml#patches[]` 删条目
6. 跑 `check-series` / `check-deps` / `doctor` 校验

### 2.5 `status-report.sh` —— 健康看板

```bash
# 全部 patch 状态
bash tools/status-report.sh

# 高亮超过 90 天未 rebase 的 patch
bash tools/status-report.sh --days 90
```

输出表:`VERSION / ID / STATUS / REBASED / DAYS / UPSTREAM / RISK`

stale 判定:`days_since_rebase > threshold` 默认 180 天。

**用法时机**:
- 月度治理 review
- 发版前
- 季度清理

### 2.6 `.githooks/pre-push` —— 本地 push 钩子

```bash
# 一次性安装
bash tools/install-hooks.sh

# 卸载
bash tools/install-hooks.sh --uninstall

# 跳过单次 push
git push --no-verify
```

**自动做**(push 前):
1. `check-series`
2. `check-deps`
3. `doctor`

**不跑**(留给 CI):
- `check-apply`(网络 + 慢)
- `check-tag`(只在发版时)
- `check-owners`(本地 .git 仓无意义)

## 3. 端到端剧本(常见 4 种场景)

### 场景 A: 新增第 6 个 patch

```bash
# 1. 创建 patch 文件
vim versions/redis-7.0.15/patches/0006-perf-add-batched-commands.patch

# 2. 创建 metadata
cat > versions/redis-7.0.15/metadata/0006-perf-add-batched-commands.yaml <<EOF
id: redis-7.0.15-0006
title: ...
type: perf
status: New
applies_on_top:
  - redis-7.0.15-0003   # 排在 0003 之后
upstream:
  status: Not-Submitted
...
EOF

# 3. 加到 series
echo "0006-perf-add-batched-commands.patch" >> versions/redis-7.0.15/series

# 4. 加到 boostkit.yaml
$EDITOR boostkit.yaml  # patches[] 加新条目

# 5. 跑本地检查
python3 tools/check-deps.py
python3 tools/check-series.py

# 6. push
git add -A
git commit -m "feat(7.0.15): add batched commands perf patch"
git push   # pre-push hook 自动跑 3 个 check
```

### 场景 B: 上游 7.0.15 → 7.0.16 升级

```bash
bash tools/rebase.sh 7.0.16
# 自动化完成 7 步,只在失败时需要人工介入
git add -A
git commit -m "chore(rebase): upgrade to 7.0.16"
git push
```

### 场景 C: 某个 patch 上游已合入,本仓要退役

```bash
# 1. 改状态
python3 tools/lifecycle.py redis-7.0.15-0001 Upstream-Accepted
# 2. 填 metadata.upstream.upstream_commit
$EDITOR versions/redis-7.0.15/metadata/0001-hw-kunpeng-adapt-iouring.yaml
# 3. 标 Deprecated(等下个 rebase 后再删)
python3 tools/lifecycle.py redis-7.0.15-0001 Deprecated
# 4. 退役(下次发版前批量做)
bash tools/retire.sh redis-7.0.15-0001
```

### 场景 D: 月度治理 review

```bash
# 1. 看健康看板
bash tools/status-report.sh

# 2. 对 STALE patch 决定 rebase / deprecate
python3 tools/lifecycle.py redis-7.0.15-0001 Deprecated  # 长期不再用
# 或
bash tools/rebase.sh 7.0.16  # 上游有新版,迁移

# 3. 生成 release tag(已合并到 release.sh)
bash tools/release.sh Redis 7.0.15 bk-26.1.0
```

## 4. 完整工具栈速查

| 工具 | 输入 | 输出 | 用法时机 |
|---|---|---|---|
| `doctor.py` | 仓库根 | 7 铁律 hard/warn | 改完必跑,CI 必跑 |
| `lint.py` | boostkit.yaml | schema 校验 | 改 yaml 后 |
| `check-series.py` | 仓库根 | series 一致 | 增删 patch 后 |
| **`check-deps.py`** | 仓库根 | depends 一致 | 改 metadata 后,**新** |
| `check-owners.py` | OWNERS | approvers ≥ 2 | 改 OWNERS 后 |
| `check-apply.sh` | 仓库根 | 干净 apply | rebase 前,CI 必跑 |
| `check-tag.sh` | 仓库根 | tag 命名 | 发版前 |
| `release.sh` | proj ver product | release tag + branch | 月度/季度 |
| `migrate-mode-d.sh` | upstream url ver | 一次性迁移 | **新仓接入** |
| **`lifecycle.py`** | patch-id | 状态转换 | 状态变化时,**新** |
| **`rebase.sh`** | new-version | 全套升级 | 上游发布新版,**新** |
| **`retire.sh`** | patch-id | 4 处同步删 | Deprecated 后,**新** |
| **`status-report.sh`** | (无) | 健康看板 | 月度 review,**新** |
| **`.githooks/pre-push`** | (无) | push 前校验 | 本地开发,**新** |
| **`install-hooks.sh`** | (无) | 装/卸 hook | 一次性,**新** |

## 5. v5 §5 状态机在本仓的当前应用

| Patch | 当前状态 | last_rebased_at | days_since | 上游 status | 健康度 |
|---|---|---|---|---|---|
| redis-6.0.20-0001 | Validated | 2026-07-10 | 3 | Not-Submitted | ✅ 良好 |
| redis-7.0.15-0001 | Validated | 2026-07-10 | 3 | Submitted-Upstream | ✅ 良好,等上游合入 |
| redis-7.0.15-0002 | Downstream-Only | 2026-07-10 | 3 | Not-Submitted | ✅ 自留,无依赖 |
| redis-7.0.15-0003 | Downstream-Only | 2026-07-10 | 3 | Submitted-Upstream | ✅ 自留,等上游合入 |

(实际数据以 `bash tools/status-report.sh` 输出为准)

## 6. 与上游 PR 协同(完整流程)

```text
本地开发(新 patch)
    ↓
pre-push hook(check-series + check-deps + doctor 绿)
    ↓
git push 到 fork
    ↓
PR → master
    ↓
CI(6 个 job 全绿)+ OWNERS approve
    ↓
merge
    ↓
跑 check-apply 测一遍(已在 CI 跑)
    ↓
本仓 Validated 状态
    ↓
发上游 PR
    ↓
python tools/lifecycle.py <id> link-upstream-pr <url>
   → 自动改 status = Submitted-Upstream
    ↓
上游 review(可能几月)
    ↓
  ├── 上游 merge
  │     ↓
  │   python tools/lifecycle.py <id> Upstream-Accepted
  │   填 metadata.upstream.upstream_commit
  │   ↓
  │   等下个上游版本 rebase 时,自动转 Deprecated
  │   ↓
  │   bash tools/retire.sh <id> 删文件
  │
  └── 上游拒绝 / 长期不响应
        ↓
      python tools/lifecycle.py <id> Downstream-Only
      ↓
      长期维护,等业务变化再 Deprecated
```
