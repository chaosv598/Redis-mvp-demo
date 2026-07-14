# 业界 Patch Overlay 治理对比(凸显本仓轻量化)

> **目的**:把 simplify-v3 后的本仓(Redis-mvp-demo)放在业界方案里横向对比,凸显"1 工具 / 3 状态 / 一版本一 yaml"的轻量化。
> **对比维度**:学习成本、工具栈规模、元数据复杂度、CI 触发面、维护负担
> **对比版本**:2026-07-14 simplify-v3 后

---

## 0. TL;DR

| 方案 | 适用场景 | 工具数 | 元数据复杂度 | 状态机 | CI 触发面 | 学习成本 | 本仓定位 |
|---|---|---|---|---|---|---|---|
| **本仓 (simplify-v3)** | 单仓 patch overlay,小团队(<10),patch < 20 | **1** | 1 yaml/版本 + patches[] 数组 | 3 状态 | 1 job | **5 min** | 极简 |
| Linux kernel quilt | 内核级开发,patch 堆叠,大量贡献者 | 1 + 助手(quilt/guilt/pw/stgit) | 邮件签名 + 0 配置文件(隐式) | 0(无状态) | patchwork + 0 day CI | 1-2 周 | 最重 |
| Debian dpkg-source 3.0 (quilt) | Debian 源包,patch 自动 apply | 1 + 打包工具链(dh / gbp / pbuilder / sbuild) | d/control + d/rules + d/changelog + d/patches/series | 0(无状态) | 多(NMU 流程、buildd、lintian) | 1-2 周 | 重 |
| openEuler RPM SPEC | RPM 发行版打包,平台特性 | 1 + 完整 rpmbuild 工具链 | SPEC + SOURCES + %patch 指令 + changelog | 0(无状态) | OBS(Open Build Service)多 stage | 1-2 周 | 重 |
| Arch makepkg | Arch 用户仓库(AUR) | 1 + makepkg/pkgver 生态 | PKGBUILD(bash 函数) + .SRCINFO(自动生成) + sources() 数组 | 0(无状态) | AUR Web validation + namcap | 0.5-1 天 | 中 |
| gentoo portage epatch | gentoo ebuild overlay | 1 + portage 全套 | ebuild + epatch/epatch_user + FILESDIR | 0(无状态) | 没有,纯本地校验 | 1-3 天 | 中 |
| OpenWrt quilt | OpenWrt 软件包构建 | 1 + OpenWrt SDK | Makefile + patches/ + 数字前缀 | 0(无状态) | OpenWrt buildbot 多架构 | 3-5 天 | 中 |

**核心结论**:本仓 simplify-v3 是 **"patch overlay 元数据治理"** 这个特定赛道的最轻量实现。其他方案都在做"完整发行版打包"或"内核级 patch 堆叠",目标场景不在同一量级。

---

## 1. 各方案详细对比

### 1.1 本仓 simplify-v3(基线方案)

```text
versions/redis-7.0.15/
├── version.yaml     # 1 个 yaml/版本
└── patches/
    ├── 0001-...patch
    ├── 0002-...patch
    └── ...

tools/verify.sh      # 1 个 bash 脚本
.github/workflows/ci.yml   # 1 个 CI job
```

**核心设计**:

- **元数据**:一版本一 yaml,顶层 6 字段 + patches[] 数组;patch 字段 8 个(name/title/owner/type/status/pr/note/dependence)
- **状态机**:3 状态(pending / submitted / accepted),type 区分 ecological/project
- **工具栈**:1 个 `verify.sh`(4 步:仓根禁放 / 字段 enum 校验 / patches[] 一致性 / upstream apply)
- **CI**:1 个 verify job(GitHub Actions,~30s)
- **退役机制**:无
- **rebase 工具**:无(人工 cp 目录)
- **构建脚本**:无(下游业务自取)
- **钩子**:无

**学习成本**:看 `docs/GOVERNANCE.md` 5 分钟即可上手。

### 1.2 Linux kernel quilt

