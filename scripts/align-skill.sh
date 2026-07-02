#!/usr/bin/env bash
# 存量 skill 仓库渐进式对齐标准 skill 模板。
# 用法:
#   align-skill.sh <skill-dir> [--dry-run] [--fix]
#   --dry-run（默认）: 只检查不修改，有 ❌ 退出 1
#   --fix:            补齐缺失文件（不覆盖已有）、追加 .gitignore 缺失项、不碰 SKILL.md
#                     fix 后重新检查，全绿退出 0，否则退出 1
#
# 检查清单:
#   - 8 个必备文件: .gitignore / LICENSE / skill.json / .claude-plugin/marketplace.json
#                   / .github/workflows/release.yml / README.md / README_EN.md / test-prompts.json
#   - .gitignore 关键忽略项: .DS_Store / .vscode / .meta / .venv / node_modules / __pycache__ / *.log / .env
#   - skill.json 8 字段: name / description / license / version / author / repo / homepage / tag
#     （与 pangu 实例 skill.json 字段名一致）
#   - LICENSE 类型: MIT
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

TPL_SKILL="$SKILL_DIR/templates/skill"

# --- 参数解析 ---
SKILL_DIR_ARG=""
MODE="dry-run"

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) MODE="dry-run"; shift ;;
    --fix)     MODE="fix"; shift ;;
    -h|--help)
      cat <<EOF
用法: align-skill.sh <skill-dir> [--dry-run] [--fix]
  <skill-dir>  必填，指向已有 skill 仓库根目录
  --dry-run    默认。只检查不修改；有 ❌ 退出 1
  --fix        补齐缺失文件 + 追加 .gitignore 缺失项；fix 后重新检查，全绿退出 0
EOF
      exit 0 ;;
    --*) die "未知选项: $1" ;;
    *)  if [ -z "$SKILL_DIR_ARG" ]; then SKILL_DIR_ARG="$1"; shift
        else die "参数过多: $1"; fi ;;
  esac
done

[ -n "$SKILL_DIR_ARG" ] || die "缺少必填参数 <skill-dir>（用法: align-skill.sh <skill-dir> [--dry-run|--fix]）"

# 转绝对路径
case "$SKILL_DIR_ARG" in
  /*) TARGET_SKILL_DIR="$SKILL_DIR_ARG" ;;
  *)  TARGET_SKILL_DIR="$(pwd)/$SKILL_DIR_ARG" ;;
esac

[ -d "$TARGET_SKILL_DIR" ] || die "目录不存在: $TARGET_SKILL_DIR"
[ -f "$TARGET_SKILL_DIR/SKILL.md" ] || die "$TARGET_SKILL_DIR 不含 SKILL.md，不像 skill 仓库"

# --- 用 skill-dir 名作 SKILL_NAME 占位符填充（--fix 时用）---
SKILL_NAME_FIX="$(basename "$TARGET_SKILL_DIR")"
SKILL_NAME_CN_FIX="$SKILL_NAME_FIX"
SKILL_AUTHOR_FIX="Kirky-X"
SKILL_DESCRIPTION_FIX="TODO: 填写本 skill 的描述"

# render_template <src.template> <dst>（与 init-skill.sh 同逻辑，独立复制避免触发初始化）
render_template() {
  local src="$1" dst="$2"
  local esc_name esc_cn esc_desc esc_author
  esc_name="${SKILL_NAME_FIX//|/\\|}";   esc_name="${esc_name//&/\\&}"
  esc_cn="${SKILL_NAME_CN_FIX//|/\\|}";  esc_cn="${esc_cn//&/\\&}"
  esc_desc="${SKILL_DESCRIPTION_FIX//|/\\|}"; esc_desc="${esc_desc//&/\\&}"
  esc_author="${SKILL_AUTHOR_FIX//|/\\|}";    esc_author="${esc_author//&/\\&}"
  sed -e "s|{{SKILL_NAME}}|${esc_name}|g" \
      -e "s|{{SKILL_NAME_CN}}|${esc_cn}|g" \
      -e "s|{{SKILL_DESCRIPTION}}|${esc_desc}|g" \
      -e "s|{{SKILL_AUTHOR}}|${esc_author}|g" \
      "$src" > "$dst"
}

# 计数器
FAIL_COUNT=0
WARN_COUNT=0
PASS_COUNT=0

mark_pass() { printf '  ✅ %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
mark_fail() { printf '  ❌ %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
mark_warn() { printf '  ⚠️  %s\n' "$1"; WARN_COUNT=$((WARN_COUNT + 1)); }

# run_checks — 执行完整检查清单，更新计数器
run_checks() {
  FAIL_COUNT=0; WARN_COUNT=0; PASS_COUNT=0
  printf '\n=== Skill 仓库对齐检查 ===\n'
  printf '目标: %s\n' "$TARGET_SKILL_DIR"
  printf '模式: %s\n\n' "$MODE"

  # --- [1/4] 必备文件 ---
  printf '[1/4] 必备文件\n'
  local required_files=(
    ".gitignore"
    "LICENSE"
    "skill.json"
    ".claude-plugin/marketplace.json"
    ".github/workflows/release.yml"
    "README.md"
    "README_EN.md"
    "test-prompts.json"
  )
  for f in "${required_files[@]}"; do
    if [ -f "$TARGET_SKILL_DIR/$f" ]; then
      mark_pass "$f"
    else
      mark_fail "$f （缺失）"
    fi
  done

  # --- [2/4] .gitignore 关键忽略项 ---
  printf '\n[2/4] .gitignore 关键忽略项\n'
  local gitignore_file="$TARGET_SKILL_DIR/.gitignore"
  local required_ignores=(".DS_Store" ".vscode" ".meta" ".venv" "node_modules" "__pycache__" "*.log" ".env")
  if [ -f "$gitignore_file" ]; then
    for pat in "${required_ignores[@]}"; do
      # 兼容 pat 与 pat/ 两种写法（.gitignore 惯例：目录带斜杠）
      if grep -qE "^[[:space:]]*${pat//\*/\\*}/?[[:space:]]*$" "$gitignore_file" 2>/dev/null; then
        mark_pass "$pat"
      else
        mark_fail "$pat （.gitignore 未含）"
      fi
    done
  else
    for pat in "${required_ignores[@]}"; do
      mark_fail "$pat （.gitignore 不存在）"
    done
  fi

  # --- [3/4] skill.json 8 字段 ---
  printf '\n[3/4] skill.json 字段（8 字段）\n'
  local skill_json="$TARGET_SKILL_DIR/skill.json"
  # 字段名与 pangu 实例 skill.json 一致（Rule 11 惯例优先）
  local required_fields=("name" "description" "license" "version" "author" "repo" "homepage" "tag")
  if [ -f "$skill_json" ]; then
    for fld in "${required_fields[@]}"; do
      # 检查 "field": 模式（允许前后空格）
      if grep -qE "\"${fld}\"[[:space:]]*:" "$skill_json" 2>/dev/null; then
        mark_pass "$fld"
      else
        mark_fail "$fld （skill.json 未含）"
      fi
    done
  else
    for fld in "${required_fields[@]}"; do
      mark_fail "$fld （skill.json 不存在）"
    done
  fi

  # --- [4/4] LICENSE 类型 ---
  printf '\n[4/4] LICENSE 类型\n'
  local license_file="$TARGET_SKILL_DIR/LICENSE"
  if [ -f "$license_file" ]; then
    if head -3 "$license_file" | grep -qi "MIT License" 2>/dev/null; then
      mark_pass "MIT License"
    else
      mark_fail "LICENSE 非 MIT（前 3 行未匹配 'MIT License'）"
    fi
  else
    mark_fail "LICENSE 不存在"
  fi

  printf '\n--- 汇总: ✅ %d  ❌ %d  ⚠️  %d ---\n' "$PASS_COUNT" "$FAIL_COUNT" "$WARN_COUNT"
}

