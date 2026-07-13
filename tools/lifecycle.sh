#!/usr/bin/env bash
# lifecycle —— 状态 + 退役管理
#
# 用法:
#   bash tools/lifecycle.sh list                       列出所有 patch
#   bash tools/lifecycle.sh show <id>                  查看一个 patch 的 metadata
#   bash tools/lifecycle.sh set <id> <status>          改状态
#   bash tools/lifecycle.sh retire <id>                退役(从 4 处删)
#   bash tools/lifecycle.sh link <id> <pr-url>         记录上游 PR(自动改 status=submitted)
#   bash tools/lifecycle.sh mark-rebased <id> <date>   标 rebase 日期
#
# 状态(简化为 4 个,原 7 状态机砍):
#   pending      patch 刚加入,未验证
#   validated    干净 apply 验证通过
#   submitted    已发上游 PR
#   accepted     上游已合入(等下次 rebase 时退役)
#   retired      终态(已 retire.sh 删文件)
#
# 合法转换:
#   pending     -> validated | retired
#   validated   -> submitted | pending | retired
#   submitted   -> accepted | validated | retired
#   accepted    -> retired
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION_LIST="versions"
VALID_STATUSES="pending validated submitted accepted retired"
LEGAL="
pending:validated,retired
validated:submitted,pending,retired
submitted:accepted,validated,retired
accepted:retired
"

