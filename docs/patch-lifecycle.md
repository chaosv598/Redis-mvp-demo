# Patch 生命周期 & 治理工具

> 配套工具:`tools/verify.sh` / `tools/lifecycle.sh` / `tools/rebase.sh` / `tools/install-hooks.sh`
> 上游:`chaosv598/Redis-mvp-demo` · 最后更新 2026-07-14
> 本文档版本 = v5 MVP **simplify-v2 落地版**(4 工具 + 5 状态机 + archive-vs-delete)

---

## 0. 30 秒速读

| 维度 | 数值 |
|---|---|
| 工具数 | **4** 个(verify / lifecycle / rebase / install-hooks) |
| 状态数 | **5** 个(pending / validated / submitted / accepted / retired) |
| metadata 字段 | **6** 个(id / title / owner / upstream_base / applies_to / upstream_plan) |
| CI job | **1** 个(verify) |
| boostkit.yaml | **已删除**(2026-07-13 simplify-v2) |
| 元数据额外文件 | **不存在**(`OWNERS` / `OWNERS.yaml` / `boostkit.yaml` 全无) |
| 退役语义 | **archive 到 retired/(可恢复),而非真删**(2026-07-14 新增) |

---

## 1. 5 状态机

每个 patch 在 `metadata/<id>.yaml` 的 `upstream_plan.status` 字段标识当前状态。

```
                 ┌─────────┐
                 │ pending │ patch 文件已加入,未验证
                 └────┬────┘
                      │ verify.sh apply 干净 + 6 字段填齐
                      ▼
                 ┌──────────┐
                 │ validated│
                 └────┬─────┘
            发上游 PR │
                      ▼
                 ┌──────────┐
                 │submitted │
                 └────┬─────┘
              上游 merge │
                      ▼
                 ┌──────────┐
                 │ accepted │
                 └────┬─────┘
              退役动作 │
                      ▼
                 ┌──────────┐
                 │ retired  │ 终态(metadata + patch 已 mv 到 retired/)
                 └──────────┘
```

### 1.1 状态机合法转换

| 当前状态 | 合法下一状态 | 触发动作 |
|---|---|---|
| `pending` | `validated`, `retired` | `verify.sh` apply 干净 → `validated`;不想用 → `retired` |
| `validated` | `submitted`, `pending`, `retired` | 发上游 PR → `submitted`;回退改动 → `pending`;退役 → `retired` |
| `submitted` | `accepted`, `validated`, `retired` | 上游 merge → `accepted`;PR 被拒 → `validated`;长期不响应且不再需要 → `retired` |
| `accepted` | `retired` | 下次 rebase 不再带 → `retired` |
| `retired` | (无,只能 restore 复活成 `validated`) | 误操作恢复 → `bash tools/lifecycle.sh restore <id>` |

> 注:`retired` 虽是终态,但**不真删文件**。`lifecycle.sh restore <id>` 可把它移回 active 状态(`validated`),适合"先 archive 看看效果,过几天再真删"的工作流。

---

## 2. 4 工具用法

### 2.1 `verify.sh` —— 一键校验(本地 + CI 必跑)

```bash
bash tools/verify.sh
```

**做 3 件事**:

1. 仓根禁放检查(`*.patch` / `Dockerfile` / `Makefile` / `src/` 等不能出现在仓根)
2. `versions/<v>/series` 与 `patches/*.patch` 一致性(顺序和命名)
3. 干净 upstream apply(从 metadata 读 `upstream_base.repo + commit`,逐 patch `git apply --check`)

**用法时机**:

- 改完 metadata / series / patch 后
- PR 提交前
- CI 中(`.github/workflows/ci.yml` 唯一 job)
- pre-push hook(`.githooks/pre-push` 装上后,git push 自动跑)

退出码:`0` = 全过,`1` = 有失败。

### 2.2 `lifecycle.sh` —— 状态 + 退役 + 复活

```bash
# 列出所有 active patch
bash tools/lifecycle.sh list

# 看一个 patch 的 metadata
bash tools/lifecycle.sh show <id>                    # 只看 active
bash tools/lifecycle.sh show <id> --archived        # 看退役的

# 改状态
bash tools/lifecycle.sh set <id> <status>            # 自动校验合法转换

# 记录上游 PR(自动改 status=submitted)
bash tools/lifecycle.sh link <id> <pr-url>

# 标 rebase 时间(可选项)
bash tools/lifecycle.sh mark-rebased <id> 2026-07-14

# 退役(archive 到 retired/,可恢复)
bash tools/lifecycle.sh retire <id>                  # 要求 status=retired
bash tools/lifecycle.sh retire <id> --force          # 跳过状态校验

# 复活(退役后想恢复)
bash tools/lifecycle.sh restore <id>                 # archived → validated
```

