#!/usr/bin/env bash
# 一键初始化 Rust 项目 harness。
# 用法:
#   init-rust.sh            # 在当前空目录初始化（项目名取目录名）
#   init-rust.sh <name>     # 新建子目录 <name> 并在其中初始化
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# shellcheck disable=SC2034  # harness_finalize 读取
LANG_NAME="Rust"
require_cmd cargo

PROJ_NAME="${1:-}"
PROJ_KIND="${2:-bin}"   # bin | lib
case "$PROJ_KIND" in
  bin|lib) ;;
  *) die "第二参数须为 bin 或 lib（默认 bin）" ;;
esac

# 幂等保护：检测目标目录是否已有 Cargo.toml
if [ -n "$PROJ_NAME" ] && [ -f "$PROJ_NAME/Cargo.toml" ]; then
  warn "检测到已有 Rust 项目（$PROJ_NAME/Cargo.toml），跳过脚手架（避免覆盖）"
  PROJ_DIR="$(cd "$PROJ_NAME" && pwd)"
elif [ -z "$PROJ_NAME" ] && [ -f Cargo.toml ]; then
  warn "检测到已有 Rust 项目（Cargo.toml），跳过脚手架（避免覆盖）"
  PROJ_DIR="$(pwd)"
else
  if [ -n "$PROJ_NAME" ]; then
    cargo init --name "$PROJ_NAME" ${PROJ_KIND:+--$PROJ_KIND} "$PROJ_NAME"
    PROJ_DIR="$(cd "$PROJ_NAME" && pwd)"
  else
    cargo init ${PROJ_KIND:+--$PROJ_KIND}
    PROJ_DIR="$(pwd)"
  fi
  log "Rust 脚手架已生成 (cargo init --$PROJ_KIND)"
fi

# 拷贝 harness 模板（含 ci/release/.pre-commit-config/lefthook/rustfmt/clippy/deny/.gitignore + cargo-profile.snippet.toml）
copy_common
copy_lang rust

# 追加 release profile 优化配置（LTO/codegen-units=1/strip/panic）到 Cargo.toml
# cargo init 默认 Cargo.toml 不含 [profile.release]，社区 release 标配需手动加
# 注意：library 项目建议删 panic = "abort"（依赖该 library 的 binary 将无法 catch panic 续跑）
if [ -f "$PROJ_DIR/cargo-profile.snippet.toml" ] && [ -f "$PROJ_DIR/Cargo.toml" ]; then
  if grep -q '\[profile.release\]' "$PROJ_DIR/Cargo.toml"; then
    warn "Cargo.toml 已含 [profile.release]，跳过追加（请手动核对优化标志）"
  else
    # library 模式：去掉 panic = "abort" 行（library 不应设 panic 策略）
    if [ "$PROJ_KIND" = "lib" ]; then
      grep -v 'panic = "abort"' "$PROJ_DIR/cargo-profile.snippet.toml" > "$PROJ_DIR/cargo-profile.snippet.toml.tmp"
      mv "$PROJ_DIR/cargo-profile.snippet.toml.tmp" "$PROJ_DIR/cargo-profile.snippet.toml"
      ok "Cargo.toml 已追加 [profile.release]（library 模式，不含 panic=abort）"
    else
      ok "Cargo.toml 已追加 [profile.release]（lto=thin/codegen-units=1/strip=symbols/panic=abort）"
    fi
    printf '\n' >> "$PROJ_DIR/Cargo.toml"
    cat "$PROJ_DIR/cargo-profile.snippet.toml" >> "$PROJ_DIR/Cargo.toml"
  fi
  rm -f "$PROJ_DIR/cargo-profile.snippet.toml"
fi

git_init
install_hooks
harness_finalize
