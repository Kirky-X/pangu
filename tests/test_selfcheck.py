#!/usr/bin/env python3
"""pangu 自检脚本冒烟（真实跑，不 mock）。

- selfcheck.sh: shellcheck + YAML lint + 模板完整性（工具缺失时脚本自身
  warn 降级，退出码语义不变）;
- test-multi.sh: copy_lang 多语言 prefix 的 bash 版回归（套件内真实执行）。
"""
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))

import _util
from _util import run_script, strip_ansi


class SelfcheckTest(unittest.TestCase):
    def test_selfcheck_passes(self):
        r = run_script("selfcheck.sh")
        self.assertEqual(r.returncode, 0, strip_ansi(r.stdout) + strip_ansi(r.stderr))
        self.assertIn("pangu selfcheck 全部通过", strip_ansi(r.stdout))
        # 三段检查都真实执行（shellcheck/yaml 可能因未装而 warn 降级，完整性必跑）
        self.assertIn("模板完整性检查", strip_ansi(r.stdout))

    def test_selfcheck_yaml_lint_covers_all_template_yaml(self):
        """回归：YAML lint 必须覆盖 templates 下全部 YAML（含点开头文件与深层目录）。

        修复前用 glob `templates/**/*.yml`（未开 globstar 时 ** 退化为单层，
        且 * 不匹配点开头文件），只 lint 27/41 个，漏掉全部 .pre-commit-config.yaml。
        修复后改用 find，lint 数必须与 find 统计一致。
        """
        import subprocess
        r = run_script("selfcheck.sh")
        self.assertEqual(r.returncode, 0, strip_ansi(r.stdout) + strip_ansi(r.stderr))
        out = strip_ansi(r.stdout)
        self.assertIn("YAML lint", out)
        self.assertIn("YAML lint 通过", out)
        expected = subprocess.run(
            ["bash", "-c",
             'find "%s" -type f \\( -name "*.yml" -o -name "*.yaml" \\) | wc -l'
             % _util.TEMPLATES],
            capture_output=True, text=True).stdout.strip()
        self.assertTrue(expected.isdigit() and int(expected) > 0)
        self.assertIn("YAML lint %s 个模板文件" % expected, out)


class TestMultiRegressionTest(unittest.TestCase):
    def test_all_green(self):
        r = run_script("test-multi.sh", cwd=tempfile.gettempdir())
        self.assertEqual(r.returncode, 0, strip_ansi(r.stdout) + strip_ansi(r.stderr))
        self.assertIn("ALL GREEN", strip_ansi(r.stdout))
        self.assertIn("Case 1", strip_ansi(r.stdout))
        self.assertIn("Case 3", strip_ansi(r.stdout))


if __name__ == "__main__":
    unittest.main()
