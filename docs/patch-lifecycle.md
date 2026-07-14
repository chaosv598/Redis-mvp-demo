# Patch 生命周期 & 元数据格式

> 配套工具:`bash tools/verify.sh`(全仓唯一工具)
> 上游:`chaosv598/Redis-mvp-demo` · 最后更新 2026-07-14
> 本文档版本 = v5 MVP **simplify-v3 落地版**(1 工具 + 3 状态 + 一版本一 yaml)

---

## 0. 30 秒速读

| 维度 | 数值 |
|---|---|
| 工具数 | **1** 个(`verify.sh`) |
| 状态数 | **3** 个(pending / submitted / accepted) |
| 元数据 | **一版本一 yaml**(`version.yaml`),patches 用数组 |
| patch 字段 | **8** 个(name / title / owner / type / status / pr / note / dependence) |
| CI job | **1** 个(verify) |
| 退役机制 | **无** |
| rebase 工具 | **无**(人工 cp 目录) |
| lifecycle 工具 | **无**(状态直接改 yaml 字段,git history 即时间线) |

---

## 1. 3 状态机

每个 patch 在 `version.yaml` 的 `patches[i].status` 字段标识当前状态。

```
                 ┌─────────┐
                 │ pending │ patch 文件已加入
                 └────┬────┘
            发上游 PR │
                      ▼
                 ┌──────────┐
                 │submitted │(type=project 时直接跳到 accepted)
                 └────┬─────┘
              上游 merge │
                      ▼
                 ┌──────────┐
                 │ accepted │ 终态(本仓永久保留)
                 └──────────┘
```

### 1.1 状态机合法转换

| 当前状态 | 合法下一状态 | 触发动作 |
|---|---|---|
| `pending` | `submitted` | 发上游 PR,把 `pr` URL 写到 yaml |
| `pending` | `accepted` | type=project 直接在本仓落地 |
| `submitted` | `accepted` | 上游 merge |
| `submitted` | `pending` | PR 被拒/长期不响应,撤回 |
| `accepted` | (终态) | 不再变;patch 永久保留 |

> **没有 retired 状态**。所有 patch 永久保留在仓里,不存在日落/sunset 工作流。

### 1.2 type 字段的作用

`type` 区分 patch 性质,跟 `status` 配合使用:

| type | 含义 | 典型 status 路径 |
|---|---|---|
| `ecological` | 修复/特性会上游合入 | pending → submitted → accepted |
| `project` | 本仓独享(平台特性、业务定制) | pending → accepted(无需 submitted) |

**hard rule**:`type=project` 时**不允许** `status=rejected`(本仓 reject 项目型 patch 没语义)。本设计下没有 rejected 状态;若上游拒绝 ecological patch,把 status 改回 `pending` 即可。

---

## 2. 一版本一 yaml 元数据格式

`versions/<v>/version.yaml` 含 2 块:**版本字段(顶层)** + **patches 数组**。

### 2.1 版本字段(顶层)

| 字段 | 必填 | 说明 |
|---|---|---|
| `version_id` | ✅ | 唯一标识,跟目录名一致 |
| `description` | ✅ | 版本作用简介 |
| `owner` | ✅ | 版本维护人 |
| `upstream_base.repo` | ✅ | 上游仓库(verify.sh 拉此仓库) |
| `upstream_base.version` | ✅ | 上游版本 tag |
| `upstream_base.commit` | ✅ | 上游 commit SHA(verify.sh checkout 这个) |

### 2.2 patches 数组

`patches[]` 每个元素:

