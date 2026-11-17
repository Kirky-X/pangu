#!/usr/bin/env bash
# 存量 skill 仓库渐进式对齐标准 skill 模板。
# 用法:
#   align-skill.sh <skill-dir> [--dry-run] [--fix] [--only <检查项>]
#   --dry-run（默认）: 只检查不修改，有 ❌ 退出 1
#   --fix:            补齐缺失文件（不覆盖已有）、追加 .gitignore 缺失项、不碰 SKILL.md
#                     fix 后重新检查，全绿退出 0，否则退出 1
#   --only <检查项>:  只跑单项检查，只按该项判退出码（slug 或序号 1-5）
#                     可与 --fix 同用：fix 仍补齐全部缺失项，随后只重检所选项
#
# 检查清单:
#   - 8 个必备文件: .gitignore / LICENSE / skill.json / .claude-plugin/marketplace.json
#                   / .github/workflows/release.yml / README.md / README_EN.md / test-prompts.json
#   - .gitignore 关键忽略项: .DS_Store / .vscode / .meta / .venv / node_modules / __pycache__ / *.log / .env
#   - skill.json 8 字段: name / description / license / version / author / repo / homepage / tag
#     （与 pangu 实例 skill.json 字段名一致）
#   - LICENSE 类型: MIT
#   - 同构镜像一致性: .trae/.trae-cn/.codebuddy 下 skills/<name>/ 与主源 diff -rq 一致
#     （由 scripts/gen-distribution.sh 构建期生成；不一致即 FAIL）
#
# --only 可用检查项（slug（序号））:
#   files(1) 必备文件 | gitignore(2) .gitignore 关键忽略项 | skill-json(3) skill.json 字段
#   license(4) LICENSE 类型 | mirror(5) 同构镜像一致性
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

TPL_SKILL="$SKILL_DIR/templates/skill"

# --- 参数解析 ---
SKILL_DIR_ARG=""
MODE="dry-run"
ONLY=""

# 检查项注册表：slug 与名称同序（序号 = 下标 + 1）
CHECK_SLUGS=(files gitignore skill-json license mirror)
CHECK_NAMES=("必备文件" ".gitignore 关键忽略项" "skill.json 字段（8 字段）" "LICENSE 类型" "同构镜像一致性")

# resolve_only <raw> — 归一化 --only 取值（slug 或序号 1-5）到全局 ONLY；非法值 die
resolve_only() {
  local raw="$1" i
  case "$raw" in
    1) ONLY="files"; return 0 ;;
    2) ONLY="gitignore"; return 0 ;;
    3) ONLY="skill-json"; return 0 ;;
    4) ONLY="license"; return 0 ;;
    5) ONLY="mirror"; return 0 ;;
  esac
  for i in "${!CHECK_SLUGS[@]}"; do
    if [ "${CHECK_SLUGS[$i]}" = "$raw" ]; then
      ONLY="${CHECK_SLUGS[$i]}"
      return 0
    fi
  done
  die "未知检查项: ${raw}（可用 slug: ${CHECK_SLUGS[*]}；或序号 1-5）"
}

# check_index <slug> — 该检查项在清单中的序号（1-5）
check_index() {
  local i
  for i in "${!CHECK_SLUGS[@]}"; do
    [ "${CHECK_SLUGS[$i]}" = "$1" ] && { printf '%d' $((i + 1)); return 0; }
  done
  printf '0'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) MODE="dry-run"; shift ;;
    --fix)     MODE="fix"; shift ;;
    --only)
      [ $# -ge 2 ] || die "--only 缺少检查项（用法: align-skill.sh <skill-dir> --only <检查项>）"
      resolve_only "$2"
      shift 2 ;;
    -h|--help)
      cat <<EOF
用法: align-skill.sh <skill-dir> [--dry-run] [--fix] [--only <检查项>]
  <skill-dir>  必填，指向已有 skill 仓库根目录
  --dry-run    默认。只检查不修改；有 ❌ 退出 1
  --fix        补齐缺失文件 + 追加 .gitignore 缺失项；fix 后重新检查，全绿退出 0
  --only       只跑单项检查，只按该项判退出码。检查项（slug（序号））:
                 files(1) 必备文件
                 gitignore(2) .gitignore 关键忽略项
                 skill-json(3) skill.json 字段
                 license(4) LICENSE 类型
                 mirror(5) 同构镜像一致性
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

# 规范化（消除 ./ 与尾斜杠，保证 basename 得到真实 skill 名）
TARGET_SKILL_DIR="$(cd "$TARGET_SKILL_DIR" && pwd)"

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

