#!/usr/bin/env bash
# status-report —— 全仓 patch 健康看板
#
# 打印:patch id / status / last_rebased_at / days_since_rebase / upstream status / risk
#
# 用法: bash tools/status-report.sh [--days N]  # 高亮 days_since_rebase > N 的 patch
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

THRESHOLD=180  # 默认 6 个月
[ "${1:-}" = "--days" ] && THRESHOLD="${2:-180}"

echo "=== boostkit status-report ==="
echo "  rebase-stale threshold: $THRESHOLD days"
echo
printf "%-15s %-25s %-18s %-13s %-12s %-18s %s\n" "VERSION" "ID" "STATUS" "REBASED" "DAYS" "UPSTREAM" "RISK"
echo "--------------------------------------------------------------------------------------------------------"

TODAY=$(date +%s)

STALE_COUNT=0
TOTAL=0
for vdir in versions/*/; do
    [ -d "$vdir" ] || continue
    vname=$(basename "$vdir")
    for yp in "$vdir"metadata/*.yaml; do
        [ -f "$yp" ] || continue
        TOTAL=$((TOTAL + 1))

        # 用 python 安全解析(避免 yq 依赖)
        read -r ID STATUS REBASED UPSTREAM RISK <<< "$(python3 -c "
import yaml, sys
m = yaml.safe_load(open('$yp'))
def s(v):
    if v is None: return '-'
    if hasattr(v, 'isoformat'): return v.isoformat()[:10]
    return str(v)
print(s(m.get('id','?')),
      s(m.get('status','?')),
      s(m.get('last_rebased_at','-')),
      s((m.get('upstream') or {}).get('status','-')),
      s(m.get('risk_level','-')))
")"

        # 计算 days_since
        if [ "$REBASED" != "-" ]; then
            REBASED_TS=$(date -d "$REBASED" +%s 2>/dev/null || echo 0)
            DAYS=$(( (TODAY - REBASED_TS) / 86400 ))
        else
            DAYS="-"
        fi

        # 标记 stale
        MARK=""
        if [ "$DAYS" != "-" ] && [ "$DAYS" -gt "$THRESHOLD" ]; then
            MARK="⚠ STALE"
            STALE_COUNT=$((STALE_COUNT + 1))
        fi
        # Deprecated 但未删 → 提醒
        if [ "$STATUS" = "Deprecated" ]; then
            MARK="$MARK [pending retire]"
        fi

        printf "%-15s %-25s %-18s %-13s %-12s %-18s %s\n" \
            "$vname" "$ID" "$STATUS" "$REBASED" "$DAYS" "$UPSTREAM" "$RISK $MARK"
    done
done

echo "--------------------------------------------------------------------------------------------------------"
echo "  总计: $TOTAL 个 patch,$STALE_COUNT 个超过 $THRESHOLD 天未 rebase"
echo
if [ "$STALE_COUNT" -gt 0 ]; then
    echo "  建议:对 STALE patch 跑 bash tools/rebase.sh <new-upstream-version> 或 python tools/lifecycle.py <id> Deprecated"
fi
