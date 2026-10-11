#!/usr/bin/env bash
# 构建期分发生成器：从 skill 仓库生成两类分发物——
#   ① 同构运行时整目录镜像（.trae/skills/<name>/，目录结构与原生一致，可按需加载全部 references）
#   ② 无渐进披露能力运行时的浓缩单文件（Cursor mdc / AGENTS.md / copilot-instructions.md）
# 浓缩版口径：方法完整、门禁完整，references 细节为概要；需深度时把 references/ 一起复制过去。
# 与 install-skill.sh 分层：本脚本产出入库物（构建期生成，随仓库提交）；install-skill.sh 做安装期复制（按需部署到全局 agent 目录）。
#
# 用法:
#   gen-distribution.sh <skill-dir> [--globs "a/**,b/**"] [--mirror-root <root>] [--dry-run]
#   --globs        Cursor mdc frontmatter 的触发通配（逗号分隔；本 skill 产物文件路径）。
#                  省略则不写 globs 键，mdc 以 alwaysApply:false 按需加载
#   --mirror-root 同构镜像的运行时根目录（默认 .trae；可传 .trae-cn/.codebuddy 等同构运行时）
#   --dry-run     只打印将生成的文件清单，不写盘
#
# 退出码: 0 成功 / 1 失败（用法错误、源目录不像 skill 仓库、镜像自校验不过）
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# --- 参数解析 ---
SKILL_DIR_ARG=""
GLOBS=""
MIRROR_ROOT=".trae"
DRY_RUN=0

usage() {
  cat <<EOF
用法: gen-distribution.sh <skill-dir> [--globs "a/**,b/**"] [--mirror-root <root>] [--dry-run]
  <skill-dir>    必填，指向 skill 仓库根目录（含 SKILL.md）
  --globs        Cursor mdc frontmatter 触发通配（逗号分隔，如 ".workbench/**,**/spec.md"）
  --mirror-root  同构镜像运行时根目录（默认 .trae；如 .trae-cn / .codebuddy）
  --dry-run      只打印将生成的文件清单，不写盘
  -h, --help     显示本帮助

例:
  gen-distribution.sh /path/to/my-skill
  gen-distribution.sh /path/to/my-skill --globs ".docs/**,**/DESIGN.md" --mirror-root .trae-cn
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --globs)
      [ $# -ge 2 ] || die "--globs 缺少参数值"
      case "$2" in --*) die "--globs 的值不能以 -- 开头: $2";; esac
      GLOBS="$2"; shift 2 ;;
    --mirror-root)
      [ $# -ge 2 ] || die "--mirror-root 缺少参数值"
      case "$2" in
        .|..|*/*) die "--mirror-root 必须是不含 / 的单层目录名（当前: '$2'）" ;;
        --*)      die "--mirror-root 的值不能以 -- 开头: $2" ;;
      esac
      MIRROR_ROOT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*)       die "未知选项: $1（用 -h 查看帮助）" ;;
    *)         if [ -z "$SKILL_DIR_ARG" ]; then SKILL_DIR_ARG="$1"; shift
               else die "参数过多: $1"; fi ;;
  esac
done

[ -n "$SKILL_DIR_ARG" ] || { usage; die "缺少必填参数 <skill-dir>"; }

case "$SKILL_DIR_ARG" in
  /*) SKILL_ROOT="$SKILL_DIR_ARG" ;;
  *)  SKILL_ROOT="$(pwd)/$SKILL_DIR_ARG" ;;
esac

[ -d "$SKILL_ROOT" ] || die "目录不存在: $SKILL_ROOT"
[ -f "$SKILL_ROOT/SKILL.md" ] || die "$SKILL_ROOT 不含 SKILL.md，不像 skill 仓库"

# 规范化（消除 ./ 与尾斜杠，保证 basename 得到真实 skill 名）
SKILL_ROOT="$(cd "$SKILL_ROOT" && pwd)"
SKILL_NAME="$(basename "$SKILL_ROOT")"
SKILL_MD="$SKILL_ROOT/SKILL.md"

# --- SKILL.md 内容提取（确定性 awk，无 LLM） ---

# frontmatter description 字段首行
frontmatter_description() {
  awk 'NR==1 && /^---/{fm=1; next} fm && /^---/{exit} fm && /^description:/{sub(/^description:[[:space:]]*/,""); print; exit}' "$1"
}

# 首个 H1 标题文本
first_h1() {
  awk '/^# /{sub(/^# /,""); print; exit}' "$1"
}

# frontmatter 之后、首个 ## 之前的引言语块（跳过 H1，避免与生成文件自己的标题重复）
intro_block() {
  awk 'NR==1 && /^---/{fm=1; next} fm && /^---/{fm=0; next} fm{next} /^## /{exit} /^# /{next} {print}' "$1"
}