**`retire` 实际动作**(对比之前的"4 处真删"):

| 路径 | 之前 | 现在 |
|---|---|---|
| `versions/<v>/metadata/<id>.yaml` | `rm` | `mv → metadata/retired/<id>.yaml` |
| `versions/<v>/patches/<id>.patch` | `rm` | `mv → patches/retired/<id>.patch` |
| `versions/<v>/series` | 删一行 | 同 |
| yaml `upstream_plan.status` | `retired` | 同(用 sed 单行改) |

退役后:
- active 集少 1 个 patch,`verify.sh` 显示 `N-1 个 patch 一致`
- 想"复活"就 `bash tools/lifecycle.sh restore <id>`,会把 metadata + patches 移回 active,series 加行,status 改 `validated`
- 想"真删"就手动 `rm versions/<v>/metadata/retired/<id>.{yaml,patch}` + `rmdir retired/`(可选)

### 2.3 `rebase.sh` —— 上游版本升级

```bash
bash tools/rebase.sh 7.0.16
```

**自动做**:

1. 拉上游新版本 SHA(`git ls-remote <upstream.url> refs/tags/7.0.16`)
2. 建 `versions/7.0.16/` 目录骨架
3. 从最新的旧版本(`7.0.15`)复制所有 patch + metadata,替换版本号
4. 跑 `verify.sh` 验证全链
5. 通过 → 所有 patch 标 `validated` + `last_rebased_at: <today>`
6. 失败 → 保留在 `pending`,人工事后修

### 2.4 `install-hooks.sh` —— 装/卸本地钩子

```bash
bash tools/install-hooks.sh              # 装 pre-push hook
bash tools/install-hooks.sh --uninstall  # 卸

git push --no-verify                     # 跳过单次
```

**自动做**(push 前):

1. `bash tools/verify.sh`(确保 series 一致 + apply 干净)

> 故意不跑 lifecycle / rebase — 那是状态/版本迁移,只在维护者主动操作时跑。

---

## 3. 端到端剧本(常见 5 种场景)

### 场景 A: 新增第 N 个 patch

```bash
# 1. 创建 patch 文件(放 versions/<v>/patches/)
$EDITOR versions/redis-7.0.15/patches/0005-perf-my-fix.patch

# 2. 创建 metadata(6 字段)
cat > versions/redis-7.0.15/metadata/0005-perf-my-fix.yaml <<EOF
id: redis-7.0.15-0005
title: ...
owner: me@boostkit
upstream_base:
  repo: https://github.com/redis/redis
  version: 7.0.15
  commit: <sha>
applies_to: 7.0.15
upstream_plan:
  status: pending
  pr: 
  note: ...
EOF

# 3. 加到 series
echo "0005-perf-my-fix.patch" >> versions/redis-7.0.15/series

# 4. 本地校验
bash tools/verify.sh

# 5. push
git add -A
git commit -m "feat(7.0.15): add my-fix patch"
git push   # pre-push hook 自动跑 verify
```

### 场景 B: 上游 7.0.15 → 7.0.16 升级

```bash
bash tools/rebase.sh 7.0.16
# 自动化完成 6 步,只在失败时需要人工介入
git add -A
git commit -m "chore(rebase): upgrade to 7.0.16"
git push
```

### 场景 C: 某个 patch 上游已合入,本仓要日落(sunset)

```bash
# 1. 标 accepted(语义:上游合入了)
bash tools/lifecycle.sh set redis-7.0.15-0001 accepted

# 2. 标 rebase 时间(可选项)
bash tools/lifecycle.sh mark-rebased redis-7.0.15-0001 2026-07-14

# 3. 标 retired(进入待退役状态)
bash tools/lifecycle.sh set redis-7.0.15-0001 retired

# 4. 退役(archive,非真删)
bash tools/lifecycle.sh retire redis-7.0.15-0001
# 自动做:
#   metadata/0001-...yaml → metadata/retired/0001-...yaml
#   patches/0001-...patch → patches/retired/0001-...patch
#   series                 删 0001-...patch 一行
#   yaml.status            → retired
#   跑 verify 自动校验

# 5. 文档同步(必做,grep 找引用)
grep -rn "io_uring\|0001-hw-kunpeng" README.md docs/ 2>/dev/null
# 改 README / feature_guide / CHANGELOG 删引用

# 6. 误操作想恢复
bash tools/lifecycle.sh restore redis-7.0.15-0001   # 移回 active,status=validated

# 7. 真删(过几个 release 确认不会回来)
rm versions/redis-7.0.15/metadata/retired/0001-*.yaml
rm versions/redis-7.0.15/patches/retired/0001-*.patch
```

