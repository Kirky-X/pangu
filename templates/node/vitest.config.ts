import { defineConfig } from "vitest/config";

// 阈值占位符 __PANGU_COV__ 由 pangu init 按本次参数渲染（--cov / --profile，默认 80）
export default defineConfig({
  test: {
    environment: "node",
    coverage: {
      provider: "v8",
      reporter: ["text", "json", "html", "lcov"], // lcov.info 供 diff-cover 计算变更行覆盖率
      include: ["src/**/*.ts"],
      exclude: ["src/**/*.d.ts", "src/**/index.ts", "**/*.config.*"],
      thresholds: {
        lines: __PANGU_COV__,
        branches: __PANGU_COV__,
        functions: __PANGU_COV__,
        statements: __PANGU_COV__,
      },
    },
  },
});
