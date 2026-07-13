# Redis 治理后仓库说明

> 本文档用通俗方式介绍 `chaosv598/Redis-mvp-demo` 治理后的目录、文件、脚本和 CI 流水线。
> 读完后,你能知道每个文件干啥、每个脚本怎么用、提一个 PR 要经过哪些检查。

---

## 1. 整体目录结构

治理后的仓库长这样(只列关键项):

```
Redis-mvp-demo/
├── README.md              # 上游产品介绍(给最终用户看,未动)
├── LICENSE.txt            # 上游 BSD 许可
│
├── boostkit.yaml          # ★ 顶层 manifest(告诉治理工具:我是什么仓)
├── OWNERS                 # ★ 治理名单(谁有权合并 PR)
├── .gitignore             # 禁放列表(防 /src/、*.spec 等进仓)
├── .gitee-ci.yml          # 上游原版 CI 模板(已不用,保留仅作历史)
│
├── .github/               # ★ GitHub 平台配置
│   ├── workflows/ci.yml   #    7 个 CI 自动检查
│   └── PULL_REQUEST_TEMPLATE.md
│
├── .githooks/             # ★ 本地 git 钩子
│   └── pre-push           #    push 前自动跑 3 个本地检查
│
├── versions/              # ★ 每个上游版本一个子目录
│   ├── redis-6.0.20/
│   │   ├── series         #   patch 应用顺序
│   │   ├── patches/       #   实际的 .patch 文件
│   │   └── metadata/      #   每个 patch 的元信息
│   └── redis-7.0.15/
│       └── (同上)
│
├── tools/                 # ★ 14 个治理脚本(后文详述)
│
└── docs/                  # 文档
    ├── GOVERNANCE.md      #   本文档
    ├── patch-lifecycle.md #   7 状态机详解
    ├── ci-github-actions.md
    └── zh/、en/           #   上游产品文档(未动)
```

**核心三件套**: `boostkit.yaml` + `versions/` + `tools/`

**对比**:
- 治理前: 4 个 patch 散落仓根,无 metadata,5 步手工操作
- 治理后: 4 个 patch 全在 `versions/<v>/patches/`,带 metadata,1 行命令搞定

---

## 2. 关键文件作用和具体介绍

### 2.1 `boostkit.yaml` — 仓的"自我介绍"

8 个必填字段,告诉治理工具"我是什么仓、补什么 patch、上游是啥、怎么验证":

```yaml
apiVersion: boostkit.io/v1          # schema 版本(固定)
kind: PatchOverlay                  # 资源类型(本仓是 patch overlay,不是 fork)
metadata:
  name: redis                       # 仓名
  owner: sig-multimedia@boostkit    # 治理 SIG 组
upstream:
  url: https://github.com/redis/redis  # 上游仓库
  versions:                         # 适配的上游版本(可多个)
    - version: 7.0.15
      baseline:
        sha: 8f9ea51a8cf4...        # 上游 commit SHA(check-apply 验证基线)
patches:                            # 本仓的 patch 清单
  - id: redis-7.0.15-0001
    file: versions/.../0001-...patch
    metadata: versions/.../0001-...yaml
ci:
  gates:                            # CI 要跑哪些检查
    - name: doctor
      cmd: python tools/doctor.py
      blocking: true
kernelSupport:
  enabled: false                    # 是否启用多内核适配矩阵
```

**一个 `boostkit.yaml` 解决了 3 件事:**
- 32 仓物理形态可以不一样(目录不同),但 schema 一样,工具读 yaml 即可
- 跨仓聚合查询(哪些 patch 已发上游、哪些 stale)有统一入口
- 上游 baseline 强校验(`check-apply.sh` 必读,缺则 CI 报错)

### 2.2 `OWNERS` — 谁有权合并

```yaml
approvers:        # 至少有 2 个(双签,缺一 PR 不能合)
  - huyizhen@boostkit
  - twwang@boostkit
reviewers:        # 5 个(可 review 代码)
  - yinbin@boostkit
  - ...
emergencyContacts: # 紧急联系人(版本发布时联系)
labels:           # 自动打标签
  - sig/multimedia
  - area/patch
```

`approvers` 强制 ≥ 2,`check-owners.py` 校验,CI 必跑。

### 2.3 `versions/<v>/` — 每个上游版本一个目录

```
versions/redis-7.0.15/
├── series                       # patch 应用顺序(每行一个 patch 文件名)
├── patches/0001-...patch        # 实际补丁(标准 unified diff 格式)
├── patches/0002-...patch
├── metadata/0001-...yaml        # 每个 patch 的元信息
└── metadata/0002-...yaml
```

