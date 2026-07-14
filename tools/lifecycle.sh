#!/usr/bin/env bash
# lifecycle —— 状态 + 退役管理
#
# 用法:
#   bash tools/lifecycle.sh list                                列出所有 patch(active)
#   bash tools/lifecycle.sh show <id> [--archived]              查看 metadata
#                                                              (默认只看 active,--archived 查 retired/)
#   bash tools/lifecycle.sh set <id> <status>                   改状态
#   bash tools/lifecycle.sh retire <id>                         退役(一步到位,任何状态可直接 retire,
#                                                              metadata → retired/,
#                                                              patch → patches/retired/,
#                                                              series 删行)
#   bash tools/lifecycle.sh restore <id>                        把退役 patch 复活
#                                                              (metadata 移回 active,
#                                                              patch 移回 patches/,
#                                                              series 加行)
#   bash tools/lifecycle.sh link <id> <pr-url>                  记录上游 PR(自动改 status=submitted)
#   bash tools/lifecycle.sh mark-rebased <id> <date>            标 rebase 日期
#
# 状态(5 个,简化版):
#   pending      patch 刚加入,未验证
#   validated    干净 apply 验证通过
#   submitted    已发上游 PR
#   accepted     上游已合入(等下次 rebase 时退役)
#   retired      终态(已 mv 到 retired/,不在 active apply 链上)
#
# 合法转换(set 校验用,retire 是快捷方式,任何状态直接到 retired):
#   pending     -> validated | submitted | retired
#   validated   -> submitted | pending | retired
#   submitted   -> accepted | validated | retired
#   accepted    -> validated | retired
#   retired     -> (终态,只能 restore 复活成 validated)
#
# 实际工作流鼓励直接用 `retire`(跳过 set accepted / set retired 这些中间态),
# `accepted` 只用于"我已经知道上游合了,标记一下"的语义场景。
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION_LIST="versions"
VALID_STATUSES="pending validated submitted accepted retired"
LEGAL="
pending:validated,submitted,retired
validated:submitted,pending,retired
submitted:accepted,validated,retired
accepted:validated,retired
"

find_meta() {
    # $1 = patch id (如 redis-7.0.15-0001) 或 base name (如 0001-...)
    # $2 = "archived" 可选,允许查 retired/ 子目录
    local target="$1"
    local include_archived="${2:-}"
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
        # 可选查 retired/ 子目录
        if [ "$include_archived" = "archived" ]; then
            [ -d "$vdir/metadata/retired" ] || continue
            for yp in "$vdir/metadata/retired/"*.yaml; do
                [ -f "$yp" ] || continue
                local id=$(awk '/^id:/{print $2; exit}' "$yp")
                local base=$(basename "$yp" .yaml)
                if [ "$id" = "$target" ] || [ "$base" = "$target" ] || echo "$base" | grep -q "^${target}-"; then
                    echo "$yp"
                    return 0
                fi
            done
        fi
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
    local scope=""
    shift || true
    while [ $# -gt 0 ]; do
        case "$1" in
            --archived) scope="archived" ;;
            *)          echo "  ✗ 未知参数: $1"; exit 1 ;;
        esac
        shift
    done
    local yp=$(find_meta "$id" "$scope")
    [ -z "$yp" ] && { echo "  ✗ 找不到: $id ${scope:+(${scope})}"; exit 1; }
    echo "  $yp"
    cat "$yp"
}

