#!/usr/bin/env python3
"""install-skill.sh 冒烟测试。

install/uninstall/status/list-skills/list-agents/generate-commands 均为纯
文件操作，真实离线执行（安装目标与脚本副本都放临时目录）。
update 子命令的 git pull 路径需网络且含 reset --hard，不测（见 SKIPPED.md）；
其非 git 仓 warn 分支在 fake root 覆盖。
"""
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))

import _util
from _util import PANGU_ROOT, SCRIPTS, read, run_bash, strip_ansi, write


def run_install(args, cwd=None, script_path=None):
    """运行 install-skill.sh。script_path 为空 = 原位（pangu 独立仓库模式）。"""
    path = script_path or os.path.join(SCRIPTS, "install-skill.sh")
    import subprocess
    env = dict(os.environ)
    return subprocess.run(["bash", path, *args], cwd=cwd, env=env,
                          capture_output=True, text=True, timeout=180)


def make_multi_skill_root():
    """多 skill 父目录模式：脚本副本 + 两个最小 fake skill。"""
    root = tempfile.mkdtemp(prefix="pangu-multi-skill-")
    os.makedirs(os.path.join(root, "scripts"))
    shutil.copy(os.path.join(SCRIPTS, "install-skill.sh"),
                os.path.join(root, "scripts", "install-skill.sh"))
    for name, desc in (("skill-a", "first test skill"), ("skill-b", "second test skill")):
        d = os.path.join(root, name)
        os.makedirs(d)
        write(os.path.join(d, "SKILL.md"),
              "---\nname: %s\ndescription: \"%s\"\n---\n\n# %s\n" % (name, desc, name))
        write(os.path.join(d, "body.txt"), "payload of " + name)
    return root


class CliSmokeTest(unittest.TestCase):
    def test_help_exits_0_with_usage(self):
        for flag in ("-h", "--help"):
            r = run_install([flag])
            self.assertEqual(r.returncode, 0, flag)
            self.assertIn("Usage: install-skill.sh", strip_ansi(r.stdout))

    def test_no_args_exits_1(self):
        r = run_install([])
        self.assertEqual(r.returncode, 1)
        self.assertIn("Usage:", strip_ansi(r.stdout))

    def test_unknown_command_exits_1(self):
        r = run_install(["frobnicate"])
        self.assertEqual(r.returncode, 1)
        self.assertIn("未知命令: frobnicate", strip_ansi(r.stderr))

    def test_list_agents_lists_all_nine(self):
        r = run_install(["list-agents"])
        self.assertEqual(r.returncode, 0)
        for agent in ("claude", "cursor", "windsurf", "trae", "gemini",
                      "copilot", "opencode", "roocode", "qoder"):
            self.assertIn(agent, strip_ansi(r.stdout))
        self.assertIn(".claude/skills/<skill>/", strip_ansi(r.stdout))


