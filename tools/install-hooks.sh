#!/usr/bin/env bash
# install-hooks —— 装/卸本地 git 钩子
#
# 用法: bash tools/install-hooks.sh [--uninstall]
#
# 启用后,所有 git 钩子从 .githooks/ 读取(.git/hooks/ 不再生效)
# 装上后,git push 前自动跑 bash tools/verify.sh
# 跳过单次: git push --no-verify
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ "${1:-}" = "--uninstall" ]; then
    git config --unset core.hooksPath
    echo "  ✓ 已卸载(恢复默认 .git/hooks/ 路径)"
    exit 0
fi

if [ ! -d .githooks ]; then
    echo "  ✗ .githooks/ 不存在"
    exit 1
fi

chmod +x .githooks/*
echo "  ✓ chmod +x .githooks/*"

git config core.hooksPath .githooks
echo "  ✓ git config core.hooksPath = .githooks"
echo
echo "  现在 push 前会自动跑 bash tools/verify.sh"
echo "  测试: git push(应自动跑 verify)"
echo "  跳过: git push --no-verify"
echo "  卸载: bash tools/install-hooks.sh --uninstall"
