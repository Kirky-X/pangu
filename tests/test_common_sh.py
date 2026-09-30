#!/usr/bin/env python3
"""_common.sh 公共函数库冒烟测试（① 纯函数/可离线调用逻辑）。

被测函数: check_idempotent / log·ok·warn·die / require_cmd /
copy_common / copy_lang（prefix·.gitignore 合并·备份跳过）/
merge_node_snippet / harness_finalize。
copy_lang 的多语言 prefix 行为另有 scripts/test-multi.sh（bash 版），本套件
在隔离 fake skill root 上复验并补充备份跳过等边界。
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))

import _util
from _util import make_fake_skill_root, source_common, strip_ansi


class LoggingTest(unittest.TestCase):
    def test_log_ok_stdout_warn_stderr(self):
        fake = make_fake_skill_root()
        r = source_common(fake, 'log hi; ok done; warn careful; echo "rc-before-die"')
        self.assertEqual(r.returncode, 0)
        self.assertIn("[harness] hi", strip_ansi(r.stdout))
        self.assertIn("✓ done", strip_ansi(r.stdout))
        self.assertIn("! careful", strip_ansi(r.stderr))
        self.assertIn("rc-before-die", r.stdout)

    def test_die_exits_1_with_message(self):
        fake = make_fake_skill_root()
        r = source_common(fake, 'die "boom 爆炸"')
        self.assertEqual(r.returncode, 1)
        self.assertIn("✗ boom 爆炸", strip_ansi(r.stderr))

    def test_require_cmd_present(self):
        fake = make_fake_skill_root()
        r = source_common(fake, "require_cmd bash")
        self.assertEqual(r.returncode, 0)

    def test_require_cmd_missing_terminates_script(self):
        # die 内是 exit 1：即使调用方用 || 兜底也终止整个脚本（显性失败，非静默继续）
        fake = make_fake_skill_root()
        r = source_common(fake, "require_cmd __no_such_cmd_pangu__ || echo FALLBACK")
        self.assertEqual(r.returncode, 1)
        self.assertIn("缺少命令: __no_such_cmd_pangu__", strip_ansi(r.stderr))
        self.assertNotIn("FALLBACK", r.stdout)


class CheckIdempotentTest(unittest.TestCase):
    def test_manifest_absent_returns_1_continue(self):
        fake = make_fake_skill_root()
        r = source_common(fake, "if check_idempotent /nonexistent/Cargo.toml rust; then echo SKIP; else echo GO; fi")
        self.assertEqual(r.returncode, 0)
        self.assertIn("GO", r.stdout)
        self.assertNotIn("SKIP", r.stdout)

    def test_manifest_present_returns_0_skip_with_warn(self):
        fake = make_fake_skill_root()
        manifest = os.path.join(fake, "existing", "go.mod")
        _util.write(manifest, "module x\n")
        r = source_common(
            fake,
            'if check_idempotent "%s" go; then echo SKIP; else echo GO; fi' % manifest,
        )
        self.assertEqual(r.returncode, 0)
        self.assertIn("SKIP", r.stdout)
        self.assertIn("跳过脚手架", r.stderr)


class CopyCommonTest(unittest.TestCase):
    def test_copies_github_ecosystem_editorconfig_and_license(self):
        fake = make_fake_skill_root()
        proj = os.path.join(fake, "proj")
        os.makedirs(proj)
        r = source_common(fake, 'PROJ_DIR="%s"; copy_common' % proj)
        self.assertEqual(r.returncode, 0, r.stderr)
        base = os.path.join(proj, ".github")
        for rel in ("workflows", "ISSUE_TEMPLATE", "dependabot.yml", "CODEOWNERS",
                    "PULL_REQUEST_TEMPLATE.md"):
            self.assertTrue(os.path.exists(os.path.join(base, rel)), rel)
        self.assertTrue(os.path.isfile(os.path.join(proj, ".editorconfig")))
        self.assertTrue(os.path.isfile(os.path.join(proj, "LICENSE")))

    def test_license_not_overwritten_when_exists(self):
        fake = make_fake_skill_root()
        proj = os.path.join(fake, "proj")
        os.makedirs(proj)
        _util.write(os.path.join(proj, "LICENSE"), "proprietary")
        r = source_common(fake, 'PROJ_DIR="%s"; copy_common' % proj)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(_util.read(os.path.join(proj, "LICENSE")), "proprietary")

    def test_missing_common_template_dir_dies(self):
        fake = make_fake_skill_root()
        import shutil
        shutil.rmtree(os.path.join(fake, "templates", "common"))
        proj = os.path.join(fake, "proj")
        os.makedirs(proj)
        r = source_common(fake, 'PROJ_DIR="%s"; copy_common' % proj)
        self.assertEqual(r.returncode, 1)
        self.assertIn("通用模板目录不存在", r.stderr)


class CopyLangTest(unittest.TestCase):
    def test_rust_single_lang_no_prefix(self):
        fake = make_fake_skill_root()
        proj = os.path.join(fake, "proj")
        os.makedirs(proj)
        r = source_common(fake, 'PROJ_DIR="%s"; copy_lang rust' % proj)
        self.assertEqual(r.returncode, 0, r.stderr)
        wf = os.path.join(proj, ".github", "workflows")
        for f in ("ci.yml", "release.yml"):
            self.assertTrue(os.path.isfile(os.path.join(wf, f)), f)
        for f in ("lefthook.yml", ".pre-commit-config.yaml", "rustfmt.toml",
                  "clippy.toml", "deny.toml", ".gitignore"):
            self.assertTrue(os.path.isfile(os.path.join(proj, f)), f)
        # 首语言 .gitignore 原样成为基底，无段头
        self.assertNotIn("# --- rust ---", _util.read(os.path.join(proj, ".gitignore")))

    def test_prefix_mode_conflicts_prefixed_configs_plain(self):
        fake = make_fake_skill_root()
        proj = os.path.join(fake, "proj")
        os.makedirs(proj)
        r = source_common(fake, 'PROJ_DIR="%s"; copy_lang python python' % proj)
        self.assertEqual(r.returncode, 0, r.stderr)
        wf = os.path.join(proj, ".github", "workflows")
        for f in ("python-ci.yml", "python-release.yml"):
            self.assertTrue(os.path.isfile(os.path.join(wf, f)), f)
        for f in ("python-lefthook.yml", "python-.pre-commit-config.yaml",
                  "pyproject-tooling.toml"):
            self.assertTrue(os.path.isfile(os.path.join(proj, f)), f)
        # 冲突文件必须加前缀，不允许无前缀覆盖
        self.assertFalse(os.path.exists(os.path.join(wf, "ci.yml")))

    def test_multi_lang_base_preserved_and_gitignore_appended(self):
        fake = make_fake_skill_root()
        proj = os.path.join(fake, "proj")
        os.makedirs(proj)
        r = source_common(
            fake,
            'PROJ_DIR="%s"; copy_lang rust && copy_lang python python && copy_lang node node'
            % proj,
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        wf = os.path.join(proj, ".github", "workflows")
        self.assertTrue(os.path.isfile(os.path.join(wf, "ci.yml")))        # rust 基底
        self.assertTrue(os.path.isfile(os.path.join(wf, "python-ci.yml")))
        self.assertTrue(os.path.isfile(os.path.join(wf, "node-ci.yml")))
        gi = _util.read(os.path.join(proj, ".gitignore"))
        self.assertIn("# --- python ---", gi)
        self.assertIn("# --- node ---", gi)

    def test_backup_files_are_not_copied(self):
        fake = make_fake_skill_root(langs=("rust",))
        rust_tpl = os.path.join(fake, "templates", "rust")
        for bak in ("rustfmt.toml.bak.20260702-0000", "rustfmt.toml.orig",
                    "clippy.toml.bak", "lefthook.yml.swp"):
            _util.write(os.path.join(rust_tpl, bak), "junk")
        proj = os.path.join(fake, "proj")
        os.makedirs(proj)
        r = source_common(fake, 'PROJ_DIR="%s"; copy_lang rust' % proj)
        self.assertEqual(r.returncode, 0, r.stderr)
        for junk in ("rustfmt.toml.bak.20260702-0000", "rustfmt.toml.orig",
                     "clippy.toml.bak", "lefthook.yml.swp"):
            self.assertFalse(os.path.exists(os.path.join(proj, junk)), junk)
        self.assertTrue(os.path.isfile(os.path.join(proj, "rustfmt.toml")))

    def test_unknown_lang_template_dies(self):
        fake = make_fake_skill_root()
        proj = os.path.join(fake, "proj")
        os.makedirs(proj)
        r = source_common(fake, 'PROJ_DIR="%s"; copy_lang fortran' % proj)
        self.assertEqual(r.returncode, 1)
        self.assertIn("语言模板不存在", r.stderr)


class MergeNodeSnippetTest(unittest.TestCase):
    SNIPPET = '{"scripts": {"fmt": "prettier --write ."}, "prettier": {"semi": false}, "engines": {"node": ">=20"}}'

    def test_merge_into_package_json_and_remove_snippet(self):
        fake = make_fake_skill_root()
        d = os.path.join(fake, "proj")
        _util.write(os.path.join(d, "package.json"), '{"name": "x", "scripts": {"test": "vitest"}}')
        _util.write(os.path.join(d, "prettier.snippet.json"), self.SNIPPET)
        r = source_common(fake, 'merge_node_snippet "%s"' % d)
        self.assertEqual(r.returncode, 0, r.stderr)
        import json
        pkg = json.loads(_util.read(os.path.join(d, "package.json")))
        self.assertEqual(pkg["scripts"]["fmt"], "prettier --write .")
        self.assertEqual(pkg["scripts"]["test"], "vitest")  # 原脚本保留
        self.assertEqual(pkg["prettier"], {"semi": False})
        self.assertEqual(pkg["engines"], {"node": ">=20"})
        self.assertFalse(os.path.exists(os.path.join(d, "prettier.snippet.json")))

    def test_noop_when_snippet_or_package_missing(self):
        fake = make_fake_skill_root()
        d = os.path.join(fake, "proj")
        r = source_common(fake, 'merge_node_snippet "%s"; echo "rc=$?"' % d)
        self.assertEqual(r.returncode, 0)
        self.assertIn("rc=0", r.stdout)
        _util.write(os.path.join(d, "prettier.snippet.json"), self.SNIPPET)
        r = source_common(fake, 'merge_node_snippet "%s"; echo "rc=$?"' % d)
        self.assertEqual(r.returncode, 0)
        self.assertIn("rc=0", r.stdout)
        self.assertTrue(os.path.isfile(os.path.join(d, "prettier.snippet.json")))


class HarnessFinalizeTest(unittest.TestCase):
    def test_prints_completion_banner_and_stages_files(self):
        fake = make_fake_skill_root()
        proj = os.path.join(fake, "proj")
        _util.write(os.path.join(proj, "README.md"), "hi")
        # harness_finalize 假定 git_init 已跑过（git add -A 失败被 || true 吞）
        r = source_common(
            fake,
            'PROJ_DIR="%s"; LANG_NAME="Rust"; git_init; harness_finalize' % proj,
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("Rust harness 初始化完成", strip_ansi(r.stdout))
        # git add -A 已 stage（git 本地操作，真实执行）
        import subprocess
        out = subprocess.run(
            ["git", "-C", proj, "ls-files"], capture_output=True, text=True
        ).stdout
        self.assertIn("README.md", out)


if __name__ == "__main__":
    unittest.main()