# check_files — [1/5] 8 个必备文件
check_files() {
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
}

# check_gitignore — [2/5] .gitignore 关键忽略项
check_gitignore() {
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
}

# check_skill_json — [3/5] skill.json 8 字段
check_skill_json() {
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
}

# check_license — [4/5] LICENSE 类型
check_license() {
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
}

# check_mirror — [5/5] 同构镜像一致性（diff -rq）
check_mirror() {
  local skill_name_local
  skill_name_local="$(basename "$TARGET_SKILL_DIR")"
  local mirror_found=0
  local mirror_roots=(".trae" ".trae-cn" ".codebuddy")
  local mirror_root mirror_path diff_out diff_n
  for mirror_root in "${mirror_roots[@]}"; do
    mirror_path="$TARGET_SKILL_DIR/$mirror_root/skills/$skill_name_local"
    [ -d "$mirror_path" ] || continue
    mirror_found=1
    if diff_out="$(diff -rq "$TARGET_SKILL_DIR" "$mirror_path" \
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
        2>&1)"; then
      mark_pass "$mirror_root/skills/${skill_name_local}（与主源一致）"
    else
      diff_n="$(printf '%s\n' "$diff_out" | grep -c . || true)"
      mark_fail "$mirror_root/skills/$skill_name_local 与主源不一致（$diff_n 处，跑 scripts/gen-distribution.sh 重建）："
      printf '%s\n' "$diff_out" | awk 'NF==0{next} c++<3{printf "        %s\n", $0}'
    fi
  done
  if [ "$mirror_found" -eq 0 ]; then
    mark_pass "无同构镜像目录（未配置分发，跳过）"
  fi
}

# want_check <slug> — 该项是否要跑（--only 时只跑所选项）
want_check() {
  [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]
}

# run_checks — 执行检查清单（--only 时只跑所选项），更新计数器
run_checks() {
  FAIL_COUNT=0; WARN_COUNT=0; PASS_COUNT=0
  printf '\n=== Skill 仓库对齐检查 ===\n'
  printf '目标: %s\n' "$TARGET_SKILL_DIR"
  printf '模式: %s\n' "$MODE"
  if [ -n "$ONLY" ]; then
    printf '单项: %s（%s/5 %s）\n' "$ONLY" "$(check_index "$ONLY")" "${CHECK_NAMES[$(check_index "$ONLY") - 1]}"
  fi
  printf '\n'

  if want_check files; then
    printf '[1/5] 必备文件\n'
    check_files
  fi

  if want_check gitignore; then
    printf '\n[2/5] .gitignore 关键忽略项\n'
    check_gitignore
  fi

  if want_check skill-json; then
    printf '\n[3/5] skill.json 字段（8 字段）\n'
    check_skill_json
  fi

  if want_check license; then
    printf '\n[4/5] LICENSE 类型\n'
    check_license
  fi

  if want_check mirror; then
    printf '\n[5/5] 同构镜像一致性\n'
    check_mirror
  fi

  printf '\n--- 汇总: ✅ %d  ❌ %d  ⚠️  %d ---\n' "$PASS_COUNT" "$FAIL_COUNT" "$WARN_COUNT"
}

# apply_fixes — 补齐缺失文件 + 追加 .gitignore 缺失项
apply_fixes() {
  printf '\n=== 应用修复 (--fix) ===\n'
  [ -d "$TPL_SKILL" ] || die "skill 模板目录不存在: ${TPL_SKILL}（无法 fix）"

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
    if [ -n "$ONLY" ]; then
      ok "单项检查通过: ${ONLY}，退出 0"
    else
      ok "全绿，退出 0"
    fi
    exit 0
  else
    if [ -n "$ONLY" ]; then
      die "单项检查未通过: ${ONLY}（❌ $FAIL_COUNT 项）"
    else
      die "仍有 ❌ $FAIL_COUNT 项未通过（可能需手动处理，如 skill.json 字段内容）"
    fi
  fi
else
  run_checks
  if [ "$FAIL_COUNT" -eq 0 ]; then
    if [ -n "$ONLY" ]; then
      ok "单项检查通过: ${ONLY}，退出 0"
    else
      ok "全绿，退出 0"
    fi
    exit 0
  else
    if [ -n "$ONLY" ]; then
      die "单项检查未通过: ${ONLY}（❌ $FAIL_COUNT 项）"
    else
      die "发现 ❌ $FAIL_COUNT 项问题（用 --fix 自动补齐缺失文件与 .gitignore；skill.json 字段内容需手动编辑）"
    fi
  fi
fi
