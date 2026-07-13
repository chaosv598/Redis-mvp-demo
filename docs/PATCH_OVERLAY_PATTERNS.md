# 三种主流 Patch Overlay 模式详解

> **目的**:对照 `GOVERNANCE.md` 看本仓的 patch overlay 设计哲学,梳理业界三套主流模式(quilt / Debian / RPM)的实际管理方式、目录结构、命令行工具链、CI/校验机制,以及本仓相对它们的差异。
>
> **范围**:本仓 `chaosv598/Redis-mvp-demo` 是上游 `redis/redis` 的本地化 patch overlay,本质问题都是「**在不动 upstream 的前提下,把多个本地 patch 整齐地叠到特定版本上,并能复现、追溯、最终合回 upstream**」。三套业界模式各自用不同工具回答了这个问题。

---

## 0. 一张表先看清脉络

| 维度 | Linux Kernel + quilt | Debian/Ubuntu 系列 patch | openEuler/Anolis RPM overlay | **本仓(Redis-mvp-demo)** |
|---|---|---|---|---|
| Patch 物理形态 | `git format-patch` / mailbox | `.patch` / `.diff` | `.patch` (SOURCES/) | `.patch` |
| 顺序声明 | 不显式(commit 顺序就是顺序) | `debian/patches/series` | SPEC `%patch -p1` 顺序 | `versions/<v>/series` |
| 元数据 | commit message + Signed-off-by | `debian/changelog` + patch header | SPEC 文件 + changelog | `metadata/*.yaml` |
| 叠加工具 | `git am` / `quilt push` | `quilt` + `dpkg-buildpackage` | `rpmbuild` + `OBS` | `git apply` + 自研 `verify.sh` |
| 状态机 | mailing list 上的讨论 + maintainer ACK | changelog 的版本号演化 | changelog 的 release 号 | 6 字段 metadata 显式建模 |
| CI/校验 | patchwork / pwclient / KernelCI | `lintian` / `piuparts` / sbuild | `osc build` + OBS 多架构 | **GitHub Actions 1 个 job** |
| 评审通道 | LKML + patchwork | Sponsor / ftp-master | Maintainer / Release SIG | **GitHub PR** |
| 退役机制 | patch 被 merge 后自然消失 | 下个 release 不再带 patch | 下个 SRPM 不再带 patch | `lifecycle.sh retire` 4 处同步删 |
| 日落机制 | merged upstream 后 quilt drop | 验证后从 series 移除 | 不再 apply 进新 SRPM | 走 §4.3-E sunset 剧本 |
| 工具数 | ~20 个(sendemail, pwclient, b4…) | ~10 个(quilt, dpkg-*, lintian…) | ~5 个(rpmbuild, osc, rpm…) | **4 个** |

---

## 1. Linux Kernel + quilt(经典原型)

### 1.1 思想

**Quilt 是 Andrew Morton 1990s 末期为内核维护者写的 patch stack 管理器**,本质上是把 `git` 之前时代「一堆 patch 文件 + 显式 stack」的思路自动化。`quilt` 不依赖 git,纯文件系统 + `.pc/` 目录记录应用状态。

内核社区后来把 quilt 哲学带到了 `git format-patch` + `git send-email` + lore.kernel.org 邮件列表的体系下,但**目录里"系列 patch + 显式 series 声明"的思想一脉相承**。

### 1.2 实际目录结构(以 `linux-stable` 子系统维护者 tree 为例)

```
git://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next.git
   └── (一棵树就是一组 stacked commits,每个 commit = 一个 patch)
```

维护者不是发文件,而是 push 一棵 **branch tree**。Linus 或其他 maintainer `git pull` 整棵 tree,内部每个 commit 用 `git log -p` / `git am` 应用。

**邮件列表模式**的产物(被 lore.kernel.org 索引):
```
[PATCH v3 0/7] support for foo subsystem
  ├── [PATCH v3 1/7] core: add foo foundation
  ├── [PATCH v3 2/7] core: add foo helper
  ├── …
  └── [PATCH v3 7/7] selftests: cover foo
```

### 1.3 关键工具链

