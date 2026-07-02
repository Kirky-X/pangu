# 9 语言工具链速查

每种语言给出：脚手架、格式、Lint、类型、安全、测试+覆盖率、**本地复现 CI** 命令、发布命令。CI 模板（`templates/<lang>/ci.yml`）与本地命令等价。

---

## Rust

| 环节        | 命令                                                                                         |
| ----------- | -------------------------------------------------------------------------------------------- |
| 脚手架      | `cargo init [name]`                                                                          |
| 添加依赖    | `cargo add <crate>`（禁止手编 Cargo.toml）                                                   |
| 格式        | `cargo fmt --check`（自动修：`cargo fmt`）                                                   |
| Lint        | `cargo clippy --all-targets --all-features -- -D warnings`                                   |
| 安全 SCA    | `cargo install cargo-audit` → `cargo audit`；`cargo install cargo-deny` → `cargo deny check` |
| 内存        | `cargo +nightly miri`（仅 nightly，针对 unsafe/FFI 测试）                                    |
| 测试+覆盖率 | `cargo install cargo-llvm-cov` → `cargo llvm-cov --fail-under-lines 80 --workspace`          |
| 发布        | `cargo publish --dry-run` → `cargo publish`（需 `CARGO_REGISTRY_TOKEN`）                     |

**本地复现 CI**

```bash
cargo fmt --check && \
cargo clippy --all-targets --all-features -- -D warnings && \
cargo audit && cargo deny check && \
cargo test --all-features && \
cargo llvm-cov --fail-under-lines 80 --workspace
```

---

## Python

| 环节        | 命令                                                                               |
| ----------- | ---------------------------------------------------------------------------------- |
| 脚手架      | `uv init [name] --lib`（库）或 `--app`（应用）；备选 `pip` + 手写 `pyproject.toml` |
| 添加依赖    | `uv add <pkg>`（禁止手编 pyproject）                                               |
| 格式        | `ruff format --check`（修：`ruff format`）                                         |
| Lint        | `ruff check`（修：`ruff check --fix`）                                             |
| 类型        | `mypy src/`（或 `pyright`）                                                        |
| 安全        | `bandit -r src/ -ll`；`pip-audit`                                                  |
| 测试+覆盖率 | `pytest --cov=src --cov-report=term --cov-fail-under=80`                           |
| 发布        | `uv build` → `uv publish`（需 `UV_PUBLISH_TOKEN` 或 `PYPI_TOKEN`）                 |

**本地复现 CI**

```bash
ruff format --check && ruff check && mypy src/ && \
bandit -r src/ -ll && pip-audit && \
pytest --cov=src --cov-report=term --cov-fail-under=80
```

---

## Node / TypeScript

| 环节        | 命令                                                                                                                |
| ----------- | ------------------------------------------------------------------------------------------------------------------- |
| 脚手架      | `pnpm init`（或 `npm init`）；TS：`pnpm add -D typescript`                                                          |
| 添加依赖    | `pnpm add <pkg>`（禁止手编 package.json）                                                                           |
| 格式        | `prettier --check .`（修：`prettier --write .`）                                                                    |
| Lint        | `eslint .`（修：`eslint . --fix`）                                                                                  |
| 类型        | `tsc --noEmit`                                                                                                      |
| 安全        | `eslint . --ext .ts,.js`（含 `eslint-plugin-security`）；`pnpm audit --audit-level=high`                            |
| 测试+覆盖率 | `vitest run --coverage`（阈值见 `vitest.config`）或 `jest --coverage --coverageThreshold='{"global":{"lines":80}}'` |
| 发布        | `pnpm publish --no-git-checks`（需 `NPM_TOKEN`；建议开 provenance）                                                 |

**本地复现 CI**

```bash
prettier --check . && eslint . && tsc --noEmit && \
pnpm audit --audit-level=high && \
pnpm test -- --coverage
```

---

## Java（Maven 默认 / Gradle 备选）

| 环节        | 命令（Maven）                                                                                                    |
| ----------- | ---------------------------------------------------------------------------------------------------------------- |
| 脚手架      | `mvn archetype:generate -DgroupId=com.example -DartifactId=app -DarchetypeArtifactId=maven-archetype-quickstart` |
| 格式        | `mvn spotless:check`（修：`mvn spotless:apply`）                                                                 |
| Lint        | `mvn checkstyle:check`                                                                                           |
| 静态分析    | `mvn spotbugs:check`（含 FindSecBugs 插件）                                                                      |
| 安全        | `mvn org.owasp:dependency-check-maven:check`                                                                     |
| 测试+覆盖率 | `mvn test jacoco:report`（`jacoco` 配 `--fail-under-line 80`）                                                   |
| 发布        | `mvn deploy`（Maven Central，需 GPG + MAVEN*CENTRAL*\*）                                                         |

Gradle 备选：`./gradlew spotlessCheck check jacocoTestCoverageVerification sonarqube`。

**本地复现 CI**

```bash
mvn -B spotless:check checkstyle:check spotbugs:check && \
mvn -B org.owasp:dependency-check-maven:check && \
mvn -B test jacoco:report
```

---

## Go

