#!/usr/bin/env bash
# FFI rust→node harness（napi-rs）。半自动：官方 napi 管骨架，本脚本管 harness。
# 前置: napi new 是纯交互式（prompt 包名/目标平台/GitHub actions），无法脚本自动化。
#   请先手动跑: napi new   (= npm create @napi-rs/cli@latest)
#   完成后本脚本叠加 harness（CI/release/hook/配置），rust 与 node 同根（napi 设计如此）。
# 用法:
#   cd /path/to/napi-project
#   bash ~/.claude/skills/pangu/scripts/init-rust-napi.sh [项目目录(默认当前)]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

[ -n "${1:-}" ] && { cd "$1" || die "目录不存在: $1"; }
PROJ_DIR="$(pwd)"
export PROJ_DIR

apply_ffi_harness node

cat <<EOF

下一步（napi-rs 专属）:
  1. 本地构建（生成 index.js + index.d.ts，编译当前平台 napi）:
       napi build
  2. 跑测试: napi build && node test/  （或 napi 自带 cargo test）
  3. 合并 hook 片段（rust 基底 + node-.pre-commit-config.yaml / node-lefthook.yml）→ references/multi-language.md
  4. 启用本地 hook: pre-commit install 或 lefthook install
  5. 发布: push tag v* → ci.yml(rust) + node-ci.yml + node-release.yml
       napi-rs 自带 universal CI（.github/workflows/ 下 napi 生成）已处理多平台构建；
       本 skill 的 node-release.yml 仅管 npm 发布（NPM_TOKEN）→ references/registry-secrets.md
       若 napi 生成 CI 与本 harness 冲突，以 napi 生成版本为准（删 node-ci.yml）。
EOF
