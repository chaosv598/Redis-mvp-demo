# Redis 治理后仓库说明

> **目的**:让第一次接触本仓的开发者,5 分钟内能上手。
> **本仓**: `chaosv598/Redis-mvp-demo`(按 v5 MVP 简化版治理)
> **核心目标**:**开发者愿意配合** — 1 个工具 + 一版本一 yaml + 1 个 CI job,够用就行。

---

## 0. 30 秒速读

| 维度 | 数值 |
|---|---|
| 仓文件总数 | ~10 个(原 ~95 个) |
| 上游适配版本 | 2 个(redis-6.0.20, redis-7.0.15) |
| patch 总数 | 5 个 |
| 工具数 | **1 个**(`verify.sh`) |
| 元数据 | **一版本一 yaml**(`version.yaml`),patches 用数组 |
| CI job | **1 个** |
| 验证耗时 | ~5 秒(本地) / ~30 秒(CI) |
| lifecycle 工具 | **无**(状态写在 metadata 里,git history 即时间线) |
| 退役/归档机制 | **无**(patch 永久保留,不日落) |
| rebase 工具 | **无**(上游发新版由人工拷贝旧版本目录) |
| 构建脚本 | **不文档化**(业务方按需自取) |

**简化历程**:
- 治理前:14 工具 + 7 状态机 + 13 字段 + 7 CI job,**对开发者重**
- 治理前(中间): 6 工具 + 5 状态机 + 6 字段 + 1 CI job
- **治理后(现在): 1 工具 + 3 状态 + 1 yaml/版本 + 1 CI job**

---

## 1. 整体目录结构

```
Redis-mvp-demo/
├── README.md / README_en.md       # 上游产品介绍(给最终用户,未动)
├── LICENSE.txt                    # 上游 BSD 许可
│
├── versions/                      # ★ 每个上游版本一个子目录
│   ├── redis-6.0.20/
│   │   ├── version.yaml          #    唯一元数据(版本字段 + patches[])
│   │   └── patches/0001-...patch #    实际补丁
│   └── redis-7.0.15/
│       └── (同上,4 个 patch)
│
├── tools/
│   └── verify.sh                 # ★ 一键验证(本地 + CI 跑)
│
├── .github/
│   ├── workflows/ci.yml           # ★ 1 个 CI job:verify
│   └── PULL_REQUEST_TEMPLATE.md
│
└── docs/                          # 文档
    ├── GOVERNANCE.md              # 本文档
    ├── patch-lifecycle.md         # 状态机说明
    ├── ci-github-actions.md       # CI 配置
    └── zh/、en/                   # 上游产品文档(未动)
```

- ✅ 现在: **没有 boostkit.yaml**、**没有 OWNERS 文件**、**没有 series 文件**、**没有 lifecycle/rebase/install-hooks/apply-and-build 工具**、**没有 retired/ 子目录**,只保留 `verify.sh` 一个 bash 脚本

---

## 2. 元数据格式(一版本一 yaml)

每个 `versions/<v>/version.yaml` 含 2 块:版本唯一字段 + patches 数组。

### 2.1 版本字段(顶层)

| 字段 | 必填 | 说明 |
|---|---|---|
| `version_id` | ✅ | 唯一标识,跟目录名一致(如 `redis-7.0.15`) |
| `description` | ✅ | 版本作用简介 |
| `owner` | ✅ | 维护人邮箱 |
| `upstream_base.repo` | ✅ | 上游仓库(verify.sh 拉此仓库) |
| `upstream_base.version` | ✅ | 上游版本(tag) |
| `upstream_base.commit` | ✅ | 上游 commit SHA(verify.sh checkout 这个) |

### 2.2 patches 数组

`patches[]` 每个元素字段:

| 字段 | 必填 | 枚举/格式 | 说明 |
|---|---|---|---|
| `name` | ✅ | 字符串 | 文件名前缀(如 `0001-hw-kunpeng-adapt-iouring`) |
| `title` | ✅ | 字符串 | patch 一句话作用 |
| `owner` | ✅ | 邮箱 | 该 patch 负责人 |
| `type` | ✅ | `ecological` / `project` | 生态型(需合入上游) / 项目型(本仓独享) |
| `status` | ✅ | `pending` / `submitted` / `accepted` | 待合入 / 已发 PR / 已合入或本仓落地 |
| `pr` | ⬜ | URL | type=ecological 且 status=submitted 时填 |
| `note` | ⬜ | 文本 | 自由说明 |
| `dependence` | ⬜ | 数组 | 依赖的其他 patch name(verify.sh 按数组顺序 apply,dependence 仅作提示) |

### 2.3 3 状态机

```
pending  →  submitted  →  accepted
(刚加入)   (已发 PR)    (上游合入 / 项目型落地)
```

| 状态 | 含义 | 何时改 |
|---|---|---|
| `pending` | patch 已加入但尚未发 PR | 新建时默认 |
| `submitted` | 已发上游 PR(type=ecological 时有意义) | PR URL 写到 `pr` 字段 |
| `accepted` | 上游 merge / 项目型已在本仓落地 | 直接在 yaml 里改 `status` |

