# Redis 治理后仓库说明

> **目的**:让第一次接触本仓的开发者,5 分钟内能上手。
> **本仓**: `chaosv598/Redis-mvp-demo`(原 `boostkit/Redis` fork,按 v5 MVP 4 周落地版治理)
> **核心目标**:**开发者愿意配合** — 4 个工具 + 6 字段 metadata + 1 个 CI job,够用就行。

---

## 0. 30 秒速读

| 维度 | 数值 |
|---|---|
| 仓文件总数 | ~95 个 |
| 上游适配版本 | 2 个(redis-6.0.20, redis-7.0.15) |
| patch 总数 | 4 个 |
| 工具数 | **4 个**(verify / lifecycle / rebase / install-hooks) |
| 必填 metadata 字段 | **6 个** |
| CI job | **1 个** |
| 验证耗时 | ~5 秒(本地) / ~30 秒(CI) |

**对比**:
- 治理前: 4 个 patch 散落仓根,5 步手工,无 CI
- 治理前(中间): 14 工具 + 7 状态机 + 13 字段 + 7 CI job,**对开发者重**
- 治理后(现在): **4 工具 + 4 状态 + 6 字段 + 1 CI job**,够用

---

## 1. 整体目录结构

```
Redis-mvp-demo/
├── README.md / README_en.md       # 上游产品介绍(给最终用户,未动)
├── LICENSE.txt                    # 上游 BSD 许可
│
├── versions/                      # ★ 每个上游版本一个子目录
│   ├── redis-6.0.20/
│   │   ├── series                #    patch 应用顺序
│   │   ├── patches/0001-...patch #    实际补丁
│   │   └── metadata/0001-...yaml #    patch 元信息(6 字段)
│   └── redis-7.0.15/
│       └── (同上)
│
├── tools/                         # ★ 4 个治理脚本
│   ├── verify.sh                 #    一键验证(本地 + CI 跑)
│   ├── lifecycle.sh              #    状态 + 退役管理
│   ├── rebase.sh                 #    上游发新版时升级
│   └── install-hooks.sh          #    装本地 pre-push 钩子
│
├── .github/
│   ├── workflows/ci.yml           # ★ 1 个 CI job:verify
│   └── PULL_REQUEST_TEMPLATE.md
│
├── .githooks/pre-push             # ★ 本地 push 前自动跑 verify.sh
│
└── docs/                          # 文档
    ├── GOVERNANCE.md              #    本文档
    └── zh/、en/                   #    上游产品文档(未动)
```

**对比治理前**:
- ❌ 之前: `boostkit.yaml` + 14 个工具 + `OWNERS` + `.gitee-ci.yml` + 7 状态机 + 13 字段 metadata
- ✅ 现在: **没有 boostkit.yaml**、**没有 OWNERS 文件校验**、**没有 .gitee-ci.yml 模板**,只保留 4 个 bash 脚本

---

## 2. 关键文件作用和具体介绍

### 2.1 metadata 6 字段(每个 patch 一份 yaml)

```yaml
id: redis-7.0.15-0001              # patch 唯一标识
title: Adapt io_uring for Kunpeng ARM  # patch 作用(一句话)
owner: twwang@boostkit              # 谁负责(邮箱)
upstream_base:                      # 上游基线(verify.sh 用)
  repo: https://github.com/redis/redis
  version: 7.0.15
  commit: 8f9ea51a8cf4...           # commit SHA
applies_to: 7.0.15                  # 适配的上游版本
upstream_plan:                      # 后续合入upstream计划
  status: submitted                #   pending / validated / submitted / accepted / retired
  pr: https://github.com/redis/redis/pull/TBD  # 可选
  note: 等待上游 review              # 可选,自由文本
```

