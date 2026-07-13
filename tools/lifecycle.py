#!/usr/bin/env python3
"""lifecycle —— patch 7 状态转换工具。

用法:
  python tools/lifecycle.py status                                  列出所有 patch 当前状态
  python tools/lifecycle.py <patch-id> <new-status>                 转换状态
  python tools/lifecycle.py <patch-id> mark-rebased <date>          标 last_rebased_at
  python tools/lifecycle.py <patch-id> link-upstream-pr <pr-url>    记录上游 PR

7 状态机(v5 §5):
  New              patch 已 commit 但未通过 apply
  Validated        apply 干净 + build 通过
  Submitted-Upstream  PR 已发上游
  Upstream-Accepted   上游合入
  Downstream-Only     长期内部维护(不走上游)
  Deprecated          等待删除
  Removed            终态(文件已删)

合法转换:
  New            -> Validated | Deprecated
  Validated      -> Submitted-Upstream | Downstream-Only | Deprecated
  Submitted-Upstream -> Upstream-Accepted | Deprecated (PR 关闭)
  Upstream-Accepted  -> Deprecated
  Downstream-Only    -> Deprecated
  Deprecated         -> Removed
  *                  -> Removed (admin override,需 --force)
"""
import sys, re, datetime
from pathlib import Path
try:
    import yaml
except ImportError:
    print("  ! pyyaml 未装,无法使用 lifecycle.py")
    sys.exit(1)

ROOT = Path(".").resolve()

VALID_STATES = {
    "New", "Validated", "Submitted-Upstream", "Upstream-Accepted",
    "Downstream-Only", "Deprecated", "Removed"
}
LEGAL_TRANSITIONS = {
    "New":                {"Validated", "Deprecated"},
    "Validated":          {"Submitted-Upstream", "Downstream-Only", "Deprecated"},
    "Submitted-Upstream": {"Upstream-Accepted", "Validated", "Deprecated"},  # PR 关闭退回 Validated
    "Upstream-Accepted":  {"Deprecated"},
    "Downstream-Only":    {"Deprecated"},
    "Deprecated":         {"Removed"},
    "Removed":            set(),  # 终态
}

def find_metadata(patch_id):
    """根据 patch_id 找到 metadata yaml 文件路径。
    支持: full id (redis-7.0.15-0001) / short id (0001) / filename base (0001-hw-kunpeng-adapt-iouring)
    """
    for vdir in sorted(ROOT.glob("versions/*")):
        if not vdir.is_dir(): continue
        mdir = vdir / "metadata"
        if not mdir.exists(): continue
        for yp in mdir.glob("*.yaml"):
            try:
                m = yaml.safe_load(yp.read_text())
            except Exception:
                continue
            if m and (m.get("id") == patch_id
                      or yp.stem == patch_id
                      or yp.stem.startswith(patch_id + "-")):
                return yp, m
    return None, None

def cmd_status():
    """列出所有 patch 当前状态"""
    rows = []
    for vdir in sorted(ROOT.glob("versions/*")):
        if not vdir.is_dir(): continue
        mdir = vdir / "metadata"
        if not mdir.exists(): continue
        for yp in sorted(mdir.glob("*.yaml")):
            try:
                m = yaml.safe_load(yp.read_text())
            except Exception as e:
                rows.append((yp.parent.parent.name, yp.stem, f"❌ YAML: {e}", "-", "-"))
                continue
            if not m: continue
            vname = yp.parent.parent.name

            def m_yr(v):
                """把 date/datetime/None 转成 YYYY-MM-DD 字符串"""
                if v is None: return "-"
                if hasattr(v, "isoformat"): return v.isoformat()[:10]
                return str(v)

            rows.append((
                vname,
                m_yr(m.get("id", "?")),
                m_yr(m.get("status", "?")),
                m_yr(m.get("last_rebased_at", "-")),
                m_yr(m.get("upstream", {}).get("status", "-") if isinstance(m.get("upstream"), dict) else "-"),
            ))
    if not rows:
        print("  (无 patch)")
        return 0
    print(f"{'VERSION':<15} {'ID':<25} {'STATUS':<20} {'LAST_REBASED':<14} {'UPSTREAM':<20}")
    print("-" * 100)
    for r in rows:
        print(f"{r[0]:<15} {r[1]:<25} {r[2]:<20} {r[3]:<14} {r[4]:<20}")
    return 0

