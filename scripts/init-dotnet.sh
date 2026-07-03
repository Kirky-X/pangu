#!/usr/bin/env bash
# 一键初始化 .NET 项目 harness。
# 用法:
#   init-dotnet.sh [name] [kind]
#     kind: console(默认) | classlib | web
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

LANG_NAME=".NET"
require_cmd dotnet

PROJ_NAME="${1:-}"
KIND="${2:-console}"
case "$KIND" in
  console|classlib|web) ;;
  *) die "第二参数 kind 须为 console | classlib | web（默认 console）" ;;
esac

if [ -n "$PROJ_NAME" ]; then
  mkdir -p "$PROJ_NAME" && cd "$PROJ_NAME"
fi
PROJ_DIR="$(pwd)"

# 不带参数时用当前目录名作项目名（与 init-go.sh MODULE 默认值 github.com/$(whoami)/$(basename "$PROJ_DIR") 惯例一致）
_name="${PROJ_NAME:-$(basename "$PROJ_DIR")}"
dotnet new "$KIND" -n "$_name" -o . >/dev/null 2>&1 \
  || dotnet new "$KIND" >/dev/null 2>&1 \
  || die "dotnet new $KIND 失败"
log ".NET 脚手架已生成 (dotnet new $KIND)"

copy_common
copy_lang dotnet

# 质量工具：SecurityCodeScan + coverlet 覆盖率
cd "$PROJ_DIR"
log "添加质量工具 (SecurityCodeScan coverlet)"
dotnet add package SecurityCodeScan.VS2019 \
  || warn "dotnet add package SecurityCodeScan 失败，请手动添加"
dotnet add package coverlet.collector \
  || warn "dotnet add package coverlet.collector 失败，请手动添加"

git_init
install_hooks
harness_finalize
