# Build Optimization（编译优化配置）

> pangu 生成的项目骨架的编译优化配置说明。
> **高 ROI 已默认落地**（Rust profile / Go ldflags / C++ Release），**中 ROI 按需启用**，**低 ROI 谨慎或不默认**。

## 现状对照表

| 语言   | 默认优化（pangu 已落地）                                                      | 是否需用户操作                           |
| ------ | ----------------------------------------------------------------------------- | ---------------------------------------- |
| Rust   | `[profile.release]`：lto=thin / codegen-units=1 / strip=symbols / panic=abort | 否（init-rust.sh 自动追加到 Cargo.toml） |
| Go     | Makefile `make release`：`-ldflags="-s -w" -trimpath`                         | 否（init-go.sh 自动拷贝 Makefile）       |
| C++    | CMake 默认 `CMAKE_BUILD_TYPE=Release`（隐含 -O3 -DNDEBUG）                    | 否（CMakeLists.txt 默认）                |
| Node   | tsconfig ES2022 + strict（编译器优化已较优）                                  | —                                        |
| .NET   | net8.0 + AnalysisLevel latest（JIT 默认已优化）                               | —                                        |
| Java   | maven.compiler.release=21（最新 LTS 编译特性）                                | —                                        |
| Python | 解释执行（uv 管理）                                                           | —                                        |

## 默认落地详解（高 ROI）

### Rust · `[profile.release]` 四件套

由 `templates/rust/cargo-profile.snippet.toml` 提供，`init-rust.sh` 在 `cargo init` 后追加到 `Cargo.toml`：

```toml
[profile.release]
lto = "thin"           # 链接时优化：体积 -15% / 速度 +10-25%
codegen-units = 1      # 单代码生成单元：最优代码生成（牺牲约 30% 编译时间）
strip = "symbols"      # 去 symbol table：二进制 -30%
panic = "abort"        # 不展开：体积 -10% + 提速
```

**权衡**：

- `lto = "thin"` 而非 `"fat"`：thin 编译快很多，收益接近 fat（fat 仅在极致优化场景值得）
- `codegen-units = 1`：编译慢 ~30%，运行快（社区 release 标配）
- `panic = "abort"`：⚠️ **library 项目删此行**——依赖该 library 的 binary 将无法 `catch_unwind` 续跑。pangu `cargo init` 默认是 binary，故默认开

**手动覆盖**：用户改 `Cargo.toml` 的 `[profile.release]` 即可（init 脚本只在无该段时追加，`grep '\[profile.release\]'` 已存在则跳过并 warn）。

### Go · Makefile release 规则

`templates/go/Makefile` 由 `init-go.sh` 自动拷贝到项目根：

```makefile
release:
	go build -ldflags="-s -w" -trimpath -o bin/app .
```

- `-s -w`：去符号表 + DWARF 调试信息，二进制体积 -25%
- `-trimpath`：去绝对路径，可复现构建（CI/Release 标配）

**用法**：`make release`（发布）/ `make build`（debug，含符号，便于 delve）/ `make test`（-race -cover）。

**调整 APP_NAME**：`make release APP_NAME=mypkg` 或改 Makefile 顶部 `APP_NAME ?= app`。

### C++ · 默认 Release

`templates/cpp/CMakeLists.txt` 第 12 行：

```cmake
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()
```

Release 隐含 `-O3 -DNDEBUG`。调试用 `cmake -DCMAKE_BUILD_TYPE=Debug ..`（含 -g -O0）。覆盖率用 `cmake -DAPP_ENABLE_COVERAGE=ON ..`（自动 -O0 -g --coverage 覆盖 -O3）。

## 按需启用（中 ROI，权衡后开）

以下未默认开启，因有兼容性/复杂度权衡。按项目类型选择。

### Node.js · Bun 替代运行时

**收益**：Bun 启动快 2-4x，原生支持 TS/JSX，内置 test/bundler。

**权衡**：

- ⚠️ 部分 npm 包（native 模块、特定 Node API）不兼容
- 生态较新，某些企业级库未验证

**启用方式**（pangu 当前 `init-node.sh` 未自动检测，需手动）：

```bash
bun init            # 替代 pnpm/npm init
bun add --dev ...   # 替代 pnpm add（bun 用 --dev/-d，非 -D）
bun run dev         # 替代 node
```

