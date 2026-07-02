# Registry 发布与 Secret 配置

Release 工作流（`templates/<lang>/release.yml`）遵循**条件发布**：GitHub Release 总是创建；registry 发布仅当对应 secret 存在时执行，否则静默跳过。本文档列出各 registry 所需 secret 与配置步骤。

## Secret 配置位置

GitHub 仓库 → Settings → Secrets and variables → Actions → New repository secret。
**不要**把 secret 写进仓库文件；release.yml 用 `${{ secrets.XXX }}` 引用，存在性用 `if: env.XXX != ''` 判断。

---

## crates.io（Rust）

| Secret                 | 值                  | 获取                                                                     |
| ---------------------- | ------------------- | ------------------------------------------------------------------------ |
| `CARGO_REGISTRY_TOKEN` | crates.io API token | crates.io → Account Settings → API Tokens → New（scope：publish-update） |

```yaml
# release.yml 片段
- name: Publish to crates.io
  if: ${{ env.CARGO_REGISTRY_TOKEN != '' }}
  env:
    CARGO_REGISTRY_TOKEN: ${{ secrets.CARGO_REGISTRY_TOKEN }}
  run: cargo publish --all-features
```

> 建议同时配置 `CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse`（默认已是）。

---

## PyPI（Python）

两种方式：

**A. Trusted Publishing（推荐，免 token）** — OIDC，无需 secret，在 PyPI 配置 GitHub 仓库 + workflow 名。

```yaml
permissions:
  id-token: write   # 关键，OIDC
- name: Publish to PyPI
  uses: pypa/gh-action-pypi-publish@release/v1
  # 无 password，走 trusted publishing
```

**B. API Token** — 传统方式。
| Secret | 值 |
|--------|----|
| `UV_PUBLISH_TOKEN` 或 `PYPI_TOKEN` | `pypi-<token>`（PyPI → Account settings → API tokens，scope 全仓或单项目） |

```yaml
- name: Publish to PyPI
  if: ${{ env.UV_PUBLISH_TOKEN != '' }}
  env:
    UV_PUBLISH_TOKEN: ${{ secrets.UV_PUBLISH_TOKEN }}
  run: uv publish
```

---

## npm（Node/TS）

| Secret      | 值               | 获取                                                                      |
| ----------- | ---------------- | ------------------------------------------------------------------------- |
| `NPM_TOKEN` | npm access token | npmjs.com → Access Tokens → New（Classic Automation 或 Granular Publish） |

```yaml
- name: Setup .npmrc
  if: ${{ env.NPM_TOKEN != '' }}
  run: echo "//registry.npmjs.org/:_authToken=${NPM_TOKEN}" >> ~/.npmrc
  env:
    NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
- name: Publish to npm
  if: ${{ env.NPM_TOKEN != '' }}
  run: npm publish --provenance --access public
```

> 开 `--provenance` 需 `permissions: id-token: write`，提升供应链可信度。

---

## Maven Central（Java）

最复杂，需要 GPG 签名 + Sonatype 中央仓库凭证。

| Secret                  | 值                                                     |
| ----------------------- | ------------------------------------------------------ |
| `MAVEN_USERNAME`        | Sonatype JIRA 用户名（中央仓库）                       |
| `MAVEN_CENTRAL_TOKEN`   | Sonatype JIRA 密码 / 中央仓库 token                    |
| `MAVEN_GPG_PRIVATE_KEY` | GPG 私钥（`gpg --armor --export-secret-keys <keyid>`） |
| `MAVEN_GPG_PASSPHRASE`  | GPG 私钥口令                                           |

```yaml
- name: Publish to Maven Central
  if: ${{ env.MAVEN_CENTRAL_TOKEN != '' && env.MAVEN_GPG_PRIVATE_KEY != '' }}
  env:
    MAVEN_USERNAME: ${{ secrets.MAVEN_USERNAME }}
    MAVEN_CENTRAL_TOKEN: ${{ secrets.MAVEN_CENTRAL_TOKEN }}
    MAVEN_GPG_PRIVATE_KEY: ${{ secrets.MAVEN_GPG_PRIVATE_KEY }}
    MAVEN_GPG_PASSPHRASE: ${{ secrets.MAVEN_GPG_PASSPHRASE }}
  run: mvn -B deploy -DskipTests
```

> 新版中央仓库（Central Portal）逐步支持 API token + 免 GPG，按目标平台实际调整。

---

## RubyGems（Ruby）

| Secret                | 值               | 获取                                                            |
| --------------------- | ---------------- | --------------------------------------------------------------- |
| `RUBYGEMS_AUTH_TOKEN` | RubyGems API key | rubygems.org → Edit Settings → API Keys（scope：push rubygems） |

```yaml
- name: Publish to RubyGems
  if: ${{ env.RUBYGEMS_AUTH_TOKEN != '' }}
  env:
    GEM_HOST_API_KEY: ${{ secrets.RUBYGEMS_AUTH_TOKEN }}
  run: |
    gem build *.gemspec
    gem push *.gem
```

---

## NuGet（.NET）

| Secret          | 值            | 获取                                         |
| --------------- | ------------- | -------------------------------------------- |
| `NUGET_API_KEY` | NuGet API key | nuget.org → API Keys → Create（scope：push） |

```yaml
- name: Publish to NuGet
  if: ${{ env.NUGET_API_KEY != '' }}
  env:
    NUGET_API_KEY: ${{ secrets.NUGET_API_KEY }}
  run: |
    dotnet pack -c Release
    dotnet nuget push **/*.nupkg --api-key ${NUGET_API_KEY} --source https://api.nuget.org/v3/index.json --skip-duplicate
```

---

## Packagist（PHP）

**无 API 发布**。机制：在 packagist.org 提交仓库 URL，平台用 webhook 拉 git tag 自动更新。

- 无需 secret。
- 仅 release.yml 创建 GitHub Release + git tag 即可，Packagist 端配置一次后自动同步。

---

## Go（无中心 registry）

发 GitHub Release，附加跨平台预编译二进制。可选 `goreleaser`：

```yaml
- name: Run GoReleaser
  uses: goreleaser/goreleaser-action@v6
  with:
    args: release --clean
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }} # 自动提供，无需另配
```

---

## 通用：GitHub Release（所有语言，无条件执行）

`GITHUB_TOKEN` 由 Actions 自动注入，无需配置。用 `softprops/action-gh-release` 或官方 API：

```yaml
- name: Create GitHub Release
  uses: softprops/action-gh-release@v2
  with:
    files: |
      target/*.tar.gz
      dist/*.whl
      build/libs/*.jar
    generate_release_notes: true
```

---

## Secret 存在性判断的统一写法

release job 开头把 secret 导出为 env，后续步骤用 `if: env.XXX != ''`：

```yaml
jobs:
  release:
    runs-on: ubuntu-latest
    env:
      CARGO_REGISTRY_TOKEN: ${{ secrets.CARGO_REGISTRY_TOKEN }}
    steps:
      - name: Conditional publish
        if: env.CARGO_REGISTRY_TOKEN != ''
        ...
```

这样：配了 secret → 自动发布；没配 → 跳过，CI 不红。符合「条件发布」原则。
