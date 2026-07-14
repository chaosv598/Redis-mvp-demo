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

**4 状态机** 

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

#### C. 退役 patch(默认 archive 到 retired/,可恢复)

```bash
bash tools/lifecycle.sh set redis-7.0.15-0001 retired
bash tools/lifecycle.sh retire redis-7.0.15-0001
# 实际动作(可恢复,非真删):
#   metadata/0001-...yaml         → metadata/retired/0001-...yaml
#   patches/0001-...patch         → patches/retired/0001-...patch
#   series                        删一行
#   yaml 里 status 改成 retired
```

**如果确实要物理删除(不可恢复)**:

```bash
# archive 后,手动 rm
rm versions/redis-7.0.15/metadata/retired/0001-*.yaml
rm versions/redis-7.0.15/patches/retired/0001-*.patch
rmdir versions/redis-7.0.15/metadata/retired 2>/dev/null
rmdir versions/redis-7.0.15/patches/retired 2>/dev/null
```

**想反悔(retire 错了,复活 patch)**:

```bash
bash tools/lifecycle.sh restore redis-7.0.15-0001
# metadata 移回 active,patches 移回 active,series 加回,status 改 validated
```

**想查已退役的 patch**:

```bash
bash tools/lifecycle.sh show redis-7.0.15-0001 --archived
# 默认 show 只查 active;--archived 查 retired/
```

#### D. 改完 push

```bash
git add -A && git commit -m "fix: ..."
git push   # pre-push 钩子自动跑 verify
```

#### E. 上游已合入我的 patch,怎么日落(sunset)?

**触发条件**:metadata.upstream_plan.pr 状态变 merged,或上游 release notes 提到了本仓 patch 的功能。

**完整剧本**:

```bash
# 1. 标 accepted(语义:上游合入了)
bash tools/lifecycle.sh set redis-7.0.15-0001 accepted

# 2. 标 rebase 时间(可选项,记录"我们知道的时刻")
bash tools/lifecycle.sh mark-rebased redis-7.0.15-0001 2026-07-13

# 3. 标 retired(进入待删除状态)
bash tools/lifecycle.sh set redis-7.0.15-0001 retired

# 4. 退役(archive 到 retired/,非真删)
bash tools/lifecycle.sh retire redis-7.0.15-0001
# 实际动作:
#   metadata/0001-...yaml  → metadata/retired/0001-...yaml
#   patches/0001-...patch  → patches/retired/0001-...patch
#   series                 删 0001-...patch 一行
#   yaml.status            → retired
#   然后自动跑 verify
# 想反悔就:bash tools/lifecycle.sh restore redis-7.0.15-0001
```

**文档同步(必做)**:删除 patch 后,可能有其他文档引用了它。**全部更新**!

```bash
# 找所有引用此 patch 的地方
grep -rn "io_uring\|0001-hw-kunpeng" README.md README_en.md docs/ .github/ 2>/dev/null
```

常见引用点:

| 文件 | 该改什么 |
|---|---|
| `README.md` / `README_en.md` | 删"特性介绍"段对此 patch 的描述,改"已合入上游" |
| `docs/zh/redis_network_async_optimization_feature_guide.md` | 同上 |
| `CHANGELOG.md`(如有) | 加一行 `### Removed` 记录 |
| `GOVERNANCE.md` § 1 目录结构示例 | 更新 patch 数 |
| `GOVERNANCE.md` § 0 30 秒速读表 | 更新"patch 总数" |

**判断题:patch 真删 vs archive 到 retired/?**

| 方案 | 何时用 |
|---|---|
| **archive 到 retired/(默认)** | 本仓精神是"开发者愿意配合",可恢复、不冒险。`bash tools/lifecycle.sh retire <id>` 一行解决 |
| 真删(rm) | archive 之后过了几个 release 确认不会回来再手动 rm,或退役的 patch 有 license 风险 |
| archive + CHANGELOG 留痕 | 兼顾可恢复 + 团队沟通(本仓推荐) |

> 注:`bash tools/lifecycle.sh retire <id>` **不真删**,而是 mv 到 `retired/` 子目录。好处:
> - 想"复活"就 `bash tools/lifecycle.sh restore <id>`
> - 想真删时手动 `rm retired/*.yaml retired/*.patch` 即可
> - 配合 git history,任何退役 patch 都可追溯 |

