#!/usr/bin/env python3
"""init-<lang>.sh 冒烟测试。

分级策略:
- init-cpp.sh（无工具链依赖）与 init-rust.sh（cargo init 纯本地）: 真实完整跑；
- init-go/python/node/java/ruby/php/dotnet: 包管理器 add/require 需网络，
  用 PATH 前置 stub 命令 mock（语言脚手架子命令生成最小 manifest），验证
  harness 侧真实逻辑（模板拷贝、snippet 合并、幂等保护、参数校验）;
- 工具链缺失时的 require_cmd die 路径: skipIf 本机已装对应工具（无法模拟缺失）。

一切副作用均在临时目录。
"""
import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))

import _util
from _util import make_mock_bin, read, run_script, strip_ansi, write


def skip_if_tool(name):
    return unittest.skipIf(_util.shutil.which(name) is not None,
                           "本机已装 %s，无法模拟缺失场景" % name)


class BaseLangTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="pangu-init-%s-" % self.lang())

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def lang(self):
        raise NotImplementedError

    def run_init(self, *args, cwd=None, mock=None, env_extra=None):
        mock_dir = make_mock_bin(mock) if mock else None
        if mock_dir:
            self.addCleanup(shutil.rmtree, mock_dir, ignore_errors=True)
        return run_script("init-%s.sh" % self.lang(), list(args),
                          cwd=cwd or self.tmp, mock_dir=mock_dir, env_extra=env_extra)


class InitCppTest(BaseLangTest):
    """cpp 脚本零外部依赖（不 require 任何编译器），可真实完整跑。"""

    def lang(self):
        return "cpp"

    def test_full_bootstrap_in_subdir(self):
        r = self.run_init("demo")
        self.assertEqual(r.returncode, 0, r.stderr)
        d = os.path.join(self.tmp, "demo")
        self.assertEqual(read(os.path.join(d, "src", "main.cpp")).count("hello"), 1)
        for sub in ("include", "tests"):
            self.assertTrue(os.path.isdir(os.path.join(d, sub)), sub)
        self.assertTrue(os.path.isfile(os.path.join(d, "CMakeLists.txt")))
        self.assertTrue(os.path.isfile(os.path.join(d, ".github", "workflows", "ci.yml")))
        self.assertTrue(os.path.isfile(os.path.join(d, "lefthook.yml")))
        self.assertTrue(os.path.isdir(os.path.join(d, ".git")))
        self.assertIn("C/C++ (CMake) harness 初始化完成", strip_ansi(r.stdout))

    def test_existing_main_cpp_not_overwritten(self):
        d = os.path.join(self.tmp, "demo")
        write(os.path.join(d, "src", "main.cpp"), "// custom main\n")
        r = self.run_init("demo")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("// custom main", read(os.path.join(d, "src", "main.cpp")))

    def test_bootstrap_in_current_dir(self):
        cur = os.path.join(self.tmp, "cur")
        os.makedirs(cur)
        r = self.run_init(cwd=cur)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(os.path.isfile(os.path.join(cur, "CMakeLists.txt")))


