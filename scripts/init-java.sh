#!/usr/bin/env bash
# 一键初始化 Java (Maven) 项目 harness。
# 用法:
#   init-java.sh [artifactId]
# 环境变量:
#   JAVA_GROUP_ID  Maven groupId（默认 com.example）
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

LANG_NAME="Java (Maven)"
require_cmd mvn

ARTIFACT="${1:-app}"
GROUP_ID="${JAVA_GROUP_ID:-com.example}"

mvn -B archetype:generate \
  -DgroupId="$GROUP_ID" \
  -DartifactId="$ARTIFACT" \
  -DarchetypeGroupId=org.apache.maven.archetypes \
  -DarchetypeArtifactId=maven-archetype-quickstart \
  -DarchetypeVersion=1.5 \
  -DinteractiveMode=false >/dev/null

PROJ_DIR="$(cd "$ARTIFACT" && pwd)"
log "Java 脚手架已生成 (mvn archetype:generate → $ARTIFACT)"

copy_common
copy_lang java

# 提示：质量插件（spotless/checkstyle/spotbugs-findsecbugs/jacoco/owasp-depcheck）
# 配置在 templates/java/pom-plugins.snippet.xml，需合并进生成的 pom.xml
warn "Java: 请将 pom-plugins.snippet.xml 的 <build>/<reporting> 片段合并到 $PROJ_DIR/pom.xml"
warn "  （合并前 CI 的 spotless/checkstyle/spotbugs/jacoco 步骤会失败）"

git_init
install_hooks
harness_finalize
