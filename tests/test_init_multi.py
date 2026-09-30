#!/usr/bin/env python3
"""init-multi.sh 冒烟测试。

- 纯参数校验 die 路径（无工具链依赖，真实跑）;
- rust,python 双语言完整流程（stub cargo/uv 挡网络依赖），验证主语言基底
  + 次语言 prefix 片段 + gitignore 分段 + 子目录脚手架。
"""
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))

from test_init_lang import MOCK_UV
from _util import make_mock_bin, read, run_script, strip_ansi

MOCK_MULTI = {
    "cargo": ('if [ "$1" = init ]; then '
              'printf "[package]\\nname = \\"stub\\"\\n" > Cargo.toml; fi; exit 0'),
    **MOCK_UV,
}


class ArgValidationTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="pangu-init-multi-arg-")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def test_missing_langs_exits_1(self):
        r = run_script("init-multi.sh", cwd=self.tmp)
        self.assertEqual(r.returncode, 1)
        self.assertIn("用法: init-multi.sh", strip_ansi(r.stderr))

    def test_single_lang_exits_1(self):
        r = run_script("init-multi.sh", ["rust"], cwd=self.tmp)
        self.assertEqual(r.returncode, 1)
        self.assertIn("至少需 2 种语言", strip_ansi(r.stderr))

    def test_unknown_lang_exits_1(self):
        r = run_script("init-multi.sh", ["rust,fortran"], cwd=self.tmp)
        self.assertEqual(r.returncode, 1)
        self.assertIn("语言 'fortran' 未知", strip_ansi(r.stderr))

    def test_duplicate_lang_exits_1(self):
        r = run_script("init-multi.sh", ["rust,rust"], cwd=self.tmp)
        self.assertEqual(r.returncode, 1)
        self.assertIn("重复", strip_ansi(r.stderr))
        self.assertIn("rust", strip_ansi(r.stderr))


class FullMultiTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="pangu-init-multi-run-")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def test_rust_python_monorepo(self):
        mock_dir = make_mock_bin(MOCK_MULTI)
        self.addCleanup(shutil.rmtree, mock_dir, ignore_errors=True)
        r = run_script("init-multi.sh", ["rust,python", "mono"], cwd=self.tmp,
                       mock_dir=mock_dir)
        self.assertEqual(r.returncode, 0, r.stderr)
        root = os.path.join(self.tmp, "mono")
        # 各语言子目录脚手架
        self.assertTrue(os.path.isfile(os.path.join(root, "rust", "Cargo.toml")))
        self.assertTrue(os.path.isfile(os.path.join(root, "python", "pyproject.toml")))
        # 主语言基底（无前缀）
        wf = os.path.join(root, ".github", "workflows")
        for f in ("ci.yml", "release.yml"):
            self.assertTrue(os.path.isfile(os.path.join(wf, f)), f)
        self.assertTrue(os.path.isfile(os.path.join(root, "lefthook.yml")))
        self.assertTrue(os.path.isfile(os.path.join(root, ".pre-commit-config.yaml")))
        # 次语言 prefix 片段
        for f in ("python-ci.yml", "python-release.yml"):
            self.assertTrue(os.path.isfile(os.path.join(wf, f)), f)
        self.assertTrue(os.path.isfile(os.path.join(root, "python-lefthook.yml")))
        self.assertTrue(os.path.isfile(os.path.join(root, "python-.pre-commit-config.yaml")))
        # 次语言非冲突 snippet 原样留在根，setup_lang_deps warn 提示手动合并
        self.assertTrue(os.path.isfile(os.path.join(root, "pyproject-tooling.toml")))
        self.assertIn("pyproject-tooling.toml 的 [tool.*] 段合并", strip_ansi(r.stderr))
        # gitignore 分段合并
        gi = read(os.path.join(root, ".gitignore"))
        self.assertIn("# --- python ---", gi)
        # 共享 git 仓 + 收尾输出
        self.assertTrue(os.path.isdir(os.path.join(root, ".git")))
        out = strip_ansi(r.stdout)
        self.assertIn("多语言 harness 初始化完成", out)
        self.assertIn("rust,python", out)
        self.assertIn("python-lefthook.yml", out)  # 待合并片段清单

    def test_lang_order_main_first(self):
        mock_dir = make_mock_bin(MOCK_MULTI)
        self.addCleanup(shutil.rmtree, mock_dir, ignore_errors=True)
        r = run_script("init-multi.sh", ["python,rust"], cwd=self.tmp,
                       mock_dir=mock_dir)
        self.assertEqual(r.returncode, 0, r.stderr)
        # 主语言 python: 基底用 python 模板；rust 为次语言（rust-ci.yml 片段）
        self.assertTrue(os.path.isfile(os.path.join(self.tmp, "python", "pyproject.toml")))
        self.assertTrue(os.path.isfile(os.path.join(self.tmp, "rust", "Cargo.toml")))
        wf = os.path.join(self.tmp, ".github", "workflows")
        self.assertTrue(os.path.isfile(os.path.join(wf, "ci.yml")))
        self.assertTrue(os.path.isfile(os.path.join(wf, "rust-ci.yml")))
        out = strip_ansi(r.stdout)
        self.assertIn("主语言: python", out)
        self.assertIn("次语言: rust", out)


if __name__ == "__main__":
    unittest.main()
