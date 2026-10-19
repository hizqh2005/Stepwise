#!/usr/bin/env bash
set -euo pipefail

# 一键「构建 + 启动 dsh web」脚本（Linux）。
#
# 为什么需要它：run-dsh-electron.sh 只是把 http://127.0.0.1:3088 装进
# Electron 窗口，它自己不构建。若 3088 上的服务来自旧构建产物，Electron
# 里看到的就永远是旧版本。本脚本先完整构建（把源码改动编进 lib/ 与
# apps/web/dist），再停掉旧的 3088 服务并启动新的 dsh web。
#
# 用法：
#   ./build-and-run-dsh.sh            构建 + 起 dsh web（端口 3088）
#   PORT=3081 ./build-and-run-dsh.sh  换端口
#   SKIP_BUILD=1 ./build-and-run-dsh.sh  跳过构建（只重启服务）

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$HERE/deepseek-harness"
PORT="${PORT:-3088}"
NODE_BIN="/home/zqh/.nvm/versions/node/v24.21.0/bin/node"

if [ ! -d "$REPO" ]; then
  echo "[build-run] 仓库不存在: $REPO" >&2
  exit 1
fi

# nvm 的 node 不在某些 shell 的 PATH 里，显式补上，保证 pnpm/corepack/tsx 可用。
export PATH="/home/zqh/.nvm/versions/node/v24.21.0/bin:$REPO/node_modules/.bin:$PATH"

cd "$REPO"

# ---- 1. 构建（把源码改动编进产物）------------------------------------------
if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "[build-run] 开始构建 -> build:lib (tsc + tsdown，产出各包 lib/)"
  # 直接跑叶子脚本，绕开 build:lib 里的 `pnpm run`（会触发 deps 校验/重装）。
  npm run build:lib:host
  npm run build:lib:client
  echo "[build-run] -> build:web (vite，产出 apps/web/dist)"
  npm run build:web
  echo "[build-run] 构建完成。"
else
  echo "[build-run] SKIP_BUILD=1，跳过构建。"
fi

# ---- 2. 停掉占用端口的旧 dsh web -------------------------------------------
OLD_PID="$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null || true)"
if [ -n "$OLD_PID" ]; then
  echo "[build-run] 停掉占用 $PORT 的旧进程: $OLD_PID"
  kill "$OLD_PID" 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    kill -0 "$OLD_PID" 2>/dev/null || break
    sleep 1
  done
  kill -9 "$OLD_PID" 2>/dev/null || true
fi

# ---- 3. 启动新的 dsh web ----------------------------------------------------
echo "[build-run] 启动 dsh web (端口 $PORT)，日志: /tmp/dsh-web-$PORT.log"
nohup "$NODE_BIN" --import tsx/esm apps/cli/src/bin.ts web --no-open --port "$PORT" \
  > "/tmp/dsh-web-$PORT.log" 2>&1 &

# ---- 4. 等它真正监听 --------------------------------------------------------
echo -n "[build-run] 等待服务就绪"
for _ in $(seq 1 40); do
  if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo ""
    echo "[build-run] ✅ dsh web 已就绪: http://127.0.0.1:$PORT"
    echo "[build-run] 现在请运行 ./run-dsh-electron.sh 打开 Electron 窗口，"
    echo "[build-run] 并在窗口里硬刷新一次 (Ctrl+Shift+R)。"
    exit 0
  fi
  echo -n "."
  sleep 1
done

echo ""
echo "[build-run] ❌ 等待超时，服务未监听 $PORT。查看日志: /tmp/dsh-web-$PORT.log" >&2
exit 1
