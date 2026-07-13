#!/usr/bin/env python3
"""OWNERS ≥ 2 校验。"""
import sys, re
text = open(sys.argv[1]).read()
m = re.search(r"^approvers:\s*(.+?)(?=^[a-zA-Z]|\Z)", text, re.M | re.S)
n = len(re.findall(r"^\s*-\s+", m.group(1), re.M)) if m else 0
print(f"  OWNERS approvers: {n}")
sys.exit(0 if n >= 2 else 1)
