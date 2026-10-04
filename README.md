# Pangu（盘古）— 项目 Harness 初始化技能

> 把空目录变成带完整质量护栏的项目：语言脚手架 + Git + GitHub CI 质量门禁 + tag 触发的 Release 发布 + 本地 pre-commit/lefthook 双检查 + 覆盖率双门禁（全局 + diff coverage）。

[![Version](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2FKirky-X%2Fpangu%2Fmain%2Fskill.json&query=%24.version&label=version&style=flat-square)](https://github.com/Kirky-X/pangu/releases) [![GitHub Release](https://img.shields.io/github/v/release/Kirky-X/pangu?style=flat-square)](https://github.com/Kirky-X/pangu/releases) [![GitHub License](https://img.shields.io/github/license/Kirky-X/pangu?style=flat-square)](LICENSE)

中文 | [English](README_EN.md)

## ✨ 功能特性

- **9 语言一键初始化**：Rust / Python / Node / Java / Go / C++ / Ruby / PHP / .NET，每语言配套专属 CI 模板、Release 工作流、安全扫描（cargo-audit、bandit、gosec、OWASP Dep-Check 等）与覆盖率工具
- **3 种混合形态**：并存型 monorepo（`init-multi.sh`）、FFI rust→python（`init-rust-pyo3.sh`）、FFI rust→node（`init-rust-napi.sh`）
- **第 10 种项目类型：skill 仓库本身**：`init-skill.sh` 一键初始化标准 skill 仓库；`align-skill.sh` 对齐存量 skill（`--dry-run`/`--fix`）；`bump-skill-version.sh` 传播版本号
- **门禁即代码**：`.pre-commit-config.yaml` 为门禁单一来源，lefthook + CI 镜核心子集，阈值统一（fast 核心：格式/lint/license-deny；slow：覆盖率全局+diff 双门禁 + 安全审计 → lefthook pre-push + CI，9 语言等价，冒烟测试守护）
- **diff coverage 双门禁**：全局覆盖率之外，对相对基线分支的新增/修改行同样设阈值（diff-cover 对接 7 语言；Go/Ruby 暂仅全局，升级路径见 coverage-standards）——新代码 0 覆盖无法再靠存量拉高全局通过
- **参数化阈值**：init 支持 `--cov <N>` / `--profile core|tool`（核心业务 85 / 工具类 70）/ `--branch` / `--no-release` / `--no-codeql` / `--changelog release-please`，阈值与分支经占位符渲染进 CI/lefthook/工具配置三处，天然一致
- **两段式 Release**：tag 触发先跑 `verify` job（tag 格式 + tag↔版本 manifest 一致性），tag 打错不进入构建；rust/go/cpp/php 产物附 checksums.txt，npm 发布带 provenance（详见 registry-secrets 的 attestation/cosign 加固）
- **生成来源可追溯**：init 写入 `.pangu-meta.yml`（pangu 版本/参数/harness 文件清单），模板升级时对照对应 tag 手动 diff；`doctor.sh` 一键体检已生成项目
- **覆盖率门禁真实生效**：阈值判定硬失败，不以 `|| true` 中和；上传统一走官方 `codecov-action@v4`；cpp 三平台构建矩阵 + 独立覆盖率 job；php/dotnet CI 依赖缓存（cpp 模板无依赖缓存）
- **自身 CI SHA-pin**：pangu 仓库的 workflows 对所有第三方 action 使用 commit SHA 固定引用
- **依赖护栏**：Dependabot + CodeQL（`--no-codeql` 可裁剪）+ 各语言专属 SCA

## 📦 安装

```bash
# 方式一：安装到某个项目的 agent 目录（install-skill.sh 共 7 个子命令，支持 9 种 agent）
bash scripts/install-skill.sh install pangu --target /path/to/project --agent claude

# 方式二：手动复制到 ZCode 技能目录
cp -r /path/to/pangu ~/.zcode/skills/pangu

# 方式三：远程安装（GitHub 仓库）
npx skills add Kirky-X/pangu --agent claude-code -y
```

## 🚀 快速开始

前置条件：目标语言工具链（如 Python 需 `uv`，Rust 需 `cargo`）；`$SKILL` 为 skill 安装目录（如 `~/.zcode/skills/pangu`）。

```bash
cd /path/to/project   # 空目录最佳；已有项目目录会被覆盖部分配置，先确认

# 语言初始化（脚本自包含：语言脚手架 + harness 模板 + 占位符渲染 + .pangu-meta + git init + 装 hooks）
bash "$SKILL/scripts/init-python.sh" my-project
bash "$SKILL/scripts/init-rust.sh" my-project --profile core   # 核心业务阈值 85
bash "$SKILL/scripts/init-go.sh" my-project --branch master --no-codeql

# 混合项目
bash "$SKILL/scripts/init-multi.sh" rust,python,node my-monorepo   # 并存型
# FFI：先 maturin new --mixed --bindings pyo3 <name>（或 napi new），再跑 init-rust-pyo3.sh / init-rust-napi.sh

# skill 仓库初始化（meta 模式）
bash "$SKILL/scripts/init-skill.sh" my-skill --cn-name 我的技能
```

初始化后按提示：启用本地 hook（`pre-commit install` / `lefthook install` / `prek install` 三选一，配置已生成）→ 本地复现 CI 等价命令全绿（含 diff coverage）→ 配置发布 secret（可选）→ push 触发 CI / 推 `v*` tag 触发 Release。诊断已生成项目：`bash "$SKILL/scripts/doctor.sh" "$(pwd)"`。

```mermaid
flowchart LR
    A["阶段0 意图确认+旗标"] --> B["阶段1 init-{L}.sh"] --> C["阶段2 CI 门禁(全局+diff)"] --> D["阶段3 Release(两段式)"] --> E["阶段4 依赖护栏"] --> F["阶段5 验证+doctor STOP"]
```

## ✅ 测试与验证

2026-10-04 实测（v0.1.6 未发布，工作区版本）：

- **自检门禁**：`bash scripts/selfcheck.sh` 全部通过 — shellcheck 22 个脚本 0 错误、YAML lint 42 个模板文件、9 语言模板完整性（skill/common 目录清点在自身 CI integrity job）、SKILL.md 索引校验（72 个引用路径 fail-closed）、init 冒烟测试
- **init 冒烟测试**（`scripts/smoke-test.sh`，templates-only 端到端）：9 语言 × 默认参数（文件齐全/占位符零残留/YAML 可解析/git 初始化/lefthook 等价性基线/no snippet 残留）+ 参数化断言（`--cov 90 --branch trunk --no-release --no-codeql` 渲染与裁剪正确）全绿
- **doctor 实测**：对冒烟产物跑 `scripts/doctor.sh` 全部通过（文件/YAML/hooks/门禁/来源记录）
- **pytest 回归套件**：`python3 -m pytest tests/ -q` 122 用例全部通过（各语言 init / 多语言 / FFI / skill 仓库 / align / bump / install-skill / selfcheck 行为）
- **多语言前缀与 lint**：`bash scripts/test-multi.sh` ALL GREEN（copy_lang prefix）；`python3 scripts/skill_lint.py .` 0 fail / 0 warn
- **评测资产**：`evals/evals.json` 3 条评测 + `test-prompts.json` 5 条触发测试；`hooks/pre-push` 为本仓库自用清理钩子（push 前 git gc + cargo clean）
- pangu 自身 CI（`.github/workflows/ci.yml`）对所有 action 使用 commit SHA 固定引用，含 lint / integrity / smoke 三类 job

## 📁 目录结构

```
pangu/
├── SKILL.md            # 路由表 + 5 阶段流程 + 失败处置
├── skill.json
├── test-prompts.json   # 5 条触发测试 prompt
├── scripts/            # 22 个脚本
│   ├── init-{rust,python,node,java,go,cpp,ruby,php,dotnet}.sh
│   ├── init-multi.sh / init-rust-pyo3.sh / init-rust-napi.sh
│   ├── init-skill.sh / align-skill.sh / bump-skill-version.sh
│   ├── install-hooks.sh / _common.sh / selfcheck.sh
│   ├── smoke-test.sh / doctor.sh / test-multi.sh
│   ├── install-skill.sh / skill_lint.py
│   └── kb/tests/           # 6 个专项回归脚本
├── templates/          # 11 个模板目录
│   ├── common/             # dependabot / codeql / issue-pr 模板 / CODEOWNERS / release-please(opt-in)
│   ├── {rust,…,dotnet}/    # 各语言 CI(全局+diff 覆盖率) / release(verify 两段式) / hook 配置
│   └── skill/              # skill 仓库模板（9 个 .template 文件）
├── references/         # 7 篇参考（languages / coverage-standards / hooks-compare / registry-secrets / multi-language / skill-release / build-optimization）
├── hooks/              # 仓库自用 pre-push 清理（git gc + cargo clean）
├── tests/              # pytest 套件（122 用例）
└── evals/              # evals.json（3 条评测）
```

## 🔮 边界

- **不触发**：单纯加一个 hook 或改一条 CI 步骤（直接编辑文件）；已有成熟项目的局部改造；仅生成 `.gitignore`；用户明确只要某一种产物（如「只给我个 release.yml」）
- **与兄弟 skill 分工**：pangu 管从 0 到 1 的初始化；`specmark` 管初始化之后的变更过程；`tiangang` 管安全扫描（CI 里的安全工具由 pangu 预置，日常扫描走 tiangang）；`diting` 管代码质量审查

## 📄 License 与归属

MIT License。作者 Kirky-X，仓库 [Kirky-X/pangu](https://github.com/Kirky-X/pangu)。
