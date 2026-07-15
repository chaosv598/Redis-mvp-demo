#!/usr/bin/env python3
"""
sync-manifest —— version.yaml → PATCHES.yaml / WHITELIST.yaml / docs/PATCHES-STATUS.md 自动同步

规范 /mnt/d/AI/github_cli/BoostKit-Patch-Governance-Spec.md §2 / §4.3:
  - 开发者唯一手写入口: versions/<v>/version.yaml + versions/<v>/patches/<name>.patch
  - PATCHES.yaml       (仓根)  - 仓内 patch 单一真相源
  - WHITELIST.yaml     (仓根)  - 白名单 patch 集中视图
  - docs/PATCHES-STATUS.md    - 人读状态仪表盘

用法:
  python3 tools/sync-manifest.py --check    # CI drift 检测
  python3 tools/sync-manifest.py --write    # 写回所有自动文件
  python3 tools/sync-manifest.py --report   # 只打印人读报表
"""
import argparse
import datetime
import sys
from collections import defaultdict
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent

STATUS_ENUM = {"pending", "submitted", "accepted", "rejected", "whitelisted"}
TYPE_ENUM = {"ecological", "project"}


def load_yaml(path: Path) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def collect_versions() -> list[dict]:
    """扫 versions/ + demos/ 下所有 version.yaml,加 kind 标记"""
    out = []
    for kind, sub in (("production", "versions"), ("demo", "demos")):
        base = ROOT / sub
        if not base.exists():
            continue
        for vp in sorted(base.glob("*/version.yaml")):
            m = load_yaml(vp)
            m["_kind"] = kind
            m["_path"] = str(vp.relative_to(ROOT))
            out.append(m)
    return out


def build_patches_manifest(versions: list[dict]) -> dict:
    """规范 §2.1: 仓根 PATCHES.yaml"""
    now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    entries = []
    for v in versions:
        if v.get("demo"):
            continue  # demo version 不进生产 manifest
        vid = v.get("version_id", "")
        ub = v.get("upstream_base", {}) or {}
        commit = ub.get("commit", "")
        for p in v.get("patches", []) or []:
            name = p.get("name", "")
            entries.append({
                "id": f"P-{name.removesuffix('.patch')}",
                "name": name,
                "title": p.get("title", ""),
                "owner": p.get("owner", ""),
                "category": p.get("type", ""),  # 派生自 type
                "status": p.get("status", ""),
                "upstream_pr": p.get("upstream_pr", []) or [],
                "whitelist": p.get("status") == "whitelisted",
                "whitelist_reason": p.get("whitelist_reason", ""),
                "applies_to": [
                    {"version": vid, "commit": commit}
                ],
            })

    # 跨 version 同 name 合并 applies_to (规范 §2.2: 同一 patch.name 跨多 version → 不合并条目,
    # 严格按 spec 是不合并的;这里保守地保留独立条目,只把多次出现也允许)
    by_name: dict[str, dict] = {}
    for e in entries:
        n = e["name"]
        if n in by_name:
            # 同一 name 出现多次:追加 applies_to,保留首个条目其它字段
            by_name[n]["applies_to"].extend(e["applies_to"])
        else:
            by_name[n] = e
    merged = list(by_name.values())

    return {
        "_warning": "⚠️ 由 tools/sync-manifest.py 自动生成,禁止手改。开发者请编辑 versions/<v>/version.yaml",
        "manifest_version": 1,
        "generated_at": now,
        "generated_by": "tools/sync-manifest.py",
        "patches": merged,
    }


def build_whitelist_manifest(patches_manifest: dict) -> dict:
    """规范 §4.3 + 附录 B: 仓根 WHITELIST.yaml"""
    now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    items = []
    for p in patches_manifest["patches"]:
        if not p["whitelist"]:
            continue
        reason = p["whitelist_reason"] or ""
        if len(reason.strip()) < 30:
            # 跳过 reason 不合格的,whitelist-audit 会标出
            continue
        items.append({
            "id": p["id"],
            "name": p["name"],
            "reason": reason.strip(),
            "applies_to": [a["version"] for a in p["applies_to"]],
            "first_whitelisted": now[:10],  # 占位
            "next_review": "2026-09-15",  # 季度评审 (规范 §4.4)
        })
    return {
        "_warning": "⚠️ 由 tools/sync-manifest.py 自动生成,禁止手改。开发者请在 version.yaml 设 status: whitelisted + whitelist_reason",
        "generated_at": now,
        "whitelist": items,
    }