# extract_sections <heading-regex>：匹配的**二级标题**章节全文（下一个二级标题处收束）。
# 只认 ## 为章节边界：三级及以下标题随当前章节输出，防止把 ### 子节从父节上下文里撕出来。
extract_sections() {
  awk -v pat="$1" '
    /^#{1,6}[[:space:]]/ {
      line=$0; lvl=0
      while (substr(line, lvl+1, 1) == "#") lvl++
      if (lvl == 2) {
        if (line ~ pat) { insec=1 } else { insec=0 }
        if (insec) print
        next
      }
      if (insec) print
      next
    }
    insec { print }
  ' "$SKILL_MD"
}

# bullets_of <heading-regex>：匹配章节内的列表项行（- 或数字. 开头）
bullets_of() {
  extract_sections "$1" | grep -E '^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]' || true
}

DESCRIPTION="$(frontmatter_description "$SKILL_MD" | sed 's/^"//; s/"$//')"
[ -n "$DESCRIPTION" ] || DESCRIPTION="$SKILL_NAME — see $SKILL_MD"
TITLE="$(first_h1 "$SKILL_MD")"
[ -n "$TITLE" ] || TITLE="$SKILL_NAME"
INTRO="$(intro_block "$SKILL_MD")"
ROUTING="$(extract_sections '路由|子命令|命令路由|用户意图')"
MANDATORY="$(extract_sections '约束汇总|禁止事项|Guardrails|失败模式|边界')"
REFS="$(extract_sections '参考|资产')"
NONNEG="$(bullets_of '约束汇总|禁止事项|Guardrails')"

# 章节识别为空 = 浓缩版结构不完整，必须响铃而不是静默产出空壳
[ -n "$ROUTING" ]   || warn "SKILL.md 未识别到路由/命令类二级章节——浓缩版仅含引言语块，路由部分为空"
[ -n "$MANDATORY" ] || warn "SKILL.md 未识别到约束/禁止/失败类二级章节——浓缩版缺强制流程，门禁完整性以 references/ 为准"
[ -n "$REFS" ]      || warn "SKILL.md 未识别到参考/资产类二级章节——浓缩版缺参考文件表"
[ -n "$NONNEG" ]    || warn "SKILL.md 未识别到非谈判项清单——copilot 版 Non-Negotiables 落回占位行"

BANNER="> 浓缩版：方法与门禁完整，references 细节为概要。需要深度时，把 references/ 一起复制过去，让它按需读。"

# YAML 单引号转义（'' 表示字面单引号）
yaml_escape() { printf "%s" "${1//\'/\'\'}"; }
# YAML 双引号串转义（\" 表示字面双引号，供 globs 列表项用）
yaml_escape_dq() { printf "%s" "${1//\"/\\\"}"; }

# --- 生成目标清单 ---
MIRROR_DIR="$SKILL_ROOT/$MIRROR_ROOT/skills/$SKILL_NAME"
MDC_FILE="$SKILL_ROOT/.cursor/rules/$SKILL_NAME.mdc"
AGENTS_FILE="$SKILL_ROOT/AGENTS.md"
COPILOT_FILE="$SKILL_ROOT/.github/copilot-instructions.md"

if [ "$DRY_RUN" -eq 1 ]; then
  cat <<EOF
[dry-run] 将为 $SKILL_NAME 生成:
  同构镜像: $MIRROR_DIR
  浓缩单文件: $MDC_FILE
  浓缩单文件: $AGENTS_FILE
  浓缩单文件: $COPILOT_FILE
EOF
  exit 0
fi

# --- ① 同构镜像（tar 排除用无 /  basename 模式，与 diff --exclude/align 语义一致，任意层级生效） ---
log "生成同构镜像 → $MIRROR_DIR"
rm -rf "$MIRROR_DIR"
mkdir -p "$MIRROR_DIR"
tar -c -C "$SKILL_ROOT" \
  --exclude=.git --exclude=.claude-plugin --exclude=.claude \
  --exclude=.github --exclude=.githooks --exclude=.absorb-external \
  --exclude=.trae --exclude=.trae-cn --exclude=.codebuddy --exclude=.cursor \
  --exclude=AGENTS.md \
  --exclude=specmark --exclude=__pycache__ --exclude=.pytest_cache \
  --exclude=.analysis --exclude=.venv --exclude=.meta --exclude=node_modules \
  --exclude=.vercel --exclude='*.pyc' --exclude=.coverage \
  --exclude=open-code-review --exclude=openspec --exclude=logs \
  --exclude=results.tsv --exclude='*.lock' \
  --exclude=corpus --exclude=temp \
  --exclude=.zcode --exclude=.mimocode --exclude=dependency_report.json \
  --exclude=agnes-output --exclude=boogu-output \
  --exclude=kolors-output --exclude=video-output \
  --exclude=.env --exclude='.env.*' --exclude='*.pem' --exclude='*.key' \
  --exclude=.netrc --exclude=.npmrc --exclude='credentials*' --exclude='id_rsa*' \
  --exclude='*.log' --exclude=.DS_Store \
  . | tar -x -C "$MIRROR_DIR" -f -
ok "同构镜像就位（diff -rq 自校验见下）"

