# 特种工作流归档（extras）

从家族仓（projects workspace）原样归档的**仓特有能力**工作流，不随 init 自动部署。
需要对应能力时，把目标文件拷入新项目 `.github/workflows/` 并按仓实态改参
（crate 名 / cron / 路径 / feature 列表都是源仓定制值，直接用必错）。

| 目录 | 文件 | 能力 | 源仓 |
| --- | --- | --- | --- |
| CalNexus/ | audit.yml | 独立审计作业（与 ci.yml security 互补的异步审计线） | CalNexus |
| NebulaId/ | code-review.yml | AI 代码审查（OCR）接线 | NebulaId |
| NebulaId/ | health-check.yml | 定时健康检查（部署/依赖面探活） | NebulaId |
| crawlrs/ | bench.yml | criterion 基准回归门禁 | crawlrs |
| crawlrs/ | codeql-fp-dismiss.yml | CodeQL 误报申辩流程 | crawlrs |
| garrison/ | api-surface.yml / api-surface-diff.yml | 公共 API 面快照与 diff 门禁（破坏性变更拦截） | garrison |
| garrison/ | docs.yml | 文档构建门禁 | garrison |
| garrison/ | fuzz-weekly.yml | 每周模糊测试回归 | garrison |
| inklog/ | test-docker.yml | Docker 环境集成测试 | inklog |
| oxcache/ | dependency-check.yml | 依赖专项检查 | oxcache |
| vecboost/ | docker.yml | 镜像构建发布 | vecboost |
| vecboost/ | scenario-tests.yml | 场景级集成测试 | vecboost |

与其相对：`templates/common/github/workflows/` 与 `templates/rust/` 里的是
**家族事实标准**（codeql / security / dependabot-branch-cleanup / tag-deleted /
feature-matrix），随 init 自动部署。
