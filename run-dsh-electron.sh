#!/usr/bin/env bash
set -euo pipefail

# Linux 上通过 Electron 运行 DeepSeek Harness（dsh web）的一键脚本。
# 默认：自启一个独立的 dsh web 实例（端口 3088、独立 home），再装进 Electron 窗口。

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$HERE/deepseek-harness"
APP_DIR="$HERE/electron-runner"

if [ ! -d "$REPO" ]; then
  echo "仓库不存在: $REPO" >&2
  exit 1
fi

# ---- 依赖自愈：node_modules/.pnpm 被清空时从本地 store 离线恢复 ----
# 为什么需要：pnpm install/run 在 lockfile 不同步时可能清掉 virtual store，
# 随后启动脚本会在 tsx/electron 解析处失败。这里在启动前检查并离线重装。
export PATH="/home/zqh/.nvm/versions/node/v24.21.0/bin:$REPO/node_modules/.bin:$PATH"
export COREPACK_HOME="${COREPACK_HOME:-$HERE/.corepack}"
export PNPM_STORE_DIR="${PNPM_STORE_DIR:-$HERE/.pnpm-store}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HERE/.xdg-cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HERE/.xdg-data}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HERE/.xdg-state}"
export ELECTRON_CACHE="${ELECTRON_CACHE:-$HERE/.electron-cache}"
export electron_config_cache="${electron_config_cache:-$ELECTRON_CACHE}"
export npm_config_cache="${npm_config_cache:-$HERE/.npm-cache}"

need_deps=0
if [ ! -d "$REPO/node_modules/.pnpm" ] || [ -z "$(ls -A "$REPO/node_modules/.pnpm" 2>/dev/null)" ]; then
  need_deps=1
elif ! (cd "$REPO" && node -e "require.resolve('tsx/esm')") >/dev/null 2>&1; then
  need_deps=1
fi
if [ "$need_deps" = "1" ]; then
  echo "[dsh-electron] node_modules 不完整，尝试从本地 pnpm store 离线恢复..." >&2
  if ! ( cd "$REPO" && corepack pnpm@11.7.0 install --offline --ignore-scripts --frozen-lockfile ); then
    echo "[dsh-electron] 离线恢复失败，改用 prefer-offline..." >&2
    ( cd "$REPO" && corepack pnpm@11.7.0 install --prefer-offline --ignore-scripts --no-frozen-lockfile ) \
      || { echo "[dsh-electron] 依赖恢复失败。" >&2; exit 1; }
  fi
fi

# ---- 自动构建：默认不编译，只在强制或没有产物时才构建 ----
# 用户只想进界面时不要被编译卡住：有 apps/web/dist 就直接启动。
#   FORCE_BUILD=1 强制重新构建；无 web 产物时会自动构建。
if [ "${FORCE_BUILD:-0}" = "1" ] || [ ! -f "$REPO/apps/web/dist/index.html" ]; then
  export PATH="/home/zqh/.nvm/versions/node/v24.21.0/bin:$REPO/node_modules/.bin:$PATH"
  echo "[dsh-electron] 开始构建 (build:lib + build:web)..."
  # 直接跑叶子脚本，绕开 build:lib 里的 `pnpm run`（pnpm run 会做 deps 校验
  # 并可能清掉 node_modules）。
  # 构建失败时不直接退出：已有产物仍可启动，避免卡在“进不去软件”。
  if ( cd "$REPO" && npm run build:lib:host && npm run build:lib:client && npm run build:web ); then
    echo "[dsh-electron] 构建完成。"
  else
    if [ -f "$REPO/apps/web/dist/index.html" ]; then
      echo "[dsh-electron] 构建失败，但已有 web 产物，继续用旧界面启动。" >&2
    else
      echo "[dsh-electron] 构建失败，且没有可用 web 产物。" >&2
      exit 1
    fi
  fi
else
  echo "[dsh-electron] 使用已有界面产物，跳过构建（FORCE_BUILD=1 可强制重建）。"
fi

# 解析 Electron 可执行文件（apps/desktop 依赖里的 electron 二进制）
ELECTRON_BIN=""
find_electron() {
  local candidate
  for candidate in "$REPO"/node_modules/.pnpm/electron@*/node_modules/electron/dist/electron; do
    if [ -x "$candidate" ]; then ELECTRON_BIN="$candidate"; return 0; fi
  done
  return 1
}
find_electron || true

# pnpm 默认不执行依赖的 postinstall，重装依赖会把 electron/dist 清掉，只剩缓存里的
# 压缩包。这里用同一个缓存把二进制补回来，避免脚本直接卡在“找不到 Electron”。
if [ -z "$ELECTRON_BIN" ]; then
  # electron 的 install.js 通过 electron_config_cache 定位缓存（不是 ELECTRON_CACHE），
  # 再把 XDG 缓存兜底到工作区，避免它去写只读的 ~/.cache。
  export electron_config_cache="${electron_config_cache:-$HERE/.electron-cache}"
  export ELECTRON_CACHE="$electron_config_cache"
  export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HERE/.xdg-cache}"
  echo "[dsh-electron] 未找到 Electron 二进制，尝试用缓存恢复..." >&2
  for pkg in "$REPO"/node_modules/.pnpm/electron@*/node_modules/electron; do
    [ -f "$pkg/install.js" ] || continue
    ( cd "$pkg" && node install.js ) || true
  done
  find_electron || true
fi

if [ -z "$ELECTRON_BIN" ]; then
  echo "找不到 Electron 可执行文件。可尝试:" >&2
  echo "  cd $REPO && corepack pnpm@11.7.0 install --prefer-offline --ignore-scripts" >&2
  echo "  然后重跑本脚本（会自动用 .electron-cache 还原 electron）。" >&2
  exit 1
fi

NODE_BIN="$(command -v node)"
export DSH_NODE="$NODE_BIN"
# 让 dsh 子进程也能解析 tsx/其它 bin（pnpm 子进程也会找 PATH 上的 pnpm）
export PATH="$REPO/node_modules/.bin:$PATH"

# 用独立、可写的 home（本环境沙箱只允许写工作区；外部 DSH_HOME 指向 /home/zqh/.dsh 只读）
export DSH_HOME="${DSH_ELECTRON_HOME:-$HERE/.dsh-electron-home}"
export DSH_ELECTRON_PORT="${DSH_ELECTRON_PORT:-3088}"
export DSH_ELECTRON_NO_BOOT="${DSH_ELECTRON_NO_BOOT:-0}"

# 缓存/状态目录迁到工作区内（避免写只读的 ~/.cache ~/.npm ~/.config）
export COREPACK_HOME="$HERE/.corepack"
export XDG_CACHE_HOME="$HERE/.xdg-cache"
export XDG_DATA_HOME="$HERE/.xdg-data"
export XDG_STATE_HOME="$HERE/.xdg-state"
export ELECTRON_CACHE="$HERE/.electron-cache"
export npm_config_cache="$HERE/.npm-cache"
export ELECTRON_USER_DATA="$HERE/.electron-user-data"

mkdir -p "$DSH_HOME" "$ELECTRON_CACHE" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$ELECTRON_USER_DATA"

echo "[dsh-electron] electron : $ELECTRON_BIN"
echo "[dsh-electron] dsh home : $DSH_HOME"
echo "[dsh-electron] web url  : http://127.0.0.1:${DSH_ELECTRON_PORT}"
echo "[dsh-electron] display  : ${DISPLAY:-<none>}"

exec "$ELECTRON_BIN" --disable-gpu --user-data-dir="$ELECTRON_USER_DATA" "$APP_DIR" "$@"
