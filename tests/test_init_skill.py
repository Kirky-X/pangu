#!/usr/bin/env python3
"""init-skill.sh 冒烟测试。

- CLI 冒烟: --help / 缺参 / 非法 skill-name（大写、下划线、连字符位置）/
  未知选项 / 参数过多 / 目标目录非空。
- 真实行为: 完整初始化到临时目录——模板渲染无占位符残留、9 文件齐、
  目录结构、git init + 全量 stage（git 本地操作）。
"""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))

import _util
from _util import read, run_script, strip_ansi

EXPECTED_FILES = (
    ".gitignore", "LICENSE", "skill.json", "SKILL.md", "README.md",
    "README_EN.md", "test-prompts.json", ".claude-plugin/marketplace.json",
    ".github/workflows/release.yml",
)


class CliSmokeTest(unittest.TestCase):
    def test_help_exits_0(self):
        r = run_script("init-skill.sh", ["--help"])
        self.assertEqual(r.returncode, 0)
        self.assertIn("用法: init-skill.sh", strip_ansi(r.stdout))

    def test_missing_name_exits_1(self):
        r = run_script("init-skill.sh")
        self.assertEqual(r.returncode, 1)
        self.assertIn("缺少必填参数 <skill-name>", strip_ansi(r.stderr))

    def test_invalid_names_exits_1(self):
        for bad in ("MySkill", "my_skill", "-lead", "trail-", "a b"):
            r = run_script("init-skill.sh", [bad])
            self.assertEqual(r.returncode, 1, bad)
            if bad != "trail-":
                self.assertIn("全小写字母+连字符", strip_ansi(r.stderr), bad)
            else:
                self.assertIn("不能以连字符结尾", strip_ansi(r.stderr), bad)

    def test_unknown_option_exits_1(self):
        r = run_script("init-skill.sh", ["x", "--wat"])
        self.assertEqual(r.returncode, 1)
        self.assertIn("未知选项: --wat", strip_ansi(r.stderr))

    def test_two_positional_args_exits_1(self):
        r = run_script("init-skill.sh", ["one", "two"])
        self.assertEqual(r.returncode, 1)
        self.assertIn("参数过多", strip_ansi(r.stderr))

    def test_nonempty_target_dir_exits_1(self):
        d = tempfile.mkdtemp(prefix="pangu-init-skill-full-")
        _util.write(os.path.join(d, "occupied.txt"), "x")
        r = run_script("init-skill.sh", ["occ", "--target-dir", d])
        self.assertEqual(r.returncode, 1)
        self.assertIn("目标目录已存在且非空", strip_ansi(r.stderr))


class FullInitTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="pangu-init-skill-run-")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def init_std(self, name="my-skill"):
        r = run_script("init-skill.sh", [
            name,
            "--cn-name", "我的技能",
            "--author", "Tester",
            "--description", "测试描述 / with slash & pipe",
            "--target-dir", os.path.join(self.tmp, name),
        ])
        return r, os.path.join(self.tmp, name)

    def test_complete_bootstrap(self):
        r, d = self.init_std()
        self.assertEqual(r.returncode, 0, r.stderr)
        for f in EXPECTED_FILES:
            self.assertTrue(os.path.isfile(os.path.join(d, f)), f)
        for sub in ("references", "scripts", "specmark/changes", "specmark/specs",
                    ".claude/skills/gitnexus"):
            self.assertTrue(os.path.isdir(os.path.join(d, sub)), sub)

    def test_rendering_replaces_all_placeholders(self):
        r, d = self.init_std()
        self.assertEqual(r.returncode, 0, r.stderr)
        import json
        skill_json = json.loads(read(os.path.join(d, "skill.json")))
        self.assertEqual(skill_json["name"], "my-skill")
        self.assertEqual(skill_json["author"], "Tester")
        for name in os.listdir(d):
            p = os.path.join(d, name)
            if os.path.isfile(p) and p.endswith((".md", ".json")):
                self.assertNotIn("{{SKILL_NAME}}", read(p), name)
        self.assertIn("我的技能", read(os.path.join(d, "SKILL.md")))
        self.assertIn("测试描述 / with slash & pipe", read(os.path.join(d, "README.md")))

    def test_git_repo_initialized_and_staged(self):
        r, d = self.init_std()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(os.path.isdir(os.path.join(d, ".git")))
        out = subprocess.run(["git", "-C", d, "ls-files"],
                             capture_output=True, text=True).stdout
        self.assertIn("SKILL.md", out)
        self.assertIn("skill.json", out)
        # 未自动 commit（留给用户）
        log = subprocess.run(["git", "-C", d, "log", "--oneline"],
                             capture_output=True, text=True)
        self.assertNotEqual(log.returncode, 0)  # 无提交 → log 失败

    def test_default_target_dir_is_dot_slash_name(self):
        r = run_script("init-skill.sh", ["rel-skill"], cwd=self.tmp)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(os.path.isfile(
            os.path.join(self.tmp, "rel-skill", "SKILL.md")))

    def test_reinit_nonempty_target_exits_1(self):
        r, d = self.init_std()
        self.assertEqual(r.returncode, 0)
        r = run_script("init-skill.sh", ["my-skill", "--target-dir", d])
        self.assertEqual(r.returncode, 1)
        self.assertIn("目标目录已存在且非空", strip_ansi(r.stderr))

    def test_cn_name_defaults_to_skill_name(self):
        r = run_script("init-skill.sh", ["cn-def", "--target-dir",
                                         os.path.join(self.tmp, "cn-def")])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("cn-def", read(os.path.join(self.tmp, "cn-def", "SKILL.md")))


if __name__ == "__main__":
    unittest.main()