find_meta() {
    # $1 = patch id (如 redis-7.0.15-0001) 或 base name (如 0001-...)
    local target="$1"
    for vdir in $VERSION_LIST/*/; do
        [ -d "$vdir" ] || continue
        for yp in "$vdir"metadata/*.yaml; do
            [ -f "$yp" ] || continue
            local id=$(awk '/^id:/{print $2; exit}' "$yp")
            local base=$(basename "$yp" .yaml)
            if [ "$id" = "$target" ] || [ "$base" = "$target" ] || echo "$base" | grep -q "^${target}-"; then
                echo "$yp"
                return 0
            fi
        done
    done
    return 1
}

is_legal() {
    # $1 = current, $2 = target
    echo "$LEGAL" | grep -q "^$1:$2"
}

cmd_list() {
    printf "%-15s %-25s %-12s %-12s\n" "VERSION" "ID" "STATUS" "UPSTREAM"
    echo "--------------------------------------------------------------"
    for vdir in $VERSION_LIST/*/; do
        [ -d "$vdir" ] || continue
        vname=$(basename "$vdir")
        for yp in "$vdir"metadata/*.yaml; do
            [ -f "$yp" ] || continue
            id=$(awk '/^id:/{print $2; exit}' "$yp")
            status=$(awk '/^  status:/{print $2; exit}' "$yp")
            up_pr=$(awk '/^  pr:/{print $2; exit}' "$yp")
            [ -z "$up_pr" ] && up_pr="-"
            printf "%-15s %-25s %-12s %-12s\n" "$vname" "$id" "$status" "$up_pr"
        done
    done
}

cmd_show() {
    local id="$1"
    local yp=$(find_meta "$id")
    [ -z "$yp" ] && { echo "  ✗ 找不到: $id"; exit 1; }
    echo "  $yp"
    cat "$yp"
}

cmd_set() {
    local id="$1" target="$2"
    local yp=$(find_meta "$id")
    [ -z "$yp" ] && { echo "  ✗ 找不到: $id"; exit 1; }
    # 用 python 改 yaml(保留注释和顺序)
    python3 - "$yp" "$target" <<'PYEOF'
import sys, re
from pathlib import Path
import yaml

yp = Path(sys.argv[1])
target = sys.argv[2]

text = yp.read_text()
m = yaml.safe_load(text)

# 合法状态校验
legal = {
    "pending":   {"validated", "retired"},
    "validated": {"submitted", "pending", "retired"},
    "submitted": {"accepted", "validated", "retired"},
    "accepted":  {"retired"},
    "retired":   set(),
}
cur = m.get("upstream_plan", {}).get("status", "pending")
if cur == target:
    print(f"  ! 已经是 {cur},无需变更")
    sys.exit(0)
if target not in legal.get(cur, set()):
    print(f"  ✗ 非法转换: {cur} -> {target}")
    print(f"  合法下一状态: {', '.join(sorted(legal.get(cur, set()))) or '(终态)'}")
    sys.exit(1)

if "upstream_plan" not in m or not isinstance(m["upstream_plan"], dict):
    m["upstream_plan"] = {}
m["upstream_plan"]["status"] = target

yp.write_text(yaml.safe_dump(m, sort_keys=False, allow_unicode=True, default_flow_style=False))
print(f"  ✓ {yp.name}: {cur} -> {target}")
PYEOF
}

cmd_link() {
    local id="$1" pr="$2"
    local yp=$(find_meta "$id")
    [ -z "$yp" ] && { echo "  ✗ 找不到: $id"; exit 1; }
    python3 - "$yp" "$pr" <<'PYEOF'
import sys
from pathlib import Path
import yaml

yp = Path(sys.argv[1])
pr = sys.argv[2]
m = yaml.safe_load(yp.read_text())
if "upstream_plan" not in m or not isinstance(m["upstream_plan"], dict):
    m["upstream_plan"] = {}
m["upstream_plan"]["pr"] = pr
m["upstream_plan"]["status"] = "submitted"
yp.write_text(yaml.safe_dump(m, sort_keys=False, allow_unicode=True, default_flow_style=False))
print(f"  ✓ {yp.name}: upstream.pr = {pr}, status -> submitted")
PYEOF
}

cmd_mark_rebased() {
    local id="$1" date="$2"
    local yp=$(find_meta "$id")
    [ -z "$yp" ] && { echo "  ✗ 找不到: $id"; exit 1; }
    # 校验日期
    if ! echo "$date" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
        echo "  ✗ 日期格式不对: $date (期望 YYYY-MM-DD)"
        exit 1
    fi
    python3 - "$yp" "$date" <<'PYEOF'
import sys
from pathlib import Path
import yaml

yp = Path(sys.argv[1])
date = sys.argv[2]
m = yaml.safe_load(yp.read_text())
m["last_rebased_at"] = date
yp.write_text(yaml.safe_dump(m, sort_keys=False, allow_unicode=True, default_flow_style=False))
print(f"  ✓ {yp.name}: last_rebased_at = {date}")
PYEOF
}

cmd_retire() {
    local id="$1"
    local yp=$(find_meta "$id")
    if [ -z "$yp" ]; then
        echo "  ✗ 找不到: $id"
        exit 1
    fi
    local base=$(basename "$yp" .yaml)
    local vdir=$(dirname "$(dirname "$yp")")
    local patch_file="$vdir/patches/$base.patch"
    local series="$vdir/series"

    # 检查状态(必须是 retired,valid状态会拒绝)
    local status=$(awk '/^  status:/{print $2; exit}' "$yp")
    if [ "$status" != "retired" ] && [ "${2:-}" != "--force" ]; then
        echo "  ✗ 当前状态 $status != retired"
        echo "  先跑: bash tools/lifecycle.sh set $id retired"
        echo "  或: bash tools/lifecycle.sh retire $id --force"
        exit 1
    fi

    # 删 4 处
    echo "  删 patch 文件: $patch_file"
    rm -f "$patch_file"
    echo "  删 metadata: $yp"
    rm -f "$yp"
    if [ -f "$series" ]; then
        if grep -q "^$base\.patch$" "$series"; then
            sed -i "/^$base\.patch$/d" "$series"
            echo "  从 series 删除 $base.patch"
        fi
    fi
    # 注:不再维护 boostkit.yaml#patches[],因为 boostkit.yaml 已删除

    # 跑 verify
    bash tools/verify.sh > /dev/null 2>&1 && echo "  ✓ verify 通过" || echo "  ! verify 报错,请检查"
}

# 主入口
case "${1:-}" in
    list)           cmd_list ;;
    show)           [ -z "${2:-}" ] && { echo "usage: $0 show <id>"; exit 1; }; cmd_show "$2" ;;
    set)            [ -z "${2:-}" ] || [ -z "${3:-}" ] && { echo "usage: $0 set <id> <status>"; exit 1; }; cmd_set "$2" "$3" ;;
    link)           [ -z "${2:-}" ] || [ -z "${3:-}" ] && { echo "usage: $0 link <id> <pr-url>"; exit 1; }; cmd_link "$2" "$3" ;;
    mark-rebased)   [ -z "${2:-}" ] || [ -z "${3:-}" ] && { echo "usage: $0 mark-rebased <id> <YYYY-MM-DD>"; exit 1; }; cmd_mark_rebased "$2" "$3" ;;
    retire)         [ -z "${2:-}" ] && { echo "usage: $0 retire <id> [--force]"; exit 1; }; cmd_retire "$2" "${3:-}" ;;
    *)              echo "usage: $0 {list|show <id>|set <id> <status>|link <id> <pr-url>|mark-rebased <id> <date>|retire <id> [--force]}"; exit 1 ;;
esac
