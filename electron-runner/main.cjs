/**
 * Minimal Linux Electron launcher for DeepSeek Harness (dsh web).
 * Boots its own `dsh web` on a dedicated port/home, captures the
 * token-authenticated URL that dsh prints, then loads it in a BrowserWindow.
 * Environment:
 *   DSH_ELECTRON_NO_BOOT=1   attach to a running server (provide DSH_WEB_URL)
 *   DSH_NODE                 path to system Node (required)
 *   DSH_ELECTRON_PORT        web port (default 3088)
 *   DSH_WEB_URL              explicit URL to load (overrides auto-detected)
 *   DSH_ELECTRON_ICON        window/taskbar icon path (defaults to the
 *                            packaged Windows artwork in the repo)
 */
const { app, BrowserWindow, shell } = require("electron")
const { spawn } = require("node:child_process")
const path = require("node:path")
const { installWindowZoom, registerZoomWheelIpc } = require("./zoom-window.cjs")

const REPO = process.env.DSH_REPO || "/home/zqh/DeepSeekHarness/deepseek-harness"
const PORT = process.env.DSH_ELECTRON_PORT || "3088"
const BASE_URL = process.env.DSH_WEB_URL || `http://127.0.0.1:${PORT}`
const NO_BOOT = process.env.DSH_ELECTRON_NO_BOOT === "1"
const NODE = process.env.DSH_NODE || "node"
// Window and taskbar icon for an unpackaged launch. The packaged app takes its
// icon from the bundle, but a development run shows Electron's default unless
// the window sets one explicitly.
const ICON = process.env.DSH_ELECTRON_ICON
  || path.join(REPO, "apps", "desktop", "resources", "icon-windows.png")

let web = null
let authUrl = null

function startWeb() {
  web = spawn(NODE, ["--import", "tsx/esm", "apps/cli/src/bin.ts", "web", "--no-open", "--port", PORT], {
    cwd: REPO,
    env: process.env,
    stdio: ["ignore", "pipe", "pipe"],
  })
  let stdoutBuf = ""
  web.stdout.on("data", (c) => {
    process.stdout.write(c)
    if (!authUrl) {
      stdoutBuf += c.toString()
      const m = stdoutBuf.match(/dsh web:\s*(https?:\/\/\S+)/)
      if (m) authUrl = m[1]
    }
  })
  web.stderr.on("data", (c) => process.stderr.write(c))
  web.on("exit", () => { web = null })
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

async function waitAuth(timeoutMs) {
  const deadline = Date.now() + timeoutMs
  while (!authUrl && Date.now() < deadline) await sleep(300)
  return authUrl || BASE_URL
}

function createWindow(url) {
  const win = new BrowserWindow({
    width: 1280,
    height: 840,
    minWidth: 900,
    minHeight: 600,
    title: "DeepSeek Harness",
    icon: ICON,
    autoHideMenuBar: true,
    backgroundColor: "#141518",
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      spellcheck: false,
      // Consumes Ctrl+wheel in the page and forwards it to the zoom controller.
      preload: path.join(__dirname, "preload.cjs"),
    },
  })
  win.setMenuBarVisibility(false)
  // Ctrl+wheel up zooms in and Ctrl+wheel down zooms out along the ladder in
  // zoom.cjs; every other wheel keeps its native scrolling.
  installWindowZoom(win.webContents, {
    trace: (message) => { console.log(`[dsh-electron] zoom ${message}`) },
  })
  win.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url)
    return { action: "deny" }
  })
  win.loadURL(url)
  return win
}

async function main() {
  registerZoomWheelIpc({
    trace: (message) => { console.log(`[dsh-electron] zoom ${message}`) },
  })
  // Linux window managers read the taskbar icon from the app, not the window.
  // setDesktopName also pins the entry so the shell does not group this
  // window under the generic Electron icon.
  app.setName("DeepSeek Harness")
  if (process.platform === "linux") app.setDesktopName("deepseek-harness.desktop")
  let url = BASE_URL
  if (!NO_BOOT) {
    startWeb()
    url = await waitAuth(150000)
    console.log("[dsh-electron] loading:", url)
  } else {
    console.log("[dsh-electron] attaching to:", BASE_URL)
  }
  console.log("[dsh-electron] icon:", ICON)
  createWindow(url)
}

app.whenReady().then(main).catch((e) => { console.error(e); app.exit(1) })
app.on("window-all-closed", () => { app.quit() })
app.on("quit", () => { if (web) { try { web.kill() } catch (_) {} } })
