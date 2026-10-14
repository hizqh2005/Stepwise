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
  echo "找不到 Electron 可执行文件，请先安装依赖: cd $REPO && pnpm install" >&2
  exit 1
fi

NODE_BIN="$(command -v node)"
export DSH_NODE="$NODE_BIN"

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
