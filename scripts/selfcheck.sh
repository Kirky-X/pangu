#!/usr/bin/env bash
# pangu 自检门禁：对 scripts/*.sh 跑 shellcheck + 模板完整性检查。
# 用途:
#   1. pangu 自身 CI（提交前/PR 前，防止脚本回归）
#   2. 配合 templates/common/.pre-commit-config.yaml 的 shellcheck hook（local 等价入口）
# 行为:
#   - shellcheck: 未装 → warn + exit 0；已装 → 逐个检查 scripts/*.sh
#   - YAML lint: 未装 python3 → warn + skip；已装 → 校验 templates/**/*.yml
#   - 模板完整性: 每个语言目录应有 ci.yml release.yml .pre-commit-config.yaml lefthook.yml .gitignore
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

ERRORS=0

# --- shellcheck ---
if ! command -v shellcheck >/dev/null 2>&1; then
  printf '\033[1;33m!\033[0m pangu selfcheck: 未安装 shellcheck，跳过（apt/brew install shellcheck 后生效）\n' >&2
else
  shopt -s nullglob
  shells=(scripts/*.sh)
  shopt -u nullglob

  if [ "${#shells[@]}" -eq 0 ]; then
    printf '\033[1;34m[harness]\033[0m scripts/ 下无 .sh，selfcheck 无事可做\n'
  else
    printf '\033[1;34m[harness]\033[0m shellcheck %d 个脚本\n' "${#shells[@]}"
    # SC1090/SC1091: source 路径含变量（_common.sh 等），shellcheck 无法静态追踪
    if shellcheck -e SC1090 -e SC1091 "${shells[@]}"; then
      printf '\033[1;32m✓\033[0m shellcheck 通过（%d 个脚本）\n' "${#shells[@]}"
    else
      ERRORS=$((ERRORS + 1))
    fi
  fi
fi

# --- YAML lint ---
if ! command -v python3 >/dev/null 2>&1; then
  printf '\033[1;33m!\033[0m pangu selfcheck: 未安装 python3，跳过 YAML lint\n' >&2
else
  shopt -s nullglob
  yamls=(templates/**/*.yml templates/**/*.yaml)
  shopt -u nullglob

  if [ "${#yamls[@]}" -gt 0 ]; then
    printf '\033[1;34m[harness]\033[0m YAML lint %d 个模板文件\n' "${#yamls[@]}"
    yaml_errors=0
    for f in "${yamls[@]}"; do
      if ! python3 -c "import yaml; yaml.safe_load(open('$f'))" 2>/dev/null; then
        printf '\033[1;31m✗\033[0m YAML 语法错误: %s\n' "$f" >&2
        yaml_errors=$((yaml_errors + 1))
      fi
    done
    if [ "$yaml_errors" -eq 0 ]; then
      printf '\033[1;32m✓\033[0m YAML lint 通过（%d 个文件）\n' "${#yamls[@]}"
    else
      printf '\033[1;31m✗\033[0m YAML lint 发现 %d 个错误\n' "$yaml_errors" >&2
      ERRORS=$((ERRORS + 1))
    fi
  fi
fi

# --- 模板完整性检查 ---
REQUIRED_FILES="ci.yml release.yml .pre-commit-config.yaml lefthook.yml .gitignore"
printf '\033[1;34m[harness]\033[0m 模板完整性检查\n'
tpl_errors=0
for lang_dir in templates/*/; do
  lang="$(basename "$lang_dir")"
  # 跳过 common/ 和 skill/（非语言模板）
  case "$lang" in
    common|skill) continue ;;
  esac
  for req in $REQUIRED_FILES; do
    if [ ! -f "$lang_dir$req" ]; then
      printf '\033[1;31m✗\033[0m 缺少: templates/%s/%s\n' "$lang" "$req" >&2
      tpl_errors=$((tpl_errors + 1))
    fi
  done
done
if [ "$tpl_errors" -eq 0 ]; then
  printf '\033[1;32m✓\033[0m 模板完整性检查通过\n'
else
  printf '\033[1;31m✗\033[0m 模板完整性检查发现 %d 个缺失\n' "$tpl_errors" >&2
  ERRORS=$((ERRORS + 1))
fi

# --- 汇总 ---
if [ "$ERRORS" -gt 0 ]; then
  printf '\033[1;31m✗\033[0m pangu selfcheck 发现 %d 类错误\n' "$ERRORS" >&2
  exit 1
fi

printf '\033[1;32m✓\033[0m pangu selfcheck 全部通过\n'