| 工具 | 用途 | 在本仓对应 |
|---|---|---|
| `quilt new/push/pop/top/refresh` | 维护 patch stack(.pc/ 记录 apply 状态) | 没用(本仓 patch 是冻结的,不需要动态 stack) |
| `git format-patch` + `git send-email` | 生成 + 发送 patch 到邮件列表 | `git format-patch`(本仓手动构造,首部用 `From:`/`Subject:`/`---`) |
| `b4` | 自动从邮件拉 patch series、`git am` 复现 | 没有,本仓直接 PR |
| `pwclient` | patchwork CLI,管理 patch state | 没有,本仓用 metadata.yaml 字段 |
| `checkpatch.pl` | 单 patch 静态检查(编码风格) | 没有,本仓只看 apply 行为 |
| `KernelCI` | 跨架构 CI,跑 defconfig/allmodconfig | 没有,本仓 1 个 job 跑 verify.sh |

### 1.4 状态机(隐式)

内核没有显式状态机,但通过**多层 review 轮次**达到同样效果:

```
RFC(社区反馈) → v1(reviewer 反馈) → v2 → … → merged into maintainer tree
                                            → pulled into Linus tree → released
```

每轮迭代**整组重新发**(`[PATCH v2 0/N]`),patch 顺序可能调整、新增/删除 patch 都通过整组重发同步。

### 1.5 与本仓的差异

| 维度 | 内核 | 本仓 |
|---|---|---|
| Patch 形式 | mailbox 邮件(Patchwork 归档) | 文件 + GitHub PR |
| Series 显式 | ❌(commit 顺序即顺序) | ✓(series 文件) |
| 状态机 | 隐式(邮件轮次) | 显式(metadata.yaml 6 字段) |
| 退役机制 | 自然合并即消失 | `lifecycle.sh retire` 4 处同步 |
| 评审通道 | LKML | GitHub PR + Actions |

**最大的不同是「开发者在 PR 中得到即时 CI 反馈」**,而内核社区的 patch 作者要等 KernelCI 跑完 + maintainer review。

---

## 2. Debian/Ubuntu 系列 patch(debian/patches)

### 2.1 思想

Debian 把「上游源码 + 本地化 patch」做成一个**包(package)**,每个包是一个目录,里面有:

- 上游源码(`.orig.tar.gz`)
- 本地 patch 系列(`debian/patches/`)
- 描述元数据(`debian/control`、`debian/changelog`)
- 构建规则(`debian/rules`)

构建时把 patches 按 series 顺序 `quilt push`,再编译。这是 **deb 系发行版所有 patch 都按这个模式管理**(apt-get source 看到的源码)。

### 2.2 实际目录结构(`apt-get source redis` 之后)

```
redis-7.0.15/
   ├── (上游源码,已解开)
   ├── debian/
   │    ├── control           # 包元数据(名、版本、依赖、维护者)
   │    ├── changelog         # 变更日志 + 版本号 + 维护者签名
   │    ├── rules             # makefile,定义 build / install / clean
   │    ├── compat            # debhelper 兼容版本
   │    ├── patches/
   │    │     ├── series      # patch 顺序,每行一个 patch 文件名
   │    │     ├── 0001-foo.patch
   │    │     ├── 0002-bar.patch
   │    │     └── …
   │    └── …
   └── (上游其他文件)
```

### 2.3 series 文件示例

```
$ cat debian/patches/series
0001-add-build-flags.patch
0002-fix-debian-specific.patch
0003-debianize-init-script.patch
```

**和本仓 `versions/redis-7.0.15/series` 几乎一模一样**。

### 2.4 patch 文件格式(`dpkg-source` 工具链输出)

```diff
Description: <changelog 一行说明>
Author: <维护者名字+邮箱>
Forwarded: <yes/no/upstream URL>
Last-Update: <YYYY-MM-DD>

--- a/src/server.c
+++ b/src/server.c
@@ -100,7 +100,7 @@ void foo() {
-    old();
+    new();
```

这种带 `Description:` / `Author:` / `Forwarded:` / `Last-Update:` 的扩展头是 **deb 特有的 `DEP-3` 格式**,quilt 原生 patch 没有。

> 这正是 2026-07-13 simplify-v2 之前的 metadata 文件结构参考对象 — DEP-3 的字段比 6 字段还重,所以本仓最终精简掉。

### 2.5 关键命令

```bash
# 在已 debian 化的源码树中
quilt new 0004-my-fix.patch        # 创建新 patch
quilt edit src/server.c            # 编辑源码,改动进 patch
quilt refresh                       # 把改动写回 .patch 文件
quilt push                          # 应用下一个 patch
quilt pop                           # 撤销上一个 patch
quilt series                        # 看 patch 列表

# 包构建
dpkg-buildpackage -us -uc -b        # 构建二进制包,会自动 quilt push 所有
lintian redis_*.changes             # 包质量检查(有 lint 警告)
piuparts                            # 安装/卸载/重装测试
sbuild                              # 在干净 chroot 中构建(reproducible build)
```

