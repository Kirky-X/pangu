#!/usr/bin/env python3
"""gen-distribution.sh 冒烟与行为测试。

- CLI 冒烟: --help / 缺参 / --globs 缺值 / --mirror-root 非法值 / 未知选项。
- 真实行为: 对临时构造的最小 skill 仓生成四类分发物；mdc 恰好一个 H1
  （intro_block 不再重复 H1）；无 .github 目录时不半途崩溃；嵌套敏感文件
  （refs/.env）不进镜像；镜像与主源 diff -rq 一致；漂移后 align-skill.sh
  [5/5] FAIL 且输出摘要（SIGPIPE 修复回归）；章节识别为空时 warn 响铃。
"""
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))

import _util
from _util import PANGU_ROOT, SCRIPTS, read, run_script, strip_ansi, write

MINIMAL_SKILL_MD = """---
name: mini-skill
description: "最小测试 skill：验证分发生成器行为"
version: "0.1.0"
---

# mini-skill — 最小测试skill

> 引言语块：这个 skill 只用于测试。

## 路由与命令

| 意图 | 命令 |
| --- | --- |
| 做点什么 | run |

## 约束汇总（硬性）

- [ ] 禁止占位符
- [ ] 先读再写
"""

EMPTY_SECTION_SKILL_MD = """---
name: plain-skill
description: "非规范标题的测试 skill"
---

# plain-skill

> 只有引言语块，没有任何二级章节。
"""


def make_mini_skill(tmp, skill_md=MINIMAL_SKILL_MD):
    root = os.path.join(tmp, "mini-skill")
    os.makedirs(os.path.join(root, "references"), exist_ok=True)
    os.makedirs(os.path.join(root, "refs"), exist_ok=True)
    write(os.path.join(root, "SKILL.md"), skill_md)
    write(os.path.join(root, "references", "doc.md"), "# ref\n")
    # 嵌套敏感文件：必须被排除在镜像之外（P1 修复回归）
    write(os.path.join(root, "refs", ".env"), "SECRET_TOKEN=sk-live-abc123\n")
    return root


class CliSmokeTest(unittest.TestCase):
    def test_help_exits_0(self):
        r = run_script("gen-distribution.sh", ["-h"])
        self.assertEqual(r.returncode, 0)
        self.assertIn("用法: gen-distribution.sh", strip_ansi(r.stdout))

    def test_missing_arg_exits_1(self):
        r = run_script("gen-distribution.sh")
        self.assertEqual(r.returncode, 1)
        self.assertIn("缺少必填参数", strip_ansi(r.stderr))

    def test_globs_missing_value_exits_1(self):
        r = run_script("gen-distribution.sh", [PANGU_ROOT, "--globs"])
        self.assertEqual(r.returncode, 1)
        self.assertIn("--globs 缺少参数值", strip_ansi(r.stderr))

    def test_globs_flag_value_rejected(self):
        r = run_script("gen-distribution.sh", [PANGU_ROOT, "--globs", "--dry-run"])
        self.assertEqual(r.returncode, 1)
        self.assertIn("--globs 的值不能以 -- 开头", strip_ansi(r.stderr))

    def test_mirror_root_with_slash_rejected(self):
        r = run_script("gen-distribution.sh", [PANGU_ROOT, "--mirror-root", "a/b"])
        self.assertEqual(r.returncode, 1)
        self.assertIn("--mirror-root", strip_ansi(r.stderr))


class GenerateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="pangu-gen-")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def test_generate_all_artifacts_single_h1(self):
        root = make_mini_skill(self.tmp)
        r = run_script("gen-distribution.sh", [root, "--globs", "**/spec.md"])
        self.assertEqual(r.returncode, 0, strip_ansi(r.stderr))
        mdc = os.path.join(root, ".cursor", "rules", "mini-skill.mdc")
        agents = os.path.join(root, "AGENTS.md")
        copilot = os.path.join(root, ".github", "copilot-instructions.md")
        mirror = os.path.join(root, ".trae", "skills", "mini-skill")
        for f in (mdc, agents, copilot):
            self.assertTrue(os.path.isfile(f), f"缺少生成物: {f}")
        self.assertTrue(os.path.isdir(mirror), "缺少同构镜像")
        # mdc 的 globs 与唯一 H1
        mdc_text = read(mdc)
        self.assertIn('  - "**/spec.md"', mdc_text)
        h1_count = sum(1 for line in mdc_text.splitlines() if line.startswith("# "))
        self.assertEqual(h1_count, 1, f"mdc 应恰好一个 H1，实际 {h1_count}")
        # 嵌套敏感文件不进镜像（排除清单两侧语义一致）
        self.assertFalse(
            os.path.exists(os.path.join(mirror, "refs", ".env")),
            "镜像含嵌套 .env——排除清单语义不一致",
        )
        # 正常内容在镜像内
        self.assertTrue(os.path.isfile(os.path.join(mirror, "references", "doc.md")))
        self.assertTrue(os.path.isfile(os.path.join(mirror, "SKILL.md")))

    def test_no_github_dir_does_not_crash(self):
        root = make_mini_skill(self.tmp)
        self.assertFalse(os.path.exists(os.path.join(root, ".github")))
        r = run_script("gen-distribution.sh", [root])
        self.assertEqual(r.returncode, 0, strip_ansi(r.stderr))
        self.assertTrue(
            os.path.isfile(os.path.join(root, ".github", "copilot-instructions.md")),
            "无 .github 目录时应自动创建后写入",
        )

    def test_empty_sections_warn(self):
        root = make_mini_skill(self.tmp, skill_md=EMPTY_SECTION_SKILL_MD)
        r = run_script("gen-distribution.sh", [root])
        self.assertEqual(r.returncode, 0, strip_ansi(r.stderr))
        err = strip_ansi(r.stderr)
        self.assertIn("未识别到路由/命令类二级章节", err)
        self.assertIn("未识别到约束/禁止/失败类二级章节", err)

    def test_drift_detected_by_align(self):
        root = make_mini_skill(self.tmp)
        r = run_script("gen-distribution.sh", [root])
        self.assertEqual(r.returncode, 0, strip_ansi(r.stderr))
        # 漂移镜像
        with open(os.path.join(root, ".trae", "skills", "mini-skill", "SKILL.md"), "a", encoding="utf-8") as f:
            f.write("\ndrift\n")
        a = run_script("align-skill.sh", [root, "--dry-run"])
        self.assertEqual(a.returncode, 1)
        out = strip_ansi(a.stdout)
        self.assertIn("与主源不一致", out)
        self.assertIn("汇总", out, "SIGPIPE 回归：汇总行应正常输出")
        self.assertIn("[5/5]", out)

    def test_mirror_root_option(self):
        root = make_mini_skill(self.tmp)
        r = run_script("gen-distribution.sh", [root, "--mirror-root", ".codebuddy"])
        self.assertEqual(r.returncode, 0, strip_ansi(r.stderr))
        self.assertTrue(
            os.path.isdir(os.path.join(root, ".codebuddy", "skills", "mini-skill")),
            "--mirror-root 未生效",
        )


if __name__ == "__main__":
    unittest.main()
