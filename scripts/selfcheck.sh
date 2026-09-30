#!/usr/bin/env bash
# pangu 自检门禁：shellcheck + YAML lint + 模板完整性 + SKILL.md 索引校验 + init 冒烟测试。
# 用途:
#   1. pangu 自身 CI（提交前/PR 前，防止脚本与模板回归）
#   2. 配合 templates/common/.pre-commit-config.yaml 的 shellcheck hook（local 等价入口）
# 行为:
#   - shellcheck: 未装 → warn + 跳过；已装 → 逐个检查 scripts/*.sh
#   - YAML lint: 未装 python3 → warn + skip；已装 → 校验 templates/**/*.yml
#   - 模板完整性: 每个语言目录应有 ci.yml release.yml .pre-commit-config.yaml lefthook.yml .gitignore
#   - SKILL.md 索引: 文档引用的脚本/模板/文档路径必须真实存在（fail-closed 防索引腐化）
#   - init 冒烟: 9 语言 templates-only 端到端跑一遍（SMC_SKIP=1 可跳过，CI 单独跑）
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
  # find 而非 glob：** 在未开 globstar 时退化为单层，且 * 不匹配点开头文件
  # （glob 会漏掉全部 .pre-commit-config.yaml / .golangci.yaml / .rubocop.yml 与 github/ 深层文件）
  yamls=()
  while IFS= read -r f; do yamls+=("$f"); done < <(find templates -type f \( -name '*.yml' -o -name '*.yaml' \))

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

# --- SKILL.md 索引校验（fail-closed：文档引用的路径必须真实存在）---
# 两个已知提取陷阱：
#   1. 语言路由表用无 templates/ 前缀写法（`rust/ci.yml`、`init-rust.sh`）——按语言前缀解析到 templates/
#   2. `templates/{common,rust,...}/` 含逗号的花括号列表——须做花括号展开而非截断
if ! command -v python3 >/dev/null 2>&1; then
  printf '\033[1;33m!\033[0m pangu selfcheck: 未安装 python3，跳过 SKILL.md 索引校验\n' >&2
else
  printf '\033[1;34m[harness]\033[0m SKILL.md 索引校验（引用路径 fail-closed）\n'
  if python3 - <<'PY'
import itertools, os, re, sys

content = open("SKILL.md", encoding="utf-8").read()
LANGS = ("rust|python|node|java|go|cpp|ruby|php|dotnet|common|skill")
missing, checked = [], 0

def expand_braces(path: str):
    """展开 {a,b,c} 枚举段；单选项 {L} 属占位符记法，原样返回交由 skip 判断。"""
    m = re.search(r"\{([^{}]+)\}", path)
    if not m or "," not in m.group(1):
        return [path]
    options = m.group(1).split(",")
    prefix, suffix = path[: m.start()], path[m.end() :]
    return [expand for opt in options for expand in expand_braces(f"{prefix}{opt}{suffix}")]

def is_concrete(path: str) -> bool:
    """占位符/用法串（init-{L}.sh、bump.sh <v> 等）不是具体路径，跳过存在性检查。"""
    return not any(ch in path for ch in "{}<>*?") and " " not in path

refs = set()
# 表格里的模板相对路径（无前缀，如 rust/ci.yml）→ templates/ 下
refs |= {f"templates/{r}" for r in re.findall(rf"`((?:{LANGS})/[^`]+)`", content)}
# scripts/ references/ .github/ 引用
refs |= set(re.findall(r"`((?:scripts|references|\.github)/[^`]+)`", content))
# 完整 templates/ 路径（含花括号列表写法）
refs |= set(re.findall(r"`(templates/[^`]+)`", content))

for ref in refs:
    for path in expand_braces(ref.rstrip("/")):
        if not is_concrete(path):
            continue
        checked += 1
        if not os.path.exists(path):
            missing.append(path)

# SKILL.md 引用的 init/hook 脚本
for r in set(re.findall(r"\b(init-[a-z0-9-]+\.sh|install-hooks\.sh|_common\.sh|smoke-test\.sh|doctor\.sh)\b", content)):
    checked += 1
    if not os.path.isfile(f"scripts/{r}"):
        missing.append(f"scripts/{r}")

if missing:
    print(f"SKILL.md 引用了不存在的路径（{len(missing)}）:", file=sys.stderr)
    for m in sorted(set(missing)):
        print(f"  MISSING: {m}", file=sys.stderr)
    sys.exit(1)
print(f"  OK {checked} 个引用路径全部存在")
PY
  then
    printf '\033[1;32m✓\033[0m SKILL.md 索引校验通过\n'
  else
    printf '\033[1;31m✗\033[0m SKILL.md 索引校验发现悬空引用\n' >&2
    ERRORS=$((ERRORS + 1))
  fi
fi

# --- init 冒烟测试（templates-only 端到端；SMC_SKIP=1 跳过）---
if [ "${SMC_SKIP:-0}" = "1" ]; then
  printf '\033[1;34m[harness]\033[0m init 冒烟测试跳过（SMC_SKIP=1）\n'
else
  printf '\033[1;34m[harness]\033[0m init 冒烟测试（9 语言 templates-only）\n'
  smoke_out="$(mktemp)"
  if bash "$(dirname "${BASH_SOURCE[0]}")/smoke-test.sh" >"$smoke_out" 2>&1; then
    printf '\033[1;32m✓\033[0m init 冒烟测试通过\n'
    rm -f "$smoke_out"
  else
    printf '\033[1;31m✗\033[0m init 冒烟测试失败（输出如下）\n' >&2
    tail -30 "$smoke_out" >&2
    rm -f "$smoke_out"
    ERRORS=$((ERRORS + 1))
  fi
fi

# --- 汇总 ---
if [ "$ERRORS" -gt 0 ]; then
  printf '\033[1;31m✗\033[0m pangu selfcheck 发现 %d 类错误\n' "$ERRORS" >&2
  exit 1
fi

printf '\033[1;32m✓\033[0m pangu selfcheck 全部通过\n'