### 2.6 状态机

通过 `debian/changelog` 的版本号演化表达:

```
redis (5:7.0.15-1) unstable; urgency=medium
  * Initial release.

redis (5:7.0.15-2) unstable; urgency=medium
  * 0001-fix-foo.patch: fix crash on reconnect (Closes: #123456)

redis (5:7.0.15-3) unstable; urgency=high
  * 0002-cve-fix.patch: fix CVE-2024-XXXX
```

每个 entry 对应一个 patch,版本号末尾 `-N` 累加。**没有显式「retire」**,要么 patch 还在(下次构建时进包),要么 patch 从 series 移除(下个版本不带)。

### 2.7 CI/校验

| 工具 | 作用 |
|---|---|
| `lintian` | 静态 lint(几百条规则),检查 packaging 规范性 |
| `piuparts` | 安装/卸载/重装/降级/升级测试 |
| `sbuild` + schroot | 在确定环境里 reproduce build |
| `autopkgtest` | 跑包内 `debian/tests/` 的测试 |
| `reproducible-builds.org` | 校验同源代码是否 byte-identical 出包 |

**Debian 的 CI 比本仓重得多** — 一个上游新版本要进入 Debian stable 通常要 5-10 天,过 `unstable → testing → stable` 三道关。

### 2.8 与本仓的差异

| 维度 | Debian | 本仓 |
|---|---|---|
| Patch 元数据 | DEP-3 头(多字段) | 6 字段 YAML |
| 系列叠加 | `quilt push`(可动态 pop) | `git apply`(单向) |
| 构建产出 | `.deb` 包 | 源码树(消费方再 build) |
| CI | lintian + piuparts + sbuild | 1 个 verify.sh |
| 评审通道 | Sponsor review / NM 流程 | GitHub PR + 1 个 CI job |
| 适用范围 | 全发行版所有包 | 单一上游(Redis)单仓 |

**最显著的差异是「动态 vs 静态」** — Debian 的 `quilt push/pop` 允许 patch 半应用状态(只 push 前 3 个 patch 调试),本仓 patch 是**冻结的**(`verify.sh` 全 apply 或 warn)。

---

## 3. openEuler / Anolis RPM overlay

### 3.1 思想

**openEuler(华为欧拉) / openAnolis(龙蜥)** 都是 CentOS/RHEL 系的国产化衍生,它们在 RPM 包层做了大量 patch overlay。每个上游包(redis / nginx / glibc …)都有专属目录,里面是 `.spec` + SOURCES + 补丁。

这是**国产化操作系统厂商几乎唯一的选择** — 不能 fork 上游(license / 协作模式问题),只能在 RPM 构建阶段 overlay patch。

### 3.2 实际目录结构(openEuler `openeuler-rpm-repo`)

```
openeuler-rpm-repo/
   └── redis/                          # 一个包一个目录
        ├── redis.spec                 # RPM 构建描述
        ├── redis-7.0.15.tar.gz        # 上游源码(打包好的)
        ├── SOURCES/
        │     ├── redis-7.0.15-boost-0001-io_uring.patch
        │     ├── redis-7.0.15-boost-0002-dtoe.patch
        │     └── …
        └── README.md
```

### 3.3 spec 文件示例(简化)

```spec
Name:           redis
Version:        7.0.15
Release:        2%{?dist}
Source0:        %{name}-%{version}.tar.gz
Patch0:         %{name}-%{version}-boost-0001-io_uring.patch
Patch1:         %{name}-%{version}-boost-0002-dtoe.patch

%description
Redis with BoostKit adaptations for Kunpeng ARM.

%prep
%autosetup -p1                  # 自动展开源码 + 按 PatchN 顺序 apply

%build
make %{?_smp_mflags} BUILD_TLS=yes USE_SYSTEMD=yes

%install
make install DESTDIR=%{buildroot}

%changelog
* Mon Jul 13 2026 dev@boostkit - 7.0.15-2
- Add AOF fallback patch (boost-0004)
* Mon Jun 15 2026 dev@boostkit - 7.0.15-1
- Initial BoostKit overlay on 7.0.15
```

**`Patch0:` / `Patch1:` + `%autosetup -p1` + `%changelog` = RPM 版的 series 文件**。顺序由 `PatchN:` 行号声明,`%autosetup` 自动按 N 顺序 apply。

