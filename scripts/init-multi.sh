#!/usr/bin/env bash
# 一键初始化多语言并存 monorepo harness（rust/python/node 任意 ≥2 组合）。
# 用法:
#   init-multi.sh <lang1,lang2,...> [项目根名]
#   例: init-multi.sh rust,python,node my-monorepo
#       init-multi.sh rust,python
#       init-multi.sh rust,node
# 第一个语言=主语言（基底 ci.yml/release.yml/lefthook.yml/.pre-commit-config.yaml），
# 其余=次语言（prefix {lang}- 避免覆盖；hook 配置成 {lang}-lefthook.yml/{lang}-.pre-commit-config.yaml 待合并片段）。
# 各语言脚手架在 $PROJ_DIR/<lang>/ 子目录；仓库根放共享 .github/ + hook 配置 + .gitignore。
#
# 边界: 支持全部 9 种语言。各语言脚手架在 $PROJ_DIR/<lang>/ 子目录。
# 注意: java/mvnrchetype 和 ruby/bundle gem 会嵌套建目录，需特殊处理。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

LANGS="${1:-}"
ROOT_NAME="${2:-}"
[ -n "$LANGS" ] || die "用法: init-multi.sh <lang1,lang2,...> [项目根名]  例: init-multi.sh rust,python,node"

IFS=',' read -ra LANG_ARR <<< "$LANGS"
[ "${#LANG_ARR[@]}" -ge 2 ] || die "至少需 2 种语言（逗号分隔），如 rust,python"

# Node 包管理器检测（setup_lang_deps 的 node 分支用）
if command -v pnpm >/dev/null 2>&1; then PKG=pnpm; PKG_DEV_FLAG=-D
elif command -v npm >/dev/null 2>&1; then PKG=npm; PKG_DEV_FLAG=-D
elif command -v bun >/dev/null 2>&1; then PKG=bun; PKG_DEV_FLAG=--dev
else PKG=; PKG_DEV_FLAG=; fi  # 无 node 包管理器时留空（非 node 项目不影响）

# 校验语言（重复也拒，避免无意义主次同名）
for L in "${LANG_ARR[@]}"; do
  case "$L" in
    rust|python|node|go|java|cpp|ruby|php|dotnet) ;;
    *) die "语言 '$L' 未知。支持: rust python node go java cpp ruby php dotnet" ;;
  esac
done

# 重复检测（注释承诺"重复也拒"）— bash 3+ 兼容字符串匹配（不用 declare -A）
_seen=""
for L in "${LANG_ARR[@]}"; do
  case " $_seen " in
    *" $L "*) die "语言 '$L' 重复（主次同名无意义）。传入: $LANGS" ;;
  esac
  _seen="$_seen $L"
done

# 确定仓库根
if [ -n "$ROOT_NAME" ]; then
  mkdir -p "$ROOT_NAME" && cd "$ROOT_NAME"
fi
PROJ_DIR="$(pwd)"
# shellcheck disable=SC2034  # harness_finalize_multi 读取
LANG_NAME="Multi (${LANGS})"
export PROJ_DIR LANGS   # harness_finalize_multi 读

