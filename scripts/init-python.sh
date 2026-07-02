#!/usr/bin/env bash
# 一键初始化 Python 项目 harness（uv 首选）。
# 用法:
#   init-python.sh           # 当前目录初始化为库（--lib）
#   init-python.sh <name>    # 新建子目录 <name>
#   init-python.sh <name> app  # 第二参数 app → 用 --app（应用）而非 --lib
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

LANG_NAME="Python"
require_cmd uv

PROJ_NAME="${1:-}"
KIND="${2:-lib}"   # lib | app
case "$KIND" in
  lib|app) ;;
  *) die "第二参数须为 lib 或 app（默认 lib）" ;;
esac

if [ -n "$PROJ_NAME" ]; then
  uv init "--$KIND" "$PROJ_NAME"
  PROJ_DIR="$(cd "$PROJ_NAME" && pwd)"
else
  uv init "--$KIND"
  PROJ_DIR="$(pwd)"
fi
log "Python 脚手架已生成 (uv init --$KIND)"

copy_common
copy_lang python

# 质量工具 dev 依赖（ruff/mypy/bandit/pip-audit/pytest-cov）
log "添加质量工具 dev 依赖 (ruff mypy bandit pip-audit pytest pytest-cov)"
cd "$PROJ_DIR"
uv add --dev ruff mypy bandit pip-audit pytest pytest-cov || warn "uv add 失败，请手动: uv add --dev ruff mypy bandit pip-audit pytest pytest-cov"

# 工具配置（ruff/mypy/bandit/pytest/coverage）在 pyproject-tooling.toml
# → 合并进 uv 生成的 pyproject.toml，合并后删除该 snippet 文件
if [ -f "$PROJ_DIR/pyproject-tooling.toml" ]; then
  warn "Python: 检测到 pyproject-tooling.toml 未合并"
  warn "  请将其 [tool.*] 段合并到 pyproject.toml，然后删除该文件"
  warn "  （ruff/mypy/bandit/pytest 自动从 pyproject.toml 读取配置）"
  exit 1
fi

git_init
install_hooks
harness_finalize
