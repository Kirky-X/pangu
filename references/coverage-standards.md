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

## diff coverage（变更覆盖率）——pangu 已落地

只看总覆盖率的盲区：存量 85% + 新增 0% 也可能过线。pangu 的落地方式：全局门禁（≥阈值）之外，**diff coverage（≥阈值）双门禁**，跑在 CI `test/coverage` job 与 lefthook `pre-push` 两处，阈值由 `--cov`/`--profile` 一次性渲染（`__PANGU_COV__` 占位符）。

| 语言 | 报告产物 | diff-cover 兼容 | CI 位置 |
| --- | --- | --- | --- |
| Rust | `cargo llvm-cov --lcov` → lcov.info | ✅ LCov | ci.yml test job + lefthook pre-push |
| Python | pytest `--cov-report=xml` → coverage.xml (cobertura) | ✅ Cobertura | 同上 |
| Node/TS | vitest reporter "lcov" → coverage/lcov.info | ✅ LCov | 同上 |
| Java | JaCoCo → target/site/jacoco/jacoco.xml | ✅ JaCoCo XML | 同上 |
| C/C++ | gcovr `--xml` → coverage.xml (cobertura) | ✅ Cobertura | 同上 |
| PHP | phpunit `--coverage-clover` → coverage.xml | ✅ Clover | 同上 |
| .NET | Coverlet → cobertura（ReportGenerator 归一） | ✅ Cobertura | 同上 |
| Go | go 原生 coverprofile | ❌ 不支持（见下） | 仅全局门禁 |
| Ruby | simplecov .resultset.json | ❌ 不支持（见下） | 仅全局门禁 |

CI 内的统一命令形态（setup-uv 后 `uvx diff-cover`，uv 缓存避免每次冷安装；本地 lefthook pre-push 同样用 `uvx`）：

```bash
uvx diff-cover <report> --fail-under 80 --compare-branch "origin/main"
```

> **版本策略决策**：模板刻意不 pin diff-cover 版本（`uvx diff-cover` 拉最新）——门禁工具随上游修复更新，升级风险由「pin 了也会过期的通用工具」兜不住；若项目要求可复现，可自行改为 `uvx --from 'diff-cover==9.x'` 并交给 Dependabot 管理。另有 CI checkout 权衡：diff-cover 需要 `fetch-depth: 0`（全历史），超大仓库可达分钟级，fork PR 会把全量历史拉进 runner——历史误提交过敏感文件的项目请先清洗历史再开源。

**已知限制与升级路径**：

- **Go**：diff-cover 不解析 `go test -coverprofile` 原生格式。升级路径：`go install github.com/axw/gocov/gocov@latest && gocov convert c.out | gocov-xml > coverage.xml`（cobertura），再接 diff-cover。
- **Ruby**：simplecov 默认输出不被支持。升级路径：Gemfile 加 `gem "simplecov-cobertura"`，`SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter`（产出 coverage.xml），再接 diff-cover。

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

1. **本地 hook**（lefthook `pre-push` 的覆盖率门禁；pre-commit framework 无 push 阶段，由 CI 兜底）—— 推送前反馈
2. **CI workflow**（`ci.yml` 的 test/coverage job，全局 + diff 双门禁）—— 阻断 PR
3. **工具配置文件**（`pyproject.toml` / `vitest.config` / `pom.xml` 等）—— 单一真相源

pangu 通过 `__PANGU_COV__` 占位符一次性渲染三处（`--cov`/`--profile` 传入），天然一致；改动阈值时三处同步。

## 反模式（不要做）

- ❌ **门禁设 100%** —— 诱发改测试去凑数而非验证意图，getter/setter 也被迫写测试。
- ❌ **只看总覆盖率** —— 80% 总覆盖可能掩盖新增代码 0% 覆盖。必须同时看 diff coverage。
- ❌ **用覆盖率当质量指标** —— 80% 覆盖不等于 80% 正确性。覆盖率是必要非充分条件（见全局 `testing.md`）。
- ❌ **豁免不显式** —— 跳过的代码必须用 `# pragma: no cover` / `// c8 ignore` 显式标注并写原因，不能默默不测。