def cmd_set(patch_id, new_status, force=False):
    """设置 patch 的新状态,自动校验合法转换"""
    if new_status not in VALID_STATES:
        print(f"  ✗ 非法状态: {new_status}")
        print(f"  合法值: {', '.join(sorted(VALID_STATES))}")
        return 1
    yp, m = find_metadata(patch_id)
    if not yp:
        print(f"  ✗ 找不到 patch: {patch_id}")
        return 1
    cur = m.get("status", "New")
    if cur == new_status:
        print(f"  ! 已经是 {cur},无需变更")
        return 0
    legal = LEGAL_TRANSITIONS.get(cur, set())
    if new_status not in legal and not force:
        print(f"  ✗ 非法转换: {cur} -> {new_status}")
        print(f"  合法下一状态: {', '.join(sorted(legal)) or '(终态,无下一态)'}")
        print(f"  强制转换请加 --force(将跳过校验,直接写入)")
        return 1
    m["status"] = new_status
    yp.write_text(yaml.safe_dump(m, sort_keys=False, allow_unicode=True, default_flow_style=False))
    print(f"  ✓ {yp.relative_to(ROOT)}: {cur} -> {new_status}")
    # 状态转换后续动作提示
    if new_status == "Submitted-Upstream":
        print(f"  → 后续: 填 metadata.upstream.pr = <url>(如未填),等 CI 跑通")
    elif new_status == "Upstream-Accepted":
        print(f"  → 后续: 填 metadata.upstream.upstream_commit = <sha>,准备下个版本 rebase")
    elif new_status == "Deprecated":
        cond = m.get("remove_when", {}).get("condition", "未填")
        print(f"  → 后续: 满足条件后跑 bash tools/retire.sh {patch_id}")
    elif new_status == "Removed":
        print(f"  → 终态: 应已通过 retire.sh 删除了文件,本工具不再操作文件")
    return 0

def cmd_mark_rebased(patch_id, date_str):
    """标 last_rebased_at"""
    # 校验日期
    try:
        datetime.date.fromisoformat(date_str)
    except ValueError:
        print(f"  ✗ 日期格式不对: {date_str} (期望 YYYY-MM-DD)")
        return 1
    yp, m = find_metadata(patch_id)
    if not yp:
        print(f"  ✗ 找不到 patch: {patch_id}")
        return 1
    m["last_rebased_at"] = date_str
    yp.write_text(yaml.safe_dump(m, sort_keys=False, allow_unicode=True, default_flow_style=False))
    print(f"  ✓ {yp.relative_to(ROOT)}: last_rebased_at = {date_str}")
    return 0

def cmd_link_pr(patch_id, pr_url):
    """记录上游 PR 链接"""
    yp, m = find_metadata(patch_id)
    if not yp:
        print(f"  ✗ 找不到 patch: {patch_id}")
        return 1
    if "upstream" not in m or not isinstance(m["upstream"], dict):
        m["upstream"] = {}
    m["upstream"]["pr"] = pr_url
    m["upstream"]["status"] = "Submitted-Upstream"
    m["status"] = "Submitted-Upstream"
    yp.write_text(yaml.safe_dump(m, sort_keys=False, allow_unicode=True, default_flow_style=False))
    print(f"  ✓ {yp.relative_to(ROOT)}: upstream.pr = {pr_url}, status -> Submitted-Upstream")
    return 0

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    cmd = sys.argv[1]
    if cmd == "status":
        return cmd_status()
    if cmd == "mark-rebased":
        if len(sys.argv) < 4:
            print("usage: lifecycle.py <patch-id> mark-rebased <YYYY-MM-DD>")
            return 1
        return cmd_mark_rebased(sys.argv[2], sys.argv[3])
    if cmd == "link-upstream-pr":
        if len(sys.argv) < 4:
            print("usage: lifecycle.py <patch-id> link-upstream-pr <pr-url>")
            return 1
        return cmd_link_pr(sys.argv[2], sys.argv[3])
    # 否则认为是 <patch-id> <new-status> [--force]
    if len(sys.argv) < 3:
        print("usage: lifecycle.py <patch-id> <new-status> [--force]")
        return 1
    patch_id = sys.argv[1]
    new_status = sys.argv[2]
    force = "--force" in sys.argv[3:]
    return cmd_set(patch_id, new_status, force=force)

if __name__ == "__main__":
    sys.exit(main() or 0)