class InitRustTest(BaseLangTest):
    """cargo init 为纯本地操作，真实执行；无任何网络调用。"""

    def lang(self):
        return "rust"

    def test_bin_bootstrap_appends_release_profile(self):
        r = self.run_init("demo")
        self.assertEqual(r.returncode, 0, r.stderr)
        d = os.path.join(self.tmp, "demo")
        toml = read(os.path.join(d, "Cargo.toml"))
        self.assertIn("[package]", toml)
        self.assertIn("[profile.release]", toml)
        self.assertIn('panic = "abort"', toml)
        self.assertFalse(os.path.exists(os.path.join(d, "cargo-profile.snippet.toml")))
        for f in ("rustfmt.toml", "clippy.toml", "deny.toml",
                  ".pre-commit-config.yaml", ".gitignore"):
            self.assertTrue(os.path.isfile(os.path.join(d, f)), f)
        self.assertTrue(os.path.isfile(os.path.join(d, ".github", "workflows", "ci.yml")))
        self.assertIn("Rust harness 初始化完成", strip_ansi(r.stdout))

    def test_lib_bootstrap_strips_panic_abort(self):
        r = self.run_init("demo", "lib")
        self.assertEqual(r.returncode, 0, r.stderr)
        toml = read(os.path.join(self.tmp, "demo", "Cargo.toml"))
        self.assertIn("[profile.release]", toml)
        self.assertNotIn('panic = "abort"', toml)

    def test_invalid_project_kind_exits_1(self):
        r = self.run_init("demo", "app")
        self.assertEqual(r.returncode, 1)
        self.assertIn("第二参数须为 bin 或 lib", strip_ansi(r.stderr))

    def test_idempotent_keeps_manifest_and_skips_append(self):
        d = os.path.join(self.tmp, "preset")
        os.makedirs(d)
        write(os.path.join(d, "Cargo.toml"),
              '[package]\nname = "preset"\n\n[profile.release]\nlto = true\n')
        r = self.run_init("preset")
        self.assertEqual(r.returncode, 0, r.stderr)
        toml = read(os.path.join(d, "Cargo.toml"))
        self.assertIn('name = "preset"', toml)     # 原内容保留
        self.assertIn("lto = true", toml)
        self.assertNotIn("strip", toml)            # 未追加 snippet
        self.assertIn("已含 [profile.release]，跳过追加", strip_ansi(r.stderr))
        # harness 模板仍拷贝
        self.assertTrue(os.path.isfile(os.path.join(d, "rustfmt.toml")))

    def test_preset_manifest_without_profile_gets_append(self):
        d = os.path.join(self.tmp, "preset")
        os.makedirs(d)
        write(os.path.join(d, "Cargo.toml"), '[package]\nname = "preset"\n')
        r = self.run_init("preset")
        self.assertEqual(r.returncode, 0, r.stderr)
        toml = read(os.path.join(d, "Cargo.toml"))
        self.assertIn('name = "preset"', toml)
        self.assertIn("[profile.release]", toml)   # 幂等跳过脚手架但 profile 仍补齐
        self.assertFalse(os.path.exists(os.path.join(d, "cargo-profile.snippet.toml")))


MOCK_GO = {"go": ('if [ "$1" = mod ] && [ "$2" = init ]; then '
                  'printf "module %s\\n" "$3" > go.mod; fi; exit 0')}


@skip_if_tool("go")
class InitGoRequireTest(BaseLangTest):
    def lang(self):
        return "go"

    def test_missing_go_dies(self):
        r = run_script("init-go.sh", ["demo"], cwd=self.tmp,
                       env_extra={"PATH": "/usr/bin:/bin"})
        self.assertEqual(r.returncode, 1)
        self.assertIn("缺少命令: go", strip_ansi(r.stderr))


class InitGoStubTest(BaseLangTest):
    def lang(self):
        return "go"

    def test_bootstrap_with_go_module_override(self):
        d = os.path.join(self.tmp, "demo")
        r = self.run_init("demo", mock=MOCK_GO, env_extra={"GO_MODULE": "example.com/x/demo"})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(read(os.path.join(d, "go.mod")), "module example.com/x/demo\n")
        makefile = read(os.path.join(d, "Makefile"))
        self.assertIn("APP_NAME ?= demo", makefile)
        self.assertNotIn("APP_NAME ?= app", makefile)
        self.assertTrue(os.path.isfile(os.path.join(d, ".github", "workflows", "ci.yml")))
        self.assertIn("Go harness 初始化完成", strip_ansi(r.stdout))

    def test_idempotent_keeps_existing_module(self):
        d = os.path.join(self.tmp, "demo")
        os.makedirs(d)
        write(os.path.join(d, "go.mod"), "module keep/me\n")
        r = self.run_init("demo", mock=MOCK_GO)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(read(os.path.join(d, "go.mod")), "module keep/me\n")
        self.assertIn("跳过脚手架", strip_ansi(r.stderr))
        self.assertTrue(os.path.isfile(os.path.join(d, "Makefile")))


MOCK_UV = {"uv": r'''
if [ "$1" = init ]; then
  dir=""
  for a in "$@"; do
    case "$a" in -*) ;; init) ;; *) dir="$a" ;; esac
  done
  body='[project]
name = "stub"
version = "0.1.0"
'
  if [ -n "$dir" ]; then mkdir -p "$dir"; printf "%s\n" "$body" > "$dir/pyproject.toml";
  else printf "%s\n" "$body" > pyproject.toml; fi
fi
exit 0
'''}


