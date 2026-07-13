#!/usr/bin/env python3
"""series check —— versions/<v>/series 与 patches/ 一致性"""
import sys
from pathlib import Path

def main(repo=sys.argv[1] if len(sys.argv) > 1 else "."):
    root = Path(repo)
    errs = 0
    vdirs = list(root.glob("versions/*"))
    if not vdirs:
        print("  ! no versions/*/ — 新仓 skip")
        return 0
    for vdir in sorted(vdirs):
        vname = vdir.name
        series = vdir / "series"
        patdir = vdir / "patches"
        if not series.exists():
            print(f"  ! {vname}/ no series — 跳")
            continue
        declared = [l.strip() for l in series.read_text().splitlines()
                    if l.strip() and not l.startswith("#")]
        actual   = sorted([p.name for p in patdir.glob("*.patch")])
        declared_set = sorted(declared)
        if declared_set != actual:
            print(f"  ✗ {vname}: series 声明 {len(declared_set)} != 实际 {len(actual)}")
            only_s = set(declared_set) - set(actual)
            only_a = set(actual) - set(declared_set)
            for n in sorted(only_s): print(f"    only in series: {n}")
            for n in sorted(only_a): print(f"    only in patches/: {n}")
            errs += 1
        else:
            print(f"  ✓ {vname}: {len(actual)} 一致")
    return 1 if errs else 0

if __name__ == "__main__":
    sys.exit(main())
