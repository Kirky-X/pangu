#!/usr/bin/env bash
# 一键初始化 skill 仓库（遵循标准 skill 模板结构）。
# 这是 pangu 的第 10 种项目类型——meta 模式：用 pangu 初始化 skill 仓库本身。
# 用法:
#   init-skill.sh <skill-name> [--cn-name <中文名>] [--author <作者>] \
#                 [--description <描述>] [--target-dir <目录>]
#   例: init-skill.sh my-skill --cn-name 我的技能 --author Kirky-X \
#         --description "AI agent skill 模板" --target-dir ./my-skill
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

TPL_SKILL="$SKILL_DIR/templates/skill"

usage() {
  cat <<EOF
用法: init-skill.sh <skill-name> [选项]
  <skill-name>        必填，全小写字母+连字符（如 my-skill、specmark）

选项:
  --cn-name <name>      skill 中文名（默认与 skill-name 同）
  --author <author>     作者（默认 Kirky-X）
  --description <desc>  skill 描述（默认占位，建议手动填写）
  --target-dir <dir>    目标目录（默认 ./<skill-name>）
  -h, --help            显示本帮助

例:
  init-skill.sh my-skill --cn-name 我的技能 --description "AI agent skill 模板"
  init-skill.sh specmark --target-dir /tmp/specmark
EOF
}

# --- 参数解析 ---
SKILL_NAME=""
SKILL_NAME_CN=""
SKILL_AUTHOR="Kirky-X"
SKILL_DESCRIPTION="TODO: 填写本 skill 的描述（用于 frontmatter description 与 README 简介）"
TARGET_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --cn-name)       SKILL_NAME_CN="$2"; shift 2 ;;
    --author)        SKILL_AUTHOR="$2"; shift 2 ;;
    --description)   SKILL_DESCRIPTION="$2"; shift 2 ;;
    --target-dir)    TARGET_DIR="$2"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    --*)             die "未知选项: $1（用 -h 查看帮助）" ;;
    *)               if [ -z "$SKILL_NAME" ]; then SKILL_NAME="$1"; shift
                     else die "参数过多: $1（skill-name 已设为 $SKILL_NAME）"; fi ;;
  esac
done

# --- [1/5] 参数校验 ---
log "[1/5] 参数校验..."

[ -n "$SKILL_NAME" ] || { usage; die "缺少必填参数 <skill-name>"; }

# 全小写字母+连字符（ponytail: 单一正则，不堆 case 分支）
case "$SKILL_NAME" in
  *[!a-z-]*|[!a-z]*|-*) die "skill-name 必须全小写字母+连字符，且不以连字符开头/结尾（当前: '$SKILL_NAME'）" ;;
esac

[ "${SKILL_NAME: -1}" != "-" ] || die "skill-name 不能以连字符结尾"

[ -n "$SKILL_NAME_CN" ] || SKILL_NAME_CN="$SKILL_NAME"
[ -n "$TARGET_DIR" ] || TARGET_DIR="./$SKILL_NAME"

