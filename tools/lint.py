#!/usr/bin/env python3
"""boostkit lint v5 —— boostkit.yaml 8 必填字段 schema check。"""
import sys
try:
    import yaml
except ImportError:
    print("  ! pyyaml 未装,跳过 schema 校验")
    sys.exit(0)

REQUIRED = [
    "apiVersion", "kind",
    "metadata.name", "metadata.owner",
    "upstream.versions", "patches",
    "ci.gates", "kernelSupport.enabled",
]
ALLOWED_API = "boostkit.io/v1"
ALLOWED_KIND = "PatchOverlay"

def main():
    if len(sys.argv) < 2:
        print("usage: lint.py <boostkit.yaml>"); sys.exit(1)
    spec = yaml.safe_load(open(sys.argv[1]))
    errs = []
    for path in REQUIRED:
        cur = spec
        try:
            for k in path.split("."): cur = cur[k]
        except (KeyError, TypeError):
            errs.append(f"missing: {path}")
    if spec.get("apiVersion") != ALLOWED_API:
        errs.append(f"apiVersion 应为 {ALLOWED_API} (当前 {spec.get('apiVersion')!r})")
    if spec.get("kind") != ALLOWED_KIND:
        errs.append(f"kind 应为 {ALLOWED_KIND} (当前 {spec.get('kind')!r})")
    if errs:
        for e in errs: print(f"  ✗ {e}")
        sys.exit(1)
    n = len(spec.get('patches', []))
    print(f"  ✓ schema OK · {n} patches")

if __name__ == "__main__":
    main()