def build_status_report(patches_manifest: dict) -> str:
    """规范 §4.3: docs/PATCHES-STATUS.md"""
    now = patches_manifest["generated_at"]
    by_status = defaultdict(int)
    for p in patches_manifest["patches"]:
        by_status[p["status"]] += 1
    total = len(patches_manifest["patches"])

    rows = []
    for p in patches_manifest["patches"]:
        versions = " / ".join(a["version"] for a in p["applies_to"])
        reason = p["whitelist_reason"] or "-"
        if len(reason) > 50:
            reason = reason[:47] + "..."
        rows.append(
            f"| `{p['name']}` | {p['status']} | {versions} | {reason} |"
        )

    body = f"""# Patch 状态仪表盘

> 自动生成,源:`tools/sync-manifest.py`
> 最近同步:`{now}`
> 总计:**{total} 个 patch**

## 状态码说明

| status | 含义 |
|---|---|
| `pending` | 暂未提交上游 |
| `submitted` | 已提交上游 PR,等待审核 |
| `accepted` | 已合入 upstream |
| `rejected` | 上游拒绝合入 |
| `whitelisted` | 永久携带,不再追求上游合入 |

## 状态分布

""" + "\n".join(f"- **{k}**: {v}" for k, v in sorted(by_status.items())) + f"""

## 全量 patch 列表

| patch.name | status | 跨版本 | whitelist_reason |
|---|---|---|---|
""" + "\n".join(rows) + """

## 季度评审

- 下一个评审日:**2026-09-15**
- 评审范围:所有 `status: whitelisted` 的 patch
- 工具:`python3 tools/whitelist-audit.py`
"""
    return body


def validate_versions(versions: list[dict]) -> list[str]:
    """规范 §1.3 / §1.4: 字段校验"""
    errs = []
    for v in versions:
        path = v.get("_path", "?")
        vid = v.get("version_id", "")
        if not vid:
            errs.append(f"{path}: missing version_id")
        if not v.get("owner"):
            errs.append(f"{path}: missing owner")
        if v.get("demo"):
            # demo: 允许 patches: []
            if v.get("patches"):
                errs.append(f"{path}: demo version 不应有 patches[] (移到非 demo 目录)")
            continue
        ub = v.get("upstream_base", {}) or {}
        if not ub.get("repo"):
            errs.append(f"{path}: missing upstream_base.repo")
        if not ub.get("commit"):
            errs.append(f"{path}: missing upstream_base.commit")
        for i, p in enumerate(v.get("patches", []) or []):
            pname = p.get("name", "")
            t = p.get("type", "")
            s = p.get("status", "")
            if t not in TYPE_ENUM:
                errs.append(f"{path}: patches[{i}].type={t!r} not in {sorted(TYPE_ENUM)}")
            if s not in STATUS_ENUM:
                errs.append(f"{path}: patches[{i}].status={s!r} not in {sorted(STATUS_ENUM)}")
            if not p.get("name"):
                errs.append(f"{path}: patches[{i}].name missing")
            if s in ("submitted", "accepted") and not p.get("upstream_pr"):
                errs.append(f"{path}: {pname}.status={s} but upstream_pr[] empty (§1.4)")
            if s == "whitelisted":
                reason = (p.get("whitelist_reason") or "").strip()
                if len(reason) < 30:
                    errs.append(f"{path}: {pname}.status=whitelisted but whitelist_reason <30 chars (§1.4)")
            if s == "rejected" and not (p.get("whitelist_reason") or "").strip():
                errs.append(f"{path}: {pname}.status=rejected but whitelist_reason (reject reason) empty (§1.4)")
    return errs


def render_yaml(obj: dict) -> str:
    return yaml.safe_dump(obj, allow_unicode=True, sort_keys=False, default_flow_style=False)