# 转绝对路径（相对路径基于当前 cwd）
case "$TARGET_DIR" in
  /*) PROJ_DIR="$TARGET_DIR" ;;
  *)  PROJ_DIR="$(pwd)/$TARGET_DIR" ;;
esac

if [ -e "$PROJ_DIR" ] && [ -n "$(ls -A "$PROJ_DIR" 2>/dev/null)" ]; then
  die "目标目录已存在且非空: $PROJ_DIR（请指定空目录或新路径）"
fi

ok "skill-name=$SKILL_NAME  cn-name=$SKILL_NAME_CN  author=$SKILL_AUTHOR  target=$PROJ_DIR"

# --- [2/5] 创建目录结构 ---
log "[2/5] 创建目录结构..."
mkdir -p "$PROJ_DIR"/{.claude/skills/gitnexus,.claude-plugin,.github/workflows,references,scripts,specmark/changes,specmark/specs}
ok "目录结构就位: $PROJ_DIR"

# --- [3/5] 渲染模板 ---
log "[3/5] 渲染模板（替换 {{SKILL_NAME}}/{{SKILL_NAME_CN}}/{{SKILL_DESCRIPTION}}/{{SKILL_AUTHOR}}）..."

[ -d "$TPL_SKILL" ] || die "skill 模板目录不存在: $TPL_SKILL"

# render_template <src.template> <dst>
# 用 | 作 sed 分隔符避免 description 中的 / 冲突；转义 replacement 中的 | 和 &。
render_template() {
  local src="$1" dst="$2"
  local esc_name esc_cn esc_desc esc_author
  esc_name="${SKILL_NAME//|/\\|}";   esc_name="${esc_name//&/\\&}"
  esc_cn="${SKILL_NAME_CN//|/\\|}";  esc_cn="${esc_cn//&/\\&}"
  esc_desc="${SKILL_DESCRIPTION//|/\\|}"; esc_desc="${esc_desc//&/\\&}"
  esc_author="${SKILL_AUTHOR//|/\\|}";    esc_author="${esc_author//&/\\&}"
  sed -e "s|{{SKILL_NAME}}|${esc_name}|g" \
      -e "s|{{SKILL_NAME_CN}}|${esc_cn}|g" \
      -e "s|{{SKILL_DESCRIPTION}}|${esc_desc}|g" \
      -e "s|{{SKILL_AUTHOR}}|${esc_author}|g" \
      "$src" > "$dst"
}

# 遍历所有 .template 文件（含子目录），去后缀写入目标
cd "$TPL_SKILL"
tpl_count=0
while IFS= read -r tpl; do
  rel="${tpl#./}"                       # 去掉 ./ 前缀
  dest_rel="${rel%.template}"           # 去掉 .template 后缀
  dest="$PROJ_DIR/$dest_rel"
  mkdir -p "$(dirname "$dest")"
  render_template "$tpl" "$dest"
  tpl_count=$((tpl_count + 1))
done < <(find . -type f -name '*.template')

ok "已渲染 $tpl_count 个模板文件"

# --- [4/5] git init + 首次 stage（不自动 commit） ---
log "[4/5] git init + 首次 stage（不自动 commit，与 init-rust.sh 一致）..."
cd "$PROJ_DIR"
if [ -d .git ]; then
  log "检测到 .git 已存在，跳过 git init"
else
  git init -q
  ok "git 仓库已初始化"
fi
git add -A 2>/dev/null || true
ok "文件已 stage（未 commit，留给用户）"

# --- [5/5] 打印 next steps ---
log "[5/5] 完成。Next steps:"
cat <<EOF

————————————————————————————————————————————————————————
✅ skill 仓库已初始化: $PROJ_DIR

已创建 9 个文件:
  .gitignore  LICENSE  skill.json  SKILL.md
  README.md  README_EN.md  test-prompts.json
  .claude-plugin/marketplace.json  .github/workflows/release.yml

目录结构:
  .claude/skills/gitnexus/  .claude-plugin/  .github/workflows/
  references/  scripts/  specmark/{changes,specs}/

下一步（请手动编辑）:
  1. 编辑 SKILL.md —— 填充 frontmatter description 与 Workflow 章节
  2. 编辑 README.md / README_EN.md —— 替换 {{SKILL_DESCRIPTION}} 占位（如未通过 --description 传入）
  3. 编辑 skill.json —— 调整 description 字段与 tag 数组
  4. 编辑 test-prompts.json —— 填充测试用例（prompt + expectation）
  5. 在 references/ 添加参考资料
  6. 首次提交:
       cd $PROJ_DIR
       git commit -m "chore: bootstrap skill repo"
  7. 推 tag 触发 release:
       git tag v0.1.0 && git push --tags

对齐存量 skill 仓库用: bash $SKILL_DIR/scripts/align-skill.sh $PROJ_DIR --dry-run
————————————————————————————————————————————————————————
EOF