> 状态变更**直接改 yaml 字段**即可,**没有专门的 lifecycle 工具**。`git log` 即完整时间线。

### 2.4 apply 顺序

**`patches[]` 数组顺序 = apply 顺序**。`dependence` 字段是提示性文档,verify.sh 不做拓扑校验。

### 2.5 实际样例(`versions/redis-7.0.15/version.yaml`)

```yaml
version_id: redis-7.0.15
description: Redis 7.0.15 patch overlay (BoostKit)
owner: chaosv598@boostkit
upstream_base:
  repo: https://github.com/redis/redis
  version: 7.0.15
  commit: 8f9ea51a8cf42ac80c0e50141462ca2c03d8aa1d

patches:
  - name: 0001-hw-kunpeng-adapt-iouring
    title: Adapt io_uring for Kunpeng ARM
    owner: twwang@boostkit
    type: ecological
    status: submitted
    pr: https://github.com/redis/redis/pull/TBD
    note: Submitted upstream, awaiting review
    dependence: []
  - name: 0002-perf-kunpeng-adapt-dtoe
    title: Enable dtoe (DMA-to-engine) network optimization on Kunpeng
    owner: twwang@boostkit
    type: project
    status: accepted
    note: Kunpeng-specific HW feature, will keep downstream-only
    dependence: []
  # ... 0003, 0004 同上
```

---

## 3. `verify.sh` —— 唯一工具

```bash
bash tools/verify.sh
```

检查 3 件事:

1. **仓根干净** — 无 `.patch` / `Dockerfile` / `build.sh` / `src/` / `storage/` 等
2. **version.yaml 一致** — `patches[]` 数组声明的 `.patch` 文件与 `patches/` 目录实际文件一一对应(顺序由数组决定)
3. **字段合法** — 顶层字段 + patches[] 元素字段、枚举(type/status)合法
4. **干净 upstream apply** — 从 version.yaml 读 `upstream_base.repo + commit`,克隆后按数组顺序逐 patch apply

**退出码**:
- `0` = 全部通过
- `1` = 有 hard error(仓根禁放、字段缺失、enum 非法、apply 元数据 vs 目录不一致)

单 patch apply 失败**只警告不阻塞**(网络/版本漂移,owner 自己判断)。

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

**总耗时 ~30 秒**(含 clone upstream)。

### 4.2 PR 端到端流程

```
开发者本地
   ↓
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

> 简化点:不再有 pre-push 钩子(没有 .githooks/pre-push,也不再有 install-hooks.sh)。开发者 push 前自己跑 `bash tools/verify.sh`。

---

## 5. 4 步最常见操作

### A. 新增第 N 个 patch

```bash
# 1. 创建 patch 文件
vim versions/redis-7.0.15/patches/0005-xxx.patch

# 2. 在 version.yaml 的 patches[] 数组末尾追加一项
$EDITOR versions/redis-7.0.15/version.yaml

# 3. 跑 verify
bash tools/verify.sh

# 4. 提交
git add -A && git commit -m "feat(7.0.15): add xxx patch"
git push
```

### B. 改 patch 状态(从 pending 到 submitted)

```bash
# 直接编辑 yaml,把 status 改成 submitted,加上 pr URL
$EDITOR versions/redis-7.0.15/version.yaml
# - status: pending
# + status: submitted
# + pr: https://github.com/redis/redis/pull/12345

bash tools/verify.sh
git add -A && git commit -m "feat(0001): submit upstream PR"
git push
```

### C. 改完 push

```bash
bash tools/verify.sh   # 必跑,本地兜底
git add -A && git commit -m "fix: ..."
git push
```

### D. 上游发新版本(7.0.15 → 7.0.16)

```bash
# 手工复制目录结构(不再有 rebase.sh)
mkdir -p versions/redis-7.0.16/patches
cp versions/redis-7.0.15/version.yaml versions/redis-7.0.16/version.yaml
cp versions/redis-7.0.15/patches/*.patch versions/redis-7.0.16/patches/

# 更新 version.yaml:version_id / description / upstream_base.version / upstream_base.commit
$EDITOR versions/redis-7.0.16/version.yaml

# 更新所有 patch 的 upstream_base 字段(因为现在只有一个版本字段)
# 实际上每个 patch 不再单独维护 upstream_base,只共用版本顶层字段

# 跑 verify
bash tools/verify.sh

git add -A && git commit -m "chore(rebase): upgrade to 7.0.16"
git push
```

---

## 6. 关键提示

- **首次参与**:`bash tools/verify.sh` 看仓健康度,然后 `cat versions/*/version.yaml` 看 metadata
- **改完必跑**:`bash tools/verify.sh`
- **改 patch metadata**:在 `version.yaml` 的 `patches[]` 数组里编辑对应项
- **状态变更**:直接改 yaml 的 `status` 字段即可,git commit message 说明原因
- **遇到不懂**:直接看 `versions/<v>/version.yaml` 的实际内容,无需先查文档
