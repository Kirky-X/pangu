#!/usr/bin/env bash
# pangu 自检门禁：对 scripts/*.sh 跑 shellcheck。
# 用途:
#   1. pangu 自身 CI（提交前/PR 前，防止脚本回归）
#   2. 配合 templates/common/.pre-commit-config.yaml 的 shellcheck hook（local 等价入口）
# 行为:
#   - 未装 shellcheck → warn 并 exit 0（开发环境常见未装；CI 镜像应显式 apt/brew install shellcheck）
#   - 已装 → 逐个检查 scripts/*.sh，发现 SC 告警即非 0 退出（set -e）
#   - 排除 SC1090/SC1091（source 路径含变量，静态无法追踪外部文件，与 pre-commit hook 一致）
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v shellcheck >/dev/null 2>&1; then
  printf '\033[1;33m!\033[0m pangu selfcheck: 未安装 shellcheck，跳过（apt/brew install shellcheck 后生效）\n' >&2
  exit 0
fi

# nullglob: scripts/ 无 .sh 时避免字面量 "scripts/*.sh" 传给 shellcheck 报 No such file
shopt -s nullglob
shells=(scripts/*.sh)
shopt -u nullglob

if [ "${#shells[@]}" -eq 0 ]; then
  printf '\033[1;34m[harness]\033[0m scripts/ 下无 .sh，selfcheck 无事可做\n'
  exit 0
fi

printf '\033[1;34m[harness]\033[0m shellcheck %d 个脚本\n' "${#shells[@]}"
# SC1090/SC1091: source 路径含变量（_common.sh 等），shellcheck 无法静态追踪
shellcheck -e SC1090 -e SC1091 "${shells[@]}"
printf '\033[1;32m✓\033[0m shellcheck 通过（%d 个脚本）\n' "${#shells[@]}"
