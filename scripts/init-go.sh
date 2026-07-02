#!/usr/bin/env bash
# 一键初始化 Go 项目 harness。
# 用法:
#   init-go.sh [name]
# 环境变量:
#   GO_MODULE  完整 module 路径（默认 github.com/<user>/<dir>）
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

LANG_NAME="Go"
require_cmd go

PROJ_NAME="${1:-}"
if [ -n "$PROJ_NAME" ]; then
  mkdir -p "$PROJ_NAME" && cd "$PROJ_NAME"
fi
PROJ_DIR="$(pwd)"

MODULE="${GO_MODULE:-github.com/$(whoami)/$(basename "$PROJ_DIR")}"
go mod init "$MODULE"
log "Go 脚手架已生成 (go mod init $MODULE)"

copy_common
copy_lang go

git_init
install_hooks
harness_finalize
