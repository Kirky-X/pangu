# Pangu (盘古) — Project Harness Init

> Turns an empty directory into a fully-guarded project: language scaffolding + Git + GitHub CI quality gates + tag-triggered Release publishing + local pre-commit/lefthook dual checks + coverage gate (baseline 80%).

[![Version](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2FKirky-X%2Fpangu%2Fmain%2Fskill.json&query=%24.version&label=version&style=flat-square)](https://github.com/Kirky-X/pangu/releases) [![GitHub Release](https://img.shields.io/github/v/release/Kirky-X/pangu?style=flat-square)](https://github.com/Kirky-X/pangu/releases) [![GitHub License](https://img.shields.io/github/license/Kirky-X/pangu?style=flat-square)](LICENSE)

English | [中文](README.md)

## ✨ Features

- **One-command init for 9 languages**: Rust / Python / Node / Java / Go / C++ / Ruby / PHP / .NET, each with dedicated CI templates, Release workflows, security scanners (cargo-audit, bandit, gosec, OWASP Dep-Check, etc.), and coverage tooling.
- **3 hybrid forms**: coexisting monorepo (`init-multi.sh`), FFI rust→python (`init-rust-pyo3.sh`), FFI rust→node (`init-rust-napi.sh`).
- **10th project type — skill repos themselves**: `init-skill.sh` scaffolds a standard skill repo; `align-skill.sh` aligns existing skills (`--dry-run`/`--fix`); `bump-skill-version.sh` propagates version bumps.
- **Policy as code**: `.pre-commit-config.yaml` is the single source of gate truth; lefthook + CI mirror the core subset with unified thresholds (fast core: format/lint/license-deny; slow: coverage ≥80% + security audit → pre-push + CI).
- **Coverage gates are real**: Go/Ruby CI hard-fail via `--cov-fail-under=80` / awk threshold checks, never neutralized by `|| true`; uploads go through the official `codecov-action@v4`; gosec is pinned to `@v2.21.4` for Go.
- **Conditional release**: the Release workflow (triggered by `v*` tags) always produces a GitHub Release; it pushes to a registry (crates.io / PyPI / npm / Maven Central / RubyGems / NuGet) **only when the corresponding secret exists** — no secret, no error, just skip.
- **SHA-pinned own CI**: pangu's own workflows reference all third-party actions by commit SHA.
- **Dependency guardrails**: Dependabot + CodeQL + per-language SCA.

## 📦 Installation

```bash
# Option 1: deploy from this workspace (to ~/.zcode/skills and ~/.claude/skills)
bash scripts/sync-skills.sh pangu

# Option 2: manual copy into the ZCode skills directory
cp -r /path/to/pangu ~/.zcode/skills/pangu

# Option 3: remote install from GitHub
npx skills add Kirky-X/pangu --agent claude-code -y
```

## 🚀 Quick Start

Prerequisites: the target language toolchain (e.g. `uv` for Python, `cargo` for Rust); `$SKILL` is the skill install directory (e.g. `~/.zcode/skills/pangu`).

```bash
cd /path/to/project   # An empty dir works best; running init in an existing project overwrites some config — confirm first

# Language init (self-contained: native scaffold + harness templates + git init + local hooks)
bash "$SKILL/scripts/init-python.sh" my-project
bash "$SKILL/scripts/init-rust.sh" my-project

# Hybrid projects
bash "$SKILL/scripts/init-multi.sh" rust,python,node my-monorepo   # coexisting monorepo
# FFI: run maturin new --mixed --bindings pyo3 <name> (or napi new) first, then init-rust-pyo3.sh / init-rust-napi.sh

# Skill-repo init (meta mode)
bash "$SKILL/scripts/init-skill.sh" my-skill --cn-name 我的技能
```

After init, follow the printed next steps: enable a local hook (`pre-commit install` or `lefthook install`, pick one) → reproduce CI commands locally until green → configure publish secrets (optional) → push to trigger CI / push a `v*` tag to trigger Release.

```mermaid
flowchart LR
    A["Stage 0 Intent"] --> B["Stage 1 init-{L}.sh"] --> C["Stage 2 CI gates"] --> D["Stage 3 Release"] --> E["Stage 4 Deps"] --> F["Stage 5 Verify STOP"]
```

## ✅ Tests & Verification

Verified 2026-09-13 (v0.1.4, matching the git tag):

- **Self-check gate**: `bash scripts/selfcheck.sh` passes in full — shellcheck on 20 scripts with 0 errors, YAML lint on 27 template files, and template integrity (ci.yml / release.yml / .pre-commit-config.yaml / lefthook.yml / .gitignore) for all 9+1 language dirs.
- **Functional** (temp directories):
  - `init-python.sh demo-py`: produced `pyproject.toml` + `src/` + `.pre-commit-config.yaml` + `lefthook.yml` + `.github/workflows/{ci.yml,codeql.yml,release.yml}`, with `uv run pytest --cov --cov-fail-under=80` in CI
  - `init-rust.sh demo-rs`: produced `Cargo.toml` + `rustfmt.toml` + `clippy.toml` + `deny.toml` + the same workflow set
  - Go/Ruby template coverage gates are hard-fail checks (awk threshold comparison, no `|| true`)
- pangu's own CI (`.github/workflows/ci.yml`) pins every action by commit SHA.

## 📁 Directory Structure

```
pangu/
├── SKILL.md            # Route table + 5-stage flow + failure handling
├── skill.json
├── scripts/            # 20 scripts
│   ├── init-{rust,python,node,java,go,cpp,ruby,php,dotnet}.sh
│   ├── init-multi.sh / init-rust-pyo3.sh / init-rust-napi.sh
│   ├── init-skill.sh / align-skill.sh / bump-skill-version.sh
│   ├── install-hooks.sh / _common.sh / selfcheck.sh
│   └── install-skill.sh
├── templates/          # 11 template dirs
│   ├── common/             # dependabot / codeql / issue-pr templates / CODEOWNERS
│   ├── {rust,…,dotnet}/    # per-language CI / release / hook configs
│   └── skill/              # skill-repo templates (9 .template files)
└── references/         # 7 references (languages / coverage-standards / hooks-compare / registry-secrets / multi-language / skill-release / build-optimization)
```

## 🔮 Boundaries

- **Does not trigger**: adding a single hook or editing one CI step (edit the file directly); localized changes to a mature project; generating only a `.gitignore`; the user explicitly wanting a single artifact (e.g. "just give me a release.yml").
- **Sibling skills**: pangu covers 0-to-1 initialization; `specmark` manages the change process afterwards; `tiangang` runs security scans (CI security tooling is pre-wired by pangu, day-to-day scanning belongs to tiangang); `diting` handles code quality review.

## 📄 License & Attribution

MIT License. Author Kirky-X, repo [Kirky-X/pangu](https://github.com/Kirky-X/pangu).