**`series` 文件** 决定 apply 顺序(`check-series.py` 校验与 `patches/` 一致):
```
0001-hw-kunpeng-adapt-iouring.patch
0002-perf-kunpeng-adapt-dtoe.patch
0003-perf-jemalloc-arm64-pointer-tag-and-gc.patch
```

**`metadata/<id>.yaml`** 是每个 patch 的身份证:
```yaml
id: redis-7.0.15-0001
title: Adapt io_uring for Kunpeng ARM
type: hw                  # hw/perf/build/cve/compat/bugfix
status: Validated         # 7 状态之一(后文详述)
risk_level: high
created_at: 2025-11-20
last_rebased_at: 2026-07-10   # 每次 rebase 上游时更新
applies_on_top:               # 显式依赖,被 check-deps 校验
  - redis-7.0.15-0001
upstream:
  status: Submitted-Upstream
  pr: https://github.com/redis/redis/pull/TBD
```

### 2.4 `tools/` — 14 个治理脚本

按"何时用"分 4 类(详细用法见第 3 章):

| 类别 | 脚本 | 何时用 |
|---|---|---|
| **7 必跑 check** | `doctor.py` / `lint.py` / `check-series.py` / `check-deps.py` / `check-owners.py` / `check-apply.sh` / `check-tag.sh` | 改完任何东西后 / 每次 push |
| **4 操作类** | `lifecycle.py` / `rebase.sh` / `retire.sh` / `status-report.sh` | 状态变化 / 上游发版 / 退役 / 月度 review |
| **2 一次性** | `migrate-mode-d.sh` / `release.sh` | 新仓接入 / 月度发版 |
| **1 钩子安装** | `install-hooks.sh` | 装本地 pre-push 检查 |

### 2.5 `.github/workflows/ci.yml` — GitHub Actions 流水线

7 个自动检查 job,详见第 4 章。

### 2.6 `.githooks/pre-push` — 本地 pre-push 钩子

`bash tools/install-hooks.sh` 装上后,每次 `git push` 前会自动跑 `check-series` / `check-deps` / `doctor` 三个 check,失败则阻止 push。

跳过:`git push --no-verify`

---

## 3. 脚本使用方法

### 3.1 7 必跑 check(本地 + CI 通用)

```bash
# 7 铁律自检(必跑,5 秒)
python3 tools/doctor.py

# boostkit.yaml schema 校验(2 秒)
python3 tools/lint.py boostkit.yaml

# series vs patches/ 一致性(2 秒)
python3 tools/check-series.py

# metadata 的 applies_on_top 依赖校验(2 秒)
python3 tools/check-deps.py

# OWNERS 双签校验(< 1 秒)
python3 tools/check-owners.py OWNERS

# 干净 upstream apply 验证(60-120 秒,网络依赖)
bash tools/check-apply.sh

# tag 命名规范(1 秒)
bash tools/check-tag.sh
```

**一次跑全部(模拟 CI)**:
```bash
for t in doctor.py lint.py check-series.py check-deps.py check-owners.py; do
    python3 tools/$t
done
bash tools/check-apply.sh
bash tools/check-tag.sh
```

### 3.2 4 操作类

#### `lifecycle.py` — 改 patch 状态

```bash
# 看所有 patch 当前状态
python3 tools/lifecycle.py status

# 改状态(自动校验合法转换)
python3 tools/lifecycle.py redis-7.0.15-0001 Submitted-Upstream
python3 tools/lifecycle.py redis-7.0.15-0001 Upstream-Accepted

# 记录上游 PR(自动改状态为 Submitted-Upstream)
python3 tools/lifecycle.py redis-7.0.15-0001 link-upstream-pr https://github.com/redis/redis/pull/12345

# 标 rebase 时间
python3 tools/lifecycle.py redis-7.0.15-0001 mark-rebased 2026-07-13
```

7 状态机:

```
New  →  Validated  →  Submitted-Upstream  →  Upstream-Accepted
                       ↓                     ↓
                   Downstream-Only  →  Deprecated  →  Removed
```

#### `rebase.sh` — 上游发新版时升级

```bash
bash tools/rebase.sh 7.0.16
# 自动:拉上游 SHA / 建 versions/7.0.16/ / 复制 patch / 跑 check-apply / 标 Validated
# 失败的 patch 留 New,事后人工事后修
```

#### `retire.sh` — 退役一个 patch

```bash
# 先改状态
python3 tools/lifecycle.py redis-7.0.15-0001 Deprecated
# 再退役(从 4 处同步删:patches/ + series + metadata/ + boostkit.yaml)
bash tools/retire.sh redis-7.0.15-0001
```

#### `status-report.sh` — 月度健康看板

```bash
bash tools/status-report.sh
# 输出:patch id / status / last_rebased / days_since / upstream / risk
# 高亮 > 180 天未 rebase 的 patch
```

### 3.3 2 一次性 / 月度