# --- ② Cursor mdc（frontmatter 带 globs 挂产物路径，实现文件触发） ---
log "生成 Cursor 规则 → $MDC_FILE"
[ -f "$MDC_FILE" ] && warn "覆盖已存在的 $MDC_FILE"
mkdir -p "$(dirname "$MDC_FILE")"
{
  printf -- '---\n'
  printf "description: '%s'\n" "$(yaml_escape "$DESCRIPTION")"
  if [ -n "$GLOBS" ]; then
    printf 'globs:\n'
    printf '%s\n' "$GLOBS" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | while IFS= read -r g; do
      printf '  - "%s"\n' "$(yaml_escape_dq "$g")"
    done
  fi
  printf 'alwaysApply: false\n'
  printf -- '---\n\n'
  printf '%s\n\n' "$BANNER"
  printf '# %s\n\n' "$TITLE"
  [ -n "$INTRO" ] && printf '%s\n' "$INTRO"
  if [ -n "$ROUTING" ]; then
    printf '\n## 路由与命令\n\n%s\n' "$ROUTING"
  fi
  if [ -n "$MANDATORY" ]; then
    printf '\n## 强制流程与边界\n\n%s\n' "$MANDATORY"
  fi
  if [ -n "$REFS" ]; then
    printf '\n## 参考文件（按需深读）\n\n%s\n' "$REFS"
  fi
} > "$MDC_FILE"
ok "Cursor 规则就位"

# --- ③ AGENTS.md（按 概览→路由→命令→强制流程→reference 表 重排） ---
log "生成 AGENTS.md → $AGENTS_FILE"
[ -f "$AGENTS_FILE" ] && warn "覆盖已存在的 $AGENTS_FILE（如为手写版，先备份）"
mkdir -p "$(dirname "$AGENTS_FILE")"
{
  printf '# AGENTS — %s\n\n' "$SKILL_NAME"
  printf '%s\n\n' "$BANNER"
  printf '%s\n' "$INTRO"
  if [ -n "$ROUTING" ]; then
    printf '\n## 路由与命令\n\n%s\n' "$ROUTING"
  fi
  if [ -n "$MANDATORY" ]; then
    printf '\n## 强制流程与边界\n\n%s\n' "$MANDATORY"
  fi
  if [ -n "$REFS" ]; then
    printf '\n## 参考文件（按需深读）\n\n%s\n' "$REFS"
  fi
} > "$AGENTS_FILE"
ok "AGENTS.md 就位"

# --- ④ copilot-instructions（压缩为 Core Directive + Non-Negotiables） ---
log "生成 copilot-instructions → $COPILOT_FILE"
[ -f "$COPILOT_FILE" ] && warn "覆盖已存在的 $COPILOT_FILE"
mkdir -p "$(dirname "$COPILOT_FILE")"
{
  printf '# Copilot Instructions: %s\n\n' "$SKILL_NAME"
  printf '%s\n\n' "$BANNER"
  printf '## Core Directive\n\n'
  printf '%s\n' "$DESCRIPTION"
  printf '\n## Non-Negotiables\n\n'
  if [ -n "$NONNEG" ]; then
    printf '%s\n' "$NONNEG"
  else
    printf -- '- 以 SKILL.md 的约束汇总与禁止事项为准\n'
  fi
} > "$COPILOT_FILE"
ok "copilot-instructions 就位"

# --- 自校验：镜像与源逐字节一致（排除清单与 tar 侧同源；不过即失败，与 align [5/5] 口径一致） ---
if diff -rq "$SKILL_ROOT" "$MIRROR_DIR" \
    --exclude=.git --exclude=.claude-plugin --exclude=.claude \
    --exclude=.github --exclude=.githooks --exclude=.absorb-external \
    --exclude=.trae --exclude=.trae-cn --exclude=.codebuddy --exclude=.cursor \
    --exclude=AGENTS.md \
    --exclude=specmark --exclude=__pycache__ --exclude=.pytest_cache \
    --exclude=.analysis --exclude=.venv --exclude=.meta --exclude=node_modules \
    --exclude=.vercel --exclude='*.pyc' --exclude=.coverage \
    --exclude=open-code-review --exclude=openspec --exclude=logs \
    --exclude=results.tsv --exclude='*.lock' \
    --exclude=corpus --exclude=temp \
    --exclude=.zcode --exclude=.mimocode --exclude=dependency_report.json \
    --exclude=agnes-output --exclude=boogu-output \
    --exclude=kolors-output --exclude=video-output \
    --exclude=.env --exclude='.env.*' --exclude='*.pem' --exclude='*.key' \
    --exclude=.netrc --exclude=.npmrc --exclude='credentials*' --exclude='id_rsa*' \
    --exclude='*.log' --exclude=.DS_Store \
    >/dev/null 2>&1; then
  ok "diff -rq 自校验通过（镜像与主源一致）"
else
  die "diff -rq 自校验未过——镜像与主源不一致；检查排除项配置后重跑"
fi

log "分发物清单:"
printf '  %s\n' "$MIRROR_DIR" "$MDC_FILE" "$AGENTS_FILE" "$COPILOT_FILE"
log "浓缩版说明已写入三个单文件头部（方法完整、门禁完整、细节概要，需深度时连 references 一起复制）"
