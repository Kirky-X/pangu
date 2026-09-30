#!/usr/bin/env bash
# doctor — 已生成项目的 harness 静态诊断（面向用户环境，非 pangu 自检；pangu 自检用 selfcheck.sh）。
# 检查目标目录的: 必备文件 / YAML 可解析 / git 仓库 / hooks 安装状态 / 占位符残留 / 门禁在位 / .pangu-meta。
# 用法:
#   scripts/doctor.sh [项目目录]     # 默认当前目录
# 退出码: 0=全部通过，1=存在 ✗ 项（修复后重跑）
set -uo pipefail

PROJ_DIR="${1:-}"
if [ -z "$PROJ_DIR" ]; then
  PROJ_DIR="$(pwd)"
elif [ ! -d "$PROJ_DIR" ]; then
  printf '\033[1;31m✗\033[0m 目录不存在: %s\n' "$PROJ_DIR" >&2
  exit 1
fi
cd "$PROJ_DIR" || exit 1

FAILS=0
ok()  { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
bad() { printf '\033[1;31m✗\033[0m %s\n' "$*"; FAILS=$((FAILS + 1)); }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }

printf '\033[1;34m[doctor]\033[0m 诊断 %s\n' "$PROJ_DIR"

# 1. 必备文件
for f in .github/workflows/ci.yml lefthook.yml .pre-commit-config.yaml .gitignore .editorconfig; do
  if [ -f "$f" ]; then ok "文件: $f"; else bad "缺文件: $f"; fi
done

# 2. YAML 可解析（python3 缺席则降级提示）
if command -v python3 >/dev/null 2>&1; then
  for f in .github/workflows/*.yml lefthook.yml .pre-commit-config.yaml; do
    [ -f "$f" ] || continue
    if python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$f" 2>/dev/null; then
      ok "YAML: $f"
    else
      bad "YAML 解析失败: $f"
    fi
  done
else
  warn "未装 python3，跳过 YAML 解析检查"
fi

# 3. git 仓库
if [ -d .git ]; then
  ok "git 仓库"
else
  bad "不是 git 仓库（缺 .git）——hooks 与 CI 都无法生效"
fi

# 4. hooks 安装状态（pre-commit / lefthook 二选一，按 .git/hooks/pre-commit 内容区分归属——
#    lefthook install 也写 pre-commit 文件，且不生成 prepare-commit-msg，不能按文件名判断）
HOOK_INSTALLED=0
if [ -d .git ] && [ -e .git/hooks/pre-commit ]; then
  if grep -q lefthook .git/hooks/pre-commit 2>/dev/null; then
    ok "hooks: lefthook 已安装"
  else
    ok "hooks: pre-commit 已安装"
  fi
  HOOK_INSTALLED=1
fi
[ "$HOOK_INSTALLED" = "1" ] || warn "本地 hook 未安装（pre-commit install 或 lefthook install，二选一）"

# 5. 占位符残留（渲染遗漏 = 模板没生效）
if grep -rq '__PANGU_' . --exclude-dir=.git 2>/dev/null; then
  # cat -v：目标目录不受信，文件名/内容可能含终端转义序列，回显前净化
  grep -rn '__PANGU_' . --exclude-dir=.git 2>/dev/null | head -5 | cat -v
  bad "占位符残留（init 渲染遗漏，重跑 init 或手动替换）"
else
  ok "无占位符残留"
fi

# 6. 覆盖率门禁在位（ci.yml 应含 fail-under / cov-fail / 阈值判断之一）
if grep -qE 'fail-under|fail_under|cov-fail' .github/workflows/ci.yml 2>/dev/null \
   || grep -qE 'awk|Coverage' .github/workflows/ci.yml 2>/dev/null; then
  ok "覆盖率门禁: ci.yml"
else
  bad "ci.yml 疑似缺覆盖率门禁（fail-under 类步骤）"
fi

# 7. .pangu-meta（生成来源记录）
if [ -f .pangu-meta.yml ]; then
  # 版本号经 cat -v 净化后回显（文件内容不受信）
  VER="$(sed -n 's/^pangu_version:[[:space:]]*//p' .pangu-meta.yml | head -1 | tr -cd '[:alnum:]._-')"
  ok "生成来源: .pangu-meta.yml (pangu v${VER:-unknown})"
else
  warn "无 .pangu-meta.yml——老版本 pangu 生成或文件被删；升级模板时对照 https://github.com/Kirky-X/pangu"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  printf '\033[1;31m✗\033[0m doctor: %d 项未通过（逐项修复后重跑）\n' "$FAILS" >&2
  exit 1
fi
printf '\033[1;32m✓\033[0m doctor: 全部通过\n'