**建议**：库项目保留 pnpm/npm（兼容性优先）；应用项目可试 Bun。

### Node.js · SWC/esbuild/tsup 替代 tsc 编译

**收益**：编译速度 10-50x（SWC/esbuild 用原生实现，tsc 用 TS 实现）。

**权衡**：tsc 的类型检查仍需保留（SWC/esbuild 仅转译不类型检查）。`tsconfig.json` 仍由 tsc 管，仅 build 步骤换。

**启用**：

```bash
pnpm add -D tsup typescript   # tsup 基于 esbuild，零配置打包
# package.json scripts: "build": "tsup src/index.ts --format esm,cjs --dts"
```

**建议**：应用项目用 tsup；库项目保留 tsc（declaration/sourceMap 是必需）。

### .NET · ReadyToRun / PublishSingleFile

**收益**：ReadyToRun 预编译 IL→原生，启动快 20-40%；SingleFile 单文件部署。

**权衡**：ReadyToRun 增大二进制（含预编译代码）；只对启动敏感场景值得。

**启用**（在 `Directory.Build.props` 追加或 `dotnet publish` 命令行）：

```xml
<PublishReadyToRun>true</PublishReadyToRun>
<PublishSingleFile>true</PublishSingleFile>
<SelfContained>false</SelfContained>
```

### Java · GraalVM native-image / ProGuard

**GraalVM native-image**：AOT 编译为原生二进制，启动 ms 级、内存 -10x。

- ⚠️ 编译慢（分钟级）、反射需配置、对小型项目 ROI 低
- 适用：CLI 工具、Serverless、启动敏感的微服务

**ProGuard**：字节码优化/混淆，减体积。

- ⚠️ 反射/序列化需 keep 规则，配置复杂
- 适用：发布产物体积敏感

### Python · mypyc / nuitka

**mypyc**（mypy 团队）：编译类型注解的 Python 为 C 扩展，热点提速 2-10x。
**nuitka**：整体编译为独立二进制（含解释器）。

- ⚠️ 增加构建复杂度，调试困难
- 适用：CPU 密集热点、发布闭源产物

## 不建议默认（低 ROI 或有副作用）

| 选项                              | 不默认的原因                                       | 适用场景                                   |
| --------------------------------- | -------------------------------------------------- | ------------------------------------------ |
| C++ `-march=native`               | 不同 CPU 跑不了（线上/本地指令集差异），仅本机优化 | 仅本机高性能计算                           |
| Rust `lto = "fat"`                | 比 thin 编译慢很多，收益边际（1-3%）               | 极致体积/速度的发行版构建                  |
| Rust `panic = "abort"`（library） | 依赖该 library 的 binary 无法 catch panic 续跑     | 仅 binary 项目（pangu 已对 binary 默认开） |
| Go `-race`（release）             | 已在 `make test` 开；release 构建不该开（拖性能）  | —                                          |
| Node Bun（库项目）                | 兼容性风险                                         | 仅应用项目                                 |

## 决策流程

1. **新建项目**：pangu 已默认落地 Rust/Go/C++ 三件套，无需操作
2. **Node 应用**：按需 `tsup`（编译速度）+ 评估 Bun（运行时）
3. **Node 库**：保留 tsc（兼容性），不换 Bun
4. **启动敏感的 .NET/Java**：评估 ReadyToRun / native-image
5. **CPU 密集 Python**：评估 mypyc 热点编译
6. **发行版构建**：可考虑 Rust `lto = "fat"`（接受编译慢换 1-3% 收益）

## 参考数据（社区基准）

| 优化                      | 编译时间影响 | 运行性能    | 二进制体积     |
| ------------------------- | ------------ | ----------- | -------------- |
| Rust lto=thin + codegen=1 | +30-50%      | +10-25%     | -30%           |
| Go -s -w + trimpath       | 无影响       | 无影响      | -25%           |
| C++ Release vs Debug      | 无影响       | 显著（-O3） | 无显著变化     |
| Bun vs Node（启动）       | —            | 2-4x 启动   | —              |
| SWC vs tsc（编译）        | 10-50x 快    | 无影响      | —              |
| GraalVM native-image      | 分钟级编译   | 启动 ms 级  | 含运行时，更大 |

> 数据为社区典型范围，具体项目因代码特征而异，建议在目标项目实测。
