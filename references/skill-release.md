# Skill 仓库发版 SOP（命令式）

6 步骤命令式发版流程，覆盖从版本号设定到 GitHub Release 发布的完整链路。与 `templates/skill/.github/workflows/release.yml.template` 的 CI 自动化互补——SOP 在发版前完成版本号同步与 CHANGELOG 编辑，CI 在 tag 推送后自动建 GitHub Release。

## 适用范围

标准 skill 仓库布局（由 `scripts/init-skill.sh` 初始化）：
- `skill.json`（顶层 `version` 字段）
- `.claude-plugin/marketplace.json`（`plugins[]` 数组，可选 `version` 字段）
- `README.md`（可选 shields.io `version-<x.y.z>-blue` badge）
- `.github/workflows/release.yml`（tag 推送触发的 GitHub Release 自动化）

其他布局（含 `package.json` / `.claude-plugin/plugin.json` / `.codex-plugin/plugin.json` / `gemini-extension.json`）同样适用——`bump-skill-version.sh` 自动检测文件存在性，不存在的静默跳过。

---

## 步骤 1 · Set source of truth

设定版本号源头。两种方式选一：

**方式 A：有 `package.json`（推荐，与 brooks-lint 流程一致）**

```bash
npm version <version> --no-git-tag-version
```

`--no-git-tag-version` 必填——plain `npm version` 会自建 commit + tag 与步骤 5 的手动 commit 冲突。

**方式 B：无 `package.json`（纯 skill 仓库）**

手动编辑 `skill.json` 的 `version` 字段：

```bash
# 例：用 python3 改 JSON（保留 indent）
python3 -c "
import json
with open('skill.json') as f: d = json.load(f)
d['version'] = '<version>'
with open('skill.json', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
    f.write('\n')
"
```

或直接用编辑器改 `skill.json` 的 `"version": "x.y.z"` 行。

## 步骤 2 · Propagate

把版本号同步到所有 manifest + README badge：

```bash
bash <skill>/scripts/bump-skill-version.sh <version>
```

脚本行为：
- 检测存在的 manifest 文件（`skill.json` / `package.json` / `.claude-plugin/plugin.json` / `.codex-plugin/plugin.json` / `gemini-extension.json` / `.claude-plugin/marketplace.json`），更新其中的 `version` 字段
- 不存在的文件静默跳过；存在但无 `version` 字段的 manifest warn 跳过（不强行添加字段）
- 更新 `README.md` 中形如 `version-<x.y.z>-<color>` 的 shields.io badge
- 末尾打印 summary：`更新 N 个文件，跳过 M 个，badge K 处`

可选 `--proj-dir <dir>` 指定项目目录（默认当前目录），`--check` dry-run 模式只打印不修改。

## 步骤 3 · Write changelog

在 `CHANGELOG.md` 顶部加 `## <version>` 段，按 Added / Fixed / Changed 分类记录本次发版内容：

```bash
# 查看自上次 tag 以来的 commit
git log <last-tag>..HEAD --oneline

# 若无上次 tag（首次发版）
git log --oneline | head -20
```

`CHANGELOG.md` 格式示例：

```markdown
# Changelog

## 1.2.3

### Added
- 新增 bump-skill-version.sh 通用版本号传播脚本

### Fixed
- 修复 init-python.sh 必失败的 CRITICAL bug

### Changed
- dotnet 默认行为对齐其他 init-*.sh

## 1.2.2
...
```

CHANGELOG 内容是人工决策——自动从 commit message 提取会丢失 Added/Fixed/Changed 分类语义。

## 步骤 4 · Validate

验证版本号一致性 + 跑测试套件：

```bash
# 4a. 幂等检查：再跑一次 bump 应显示无变更
bash <skill>/scripts/bump-skill-version.sh <version> --check
# 期望输出：每个 manifest "version 已是 <version>，无变化"

# 4b. git diff 检查改动范围
git diff --stat
git diff skill.json
git diff README.md

# 4c. 跑项目测试套件（若存在）
# bash scripts/kb/tests/test-*.sh
# 或 npm test / cargo test / pytest 等
```

若 `--check` 显示有变更，说明步骤 2 未完整执行——重跑步骤 2。

## 步骤 5 · Commit & push

提交版本号 + CHANGELOG 改动：

```bash
git add -A
git commit -m "chore(release): bump version to <version>"
git push
```

直接推 `main`（skill 仓库通常是 direct-to-main，无 PR 流程）。若仓库有 PR 流程，改为推分支 + 开 PR。

## 步骤 6 · Tag & publish

推 tag 触发 CI 自动建 GitHub Release：

```bash
git tag v<version>
git push --tags
```

`templates/skill/.github/workflows/release.yml.template` 中的 GitHub Action 会自动：
- `softprops/action-gh-release@v2` 创建 GitHub Release
- `generate_release_notes: true` 自动从 commit 生成 release notes
- 预发布版本（`-rc` / `-beta` / `-alpha`）标记为 prerelease

**手动建 release（CI 未配置或失败时）**：

```bash
gh release create v<version> --title "v<version>" --notes "$(awk '/^## <version>/,/^## [0-9]/' CHANGELOG.md | sed '1d;$d')"
```

`--notes` 从 CHANGELOG.md 提取对应版本段。

---

## 已知限制

1. **不验证 manifest schema** — `bump-skill-version.sh` 只更新 `version` 字段，不校验 manifest 整体 schema。一致性验证靠步骤 4 的 `--check` 幂等 + `git diff` 人工核对。若需强 schema 断言，需项目专属 validate 脚本（如 brooks-lint 的 `npm run validate`），泛化成本高于收益。

2. **仅支持 shields.io `version-<x.y.z>-` badge 格式** — `bump-skill-version.sh` 的 README badge 正则锚定 `version-` 前缀 + 语义化版本 + `-` 后缀（色名不限制，`blue`/`red`/`green` 等都匹配）。其他前缀格式（如 `v<x.y.z>-blue`、`ver-<x.y.z>-blue`）不被识别。

3. **CHANGELOG 内容是人工决策** — 不自动从 commit message 生成 CHANGELOG 段。Added/Fixed/Changed 分类需要维护者根据 commit 内容人工判断。

4. **无 `npm run bump` 等价快捷方式** — 直接 `bash scripts/bump-skill-version.sh <v>` 调用，不假设 skill 仓库有 npm/package.json。若仓库有 package.json，可自行在 `scripts` 字段加 `"bump": "bash scripts/bump-skill-version.sh"`。

5. **marketplace.json 无 version 字段时跳过** — pangu 自身 `.claude-plugin/marketplace.json` 当前 schema 无 `version` 字段（只有 `metadata` + `plugins[name/source/skills]`）。`bump-skill-version.sh` 会 warn 跳过。是否为 marketplace.json 加 version 字段是 schema 演进决策，不在本 SOP 范围。
