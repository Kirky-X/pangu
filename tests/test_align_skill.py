#!/usr/bin/env python3
"""align-skill.sh 冒烟测试。

- CLI 冒烟: --help / 缺参 / 目录不存在 / 非 skill 目录 / 未知选项。
- 真实行为: 用 init-skill.sh 生成的标准仓 align --dry-run 全绿（跨脚本
  集成）；残缺仓 dry-run 报缺项退出 1；--fix 补齐缺失文件与 .gitignore
  项且不覆盖已有文件（含非 MIT LICENSE 场景）。
"""
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))

import _util
from _util import PANGU_ROOT, SCRIPTS, read, run_script, strip_ansi, write


class CliSmokeTest(unittest.TestCase):
    def test_help_exits_0(self):
        r = run_script("align-skill.sh", ["-h"])
        self.assertEqual(r.returncode, 0)
        self.assertIn("用法: align-skill.sh", strip_ansi(r.stdout))

    def test_missing_arg_exits_1(self):
        r = run_script("align-skill.sh")
        self.assertEqual(r.returncode, 1)
        self.assertIn("缺少必填参数 <skill-dir>", strip_ansi(r.stderr))

    def test_nonexistent_dir_exits_1(self):
        r = run_script("align-skill.sh", ["/nonexistent/pangu-align"])
        self.assertEqual(r.returncode, 1)
        self.assertIn("目录不存在", strip_ansi(r.stderr))

    def test_dir_without_skillmd_exits_1(self):
        d = tempfile.mkdtemp(prefix="pangu-align-notskill-")
        r = run_script("align-skill.sh", [d])
        self.assertEqual(r.returncode, 1)
        self.assertIn("不含 SKILL.md", strip_ansi(r.stderr))

    def test_unknown_option_and_extra_arg_exits_1(self):
        d = tempfile.mkdtemp(prefix="pangu-align-opt-")
        write(os.path.join(d, "SKILL.md"), "---\nname: x\n---\n")
        r = run_script("align-skill.sh", [d, "--wat"])
        self.assertEqual(r.returncode, 1)
        self.assertIn("未知选项: --wat", strip_ansi(r.stderr))
        r = run_script("align-skill.sh", [d, "extra"])
        self.assertEqual(r.returncode, 1)
        self.assertIn("参数过多", strip_ansi(r.stderr))


class DryRunTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # 跨脚本集成：真实 init-skill.sh 产物 = align 期望的标准仓
        cls.tmp = tempfile.mkdtemp(prefix="pangu-align-std-")
        r = run_script("init-skill.sh", ["std-skill", "--target-dir", cls.tmp + "/std-skill"])
        assert r.returncode == 0, r.stderr
        cls.skill_dir = os.path.join(cls.tmp, "std-skill")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_init_output_is_fully_aligned(self):
        r = run_script("align-skill.sh", [self.skill_dir])
        self.assertEqual(r.returncode, 0, strip_ansi(r.stdout) + strip_ansi(r.stderr))
        # 8 文件 + 8 gitignore 项 + 8 字段 + MIT + 无镜像跳过 = 26 全过
        self.assertIn("✅ 26  ❌ 0", strip_ansi(r.stdout))
        self.assertIn("全绿，退出 0", strip_ansi(r.stdout))

    def test_broken_repo_reports_missing_items_and_exits_1(self):
        d = tempfile.mkdtemp(prefix="pangu-align-broken-")
        write(os.path.join(d, "SKILL.md"), "---\nname: x\n---\n")
        write(os.path.join(d, "LICENSE"), "Apache License\n")  # 非 MIT
        r = run_script("align-skill.sh", [d])
        self.assertEqual(r.returncode, 1)
        out = strip_ansi(r.stdout)
        for missing in ("skill.json （缺失）", "README.md （缺失）", "test-prompts.json （缺失）"):
            self.assertIn(missing, out)
        self.assertIn("LICENSE 非 MIT", out)
        self.assertIn("发现 ❌", strip_ansi(r.stderr))

    def test_gitignore_missing_entry_flagged(self):
        d = tempfile.mkdtemp(prefix="pangu-align-gi-")
        write(os.path.join(d, "SKILL.md"), "---\nname: x\n---\n")
        write(os.path.join(d, ".gitignore"), ".DS_Store\n.vscode\n")
        r = run_script("align-skill.sh", [d])
        self.assertEqual(r.returncode, 1)
        self.assertIn(".meta （.gitignore 未含）", strip_ansi(r.stdout))

    def test_skilljson_missing_field_flagged(self):
        d = tempfile.mkdtemp(prefix="pangu-align-sj-")
        write(os.path.join(d, "SKILL.md"), "---\nname: x\n---\n")
        write(os.path.join(d, ".gitignore"),
              ".DS_Store\n.vscode\n.meta\n.venv\nnode_modules\n__pycache__\n*.log\n.env\n")
        write(os.path.join(d, "skill.json"), json_minimal())
        r = run_script("align-skill.sh", [d])
        self.assertEqual(r.returncode, 1)
        out = strip_ansi(r.stdout)
        self.assertIn("name", out)
        self.assertIn("version （skill.json 未含）", out)


def json_minimal():
    return '{"name": "x"}\n'


