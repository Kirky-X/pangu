#!/usr/bin/env python3
"""pangu scripts 冒烟测试公共工具。

约定（仿 dayv/tests）:
- 全部离线可跑：外部/网络调用（语言包管理器 add、git pull 等）用 PATH 前置的
  mock 命令挡掉；git init/add 等本地操作真实执行。
- 一切副作用只发生在临时目录，不触碰仓库本体、~/.zcode 与 specmark/。
"""
import os
import re
import shutil
import stat
import subprocess
import tempfile

PANGU_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(PANGU_ROOT, "scripts")
TEMPLATES = os.path.join(PANGU_ROOT, "templates")

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")


def strip_ansi(text):
    """去掉终端颜色转义，便于断言纯文本。"""
    return ANSI_RE.sub("", text)


def run_script(script, args=(), cwd=None, mock_dir=None, env_extra=None, timeout=180):
    """运行 scripts/<script>，返回 CompletedProcess（capture 输出）。"""
    env = dict(os.environ)
    if mock_dir:
        env["PATH"] = mock_dir + os.pathsep + env.get("PATH", "")
    if env_extra:
        env.update(env_extra)
    return subprocess.run(
        ["bash", os.path.join(SCRIPTS, script), *args],
        cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout,
    )


def run_bash(body, cwd=None, mock_dir=None, env_extra=None, timeout=120):
    """跑一段 bash 测试体（通常 source _common.sh 后调用库函数）。"""
    env = dict(os.environ)
    if mock_dir:
        env["PATH"] = mock_dir + os.pathsep + env.get("PATH", "")
    if env_extra:
        env.update(env_extra)
    return subprocess.run(
        ["bash", "-c", body], cwd=cwd, env=env,
        capture_output=True, text=True, timeout=timeout,
    )


def make_mock_bin(spec):
    """生成 mock 命令目录。spec: {命令名: bash 函数体}，函数体可读 "$@"。返回目录路径。

    该目录将以 PATH 前置方式注入，使被测脚本命中 mock 而非真实工具链
    （真实工具链的 add/require 等子命令需要网络，违反离线约束）。
    """
    d = tempfile.mkdtemp(prefix="pangu-mock-bin-")
    for name, body in spec.items():
        p = os.path.join(d, name)
        with open(p, "w", encoding="utf-8") as f:
            f.write("#!/usr/bin/env bash\n%s\n" % body)
        os.chmod(p, os.stat(p).st_mode | stat.S_IEXEC)
    return d


def make_fake_skill_root(langs=("rust", "python", "node", "go")):
    """构造隔离的 fake skill root：scripts/_common.sh + templates/{common,<langs>}。

    copy_lang/copy_common 的源是 $SKILL_DIR/templates/<lang>，用 fake root
    测库函数可自由注入 .bak 等畸形文件，不污染真仓 templates/。
    """
    root = tempfile.mkdtemp(prefix="pangu-fake-skill-")
    os.makedirs(os.path.join(root, "scripts"))
    shutil.copy(os.path.join(SCRIPTS, "_common.sh"),
                os.path.join(root, "scripts", "_common.sh"))
    tpl = os.path.join(root, "templates")
    os.makedirs(tpl)
    shutil.copytree(os.path.join(TEMPLATES, "common"), os.path.join(tpl, "common"))
    for lang in langs:
        shutil.copytree(os.path.join(TEMPLATES, lang), os.path.join(tpl, lang))
    return root


def source_common(fake_root, body):
    """在 fake skill root 下 source _common.sh 后执行测试体。"""
    return run_bash(
        'set -uo pipefail\nsource "%s"\n%s\n'
        % (os.path.join(fake_root, "scripts", "_common.sh"), body),
    )


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