**完整 e2e 示例**(本仓 0001 假设被上游 7.2 合并):

```bash
# 1. 标 accepted
bash tools/lifecycle.sh set redis-7.0.15-0001 accepted

# 2. 查引用
grep -rn "0001\|io_uring" README.md docs/

# 3. 改 README.md 删引用段
$EDITOR README.md

# 4. 改 docs/...
$EDITOR docs/zh/redis_network_async_optimization_feature_guide.md

# 5. CHANGELOG.md 留痕
echo "## 2026-07-13
- remove redis-7.0.15-0001(io_uring): merged upstream in 7.2" >> CHANGELOG.md

# 6. 退役
bash tools/lifecycle.sh retire redis-7.0.15-0001

# 7. 跑 verify
bash tools/verify.sh

# 8. 提交 push
git add -A
git commit -m "chore(retire): remove 0001, merged upstream in 7.2"
git push
```

#### F. 怎么基于本仓构建(消费侧剧本)

**场景**:你(下游用户)拿到本仓的 patch,要 apply 到干净 redis 源码上 make。

**方法 1(最快,1 行):用 verify.sh 看 apply 状态**

```bash
bash tools/verify.sh
# 输出每个 patch 的 apply 状态,但产物在 /tmp,不可用
```

**方法 2(标准):逐 patch apply + build 到 redis 源**

```bash
# 假设 redis 源在 /opt/redis-7.0.15
REDIS_SRC=/opt/redis-7.0.15
VER=7.0.15
PATCH_REPO=/path/to/this/Redis-mvp-demo

cd "$REDIS_SRC"
git checkout $VER  # 或 checkout 目标 commit

# 逐 patch apply,每步 build + test
i=0
while read p; do
    i=$((i+1))
    [[ "$p" =~ ^# ]] && continue
    [[ -z "$p" ]] && continue

    echo "=== [$i] $p ==="

    # Step 1: apply
    if ! git apply --check "$PATCH_REPO/versions/redis-$VER/patches/$p"; then
        echo "  ✗ apply 失败,停止"
        exit 1
    fi
    git apply "$PATCH_REPO/versions/redis-$VER/patches/$p"
    echo "  ✓ applied"

    # Step 2: build
    make distclean >/dev/null 2>&1
    if ! make -j$(nproc) >/dev/null 2>&1; then
        echo "  ✗ build 失败,patch 引入编译错误"
        exit 1
    fi
    echo "  ✓ build OK"

    # Step 3: smoke test(可选)
    if [ -x ./runtest ]; then
        ./runtest --single unit/type 2>/dev/null && echo "  ✓ unit test OK" || echo "  ⚠ unit test 失败"
    fi
done < "$PATCH_REPO/versions/redis-$VER/series"
```

**方法 3(脚本化):保存到 `tools/apply-and-build.sh` 复用**

```bash
cat > /tmp/apply-and-build.sh <<'EOF'
#!/usr/bin/env bash
# apply-and-build.sh —— 把本仓的 patch apply 到 redis 源上并 build
# 用法: bash /tmp/apply-and-build.sh <redis-src-dir> [version]
set -e
SRC="${1:?usage: $0 <redis-src-dir> [version]}"
VER="${2:-7.0.15}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"

cd "$SRC"
git checkout "$VER" 2>/dev/null || { echo "  ✗ 缺 $VER tag"; exit 1; }
i=0
while read p; do
    i=$((i+1))
    [[ "$p" =~ ^# ]] && continue
    [[ -z "$p" ]] && continue
    echo "[$i] $p"
    git apply --check "$REPO/versions/redis-$VER/patches/$p" || { echo "  ✗ apply fail"; exit 1; }
    git apply "$REPO/versions/redis-$VER/patches/$p"
    make -j$(nproc) >/dev/null 2>&1 || { echo "  ✗ build fail"; exit 1; }
    echo "  ✓"
done < "$REPO/versions/redis-$VER/series"
echo "✓ 全部 $i 个 patch apply + build 成功"
EOF
chmod +x /tmp/apply-and-build.sh
```

**回滚**:如果中途某 patch 引入问题,`git reset --hard HEAD` 回滚(每个 apply 前可加 `git commit -am "before 0001"`,回滚用 `git reset --hard HEAD~1`)。

