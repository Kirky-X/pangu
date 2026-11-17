# Changelog

## 0.1.11

### Added
- dependabot 模板家族终态（2026-11-16 决策）：patch 级更新默认 ignore 不自动开 PR + cooldown 7 天；注释示例同步为完整现代形态
- 家族事实标准工作流四件套随 init 自动部署：security.yml（actionlint + zizmor + gitleaks 增量/全历史双 job）、dependabot-branch-cleanup.yml（周一清孤儿分支，最小权限）、tag-deleted.yml（删 tag 联动删 Release）、feature-matrix.yml（rust，cargo-hack 单开矩阵）
- rust ci.yml 刷新家族终态：动态跨平台矩阵（含 job 级 if 禁引用 matrix 铁律注释）、action SHA 钉、paths-ignore、schedule 兜底腿
- rust release.yml 刷新家族终态：rc 预发布派生、Release 唯一性断言（幂等三元组）、crates.io trusted publishing（OIDC，token 条件路径备注释）
- templates/extras/ 特种工作流归档区：7 个源仓 13 个文件（bench/fuzz/api-surface/docker/scenario-tests 等），按需拷贝不随 init 部署
- CHANGELOG.md 建档

### Fixed
- render_placeholders 在 macOS 从未生效：BSD grep 不支持 `-Z` 输出 NUL 分隔，`read -d ''` 收不到文件名——改 `--null` + 双 `-e`（BSD/GNU/ugrep 三方兼容）
- init-go.sh 裸 `sed -i`（GNU 专用）在 BSD 下把替换脚本当备份后缀吞掉——改 `-i.bak` + 清理
- selfcheck 模板完整性检查豁免新增的 templates/extras/ 目录

### Changed
- copy_lang workflow 白名单加入 feature-matrix.yml（其他语言模板无此文件时静默跳过，向后兼容）
