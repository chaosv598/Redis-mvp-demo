#!/usr/bin/env python3
"""check-deps —— 校验 metadata 的 applies_on_top 与 series 顺序是否一致。

校验规则(每个 versions/<v>/ 目录):
  1. series 中每个 patch 必须有同名 metadata
  2. metadata 中 applies_on_top 列表里的 patch id,必须出现在 series 中更早的位置
  3. metadata 中 applies_on_top 列表里的 patch id,必须真实存在
  4. 不允许循环依赖(A 在 B 前,B 也在 A 前)

退出码: 0 全过 / 1 有 hard error / 2 有 warn
"""
import sys, re
from pathlib import Path
try:
    import yaml
except ImportError:
    print("  ! pyyaml 未装,跳过", file=sys.stderr)
    sys.exit(0)

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
errors = []
warns = []

def hard(code, msg): errors.append((code, msg))
def soft(code, msg): warns.append((code, msg))

# 解析 series 文件,返回 [patch_filename, ...] 顺序
def parse_series(series_path):
    if not series_path.exists():
        return []
    return [l.strip() for l in series_path.read_text().splitlines()
            if l.strip() and not l.startswith("#")]

# 从 filename "0001-hw-kunpeng-adapt-iouring.patch" 提取 id "0001"
def filename_to_id(fname):
    m = re.match(r"^(\d{4})-", fname)
    return m.group(1) if m else fname.split("-")[0]

# 解析 metadata yaml
def parse_metadata(meta_path):
    if not meta_path.exists():
        return None
    try:
        return yaml.safe_load(meta_path.read_text())
    except Exception as e:
        hard("META-YAML-INVALID", f"{meta_path.name} YAML 解析失败: {e}")
        return None

# 对每个版本目录做校验
vdirs = sorted([d for d in ROOT.glob("versions/*") if d.is_dir()])
if not vdirs:
    print("  ! no versions/*/ — 新仓 skip")
    sys.exit(0)

for vdir in vdirs:
    vname = vdir.name
    series_list = parse_series(vdir / "series")
    if not series_list:
        continue
    meta_dir = vdir / "metadata"
    if not meta_dir.exists():
        hard("NO-METADATA-DIR", f"{vname}/ 无 metadata/ 目录")
        continue

    # 把 series 中的每个 patch 位置编号(同时支持 short id 和 full id)
    pos_of = {}  # full_id 或 short_id -> position
    series_fname_to_id = {}  # filename -> full_id
    for idx, fname in enumerate(series_list):
        base = fname[:-len(".patch")]
        short_id = filename_to_id(fname)
        pos_of[short_id] = idx  # 短 id (0001)
        # full id 暂时不知道,要等 metadata 解析完

    # 先把所有 metadata 解析,得到 full id
    metas = {}  # full_id -> metadata
    fname_of_id = {}  # full_id -> filename
    for idx, fname in enumerate(series_list):  # 补 enumerate
        base = fname[:-len(".patch")]
        m = parse_metadata(meta_dir / f"{base}.yaml")
        if m is None:
            hard("META-MISSING", f"{vname}/{base}.yaml 缺失")
            continue
        if "id" not in m:
            hard("META-NO-ID", f"{vname}/{base}.yaml 缺 id 字段")
            continue
        full_id = m["id"]
        metas[full_id] = m
        fname_of_id[full_id] = fname
        pos_of[full_id] = idx  # 直接用 idx,不用 pos_of[short_id]

    # 规则 1: 每个 series patch 有 metadata(已通过 metas 检查)

    # 规则 2: applies_on_top 里每个依赖必须出现在 series 中更早位置
    # 规则 3: 依赖必须真实存在
    # 规则 4: 不能循环
    for fname in series_list:
        base = fname[:-len(".patch")]
        m = parse_metadata(meta_dir / f"{base}.yaml")
        if m is None:
            continue
        pid = m.get("id")
        deps = m.get("applies_on_top", []) or []
        my_pos = pos_of.get(pid)

        for dep in deps:
            # dep 可能是: 完整 id (redis-7.0.15-0001) / 短 id (0001) / filename (0001-...patch)
            dep_id = None
            if dep in pos_of:
                dep_id = dep
            elif dep in series_list:
                dep_id = filename_to_id(dep)  # filename -> 短 id,再查 pos_of
                if dep_id not in pos_of:
                    # 短 id 不在,说明是 filename 但没有 short id 对应,失败
                    hard("DEP-NOT-IN-SERIES", f"{vname}/{base}.yaml: applies_on_top 引用了不存在的 patch: {dep}")
                    continue
                dep_id = dep_id
            else:
                hard("DEP-NOT-IN-SERIES", f"{vname}/{base}.yaml: applies_on_top 引用了不存在的 patch: {dep}")
                continue

            dep_pos = pos_of[dep_id]
            if my_pos is not None and dep_pos >= my_pos:
                hard("DEP-AFTER-SELF",
                     f"{vname}/{base}.yaml: applies_on_top 引用了排在自身之后的 patch: {dep} (pos {dep_pos} >= {my_pos})")
            else:
                print(f"  ✓ {vname}/{base}: 依赖 {dep_id} 在 pos {dep_pos} (< {my_pos})")

    # 规则 4: 简单循环检测(DFS)
    # 对每个 id 跑一遍,看 visited 集合
    def has_cycle(start_id, visited, stack):
        visited.add(start_id)
        stack.add(start_id)
        m = metas.get(start_id)
        if not m: return False
        for dep in (m.get("applies_on_top") or []):
            dep_id = dep if dep in pos_of else filename_to_id(dep) if dep in series_list else dep
            if dep_id not in pos_of: continue
            if dep_id in stack:
                return True  # 找到环
            if dep_id not in visited and has_cycle(dep_id, visited, stack):
                return True
        stack.discard(start_id)
        return False

    visited, stack = set(), set()
    for pid in metas:
        if pid not in visited:
            if has_cycle(pid, visited, stack):
                hard("CYCLE", f"{vname}/ 存在循环依赖,涉及 {pid}")
                break  # 一个环就够报错

# 输出
print(f"=== boostkit check-deps ===")
print(f"  hard errors: {len(errors)}")
print(f"  warns:       {len(warns)}")
for c, m in errors:
    print(f"  ✗ {c}: {m}")
for c, m in warns:
    print(f"  ⚠ {c}: {m}")
sys.exit(1 if errors else 2 if warns else 0)
