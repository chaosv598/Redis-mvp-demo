# CI —— GitHub Actions 版

> 翻译自 `.gitee-ci.yml`(v5 MVP 4 周落地版的 GitCode CI 模板,2026-07-10)
> GitHub 公共仓库使用 GitHub-hosted runner 即可免费跑,**这是 W3 验证后的实施版本**。

## 触发条件

| 事件 | 行为 |
|---|---|
| `push` to `master` | 跑全部 6 个 job(doctor / lint / check-series / check-owners / check-apply / check-tag) |
| `pull_request` to `master` | 同上 |
| `workflow_dispatch` | 手动触发,菜单里 Run workflow |

并发控制:`concurrency.cancel-in-progress = true`,**同 PR 后续 push 会取消旧 run**,节省 CI 分钟数。

## Job 矩阵与 .gitee-ci.yml 对照

| .gitee-ci.yml stage | .gitee-ci.yml job | GitHub Actions job | blocking | 备注 |
|---|---|---|---|---|
| `lint` | `doctor` | `doctor` | ✅ 必跑 | `python tools/doctor.py` 7 铁律自检 |
| `lint` | `lint-yaml` | `lint` | ✅ 必跑 | `python tools/lint.py boostkit.yaml` 8 必填字段 |
| `lint` | `check-series` | `check-series` | ✅ 必跑 | `python tools/check-series.py` series ↔ patches/ |
| `apply` | `check-apply` | `check-apply` | ⚠️ `continue-on-error: true` | 网络拉 upstream + apply,允许偶发失败(对应 .gitee-ci.yml 的 `allow_failure: true`) |
| `owners` | `check-owners` | `check-owners` | ✅ 必跑 | `python tools/check-owners.py OWNERS` 强制 ≥ 2 双签 |
| (无) | (无) | `check-tag` | ⚠️ `continue-on-error: true` | v5 选跑项,只在发版时硬性要求 |

## 关键翻译点

1. **image → runs-on**: GitHub Actions 不需要 `image:` 字段,用 `runs-on: ubuntu-latest` 即可
2. **rules 条件**: `if: $CI_PIPELINE_SOURCE == 'merge_request_event'` → GitHub 的 `on: pull_request`
3. **artifact 路径**: `versions/*/reports/` 用 GLOB 通配,`upload-artifact@v4` 的 `if-no-files-found: ignore` 避免空目录失败
4. **apk add bash git**: ubuntu-latest 自带 bash + git,无需装
5. **allow_failure: true → continue-on-error: true**: 语义等价

## 预计运行时间

| Job | 时间 | 备注 |
|---|---|---|
| doctor / lint / check-series / check-owners | ~5-10s | 纯本地检查 |
| check-apply | ~60-120s | 主要花在 `git clone https://github.com/redis/redis` |
| check-tag | ~3s | git for-each-ref |

**总时长 ~1.5 分钟**(对比 .gitee-ci.yml 的 1-3 分钟,GitHub runner 普遍更快)。

## 必要权限 / 限制

- **Public 仓库**: 完全免费,无分钟数限制
- **Private 仓库**: GitHub Free tier 给 2000 分钟/月
- 不需要任何 GitHub Secrets(check-apply 走匿名 clone)
- 如未来要加私有上游,需 `GH_TOKEN` + `actions/checkout` 用 token

## 失败处理

| 失败类型 | 修复路径 |
|---|---|
| `doctor` 报 `PATCH-IN-ROOT` | 仓根禁止 `*.patch`,移到 `versions/<v>/patches/` |
| `doctor` 报 `SERIES-MISMATCH` | 把 `patches/*.patch` 文件名同步到 `series` 字典序 |
| `lint` 报 `missing: <path>` | 补 `boostkit.yaml` 8 必填字段 |
| `check-owners` 报 `OWNERS approvers: 1` | 在 `OWNERS` 的 `approvers:` 下加 1 个邮箱(强制 ≥ 2) |
| `check-apply` 报 `clone failed` | 几乎都是网络抖动,重跑即可(check-apply 已经是 `continue-on-error`,不阻塞 merge) |
| `check-apply` 报 `FAIL <patch>` | patch 与 upstream `<sha>` 不匹配,需 rebase |

## 与 v5 规范的对应

- v5 §1 第 7 条铁律: "所有 CI 必跑 4 步:yaml-lint → apply → build → owners,绿才允许 merge"
- 本仓 4 步 = `lint → check-apply → check-owners → (可选 check-tag)`,**build 由 patch 集成的实际项目跑(Kunpeng ARM jenkins)**,不在本仓 CI 跑(避免跨架构)
- v5 §3.7 `.gitee-ci.yml` 4 步模板 → 本文件做 GitHub Actions 适配
- v5 §13 验收指标 3 "CI 4 步接入: 100%(可豁免未启用)":**本仓已在 GitHub 启用,可作为 W2 验收示范**

## 进一步优化方向(超出 MVP 4 周范围)

- 加 `concurrency.group` 防止 PR 拥塞(已做)
- 加 `actions/cache` 缓存 pip / git(影响小,跳过)
- `check-apply` 改 matrix(每个 upstream version 一个 job,失败定位更准)
- 加 `policy-bot`/`dangerjs` 强约束 PR 模板(本仓 PR 模板已是规范版本)
