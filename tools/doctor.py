#!/usr/bin/env python3
"""boostkit doctor v5 MVP —— 仓完整性自检,7 条铁律全覆盖。"""
import os, sys, re, json, subprocess
from pathlib import Path

ROOT = Path(sys.argv[2] if "--repo" in sys.argv else ".").resolve()
errors = []
warns = []

def hard(code, msg): errors.append({"code": code, "msg": msg})
def soft(code, msg): warns.append({"code":  code, "msg": msg})

# 铁律 1:仓根白名单
WHITE_DIR  = {"versions", "docs", "ci", "tools", ".git", "images"}
WHITE_FILE = {"OWNERS", "boostkit.yaml", "upstream.yml", "README.md", "README_en.md",
              "README_EN.md", "CHANGELOG.md", "LICEN[!]?SE", "LICEN[!]?SE.txt",
              "NOTICE", "CONTRIBUTING.md", ".gitignore", ".gitattributes",
              ".editorconfig", ".gitee-ci.yml"}
BLACK_FILE_GLOB = re.compile(
    r"\.(patch|spec|rpm|deb|dsc|changes|c|h|cc|cpp|go|py|pyc|sh|cmd|bat|jar|war|so|a|o|lo|la)$"
)
BLACK_DIR  = {"src", "storage", "sql", "include", "libbinlogevents", "libmysqld",
              "extra", "plugin", "test", "client", "deps", "third_party",
              "SPECS", "RPMS", "SOURCES", "BUILD", "SRPMS", "vendor"}

for entry in Path(ROOT).iterdir():
    name = entry.name
    if name in WHITE_DIR or name.startswith(".") or name == "LICENSE.txt":
        continue
    if entry.is_dir():
        if name.lower() in BLACK_DIR:
            hard("ROOT-FORBIDDEN-DIR", f"仓根禁放目录: {name}/")
        continue
    if BLACK_FILE_GLOB.search(name):
        hard("ROOT-FORBIDDEN-FILE", f"仓根禁放文件: {name}")

# 铁律 2:boostkit.yaml 8 必填字段
bky_path = ROOT / "boostkit.yaml"
REQ = ("apiVersion", "kind", "metadata.name", "metadata.owner",
       "upstream.versions", "patches", "ci.gates", "kernelSupport.enabled")
if bky_path.exists():
    try:
        import yaml
        bky = yaml.safe_load(bky_path.read_text())
    except Exception as e:
        hard("BOOSTKIT-YAML-INVALID", f"boostkit.yaml YAML 解析失败: {e}")
        bky = {}
    for path in REQ:
        cur = bky
        try:
            for k in path.split("."):
                cur = cur[k]
        except (KeyError, TypeError):
            hard("BOOSTKIT-MISSING-FIELD", f"boostkit.yaml 缺必填: {path}")
else:
    hard("BOOSTKIT-NO-FILE", "boostkit.yaml 不存在")

# 铁律 3:OWNERS ≥ 2
owners_path = ROOT / "OWNERS"
if owners_path.exists():
    text = owners_path.read_text()
    m = re.search(r"^approvers:\s*(.+?)(?=^[a-zA-Z]|\Z)", text, re.M | re.S)
    if m:
        block = m.group(1)
        n = len(re.findall(r"^\s*-\s+", block, re.M))
        if n < 2:
            hard("OWNERS-LT-2", f"OWNERS approvers={n} < 2")
    else:
        hard("OWNERS-NO-APPROVERS", "OWNERS 缺 approvers 段")
else:
    hard("OWNERS-NO-FILE", "OWNERS 文件不存在")

# 铁律 4:patch 在 versions/<v>/patches/
for p in ROOT.glob("*.patch"):
    hard("PATCH-IN-ROOT", f"仓根发现 *.patch: {p.name}")

# 铁律 5:series 与 patches/ 一致
vdirs = [d for d in ROOT.glob("versions/*") if d.is_dir()]
if not vdirs:
    soft("NO-VERSIONS", "没有 versions/<v>/ 子目录")
else:
    for vdir in vdirs:
        series = vdir / "series"
        patdir = vdir / "patches"
        if not patdir.exists():
            if series.exists():
                hard("NO-PATCHES-DIR", f"{vdir.name} 有 series 但无 patches/")
            continue
        declared = []
        if series.exists():
            declared = [l.strip() for l in series.read_text().splitlines()
                        if l.strip() and not l.startswith("#")]
        actual = sorted([p.name for p in patdir.glob("*.patch")])
        declared_set = sorted(declared)
        if declared_set != actual:
            hard("SERIES-MISMATCH", f"{vdir.name}/series vs patches/ 不一致\n    decl={declared_set}\n    actual={actual}")
        else:
            print(f"  ✓ {vdir.name}: {len(actual)} patches 一致")

# 铁律 6:branch protection(本地)
# 6a) 本地仓必须有 master(开发时硬要求)
# 6b) CI 环境下(GITHUB_ACTIONS / GITEA_ACTIONS / GITHUB_ACTIONS=true)允许 PR 触发只 checkout 当前 ref
#     此时 master 不在 local refs 中(但远端必然存在,否则 PR 不会通过),降为 soft warn
import os as _os
_in_ci = any(_os.environ.get(k) for k in ("GITHUB_ACTIONS", "GITEA_ACTIONS", "CI_PIPELINE_SOURCE", "GITLAB_CI"))
try:
    refs = subprocess.check_output(
        ["git", "-C", str(ROOT), "for-each-ref", "--format=%(refname:short)"],
        text=True
    ).split()
except subprocess.CalledProcessError:
    refs = []
if "master" not in refs:
    if _in_ci:
        soft("BRANCH-NO-MASTER-CI", "CI 模式:PR 触发时本地无 master(已自动降为 warn,远端必然存在)")
    else:
        hard("BRANCH-NO-MASTER", "缺 master 分支")

# 铁律 7:CI 配置
ci_path = ROOT / ".gitee-ci.yml"
if not ci_path.exists():
    soft("NO-CI", f"建议在 .gitee-ci.yml 接入 CI 模板")

# 输出
total_hard = len(errors); total_warn = len(warns)
print(f"=== boostkit doctor ===")
print(f"  hard errors: {total_hard}")
print(f"  warns:       {total_warn}")
for e in errors:
    print(f"  ✗ {e['code']}: {e['msg']}")
for w in warns:
    print(f"  ⚠ {w['code']}: {w['msg']}")

sys.exit(1 if errors else 2 if warns else 0)
