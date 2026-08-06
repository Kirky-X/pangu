#!/usr/bin/env bash
# 一键初始化 Go 项目 harness。
# 用法:
#   init-go.sh [name]
# 环境变量:
#   GO_MODULE  完整 module 路径（默认 github.com/<user>/<dir>）
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# shellcheck disable=SC2034  # harness_finalize 读取
LANG_NAME="Go"
require_cmd go

PROJ_NAME="${1:-}"
if [ -n "$PROJ_NAME" ]; then
  mkdir -p "$PROJ_NAME" && cd "$PROJ_NAME"
fi
PROJ_DIR="$(pwd)"

# 幂等保护：检测目标目录是否已有 go.mod
if [ -f "$PROJ_DIR/go.mod" ]; then
  warn "检测到已有 Go 项目（go.mod），跳过脚手架（避免覆盖）"
else
  MODULE="${GO_MODULE:-github.com/$(whoami)/$(basename "$PROJ_DIR")}"
  go mod init "$MODULE"
  log "Go 脚手架已生成 (go mod init $MODULE)"
fi

copy_common
copy_lang go

# Makefile APP_NAME 自动替换为项目名
APP_NAME="$(basename "$PROJ_DIR")"
if [ -f "$PROJ_DIR/Makefile" ] && grep -q 'APP_NAME ?= app' "$PROJ_DIR/Makefile"; then
  sed -i "s/APP_NAME ?= app/APP_NAME ?= $APP_NAME/" "$PROJ_DIR/Makefile"
  ok "Makefile APP_NAME 已替换为 '$APP_NAME'"
fi

# 工具安装提示
log "Go 质量工具提示（未自动安装）："
for cmd in golangci-lint gosec govulncheck; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    warn "  缺少 $cmd — CI 会自动安装，本地开发建议安装："
    case "$cmd" in
      golangci-lint) warn "    go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest" ;;
      gosec)         warn "    go install github.com/securego/gosec/v2/cmd/gosec@latest" ;;
      govulncheck)   warn "    go install golang.org/x/vuln/cmd/govulncheck@latest" ;;
    esac
  fi
done

git_init
install_hooks
harness_finalize
