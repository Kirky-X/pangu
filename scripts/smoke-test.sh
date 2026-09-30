#!/usr/bin/env bash
# init 端到端冒烟测试（templates-only 模式，无需语言工具链）。
# 对 9 种语言各跑一次 init-{L}.sh --templates-only 到临时目录，断言:
#   1. harness 必备文件齐全（ci.yml/lefthook.yml/.pre-commit-config.yaml/.gitignore/.pangu-meta.yml…）
#   2. 占位符全部渲染（无 __PANGU_ 残留），默认阈值 80 已落到 ci.yml/lefthook.yml
#   3. YAML 全部可解析
#   4. 默认参数: release.yml + codeql.yml 生成；git 仓库初始化；无 *.snippet.* 残留
#   5. 参数化: --cov/--branch/--no-release/--no-codeql 渲染与裁剪正确（抽 python 验证）
# 用法:
#   scripts/smoke-test.sh                # 全部 9 语言
#   scripts/smoke-test.sh rust,python    # 子集（调试用）
#   SMK_KEEP=1 scripts/smoke-test.sh     # 保留临时目录（调试用，路径打印在输出里）
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LANGS="${1:-rust,python,node,java,go,cpp,ruby,php,dotnet}"
IFS=',' read -ra LANG_ARR <<< "$LANGS"

FAILS=0
ROOT="$(mktemp -d /tmp/pangu-smoke.XXXXXX)"
# init-{L}.sh 的 <name> 相对【调用方 CWD】建目录——必须先切进临时根，
# 否则项目会生成到冒烟脚本自己的 CWD（曾在 pangu 仓库根误生成 10 个 *-proj）
cd "$ROOT" || exit 1
cleanup() {
  if [ "${SMK_KEEP:-0}" = "1" ]; then
    printf '\033[1;34m[harness]\033[0m 保留临时目录: %s\n' "$ROOT"
  else
    rm -rf "$ROOT"
  fi
}
trap cleanup EXIT

ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
bad()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; FAILS=$((FAILS + 1)); }
fail_lang() { bad "$1: $2"; }

# yaml_ok <file> — python3 缺席时跳过（selfcheck 已有相同降级策略）
yaml_ok() {
  command -v python3 >/dev/null 2>&1 || return 0
  python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$1" 2>/dev/null
}

