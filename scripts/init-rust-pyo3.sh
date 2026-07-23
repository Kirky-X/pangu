#!/usr/bin/env bash
# FFI rust→python harness（maturin/PyO3）。半自动：官方 maturin 管骨架，本脚本管 harness。
# 前置: 先在目标目录跑官方脚手架（非交互）:
#   maturin new --mixed --bindings pyo3 <name>
# 完成后本脚本叠加 harness（CI/release/hook/配置），rust 与 python 同根（maturin mixed layout）。
# 用法:
#   cd /path/to/maturin-project
#   bash ~/.claude/skills/pangu/scripts/init-rust-pyo3.sh [项目目录(默认当前)]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

[ -n "${1:-}" ] && { cd "$1" || die "目录不存在: $1"; }
PROJ_DIR="$(pwd)"
export PROJ_DIR

apply_ffi_harness python

cat <<EOF

下一步（PyO3 专属）:
  1. 本地开发安装（编译 rust 扩展到当前 venv，editable）:
       maturin develop
  2. 跑测试: pytest（python/<pkg>/tests/）+ cargo test（src/）
  3. 合并 hook 片段（rust 基底 + python-.pre-commit-config.yaml / python-lefthook.yml）→ references/multi-language.md
  4. 启用本地 hook: pre-commit install 或 lefthook install
  5. 发布: push tag v* → ci.yml(rust) + python-ci.yml + python-release.yml
       PyPI secret: PYPI_TOKEN / UV_PUBLISH_TOKEN → references/registry-secrets.md
EOF
