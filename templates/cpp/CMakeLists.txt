cmake_minimum_required(VERSION 3.20)
project(app VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# pangu 选项
option(APP_ENABLE_COVERAGE "Enable code coverage instrumentation (--coverage)" OFF)
option(APP_ENABLE_CLANG_TIDY "Run clang-tidy during build" OFF)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  # 默认 Release：隐含 -O3 -DNDEBUG（优化体积与速度）。
  # 调试用：cmake -DCMAKE_BUILD_TYPE=Debug .. （含 -g -O0，配合 gdb/lldb/delve）
  # 覆盖率用：cmake -DAPP_ENABLE_COVERAGE=ON .. （下方 -O0 -g --coverage 会覆盖 -O3）
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

if(APP_ENABLE_CLANG_TIDY)
  find_program(CLANG_TIDY_EXE NAMES clang-tidy)
  if(CLANG_TIDY_EXE)
    set(CMAKE_CXX_CLANG_TIDY "${CLANG_TIDY_EXE};-p=${CMAKE_BINARY_DIR}")
  endif()
endif()

if(APP_ENABLE_COVERAGE)
  add_compile_options(--coverage -O0 -g)
  add_link_options(--coverage)
endif()

# 主可执行文件（init-cpp.sh 已创建 src/main.cpp 占位）
add_executable(app src/main.cpp)
target_include_directories(app PRIVATE include)

# 测试由 CTest 驱动；在此追加测试目标，例如：
#   add_executable(test_main tests/test_main.cpp)
#   target_link_libraries(test_main PRIVATE app)
#   add_test(NAME test_main COMMAND test_main)
enable_testing()