# check_lang <lang> — 跑 init-{L}.sh --templates-only 并断言产物
check_lang() {
  local lang="$1" d="$ROOT/$1"
  printf '\033[1;34m[harness]\033[0m smoke: %s\n' "$lang"

  if ! bash "$SKILL_DIR/scripts/init-$lang.sh" "$lang-proj" --templates-only \
       >"$ROOT/$lang.init.log" 2>&1; then
    fail_lang "$lang" "init 退出非零（日志: $ROOT/$lang.init.log 末尾如下）"
    tail -5 "$ROOT/$lang.init.log" >&2
    return 1
  fi
  d="$ROOT/$lang-proj"

  # 1. harness 必备文件
  local f
  for f in .github/workflows/ci.yml .github/workflows/release.yml .github/workflows/codeql.yml \
           lefthook.yml .pre-commit-config.yaml .gitignore .editorconfig .pangu-meta.yml; do
    [ -f "$d/$f" ] || fail_lang "$lang" "缺文件: $f"
  done

  # 2. 占位符零残留 + 默认值精确渲染（阈值 80 + 默认分支 main）
  if grep -rq '__PANGU_' "$d" 2>/dev/null; then
    grep -rn '__PANGU_' "$d" 2>/dev/null | head -3 >&2
    fail_lang "$lang" "占位符残留"
  fi
  grep -q 'branches: \[main\]' "$d/.github/workflows/ci.yml" || fail_lang "$lang" "默认分支 main 未渲染进 ci.yml"
  grep -qE 'fail-under(-lines)? 80|fail-under=80|< 80|0\.80|80\.0|lines: 80|fail_under = 80' \
    "$d/.github/workflows/ci.yml" "$d/lefthook.yml" 2>/dev/null \
    || fail_lang "$lang" "默认阈值 80 未渲染进门禁文件"

  # 2b. 私钥正则实击：PKCS#8（BEGIN PRIVATE KEY）/ DSA / OPENSSH 三类样本必须被
  #     lefthook no-private-key 命中（键名存在 ≠ 规则正确；对齐 detect-private-key 覆盖面）
  local _re
  _re="$(grep -oE "grep -IlE '[^']+'" "$d/lefthook.yml" | head -1 | sed "s/^grep -IlE '//; s/'$//")"
  if [ -n "$_re" ]; then
    local sample
    for sample in "-----BEGIN PRIVATE KEY-----" "-----BEGIN DSA PRIVATE KEY-----" "-----BEGIN OPENSSH PRIVATE KEY-----"; do
      printf '%s\n' "$sample" | grep -qE "$_re" || fail_lang "$lang" "私钥正则漏检: $sample"
    done
  else
    fail_lang "$lang" "lefthook 未找到 no-private-key 正则"
  fi

  # 3. YAML 可解析（workflow + hook 配置）
  for f in "$d"/.github/workflows/*.yml "$d/lefthook.yml" "$d/.pre-commit-config.yaml"; do
    [ -f "$f" ] || continue
    yaml_ok "$f" || fail_lang "$lang" "YAML 解析失败: $f"
  done

  # 4. git 仓库 + snippet 无残留 + .pangu-meta 内容
  [ -d "$d/.git" ] || fail_lang "$lang" "git 仓库未初始化"
  ls "$d"/*.snippet.* "$d"/pyproject-tooling.toml >/dev/null 2>&1 && fail_lang "$lang" "snippet 残留未清理"
  grep -q 'pangu_version:' "$d/.pangu-meta.yml" || fail_lang "$lang" ".pangu-meta.yml 缺 pangu_version"
  grep -q 'coverage_threshold: 80' "$d/.pangu-meta.yml" || fail_lang "$lang" ".pangu-meta.yml 阈值与默认不符"

  # 5. lefthook 等价性基线：每语言都应有 no-private-key 与 pre-push 段
  grep -q 'no-private-key:' "$d/lefthook.yml" || fail_lang "$lang" "lefthook 缺 no-private-key（等价性破坏）"
  grep -q '^pre-push:' "$d/lefthook.yml" || fail_lang "$lang" "lefthook 缺 pre-push 段（等价性破坏）"
  # diff coverage 门禁应存在（go/ruby 为全局门禁，无 diff 关键字属预期，单独放行）
  case "$lang" in
    go|ruby) : ;;
    *) grep -q 'diff-cover' "$d/.github/workflows/ci.yml" || fail_lang "$lang" "ci.yml 缺 diff coverage 门禁" ;;
  esac

  if [ "$FAILS" -eq "$FAILS_BEFORE" ]; then ok "$lang 默认参数通过"; else bad "$lang 存在失败项（见上）"; fi
}

# --- 逐语言默认参数冒烟 ---
for L in "${LANG_ARR[@]}"; do
  case "$L" in
    rust|python|node|java|go|cpp|ruby|php|dotnet) ;;
    *) bad "未知语言: $L"; continue ;;
  esac
  FAILS_BEFORE=$FAILS
  check_lang "$L"
done

# --- 参数化冒烟（python 一个代表）：--cov/--branch/--no-release/--no-codeql ---
printf '\033[1;34m[harness]\033[0m smoke: 参数化 (python)\n'
FAILS_BEFORE=$FAILS
bash "$SKILL_DIR/scripts/init-python.sh" flags-proj --templates-only \
  --cov 90 --branch trunk --no-release --no-codeql >"$ROOT/flags.init.log" 2>&1 \
  || fail_lang "flags" "带参 init 退出非零"
FD="$ROOT/flags-proj"
[ -f "$FD/.github/workflows/ci.yml" ] || fail_lang "flags" "ci.yml 未生成"
[ -f "$FD/.github/workflows/release.yml" ] && fail_lang "flags" "--no-release 未裁剪 release.yml"
[ -f "$FD/.github/workflows/codeql.yml" ] && fail_lang "flags" "--no-codeql 未裁剪 codeql.yml"
[ -f "$FD/.github/workflows/release-please.yml" ] && fail_lang "flags" "默认不应生成 release-please.yml"
grep -q 'branches: \[trunk\]' "$FD/.github/workflows/ci.yml" 2>/dev/null || fail_lang "flags" "--branch trunk 未渲染"
grep -q '__PANGU_COV__' "$FD/.github/workflows/ci.yml" 2>/dev/null && fail_lang "flags" "阈值占位符未渲染"
grep -q 'coverage_threshold: 90' "$FD/.pangu-meta.yml" 2>/dev/null || fail_lang "flags" ".pangu-meta 未记录 cov=90"
grep -q 'default_branch: "trunk"' "$FD/.pangu-meta.yml" 2>/dev/null || fail_lang "flags" ".pangu-meta 未记录 branch=trunk"
grep -q '90' "$FD/.github/workflows/ci.yml" 2>/dev/null || fail_lang "flags" "--cov 90 未渲染"
# fail_under 第三处（工具配置）在 templates-only 下无 pyproject.toml 可验（snippet 被清理），
# 由下方「模板源静态一致性」区覆盖

# --- 参数化冒烟 2：--profile core + --changelog release-please（默认分支 main）---
printf '\033[1;34m[harness]\033[0m smoke: 参数化 2 (python, profile+changelog)\n'
FAILS_BEFORE=$FAILS
bash "$SKILL_DIR/scripts/init-python.sh" rp-proj --templates-only \
  --profile core --changelog release-please >"$ROOT/rp.init.log" 2>&1 \
  || fail_lang "profile" "带参 init 退出非零"
FP="$ROOT/rp-proj"
[ -f "$FP/.github/workflows/release.yml" ] || fail_lang "profile" "release.yml 不应被裁剪"
[ -f "$FP/.github/workflows/codeql.yml" ] || fail_lang "profile" "codeql.yml 不应被裁剪"
[ -f "$FP/.github/workflows/release-please.yml" ] || fail_lang "profile" "--changelog release-please 未生成 release-please.yml"
grep -q 'branches: \[main\]' "$FP/.github/workflows/ci.yml" 2>/dev/null || fail_lang "profile" "默认分支 main 未渲染"
grep -q '85' "$FP/.github/workflows/ci.yml" 2>/dev/null || fail_lang "profile" "--profile core 阈值 85 未渲染"
grep -q '__PANGU_' "$FP" -r 2>/dev/null && fail_lang "profile" "占位符残留"
if [ "$FAILS" -eq "$FAILS_BEFORE" ]; then ok "参数化 通过（含 profile/changelog 组）"; fi

# --- 模板源静态一致性（三处一致承诺的第三处出口；渲染行为已被上面断言覆盖）---
printf '\033[1;34m[harness]\033[0m smoke: 模板源静态一致性\n'
FAILS_BEFORE=$FAILS
grep -q 'fail_under = __PANGU_COV__' "$SKILL_DIR/templates/python/pyproject-tooling.toml" 2>/dev/null \
  || bad "静态: pyproject-tooling.toml fail_under 未用 __PANGU_COV__ 占位符（三处一致承诺缺口）"
# 私钥正则必须覆盖 PKCS#8/DSA（对齐 detect-private-key；正则改动须 9 语言同步）
for f in "$SKILL_DIR"/templates/*/lefthook.yml; do
  grep -q "BEGIN ((RSA|DSA|EC|OPENSSH|PGP) )?PRIVATE KEY" "$f" \
    || bad "静态: $f 私钥正则未含 PKCS#8/DSA 覆盖"
done
if [ "$FAILS" -eq "$FAILS_BEFORE" ]; then ok "静态一致性 通过"; fi

# --- 汇总 ---
echo
if [ "$FAILS" -gt 0 ]; then
  bad "冒烟测试失败 $FAILS 处"
  exit 1
fi
ok "冒烟测试全部通过（${#LANG_ARR[@]} 语言默认参数 + 参数化）"
