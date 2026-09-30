# SKIPPED — 不做假测试的脚本/路径清单

原则：有副作用的操作（网络访问、破坏性 git 写操作、真实发布）不写假测试。
本套件只跳过以下三处，其余脚本或路径均已用「真实执行」或「stub mock 外部命令」覆盖。

## 1. `install-skill.sh update` 的 git pull 路径

- 不可测原因：`git pull --ff-only` 需要访问远端仓库（网络）；拉取失败时的回退分支
  执行 `git fetch origin` + `git reset --hard origin/<branch>`（规则 28 禁止的破坏性
  回退操作，测试中不得触发）。
- 已覆盖的替代面：非 git 仓时的降级分支（warn "跳过拉取，直接重新安装" + 重装）
  见 `test_install_skill.py::MultiSkillModeTest::test_update_without_git_warns_and_reinstalls_offline`。

## 2. init-*.sh 的真实 dev 依赖安装步骤（网络 registry）

涉及脚本与命令（均带 `|| warn` 兜底，失败不阻断 harness）：

| 脚本 | 网络命令 |
| --- | --- |
| init-python.sh | `uv add --dev ruff mypy bandit pip-audit pytest pytest-cov` |
| init-node.sh | `pnpm/npm add -D typescript … vitest …` |
| init-ruby.sh | `bundle add rspec rubocop …` |
| init-php.sh | `composer require --dev php-cs-fixer psalm phpunit` |
| init-dotnet.sh | `dotnet add package SecurityCodeScan.VS2019 / coverlet.collector` |
| init-multi.sh | setup_lang_deps 中上述各语言的 add/require |

- 不可测原因：需要访问 PyPI/npm/RubyGems/Packagist/NuGet（离线约束）。
- 已覆盖的替代面：测试用 PATH 前置 stub 命令 mock 这些子命令为 no-op，harness 侧
  真实逻辑（模板拷贝、snippet 合并、幂等保护、git init、hook 安装）全部真实执行。
  真实依赖解析属集成测试范畴，不在冒烟套件内。

## 3. 工具链缺失的 die 路径（环境相关的动态 skip）

`init-go.sh / init-java.sh / init-ruby.sh / init-php.sh / init-dotnet.sh` 的
`require_cmd` die 测试标注了 `skipIf(本机已装该工具)`——工具真实存在时无法模拟
"缺失"场景，对应用例自动 skip 而非假通过。当前环境 go/mvn/bundle/composer/dotnet
均未安装，这些用例实际执行。

## 备注（不算 skip）

- `install-hooks.sh` 的 `pre-commit install / lefthook install`：本机已装两工具时
  会在临时 git 仓的 `.git/hooks` 真实安装（init 系列测试已真实触发，临时目录无副作用）；
  未装时脚本走提示分支，两条路径均被覆盖。
- `init-rust.sh` 的 `cargo init` 与 `git init/add` 均为纯本地操作，已真实执行，无 mock。
