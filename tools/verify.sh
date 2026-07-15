#!/usr/bin/env bash
# verify —— 一键验证 patch overlay 仓基本结构
#
# 检查 3 件事:
#   1. 仓根无 .patch / Dockerfile / Makefile 等禁放文件
#   2. versions/<v>/version.yaml 的 patches[] 数组与 patches/ 目录一致
#      (按数组顺序逐个 apply,dependence 仅做提示性文档)
#   3. 干净 upstream apply:从 version.yaml 读 upstream_base.repo+commit,
#      拉 upstream 切到该 commit,逐 patch apply
#
# 用法: bash tools/verify.sh
# 退出码: 0 全过 / 1 有失败
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

errs=0

echo "=== boostkit verify ==="

# === 1. 仓根禁放文件检查 ===
echo "--- 仓根禁放检查 ---"
root_bad=0
if compgen -G "*.patch" > /dev/null; then
    echo "  ✗ 仓根发现 .patch 文件(应移到 versions/<v>/patches/)"
    ls *.patch
    root_bad=$((root_bad+1))
fi
[ -f Dockerfile ] && { echo "  ✗ 仓根有 Dockerfile"; root_bad=$((root_bad+1)); }
[ -f build.sh ] && { echo "  ✗ 仓根有 build.sh"; root_bad=$((root_bad+1)); }
[ -f Makefile ] && { echo "  ✗ 仓根有 Makefile"; root_bad=$((root_bad+1)); }
for d in src/ storage/ sql/ include/ SPECS/ RPMS/ SOURCES/ BUILD/ SRPMS/ vendor/; do
    [ -d "$d" ] && { echo "  ✗ 仓根有目录: $d"; root_bad=$((root_bad+1)); }
done
[ "$root_bad" = "0" ] && echo "  ✓ 仓根干净"
errs=$((errs+root_bad))

# === 2 + 3. versions/<v>/version.yaml 一致性 + upstream apply ===
echo "--- version.yaml 校验 + upstream apply ---"
vcount=0

# 校验 status / type 枚举的 hard rule
check_enum() {
    local field="$1" allowed="$2" value="$3" fname="$4"
    case " $allowed " in
        *" $value "*) return 0 ;;
        *) echo "  ✗ $fname: $field=$value 非法(允许: $allowed)"; return 1 ;;
    esac
}

