#!/usr/bin/env bash
# test-multi.sh — 验证 copy_lang 的多语言 prefix 行为（TDD red→green）。
# 跑法: bash scripts/test-multi.sh  → 全过输出 "ALL GREEN"，否则 FAIL 行 + 非零退出。
# .bak/.orig 跳过防御由 hotfix 11/11 覆盖，本测不重复污染 templates。
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PROJ_DIR="$TMP"

assert_exists()     { [ -e "$1" ] || { echo "FAIL: 期望存在 $1"; FAIL=1; }; }
assert_contains()   { grep -q "$2" "$1" 2>/dev/null || { echo "FAIL: $1 不含 '$2'"; FAIL=1; }; }

WF="$PROJ_DIR/.github/workflows"

echo "── Case 1: copy_lang rust（无 prefix，主语言基底）──"
copy_lang rust
assert_exists "$WF/ci.yml"
assert_exists "$WF/release.yml"
assert_exists "$PROJ_DIR/lefthook.yml"
assert_exists "$PROJ_DIR/.pre-commit-config.yaml"
assert_exists "$PROJ_DIR/rustfmt.toml"     # 非冲突原样
assert_exists "$PROJ_DIR/clippy.toml"

echo "── Case 2: copy_lang python python（prefix，次语言）──"
copy_lang python python
assert_exists "$WF/python-ci.yml"           # 冲突文件加 prefix
assert_exists "$WF/python-release.yml"
assert_exists "$PROJ_DIR/python-lefthook.yml"
assert_exists "$PROJ_DIR/python-.pre-commit-config.yaml"
assert_exists "$PROJ_DIR/pyproject-tooling.toml"  # 非冲突原样（不 prefix）
assert_exists "$WF/ci.yml"                  # rust 基底未被覆盖
assert_contains "$PROJ_DIR/.gitignore" "# --- python ---"

echo "── Case 3: copy_lang node node（prefix，第三语言）──"
copy_lang node node
assert_exists "$WF/node-ci.yml"
assert_exists "$PROJ_DIR/node-lefthook.yml"
assert_exists "$PROJ_DIR/tsconfig.json"     # 非冲突原样
assert_exists "$WF/ci.yml"                  # rust 基底仍在
assert_exists "$WF/python-ci.yml"           # python 次语言仍在
assert_contains "$PROJ_DIR/.gitignore" "# --- node ---"

if [ "$FAIL" = 0 ]; then
  echo "✅ ALL GREEN — copy_lang prefix 多语言行为正确"
  exit 0
else
  echo "❌ FAIL — 见上方失败行"
  exit 1
fi
