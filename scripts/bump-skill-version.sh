#!/usr/bin/env bash
# 通用版本号传播脚本：把 version 字段同步到项目中所有 manifest + README badge。
# 适应不同 skill 仓库的 manifest 组合——不存在的文件静默跳过。
#
# 用法:
#   bump-skill-version.sh <version> [--check] [--proj-dir <dir>]
#   例: bump-skill-version.sh 1.2.3
#       bump-skill-version.sh 1.2.3-rc.1 --check --proj-dir ./my-skill
set -euo pipefail

# 自包含工具函数（不 source _common.sh）——让脚本可独立分发到任意 skill 仓库，
# 且在 PATH 隔离场景（如测试 R-006 用 PATH=/dev/null）能命中 require_cmd python3
# 而非在 source 阶段（dirname 找不到）就退出。
log()  { printf '\033[1;34m[bump]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1（请先安装后再运行本脚本）"; }

usage() {
  cat <<EOF
用法: bump-skill-version.sh <version> [--check] [--proj-dir <dir>]
  <version>          目标版本号 (语义化版本 x.y.z[-pre]，如 1.2.3 / 1.2.3-rc.1)
  --check            dry-run：只打印将修改的清单，不实际改文件
  --proj-dir <dir>   目标项目目录（默认当前目录）
  -h, --help         显示本帮助

更新范围（仅当文件存在时）:
  - skill.json / package.json / .claude-plugin/plugin.json / .codex-plugin/plugin.json / gemini-extension.json
    （顶层 version 字段；无 version 字段则 warn 跳过）
  - .claude-plugin/marketplace.json （plugins[].version 遍历；无 version 字段的 plugin 跳过）
  - README.md 中形如 version-<x.y.z>-<color> 的 shields.io badge
EOF
}

VERSION=""
CHECK=0
PROJ_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check)      CHECK=1; shift ;;
    --proj-dir)   PROJ_DIR="$2"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    --*)          die "未知选项: $1（用 -h 查看帮助）" ;;
    *)            if [ -z "$VERSION" ]; then VERSION="$1"; shift
                  else die "参数过多: $1（version 已设为 $VERSION）"; fi ;;
  esac
done

[ -n "$VERSION" ] || { usage; die "缺少必填参数 <version>"; }

# 用 bash 内置正则避免外部 grep 依赖（让 PATH 隔离场景能命中 require_cmd python3）
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.]+)?$ ]]; then
  die "非法 version: '$VERSION'（需匹配 x.y.z[-pre]，如 1.2.3 / 1.2.3-rc.1）"
fi

[ -n "$PROJ_DIR" ] || PROJ_DIR="$(pwd)"

require_cmd python3

if [ "$CHECK" = "1" ]; then
  log "版本号传播: $VERSION → $PROJ_DIR (dry-run)"
else
  log "版本号传播: $VERSION → $PROJ_DIR"
fi

VERSION="$VERSION" PROJ_DIR="$PROJ_DIR" CHECK="$CHECK" python3 <<'PYEOF'
import json, re, os, sys

VERSION = os.environ['VERSION']
PROJ_DIR = os.environ['PROJ_DIR']
CHECK = os.environ.get('CHECK', '0') == '1'

TOP_LEVEL_MANIFESTS = [
    'skill.json',
    'package.json',
    '.claude-plugin/plugin.json',
    '.codex-plugin/plugin.json',
    'gemini-extension.json',
]
MARKETPLACE = '.claude-plugin/marketplace.json'

updated = 0
skipped = 0
badge_count = 0

def plog(msg):
    print(f'  {msg}')

def pwarn(msg):
    print(f'! {msg}', file=sys.stderr)

def write_json(full, data):
    with open(full, 'w') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write('\n')

def update_top_level(rel):
    global updated, skipped
    full = os.path.join(PROJ_DIR, rel)
    if not os.path.isfile(full):
        return
    try:
        with open(full) as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        pwarn(f'{rel}: JSON 解析失败 {e}，跳过')
        skipped += 1
        return
    if not isinstance(data, dict):
        pwarn(f'{rel}: 顶层不是 JSON 对象，跳过')
        skipped += 1
        return
    if 'version' not in data:
        pwarn(f'{rel}: 无 version 字段，跳过')
        skipped += 1
        return
    old = data['version']
    if old == VERSION:
        plog(f'{rel}: version 已是 {VERSION}，无变化')
        skipped += 1
        return
    action = '将更新' if CHECK else '更新'
    plog(f'{action}: {rel} (version: {old} → {VERSION})')
    if not CHECK:
        data['version'] = VERSION
        write_json(full, data)
    updated += 1

def update_marketplace(rel):
    global updated, skipped
    full = os.path.join(PROJ_DIR, rel)
    if not os.path.isfile(full):
        return
    try:
        with open(full) as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        pwarn(f'{rel}: JSON 解析失败 {e}，跳过')
        skipped += 1
        return
    if not isinstance(data, dict):
        pwarn(f'{rel}: 顶层不是 JSON 对象，跳过')
        skipped += 1
        return
    plugins = data.get('plugins')
    if not isinstance(plugins, list):
        pwarn(f'{rel}: plugins 不是数组，跳过')
        skipped += 1
        return
    changed = False
    for p in plugins:
        if isinstance(p, dict) and 'version' in p:
            old = p['version']
            if old != VERSION:
                action = '将更新' if CHECK else '更新'
                plog(f'{action}: {rel} plugins[].version ({old} → {VERSION})')
                if not CHECK:
                    p['version'] = VERSION
                changed = True
    if changed:
        if not CHECK:
            write_json(full, data)
        updated += 1
    else:
        plog(f'{rel}: 无 plugin version 需更新，跳过')
        skipped += 1

def update_readme_badge(rel):
    global badge_count
    full = os.path.join(PROJ_DIR, rel)
    if not os.path.isfile(full):
        return
    with open(full) as f:
        content = f.read()
    pattern = r'version-[0-9]+\.[0-9]+\.[0-9]+(?:-[a-z0-9.]+)?-'
    new_content, n = re.subn(pattern, f'version-{VERSION}-', content)
    if n > 0:
        action = '将更新' if CHECK else '更新'
        plog(f'{action}: {rel} badge ({n} 处)')
        if not CHECK:
            with open(full, 'w') as f:
                f.write(new_content)
        badge_count += n

for m in TOP_LEVEL_MANIFESTS:
    update_top_level(m)
update_marketplace(MARKETPLACE)
update_readme_badge('README.md')

summary = f'summary: 更新 {updated} 个文件，跳过 {skipped} 个，badge {badge_count} 处'
if CHECK:
    summary += ' (dry-run)'
print(f'\n{summary}')
PYEOF

ok "版本号传播完成"