| 环节        | 命令                                                                                                              |
| ----------- | ----------------------------------------------------------------------------------------------------------------- |
| 脚手架      | `go mod init <module>`（如 `github.com/user/repo`）                                                               |
| 添加依赖    | `go get <pkg>`                                                                                                    |
| 格式        | `gofmt -l .`（修：`gofmt -w .`）；`goimports -l .`                                                                |
| Lint        | `golangci-lint run`（含 `go vet`）                                                                                |
| 安全        | `gosec ./...`；`go run golang.org/x/vuln/cmd/govulncheck@latest ./...`                                            |
| 测试+覆盖率 | `go test -race -coverprofile=coverage.out -coverpkg=./... ./...` → 阈值用 `go tool cover -func=coverage.out` 比对 |
| 发布        | Go 无中心 registry，发 GitHub Release（附加跨平台二进制）                                                         |

**本地复现 CI**

```bash
gofmt -l . && go vet ./... && golangci-lint run && \
gosec ./... && govulncheck ./... && \
go test -race -coverprofile=coverage.out -coverpkg=./... ./...
```

---

## C / C++

| 环节        | 命令                                                                       |
| ----------- | -------------------------------------------------------------------------- |
| 脚手架      | CMake：手写 `CMakeLists.txt` + `src/` + `tests/`（脚本提供模板）           |
| 格式        | `clang-format --dry-run --Werror $(find src -name '*.cpp' -o -name '*.h')` |
| Lint        | `clang-tidy src/*.cpp -- -Iinclude`                                        |
| 静态分析    | `cppcheck --enable=warning,performance,style --error-exitcode=1 src/`      |
| 安全        | `flawfinder src/`（高风险项阈值过滤）                                      |
| 测试+覆盖率 | 编译加 `--coverage` → `ctest` → `gcovr --fail-under-line 80`               |
| 发布        | 发 GitHub Release（源码 tarball + 预编译二进制）                           |

**本地复现 CI**

```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug && cmake --build build && \
cppcheck --enable=warning,style --error-exitcode=1 src/ && \
flawfinder src/ && \
cd build && ctest --output-on-failure && gcovr --fail-under-line 80
```

---

## Ruby

| 环节          | 命令                                                                                 |
| ------------- | ------------------------------------------------------------------------------------ |
| 脚手架        | `bundle init`（生成 Gemfile）；gem：`bundle gem <name>`                              |
| 添加依赖      | 编辑 Gemfile 后 `bundle install`                                                     |
| 格式/Lint     | `rubocop`（修：`rubocop -A`）                                                        |
| 安全（Rails） | `brakeman`（Rails 项目）；非 Rails 跳过                                              |
| 安全 SCA      | `bundle audit check --update`                                                        |
| 测试+覆盖率   | `bundle exec rspec`（simplecov 在 spec_helper 注入，`SimpleCov.start` + 覆盖率门禁） |
| 发布          | `rake release`（RubyGems，需 `RUBYGEMS_AUTH_TOKEN`）                                 |

**本地复现 CI**

```bash
bundle exec rubocop && \
(bundle exec brakeman || true) && \
bundle audit check --update && \
bundle exec rspec
```

---

## PHP

| 环节          | 命令                                                                            |
| ------------- | ------------------------------------------------------------------------------- |
| 脚手架        | `composer init`（生成 composer.json）                                           |
| 添加依赖      | `composer require <pkg>`                                                        |
| 格式          | `vendor/bin/php-cs-fixer fix --dry-run --diff`（修：去 `--dry-run`）            |
| 静态分析/安全 | `vendor/bin/psalm --security-analysis`（或 phpstan）                            |
| 安全 SCA      | `composer audit`                                                                |
| 测试+覆盖率   | `vendor/bin/phpunit --coverage-text --fail-on-warning`（覆盖率门禁见 xml 配置） |
| 发布          | Packagist 无 API，提交仓库到 packagist.org 并开 git tag 自动更新钩子            |

**本地复现 CI**

```bash
composer install --no-interaction && \
php-cs-fixer fix --dry-run --diff && \
psalm --security-analysis && \
composer audit && \
phpunit --coverage-text
```

---

## .NET / C#

| 环节        | 命令                                                                                                |
| ----------- | --------------------------------------------------------------------------------------------------- |
| 脚手架      | `dotnet new console -n App`（或 `classlib`/`webapi`）                                               |
| 添加依赖    | `dotnet add package <name>`                                                                         |
| 格式        | `dotnet format --verify-no-changes`（修：去 `--verify-no-changes`）                                 |
| Lint/安全   | `dotnet format analyzers --verify-no-changes`（含 SecurityCodeScan 分析器）                         |
| 安全 SCA    | `dotnet list package --vulnerable`                                                                  |
| 测试+覆盖率 | `dotnet test /p:CollectCoverage=true /p:Threshold=80 /p:CoverletOutputFormat=cobertura`（coverlet） |
| 发布        | `dotnet pack -c Release` → `dotnet nuget push`（需 `NUGET_API_KEY`）                                |

**本地复现 CI**

```bash
dotnet format --verify-no-changes && \
dotnet format analyzers --verify-no-changes && \
dotnet list package --vulnerable && \
dotnet test /p:CollectCoverage=true /p:Threshold=80
```

---

## 通用：不在 CI 里跑、只在 nightly/手动跑的重型检查

- Rust Miri（慢，仅 unsafe 测试）
- Go fuzzing（`go test -fuzz`）
- Java SonarQube 长期扫描
- C/C++ sanitize 全套（`-fsanitize=address,undefined`）

这些放在单独的 `cron` 或 `workflow_dispatch` 触发的 workflow，避免每个 PR 都跑慢。