| 字段 | 必填? | 作用 |
|---|---|---|
| `id` | ✅ | 唯一标识(全仓唯一,跟文件名同名前缀) |
| `title` | ✅ | patch 作用(开发一眼看明白) |
| `owner` | ✅ | 负责人(邮箱) |
| `upstream_base.repo` | ✅ | 上游仓库(verify.sh 拉此仓库) |
| `upstream_base.version` | ✅ | 适配的上游版本 |
| `upstream_base.commit` | ✅ | 适配的 commit SHA(verify.sh checkout 这个) |
| `applies_to` | ✅ | 适配版本(字符串) |
| `upstream_plan.status` | ✅ | 4 状态之一(下表) |
| `upstream_plan.pr` | ⬜ | 已发上游 PR 时的链接 |
| `upstream_plan.note` | ⬜ | 自由文本说明 |

**4 状态机** (从原 7 状态机砍):

```
pending  →  validated  →  submitted  →  accepted  →  retired
            (清理)
```

| 状态 | 含义 | 何时改 |
|---|---|---|
| `pending` | patch 刚加入 | 新建 |
| `validated` | verify.sh 干净 apply | `bash tools/lifecycle.sh set <id> validated` |
| `submitted` | 已发上游 PR | `bash tools/lifecycle.sh link <id> <pr-url>` |
| `accepted` | 上游已合入 | `bash tools/lifecycle.sh set <id> accepted` |
| `retired` | 终态(已删文件) | `bash tools/lifecycle.sh retire <id>` |

### 2.2 `series` 文件(每个 versions/<v>/ 下一个)

```
0001-hw-kunpeng-adapt-iouring.patch
0002-perf-kunpeng-adapt-dtoe.patch
0003-perf-jemalloc-arm64-pointer-tag-and-gc.patch
```

决定 apply 顺序,verify.sh 第 2 步校验与 `patches/*.patch` 一致。

> 这个文件概念**来自 quilt**(quilt 的 `patches/series`),quilt 适合**开发中**补丁管理,本仓用**静态** + 简单 bash 校验,不引外部依赖。

### 2.3 `.githooks/pre-push` — 本地 push 钩子

`bash tools/install-hooks.sh` 装上后,每次 `git push` 前自动跑 `verify.sh`。失败则 push 终止。

跳过: `git push --no-verify`

### 2.4 `.github/workflows/ci.yml` — 1 个 CI job

只有 1 个 `verify` job,跑 `bash tools/verify.sh`。PR 触发 / push master 触发 / 手动触发。

---

## 3. 4 个工具使用方法

### 3.1 `verify.sh` — 一键验证(本地 + CI 必跑)

```bash
bash tools/verify.sh
```

检查 3 件事:
1. **仓根干净** — 无 `.patch` / `Dockerfile` / `build.sh` / `src/` / `storage/` 等
2. **series 一致** — `versions/<v>/series` 与 `patches/*.patch` 文件名一致
3. **干净 upstream apply** — 从 metadata 读 `upstream_base.repo + commit`,克隆后逐 patch apply

**退出码**:
- `0` = 全部通过
- `1` = 有 hard error(仓根禁放、series 不一致)

单 patch apply 失败**只警告不阻塞**(网络/版本漂移,owner 自己判断 rebase 或退役)。

### 3.2 `lifecycle.sh` — 状态 + 退役管理

```bash
# 列出所有 patch 状态
bash tools/lifecycle.sh list

# 查看一个 patch 的 metadata
bash tools/lifecycle.sh show redis-7.0.15-0001

# 改状态(自动校验合法转换)
bash tools/lifecycle.sh set redis-7.0.15-0001 validated
bash tools/lifecycle.sh set redis-7.0.15-0001 accepted

# 记录上游 PR(自动改 status=submitted)
bash tools/lifecycle.sh link redis-7.0.15-0001 https://github.com/redis/redis/pull/12345

# 标 rebase 日期
bash tools/lifecycle.sh mark-rebased redis-7.0.15-0001 2026-07-13

# 退役(删 4 处:patches/ + series + metadata/ + 自动 verify)
bash tools/lifecycle.sh retire redis-7.0.15-0001
# 当前状态不是 retired 时,先:
bash tools/lifecycle.sh set redis-7.0.15-0001 retired
bash tools/lifecycle.sh retire redis-7.0.15-0001
```

### 3.3 `rebase.sh` — 上游发新版时升级

```bash
bash tools/rebase.sh 7.0.16
```