class StandaloneModeTest(unittest.TestCase):
    """原位运行（PROJECT_ROOT=pangu，独立 skill 仓库模式）。"""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="pangu-install-standalone-")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_01_install_to_target_creates_skill_copy(self):
        target = os.path.join(self.tmp, "proj1")
        r = run_install(["install", "pangu", "--target", target])
        self.assertEqual(r.returncode, 0, r.stderr)
        dest = os.path.join(target, ".claude", "skills", "pangu")
        self.assertTrue(os.path.isfile(os.path.join(dest, "SKILL.md")))
        self.assertTrue(os.path.isfile(os.path.join(dest, "skill.json")))
        # 排除项不拷贝
        self.assertFalse(os.path.exists(os.path.join(dest, ".git")))
        # specmark/ 运行时产物 changes 被清理（specmark 本体保留）
        self.assertFalse(os.path.exists(os.path.join(dest, "specmark", "changes")))
        self.assertIn("OK", strip_ansi(r.stdout))

    def test_02_install_single_agent_cursor_layout(self):
        target = os.path.join(self.tmp, "proj2")
        r = run_install(["install", "pangu", "--target", target, "--agent", "cursor"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(os.path.isfile(os.path.join(target, ".cursor", "rules", "pangu", "SKILL.md")))
        self.assertFalse(os.path.exists(os.path.join(target, ".claude")))

    def test_03_install_unknown_agent_exits_1(self):
        r = run_install(["install", "pangu", "--agent", "nope",
                         "--target", os.path.join(self.tmp, "proj3")])
        self.assertEqual(r.returncode, 1)
        self.assertIn("不支持的 agent 类型: nope", strip_ansi(r.stderr))

    def test_04_install_unknown_skill_exits_1(self):
        r = run_install(["install", "no-such-skill", "--target", os.path.join(self.tmp, "proj3")])
        self.assertEqual(r.returncode, 1)
        self.assertIn("skill 源目录不存在", strip_ansi(r.stderr))

    def test_05_install_requires_skill_name(self):
        r = run_install(["install"])
        self.assertEqual(r.returncode, 1)
        self.assertIn("install 需要 <skill-name>", strip_ansi(r.stderr))

    def test_06_uninstall_removes_then_reports_absent(self):
        target = os.path.join(self.tmp, "proj1")  # test_01 已安装
        r = run_install(["uninstall", "pangu", "--target", target])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("REMOVED", strip_ansi(r.stdout))
        self.assertFalse(os.path.exists(os.path.join(target, ".claude", "skills", "pangu")))
        r = run_install(["uninstall", "pangu", "--target", target])
        self.assertEqual(r.returncode, 0)
        self.assertIn("ABSENT", strip_ansi(r.stdout))

    def test_07_uninstall_requires_existing_target(self):
        r = run_install(["uninstall", "pangu", "--target", os.path.join(self.tmp, "nope")])
        self.assertEqual(r.returncode, 1)
        self.assertIn("目标目录不存在", strip_ansi(r.stderr))

    def test_08_status_reports_installed_skill(self):
        target = os.path.join(self.tmp, "proj2")  # test_02 已装 cursor
        r = run_install(["status", "--target", target])
        self.assertEqual(r.returncode, 0)
        self.assertIn("cursor", strip_ansi(r.stdout))
        self.assertIn("pangu", strip_ansi(r.stdout))
        empty = os.path.join(self.tmp, "empty")
        os.makedirs(empty, exist_ok=True)
        r = run_install(["status", "--target", empty])
        self.assertEqual(r.returncode, 0)
        self.assertIn("未在", strip_ansi(r.stderr))

    def test_09_list_skills_standalone_shows_pangu(self):
        r = run_install(["list-skills"])
        self.assertEqual(r.returncode, 0)
        self.assertIn("pangu", strip_ansi(r.stdout))

    def test_10_generate_commands_explicit_list(self):
        target = os.path.join(self.tmp, "proj-cmds")
        r = run_install(["generate-commands", "pangu", "--commands", "init,review",
                         "--target", target])
        self.assertEqual(r.returncode, 0, r.stderr)
        cmddir = os.path.join(target, ".claude", "commands")
        for sub in ("init", "review"):
            f = os.path.join(cmddir, "pangu-%s.md" % sub)
            self.assertTrue(os.path.isfile(f), f)
            self.assertIn("description:", read(f))
            self.assertIn(sub, read(f))
        self.assertIn("(2 cmds)", strip_ansi(r.stdout))

    def test_11_generate_commands_no_subcommands_exits_1(self):
        # pangu/SKILL.md 无 argument-hint、无子命令表格，且未给 --commands
        r = run_install(["generate-commands", "pangu",
                         "--target", os.path.join(self.tmp, "proj-cmds2")])
        self.assertEqual(r.returncode, 1)
        self.assertIn("未能从 SKILL.md 提取子命令", strip_ansi(r.stderr))

    def test_12_install_unknown_option_exits_1(self):
        r = run_install(["install", "pangu", "--bogus"])
        self.assertEqual(r.returncode, 1)
        self.assertIn("未知参数: --bogus", strip_ansi(r.stderr))


class MultiSkillModeTest(unittest.TestCase):
    """脚本副本放入多 skill 父目录（fake root），验证扫描/安装/状态。"""

    @classmethod
    def setUpClass(cls):
        cls.root = make_multi_skill_root()
        cls.script = os.path.join(cls.root, "scripts", "install-skill.sh")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.root, ignore_errors=True)

    def run_in_root(self, args):
        return run_install(args, script_path=self.script)

    def test_list_skills_scans_siblings(self):
        r = self.run_in_root(["list-skills"])
        self.assertEqual(r.returncode, 0)
        out = strip_ansi(r.stdout)
        self.assertIn("skill-a", out)
        self.assertIn("skill-b", out)
        self.assertIn("first test skill", out)

    def test_install_and_status_roundtrip(self):
        target = os.path.join(self.root, "target")
        r = self.run_in_root(["install", "skill-a", "--target", target])
        self.assertEqual(r.returncode, 0, r.stderr)
        dest = os.path.join(target, ".claude", "skills", "skill-a")
        self.assertTrue(os.path.isfile(os.path.join(dest, "SKILL.md")))
        self.assertEqual(read(os.path.join(dest, "body.txt")), "payload of skill-a")
        r = self.run_in_root(["status", "--target", target])
        self.assertEqual(r.returncode, 0)
        self.assertIn("skill-a", strip_ansi(r.stdout))

    def test_update_without_git_warns_and_reinstalls_offline(self):
        target = os.path.join(self.root, "target")  # test_install_and_status 已装
        r = self.run_in_root(["update", "skill-a", "--target", target])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("非 git 仓库，跳过拉取", strip_ansi(r.stderr))
        self.assertIn("UPDATED", strip_ansi(r.stdout))
        # 重装后文件仍在
        self.assertTrue(os.path.isfile(
            os.path.join(target, ".claude", "skills", "skill-a", "SKILL.md")))

    def test_generate_commands_from_table_rows(self):
        # SKILL.md 用 markdown 表格列子命令（策略 2 提取路径）
        d = os.path.join(self.root, "skill-c")
        os.makedirs(d, exist_ok=True)
        write(os.path.join(d, "SKILL.md"),
              "---\nname: skill-c\ndescription: \"cmd table\"\n---\n\n"
              "| 命令 | 说明 |\n|---|---|\n"
              "| `search` | 搜索 |\n| `write` | 写作 |\n")
        target = os.path.join(self.root, "target-c")
        r = self.run_in_root(["generate-commands", "skill-c", "--target", target])
        self.assertEqual(r.returncode, 0, r.stderr)
        f = os.path.join(target, ".claude", "commands", "skill-c-search.md")
        self.assertTrue(os.path.isfile(f))
        self.assertIn("搜索", read(f))  # 描述来自表格第 3 列

    def test_install_copies_only_named_skill(self):
        target = os.path.join(self.root, "target-iso")
        r = self.run_in_root(["install", "skill-b", "--target", target])
        self.assertEqual(r.returncode, 0)
        self.assertTrue(os.path.isfile(
            os.path.join(target, ".claude", "skills", "skill-b", "SKILL.md")))
        self.assertFalse(os.path.exists(
            os.path.join(target, ".claude", "skills", "skill-a")))


if __name__ == "__main__":
    unittest.main()
