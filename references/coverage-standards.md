# 行业覆盖率门禁标准

## 通用阈值（事实基准）

| 维度                            | 门槛             | 说明                                                               |
| ------------------------------- | ---------------- | ------------------------------------------------------------------ |
| **总行覆盖率底线**              | **≥ 80%**        | 业界最广泛采用的 CI 门禁底线（Google/Test/多数大厂内部准则的下限） |
| **核心业务逻辑**                | ≥ 85%，建议 90%+ | 资金、权限、算法、状态机——出错代价最高的代码                       |
| **工具类 / 纯函数**             | ≥ 70%            | 边角多，强求 100% 性价比低                                         |
| **配置/胶水代码**               | 可豁免           | DTO、main 入口、迁移文件——显式标注 `# pragma: no cover` 类豁免     |
| **变更覆盖率（diff coverage）** | ≥ 80%            | 新增/修改行必须被测试覆盖，防止存量下降被稀释                      |

> 行业基准：Google SRE/工程文化 ~80%，Microsoft 多数项目 75-80%，开源旗舰项目（Linux kernel 子系统、kubernetes）80%+。**低于 70% 的门禁形同虚设**，不要设。

## 各语言覆盖率工具与门禁配置

### Rust — `cargo-llvm-cov`（首选，基于 LLVM，比 tarpaulin 快且稳）

```bash
cargo llvm-cov --fail-under-lines 80 --fail-under-functions 80 --workspace
```

> 备选 `cargo-tarpaulin --fail-under-line 80`（仅 Linux 稳定，macOS 支持差）。

### Python — `pytest-cov`

```bash
pytest --cov=src --cov-report=term-missing --cov-report=xml --cov-fail-under=80
```

`pyproject.toml` 持久化：

```toml
[tool.coverage.report]
fail_under = 80
show_missing = true
```

### Node/TS — Vitest

```ts
// vitest.config.ts
test: {
  coverage: {
    provider: 'v8',
    reporter: ['text', 'lcov'],
    thresholds: { lines: 80, functions: 80, branches: 75, statements: 80 },
  },
}
```

Jest 备选：`--coverageThreshold='{"global":{"lines":80}}'`。

### Java — JaCoCo

```xml
<!-- pom.xml -->
<plugin>
  <groupId>org.jacoco</groupId>
  <artifactId>jacoco-maven-plugin</artifactId>
  <executions>
    <execution><id>check</id><goals><goal>check</goal></goals>
      <configuration><rules><rule>
        <element>BUNDLE</element><limits>
          <limit><counter>LINE</counter><minimum>0.80</minimum></limit>
        </limits>
      </rule></rules></configuration>
    </execution>
  </executions>
</plugin>
```

### Go — `go test -coverprofile` + 自定义阈值脚本

Go 无原生 `--fail-under`，用脚本比对：

```bash
go test -coverprofile=c.out -coverpkg=./... ./...
total=$(go tool cover -func=c.out | grep total | awk '{print $3}' | tr -d '%')
[ "${total%.*}" -ge 80 ] || { echo "coverage $total < 80"; exit 1; }
```

或用 `go-test-coverage`：`go-test-coverage --profile=c.out --threshold=80`。

### C/C++ — `gcovr`

```bash
gcovr --fail-under-line 80 --fail-under-branch 70 --xml -o coverage.xml
```

### Ruby — `simplecov`

```ruby
# spec_helper.rb / test_helper.rb
require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  minimum_coverage 80
  minimum_coverage_by_file 60   # 单文件底线，防聚合造假
end
SimpleCov.refuse_coverage_drop # 防回退
```

### PHP — PHPUnit

```xml
<!-- phpunit.xml -->
<coverage>
  <report><text outputFile="php://stdout"/></report>
</coverage>
<source><directory>src</directory></source>
```

门禁：`--fail-on-risky` + 在 CI 脚本里解析 coverage 百分比比对 80。或用 `infection`（变异测试）兜底。

### .NET — Coverlet

```bash
dotnet test /p:CollectCoverage=true /p:Threshold=80 /p:ThresholdType=line /p:CoverletOutputFormat=cobertura
```

## 三处一致原则

覆盖率阈值必须**同时**配置在：

1. **本地 hook**（pre-commit/lefthook 里的测试阶段）—— 立即反馈
2. **CI workflow**（`ci.yml` 的 test job）—— 阻断 PR
3. **工具配置文件**（`pyproject.toml` / `vitest.config` / `pom.xml` 等）—— 单一真相源

三处数字不一致 = 门禁可绕过。改动阈值时三处同步。

## 反模式（不要做）

- ❌ **门禁设 100%** —— 诱发改测试去凑数而非验证意图，getter/setter 也被迫写测试。
- ❌ **只看总覆盖率** —— 80% 总覆盖可能掩盖新增代码 0% 覆盖。必须同时看 diff coverage。
- ❌ **用覆盖率当质量指标** —— 80% 覆盖不等于 80% 正确性。覆盖率是必要非充分条件（见全局 `testing.md`）。
- ❌ **豁免不显式** —— 跳过的代码必须用 `# pragma: no cover` / `// c8 ignore` 显式标注并写原因，不能默默不测。
