# BoostKit/Redis 治理后仓库说明

> **仓库**: [chaosv598/Redis-mvp-demo](https://github.com/chaosv598/Redis-mvp-demo)
> **治理框架**: BoostKit Patch 治理 v5 MVP(基于 V3/V4 102 KB 规范瘦身至 40 KB 4 周落地版)
> **上游**: [boostkit/Redis](https://gitcode.com/boostkit/Redis) → [redis/redis](https://github.com/redis/redis)
> **版本**: v1.0(治理演示范本,2026-07-13)
> **维护者**: chaosv598@users.noreply.github.com

---

## 0. 30 秒速读

| 维度 | 数值 |
|---|---|
| 仓文件总数 | 99 个(治理迁移前 ~50) |
| 仓根禁放文件 | 0 ✓ |
| 上游适配版本 | 2 个(redis-6.0.20, redis-7.0.15) |
| patch 总数 | 4 个(全在 `versions/<v>/patches/`) |
| 治理脚本 | **14 个**(2 Python lint + 5 Python check + 7 Bash 工具) |
| CI 必跑 job | **7 个**(平均 6 秒) |
| 文档章节 | 4 篇(本篇 + lifecycle + ci-github-actions + 产品文档) |
| PR 模板 | 6 段(仓/背景/内容/验证/删除条件) |
| v5 验收指标 | 9/10 ✓ |

**本仓是 v5 MVP 4 周落地版的样板仓**,展示:
- patch overlay 的标准结构如何从散落仓升级而来
- 14 个治理脚本如何支撑端到端 PR 流程
- 7 个 GitHub Actions job 如何完整替代 5 个 GitCode CI stage

---

## 1. 这是什么 / 为什么有这个仓

### 1.1 产品定位

`boostkit/Redis` 是给上游 [redis/redis](https://github.com/redis/redis) 的 **patch overlay 仓库**(不是 fork 源码,而是装在 Redis 之上的增强补丁集)。核心能力是 **KRAIO(Kunpeng Redis Asynchronous I/O)** 方案:

- **网络异步优化**:把 Redis 的网络 I/O 异步化、批量化
- **sockmap 优化**:内核态 socket mapping,减少上下文切换
- **目标硬件**:Kunpeng ARM(aarch64)
- **目标 OS**:openEuler 22.03 LTS SP4
- **目标 Redis 版本**:6.0.20 + 7.0.15(2 个 LTS 分支并行)

### 1.2 为什么需要治理

**治理前**(2026-07-09 调研数据):
- 4 个 patch 散落仓根
- 无元数据(没法聚合查询"哪些 patch 已发上游、哪些 patch 阻塞")
- 11 个手工 tag(其中 1 个误打,数字 `1` 没法解析)
- 3 个分支但没人知道哪条是 release
- 5 个 PR review 拥塞,owner 不回复

**治理后**(本仓):
- patch 全部进 `versions/<v>/patches/` 标准化目录
- 4 个 patch 各自有完整 metadata(13 字段,3 个状态信息字段 V5 强校验)
- 7 状态机自动跟踪 lifecycle
- 14 个治理脚本 1 行命令代替 5 步手工
- CI 7 步必跑,PR 提交后 18 秒内出结果

---

## 2. 治理框架(v5 MVP 4 周落地版)

### 2.1 演进史

| 版本 | 大小 | 状态机 | 门禁 | 必填字段 | 落地周期 | 适用 |
|---|---|---|---|---|---|---|
| V1 (DeepSeek) | 50 KB | 7 状态 | 12 门禁 | 10 字段 | 12 周 | 单仓 |
| V2 (V1 优化) | 58 KB | 7 状态 | 12 门禁 | 10 字段 | 12 月 | 94 仓 |
| V3/V4 (完整规范) | 102 KB | 11 状态 + FROZEN | 18 门禁 | 13 字段 | 12 月 4 阶段 5 FTE | 32 仓 + 详尽 reference |
| **v5 MVP** | **40 KB** | **7 状态** | **8 必跑 + 5 选跑** | **8 字段** | **4 周(20 工作日)** | **32 仓 + 实操剧本** |

**v5 目标**:把"小仓、过设计"的 V3/V4 砍到 2.5 FTE × 4 周能落地的程度。本仓就是 W1-W2 阶段的样板。

### 2.2 7 条铁律(替代 V4 的 18 门禁)

每条都有工具钩子,**不需要人工理解**:

| # | 铁律 | 工具钩子 | CI 跑 |
|---|---|---|---|
| 1 | 仓根不放 patch,只放 OWNERS/boostkit.yaml/README | `doctor.py` + `.gitignore` | ✓ |
| 2 | `boostkit.yaml` 必填 8 字段,缺一 PR fail | `lint.py --strict` | ✓ |
| 3 | `OWNERS` ≥ 2 显式 approvers,平台强校验 | `check-owners.py` | ✓ |
| 4 | patch 必进 `versions/<v>/patches/`,不在仓根、不散落 | `doctor.py` | ✓ |
| 5 | patch 顺序由 `series` 文件决定 | `check-series.py` + `check-deps.py` | ✓ |
| 6 | PR 目标 = `master`,禁止直接 push | GitHub branch protection(可选) | 平台 |
| 7 | 所有 CI 必跑 4 步:yaml-lint → apply → build → owners | `boostkit-v5-ci.yml`(7 job) | ✓ |

---

## 3. 仓库结构

```text
chaosv598/Redis-mvp-demo/
├── README.md / README_en.md     # 上游产品介绍(未动)
├── LICENSE.txt                  # 上游 BSD 副件
│
├── boostkit.yaml                # ★ 顶层 manifest(8 必填字段,2 upstream versions, 4 patch entries)
├── OWNERS                       # ★ 2 approver + 3 reviewer + 2 紧急联系人 + 3 label
├── .gitignore                   # ★ 屏蔽 /src/、*.spec、*.rpm 等禁放项
├── .gitee-ci.yml                # 上游原版 CI 模板(已弃用,迁移到 .github/workflows/)
│
├── .github/                     # ★ GitHub 平台配置
│   ├── workflows/ci.yml         #    7 个 GitHub Actions job
│   └── PULL_REQUEST_TEMPLATE.md #    6 段 PR 模板
│
├── .githooks/                   # ★ 本地 git 钩子
│   └── pre-push                 #    push 前 3 个 check
│
├── versions/                    # ★ 每个上游版本一个目录
│   ├── redis-6.0.20/
│   │   ├── series               # 1 patch 字典序
│   │   ├── patches/0001-hw-kunpeng-adapt-iouring-on-6.0.15-6.0.20.patch
│   │   └── metadata/0001-hw-kunpeng-adapt-iouring-on-6.0.15-6.0.20.yaml
│   └── redis-7.0.15/
│       ├── series               # 3 patch 字典序
│       ├── patches/
│       │   ├── 0001-hw-kunpeng-adapt-iouring.patch
│       │   ├── 0002-perf-kunpeng-adapt-dtoe.patch
│       │   └── 0003-perf-jemalloc-arm64-pointer-tag-and-gc.patch
│       └── metadata/0001-...yaml × 3
│
├── tools/                       # ★ 14 个治理脚本
│   ├── 7 必跑 check(本地+CI):
│   │   ├── doctor.py            # 7 铁律自检
│   │   ├── lint.py              # boostkit.yaml 8 必填字段
│   │   ├── check-series.py      # series vs patches/ 一致性
│   │   ├── check-deps.py        # ★ applies_on_top 与 series 顺序(本仓新增)
│   │   ├── check-owners.py      # OWNERS ≥ 2
│   │   ├── check-apply.sh       # 从干净 upstream 重放 patch 系列
│   │   └── check-tag.sh         # tag 命名规范
│   ├── 4 操作类(本仓新增):
│   │   ├── lifecycle.py         # ★ 7 状态机 CLI
│   │   ├── rebase.sh            # ★ 上游版本升级剧本
│   │   ├── retire.sh            # ★ patch 退役剧本
│   │   └── status-report.sh     # ★ 健康看板
│   ├── 1 仓接入:
│   │   └── migrate-mode-d.sh    # 一次性:散落仓 → 标准仓
│   ├── 1 发版:
│   │   └── release.sh           # 一键打 release tag + freeze
│   └── 1 钩子安装:
│       └── install-hooks.sh     # ★ 装/卸 .githooks/
│
├── docs/                        # 产品文档(4 篇)
│   ├── GOVERNANCE.md            #    ★ 本文档(治理总览)
│   ├── patch-lifecycle.md       #    ★ 7 状态机 + 4 场景剧本
│   ├── ci-github-actions.md     #    GitHub Actions 翻译细节
│   ├── LICENSE                  # 文档 CC-BY 4.0
│   ├── en/                      # 上游英文产品文档
│   └── zh/                      # 上游中文产品文档
│
└── .migration-backup/           # 一次性迁移产物(已 .gitignore,不入仓)
```

---

## 4. 工具栈(14 个脚本,2.5 FTE 半天)

### 4.1 7 必跑 check(本地 + CI 共用)

| 工具 | 作用 | 用法 | 输出 |
|---|---|---|---|
| `tools/doctor.py` | 7 铁律自检 | `python tools/doctor.py` | 0 hard errors / warns |
| `tools/lint.py` | boostkit.yaml schema | `python tools/lint.py boostkit.yaml` | schema OK · N patches |
| `tools/check-series.py` | series vs patches/ | `python tools/check-series.py` | ✓ 一致 / ✗ 不一致 |
| `tools/check-deps.py` | applies_on_top ↔ series 顺序 | `python tools/check-deps.py` | ✓ 3 依赖 / ✗ 循环 |
| `tools/check-owners.py` | OWNERS ≥ 2 | `python tools/check-owners.py OWNERS` | approvers: 2 |
| `tools/check-apply.sh` | 干净 upstream 重放 | `bash tools/check-apply.sh` | ✓ 4/4 apply 干净 |
| `tools/check-tag.sh` | tag 命名规范 | `bash tools/check-tag.sh` | ⚠ 推荐打 upstream-* tag |

### 4.2 4 操作类(本仓新增,补 v5 4 大 gap)

| 工具 | 作用 | 用法 | 频率 |
|---|---|---|---|
| `tools/lifecycle.py` | 7 状态机 CLI | `python tools/lifecycle.py <id> <new-status>` | 每次状态变化 |
| `tools/rebase.sh` | 上游版本升级剧本 | `bash tools/rebase.sh 7.0.16` | 上游发新版 |
| `tools/retire.sh` | patch 退役剧本 | `bash tools/retire.sh <id>` | Deprecated 后 |
| `tools/status-report.sh` | 健康看板 | `bash tools/status-report.sh` | 月度 review |

### 4.3 2 一次性 / 月度

| 工具 | 作用 | 用法 |
|---|---|---|
| `tools/migrate-mode-d.sh` | 散落仓一次性升级标准仓 | `bash tools/migrate-mode-d.sh <url> <ver>` |
| `tools/release.sh` | 一键发版 | `bash tools/release.sh Redis 7.0.15 bk-26.1.0` |

### 4.4 1 钩子安装

| 工具 | 作用 | 用法 |
|---|---|---|
| `tools/install-hooks.sh` | 装/卸 git hooks | `bash tools/install-hooks.sh` / `--uninstall` |

---

## 5. CI/CD 流水线(7 个 GitHub Actions job)

### 5.1 触发条件

| 事件 | 行为 |
|---|---|
| `push` to `master` | 跑全部 7 个 job |
| `pull_request` to `master` | 跑全部 7 个 job |
| `workflow_dispatch` | 手动触发 |

### 5.2 7 个 Job 概览

| # | Job | 类型 | 阻塞 | 平均耗时 | 替代 .gitee-ci.yml 的 |
|---|---|---|---|---|---|
| 1 | doctor (7 铁律) | lint | ✅ | 9s | `doctor` |
| 2 | lint (boostkit.yaml) | lint | ✅ | 6s | `lint-yaml` |
| 3 | check-series | lint | ✅ | 6s | `check-series` |
| 4 | check-deps ★新 | lint | ✅ | 5s | (无,本仓新增) |
| 5 | check-owners | owners | ✅ | 6s | `check-owners` |
| 6 | check-apply | apply | ⚠️ continue-on-error | 5s | `check-apply` |
| 7 | check-tag | tag | ⚠️ continue-on-error | 6s | (无,本仓新增) |

**总耗时 ~18 秒**(并发,GitHub Actions ubuntu-latest runner)

### 5.3 翻译表(GitCode → GitHub Actions)

| .gitee-ci.yml 字段 | GitHub Actions 对应 |
|---|---|
| `image: python:3.11` | `actions/setup-python@v5` + `python-version: '3.11'` |
| `if: $CI_PIPELINE_SOURCE == 'merge_request_event'` | `on: pull_request` |
| `allow_failure: true` | `continue-on-error: true` |
| `artifacts.paths: [versions/*/reports/]` | `actions/upload-artifact@v4` + `path: versions/*/reports/` |
| `apk add --no-cache bash git` | (无需,ubuntu-latest 自带) |

详细翻译见 [`docs/ci-github-actions.md`](./ci-github-actions.md)。

### 5.4 端到端 PR 流程

```text
开发者本地
    ↓
[pre-push hook 自动跑 3 个 check]
    ✓ check-series
    ✓ check-deps
    ✓ doctor
    ↓
git push origin <branch>
    ↓
[GitHub Actions 自动跑 7 个 job]
    ✓ doctor / lint / check-series / check-deps / check-owners (硬阻塞)
    ⚠ check-apply / check-tag (软警告,网络/版本)
    ↓
PR 开到 master
    ↓
OWNERS 2 人 approve(GitHub branch protection 可选配)
    ↓
Squash merge
    ↓
[merge 后 push 触发 master 7 job 全跑,确认不退化]
```

详细 PR 模板见 [`.github/PULL_REQUEST_TEMPLATE.md`](../.github/PULL_REQUEST_TEMPLATE.md)。

---

## 6. Patch 生命周期(7 状态 + 完整剧本)

### 6.1 7 状态机

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

### 6.2 4 常见场景剧本

#### 场景 A: 新增第 N 个 patch

```bash
# 1. 创建 patch
vim versions/redis-7.0.15/patches/0004-perf-add-batched-commands.patch

# 2. 创建 metadata(applies_on_top 必须填前面所有 patch id)
cat > versions/redis-7.0.15/metadata/0004-perf-add-batched-commands.yaml <<EOF
id: redis-7.0.15-0004
title: Batched RESP commands optimization
type: perf
status: New
applies_on_top:
  - redis-7.0.15-0001
  - redis-7.0.15-0002
  - redis-7.0.15-0003
upstream:
  status: Not-Submitted
...
EOF

# 3. 加到 series
echo "0004-perf-add-batched-commands.patch" >> versions/redis-7.0.15/series

# 4. 加到 boostkit.yaml patches[]
$EDITOR boostkit.yaml

# 5. pre-push hook 自动跑 3 check
git add -A
git commit -m "feat(7.0.15): add batched commands perf patch"
git push
```

#### 场景 B: 上游 7.0.15 → 7.0.16 升级

```bash
bash tools/rebase.sh 7.0.16
# 自动:拉 SHA / 建目录 / 复制 patch / 跑 check-apply / 标 Validated / 更新 boostkit.yaml
# 失败 patch 保留 New,人工事后修

git add -A
git commit -m "chore(rebase): upgrade to 7.0.16"
git push
```

#### 场景 C: 某个 patch 上游已合入,本仓要退役

```bash
python tools/lifecycle.py redis-7.0.15-0001 Upstream-Accepted
$EDITOR versions/redis-7.0.15/metadata/0001-hw-kunpeng-adapt-iouring.yaml
# 填 metadata.upstream.upstream_commit
python tools/lifecycle.py redis-7.0.15-0001 Deprecated
bash tools/retire.sh redis-7.0.15-0001
# 4 处同步删 + 3 个 check 验证
```

#### 场景 D: 月度治理 review

```bash
bash tools/status-report.sh
# 看 STALE patch(>180 天未 rebase)
python tools/lifecycle.py redis-7.0.15-0003 Deprecated  # 长期不再用
# 或
bash tools/rebase.sh 7.0.16  # 上游有新版,迁移

# 月末发版
bash tools/release.sh Redis 7.0.15 bk-26.1.0
```

详细 7 状态机 + 工具用法见 [`docs/patch-lifecycle.md`](./patch-lifecycle.md)。

---

## 7. 上游协同

### 7.1 当前状态(本仓 4 个 patch)

| Patch | 状态 | last_rebased | 上游 status | 计划 |
|---|---|---|---|---|
| redis-6.0.20-0001 | Validated | 2026-07-10 | Not-Submitted | 长期维护 6.0 LTS |
| redis-7.0.15-0001 | Validated | 2026-07-10 | Submitted-Upstream | 等上游合入 |
| redis-7.0.15-0002 | Downstream-Only | 2026-07-10 | Not-Submitted | Kunpeng 专属,自留 |
| redis-7.0.15-0003 | Downstream-Only | 2026-07-10 | Submitted-Upstream | jemalloc,等上游合入 |

### 7.2 上游 PR 流程

```text
本仓 Validated
    ↓
发上游 PR(github.com/redis/redis)
    ↓
python tools/lifecycle.py <id> link-upstream-pr <url>
   → 自动改 status=Submitted-Upstream + 填 metadata.upstream.pr
    ↓
上游 review(可能几月)
    ↓
  ├── 上游 merge
  │     ↓
  │   python tools/lifecycle.py <id> Upstream-Accepted
  │   填 metadata.upstream.upstream_commit
  │   ↓
  │   等下个 rebase 时自动转 Deprecated
  │   ↓
  │   bash tools/retire.sh <id> 删文件
  │
  └── 上游拒绝 / 长期不响应
        ↓
      python tools/lifecycle.py <id> Downstream-Only
      ↓
      长期维护,等业务变化再 Deprecated
```

---

## 8. 贡献者指南

### 8.1 第一次参与

```bash
# 1. 装 git hooks
bash tools/install-hooks.sh

# 2. 看健康看板
bash tools/status-report.sh

# 3. 跑全部 7 个本地 check(模拟 CI)
for t in doctor.py lint.py check-series.py check-deps.py check-owners.py; do
    python3 tools/$t
done
bash tools/check-apply.sh
bash tools/check-tag.sh
```

### 8.2 修改 patch

```bash
# 改前:看 metadata 状态
python tools/lifecycle.py status

# 改 patch
$EDITOR versions/redis-7.0.15/patches/0001-hw-kunpeng-adapt-iouring.patch

# 跑 check-apply 看是否仍能 apply
bash tools/check-apply.sh

# 改 metadata
$EDITOR versions/redis-7.0.15/metadata/0001-hw-kunpeng-adapt-iouring.yaml

# 提交
git add -A
git commit -m "fix(7.0.15): rebase 0001 on latest upstream"
git push  # pre-push 自动跑 3 check
```

### 8.3 添加新工具

1. 在 `tools/` 下加新文件,加可执行权限
2. 在 `boostkit.yaml#ci.gates` 加新条目
3. 在 `.github/workflows/ci.yml` 加新 job
4. 在 `docs/patch-lifecycle.md` 的工具速查表加一行
5. 提 PR,跑 7 个 job 全绿

### 8.4 提升 OWNERS

```bash
# 加新 approver(从 reviewer 升)
$EDITOR OWNERS
# 在 approvers: 段加邮箱
# 必须保持 ≥ 2
```

---

## 9. 部署与使用

### 9.1 用户场景:使用 KRAIO Redis

参考 [`docs/zh/redis_network_async_optimization_feature_guide.md`](./zh/redis_network_async_optimization_feature_guide.md):

```bash
# 1) 准备 kraio 并安装库文件
cd kraio
make -j4
cp ./libkraio.so /usr/lib64
cp ./include/kraio.h /usr/include

# 2) 合入补丁并编译 Redis
cd /path/to/redis-7.0.15
cp /path/to/Redis/versions/redis-7.0.15/patches/0001-hw-kunpeng-adapt-iouring.patch .
patch -p1 < 0001-hw-kunpeng-adapt-iouring.patch
patch -p1 < 0002-perf-kunpeng-adapt-dtoe.patch
patch -p1 < 0003-perf-jemalloc-arm64-pointer-tag-and-gc.patch
make distclean
make -j
```

### 9.2 仓主场景:维护本仓

```bash
# 每周一看健康看板
bash tools/status-report.sh

# 上游发新版就跑 rebase
bash tools/rebase.sh <new-version>

# 月末发版
bash tools/release.sh Redis 7.0.15 bk-26.1.0
```

---

## 10. 推广指南:从样板仓到 32 仓

### 10.1 推广 3 步

```bash
# 1) 把本仓 tools/ 复制到目标仓(11 个 .py + .sh)
cp -r tools/ /path/to/target-repo/

# 2) 在目标仓跑一次性迁移
cd /path/to/target-repo
bash tools/migrate-mode-d.sh <upstream-url> <version>

# 3) 编辑 OWNERS / boostkit.yaml / 各 metadata,填实际值
# 然后跑
python tools/doctor.py
python tools/check-deps.py
bash tools/check-apply.sh
```

### 10.2 适配差异(各仓可能不同)

| 差异 | 适配方法 |
|---|---|
| OWNERS 没有 ≥ 2 approver | 仓主拉治理小组 2 人,治理小组加邮箱 |
| upstream 不是 git tag 而是 commit SHA | `migrate-mode-d.sh` 已支持 |
| patch 命名不规范 | `migrate-mode-d.sh` 自动重命名 `<NNNN>-<type>-<mod>-<desc>.patch` |
| 多版本并行(本仓 6.0 + 7.0) | 已有 2 个 versions/ 目录,加新版本 `bash tools/rebase.sh 7.0.16` |
| patch 数量 > 10 | check-deps 自动处理,series 仍字典序 |

### 10.3 推广 32 仓的 W3-W4 节奏(v5 §11)

| 周 | 任务 | 仓数 |
|---|---|---|
| W1 (D1-D5) | redis 改造完(本仓) + lz4 改造完 | 2 |
| W2 (D6-D10) | CI 4 步在样板仓跑通 + PR 模板 ≤100 行 + 月度 review 文档化 | 2 |
| W3 (D11-D15) | B 类仓批量改造 | 12 |
| W4 (D16-D20) | B 类剩余 6 仓 + C 类 10 仓 + 月度 release + 看板 | 16 |

**W3-W4 预期**:每仓 1-2 小时,套工具脚本即可,OWNERS 收集是关键阻塞。

---

## 11. 已知限制与未来工作

### 11.1 当前仓的限制

1. **网络层**:check-apply 拉 upstream 用匿名 clone,无 token。如未来要拉私有上游,需 `GH_TOKEN` secret
2. **build 步骤不在本仓 CI**:build 由 Kunpeng ARM jenkins 跑(跨架构),本仓只验 apply 不验编译
3. **多内核适配未启用**:`kernelSupport.enabled: false`,v5 §20 多内核矩阵仅 hyperscan/dpdk/spdk 需要
4. **monorepo 拆分**:本仓只覆盖 redis,其他 31 仓各自有仓,本仓 14 工具可直接复用

### 11.2 未来增强(超出 MVP 范围)

| 增强 | 价值 | 复杂度 |
|---|---|---|
| 仓根 dashboard(Grafana + dependabot) | 高 | 高 |
| `bp` Go 二进制(替代 14 个脚本) | 中(更快但增加二进制依赖) | 高 |
| 自动 upstream PR status 拉取(GraphQL) | 中 | 中 |
| patch diff 工具(对比两个 rebase 之间变化) | 中 | 中 |
| `actions/cache` 缓存 pip / git | 低(本仓 <30s) | 低 |
| policy-bot / dangerjs 强约束 PR 模板 | 低(本仓已规范) | 中 |

### 11.3 v6 候选(基于本仓实战反馈)

- 状态机砍到 5 状态(`Removed` 与 `Deprecated` 合并)
- `applies_on_top` 默认必填(本仓 0003 之前漏填,依赖 check-deps 兜底)
- `bp release` 真正落地(本仓 release.sh 是 bash 模拟)
- patch 数量超 10 时 series 改用 Quilt 系列管理(本仓 4 patch 不需要)

---

## 12. 相关文档

| 文档 | 章节 | 何时读 |
|---|---|---|
| [`docs/GOVERNANCE.md`](./GOVERNANCE.md) | 本文档 | 第一次接触本仓 |
| [`docs/patch-lifecycle.md`](./patch-lifecycle.md) | 7 状态机 + 4 场景剧本 | 改 patch / 状态变化 |
| [`docs/ci-github-actions.md`](./ci-github-actions.md) | GitHub Actions 翻译细节 | 改 CI / debug |
| [`docs/zh/redis_network_async_optimization_feature_guide.md`](./zh/redis_network_async_optimization_feature_guide.md) | KRAIO 网络异步特性 | 用户场景 |
| [`docs/zh/redis_sockmap_optimization_feature_guide.md`](./zh/redis_sockmap_optimization_feature_guide.md) | sockmap 优化特性 | 用户场景 |
| `boostkit.yaml` | 顶层 manifest | 改字段时 |
| `OWNERS` | 治理名单 | 加 approver 时 |
| `.github/workflows/ci.yml` | 7 个 CI job | 加新 check 时 |
| `tools/*.py` / `tools/*.sh` | 14 个治理脚本 | 改工具时 |

---

## 13. 一句话总结

> **本仓是 BoostKit 32 仓 patch overlay 治理 v5 MVP 4 周落地版的样板,展示 14 个工具 + 7 个 CI job + 7 状态机如何把 4 个 patch 的全生命周期从"散落手工"自动化到"PR 即治理"。**

---

**版本**: v1.0(2026-07-13,基于 4 commits / 99 files)
**关联 PR**: #1 (CI 翻译) + #2 (lifecycle tooling)
**关联规范**: BoostKit Patch v5 MVP 4-week plan (§1-§15, 40 KB)
**配套上游**: [boostkit/Redis](https://gitcode.com/boostkit/Redis) | [redis/redis](https://github.com/redis/redis)