class InitPythonStubTest(BaseLangTest):
    def lang(self):
        return "python"

    def test_bootstrap_merges_tooling_snippet(self):
        r = self.run_init("demo", mock=MOCK_UV)
        self.assertEqual(r.returncode, 0, r.stderr)
        d = os.path.join(self.tmp, "demo")
        py = read(os.path.join(d, "pyproject.toml"))
        self.assertIn("[project]", py)
        self.assertIn("[tool.ruff]", py)          # snippet 已合并
        self.assertIn("pangu tooling snippet", py)
        self.assertFalse(os.path.exists(os.path.join(d, "pyproject-tooling.toml")))
        self.assertTrue(os.path.isfile(os.path.join(d, ".pre-commit-config.yaml")))
        self.assertIn("Python harness 初始化完成", strip_ansi(r.stdout))

    def test_kind_validation_exits_1(self):
        r = self.run_init("demo", "service", mock=MOCK_UV)
        self.assertEqual(r.returncode, 1)
        self.assertIn("第二参数须为 lib 或 app", strip_ansi(r.stderr))

    def test_idempotent_with_existing_ruff_config(self):
        d = os.path.join(self.tmp, "preset")
        os.makedirs(d)
        write(os.path.join(d, "pyproject.toml"),
              '[project]\nname = "preset"\n\n[tool.ruff]\nline-length = 100\n')
        r = self.run_init("preset", mock=MOCK_UV)
        self.assertEqual(r.returncode, 0, r.stderr)
        py = read(os.path.join(d, "pyproject.toml"))
        self.assertIn("line-length = 100", py)
        self.assertIn("已含 [tool.ruff]，跳过 snippet 合并", strip_ansi(r.stderr))
        self.assertFalse(os.path.exists(os.path.join(d, "pyproject-tooling.toml")))

    def test_uv_init_failure_aborts_explicitly(self):
        # uv init 失败 → set -e 直接终止（失败显性化，不静默降级）
        mock = {"uv": 'if [ "$1" = init ]; then exit 1; fi; exit 0'}
        r = self.run_init("demo", mock=mock)
        self.assertEqual(r.returncode, 1)
        d = os.path.join(self.tmp, "demo")
        self.assertFalse(os.path.exists(os.path.join(d, ".github")))  # harness 未叠加


MOCK_PKG = {
    "pnpm": ('if [ "$1" = init ]; then printf "{\\n  \\"name\\": \\"stub\\"\\n}\\n" > package.json; fi; exit 0'),
}


class InitNodeStubTest(BaseLangTest):
    def lang(self):
        return "node"

    def test_bootstrap_lands_eslint_config_and_merges_snippet(self):
        r = self.run_init("demo", mock=MOCK_PKG)
        self.assertEqual(r.returncode, 0, r.stderr)
        d = os.path.join(self.tmp, "demo")
        self.assertTrue(os.path.isfile(os.path.join(d, "eslint.config.js")))  # snippet 落地
        self.assertFalse(os.path.exists(os.path.join(d, "eslint-flat.snippet.js")))
        self.assertTrue(os.path.isfile(os.path.join(d, "tsconfig.json")))
        self.assertTrue(os.path.isfile(os.path.join(d, "vitest.config.ts")))
        pkg = json.loads(read(os.path.join(d, "package.json")))
        self.assertIn("format", pkg.get("scripts", {}))   # 真实 node 合并 prettier snippet
        self.assertFalse(os.path.exists(os.path.join(d, "prettier.snippet.json")))
        self.assertIn("Node/TypeScript harness 初始化完成", strip_ansi(r.stdout))

    def test_idempotent_keeps_existing_package_json(self):
        d = os.path.join(self.tmp, "preset")
        os.makedirs(d)
        write(os.path.join(d, "package.json"), '{"name": "preset", "version": "1.0.0"}')
        r = self.run_init("preset", mock=MOCK_PKG)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("跳过脚手架", strip_ansi(r.stderr))
        self.assertEqual(json.loads(read(os.path.join(d, "package.json")))["name"], "preset")
        self.assertTrue(os.path.isfile(os.path.join(d, "tsconfig.json")))


