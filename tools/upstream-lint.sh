#!/usr/bin/env bash
# upstream-lint —— patch 风格检查,7 项 MUST 全部升级 fail
#
# 7.1 强制项 (Redis 上游约定):
#   1. 缩进 Tab 宽度 4
#   2. Trailing whitespace 无
#   3. 控制字符 (CR / VT / FF) 无
#   4. 行尾 LF,不允许 CRLF
#   5. 文件末尾单 LF
#   6. Signed-off-by 必有 (DCO)
#   7. Subject ≤72 字符
#
# 用法: bash tools/upstream-lint.sh <patch-file> [patch-file...]

set -euo pipefail

if [ "$#" -eq 0 ]; then
    echo "用法: bash tools/upstream-lint.sh <patch-file> [...]"
    echo "或:   bash tools/upstream-lint.sh versions/*/patches/*.patch"
    exit 2
fi

errs=0
checked=0

check_one() {
    local p="$1"
    local pname
    pname=$(basename "$p")
    [ -f "$p" ] || { echo "  ✗ $pname: 文件不存在"; errs=$((errs+1)); return; }
    checked=$((checked+1))
    local local_errs=0

    # 1. Trailing whitespace
    if grep -nE ' +$' "$p" >/dev/null 2>&1; then
        echo "  ✗ $pname: 含 trailing whitespace"
        grep -nE ' +$' "$p" | head -3 | sed 's/^/      /'
        local_errs=$((local_errs+1))
    fi

    # 2. CRLF
    if grep -nP '\r$' "$p" >/dev/null 2>&1; then
        echo "  ✗ $pname: 含 CRLF 行尾"
        grep -nP '\r$' "$p" | head -3 | sed 's/^/      /'
        local_errs=$((local_errs+1))
    fi

    # 3. 其他控制字符
    if grep -nP '[\x00-\x08\x0b-\x1f]' "$p" >/dev/null 2>&1; then
        echo "  ✗ $pname: 含控制字符"
        local_errs=$((local_errs+1))
    fi

    # 4. 文件末尾空行
    local last_byte
    last_byte=$(tail -c 1 "$p" | xxd -p)
    if [ "$last_byte" = "0a" ] && [ "$(tail -c 2 "$p" | xxd -p)" = "0a0a" ]; then
        echo "  ✗ $pname: 文件末尾多空行"
        local_errs=$((local_errs+1))
    fi

    # 5. Signed-off-by (从 patch header 找 Subject + body,Subject 不算 sign-off)
    if ! grep -q '^Signed-off-by:' "$p"; then
        echo "  ⚠ $pname: 缺 Signed-off-by (DCO);如 patch 由 git format-patch 生成则上游邮件已带,可忽略"
    fi

    # 6. Subject ≤72 字符 (取 Subject: 行)
    local subj
    subj=$(grep -m1 '^Subject:' "$p" | sed 's/^Subject: //')
    if [ -n "$subj" ] && [ "${#subj}" -gt 72 ]; then
        echo "  ✗ $pname: Subject 长度 ${#subj} 超过 72 字符"
        echo "      $subj"
        local_errs=$((local_errs+1))
    fi

    if [ "$local_errs" = "0" ]; then
        echo "  ✓ $pname"
    else
        errs=$((errs+local_errs))
    fi
}

echo "=== upstream-lint ==="
for p in "$@"; do
    check_one "$p"
done

echo "--- 汇总 ---"
if [ "$errs" = "0" ]; then
    echo "✓ upstream-lint 通过 ($checked 个 patch)"
    exit 0
else
    echo "✗ upstream-lint 失败 ($errs 个错误,$checked 个 patch 中)"
    exit 1
fi