```bash
# 新仓接入:把散落仓升级为标准结构
bash tools/migrate-mode-d.sh <upstream-url> <version>

# 月度发版
bash tools/release.sh Redis 7.0.15 bk-26.1.0
```

### 3.4 1 钩子安装

```bash
# 装
bash tools/install-hooks.sh
# 卸
bash tools/install-hooks.sh --uninstall
```

---

## 4. 后续 CI 流程

### 4.1 7 个 GitHub Actions job(全跑在 PR 触发时)

| # | Job | 作用 | 阻塞? | 耗时 |
|---|---|---|---|---|
| 1 | `doctor` | 7 铁律自检 | ✅ | 9s |
| 2 | `lint` | boostkit.yaml schema | ✅ | 6s |
| 3 | `check-series` | series 一致性 | ✅ | 6s |
| 4 | `check-deps` | metadata 依赖 | ✅ | 5s |
| 5 | `check-owners` | OWNERS ≥ 2 | ✅ | 6s |
| 6 | `check-apply` | 干净 upstream apply | ⚠️ 网络失败不阻塞 | 5s |
| 7 | `check-tag` | tag 命名规范 | ⚠️ 软警告 | 6s |

**总耗时约 18 秒**(并发跑),PR 提交后 30 秒内出结果。

### 4.2 完整 PR 流程(从开发到合并)

```
1. 开发者 fork 仓
   ↓
2. 改 patch / metadata / boostkit.yaml
   ↓
3. 本地跑 7 个 check
   ↓
4. [自动] pre-push 钩子跑 3 个本地 check(doctor + check-series + check-deps)
   ↓ 通过
5. git push origin feature/<branch>
   ↓
6. [自动] GitHub Actions 跑 7 个 job(全部 < 30s 出结果)
   ↓ 全部绿
7. 开 PR 到 master
   ↓
8. OWNERS 中 ≥ 2 个 approver 手动 review + 合并
   ↓
9. [自动] merge 后 master 触发 7 个 job 验证
   ↓ 全绿
10. 合并完成
```

### 4.3 4 步最常见操作

#### A. 新增第 N 个 patch

```bash
# 1. 创建 patch 文件
vim versions/redis-7.0.15/patches/0004-xxx.patch

# 2. 创建 metadata
cat > versions/redis-7.0.15/metadata/0004-xxx.yaml <<EOF
id: redis-7.0.15-0004
title: ...
type: perf
status: New
applies_on_top: [redis-7.0.15-0001, redis-7.0.15-0002]
upstream:
  status: Not-Submitted
...
EOF

# 3. 加到 series
echo "0004-xxx.patch" >> versions/redis-7.0.15/series

# 4. 加到 boostkit.yaml
# (在 patches[] 加新条目)

# 5. push
git add -A && git commit -m "feat: add 0004 patch"
git push
```

#### B. 上游发新版本(7.0.15 → 7.0.16)

```bash
bash tools/rebase.sh 7.0.16
git add -A && git commit -m "chore(rebase): upgrade to 7.0.16"
git push
```

#### C. 某个 patch 上游已合入

```bash
python3 tools/lifecycle.py redis-7.0.15-0001 Upstream-Accepted
# 手动填 metadata.upstream.upstream_commit
python3 tools/lifecycle.py redis-7.0.15-0001 Deprecated
bash tools/retire.sh redis-7.0.15-0001
```

#### D. 月度治理 review

```bash
bash tools/status-report.sh
# 看哪些 patch 超过 180 天没 rebase
# 决定 rebase / deprecate
```

### 4.4 失败处理(常见 4 种)

| 报错 | 原因 | 修复 |
|---|---|---|
| `PATCH-IN-ROOT` | 仓根有 .patch 文件 | 移到 `versions/<v>/patches/` |
| `SERIES-MISMATCH` | series 与 patches/ 不一致 | 改 series 加/减/改名字 |
| `BOOSTKIT-MISSING-FIELD` | boostkit.yaml 缺字段 | 补 8 必填 |
| `OWNERS approvers: 1` | OWNERS 双签不够 | 在 `approvers:` 段加邮箱 |
| `check-apply FAIL <patch>` | patch 与上游 baseline 不匹配 | 等下次 rebase |

---

## 5. 关键提示

- **首次参与**:`bash tools/install-hooks.sh` 装本地钩子,然后 `bash tools/status-report.sh` 看现状
- **改完必跑**:`python3 tools/doctor.py`(最严格)
- **加新工具**:在 `tools/` 加 .py/.sh + 在 `boostkit.yaml#ci.gates` 加条目 + 在 `.github/workflows/ci.yml` 加 job + 提 PR
- **遇到不懂**:`docs/patch-lifecycle.md`(状态机)、`docs/ci-github-actions.md`(CI 细节)
