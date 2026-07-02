#!/usr/bin/env bash
# 安装本地 commit hooks。pre-commit 与 lefthook 配置都已生成，
# 按本机已装的工具分别启用，未装的给出安装提示。
set -euo pipefail

[ -d .git ] || { echo '✗ 当前目录不是 git 仓库根（缺少 .git）' >&2; exit 1; }

# --- pre-commit framework ---
if [ -f .pre-commit-config.yaml ]; then
  if command -v pre-commit >/dev/null 2>&1; then
    pre-commit install
    echo '✓ pre-commit 已启用（.git/hooks/pre-commit）'
    echo '  首次全量检查: pre-commit run --all-files'
  else
    echo '! 未装 pre-commit，跳过。安装后运行: pre-commit install'
    echo '  uv tool install pre-commit   # 或 brew install pre-commit'
  fi
fi

# --- lefthook ---
if [ -f lefthook.yml ]; then
  if command -v lefthook >/dev/null 2>&1; then
    lefthook install
    echo '✓ lefthook 已启用'
    echo '  首次全量检查: lefthook run pre-commit --all-files'
  else
    echo '! 未装 lefthook，跳过。安装后运行: lefthook install'
    echo '  brew install lefthook    # 或 go install github.com/evilmartians/lefthook@latest'
  fi
fi

echo
echo '提示: 两套配置等价，择一启用即可。切换前先 uninstall 旧的。'
echo '  详见 references/hooks-compare.md'