cmd_restore() {
    # 把 retired/ 下的 metadata 复活回 metadata/,前提 patch 文件还在 patches/
    local id="$1"
    if [ -z "$id" ]; then
        echo "usage: $0 restore <id>"; exit 1
    fi
    local archived_yp=$(find_meta "$id" "archived")
    if [ -z "$archived_yp" ]; then
        echo "  ✗ 找不到 archived patch: $id"; exit 1
    fi
    # 只允许在 retired/ 下查找(不能误恢复一个还活着的 patch)
    case "$archived_yp" in
        */retired/*.yaml) ;;
        *) echo "  ✗ $id 不在 retired/ 下,无需 restore"; exit 1 ;;
    esac
    local base=$(basename "$archived_yp" .yaml)
    local vdir=$(dirname "$(dirname "$(dirname "$archived_yp")")")
    local target_yp="$vdir/metadata/$base.yaml"
    local patch_file="$vdir/patches/$base.patch"
    local archived_patch="$vdir/patches/retired/$base.patch"
    local series="$vdir/series"

    # 优先从 patches/retired/ 取 patch 文件
    if [ -f "$archived_patch" ]; then
        if [ -f "$patch_file" ]; then
            echo "  ✗ patches/$base.patch 已存在,拒绝覆盖"; exit 1
        fi
        mv "$archived_patch" "$patch_file"
        echo "  ✓ patch 文件移回: $patch_file"
    elif [ -f "$patch_file" ]; then
        echo "  ! patches/$base.patch 已在原位(可能手动处理过),metadata 继续移回"
    else
        echo "  ✗ patch 文件不在任何地方: 既不在 $archived_patch 也不在 $patch_file"
        echo "  若确实要恢复,请先把 patch 放回 $patch_file 再跑"
        exit 1
    fi
    # 检查 metadata 是否已经存在(防止覆盖)
    if [ -f "$target_yp" ]; then
        echo "  ✗ metadata 已存在: $target_yp,拒绝覆盖"; exit 1
    fi
    # 改 yaml:status 回到 validated(中性状态,owner 决定后续 submit/pending)
    python3 - "$archived_yp" <<'PYEOF'
import sys
from pathlib import Path
import yaml

yp = Path(sys.argv[1])
m = yaml.safe_load(yp.read_text())
if "upstream_plan" in m and isinstance(m["upstream_plan"], dict):
    m["upstream_plan"]["status"] = "validated"
    # 保留 retired_at/reason/pr 作历史,不删
yp.write_text(yaml.safe_dump(m, sort_keys=False, allow_unicode=True, default_flow_style=False))
PYEOF
    mv "$archived_yp" "$target_yp"
    echo "  ✓ 复活 metadata: $target_yp (status: validated)"

    # series 加回这一行(若已存在则跳过)
    if [ -f "$series" ] && ! grep -q "^$base\.patch$" "$series"; then
        echo "$base.patch" >> "$series"
        echo "  ✓ series 追加 $base.patch"
    else
        echo "  ! series 已有 $base.patch,未追加"
    fi
    bash tools/verify.sh > /dev/null 2>&1; rc=$?
    [ $rc -eq 0 ] && echo "  ✓ verify 通过" || echo "  ! verify 报错(退出码 $rc)"
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
    local archive_dir="$vdir/metadata/retired"

    # 准备 archive 目录(metadata 和 patches 都用 retired/ 子目录,保持对称)
    mkdir -p "$archive_dir" "$vdir/patches/retired"

    # 1. 把 metadata 的 status 改成 retired(只改这一行,避免 yaml 整体重写丢字段)
    sed -i 's/^\(\s*\)status:\s*.*/\1status: retired/' "$yp"

    # 2. mv metadata → archive
    mv "$yp" "$archive_dir/$base.yaml"
    echo "  archive metadata: $archive_dir/$base.yaml"

    # 3. patch 文件 mv 到 patches/retired/(不在 patches/ 根下,verify 一致性才过)
    if [ -f "$patch_file" ]; then
        mv "$patch_file" "$vdir/patches/retired/$base.patch"
        echo "  archive patch: $vdir/patches/retired/$base.patch"
    else
        echo "  ! patch 文件已不在原位(可能之前手动删过)"
    fi

    # 4. series 删行
    if [ -f "$series" ] && grep -q "^$base\.patch$" "$series"; then
        sed -i "/^$base\.patch$/d" "$series"
        echo "  从 series 删除 $base.patch"
    else
        echo "  ! series 里没找到 $base.patch(已不在 apply 链上)"
    fi

    # 5. 跑 verify
    bash tools/verify.sh > /dev/null 2>&1; rc=$?
    [ $rc -eq 0 ] && echo "  ✓ verify 通过" || echo "  ! verify 报错(退出码 $rc)"
}

# 主入口
case "${1:-}" in
    list)           cmd_list ;;
    show)           shift; cmd_show "$@" ;;
    set)            [ -z "${2:-}" ] || [ -z "${3:-}" ] && { echo "usage: $0 set <id> <status>"; exit 1; }; cmd_set "$2" "$3" ;;
    link)           [ -z "${2:-}" ] || [ -z "${3:-}" ] && { echo "usage: $0 link <id> <pr-url>"; exit 1; }; cmd_link "$2" "$3" ;;
    mark-rebased)   [ -z "${2:-}" ] || [ -z "${3:-}" ] && { echo "usage: $0 mark-rebased <id> <YYYY-MM-DD>"; exit 1; }; cmd_mark_rebased "$2" "$3" ;;
    retire)         [ -z "${2:-}" ] && { echo "usage: $0 retire <id>"; exit 1; }; cmd_retire "$2" ;;
    restore)        cmd_restore "$2" ;;
    *)              echo "usage: $0 {list|show <id> [--archived]|set <id> <status>|link <id> <pr-url>|mark-rebased <id> <date>|retire <id>|restore <id>}"; exit 1 ;;
esac
