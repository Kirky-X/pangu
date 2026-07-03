#!/usr/bin/env bash
# 一键初始化 PHP 项目 harness（Composer）。
# 用法:
#   init-php.sh             # 当前目录 composer init
#   init-php.sh <name>      # 新建子目录 <name>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

LANG_NAME="PHP"
require_cmd composer

PROJ_NAME="${1:-}"
if [ -n "$PROJ_NAME" ]; then
  mkdir -p "$PROJ_NAME" && cd "$PROJ_NAME"
fi
PROJ_DIR="$(pwd)"

# 非交互式初始化：默认应用类型，MIT，PSR-4 autoload（包名小写）
composer init --no-interaction \
  --type=project \
  --license=MIT \
  --name="$(whoami | tr '[:upper:]' '[:lower:]')/$(basename "$PROJ_DIR" | tr '[:upper:]' '[:lower:]')" \
  >/dev/null 2>&1 || composer init --no-interaction >/dev/null 2>&1 \
  || die "composer init 失败"
log "PHP 脚手架已生成 (composer init)"

copy_common
copy_lang php

# 质量工具 dev 依赖：php-cs-fixer / psalm(security) / phpunit
cd "$PROJ_DIR"
log "添加质量工具 dev 依赖 (php-cs-fixer psalm phpunit)"
composer require --dev friendsofphp/php-cs-fixer vimeo/psalm squizlabs/php_codesniffer phpunit/phpunit \
  || warn "composer require --dev 失败，请手动安装 php-cs-fixer/psalm/phpunit"
log "psalm 安全检查: CI 用 --taint-analysis 命令行触发（见 php/ci.yml security job），无需改 psalm.xml"

git_init
install_hooks
harness_finalize
