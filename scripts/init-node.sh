#!/usr/bin/env bash
# 一键初始化 Node/TypeScript 项目 harness（pnpm 首选，回退 npm）。
# 用法:
#   init-node.sh             # 当前目录初始化
#   init-node.sh <name>      # 新建子目录 <name>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

LANG_NAME="Node/TypeScript"
if command -v pnpm >/dev/null 2>&1; then PKG=pnpm
elif command -v npm >/dev/null 2>&1; then PKG=npm
else die "缺少 pnpm 或 npm（请先安装 Node.js 与包管理器）"; fi

PROJ_NAME="${1:-}"
if [ -n "$PROJ_NAME" ]; then
  mkdir -p "$PROJ_NAME" && cd "$PROJ_NAME"
fi
PROJ_DIR="$(pwd)"

$PKG init -y >/dev/null
log "Node 脚手架已生成 ($PKG init)"

copy_common
copy_lang node

# 质量工具 + TypeScript dev 依赖
log "添加质量工具 dev 依赖 (typescript 工具链)"
cd "$PROJ_DIR"
# flat config 推荐组合: typescript-eslint(unified) + @eslint/js
$PKG add -D typescript @types/node \
  prettier eslint @eslint/js typescript-eslint \
  eslint-plugin-security \
  vitest @vitest/coverage-v8 \
  || warn "$PKG add -D 失败，请手动安装上述 dev 依赖"

# 落地配置文件（snippet → 真实文件名，绕过 config-protection 模板保护）
if [ -f eslint-flat.snippet.js ] && [ ! -f eslint.config.js ]; then
  cp eslint-flat.snippet.js eslint.config.js
  rm eslint-flat.snippet.js
  ok "eslint.config.js 已生成"
fi
if [ -f prettier.snippet.json ] && [ -f package.json ]; then
  node -e '
    const fs = require("fs");
    const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
    const snip = JSON.parse(fs.readFileSync("prettier.snippet.json", "utf8"));
    pkg.scripts = Object.assign({}, pkg.scripts || {}, snip.scripts || {});
    if (snip.prettier) pkg.prettier = snip.prettier;
    if (snip.engines) pkg.engines = snip.engines;
    fs.writeFileSync("package.json", JSON.stringify(pkg, null, 2) + "\n");
  ' && rm prettier.snippet.json && ok "package.json 已合并 scripts/prettier/engines"
fi

git_init
install_hooks
harness_finalize
