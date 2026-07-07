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

# merge_pom_plugins <pom> <snippet>
# 确定性合并 pom-plugins.snippet.xml 的 <properties>/<build>/<reporting> 到 archetype 生成的 pom.xml。
# 策略（schema 安全：Maven POM XSD 对 <project> 子元素顺序有约束——properties 在 dependencies 前，build/reporting 在其后）：
#   - <properties>：原位替换（snippet 是超集：compiler.release 取代 archetype 的 source/target，含 sourceEncoding）
#   - <build>/<reporting>：pom 无则注入到 </project> 前（dependencies 之后 = 正确顺序）；已有则跳过 + warn（避免重复块致 XML 非法）
# 合并后 xmllint 校验 well-formed；失败则丢弃合并、保留原 pom + snippet 供手动合并。
# 任何失败均 return 0 + warn（不破坏 harness 主流程；最坏情况退回原手动合并路径）。
merge_pom_plugins() {
  local pom="$1" snippet="$2"
  [ -f "$pom" ] || { warn "merge_pom_plugins: pom 不存在 ($pom)，跳过"; return 0; }
  [ -f "$snippet" ] || { warn "merge_pom_plugins: snippet 不存在 ($snippet)，跳过"; return 0; }

  local tmp="${pom}.pangu.tmp"
  # awk 提取 snippet 三块并注入 pom；getline 读 snippet，index/substr 定位标签块。
  awk -v snippet="$snippet" '
    function extract(text, tag,   opn, cls, p1, p2) {
      opn = "<" tag ">"; cls = "</" tag ">"
      p1 = index(text, opn); if (p1 == 0) return ""
      p2 = index(text, cls); if (p2 == 0) return ""
      return substr(text, p1, p2 + length(cls) - p1)
    }
    BEGIN {
      # 读 snippet，跳过多行/单行 <!-- ... --> 注释（避免注释里的标签污染抽取）
      s = ""; incmt = 0
      while ((getline line < snippet) > 0) {
        if (incmt) { if (line ~ /-->/) incmt = 0; continue }
        if (line ~ /<!--/) { if (line ~ /-->/) continue; incmt = 1; continue }
        s = s line "\n"
      }
      close(snippet)
      PROPS = extract(s, "properties")
      BUILD = extract(s, "build")
      REPORTING = extract(s, "reporting")
      warns = ""
    }
    {
      # 原位替换 pom 的 <properties> 整块（跳过原内容，emit snippet 的 PROPS）
      if (in_props) { if ($0 ~ /^[[:space:]]*<\/properties>/) in_props = 0; next }
      if (PROPS && $0 ~ /^[[:space:]]*<properties>/) { print PROPS; in_props = 1; props_done = 1; next }
      if ($0 ~ /^[[:space:]]*<build>/) has_build = 1
      if ($0 ~ /^[[:space:]]*<reporting>/) has_reporting = 1
      if ($0 ~ /^[[:space:]]*<\/project>/) {
        if (PROPS && !props_done) warns = warns "pom 无 <properties>，未注入 properties；"
        if (BUILD) {
          if (has_build) warns = warns "pom 已有 <build>，跳过 build 注入（手动合并）；"
          else print BUILD
        }
        if (REPORTING) {
          if (has_reporting) warns = warns "pom 已有 <reporting>，跳过注入（手动合并）；"
          else print REPORTING
        }
        print
        next
      }
      print
    }
    END { if (warns != "") print "[pangu merge] " warns > "/dev/stderr" }
  ' "$pom" > "$tmp" || { warn "awk 合并失败，保留原 pom + snippet 手动合并"; rm -f "$tmp"; return 0; }

  # xmllint 校验 well-formed（仅装了才校验；未装则 warn 但仍应用——awk 已确定性测试）
  if command -v xmllint >/dev/null 2>&1; then
    if ! xmllint --noout "$tmp" 2>/dev/null; then
      warn "合并后 pom.xml 非 well-formed XML（见 $tmp），保留原 pom + snippet 手动合并"
      rm -f "$tmp"
      return 0
    fi
  else
    warn "未装 xmllint，跳过 well-formed 校验（合并已应用，建议装 libxml2 验证）"
  fi

  mv "$tmp" "$pom"
  rm -f "$snippet"
  ok "pom-plugins.snippet.xml 已自动合并到 pom.xml（properties 原位替换 + build/reporting 注入）"
}

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

# 合并质量插件片段（spotless/checkstyle/spotbugs-findsecbugs/jacoco/owasp-depcheck）
# templates/java/pom-plugins.snippet.xml → pom.xml，参照 init-node.sh 的 prettier.snippet.json 合并模式：
# 程序化确定性合并 + xmllint 校验 + 成功后删 snippet；失败则保留 snippet 供手动合并（不破坏生成 pom）。
merge_pom_plugins "$PROJ_DIR/pom.xml" "$PROJ_DIR/pom-plugins.snippet.xml"

git_init
install_hooks
harness_finalize
