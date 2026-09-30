#!/usr/bin/env python3
"""bump-skill-version.sh 冒烟测试（① 纯文件操作，完全离线）。

覆盖: 版本校验、--check dry-run 不落盘、manifest/marketplace/badge 全链
传播、无 version 字段与坏 JSON 的显性跳过。
"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))

import _util
from _util import run_script, strip_ansi, write


def mkproj():
    return tempfile.mkdtemp(prefix="pangu-bump-")


class ArgValidationTest(unittest.TestCase):
    def test_help_exits_0(self):
        r = run_script("bump-skill-version.sh", ["-h"])
        self.assertEqual(r.returncode, 0)
        self.assertIn("用法: bump-skill-version.sh", strip_ansi(r.stdout))

    def test_missing_version_exits_1(self):
        r = run_script("bump-skill-version.sh")
        self.assertEqual(r.returncode, 1)
        self.assertIn("缺少必填参数 <version>", strip_ansi(r.stderr))

    def test_invalid_versions_exits_1(self):
        for bad in ("abc", "1.2", "1", "1.2.3.4", "v1.2.3"):
            r = run_script("bump-skill-version.sh", [bad, "--proj-dir", mkproj()])
            self.assertEqual(r.returncode, 1, bad)
            self.assertIn("非法 version", strip_ansi(r.stderr), bad)

    def test_unknown_option_and_too_many_args_exits_1(self):
        r = run_script("bump-skill-version.sh", ["1.2.3", "--wat"])
        self.assertEqual(r.returncode, 1)
        self.assertIn("未知选项: --wat", strip_ansi(r.stderr))
        r = run_script("bump-skill-version.sh", ["1.2.3", "3.4.5"])
        self.assertEqual(r.returncode, 1)
        self.assertIn("参数过多", strip_ansi(r.stderr))


class CheckModeTest(unittest.TestCase):
    def test_dry_run_reports_without_touching_files(self):
        d = mkproj()
        write(os.path.join(d, "skill.json"), json.dumps({"name": "x", "version": "0.1.0"}))
        write(os.path.join(d, "README.md"), "badge version-0.1.0-blue\n")
        r = run_script("bump-skill-version.sh", ["0.2.0", "--check", "--proj-dir", d])
        self.assertEqual(r.returncode, 0, r.stderr)
        out = strip_ansi(r.stdout)
        self.assertIn("将更新: skill.json (version: 0.1.0 → 0.2.0)", out)
        self.assertIn("将更新: README.md badge (1 处)", out)
        self.assertIn("summary: 更新 1 个文件，跳过 0 个，badge 1 处 (dry-run)", out)
        self.assertIn('"version": "0.1.0"', _util.read(os.path.join(d, "skill.json")))
        self.assertIn("version-0.1.0-blue", _util.read(os.path.join(d, "README.md")))


class PropagateTest(unittest.TestCase):
    def mkfull(self):
        d = mkproj()
        write(os.path.join(d, "skill.json"), json.dumps({"name": "x", "version": "0.1.0"}))
        write(os.path.join(d, "package.json"), json.dumps({"version": "0.1.0", "name": "x"}))
        write(os.path.join(d, ".claude-plugin", "plugin.json"),
              json.dumps({"version": "0.1.0"}))
        write(os.path.join(d, ".codex-plugin", "plugin.json"),
              json.dumps({"version": "0.1.0"}))
        write(os.path.join(d, "gemini-extension.json"), json.dumps({"version": "0.1.0"}))
        write(os.path.join(d, ".claude-plugin", "marketplace.json"), json.dumps({
            "plugins": [{"name": "a", "version": "0.1.0"},
                        {"name": "b", "description": "no version"}]}))
        write(os.path.join(d, "README.md"),
              "![v](https://img.shields.io/badge/version-0.1.0-green) "
              "and version-0.1.0-blue\n")
        return d

    def test_full_propagation(self):
        d = self.mkfull()
        r = run_script("bump-skill-version.sh", ["1.2.3", "--proj-dir", d])
        self.assertEqual(r.returncode, 0, r.stderr)
        out = strip_ansi(r.stdout)
        for rel in ("skill.json", "package.json", ".claude-plugin/plugin.json",
                    ".codex-plugin/plugin.json", "gemini-extension.json"):
            self.assertEqual(json.loads(_util.read(os.path.join(d, rel)))["version"], "1.2.3", rel)
        mp = json.loads(_util.read(os.path.join(d, ".claude-plugin", "marketplace.json")))
        self.assertEqual(mp["plugins"][0]["version"], "1.2.3")
        self.assertNotIn("version", mp["plugins"][1])  # 无 version 字段的 plugin 不动
        self.assertEqual(_util.read(os.path.join(d, "README.md")).count("version-1.2.3-"), 2)
        self.assertIn("更新 6 个文件，跳过 0 个，badge 2 处", out)

    def test_pre_release_version_allowed(self):
        d = mkproj()
        write(os.path.join(d, "skill.json"), json.dumps({"version": "0.1.0"}))
        r = run_script("bump-skill-version.sh", ["1.2.3-rc.1", "--proj-dir", d])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(_util.read(os.path.join(d, "skill.json")))["version"],
                         "1.2.3-rc.1")

    def test_same_version_counts_as_skipped(self):
        d = mkproj()
        write(os.path.join(d, "skill.json"), json.dumps({"version": "1.2.3"}))
        r = run_script("bump-skill-version.sh", ["1.2.3", "--proj-dir", d])
        self.assertEqual(r.returncode, 0)
        self.assertIn("version 已是 1.2.3，无变化", strip_ansi(r.stdout))
        self.assertIn("跳过 1 个", strip_ansi(r.stdout))

    def test_manifest_without_version_field_skips_explicitly(self):
        d = mkproj()
        write(os.path.join(d, "skill.json"), json.dumps({"name": "x"}))
        r = run_script("bump-skill-version.sh", ["1.2.3", "--proj-dir", d])
        self.assertEqual(r.returncode, 0)
        self.assertIn("无 version 字段，跳过", strip_ansi(r.stderr))
        self.assertIn("跳过 1 个", strip_ansi(r.stdout))

    def test_broken_json_warns_and_continues(self):
        d = mkproj()
        write(os.path.join(d, "skill.json"), "{not json")
        write(os.path.join(d, "package.json"), json.dumps({"version": "0.1.0"}))
        r = run_script("bump-skill-version.sh", ["1.2.3", "--proj-dir", d])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("JSON 解析失败", strip_ansi(r.stderr))
        self.assertEqual(json.loads(_util.read(os.path.join(d, "package.json")))["version"],
                         "1.2.3")

    def test_non_object_json_skips(self):
        d = mkproj()
        write(os.path.join(d, "skill.json"), "[1, 2]")
        r = run_script("bump-skill-version.sh", ["1.2.3", "--proj-dir", d])
        self.assertEqual(r.returncode, 0)
        self.assertIn("顶层不是 JSON 对象，跳过", strip_ansi(r.stderr))

    def test_marketplace_non_array_plugins_skips(self):
        d = mkproj()
        write(os.path.join(d, ".claude-plugin", "marketplace.json"),
              json.dumps({"plugins": "oops"}))
        r = run_script("bump-skill-version.sh", ["1.2.3", "--proj-dir", d])
        self.assertEqual(r.returncode, 0)
        self.assertIn("plugins 不是数组，跳过", strip_ansi(r.stderr))

    def test_absent_files_are_silently_ignored(self):
        d = mkproj()  # 空目录
        r = run_script("bump-skill-version.sh", ["1.2.3", "--proj-dir", d])
        self.assertEqual(r.returncode, 0)
        self.assertIn("更新 0 个文件", strip_ansi(r.stdout))


if __name__ == "__main__":
    unittest.main()