**自动做**:
1. 找最新旧版本(`versions/` 字典序最大)
2. 从 metadata 读 `upstream_base.repo`
3. `git ls-remote` 拿新版本 SHA
4. 建 `versions/7.0.16/` 目录
5. 复制所有 patch + metadata,版本号替换
6. 跑 `verify.sh` 验证
7. 标 `validated` + `last_rebased_at: <today>`

### 3.4 `install-hooks.sh` — 装/卸本地钩子

```bash
bash tools/install-hooks.sh          # 装
bash tools/install-hooks.sh --uninstall  # 卸
```

---

## 4. CI 流程

### 4.1 1 个 job

```yaml
verify:
  runs-on: ubuntu-latest
  steps:
    - checkout
    - pip install pyyaml
    - bash tools/verify.sh
```

**总耗时 ~30 秒** (含 clone upstream)。

### 4.2 PR 端到端流程

```
开发者本地
   ↓
[本地] pre-push 钩子 → verify.sh
   ↓ 通过
git push origin feature/<branch>
   ↓
[CI] GitHub Actions verify job → bash tools/verify.sh
   ↓ 绿
开 PR 到 master
   ↓
人工 review + 合并
   ↓
[CI] master push → verify job 验证
   ↓ 绿
合并完成
```

### 4.3 4 步最常见操作

#### A. 新增第 N 个 patch

```bash
# 1. 创建 patch 文件
vim versions/redis-7.0.15/patches/0004-xxx.patch

# 2. 创建 metadata(6 字段)
cat > versions/redis-7.0.15/metadata/0004-xxx.yaml <<EOF
id: redis-7.0.15-0004
title: ...
owner: ...
upstream_base:
  repo: https://github.com/redis/redis
  version: 7.0.15
  commit: <sha>
applies_to: 7.0.15
upstream_plan:
  status: pending
  note: ...
EOF

# 3. 加到 series
echo "0004-xxx.patch" >> versions/redis-7.0.15/series

# 4. 跑 verify
bash tools/verify.sh
```

#### B. 上游发新版本(7.0.15 → 7.0.16)

```bash
bash tools/rebase.sh 7.0.16
git add -A && git commit -m "chore(rebase): upgrade to 7.0.16"
git push
```

#### C. 退役 patch

```bash
bash tools/lifecycle.sh set redis-7.0.15-0001 retired
bash tools/lifecycle.sh retire redis-7.0.15-0001
```

#### D. 改完 push

```bash
git add -A && git commit -m "fix: ..."
git push   # pre-push 钩子自动跑 verify
```

---

## 5. 关于 quilt 的调研结论

> 用户问:quilt 能否使用?

**结论:不适合本场景,继续用 git apply + bash 校验。**

| 维度 | quilt | 当前方案 |
|---|---|---|
| 状态管理 | `.pc/` 目录(per-checkout state) | 无(我们只做静态验证) |
| 外部依赖 | 需 `apt install quilt` | 无 |
| 用例 | **开发中**补丁(创建/编辑/刷新/堆叠) | **静态** patch 验证 |
| 概念兼容性 | — | `series` 文件概念就来自 quilt(quilt 的 `patches/series`) |

**理由**:
- 我们是 patch overlay(静态发布),不是 patch 活跃开发
- `git apply --check` + `git apply` 3 行 bash 即可完成 "按顺序 apply 验证"
- 引 quilt 反而增加 .pc/ 状态管理负担
- `series` 文件我们已经用了 quilt 的心智模型,只是更轻量

**何时考虑切换**:patch 数量超过 20 个,需要堆叠式开发(像 Linux kernel),再考虑用 quilt。

参考: [Quilt Wikipedia](https://en.wikipedia.org/wiki/Quilt_(software))

---

## 6. 关键提示

- **首次参与**:`bash tools/install-hooks.sh` 装本地钩子,然后 `bash tools/lifecycle.sh list` 看现状
- **改完必跑**:`bash tools/verify.sh`
- **改 patch metadata**:6 字段填齐即可,**不要**加额外的 status/risk_level/validation 等字段
- **遇到不懂**:`bash tools/lifecycle.sh show <id>` 看真实 metadata,`docs/` 里没有 reference,直接看代码