#### G. 两个 patch 冲突怎么办?

**冲突种类**:

| 类型 | 表现 | 难易度 |
|---|---|---|
| **A. 顺序敏感但不冲突** | 0001 改 X 第 10 行,0002 改 X 第 50 行 | ✅ 容易,series 排好序即可 |
| **B. 真冲突** | 0001 和 0002 都改 X 第 10 行的相同内容 | ❌ 难,需手工 rebase |
| **C. 上下文漂移** | 0001 的 `@@ -10,5 +10,7 @@` 上下文行在 0002 apply 后行号变了 | ⚠️ 中,git apply 失败 |

**检测冲突**:

```bash
# 单独 apply 都 OK,顺序 apply 才失败 → 真冲突
git apply --check versions/redis-7.0.15/patches/0001.patch  # OK
git apply --check versions/redis-7.0.15/patches/0002.patch  # OK
git apply versions/redis-7.0.15/patches/0001.patch
git apply --check versions/redis-7.0.15/patches/0002.patch  # 失败!

# 看具体哪个 hunk 失败
git apply --check versions/redis-7.0.15/patches/0002.patch 2>&1
# error: patch failed: src/networking.c:123
# error: src/networking.c: patch does not apply
```

**解决 3 方案**:

**方案 1:rebase 后到的 patch(推荐)**

```bash
# 思路:让 0002 基于"0001 apply 后"的状态生成
cd /tmp/redis-7.0.15
git checkout <baseline>
git apply 0001.patch

# 现在手动编辑,产生新的 0002 内容
$EDITOR src/networking.c

# 生成新的 0002 patch
git diff > /path/to/Redis/versions/redis-7.0.15/patches/0002.patch
```

**方案 2:三方合并(部分自动化)**

```bash
git apply --3way 0002.patch
# 3-way merge 利用 git 的合并算法,可能能自动解决一部分
# 成功:直接 apply
# 失败:有 CONFLICT 标记,需手工
```

**方案 3:--reject 部分应用**

```bash
git apply --reject 0002.patch
# 成功的 hunk 已应用
# 失败的 hunk 留到 .rej 文件,需手工
# 最后 git status 看哪些 .rej
```

**方案 4:合并两个 patch 为一个**

```bash
# 思路:把 0001 和 0002 的 hunks 合并
cat 0001.patch 0002.patch > combined.patch
# 手工编辑 combined.patch,去重 / 合并相近的 hunks
# 一般方案 1 失败时才用
```

**预防措施(写 patch 时就避免冲突)**:

| 做法 | 理由 |
|---|---|
| patch 拆细,每个 patch 只改一个 feature | 冲突面小,定位容易 |
| `applies_to` 字段记下"这个 patch 改哪些文件"(旧 metadata 字段,新 metadata 没保留) | 写 patch 时主动避开其他 patch 改的文件 |
| 早期 PR 阶段就 review,避免后期改同一文件 | review 时关注 "applies_to" 区域重叠 |
| 用 `git log --diff-filter=M --name-only` 查每个 patch 改的文件 | 写新 patch 时避开 |

**完整排查剧本**(本仓两个 patch 冲突示例):

```bash
# 1. 跑 verify 看到错误
bash tools/verify.sh
# 输出:  ⚠ redis-7.0.15/0002-perf-...: apply 失败

# 2. 单独 check 0002
cd /tmp && rm -rf r && git clone --depth 1 --branch 7.0.15 https://github.com/redis/redis r
cd r
git apply --check /path/to/Redis/versions/redis-7.0.15/patches/0001.patch  # OK
git apply /path/to/Redis/versions/redis-7.0.15/patches/0001.patch
git apply --check /path/to/Redis/versions/redis-7.0.15/patches/0002.patch  # 失败
# error: patch failed: src/networking.c:123

# 3. 试 --3way
cd /tmp/r
git apply --3way /path/to/Redis/versions/redis-7.0.15/patches/0002.patch
# 成功?✓ 完事
# 失败?有 CONFLICT,手工编辑

# 4. 手工合并(3-way 失败时)
$EDITOR src/networking.c
# 找 <<<<<<< 标记,合并
git diff > /path/to/Redis/versions/redis-7.0.15/patches/0002.patch
# 跑 verify
bash tools/verify.sh
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
