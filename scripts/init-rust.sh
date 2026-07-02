#!/usr/bin/env bash
# 一键初始化 Rust 项目 harness。
# 用法:
#   init-rust.sh            # 在当前空目录初始化（项目名取目录名）
#   init-rust.sh <name>     # 新建子目录 <name> 并在其中初始化
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

LANG_NAME="Rust"
require_cmd cargo

PROJ_NAME="${1:-}"
if [ -n "$PROJ_NAME" ]; then
  cargo init --name "$PROJ_NAME" "$PROJ_NAME"
  PROJ_DIR="$(cd "$PROJ_NAME" && pwd)"
else
  cargo init
  PROJ_DIR="$(pwd)"
fi

log "Rust 脚手架已生成 (cargo init)"

# 拷贝 harness 模板（含 ci/release/.pre-commit-config/lefthook/rustfmt/clippy/deny/.gitignore）
copy_common
copy_lang rust

git_init
install_hooks
harness_finalize