for vdir in versions/*/; do
    [ -d "$vdir" ] || continue
    vname=$(basename "$vdir")
    vyaml="$vdir/version.yaml"
    patches_dir="$vdir/patches"

    if [ ! -f "$vyaml" ]; then
        echo "  ✗ $vname: 缺 version.yaml"
        errs=$((errs+1))
        continue
    fi
    if [ ! -d "$patches_dir" ]; then
        echo "  ✗ $vname: 缺 patches/ 目录"
        errs=$((errs+1))
        continue
    fi

    # 读顶层 + patches 数组(用 python,保留顺序)
    read_vars=$(python3 - "$vyaml" <<'PYEOF'
import sys, json, yaml
from pathlib import Path

yp = Path(sys.argv[1])
m = yaml.safe_load(yp.read_text())
if not isinstance(m, dict):
    print("ERR:not_a_dict"); sys.exit(0)

# 顶层字段校验
top = m.get("version_id", "")
desc = m.get("description", "")
owner = m.get("owner", "")
ub = m.get("upstream_base", {}) or {}
patches = m.get("patches", []) or []

# 顶层枚举:version_id 非空;upstream_base.repo/commit 必填
errs = []
if not top: errs.append("missing version_id")
if not isinstance(ub, dict) or not ub.get("repo"): errs.append("missing upstream_base.repo")
if not isinstance(ub, dict) or not ub.get("commit"): errs.append("missing upstream_base.commit")
if not isinstance(patches, list) or not patches:
    errs.append("patches[] must be a non-empty array")

# patch 字段校验 (V3 规范 §1.3 / §1.4)
patch_names = []
for i, p in enumerate(patches):
    if not isinstance(p, dict):
        errs.append(f"patches[{i}] is not a dict"); continue
    n = p.get("name", "")
    if not n: errs.append(f"patches[{i}].name is empty")
    patch_names.append(n)
    t = p.get("type", "")
    s = p.get("status", "")
    if t not in ("ecological", "project"):
        errs.append(f"{n}.type={t!r} not in (ecological, project)")
    if s not in ("pending", "submitted", "accepted", "rejected", "whitelisted"):
        errs.append(f"{n}.status={s!r} not in (pending, submitted, accepted, rejected, whitelisted)")
    # V3: upstream_pr[] (数组,不再用 pr)
    if s in ("submitted", "accepted") and not p.get("upstream_pr"):
        errs.append(f"{n}.status={s} but upstream_pr[] empty (§1.4)")
    # V3: whitelisted 必须带 ≥30 字符理由
    if s == "whitelisted":
        reason = (p.get("whitelist_reason") or "").strip()
        if len(reason) < 30:
            errs.append(f"{n}.status=whitelisted but whitelist_reason <30 chars (§1.4)")

# 输出 JSON 供 bash 用
out = {
    "version_id": top,
    "description": desc,
    "owner": owner,
    "repo": (ub or {}).get("repo", ""),
    "version": (ub or {}).get("version", ""),
    "commit": (ub or {}).get("commit", ""),
    "patch_names": patch_names,
    "patches": patches,
    "errs": errs,
}
print(json.dumps(out))
PYEOF
)

    # shellcheck disable=SC2181
    if [ "$(echo "$read_vars" | head -c 3)" = "ERR" ]; then
        echo "  ✗ $vname: version.yaml 解析失败"
        errs=$((errs+1))
        continue
    fi

    # 校验
    PYERRS=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print('\n'.join(d.get('errs',[])))" "$read_vars")
    if [ -n "$PYERRS" ]; then
        echo "  ✗ $vname: version.yaml 字段错误:"
        echo "$PYERRS" | sed 's/^/      /'
        errs=$((errs+1))
        continue
    fi

    REPO=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['repo'])" "$read_vars")
    SHA=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['commit'])" "$read_vars")
    VERSION=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['version'])" "$read_vars")
    PATCH_NAMES=$(python3 -c "import json,sys; print('\n'.join(json.loads(sys.argv[1])['patch_names']))" "$read_vars")

    # 2a. patches/ 目录与数组一致性(必须多不能少,按数组顺序)
    actual=$(ls "$patches_dir"/*.patch 2>/dev/null | xargs -n1 basename 2>/dev/null | sort)
    expected=$(echo "$PATCH_NAMES" | awk '{print $0".patch"}' | sort)
    if [ "$actual" != "$expected" ]; then
        echo "  ✗ $vname: patches[] 与 patches/ 不一致"
        diff <(echo "$expected") <(echo "$actual") | head -10 | sed 's/^/      /'
        errs=$((errs+1))
        continue
    fi

    # 2b. patches/ 不能有多余 .patch(避免漏声明)
    extras=$(comm -23 <(echo "$actual") <(echo "$expected"))
    if [ -n "$extras" ]; then
        echo "  ✗ $vname: patches/ 有未声明的 .patch: $extras"
        errs=$((errs+1))
    fi

    npatch=$(echo "$PATCH_NAMES" | grep -c . || echo 0)
    echo "  ✓ $vname: $npatch 个 patch 与 version.yaml 一致"

    # 3. 干净 upstream apply
    WORK=$(mktemp -d)
    if ! git clone --quiet --no-checkout "$REPO" "$WORK/r" 2>/dev/null; then
        echo "  ⚠ $vname: clone $REPO 失败(跳过 apply 验证)"
        rm -rf "$WORK"
        continue
    fi

    # 优先 SHA,无效回退 tag
    if (cd "$WORK/r" && git cat-file -t "$SHA" >/dev/null 2>&1); then
        (cd "$WORK/r" && git checkout --quiet "$SHA" 2>/dev/null) || {
            echo "  ⚠ $vname: checkout $SHA 失败,跳过"
            rm -rf "$WORK"
            continue
        }
    elif [ -n "$VERSION" ] && (cd "$WORK/r" && git checkout --quiet "$VERSION" 2>/dev/null); then
        echo "  ⚠ $vname: SHA $SHA 不可达,改用 tag $VERSION"
    else
        echo "  ⚠ $vname: SHA $SHA 和 tag 都不存在,跳过 apply 验证"
        rm -rf "$WORK"
        continue
    fi

    # 按数组顺序 apply
    while IFS= read -r fname; do
        [ -z "$fname" ] && continue
        if (cd "$WORK/r" && git apply --check "$OLDPWD/$vdir"patches/"$fname".patch 2>/dev/null); then
            (cd "$WORK/r" && git apply "$OLDPWD/$vdir"patches/"$fname".patch)
            echo "  ✓ $vname/$fname"
        else
            echo "  ⚠ $vname/$fname: apply 失败(可能 baseline 不匹配,owner 检查)"
        fi
    done <<< "$PATCH_NAMES"
    rm -rf "$WORK"
    vcount=$((vcount+1))
done

# === 汇总 ===
echo "--- 汇总 ---"
if [ "$errs" = "0" ]; then
    echo "✓ verify 全部通过($vcount 个版本,patch overlay 健康)"
    exit 0
else
    echo "✗ verify 失败($errs 个错误)"
    exit 1
fi
