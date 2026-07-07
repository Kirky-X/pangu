# pangu 通用多语言 Dockerfile 模板（python / node / rust，ARG 切换）。
#
# 这是脚手架模板——COPY 路径、构建命令、CMD 入口需按实际项目调整。
# 设计要点（对应 .claude/rules/deployment.md）：
#   - 多阶段构建：builder 装工具链编译，runtime 仅含产物（镜像最小化）
#   - 基础镜像版本锁定（ARG 可覆盖），避免 upstream :latest 标签漂移
#   - 非 root 用户运行（安全默认；最小权限）
#   - 每种语言独立 builder + runtime，未选中的 stage 由 Docker 自动死代码消除
#
# 用法（按 --target 选运行时镜像；APP_LANG ARG 同时写入 OCI label 便于筛选）:
#   docker build --target run-python --build-arg APP_LANG=python -t app:py .
#   docker build --target run-node   --build-arg APP_LANG=node   -t app:js .
#   docker build --target run-rust   --build-arg APP_LANG=rust   -t app:rs .
#
# 校验（无需 Docker）: docker buildx build --check .   # Dockerfile linter（需 buildx >=0.13）

# ===== 全局 ARG：语言选择 + 各语言基础镜像版本（可 docker build --build-arg 覆盖）=====
ARG APP_LANG=python
ARG PYTHON_BUILD_IMAGE=python:3.12-slim
ARG PYTHON_RUN_IMAGE=python:3.12-slim
ARG NODE_BUILD_IMAGE=node:22-bookworm
ARG NODE_RUN_IMAGE=node:22-alpine
ARG RUST_BUILD_IMAGE=rust:1.83-bookworm
ARG RUST_RUN_IMAGE=debian:12-slim

# ============================================================
# Builder 阶段（产出可运行产物）
# ============================================================

# ----- Python builder（uv 优先，回退 pip；产物 = 虚拟环境 + 源码）-----
FROM ${PYTHON_BUILD_IMAGE} AS build-python
ARG PYTHON_BUILD_IMAGE
WORKDIR /app
COPY pyproject.toml uv.lock* ./
COPY . .
RUN --mount=type=cache,target=/root/.cache \
    if command -v uv >/dev/null 2>&1; then \
      uv sync --frozen --no-dev --no-install-project || uv pip install --system . ; \
    else pip install --no-cache-dir . ; fi

# ----- Node builder（npm ci 优先；产物 = node_modules + 源码；按需补 build 步骤）-----
FROM ${NODE_BUILD_IMAGE} AS build-node
WORKDIR /app
COPY package.json package-lock.json* ./
RUN --mount=type=cache,target=/root/.npm npm ci --omit=dev || npm install --omit=dev
COPY . .
# 若有构建步骤（tsc / vite build / next build）取消下行注释并按需调整输出目录:
# RUN npm run build

# ----- Rust builder（release 编译；产物 = target/release/<bin>）-----
FROM ${RUST_BUILD_IMAGE} AS build-rust
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN --mount=type=cargo,target=/usr/local/cargo/registry \
    --mount=type=cargo,target=/app/target \
    cargo build --release && \
    cp target/release/*/app target/release/app 2>/dev/null || cp target/release/app ./app-bin

# ============================================================
# Runtime 阶段（按语言，最小化；非 root）
# 用法: docker build --target run-<lang> 选择最终镜像
# ============================================================

# ----- Python runtime -----
FROM ${PYTHON_RUN_IMAGE} AS run-python
ARG PYTHON_RUN_IMAGE
ARG APP_LANG
LABEL org.opencontainers.image.title="app (python runtime)" \
      org.pangu.lang="${APP_LANG}"
WORKDIR /app
RUN python -m venv /opt/venv && \
    useradd -r -u 10001 -d /app -s /usr/sbin/nologin nonroot
ENV PATH="/opt/venv/bin:${PATH}"
COPY --from=build-python /app /app
USER nonroot
# 默认入口占位（按实际框架替换: uvicorn / gunicorn / python -m …）
CMD ["python", "-c", "print('pangu python runtime: edit CMD')"]

# ----- Node runtime -----
FROM ${NODE_RUN_IMAGE} AS run-node
ARG APP_LANG
LABEL org.opencontainers.image.title="app (node runtime)" \
      org.pangu.lang="${APP_LANG}"
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup -S app && adduser -S app -G app -h /app
COPY --from=build-node /app /app
USER app
# 默认入口占位（按实际框架替换: node dist/index.js / server.js …）
CMD ["node", "-e", "console.log('pangu node runtime: edit CMD')"]

# ----- Rust runtime -----
FROM ${RUST_RUN_IMAGE} AS run-rust
ARG APP_LANG
LABEL org.opencontainers.image.title="app (rust runtime)" \
      org.pangu.lang="${APP_LANG}"
WORKDIR /app
RUN useradd -r -u 10001 -d /app -s /usr/sbin/nologin nonroot
COPY --from=build-rust /app/app-bin /usr/local/bin/app
USER nonroot
CMD ["app"]
