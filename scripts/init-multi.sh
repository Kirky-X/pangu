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
# 边界: 第一版内置 rust/python/node（脚手架可在预设子目录干净跑）。
#   含 java/go/cpp/ruby/php/dotnet 的组合见 references/multi-language.md 手动并存步骤。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

LANGS="${1:-}"
ROOT_NAME="${2:-}"
[ -n "$LANGS" ] || die "用法: init-multi.sh <lang1,lang2,...> [项目根名]  例: init-multi.sh rust,python,node"

IFS=',' read -ra LANG_ARR <<< "$LANGS"
[ "${#LANG_ARR[@]}" -ge 2 ] || die "至少需 2 种语言（逗号分隔），如 rust,python"

# 校验语言（重复也拒，避免无意义主次同名）
for L in "${LANG_ARR[@]}"; do
  case "$L" in
    rust|python|node) ;;
    *) die "语言 '$L' 暂未内置并存支持（第一版仅 rust/python/node）。含 $L 的组合请按 references/multi-language.md 手动并存。" ;;
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
        if command -v pnpm >/dev/null 2>&1; then PKG=pnpm
        elif command -v npm >/dev/null 2>&1; then PKG=npm
        else die "node 缺少 pnpm/npm"; fi
        $PKG init -y >/dev/null
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
        $PKG add -D typescript @types/node prettier eslint @eslint/js typescript-eslint \
          eslint-plugin-security vitest @vitest/coverage-v8 \
          || warn "node $PKG add -D 失败，请手动安装上述 dev 依赖"
        # copy_lang 把 snippet/tsconfig 拷到仓库根（非冲突文件原样），移入 node/ 子目录
        [ -f "$PROJ_DIR/eslint-flat.snippet.js" ] && [ ! -f eslint.config.js ] \
          && mv "$PROJ_DIR/eslint-flat.snippet.js" eslint.config.js && ok "node/eslint.config.js 已生成"
        [ -f "$PROJ_DIR/tsconfig.json" ] && [ ! -f tsconfig.json ] \
          && mv "$PROJ_DIR/tsconfig.json" tsconfig.json
        [ -f "$PROJ_DIR/vitest.config.ts" ] && [ ! -f vitest.config.ts ] \
          && mv "$PROJ_DIR/vitest.config.ts" vitest.config.ts
        if [ -f "$PROJ_DIR/prettier.snippet.json" ] && [ -f package.json ]; then
          node -e "
            const fs=require('fs');
            const pkg=JSON.parse(fs.readFileSync('package.json','utf8'));
            const snip=JSON.parse(fs.readFileSync('$PROJ_DIR/prettier.snippet.json','utf8'));
            pkg.scripts=Object.assign({},pkg.scripts||{},snip.scripts||{});
            if(snip.prettier)pkg.prettier=snip.prettier;
            if(snip.engines)pkg.engines=snip.engines;
            fs.writeFileSync('package.json',JSON.stringify(pkg,null,2)+'\n');
          " && rm "$PROJ_DIR/prettier.snippet.json" && ok "node/package.json 已合并 scripts/prettier/engines"
        fi
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
