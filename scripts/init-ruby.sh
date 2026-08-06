#!/usr/bin/env bash
# 一键初始化 Ruby 项目 harness。
# 用法:
#   init-ruby.sh            # 当前目录 bundle init（应用/脚本）
#   init-ruby.sh <name>     # bundle gem <name>（生成完整 gem 骨架）
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# shellcheck disable=SC2034  # harness_finalize 读取
LANG_NAME="Ruby"
require_cmd bundle

PROJ_NAME="${1:-}"
if [ -n "$PROJ_NAME" ]; then
  # 幂等保护：检测目标目录是否已有 gemspec 或 Gemfile
  if [ -d "$PROJ_NAME" ] && { ls "$PROJ_NAME"/*.gemspec >/dev/null 2>&1 || [ -f "$PROJ_NAME/Gemfile" ]; }; then
    warn "检测到已有 Ruby 项目（$PROJ_NAME），跳过脚手架（避免覆盖）"
    PROJ_DIR="$(cd "$PROJ_NAME" && pwd)"
  else
    bundle gem "$PROJ_NAME" --no-test --no-coc --no-license >/dev/null 2>&1 \
      || bundle gem "$PROJ_NAME" >/dev/null 2>&1 \
      || die "bundle gem 失败"
    PROJ_DIR="$(cd "$PROJ_NAME" && pwd)"
  fi
else
  # 幂等保护
  if [ -f Gemfile ]; then
    warn "检测到已有 Ruby 项目（Gemfile），跳过脚手架（避免覆盖）"
    PROJ_DIR="$(pwd)"
  else
    bundle init
    PROJ_DIR="$(pwd)"
  fi
fi
log "Ruby 脚手架已生成"

copy_common
copy_lang ruby

# 通用质量 gem（rubocop/rspec/simplecov/bundler-audit）。
# brakeman 仅 Rails 项目用，非 Rails 不加。
cd "$PROJ_DIR"
if [ -f Gemfile ]; then
  log "添加质量 gem (rspec rubocop simplecov bundler-audit)"
  bundle add rspec rubocop rubocop-rspec simplecov bundler-audit --group development \
    || warn "bundle add 失败，请手动: bundle add rspec rubocop simplecov bundler-audit --group development"
  warn "Rails 项目另加: bundle add brakeman --group development"
fi

git_init
install_hooks
harness_finalize