### 场景 D: 改完 metadata / series / patch

```bash
# 1. 改完
$EDITOR versions/redis-7.0.15/metadata/0001-...yaml

# 2. 本地校验(必须)
bash tools/verify.sh

# 3. commit + push(pre-push 自动再跑一遍)
git add -A
git commit -m "fix(7.0.15): ..."
git push
```

### 场景 E: 月度治理 review

```bash
# 1. 看健康状态
bash tools/lifecycle.sh list

# 2. 对长期未动 / 不会再用的 patch 退役
bash tools/lifecycle.sh set redis-7.0.15-0003 retired
bash tools/lifecycle.sh retire redis-7.0.15-0003

# 3. 上游发新版时
bash tools/rebase.sh 7.0.16

# 4. 看哪些退役了
bash tools/lifecycle.sh show <archived-id> --archived
```

---

## 4. 完整工具栈速查

| 工具 | 输入 | 输出 | 用法时机 |
|---|---|---|---|
| `verify.sh` | 仓库根 | 系列一致 + apply 校验 | 改完必跑,CI + pre-push 自动 |
| `lifecycle.sh list` | (无) | active patch 状态表 | 任何时候 |
| `lifecycle.sh show <id>` | patch id | yaml 内容 | 查单个 patch |
| `lifecycle.sh set <id> <status>` | patch id + 状态 | 状态变更 | 状态变化时 |
| `lifecycle.sh link <id> <pr>` | patch id + PR URL | 上游 PR 记录 | 发 PR 后 |
| `lifecycle.sh mark-rebased <id> <date>` | patch id + 日期 | rebase 时间戳 | rebase 后 |
| `lifecycle.sh retire <id>` | patch id | archive 到 retired/ | 不再需要时 |
| `lifecycle.sh restore <id>` | patch id | 复活到 active | retire 误操作后 |
| `rebase.sh` | new-version | 全套升级 | 上游发新版 |
| `install-hooks.sh` | (无) | 装/卸 pre-push hook | 一次性 |

---

## 5. 本仓当前 patch 健康表

| Patch | upstream_plan.status | 上游 PR | 健康度 |
|---|---|---|---|
| redis-6.0.20-0001 | pending | - | ⚠️ 未验证 |
| redis-7.0.15-0001 | submitted | TBD | ✅ 等上游 review |
| redis-7.0.15-0002 | pending | - | ⚠️ 未验证(apply fail) |
| redis-7.0.15-0003 | submitted | jemalloc PR TBD | ✅ 等上游 review |
| redis-7.0.15-0004 | submitted | TBD | ✅ 等上游 review |

(实际数据以 `bash tools/lifecycle.sh list` 输出为准)

---

## 6. 与上游 PR 协同(完整流程)

```
本地开发(新 patch)
   ↓
pre-push hook(verify.sh 绿)
   ↓
git push 到 fork
   ↓
PR → master
   ↓
CI(1 个 verify job 绿)+ OWNER review(无强制 ≥ 2 签)
   ↓
merge(squash)
   ↓
post-merge CI verify 自动跑一次
   ↓
本仓 validated 状态
   ↓
发上游 PR
   ↓
bash tools/lifecycle.sh link <id> <pr-url>
   → 自动改 status = submitted
   ↓
上游 review(可能几月)
   ↓
├── 上游 merge
│     ↓
│   bash tools/lifecycle.sh set <id> accepted
│   ↓
│   bash tools/lifecycle.sh mark-rebased <id> <date>
│   ↓
│   bash tools/lifecycle.sh set <id> retired
│   ↓
│   bash tools/lifecycle.sh retire <id>   # archive 到 retired/
│
└── 上游拒绝 / 长期不响应
      ↓
    bash tools/lifecycle.sh set <id> validated
    ↓
    长期维护,等业务变化再 retired
```

---

## 7. 历次治理精简记录

| 时间 | 变更 | 工具数 | 状态机 | 字段 | CI job |
|---|---|---|---|---|---|
| 2026-06-XX | 治理前 | 0 | 无 | 无 | 无 |
| 2026-07-08 | v5 MVP 初版 | 14 | 7 | 13 | 7 |
| 2026-07-10 | simplify-v1 | 6 | 5 | 6 | 1 |
| 2026-07-13 | simplify-v2 | 4 | 5 | 6 | 1 |
| 2026-07-14 | archive-vs-delete | 4 | 5 | 6 | 1 |

`retired/` 子目录和 `restore` 命令是 2026-07-14 archive-vs-delete 改动新增。