[Quilt](https://en.wikipedia.org/wiki/Quilt_(software)) 是 Linux kernel 早期(2.6 时代)主流的 patch 堆叠管理工具,现在被 Git + 邮件列表取代,但心智模型仍在。相关工具有 **guilt**(quilt 的 git-aware 增强版)、**stgit**、**patman/pw**(Patchwork + Patchwork 自动化)。

```text
linux/
├── .pc/                       # quilt 内部状态目录(每个 patch 一个应用状态)
└── patches/
    ├── series                 # apply 顺序,quilt 必读
    ├── 0001-foo.patch
    ├── 0002-bar.patch
    └── ...
```

**核心设计**:

- **元数据**:零配置文件。`series` 文件只有文件名,patch 内嵌 `From:` / `Subject:` / `Signed-off-by:` 等邮件头
- **状态机**:无。所有 patch 永久存在(没有 retired 概念)
- **工具栈**:`quilt push` / `quilt pop` / `quilt refresh` / `quilt new` / `quilt edit` … 至少 20+ 子命令。guilt 还多一组:guilt-init / guilt-add / guilt-fold / guilt-remove / guilt-rebase / guilt-push / guilt-pop …
- **CI**:`0-day CI` 是 kernel 特有的自动化测试基础设施,运行在 maintainer 的树之外;patch 提交后由 patchwork 自动测试。无统一 CI 模板,每个 subsystem 维护者有自己的脚本
- **元数据维护**:通过 `quilt header -e <patch>` 在 patch 内嵌 changelog / Tested-by / Reviewed-by 等
- **协作模式**:邮件列表(`lkml.org`),无 PR 概念

**学习成本**:1-2 周(quilt 命令集 + 邮件礼仪 + git 集成)

**为什么不学**:我们不是内核开发,没有 1000+ 贡献者协作场景,不需要邮件签名/Reviewed-by 链路。

### 1.3 Debian dpkg-source 3.0 (quilt)

[Debian 3.0 (quilt)](https://wiki.debian.org/DpkgV3toV1) 源包格式是 Debian 系发行版的标准,实际上借用了 Linux kernel 的 quilt 心智模型,但增加了完整的 Debian 打包体系。

```text
mypackage/
├── debian/
│   ├── control              # 包元数据(包名、依赖、维护者)
│   ├── rules                # 编译脚本(常用 dh)
│   ├── changelog            # 变更日志(dch 命令维护)
│   ├── source/
│   │   └── format           # 内容: "3.0 (quilt)"
│   ├── patches/
│   │   ├── series           # patch 应用顺序
│   │   ├── 01-loadparts.patch
│   │   ├── 02-gcc4.patch
│   │   └── ...
│   └── ...
└── upstream-source.tar.gz   # 上游源码 tarball
```

**核心设计**:

- **元数据**:`d/control`(包元数据)+ `d/changelog`(版本时间线)+ `d/rules`(编译脚本)+ `d/source/format` + `d/patches/series` + 每个 patch 单独文件 → **5+ 文件/dir 协同**
- **状态机**:无。patch 在 series 里就是"在线",移除就是"离线"(但保留在 patches/ 目录)
- **工具栈**:`dpkg-source` / `dpkg-buildpackage` / `dch` / `debuild` / `gbp`(git-buildpackage)+ `pbuilder` / `sbuild`(隔离构建)+ `lintian`(静态检查)+ `piuparts`(安装测试)+ `autopkgtest`(运行时测试)。**最少 8 个工具**
- **CI**:Debian 官方有 [buildd](https://buildd.debian.org/) 在多架构多 Debian 版本上自动编译;另有 [Debian CI](https://ci.debian.net/) 跑 autopkgtest。**多 stage 多 job**
- **patch 命名**:通常 `NN-description.patch`,NN 是数字前缀
- **协作模式**:`dch -i` 追加 changelog → commit → push → MR 到 salsa.debian.org → CI 自动跑 → maintainer review

**学习成本**:1-2 周(dh 框架 + lintian 规则 + pbuilder 隔离构建 + gbp 工作流)

**为什么不学**:我们不发布 .deb 包,不打 NMU(Non-Maintainer Upload)流程,不跑 lintian 30+ 类警告。

### 1.4 openEuler RPM SPEC

openEuler 的 RPM 打包体系,源自 Fedora / RHEL,核心是 SPEC 文件。

```text
redis/
├── redis.spec                # 核心:包元数据 + 构建指令 + %patch 指令
├── redis-7.0.15.tar.gz       # 上游源码 tarball
├── SOURCES/
│   ├── 0001-io_uring.patch   # patch 实际文件
│   ├── 0002-dtoe.patch
│   └── ...
└── rpmlintrc                 # rpmlint 抑制规则
```

**核心 SPEC 简化样例**:

```spec
Name:           redis
Version:        7.0.15
Release:        1
Source0:        https://download.redis.io/releases/redis-%{version}.tar.gz
Patch0:         0001-io_uring.patch
Patch1:         0002-dtoe.patch

%prep
%setup -q
%patch0 -p1
%patch1 -p1

%build
make -j$(nproc)

%install
make install PREFIX=%{buildroot}/usr

%changelog
* Mon Jul 14 2026 chaosv598 - 7.0.15-1
- adapt io_uring for Kunpeng
```

**核心设计**:

- **元数据**:SPEC 文件 + `%changelog`(RPM 强制,无 changelog 不能发布)+ SOURCES/ + rpmlintrc → **3+ 文件**
- **状态机**:无。patch 编号 Patch0/Patch1 就是元数据
- **工具栈**:`rpmbuild` / `rpm` / `rpmlint` / `spectool` / `rpmdevtools` + openEuler 特有的 **OBS(Open Build Service)** 多 stage build + 仓库管理 → **最少 6 个工具**
- **CI**:OBS 自动跨 openEuler 多个版本 + 多个架构(aarch64/x86_64)跑构建 → **多 stage 多架构 job**
- **patch 命名**:`NNNN-description.patch`,NNNN 是 SPEC 中的 PatchN 编号
- **协作模式**:PR 到 [src-openEuler](https://gitee.com/src-openeuler) → CI 自动跑 → maintainer review → 合并后自动 build → 推送到 openEuler 仓库

**学习成本**:1-2 周(SPEC 语法 + rpmbuild 流程 + OBS 使用 + rpmlint 规则)

**为什么不学**:我们不打 RPM 包,OBS 流水线对我们过重。

### 1.5 Arch Linux makepkg

Arch 的 PKGBUILD 是一个 **bash 函数集合**,本质是"用 bash 描述构建过程"。

```text
redis-pkg/
├── PKGBUILD                  # bash 函数:build() / package() / prepare()
├── .SRCINFO                  # 自动生成的元数据(给 AUR 用)
├── 0001-io_uring.patch       # patch 在同目录或 sources() 里下载
└── redis.install             # 可选:安装钩子
```

**简化 PKGBUILD**:

```bash
pkgname=redis-boostkit
pkgver=7.0.15
pkgrel=1
source=("https://download.redis.io/releases/redis-${pkgver}.tar.gz"
        "0001-io_uring.patch")
md5sums=('...' '...')

prepare() {
    cd redis-${pkgver}
    patch -p1 < ../0001-io_uring.patch
}

build() {
    make -j$(nproc)
}

package() {
    make PREFIX="$pkgdir/usr" install
}
```

**核心设计**:

- **元数据**:PKGBUILD(bash 函数,本身就是元数据 + 逻辑)+ .SRCINFO(自动生成)+ 可选 .install → **2 文件**
- **状态机**:无
- **工具栈**:`makepkg` / `namcap`(静态检查)+ `updpkgsums` / `makepkg --geninteg` → **3 个工具**
- **CI**:AUR Web 有 [namcap 自动验证](https://aur.archlinux.org/),但不在 PR 阶段;本地 `namcap PKGBUILD` 是常态
- **patch 应用**:`prepare()` 函数里手写 `patch -p1`,**不用 series 文件**
- **协作模式**:push 到 AUR(`git push ssh://aur@aur.archlinux.org/redis-boostkit.git`)→ 用户直接 `yay -S redis-boostkit` 安装

**学习成本**:0.5-1 天(PKGBUILD 模板熟悉即可)

**为什么不学**:虽然轻量,但 PKGBUILD 把元数据和构建逻辑混在 bash 函数里,verify 校验不容易做(没有独立 yaml 描述 patch 状态)。我们是"只管理 patch 元数据,不参与构建"的定位。

### 1.6 gentoo portage epatch

gentoo 用 ebuild 描述包,patch 通过 eclass(`epatch` / `epatch_user`)应用。

```text
local-overlay/
├── net-misc/
│   └── redis-boostkit/
│       ├── redis-boostkit-7.0.15.ebuild    # 元数据 + 编译指令
│       └── files/
│           ├── 0001-io_uring.patch
│           └── 0002-dtoe.patch
```

**简化 ebuild**:

```bash
EAPI=8
inherit epatch

DESCRIPTION="Redis with Kunpeng BoostKit patches"
SRC_URI="https://download.redis.io/releases/redis-${PV}.tar.gz"
HOMEPAGE="https://redis.io"

src_prepare() {
    epatch "${FILESDIR}/0001-io_uring.patch"
    epatch "${FILESDIR}/0002-dtoe.patch"
    default
}
```

**核心设计**:

- **元数据**:ebuild(类 bash 函数)+ FILESDIR 目录 → **1 文件 + 1 目录**
- **状态机**:无
- **工具栈**:`emerge` / `repoman`(仓库验证)+ `epatch`(eclass 函数,实际是 bash 函数)+ `eclass/`(自定义 eclass 库)→ **3 个工具,但耦合在 portage 全家桶里**
- **CI**:gentoo 没有统一 CI,每个 overlay 维护者自己跑 `repoman full -dx`
- **patch 应用**:`epatch` 或 `epatch_user` 函数,**不用 series 文件**,顺序靠 ebuild 里的调用顺序
- **协作模式**:push 到 overlays.gentoo.org → 用户用 eselect-repo 拉

**学习成本**:1-3 天(ebuild 语法 + eclass 体系 + repoman 规则)

**为什么不学**:gentoo 的"用户自定义 patch"心智模型好,但 ebuild 本身是包管理器的扩展点,不是"patch 元数据描述符",不适合我们"只描述 patch 不参与构建"的定位。

### 1.7 OpenWrt quilt

OpenWrt 软件包构建大量使用 quilt,目录结构和 Linux kernel 类似,但 patch 用数字前缀管理。

```text
package/utils/redis/
├── Makefile                  # OpenWrt 包定义
└── patches/
    ├── 0001-add-kunpeng-support.patch
    ├── 0002-fix-aof-fallback.patch
    └── ...
```

**核心设计**:

- **元数据**:Makefile + patches/ 目录(无 series 文件,OpenWrt 按字典序 apply)
- **状态机**:无
- **工具栈**:`quilt`(实际是 OpenWrt build system 调用)+ OpenWrt SDK 全套(`make menuconfig` / `make package/redis/compile` …)→ **最少 3 个工具,但 build system 整体复杂**
- **CI**:OpenWrt buildbot 跑多架构(ar71xx / ath79 / ipq40xx …)、多 firmware 变体 → **多架构多 job**
- **patch 命名**:`NNNN-description.patch`,NNNN 决定 apply 顺序(字典序)
- **协作模式**:PR 到 github.com/openwrt/packages → CI 自动跑 buildbot → maintainer review

**学习成本**:3-5 天(OpenWrt build system + menuconfig + 多架构工具链)

**为什么不学**:我们是 patch overlay 不是 firmware 构建,不需要 OpenWrt SDK。

---

## 2. 横向对比矩阵

### 2.1 工具栈规模

| 方案 | 必需工具数 | 工具列表 |
|---|---|---|
| **本仓 simplify-v3** | **1** | verify.sh |
| Linux quilt | 1 + 子命令集(20+) | quilt push/pop/refresh/new/edit/header/applied/series/top/bottom/unapplied/folders/diff … |
| Debian 3.0 (quilt) | 8+ | dpkg-source / dpkg-buildpackage / dch / debuild / gbp / pbuilder / sbuild / lintian / piuparts / autopkgtest |
| openEuler RPM SPEC | 6+ | rpmbuild / rpm / rpmlint / spectool / rpmdevtools + OBS 多 stage |
| Arch makepkg | 3 | makepkg / namcap / updpkgsums |
| gentoo epatch | 3+ | emerge / repoman + portage 全家桶 |
| OpenWrt quilt | 3+ | quilt + OpenWrt SDK(menuconfig + buildbot) |

### 2.2 元数据复杂度

| 方案 | 描述一个 patch 需要的文件/字段 |
|---|---|
| **本仓 simplify-v3** | **1 个 yaml 数组元素(8 字段)** |
| Linux quilt | patch 文件内嵌邮件头(From/Subject/Signed-off-by/...)+ `series` 文件 1 行 |
| Debian 3.0 | patch 文件 + `d/control` + `d/changelog` 引用 + `d/patches/series` 行 + `d/rules` 中编译指令 |
| openEuler RPM | patch 文件 + `SPEC` 中 `PatchN:` + `%patchN -p1` 指令 + `%changelog` |
| Arch makepkg | patch 文件 + PKGBUILD 中 `source=()` 数组元素 + `prepare()` 中 `patch -p1` |
| gentoo epatch | patch 文件 + `files/` 目录 + ebuild 中 `epatch "${FILESDIR}/..."` |
| OpenWrt quilt | patch 文件(命名带 NNNN 前缀决定顺序)+ Makefile 中引用 |

### 2.3 CI 触发面

| 方案 | CI 复杂度 | 典型耗时 |
|---|---|---|
| **本仓 simplify-v3** | **1 个 verify job** | ~30s |
| Linux quilt | patchwork + 0-day + 各 subsystem 自维护 | 几小时到几天 |
| Debian 3.0 | buildd 多版本多架构 + lintian + autopkgtest + piuparts + CI | 几小时 |
| openEuler RPM | OBS 多版本多架构 + rpmlint | 几小时 |
| Arch makepkg | 无强制 CI,namcap 本地校验 | 几秒 |
| gentoo epatch | 无强制 CI,repoman 本地 | 几秒 |
| OpenWrt quilt | buildbot 多架构 | 几小时 |

### 2.4 状态管理

| 方案 | 有显式状态机? | 状态字段位置 |
|---|---|---|
| **本仓 simplify-v3** | **✅ 3 状态** | `patches[].status`(yaml) |
| Linux quilt | ❌ 无 | (无) |
| Debian 3.0 | ❌ 无 | (无) |
| openEuler RPM | ❌ 无 | (无) |
| Arch makepkg | ❌ 无 | (无) |
| gentoo epatch | ❌ 无 | (无) |
| OpenWrt quilt | ❌ 无 | (无) |

**注意**:所有业界主流方案都**没有显式状态机**。`status: pending/submitted/accepted` 是本仓 simplify-v3 独有的概念(因为我们要追踪"是否发上游 PR / 上游是否合入")。

业界方案不追踪 patch 状态的原因是:**它们发布的 patch 就是终态**。Debian 进了 sid/testing 就是"已发布",不需要"pending"。我们追踪状态是因为 BoostKit 业务有"持续发上游"的诉求,需要区分"还在等上游 review"和"已落地本仓"。

### 2.5 学习成本

| 方案 | 新人上手时间 | 主要门槛 |
|---|---|---|
| **本仓 simplify-v3** | **5 分钟** | 看 GOVERNANCE.md 即可 |
| Linux quilt | 1-2 周 | quilt 命令集 + 邮件礼仪 + git 集成 |
| Debian 3.0 | 1-2 周 | dh 框架 + lintian + pbuilder + gbp |
| openEuler RPM | 1-2 周 | SPEC 语法 + rpmbuild + OBS |
| Arch makepkg | 0.5-1 天 | PKGBUILD 模板 |
| gentoo epatch | 1-3 天 | ebuild 语法 + eclass 体系 |
| OpenWrt quilt | 3-5 天 | OpenWrt build system + menuconfig + 多架构 |

---

## 3. 为什么 simplify-v3 是合适的(对比视角)

### 3.1 本仓定位的特殊性

我们的诉求和业界方案都不同:

| 维度 | 业界方案 | 本仓 |
|---|---|---|
| **目的** | 完整发行版打包或内核 patch 堆叠 | **patch overlay 元数据治理**(只描述 patch,不参与构建) |
| **贡献者** | 几十到几千 | **< 10 人**(内部 BoostKit 团队) |
| **patch 数** | 几十到几千 | **< 20 个** |
| **生命周期** | 包发布 = 终态 | patch 永久保留 + 持续发上游 |
| **发布物** | .deb / .rpm / kernel image | **下游业务自取(无打包)** |
| **合规需求** | lintian/rpmlint/repoman 多类警告 | 无 |
| **CI 目标** | 多架构多版本构建 | **verify 一致性 + apply 干净** |

### 3.2 借鉴了什么 / 没借鉴什么

**借鉴**:

- ✅ **quilt 的 `series` 心智模型**(patch 顺序由列表控制)— simplify-v3 把这个心智模型**内化到 yaml 数组**,省掉 series 文件
- ✅ **Debian/OpenEuler 的"每版本独立目录"**(`d/patches/` 或 SPEC 的版本化命名)— 我们用 `versions/<v>/` 一一对应
- ✅ **quilt/RPM 的"用数字前缀排序"**(0001-, 0002-)— 沿用,简单直观
- ✅ **GitHub Actions 的轻量 CI 模式**— 比 OBS/buildbot 简单一个数量级

**没借鉴**:

- ❌ **没有独立 `series` 文件**— 顺序在 yaml 数组里,不需要单独维护
- ❌ **没有 changelog 强制文件**— git commit message 即 changelog
- ❌ **没有 patch 邮件头**(From/Signed-off-by)— 不发邮件列表
- ❌ **没有 lintian/rpmlint/repoman 静态分析**— 不打 .deb/.rpm
- ❌ **没有 multi-arch 构建矩阵**— 下游业务方自己按需 build
- ❌ **没有 retired 状态**— patch 永久保留,不日落
- ❌ **没有 rebase 工具**— 人工 cp 目录(每年最多一两次,值得不上脚本)

### 3.3 simplify-v3 的"刚好够用"原则

```text
够用                     不够用(过度设计)
─────────────────────────────────────────────────
1 个 verify.sh            → 多个专用工具(lifecycle / rebase / install-hooks)
3 状态(yaml 字段)         → 5 状态(状态机脚本 + 状态变更校验)
一版本一 yaml             → 一 patch 一 yaml + series 文件 + 配置文件
github actions 1 job      → CI matrix(多版本/多架构)
git history = changelog   → 强制 %changelog 文件 / d/changelog 文件
```

每当我们觉得"这个工具/状态/字段是不是多余"时,就问两个问题:
1. 团队 5 个开发者中,**至少 3 个**会在日常工作中用到吗?
2. **没有它**会有什么真实的失败场景?(而不是"理论上可能")

如果两个答案都是"不会/没有",就砍掉。

---

## 4. 适用边界

simplify-v3 不是万能方案,以下场景**不适合**:

| 场景 | 为什么 simplify-v3 不适合 | 推荐方案 |
|---|---|---|
| patch 数 > 50 | yaml 数组会变长,人工维护成本上升 | Debian 3.0 (quilt) 或 kernel quilt |
| 贡献者 > 20 人 | 单仓一 owner 模式管理不过来 | 内核 quilt + patchwork + 邮件列表 |
| 多架构多 OS 矩阵 | 我们不参与构建 | openEuler RPM + OBS |
| 用户需要 .deb / .rpm | 我们不打发行版包 | Debian 3.0 / openEuler RPM |
| patch 有合规审查 | 我们不审 lintian 规则 | Debian 3.0(lintian 强制) |
| patch 需要邮件签名 | 我们不发邮件列表 | Linux kernel quilt |

**适用场景**:

- ✅ 单一上游项目(Redis、PostgreSQL、nginx 等)
- ✅ 内部团队维护(< 10 人)
- ✅ patch 数 5-20 个
- ✅ patch 永久保留(不需要退役)
- ✅ 下游业务方按需自取(仓本身不打发行版包)
- ✅ 不需要多架构/多 OS 矩阵构建

---

## 5. 总结

simplify-v3 不是"业界最佳实践",而是**"针对本仓定位的最小化实践"**:

- 业界方案是**通用打包/构建框架**,我们只需要**patch 元数据描述**;
- 业界方案追踪**包生命周期**,我们追踪**patch 状态**(发上游进度);
- 业界方案跑**完整 CI 矩阵**,我们跑**verify 一致性**即可;
- 业界方案强制**changelog/lint 规则**,我们靠**git history + enum 校验**。

把不必要的部分砍光,剩下的就是 simplify-v3:**1 工具 / 3 状态 / 一版本一 yaml / 1 个 CI job**。

这也是为什么本仓 5 分钟就能上手 — **不是设计得巧妙,而是设计得刚好**。