### 3.4 关键工具链

| 工具 | 用途 | 在本仓对应 |
|---|---|---|
| `rpmbuild -ba xxx.spec` | 本地构建 SRPM + RPM | 没用(本仓不产 RPM) |
| `osc` (openSUSE Build Service 命令行) | 提交源码包到 OBS | 没用 |
| `osc build` | 在 OBS 干净 chroot 跨架构构建 | 没用 |
| `rpm -qp --changelog xxx.rpm` | 看包 changelog | 没有 |
| `mock` | 本地干净 chroot 模拟构建 | 没有 |

### 3.5 状态机

通过 `%changelog` 段落 + `Release:` 字段演化:

```
Release: 1     # 第一次 overlay
Release: 2     # 加了 1 个 patch
Release: 3     # 加了 1 个 patch + rebase 到上游新版本
Release: 5%{?dist}.1   # 修复某个 patch 应用错误(进 .1)
```

**没有显式 retire 字段** — 要退役就在 `Prep:` 里删 `PatchN:` 那行,下次构建就不带。

### 3.6 CI / 校验(OBS 体系)

**openEuler / openAnolis 用 OBS(Open Build Service)做 CI**,一站式搞定:

- 提交 PR(可以是 Gitee 仓 PR)
- 触发 OBS webhook
- OBS 在 x86_64 / aarch64 / armv7hl / loongarch64 … 多个架构上跑 rpmbuild
- 失败 → 邮件 + Gitee 评论,成功 → 进 build 仓库

### 3.7 与本仓的差异

| 维度 | openEuler RPM | 本仓 |
|---|---|---|
| 构建产出 | `.rpm`(给 yum/dnf 用) | 源码树(消费方再 build) |
| 叠加工具 | `rpmbuild` + `%autosetup` | `git apply` |
| 顺序声明 | `PatchN:` 字段 | `series` 文件 |
| CI | OBS 跨架构多仓库 | GitHub Actions 1 个 ubuntu-latest job |
| 评审通道 | Gitee PR + OBS | GitHub PR + Actions |
| 元数据 | `xxx.spec` + `%changelog` | 6 字段 YAML |

**最大差异是「OS vendor 全栈视角 vs 单包轻治理视角」** — openEuler 要为几十万个 RPM 包负责,所以工具链重(spec + SOURCES + SRPM);本仓只为 Redis 一个上游服务,所以工具链极简(4 个 .sh)。

---

## 4. 三者并列对照(从开发者视角)

### 4.1 「我加了 1 个新 patch,要走什么流程?」

| 步骤 | 内核 quilt | Debian | openEuler RPM | **本仓** |
|---|---|---|---|---|
| 1. 准备 patch | `quilt new` + `quilt edit` + `quilt refresh` | `quilt new` + `quilt edit` + `quilt refresh` | 手写 .patch,放 `SOURCES/` | `git diff` 出 .patch,放 `versions/<v>/patches/` |
| 2. 加到 series | 自动(pop top 时的 stack 状态) | 加一行到 `debian/patches/series` | 加一行 `PatchN:` 到 spec | 加一行到 `versions/<v>/series` |
| 3. 元数据 | commit message + S-o-b | `dch -i` + changelog entry | `%changelog` entry | 6 字段 YAML |
| 4. 验证 | `checkpatch.pl` + `git am --3way` | `lintian` + `sbuild` | `osc build` | `bash tools/verify.sh` |
| 5. 提交 | `git send-email` 到 LKML | Sponsor review / dput | `osc sr` 进 OBS | `git push` + GitHub PR |
| 6. CI | patchwork + KernelCI | 多层(Debian CI / Salsa CI / Buildd) | OBS 多架构 | 1 个 GitHub Actions job |
| 7. 合并/接受 | maintainer pull → Linus | FTP master 入库 | 进 build 仓库 | squash merge PR |

### 4.2 「上游发新版本了,我要 rebase 全部 patch 怎么办?」

| | 内核 | Debian | openEuler RPM | **本仓** |
|---|---|---|---|---|
| 工具 | `git rebase` + 一个个冲突解 | `gbp pq import` + rebase | `rpmbuild --rebuild` + 手改 | `bash tools/rebase.sh` |
| 耗时 | 几小时(数千个 patch) | 几小时(几十个 patch) | 几小时 | 几分钟 |
| 失败处理 | `git rerere` 缓存 | `gbp pq export` 重做 | 手动编辑 SOURCES | 手动 + 注释冲突 patch |

