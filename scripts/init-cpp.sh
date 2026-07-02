#!/usr/bin/env bash
# 一键初始化 C/C++ (CMake) 项目 harness。
# CMake 无官方脚手架命令，本脚本生成最小骨架：src/ include/ tests/ + main.cpp，
# 完整 CMakeLists.txt 由 templates/cpp/ 提供（copy_lang 拷入）。
# 用法:
#   init-cpp.sh [name]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

LANG_NAME="C/C++ (CMake)"

PROJ_NAME="${1:-}"
if [ -n "$PROJ_NAME" ]; then
  mkdir -p "$PROJ_NAME" && cd "$PROJ_NAME"
fi
PROJ_DIR="$(pwd)"

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
copy_lang cpp   # 模板含 CMakeLists.txt / .clang-format / .clang-tidy

git_init
install_hooks
harness_finalize