class FixModeTest(unittest.TestCase):
    def test_fix_fills_missing_and_never_overwrites_existing(self):
        d = tempfile.mkdtemp(prefix="pangu-align-fix-")
        write(os.path.join(d, "SKILL.md"), "---\nname: keepme\n---\n\noriginal content\n")
        write(os.path.join(d, "LICENSE"), "MIT License\n\npartial\n")  # 已存在 → 不覆盖
        write(os.path.join(d, "README.md"), "my readme\n")
        write(os.path.join(d, ".gitignore"), "# mine\n.claude\n")
        # 模板补齐的 skill.json/gitignore/LICENSE 均达标 → fix 后重新检查全绿
        r = run_script("align-skill.sh", [d, "--fix"])
        self.assertEqual(r.returncode, 0, strip_ansi(r.stdout) + strip_ansi(r.stderr))
        self.assertIn("全绿，退出 0", strip_ansi(r.stdout))
        # 已有文件不被覆盖
        self.assertEqual(read(os.path.join(d, "README.md")), "my readme\n")
        self.assertEqual(read(os.path.join(d, "SKILL.md")),
                         "---\nname: keepme\n---\n\noriginal content\n")  # SKILL.md 显式不修改
        self.assertTrue(read(os.path.join(d, "LICENSE")).startswith("MIT License"))
        # 缺失文件被补齐（来自 templates/skill 渲染）
        for f in ("skill.json", "test-prompts.json", "README_EN.md",
                  ".claude-plugin/marketplace.json", ".github/workflows/release.yml"):
            self.assertTrue(os.path.isfile(os.path.join(d, f)), f)
        self.assertNotIn("{{SKILL_NAME}}", read(os.path.join(d, "skill.json")))
        # .gitignore 缺失项被追加
        gi = read(os.path.join(d, ".gitignore"))
        for pat in (".DS_Store", ".meta", "node_modules", "*.log", ".env"):
            self.assertIn(pat, gi)

    def test_fix_reports_still_failing_when_license_not_mit(self):
        d = tempfile.mkdtemp(prefix="pangu-align-fix3-")
        write(os.path.join(d, "SKILL.md"), "---\nname: x\n---\n")
        write(os.path.join(d, "LICENSE"), "Apache License 2.0\n")  # 已存在且非 MIT → 不覆盖
        r = run_script("align-skill.sh", [d, "--fix"])
        self.assertEqual(r.returncode, 1)
        self.assertIn("仍有 ❌", strip_ansi(r.stderr))
        self.assertIn("LICENSE 非 MIT", strip_ansi(r.stdout))


class OnlyCheckTest(unittest.TestCase):
    """--only 单项触发：只跑所选检查项，并只按该项判退出码。"""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="pangu-align-only-")
        r = run_script("init-skill.sh", ["only-skill", "--target-dir", cls.tmp + "/only-skill"])
        assert r.returncode == 0, r.stderr
        cls.skill_dir = os.path.join(cls.tmp, "only-skill")
        r = run_script("gen-distribution.sh", [cls.skill_dir])
        assert r.returncode == 0, r.stderr
        cls.mirror_md = os.path.join(cls.skill_dir, ".trae", "skills", "only-skill", "SKILL.md")
        cls.mirror_md_orig = read(cls.mirror_md)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_only_mirror_consistent_exits_0(self):
        r = run_script("align-skill.sh", [self.skill_dir, "--only", "mirror"])
        self.assertEqual(r.returncode, 0, strip_ansi(r.stdout) + strip_ansi(r.stderr))
        out = strip_ansi(r.stdout)
        self.assertIn("单项: mirror", out)
        self.assertIn("与主源一致", out)
        self.assertIn("✅ 1  ❌ 0", out)

    def test_only_mirror_drift_exits_1(self):
        with open(self.mirror_md, "a", encoding="utf-8") as f:
            f.write("\ndrift\n")
        try:
            r = run_script("align-skill.sh", [self.skill_dir, "--only", "mirror"])
            self.assertEqual(r.returncode, 1)
            self.assertIn("与主源不一致", strip_ansi(r.stdout))
            self.assertIn("单项检查未通过: mirror", strip_ansi(r.stderr))
        finally:
            write(self.mirror_md, self.mirror_md_orig)

    def test_only_numeric_alias_works(self):
        r = run_script("align-skill.sh", [self.skill_dir, "--only", "5"])
        self.assertEqual(r.returncode, 0, strip_ansi(r.stdout) + strip_ansi(r.stderr))
        self.assertIn("单项: mirror", strip_ansi(r.stdout))

    def test_only_other_item_ignores_mirror_drift(self):
        with open(self.mirror_md, "a", encoding="utf-8") as f:
            f.write("\ndrift\n")
        try:
            r = run_script("align-skill.sh", [self.skill_dir, "--only", "license"])
            self.assertEqual(r.returncode, 0, strip_ansi(r.stdout) + strip_ansi(r.stderr))
            self.assertNotIn("与主源不一致", strip_ansi(r.stdout))
        finally:
            write(self.mirror_md, self.mirror_md_orig)

    def test_only_unknown_item_exits_1(self):
        r = run_script("align-skill.sh", [self.skill_dir, "--only", "bogus"])
        self.assertEqual(r.returncode, 1)
        self.assertIn("未知检查项: bogus", strip_ansi(r.stderr))

    def test_only_missing_value_exits_1(self):
        r = run_script("align-skill.sh", [self.skill_dir, "--only"])
        self.assertEqual(r.returncode, 1)
        self.assertIn("--only 缺少检查项", strip_ansi(r.stderr))

    def test_help_lists_only_items(self):
        r = run_script("align-skill.sh", ["-h"])
        self.assertEqual(r.returncode, 0)
        out = strip_ansi(r.stdout)
        self.assertIn("--only", out)
        self.assertIn("mirror(5)", out)


if __name__ == "__main__":
    unittest.main()
