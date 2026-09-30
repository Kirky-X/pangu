#!/usr/bin/env bash
# 一键初始化 C/C++ (CMake) 项目 harness。
# CMake 无官方脚手架命令，本脚本生成最小骨架：src/ include/ tests/ + main.cpp，
# 完整 CMakeLists.txt 由 templates/cpp/ 提供（copy_lang 拷入）。
# 用法:
#   init-cpp.sh [name]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# shellcheck disable=SC2034  # harness_finalize 读取
LANG_NAME="C/C++ (CMake)"
parse_harness_args "$@"
set -- ${PANGU_POSITIONAL[@]+"${PANGU_POSITIONAL[@]}"}

PROJ_NAME="${1:-}"
if [ -n "$PROJ_NAME" ]; then
  mkdir -p "$PROJ_NAME" && cd "$PROJ_NAME"
fi
# shellcheck disable=SC2034  # harness_finalize 读取
PROJ_DIR="$(pwd)"

# cpp 骨架是纯文件操作（无工具链依赖），templates-only 也照常生成，保持断言结构完整
mkdir -p src include tests
if [ ! -f src/main.cpp ]; then
  cat > src/main.cpp <<'CPP'
#include <iostream>

int main() {
    std::cout << "hello\n";
    return 0;
}
CPP
fi
log "C/C++ 骨架已生成 (src/ include/ tests/)"

copy_common
copy_lang cpp   # 模板含 CMakeLists.txt / ci.yml / lefthook.yml / .pre-commit-config.yaml / .gitignore（clang-format/clang-tidy 由 CI 安装执行，无独立模板文件）

git_init
install_hooks
harness_finalize
