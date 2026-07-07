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

# 拷贝 harness 模板（含 ci/release/.pre-commit-config/lefthook/rustfmt/clippy/deny/.gitignore + cargo-profile.snippet.toml）
copy_common
copy_lang rust

# 追加 release profile 优化配置（LTO/codegen-units=1/strip/panic）到 Cargo.toml
# cargo init 默认 Cargo.toml 不含 [profile.release]，社区 release 标配需手动加
if [ -f "$PROJ_DIR/cargo-profile.snippet.toml" ] && [ -f "$PROJ_DIR/Cargo.toml" ]; then
  if grep -q '\[profile.release\]' "$PROJ_DIR/Cargo.toml"; then
    warn "Cargo.toml 已含 [profile.release]，跳过追加（请手动核对优化标志）"
  else
    printf '\n' >> "$PROJ_DIR/Cargo.toml"
    cat "$PROJ_DIR/cargo-profile.snippet.toml" >> "$PROJ_DIR/Cargo.toml"
    ok "Cargo.toml 已追加 [profile.release]（lto=thin/codegen-units=1/strip=symbols/panic=abort）"
  fi
  rm -f "$PROJ_DIR/cargo-profile.snippet.toml"
fi

git_init
install_hooks
harness_finalize
