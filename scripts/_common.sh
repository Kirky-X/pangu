#!/usr/bin/env bash
# pangu 公共函数库。被各 init-<lang>.sh source。
# 提供：日志、命令检测、模板拷贝、git 初始化、hook 安装、收尾提示。
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL_COMMON="$SKILL_DIR/templates/common"

# --- 版本常量与 harness 默认参数 ---
# COV_THRESHOLD 是覆盖率门禁默认阈值；init 脚本可用 --cov <N> / --profile <core|tool> 覆盖
# （渲染进模板的 __PANGU_COV__ 占位符，见 render_placeholders）
# shellcheck disable=SC2034  # parse_harness_args 与冒烟测试读取
COV_THRESHOLD=80
# shellcheck disable=SC2034
PRE_COMMIT_HOOKS_REV="v5.0.0"
# shellcheck disable=SC2034
TYPOS_REV="v1.28.0"

# --- harness 参数（init 脚本共用；旗标单一来源）---
# 用法（init 脚本 source 后、取位置参数前）:
#   parse_harness_args "$@"
#   set -- ${PANGU_POSITIONAL[@]+"${PANGU_POSITIONAL[@]}"}   # 剥离旗标，位置参数语义不变
# 旗标:
#   --cov <N>              覆盖率门禁阈值（默认 80）
#   --profile <core|tool>  分级阈值预设：core=85（核心业务逻辑）、tool=70（工具类）；
#                          SKILL.md 核心原则 4 的出口。显式 --cov 优先于 --profile
#   --branch <name>        默认分支（CI push 触发 + diff coverage 基线，默认 main）
#   --no-release           不生成 release.yml（tag 发布工作流）
#   --no-codeql            不生成 codeql.yml（语义级漏洞扫描）
#   --changelog <mode>     manual（默认，人工维护 CHANGELOG）/ release-please（附加 Release PR 自动化工作流）
#   --templates-only       只拷 harness 模板：跳过语言脚手架与依赖安装（冒烟测试/存量项目叠加用）
PANGU_COV="$COV_THRESHOLD"
PANGU_BRANCH="main"
PANGU_PROFILE="default"
PANGU_SKIP_RELEASE=0
PANGU_SKIP_CODEQL=0
PANGU_CHANGELOG="manual"
PANGU_TEMPLATES_ONLY=0
PANGU_POSITIONAL=()
parse_harness_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --cov)
        [ $# -ge 2 ] || die "--cov 需要数值参数（如 --cov 85）"
        case "$2" in ""|*[!0-9]*) die "--cov 须为正整数: $2" ;; esac
        # 上限 99：java 模板用 0.__PANGU_COV__ 渲染小数（0.100 会被解析为 10%）
        if [ "$2" -lt 10 ] || [ "$2" -gt 99 ]; then
          die "--cov 须在 10-99 之间（java pom 按 0.N 渲染小数比例）: $2"
        fi
        PANGU_COV="$2"; PANGU_PROFILE="custom"; shift 2 ;;
      --profile)
        [ $# -ge 2 ] || die "--profile 需要 core 或 tool"
        case "$2" in
          core) PANGU_COV=85; PANGU_PROFILE="core" ;;
          tool) PANGU_COV=70; PANGU_PROFILE="tool" ;;
          *) die "--profile 须为 core 或 tool（核心业务 85% / 工具类 70%，见 references/coverage-standards.md）" ;;
        esac
        shift 2 ;;
      --branch)
        [ $# -ge 2 ] || die "--branch 需要分支名"
        # 白名单 + git ref 规范双重校验：分支名会渲染进 workflow YAML 与 lefthook 的
        # shell 串（--compare-branch "origin/<branch>"），含引号/$/空格即是持久注入
        case "$2" in
          ""|*[!A-Za-z0-9._/-]*) die "--branch 仅允许字母数字与 . _ - / : $2" ;;
        esac
        if command -v git >/dev/null 2>&1; then
          git check-ref-format --allow-onelevel "$2" 2>/dev/null || die "--branch 不是合法 git 分支名: $2"
        fi
        PANGU_BRANCH="$2"; shift 2 ;;
      --no-release) PANGU_SKIP_RELEASE=1; shift ;;
      --no-codeql)  PANGU_SKIP_CODEQL=1; shift ;;
      --changelog)
        [ $# -ge 2 ] || die "--changelog 需要 manual 或 release-please"
        case "$2" in
          manual|release-please) PANGU_CHANGELOG="$2" ;;
          *) die "--changelog 须为 manual 或 release-please" ;;
        esac
        shift 2 ;;
      --templates-only) PANGU_TEMPLATES_ONLY=1; shift ;;
      -h|--help)
        printf 'harness 旗标: --cov <N> --profile <core|tool> --branch <name> --no-release --no-codeql --changelog <manual|release-please> --templates-only\n'
        exit 0 ;;
      --*) die "未知 harness 旗标: $1（支持 --cov/--profile/--branch/--no-release/--no-codeql/--changelog/--templates-only，-h 看帮助）" ;;
      *) PANGU_POSITIONAL+=("$1"); shift ;;
    esac
  done
}

