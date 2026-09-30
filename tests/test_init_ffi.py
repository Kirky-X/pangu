#!/usr/bin/env python3
"""FFI 脚手架（init-rust-napi.sh / init-rust-pyo3.sh / apply_ffi_harness）冒烟测试。

半自动设计：官方工具（napi new / maturin new）管骨架 → 本脚本叠加 harness。
die 路径真实跑；就位路径预置官方产物（Cargo.toml + 绑定 manifest）后
harness 叠加为纯文件操作，真实执行。
"""
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))

import _util
from _util import make_fake_skill_root, read, run_bash, run_script, source_common, strip_ansi, write

CARGO_TOML = '[package]\nname = "demo"\nversion = "0.1.0"\n'
PYPROJECT = '[project]\nname = "demo"\n\n[tool.maturin]\nmodule-name = "demo"\n'
PACKAGE_JSON = '{\n  "name": "demo",\n  "napi": {"binaryName": "demo"}\n}\n'


class FfiDiePathTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="pangu-ffi-die-")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def test_pyo3_without_scaffold_dies(self):
        r = run_script("init-rust-pyo3.sh", cwd=self.tmp)
        self.assertEqual(r.returncode, 1)
        err = strip_ansi(r.stderr)
        self.assertIn("未检测到 python FFI 脚手架产物", err)
        self.assertIn("maturin new --mixed --bindings pyo3", err)

    def test_napi_without_scaffold_dies(self):
        r = run_script("init-rust-napi.sh", cwd=self.tmp)
        self.assertEqual(r.returncode, 1)
        self.assertIn("未检测到 node FFI 脚手架产物", strip_ansi(r.stderr))

    def test_pyo3_missing_cargo_but_has_pyproject_dies(self):
        write(os.path.join(self.tmp, "pyproject.toml"), PYPROJECT)
        r = run_script("init-rust-pyo3.sh", cwd=self.tmp)
        self.assertEqual(r.returncode, 1)
        self.assertIn("未检测到", strip_ansi(r.stderr))

    def test_missing_dir_argument_dies(self):
        r = run_script("init-rust-pyo3.sh", ["/nonexistent/pangu-ffi"])
        self.assertEqual(r.returncode, 1)
        self.assertIn("目录不存在", strip_ansi(r.stderr))

    def test_apply_ffi_harness_unknown_bind_lang_dies(self):
        fake = make_fake_skill_root()
        r = source_common(fake, 'PROJ_DIR="."; apply_ffi_harness ruby')
        self.assertEqual(r.returncode, 1)
        self.assertIn("未知绑定语言 'ruby'", strip_ansi(r.stderr))


class Pyo3ScaffoldedTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="pangu-ffi-pyo3-")
        write(os.path.join(self.tmp, "Cargo.toml"), CARGO_TOML)
        write(os.path.join(self.tmp, "pyproject.toml"), PYPROJECT)
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def test_overlays_rust_base_plus_python_prefix(self):
        r = run_script("init-rust-pyo3.sh", cwd=self.tmp)
        self.assertEqual(r.returncode, 0, r.stderr)
        wf = os.path.join(self.tmp, ".github", "workflows")
        # rust 基底
        for f in ("ci.yml", "release.yml"):
            self.assertTrue(os.path.isfile(os.path.join(wf, f)), f)
        self.assertTrue(os.path.isfile(os.path.join(self.tmp, "lefthook.yml")))
        self.assertTrue(os.path.isfile(os.path.join(self.tmp, ".pre-commit-config.yaml")))
        self.assertTrue(os.path.isfile(os.path.join(self.tmp, "rustfmt.toml")))
        # python prefix 片段（不覆盖基底）
        for f in ("python-ci.yml", "python-release.yml"):
            self.assertTrue(os.path.isfile(os.path.join(wf, f)), f)
        self.assertTrue(os.path.isfile(os.path.join(self.tmp, "python-lefthook.yml")))
        self.assertTrue(os.path.isfile(os.path.join(self.tmp, "python-.pre-commit-config.yaml")))
        self.assertTrue(os.path.isfile(os.path.join(self.tmp, "pyproject-tooling.toml")))
        self.assertTrue(os.path.isdir(os.path.join(self.tmp, ".git")))
        out = strip_ansi(r.stdout)
        self.assertIn("Rust+python harness 初始化完成", out)
        self.assertIn("PyO3 专属", r.stdout)  # heredoc 原文，无颜色
        self.assertIn("hook 片段", out)

    def test_missing_marker_warns_but_proceeds(self):
        write(os.path.join(self.tmp, "pyproject.toml"),
              '[project]\nname = "demo"\n')  # 无 [tool.maturin] 标志
        r = run_script("init-rust-pyo3.sh", cwd=self.tmp)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("未在 pyproject.toml 找到", strip_ansi(r.stderr))
        self.assertTrue(os.path.isfile(
            os.path.join(self.tmp, ".github", "workflows", "python-ci.yml")))


class NapiScaffoldedTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="pangu-ffi-napi-")
        write(os.path.join(self.tmp, "Cargo.toml"), CARGO_TOML)
        write(os.path.join(self.tmp, "package.json"), PACKAGE_JSON)
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def test_overlays_rust_base_plus_node_prefix(self):
        r = run_script("init-rust-napi.sh", cwd=self.tmp)
        self.assertEqual(r.returncode, 0, r.stderr)
        wf = os.path.join(self.tmp, ".github", "workflows")
        self.assertTrue(os.path.isfile(os.path.join(wf, "ci.yml")))          # rust 基底
        self.assertTrue(os.path.isfile(os.path.join(wf, "node-ci.yml")))     # node 片段
        self.assertTrue(os.path.isfile(os.path.join(self.tmp, "node-lefthook.yml")))
        self.assertTrue(os.path.isfile(os.path.join(self.tmp, "node-.pre-commit-config.yaml")))
        self.assertTrue(os.path.isfile(os.path.join(self.tmp, "tsconfig.json")))
        # 基底 lefthook.yml 与 node 片段并存
        self.assertTrue(os.path.isfile(os.path.join(self.tmp, "lefthook.yml")))
        self.assertIn("napi-rs 专属", r.stdout)
        self.assertIn("Rust+node harness 初始化完成", strip_ansi(r.stdout))


class ApplyFfiHarnessDirectTest(unittest.TestCase):
    """直接调用 _common.sh 的 apply_ffi_harness（隔离 fake skill root）。"""

    def test_scaffolded_python_bind_overlays_harness(self):
        fake = make_fake_skill_root()
        proj = os.path.join(fake, "proj")
        write(os.path.join(proj, "Cargo.toml"), CARGO_TOML)
        write(os.path.join(proj, "pyproject.toml"), PYPROJECT)
        r = source_common(fake, 'PROJ_DIR="%s"; apply_ffi_harness python' % proj)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(os.path.isfile(
            os.path.join(proj, ".github", "workflows", "python-ci.yml")))
        self.assertTrue(os.path.isfile(os.path.join(proj, "lefthook.yml")))


if __name__ == "__main__":
    unittest.main()