### 4.3 「上游把我的 patch 合了,本地怎么日落?」

| | 内核 | Debian | openEuler RPM | **本仓** |
|---|---|---|---|---|
| 动作 | 自然消失(下版不再发) | 下次 release 移除 `PatchN:` | 下次 SRPM 移除 `PatchN:` + `Source0` 升版 | `lifecycle.sh retire <id>` 4 处同步删 |
| 痕迹 | 邮件归档(lore.kernel.org) | changelog 历史 | `%changelog` 历史 | metadata `status: retired` + git log |

### 4.4 「我 patch 之间有依赖 / 冲突怎么办?」

| | 内核 | Debian | openEuler RPM | **本仓** |
|---|---|---|---|---|
| 依赖声明 | patch header `Depends-on:`(约定俗成) | patch header `Depends:`(DEP-3) | 注释在 SPEC | series 顺序隐式 |
| 冲突解决 | `git rerere` + 重新 base | `quilt refresh` 时手工合并 | 手动 + `rpmbuild` 失败重试 | `git apply --3way` + 人工 |
| 预防 | patch 拆细 + review 关注重叠 | 同 | 同 | 同(详见 GOVERNANCE.md §4.3-G) |

---

## 5. 工具数量与上手成本的对比

| 模式 | 必装工具 | 上手成本 |
|---|---|---|
| 内核 quilt | `quilt` `git` `git-email` `b4` `pwclient` ~7 个 | **高**(邮件列表文化) |
| Debian | `quilt` `dpkg-dev` `lintian` `sbuild` `devscripts` ~8 个 | **中**(打包规范多) |
| openEuler RPM | `rpm-build` `rpmdevtools` `osc` `mock` ~5 个 | **中**(spec 文件学习曲线) |
| **本仓** | `bash` `git` `gh` ~3 个 | **低**(30 秒速读,见 GOVERNANCE.md §0) |

---

## 6. 一句话总结

> **Linux quilt 是 patch overlay 的哲学原型**,**Debian 是它最忠实的工程化继承者**,**openEuler RPM 是它在 OS vendor 场景下的国产化分支**。
>
> 本仓 `Redis-mvp-demo` 是**这三者的现代 GitHub 化综合**:
> - 继承了 **quilt** 的「patch series + 显式叠加」思想
> - 借鉴了 **Debian** 的 `series` 文件 + 6 字段精简 metadata(去掉 DEP-3 的重字段)
> - 等价替换了 **openEuler RPM** 的 `%autosetup` 为 `git apply`、OBS 为 GitHub Actions、`PatchN:` 序号为 `series` 行号
> - 加了 **状态机显式建模**(metadata.yaml 的 `upstream_plan.status`)和 **PR 即时 CI 反馈**(GitHub Actions),这是内核邮件列表模式所缺的
>
> 适用场景:**单 upstream、单仓库、轻量、本地 CI 优先**。当 patch 数 < 50、上游发版频率 < 半年一次,本仓模式比 RPM/quilt 更轻;反之,建议升级到完整 Debian / RPM 工具链。

---

## 附录:本仓文件 ↔ 业界模式映射表

| 本仓文件/工具 | 内核对应 | Debian 对应 | openEuler RPM 对应 |
|---|---|---|---|
| `versions/<v>/patches/*.patch` | `git format-patch` 产物 | `debian/patches/*.patch` | `SOURCES/*.patch` |
| `versions/<v>/series` | 隐式(commit 顺序) | `debian/patches/series` | `PatchN:` 字段 |
| `versions/<v>/metadata/*.yaml` | commit message + S-o-b | DEP-3 patch 头 + `debian/changelog` | `xxx.spec` `%changelog` |
| `tools/verify.sh` | `checkpatch.pl` + manual apply | `lintian` + `quilt push` | `rpmbuild --nobuild` + OBS |
| `tools/lifecycle.sh` | patchwork 状态 | changelog 版本号 | `%changelog` Release 号 |
| `tools/rebase.sh` | `git rebase` | `gbp pq rebase` | `rpmbuild` + SPEC `%define` |
| `tools/install-hooks.sh` | 没有(自带 hook 体系) | 没有 | 没有 |
| `.github/workflows/ci.yml` | patchwork + KernelCI | Salsa CI / Buildd | OBS webhook |
| `docs/GOVERNANCE.md` | `Documentation/` + maintainer info | `debian/README.*` | `README.md` + `docs/` |

— 完 —