def strip_volatile(obj):
    """去掉 _warning / generated_at 等不稳定字段,用于 --check 比对。

    规范 §2.4: 校验只看结构与字段值是否一致,不看时间戳(否则每次 CI 必 drift)。
    """
    if isinstance(obj, dict):
        return {k: strip_volatile(v) for k, v in obj.items() if k not in {"generated_at"}}
    if isinstance(obj, list):
        return [strip_volatile(v) for v in obj]
    return obj


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="CI drift 检测")
    ap.add_argument("--write", action="store_true", help="写回所有自动文件")
    ap.add_argument("--report", action="store_true", help="只打印人读报表")
    args = ap.parse_args()

    versions = collect_versions()
    errs = validate_versions(versions)
    if errs:
        print("=== version.yaml 字段校验失败 (§1.3 / §1.4) ===", file=sys.stderr)
        for e in errs:
            print(f"  ✗ {e}", file=sys.stderr)
        return 2

    patches_manifest = build_patches_manifest(versions)
    whitelist_manifest = build_whitelist_manifest(patches_manifest)
    status_report = build_status_report(patches_manifest)

    if args.report:
        print(status_report)
        return 0

    target_patches = ROOT / "PATCHES.yaml"
    target_whitelist = ROOT / "WHITELIST.yaml"
    target_status = ROOT / "docs" / "PATCHES-STATUS.md"

    if args.write:
        target_patches.write_text(render_yaml(patches_manifest), encoding="utf-8")
        target_whitelist.write_text(render_yaml(whitelist_manifest), encoding="utf-8")
        target_status.parent.mkdir(parents=True, exist_ok=True)
        target_status.write_text(status_report, encoding="utf-8")
        print(f"✓ wrote {target_patches.relative_to(ROOT)}")
        print(f"✓ wrote {target_whitelist.relative_to(ROOT)}")
        print(f"✓ wrote {target_status.relative_to(ROOT)}")
        return 0

    if args.check:
        # 规范 §2.4: 校验结构与字段一致性,不看时间戳(否则每次 CI 必 drift)
        drift = []
        for tgt, content in [
            (target_patches, render_yaml(strip_volatile(patches_manifest))),
            (target_whitelist, render_yaml(strip_volatile(whitelist_manifest))),
        ]:
            if not tgt.exists():
                drift.append(f"missing: {tgt.relative_to(ROOT)}")
            else:
                # 现有文件也剥掉 generated_at 再比
                try:
                    existing = yaml.safe_load(tgt.read_text(encoding="utf-8"))
                except Exception:
                    drift.append(f"parse error: {tgt.relative_to(ROOT)}")
                    continue
                existing_norm = yaml.safe_dump(strip_volatile(existing), allow_unicode=True, sort_keys=False)
                if existing_norm != content:
                    drift.append(f"drift: {tgt.relative_to(ROOT)}")
        # docs/PATCHES-STATUS.md 是人读报告,只比除去 "最近同步" 行的内容
        if not target_status.exists():
            drift.append(f"missing: {target_status.relative_to(ROOT)}")
        else:
            cur_lines = [l for l in target_status.read_text(encoding="utf-8").splitlines() if not l.startswith("> 最近同步")]
            new_lines = [l for l in status_report.splitlines() if not l.startswith("> 最近同步")]
            if "\n".join(cur_lines) != "\n".join(new_lines):
                drift.append(f"drift: {target_status.relative_to(ROOT)}")
        if drift:
            print("=== sync-manifest drift 检测 (§2.4) ===", file=sys.stderr)
            for d in drift:
                print(f"  ✗ {d}", file=sys.stderr)
            print("", file=sys.stderr)
            print("修复: python3 tools/sync-manifest.py --write", file=sys.stderr)
            print("      git add PATCHES.yaml WHITELIST.yaml docs/PATCHES-STATUS.md", file=sys.stderr)
            print("      git commit -m 'manifest: auto-sync from version.yaml'", file=sys.stderr)
            return 1
        print("✓ sync-manifest --check: PATCHES.yaml / WHITELIST.yaml / docs/PATCHES-STATUS.md 与 version.yaml 一致 (忽略时间戳)")
        return 0

    ap.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