# scaffold_lang <lang> <dir> — 在 <dir> 子目录跑语言原生脚手架
scaffold_lang() {
  local lang="$1" dir="$2"
  mkdir -p "$dir"
  ( cd "$dir"
    case "$lang" in
      rust)
        require_cmd cargo
        cargo init -q --name "$(basename "$dir")" >/dev/null
        ;;
      python)
        require_cmd uv
        uv init --lib >/dev/null 2>&1 || uv init >/dev/null 2>&1 || die "uv init 失败"
        ;;
      node)
        # PKG 已在脚本顶部检测
        [ -n "$PKG" ] || die "node 缺少 pnpm/npm/bun"
        $PKG init -y >/dev/null
        ;;
      go)
        require_cmd go
        local mod
        mod="github.com/$(whoami)/$(basename "$dir")"
        go mod init "$mod" >/dev/null
        ;;
      java)
        require_cmd mvn
        # mvn archetype:generate 会嵌套建目录，用临时目录 + 移动文件规避
        local tmpdir=".pangu-mvn-tmp"
        mkdir -p "$tmpdir"
        mvn -B archetype:generate \
          -DgroupId=com.example \
          -DartifactId="$(basename "$dir")" \
          -DarchetypeGroupId=org.apache.maven.archetypes \
          -DarchetypeArtifactId=maven-archetype-quickstart \
          -DarchetypeVersion=1.5 \
          -DinteractiveMode=false \
          -DoutputDirectory="$tmpdir" >/dev/null 2>&1
        # 移动生成的文件到当前目录（跳过外层包装目录）
        if [ -d "$tmpdir/$(basename "$dir")" ]; then
          mv "$tmpdir/$(basename "$dir")"/* . 2>/dev/null || true
          mv "$tmpdir/$(basename "$dir")"/.* . 2>/dev/null || true
        fi
        rm -rf "$tmpdir"
        ;;
      cpp)
        mkdir -p src include tests
        if [ ! -f src/main.cpp ]; then
          cat > src/main.cpp <<'CPP'
#include <iostream>

int main() {
    std::cout << "hello\n";
    return 0;
}
CPP
        fi
        ;;
      ruby)
        require_cmd bundle
        # bundle gem 会嵌套建目录，用 bundle init 代替（生成 Gemfile 即可）
        bundle init >/dev/null 2>&1 || die "bundle init 失败"
        ;;
      php)
        require_cmd composer
        composer init --no-interaction \
          --type=project --license=MIT \
          --name="$(whoami | tr '[:upper:]' '[:lower:]')/$(basename "$dir" | tr '[:upper:]' '[:lower:]')" \
          >/dev/null 2>&1 || composer init --no-interaction >/dev/null 2>&1 \
          || die "composer init 失败"
        ;;
      dotnet)
        require_cmd dotnet
        local _name
        _name="$(basename "$dir")"
        dotnet new console -n "$_name" -o . >/dev/null 2>&1 \
          || dotnet new console >/dev/null 2>&1 \
          || die "dotnet new console 失败"
        ;;
    esac
  )
  log "$lang 脚手架已生成 ($dir)"
}

# setup_lang_deps <lang> — copy_lang 之后：把根的 snippet/配置移入 <lang>/ 子目录 + 落地 + 装 dev 依赖
setup_lang_deps() {
  local lang="$1" sub="$PROJ_DIR/$1"
  case "$lang" in
    rust) ;;  # rust 无 dev-deps 添加；rustfmt/clippy/deny 在根，cargo fmt 向上查找即可
    python)
      ( cd "$sub"
        uv add --dev ruff mypy bandit pip-audit pytest pytest-cov \
          || warn "python uv add 失败，请手动: uv add --dev ruff mypy bandit pip-audit pytest pytest-cov"
      )
      # pyproject-tooling.toml 在根（copy_lang 原样拷），python/pyproject.toml 在子目录 → warn 手动合并
      [ -f "$PROJ_DIR/pyproject-tooling.toml" ] \
        && warn "Python: 把根目录 pyproject-tooling.toml 的 [tool.*] 段合并到 $sub/pyproject.toml 后删除该文件"
      ;;
    node)
      ( cd "$sub"
        $PKG add $PKG_DEV_FLAG typescript @types/node prettier eslint @eslint/js typescript-eslint \
          eslint-plugin-security vitest @vitest/coverage-v8 \
          || warn "node $PKG add $PKG_DEV_FLAG 失败，请手动安装上述 dev 依赖"
        # copy_lang 把 snippet/tsconfig 拷到仓库根（非冲突文件原样），移入 node/ 子目录
        [ -f "$PROJ_DIR/eslint-flat.snippet.js" ] && [ ! -f eslint.config.js ] \
          && mv "$PROJ_DIR/eslint-flat.snippet.js" eslint.config.js && ok "node/eslint.config.js 已生成"
        [ -f "$PROJ_DIR/tsconfig.json" ] && [ ! -f tsconfig.json ] \
          && mv "$PROJ_DIR/tsconfig.json" tsconfig.json
        [ -f "$PROJ_DIR/vitest.config.ts" ] && [ ! -f vitest.config.ts ] \
          && mv "$PROJ_DIR/vitest.config.ts" vitest.config.ts
      )
      # 使用公共函数合并 prettier snippet（DRY，与 init-node.sh 共享）
      merge_node_snippet "$sub"
      ;;
    go)
      # Go 无 dev deps，但提示工具安装
      for cmd in golangci-lint gosec govulncheck; do
        command -v "$cmd" >/dev/null 2>&1 || warn "Go: 缺少 $cmd（CI 自动安装，本地建议安装）"
      done
      ;;
    java)
      # pom-plugins.snippet.xml 在根（copy_lang 原样拷），java/pom.xml 在子目录 → warn 手动合并
      [ -f "$PROJ_DIR/pom-plugins.snippet.xml" ] \
        && warn "Java: 把根目录 pom-plugins.snippet.xml 合并到 $sub/pom.xml 后删除该文件"
      ;;
    cpp) ;;  # C++ 无 dev deps；clang-format/clang-tidy/cppcheck 在 CI 装
    ruby)
      ( cd "$sub"
        if [ -f Gemfile ]; then
          bundle add rspec rubocop rubocop-rspec simplecov bundler-audit --group development \
            || warn "ruby bundle add 失败，请手动: bundle add rspec rubocop simplecov bundler-audit --group development"
        fi
      )
      ;;
    php)
      ( cd "$sub"
        composer require --dev friendsofphp/php-cs-fixer vimeo/psalm phpunit/phpunit \
          || warn "php composer require --dev 失败，请手动安装 php-cs-fixer/psalm/phpunit"
      )
      ;;
    dotnet)
      ( cd "$sub"
        dotnet add package SecurityCodeScan.VS2019 \
          || warn "dotnet add SecurityCodeScan 失败，请手动添加"
        dotnet add package coverlet.collector \
          || warn "dotnet add coverlet.collector 失败，请手动添加"
      )
      ;;
  esac
}

# --- 主语言：脚手架 + harness 基底 ---
MAIN="${LANG_ARR[0]}"
log "主语言: $MAIN（基底 ci.yml/release.yml/hook）"
scaffold_lang "$MAIN" "$PROJ_DIR/$MAIN"
copy_common
copy_lang "$MAIN"
setup_lang_deps "$MAIN"

# --- 次语言：脚手架 + harness prefix 片段 ---
for ((i=1; i<${#LANG_ARR[@]}; i++)); do
  L="${LANG_ARR[$i]}"
  log "次语言: $L（prefix ${L}- 片段）"
  scaffold_lang "$L" "$PROJ_DIR/$L"
  copy_lang "$L" "$L"
  setup_lang_deps "$L"
done

echo
warn "Hook 合并: 主语言 $MAIN 的 .pre-commit-config.yaml/lefthook.yml 为基底；"
warn "  次语言的 {lang}- 片段需按 references/multi-language.md 语义合并后删除。"

git_init
install_hooks
harness_finalize_multi