# apply_fixes — 补齐缺失文件 + 追加 .gitignore 缺失项
apply_fixes() {
  printf '\n=== 应用修复 (--fix) ===\n'
  [ -d "$TPL_SKILL" ] || die "skill 模板目录不存在: $TPL_SKILL（无法 fix）"

  local fixed=0

  # 补缺失文件（不覆盖已有）
  printf '[补缺失文件]\n'
  cd "$TPL_SKILL"
  while IFS= read -r tpl; do
    rel="${tpl#./}"
    dest_rel="${rel%.template}"
    dest="$TARGET_SKILL_DIR/$dest_rel"
    if [ -f "$dest" ]; then
      printf '  ⏭️  %s （已存在，跳过）\n' "$dest_rel"
    else
      mkdir -p "$(dirname "$dest")"
      render_template "$tpl" "$dest"
      printf '  ➕ %s （已补齐）\n' "$dest_rel"
      fixed=$((fixed + 1))
    fi
  done < <(find . -type f -name '*.template')

  # 追加 .gitignore 缺失项
  printf '\n[追加 .gitignore 缺失项]\n'
  local gitignore_file="$TARGET_SKILL_DIR/.gitignore"
  local required_ignores=(".DS_Store" ".vscode" ".meta" ".venv" "node_modules" "__pycache__" "*.log" ".env")
  if [ ! -f "$gitignore_file" ]; then
    printf '  ➕ 创建 .gitignore\n'
    {
      printf '# --- align-skill 补齐 ---\n'
      for pat in "${required_ignores[@]}"; do printf '%s\n' "$pat"; done
    } > "$gitignore_file"
    fixed=$((fixed + 1))
  else
    local appended=0
    for pat in "${required_ignores[@]}"; do
      if grep -qE "^[[:space:]]*${pat//\*/\\*}/?[[:space:]]*$" "$gitignore_file" 2>/dev/null; then
        printf '  ⏭️  %s （已存在）\n' "$pat"
      else
        printf '%s\n' "$pat" >> "$gitignore_file"
        printf '  ➕ %s （已追加）\n' "$pat"
        appended=$((appended + 1))
      fi
    done
    [ "$appended" -gt 0 ] && fixed=$((fixed + 1))
  fi

  # 不修改 SKILL.md（避免破坏现有内容）—— 显式声明
  printf '\n[SKILL.md]\n  ⏭️  SKILL.md （不修改，避免破坏现有内容）\n'

  printf '\n--- 修复完成: 共处理 %d 项 ---\n' "$fixed"
}

# --- 主流程 ---
if [ "$MODE" = "fix" ]; then
  apply_fixes
  printf '\n=== 修复后重新检查 ===\n'
  run_checks
  if [ "$FAIL_COUNT" -eq 0 ]; then
    ok "全绿，退出 0"
    exit 0
  else
    die "仍有 ❌ $FAIL_COUNT 项未通过（可能需手动处理，如 skill.json 字段内容）"
  fi
else
  run_checks
  if [ "$FAIL_COUNT" -eq 0 ]; then
    ok "全绿，退出 0"
    exit 0
  else
    die "发现 ❌ $FAIL_COUNT 项问题（用 --fix 自动补齐缺失文件与 .gitignore；skill.json 字段内容需手动编辑）"
  fi
fi