MOCK_MVN = {"mvn": r'''
if [ "$2" = archetype:generate ] || [ "$1" = archetype:generate ]; then
  aid="app"; outdir="."
  for a in "$@"; do
    case "$a" in
      -DartifactId=*) aid="${a#-DartifactId=}" ;;
      -DoutputDirectory=*) outdir="${a#-DoutputDirectory=}" ;;
    esac
  done
  mkdir -p "$outdir/$aid"
  cat > "$outdir/$aid/pom.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
  </properties>
  <dependencies>
    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
      <version>3.8.1</version>
    </dependency>
  </dependencies>
</project>
XML
fi
exit 0
'''}


@skip_if_tool("mvn")
class InitJavaRequireTest(BaseLangTest):
    def lang(self):
        return "java"

    def test_missing_mvn_dies(self):
        r = run_script("init-java.sh", ["demo"], cwd=self.tmp,
                       env_extra={"PATH": "/usr/bin:/bin"})
        self.assertEqual(r.returncode, 1)
        self.assertIn("缺少命令: mvn", strip_ansi(r.stderr))


class InitJavaStubTest(BaseLangTest):
    def lang(self):
        return "java"

    def test_bootstrap_merges_pom_plugins_snippet(self):
        r = self.run_init("demo", mock=MOCK_MVN)
        self.assertEqual(r.returncode, 0, r.stderr)
        d = os.path.join(self.tmp, "demo")
        pom = read(os.path.join(d, "pom.xml"))
        # properties 原位替换: snippet 的 release 21 取代 archetype 的 source 17
        self.assertIn("<maven.compiler.release>21</maven.compiler.release>", pom)
        self.assertNotIn("<maven.compiler.source>", pom)
        self.assertIn("<modelVersion>", pom)                    # archetype 原有内容保留
        self.assertIn("junit", pom)
        # build/reporting 注入
        self.assertIn("spotless-maven-plugin", pom)
        self.assertIn("maven-checkstyle-plugin", pom)
        self.assertFalse(os.path.exists(os.path.join(d, "pom-plugins.snippet.xml")))
        self.assertIn("pom-plugins.snippet.xml 已自动合并", strip_ansi(r.stdout))

    def test_idempotent_skips_archetype(self):
        d = os.path.join(self.tmp, "demo")
        os.makedirs(d)
        write(os.path.join(d, "pom.xml"),
              "<project>\n  <properties>\n    <x>1</x>\n  </properties>\n</project>\n")
        r = self.run_init("demo", mock=MOCK_MVN)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("跳过脚手架", strip_ansi(r.stderr))
        self.assertIn("spotless-maven-plugin", read(os.path.join(d, "pom.xml")))


MOCK_BUNDLE = {"bundle": r'''
if [ "$1" = init ]; then
  printf "source \"https://rubygems.org\"\n" > Gemfile
elif [ "$1" = gem ]; then
  name=""
  for a in "$@"; do
    case "$a" in gem) ;; -*) ;; *) name="$a" ;; esac
  done
  mkdir -p "$name"
  printf "source \"https://rubygems.org\"\n" > "$name/Gemfile"
fi
exit 0
'''}


@skip_if_tool("bundle")
class InitRubyRequireTest(BaseLangTest):
    def lang(self):
        return "ruby"

    def test_missing_bundle_dies(self):
        r = run_script("init-ruby.sh", ["demo"], cwd=self.tmp,
                       env_extra={"PATH": "/usr/bin:/bin"})
        self.assertEqual(r.returncode, 1)
        self.assertIn("缺少命令: bundle", strip_ansi(r.stderr))


class InitRubyStubTest(BaseLangTest):
    def lang(self):
        return "ruby"

    def test_bootstrap_creates_gemfile_and_copies_templates(self):
        r = self.run_init("demo", mock=MOCK_BUNDLE)
        self.assertEqual(r.returncode, 0, r.stderr)
        d = os.path.join(self.tmp, "demo")
        self.assertIn("rubygems.org", read(os.path.join(d, "Gemfile")))
        self.assertTrue(os.path.isfile(os.path.join(d, ".github", "workflows", "ci.yml")))
        self.assertTrue(os.path.isfile(os.path.join(d, "lefthook.yml")))
        self.assertIn("Ruby harness 初始化完成", strip_ansi(r.stdout))

    def test_idempotent_keeps_gemfile(self):
        d = os.path.join(self.tmp, "demo")
        os.makedirs(d)
        write(os.path.join(d, "Gemfile"), 'source "https://custom.example"\n')
        r = self.run_init("demo", mock=MOCK_BUNDLE)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("https://custom.example", read(os.path.join(d, "Gemfile")))
        self.assertIn("跳过脚手架", strip_ansi(r.stderr))