# templates_only 收尾：清理未合并的 snippet（脚手架/依赖安装被跳过，snippet 无从合并）
templates_only_cleanup() {
  [ "$PANGU_TEMPLATES_ONLY" = "1" ] || return 0
  rm -f "$PROJ_DIR"/cargo-profile.snippet.toml "$PROJ_DIR"/pyproject-tooling.toml \
        "$PROJ_DIR"/eslint-flat.snippet.js "$PROJ_DIR"/prettier.snippet.json \
        "$PROJ_DIR"/pom-plugins.snippet.xml
}

# --- 幂等保护 ---
# check_idempotent <manifest_file> <lang>
# 检测目标目录是否已有语言 manifest 文件，已有则 warn 并跳过脚手架。
# 用法：在脚手架命令前调用，返回 0=可继续，1=已存在需跳过脚手架。
check_idempotent() {
  local manifest="$1" lang="${2:-}"
  if [ -f "$manifest" ]; then
    warn "检测到已有 $lang manifest（$manifest），跳过脚手架（避免覆盖）"
    return 0
  fi
  return 1
}

# 颜色日志
log()  { printf '\033[1;34m[harness]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# require_cmd <cmd> — 缺失即终止
# templates-only 模式下跳过脚手架与依赖安装，语言工具链无需在场 → 降级为 warn
require_cmd() {
  if [ "$PANGU_TEMPLATES_ONLY" = "1" ] && ! command -v "$1" >/dev/null 2>&1; then
    warn "templates-only 模式跳过工具检查: $1（未安装；正式初始化时必需）"
    return 0
  fi
  command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1（请先安装后再运行本脚本）"
}

# copy_common — 拷贝通用 GitHub 生态文件到 $PROJ_DIR
# --no-codeql 裁剪 codeql.yml；--changelog release-please 附加 release-please.yml（默认不生成）
copy_common() {
  [ -d "$TPL_COMMON" ] || die "通用模板目录不存在: $TPL_COMMON"
  log "拷贝通用 GitHub 生态文件 (dependabot/codeql/issue/pr/CODEOWNERS/editorconfig)"
  mkdir -p "$PROJ_DIR/.github/workflows" "$PROJ_DIR/.github/ISSUE_TEMPLATE"
  if [ -d "$TPL_COMMON/github" ]; then
    cp -r "$TPL_COMMON/github/." "$PROJ_DIR/.github/"
    if [ "$PANGU_SKIP_CODEQL" = "1" ] && [ -f "$PROJ_DIR/.github/workflows/codeql.yml" ]; then
      rm "$PROJ_DIR/.github/workflows/codeql.yml"
      log "--no-codeql: 已跳过 codeql.yml（SAST 由各语言专属工具兜底）"
    fi
  fi
  if [ "$PANGU_CHANGELOG" = "release-please" ]; then
    [ -f "$TPL_COMMON/release-please.yml" ] || die "release-please 模板缺失: $TPL_COMMON/release-please.yml"
    cp "$TPL_COMMON/release-please.yml" "$PROJ_DIR/.github/workflows/release-please.yml"
    log "--changelog release-please: release-please.yml 已生成（Release PR 自动维护 CHANGELOG）"
  fi
  [ -f "$TPL_COMMON/.editorconfig" ] && cp "$TPL_COMMON/.editorconfig" "$PROJ_DIR/.editorconfig"
  [ -f "$TPL_COMMON/LICENSE-MIT" ] && [ ! -f "$PROJ_DIR/LICENSE" ] && cp "$TPL_COMMON/LICENSE-MIT" "$PROJ_DIR/LICENSE"
  ok "通用文件就位"
}

# copy_lang <lang> [prefix] — 拷贝语言专属模板（ci/release → .github/workflows；其余 → 项目根）
# prefix（可选）：多语言并存时给冲突文件加前缀，避免次语言覆盖主语言基底：
#   - ci.yml/release.yml/codeql.yml → {prefix}-ci.yml 放 .github/workflows/
#   - lefthook.yml/.pre-commit-config.yaml → {prefix}-lefthook.yml 放项目根，作待合并片段
#   - 非冲突文件（rustfmt.toml/pyproject-tooling.toml/tsconfig.json 等语言配置）原样不前缀
# 不传 prefix = 单语言模式，行为不变（向后兼容 9 个 init-{L}.sh）。
copy_lang() {
  local lang="$1"
  local prefix="${2:-}"
  local src="$SKILL_DIR/templates/$lang"
  [ -d "$src" ] || die "语言模板不存在: $src"
  log "拷贝 $lang 专属模板 (ci/release/pre-commit/lefthook/配置/gitignore)${prefix:+ [prefix=$prefix]}"

  # workflow 文件汇入 .github/workflows/（prefix 模式加前缀避免多语言同名覆盖）
  # --no-release / --no-codeql 裁剪对应工作流（SKILL.md 阶段 0 意图确认的出口）
  local wf="$PROJ_DIR/.github/workflows"
  mkdir -p "$wf"
  local f b dest
  for f in ci.yml release.yml codeql.yml; do
    [ -f "$src/$f" ] || continue
    if [ "$f" = "release.yml" ] && [ "$PANGU_SKIP_RELEASE" = "1" ]; then continue; fi
    if [ "$f" = "codeql.yml" ] && [ "$PANGU_SKIP_CODEQL" = "1" ]; then continue; fi
    if [ -n "$prefix" ]; then
      cp "$src/$f" "$wf/${prefix}-${f}"
    else
      cp "$src/$f" "$wf/$f"
    fi
  done

  # 其余文件（.pre-commit-config.yaml / lefthook.yml / 语言配置）放项目根
  # dotglob: 让 glob 匹配 .pre-commit-config.yaml 等点开头文件（否则被静默漏拷 → pre-commit 永不安装）
  # nullglob: 目录为空时 glob 返回空，避免字面量 "$src/*" 误入循环
  local _restore_shopt
  # ponytail: shopt -p 在被查询选项未全部 enabled 时返回非 0（bash 文档：list 模式仅当全部 enabled 才 0）。
  # set -e 下赋值会继承该退出码并静默退出函数。|| true 吞退出码，输出文本（用于 eval 恢复）不受影响。
  _restore_shopt=$(shopt -p dotglob nullglob || true)
  shopt -s dotglob nullglob
  for f in "$src"/*; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    case "$b" in
      ci.yml|release.yml|codeql.yml) continue ;;  # 已拷到 workflows
      .gitignore) continue ;;  # ponytail: 由下方合并逻辑独占处理（首语言 cp 成基底/后续追加带段头段落）；循环里 cp 会让次语言覆盖主语言基底 + 同语言重复写入
      *.bak|*.bak.*|*.orig|*.backup|*.swp|*~) continue ;;  # ponytail: 防编辑器/darwin 备份残留污染用户项目。*.bak.* 覆盖 darwin 的 .bak.YYYYMMDD-HHMM 命名（曾发生 lefthook.yml.bak.20260702-0000 被拷入新项目根）
    esac
    # prefix 模式：hook 配置加前缀作待合并片段；语言配置（rustfmt.toml 等）原样
    if [ -n "$prefix" ] && { [ "$b" = "lefthook.yml" ] || [ "$b" = ".pre-commit-config.yaml" ]; }; then
      dest="$PROJ_DIR/${prefix}-${b}"
    else
      dest="$PROJ_DIR/$b"
    fi
    cp "$f" "$dest"
  done
  eval "$_restore_shopt"
  # 合并语言 .gitignore（追加到通用 .gitignore 之后）
  if [ -f "$src/.gitignore" ] && [ ! -f "$PROJ_DIR/.gitignore" ]; then
    cp "$src/.gitignore" "$PROJ_DIR/.gitignore"
  elif [ -f "$src/.gitignore" ]; then
    printf '\n# --- %s ---\n' "$lang" >> "$PROJ_DIR/.gitignore"
    cat "$src/.gitignore" >> "$PROJ_DIR/.gitignore"
  fi
  ok "$lang 模板就位"
}

# render_placeholders — 把模板占位符渲染为本次初始化的实际值。
# 占位符（预存在模板里，阈值/分支改动无需手改 9 套模板）:
#   __PANGU_COV__     → $PANGU_COV（覆盖率门禁阈值）
#   __PANGU_BRANCH__  → $PANGU_BRANCH（默认分支：CI push 触发 + diff coverage 基线）
# 渲染后仍有 __PANGU_* 残留 = 渲染遗漏，fail-closed 报错（禁止带占位符入库）。
render_placeholders() {
  local hits=0 f
  # 分支名可含 / | & 等特殊字符（如 feature/x），替换前按 sed|分隔符转义
  local branch_esc
  branch_esc="$(printf '%s' "$PANGU_BRANCH" | sed -e 's/[&|\\]/\\&/g')"
  # 排除依赖目录：存量项目叠加（--templates-only）时项目里可能有 node_modules/vendor/target
  # （实测 45k 文件项目两次扫描 ~1.7s，一次性命令可接受；排除依赖目录后更小）
  while IFS= read -r -d '' f; do
    sed -i.bak -e "s|__PANGU_COV__|${PANGU_COV}|g" -e "s|__PANGU_BRANCH__|${branch_esc}|g" "$f"
    rm -f "${f}.bak"
    hits=$((hits + 1))
  done < <(grep -rlZ --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor \
      --exclude-dir=target --exclude-dir=.venv \
      '__PANGU_COV__\|__PANGU_BRANCH__' "$PROJ_DIR" 2>/dev/null || true)
  if [ "$hits" -gt 0 ]; then
    ok "占位符已渲染 (cov=${PANGU_COV}% branch=${PANGU_BRANCH}，${hits} 个文件)"
  fi
  if grep -rq --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor \
      --exclude-dir=target --exclude-dir=.venv \
      '__PANGU_' "$PROJ_DIR" 2>/dev/null; then
    grep -rn --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor \
      --exclude-dir=target --exclude-dir=.venv \
      '__PANGU_' "$PROJ_DIR" 2>/dev/null | head -20 >&2 || true
    die "占位符渲染后有残留（见上）：render_placeholders 未覆盖该占位符名"
  fi
}

# write_pangu_meta — 生成来源记录（.pangu-meta.yml）。
# copier .copier-answers.yml 思路的最小闭环：pangu 不自动合并模板升级（生成物归项目所有），
# 但可追溯由哪个 pangu 版本/参数生成，模板演进后对照 repo 对应 tag 手动 diff。
write_pangu_meta() {
  local pangu_version
  # skill.json 缺失是合法状态（fake root/模板-only 场景）；set -e 下 sed 的退出码 2 会静默杀死 init，须连同退出码一起吞
  pangu_version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SKILL_DIR/skill.json" 2>/dev/null | head -1 || true)"
  pangu_version="${pangu_version:-unknown}"
  {
    printf '# pangu harness 元数据（生成来源记录）。生成物归本项目所有，pangu 不会自动覆盖。\n'
    printf '# 模板升级：对照 https://github.com/Kirky-X/pangu 对应版本 tag 的 templates/ 手动 diff。\n'
    printf 'pangu_version: %s\n' "$pangu_version"
    printf 'generated_at: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'coverage_threshold: %s\n' "$PANGU_COV"
    printf 'threshold_profile: %s\n' "$PANGU_PROFILE"
    printf 'default_branch: "%s"\n' "$PANGU_BRANCH"
    printf 'changelog: %s\n' "$PANGU_CHANGELOG"
    printf 'release_workflow: %s\n' "$([ "$PANGU_SKIP_RELEASE" = "1" ] && echo disabled || echo enabled)"
    printf 'codeql: %s\n' "$([ "$PANGU_SKIP_CODEQL" = "1" ] && echo disabled || echo enabled)"
    printf 'harness_files:\n'
    # 清单覆盖：github 全目录 + 根目录 harness 文件 + hook 前缀片段（multi/FFI）+ 语言配置
    # （升级 diff 的依据，宁全勿缺；缺失路径被 find 的 2>/dev/null 静默跳过）
    (cd "$PROJ_DIR" && { find .github .editorconfig .gitignore .pre-commit-config.yaml lefthook.yml \
        '*-lefthook.yml' '*-.pre-commit-config.yaml' \
        rustfmt.toml clippy.toml deny.toml pyproject-tooling.toml tsconfig.json vitest.config.ts \
        .golangci.yaml Makefile CMakeLists.txt .rubocop.yml .php-cs-fixer.php phpunit.xml psalm.xml \
        Directory.Build.props -type f 2>/dev/null || true; } | sort -u) | sed 's/^/  - /'
  } > "$PROJ_DIR/.pangu-meta.yml"
  ok "生成来源已记录: .pangu-meta.yml (pangu v$pangu_version)"
}

git_init() {
  cd "$PROJ_DIR"
  if [ -d .git ]; then
    log "检测到 .git（语言脚手架或既有仓库已创建），git init 已就位"
  else
    log "git init"
    git init -q
    ok "git 仓库已初始化"
  fi
}

# install_hooks — 调用 install-hooks.sh（pre-commit + lefthook 按已装工具启用）
install_hooks() {
  cd "$PROJ_DIR"
  log "安装本地 commit hooks"
  bash "$SKILL_DIR/scripts/install-hooks.sh" || warn "hook 安装未全部完成（见上方提示）"
}

# merge_node_snippet <proj_dir>
# 合并 prettier.snippet.json 到 package.json（scripts/prettier/engines）。
# 由 init-node.sh 和 init-multi.sh 共享调用（DRY）。
# 成功合并后删除 snippet 文件；node 未装则 warn + 保留 snippet。
merge_node_snippet() {
  local dir="$1"
  [ -f "$dir/prettier.snippet.json" ] || return 0
  [ -f "$dir/package.json" ] || return 0
  if ! command -v node >/dev/null 2>&1; then
    warn "node 未安装，prettier.snippet.json 未自动合并（手动合并 scripts/prettier/engines 到 package.json）"
    return 0
  fi
  (
    cd "$dir"
    node -e '
      const fs = require("fs");
      const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
      const snip = JSON.parse(fs.readFileSync("prettier.snippet.json", "utf8"));
      pkg.scripts = Object.assign({}, pkg.scripts || {}, snip.scripts || {});
      if (snip.prettier) pkg.prettier = snip.prettier;
      if (snip.engines) pkg.engines = snip.engines;
      fs.writeFileSync("package.json", JSON.stringify(pkg, null, 2) + "\n");
    ' && rm -f prettier.snippet.json && ok "package.json 已合并 scripts/prettier/engines"
  )
}

# harness_finalize — 渲染占位符、记录生成来源、stage 全部文件并打印下一步指引
harness_finalize() {
  cd "$PROJ_DIR"
  templates_only_cleanup
  render_placeholders
  write_pangu_meta
  git add -A 2>/dev/null || true
  cat <<EOF

————————————————————————————————————————————————————————
✅ $LANG_NAME harness 初始化完成: $PROJ_DIR

下一步:
  1. 启用本地 hook（二选一，配置都已生成）:
       pre-commit install     # 需先 uv tool install pre-commit
       lefthook install       # 需先 brew install lefthook
  2. 检查 .github/workflows/ 下 ci.yml / release.yml，阈值已按本次参数渲染（覆盖率 ${PANGU_COV}%）
  3. 配置发布 secret（可选）:
       "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/references/registry-secrets.md"
  4. 首次提交:
       git commit -m "chore: bootstrap project harness"
  5. 推 tag 触发 release（自动建 GitHub Release，配了 secret 则发 registry）:
       git tag v0.1.0 && git push --tags
  6. 诊断 harness 完整性（文件/YAML/hooks/门禁）:
       bash "$SKILL_DIR/scripts/doctor.sh" "$PROJ_DIR"
  生成来源已记录在 .pangu-meta.yml（pangu 版本/参数/harness 文件清单）
————————————————————————————————————————————————————————
EOF
}

# apply_ffi_harness <bind_lang> — 在已含官方 FFI 脚手架的目录叠加 harness。
# bind_lang: python (maturin/PyO3) 或 node (napi-rs)。rust 与绑定语言同根（maturin/napi 设计如此）。
# 半自动：检测官方产物 → 未就位 die 提示先跑官方命令 → 已就位则叠加 harness。
# 职责单一：官方工具管骨架，本函数管 harness（CI/release/hook/配置）。
apply_ffi_harness() {
  local bind_lang="$1"
  PROJ_DIR="${PROJ_DIR:-$(pwd)}"
  cd "$PROJ_DIR"

  local bind_manifest bind_marker scaffold_cmd
  case "$bind_lang" in
    python)
      bind_manifest="pyproject.toml"
      bind_marker='\[tool.maturin\]'        # maturin mixed layout 标志
      scaffold_cmd="maturin new --mixed --bindings pyo3 <name>"
      ;;
    node)
      bind_manifest="package.json"
      bind_marker='"napi"'                   # package.json 含 napi 脚本/依赖
      scaffold_cmd="napi new"
      ;;
    *) die "apply_ffi_harness: 未知绑定语言 '$bind_lang'（仅支持 python/node）" ;;
  esac

  if [ ! -f "$PROJ_DIR/Cargo.toml" ] || [ ! -f "$PROJ_DIR/$bind_manifest" ]; then
    die "未检测到 $bind_lang FFI 脚手架产物（期望同根存在 Cargo.toml + $bind_manifest）。
请先在目标目录跑官方脚手架命令:  $scaffold_cmd
完成后重跑本脚本叠加 harness（CI/release/hook/配置）。"
  fi
  # ponytail: marker 仅 warn 不 die——脚手架版本演进可能改格式，硬卡会误杀
  grep -q "$bind_marker" "$PROJ_DIR/$bind_manifest" 2>/dev/null \
    || warn "未在 $bind_manifest 找到 '$bind_marker' 标志——确认这是 $bind_lang FFI（而非纯 rust）项目"

  log "检测到 $bind_lang FFI 脚手架，叠加 harness"
  copy_common
  copy_lang rust                          # 基底 ci.yml/release.yml/lefthook.yml/.pre-commit-config.yaml
  copy_lang "$bind_lang" "$bind_lang"     # prefix: {bind}-ci.yml + {bind}-lefthook.yml 片段（不覆盖基底）

  echo
  warn "Hook 合并: rust 的 .pre-commit-config.yaml/lefthook.yml 为基底；"
  warn "  ${bind_lang}-.pre-commit-config.yaml / ${bind_lang}-lefthook.yml 为待合并片段。"
  warn "  按 references/multi-language.md 语义合并后删除片段文件。"

  git_init
  install_hooks
  LANG_NAME="Rust+${bind_lang}"
  harness_finalize
}

# harness_finalize_multi — 多语言并存 monorepo 收尾。
# 依赖 init-multi.sh 设的 $PROJ_DIR + $LANGS（逗号分隔语言列表）。
harness_finalize_multi() {
  cd "$PROJ_DIR"
  templates_only_cleanup
  render_placeholders
  write_pangu_meta
  git add -A 2>/dev/null || true
  # 收集待合并 hook 片段文件列表（在 heredoc 外计算，避免 shellcheck SC2012）
  local _hook_fragments
  _hook_fragments=$(find "$PROJ_DIR" -maxdepth 1 \( -name '*-.pre-commit-config.yaml' -o -name '*-lefthook.yml' \) 2>/dev/null | sed 's/^/  - /' || echo '  （无）')
  cat <<EOF

————————————————————————————————————————————————————————
✅ 多语言 harness 初始化完成: $PROJ_DIR

语言（主→次）: $LANGS

待合并 hook 片段（主语言为基底，次语言片段需语义合并后删除）:
$_hook_fragments

下一步:
  1. 按 references/multi-language.md 合并 hook 片段（主语言基底 + 次语言 {lang}- 片段）
  2. 启用本地 hook（二选一，配置都已生成）:
       pre-commit install     # 需先 uv tool install pre-commit
       lefthook install       # 需先 brew install lefthook
  3. 各语言 dev 依赖与配置见对应子目录
  4. 首次提交:
       git commit -m "chore: bootstrap multi-lang harness"
————————————————————————————————————————————————————————
EOF
}