| 字段 | 必填 | 枚举 | 说明 |
|---|---|---|---|
| `name` | ✅ | 字符串 | 文件名前缀(如 `0001-hw-kunpeng-adapt-iouring`) |
| `title` | ✅ | 字符串 | patch 一句话作用 |
| `owner` | ✅ | 邮箱 | 该 patch 负责人 |
| `type` | ✅ | `ecological` / `project` | 生态型(需合入上游)/项目型(本仓独享) |
| `status` | ✅ | `pending` / `submitted` / `accepted` | 待合入 / 已发 PR / 已合入 |
| `pr` | ⬜ | URL | type=ecological 且 status=submitted 时填 |
| `note` | ⬜ | 文本 | 自由说明 |
| `dependence` | ⬜ | 数组 | 依赖的 patch name(verify.sh 按数组顺序 apply,dependence 仅作文档提示) |

### 2.3 完整样例

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
    title: Enable dtoe network optimization on Kunpeng
    owner: twwang@boostkit
    type: project
    status: accepted
    note: Kunpeng-specific HW feature, will keep downstream-only
    dependence: []
```

---

## 3. `verify.sh` 用法

### 3.1 命令

```bash
bash tools/verify.sh
```

### 3.2 检查 4 件事

1. **仓根干净**:无 `.patch` / `Dockerfile` / `build.sh` / `src/` / `storage/` 等
2. **version.yaml 字段合法**:顶层字段、enum 校验
3. **patches[] 与 patches/ 一致**:数组声明的文件名 = 目录实际文件
4. **干净 upstream apply**:从 `upstream_base.repo+commit` 拉代码,按数组顺序逐 patch apply

### 3.3 退出码

- `0`:全部通过(可能有 warning,如某 patch apply 失败因为 baseline 不匹配)
- `1`:有 hard error(仓根污染、字段缺失、enum 非法、apply 元数据 vs 目录不一致)

### 3.4 使用时机

- 改完 version.yaml / patches/ 后必跑
- PR 提交前
- CI 中(`.github/workflows/ci.yml` 唯一 job)

---

## 4. 4 个常见场景

### 场景 A:新增第 N 个 patch

```bash
# 1. 创建 patch 文件
$EDITOR versions/redis-7.0.15/patches/0005-my-fix.patch

# 2. 在 version.yaml 的 patches[] 末尾追加一项
$EDITOR versions/redis-7.0.15/version.yaml

# 3. 验证
bash tools/verify.sh

# 4. 提交
git add -A && git commit -m "feat(7.0.15): add my-fix patch"
git push
```

### 场景 B:patch 状态从 pending → submitted

```bash
# 1. 改 yaml:status=submitted,加 pr URL
$EDITOR versions/redis-7.0.15/version.yaml
# - status: pending
# + status: submitted
# + pr: https://github.com/redis/redis/pull/12345

# 2. 验证 + 提交
bash tools/verify.sh
git add -A && git commit -m "feat(0001): submit upstream PR"
git push
```

### 场景 C:改完 push(常规 fix)

```bash
bash tools/verify.sh    # 本地必跑
git add -A && git commit -m "fix: ..."
git push
```

---

## 5. 历次治理精简记录

| 时间 | 变更 | 工具数 | 状态机 | 元数据粒度 | CI job |
|---|---|---|---|---|---|
| 2026-06-XX | 治理前 | 0 | 无 | 无 | 无 |
| 2026-07-08 | v5 MVP 初版 | 14 | 7 | 一 patch 一 yaml | 7 |
| 2026-07-10 | simplify-v1 | 6 | 5 | 一 patch 一 yaml | 1 |
| 2026-07-13 | simplify-v2 | 4 | 5 | 一 patch 一 yaml | 1 |
| 2026-07-14 | simplify-v3 | **1** | **3** | **一版本一 yaml** | 1 |

simplify-v3 关键变化:
- 一版本一 yaml(取代一 patch 一 yaml + series 文件)
- 状态机从 5 状态(pending/validated/submitted/accepted/retired)简化为 3 状态(pending/submitted/accepted)
- 工具从 4 个简化为 1 个,只保留 verify.sh
- 删除 lifecycle.sh、rebase.sh、apply-and-build.sh、install-hooks.sh
- 删除 retired/ 归档机制,patch 永久保留
- 删除 pre-push 钩子(.githooks/pre-push)
