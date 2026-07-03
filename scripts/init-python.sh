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
# （与 init-node.sh prettier.snippet.json 自动合并模式对齐）
if [ -f "$PROJ_DIR/pyproject-tooling.toml" ]; then
  if [ -f "$PROJ_DIR/pyproject.toml" ] && ! grep -q '^\[tool\.ruff\]' "$PROJ_DIR/pyproject.toml" 2>/dev/null; then
    printf '\n# --- pangu tooling snippet（init-python.sh 自动合并）---\n' >> "$PROJ_DIR/pyproject.toml"
    cat "$PROJ_DIR/pyproject-tooling.toml" >> "$PROJ_DIR/pyproject.toml"
    rm "$PROJ_DIR/pyproject-tooling.toml"
    ok "pyproject-tooling.toml 已合并到 pyproject.toml"
  elif [ -f "$PROJ_DIR/pyproject.toml" ] && grep -q '^\[tool\.ruff\]' "$PROJ_DIR/pyproject.toml" 2>/dev/null; then
    warn "pyproject.toml 已含 [tool.ruff]，跳过 snippet 合并（疑似重复 init）"
    rm "$PROJ_DIR/pyproject-tooling.toml"
  else
    warn "pyproject.toml 不存在（uv init 异常），保留 pyproject-tooling.toml 作参考"
  fi
fi

git_init
install_hooks
harness_finalize
