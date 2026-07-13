#!/usr/bin/env bash
# install-hooks —— 把 .githooks/ 装到 .git/hooks/ 并启用 core.hooksPath
#
# 用法: bash tools/install-hooks.sh [--uninstall]
#
# 启用后,所有 git 钩子从 .githooks/ 读取(.git/hooks/ 不再生效)
# 卸载: --uninstall 把 core.hooksPath 还原为默认(.git/hooks/)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ "${1:-}" = "--uninstall" ]; then
    git config --unset core.hooksPath
    echo "  ✓ 已卸载(恢复默认 .git/hooks/ 路径)"
    exit 0
fi

# 检查 .githooks/ 存在
if [ ! -d .githooks ]; then
    echo "  ✗ .githooks/ 不存在"
    exit 1
fi

# 给所有 .githooks/* 加可执行权限
chmod +x .githooks/*
echo "  ✓ chmod +x .githooks/*"

# 设置 core.hooksPath
git config core.hooksPath .githooks
echo "  ✓ git config core.hooksPath = .githooks"
echo
echo "  现在 .git/hooks/ 不会被使用,所有钩子从 .githooks/ 读取"
echo "  测试: git push(应自动跑 pre-push 3 个 check)"
echo "  跳过: git push --no-verify"
echo "  卸载: bash tools/install-hooks.sh --uninstall"