MOCK_COMPOSER = {"composer": ('if [ "$1" = init ]; then printf "{}\\n" > composer.json; fi; exit 0')}


@skip_if_tool("composer")
class InitPhpRequireTest(BaseLangTest):
    def lang(self):
        return "php"

    def test_missing_composer_dies(self):
        r = run_script("init-php.sh", ["demo"], cwd=self.tmp,
                       env_extra={"PATH": "/usr/bin:/bin"})
        self.assertEqual(r.returncode, 1)
        self.assertIn("缺少命令: composer", strip_ansi(r.stderr))


class InitPhpStubTest(BaseLangTest):
    def lang(self):
        return "php"

    def test_bootstrap_creates_composer_json_and_templates(self):
        r = self.run_init("demo", mock=MOCK_COMPOSER)
        self.assertEqual(r.returncode, 0, r.stderr)
        d = os.path.join(self.tmp, "demo")
        self.assertTrue(os.path.isfile(os.path.join(d, "composer.json")))
        self.assertTrue(os.path.isfile(os.path.join(d, "phpunit.xml")))
        self.assertTrue(os.path.isfile(os.path.join(d, "psalm.xml")))
        self.assertIn("PHP harness 初始化完成", strip_ansi(r.stdout))

    def test_idempotent_keeps_composer_json(self):
        d = os.path.join(self.tmp, "demo")
        os.makedirs(d)
        write(os.path.join(d, "composer.json"), '{"name": "keep/me"}')
        r = self.run_init("demo", mock=MOCK_COMPOSER)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(read(os.path.join(d, "composer.json")))["name"], "keep/me")
        self.assertIn("跳过脚手架", strip_ansi(r.stderr))


MOCK_DOTNET = {"dotnet": r'''
if [ "$1" = new ]; then
  name="stub"
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      -n) name="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  printf '<Project Sdk="Microsoft.NET.Sdk" />\n' > "$name.csproj"
fi
exit 0
'''}


@skip_if_tool("dotnet")
class InitDotnetRequireTest(BaseLangTest):
    def lang(self):
        return "dotnet"

    def test_missing_dotnet_dies(self):
        r = run_script("init-dotnet.sh", ["demo"], cwd=self.tmp,
                       env_extra={"PATH": "/usr/bin:/bin"})
        self.assertEqual(r.returncode, 1)
        self.assertIn("缺少命令: dotnet", strip_ansi(r.stderr))


class InitDotnetStubTest(BaseLangTest):
    def lang(self):
        return "dotnet"

    def test_kind_validation_exits_1(self):
        r = self.run_init("demo", "mobile", mock=MOCK_DOTNET)
        self.assertEqual(r.returncode, 1)
        self.assertIn("kind 须为 console | classlib | web", strip_ansi(r.stderr))

    def test_console_bootstrap_creates_csproj(self):
        r = self.run_init("demo", mock=MOCK_DOTNET)
        self.assertEqual(r.returncode, 0, r.stderr)
        d = os.path.join(self.tmp, "demo")
        self.assertTrue(os.path.isfile(os.path.join(d, "demo.csproj")))
        self.assertTrue(os.path.isfile(os.path.join(d, "Directory.Build.props")))
        self.assertTrue(os.path.isfile(os.path.join(d, ".github", "workflows", "ci.yml")))
        self.assertIn(".NET harness 初始化完成", strip_ansi(r.stdout))

    def test_idempotent_keeps_csproj(self):
        d = os.path.join(self.tmp, "demo")
        os.makedirs(d)
        write(os.path.join(d, "keep.csproj"), "<Project />\n")
        r = self.run_init("demo", mock=MOCK_DOTNET)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(os.path.isfile(os.path.join(d, "keep.csproj")))
        self.assertFalse(os.path.exists(os.path.join(d, "demo.csproj")))
        self.assertIn("跳过脚手架", strip_ansi(r.stderr))


if __name__ == "__main__":
    unittest.main()
