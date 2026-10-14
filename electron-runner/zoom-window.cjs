/**
 * Window zoom for the Electron runner: owns one zoom factor per window
 * contents and applies the Ctrl+wheel steps the preload forwards.
 *
 * Electron disables visual zoom, so the Ctrl+wheel gesture is not dispatched
 * until the visual zoom limits are raised; the preload listener then consumes
 * the gesture and this module moves the factor along the ladder from zoom.cjs
 * (positive steps zoom in, i.e. Ctrl+wheel up).
 *
 * The preload channel is the only zoom input: Chromium's own `zoom-changed`
 * event fires for the same gesture alongside the DOM event, so handling both
 * would move two ladder entries per notch.
 */
const { ipcMain } = require("electron")
const { DEFAULT_ZOOM_FACTOR, createWheelAccumulator, snapZoomFactor, stepZoomFactor } = require("./zoom.cjs")

/** Must match the channel name in preload.cjs (a sandboxed preload cannot require this file). */
const ZOOM_WHEEL_CHANNEL = "dsh-electron:zoom-wheel"

/** One controller per window contents; a reload keeps its factor. */
const controllers = new WeakMap()

/**
 * Install zoom handling on one window's contents; a second call returns the existing controller.
 * @param {import('electron').WebContents} contents window contents whose page is zoomed.
 * @param {{ trace?: (message: string) => void }} [options] optional operator-visible trace.
 * @returns {{ factor: () => number, steps: (steps: number) => number }} the window's zoom controller.
 */
function installWindowZoom(contents, options = {}) {
  const existing = controllers.get(contents)
  if (existing !== undefined) return existing
  const accumulator = createWheelAccumulator()
  let factor = DEFAULT_ZOOM_FACTOR

  const apply = (next, cause) => {
    if (next === factor) return factor
    factor = next
    contents.setZoomFactor(factor)
    options.trace?.(`${cause} zoom=${factor}`)
    return factor
  }

  // Without raised limits the gesture never reaches the page.
  contents.setVisualZoomLevelLimits(1, 3).catch((error) => {
    options.trace?.(`visual zoom limits rejected: ${String(error)}`)
  })
  contents.setZoomFactor(factor)
  contents.on("destroyed", () => { controllers.delete(contents) })
  // Chromium restores the zoom it stored for the page's origin on every load,
  // so a window reopens at the factor the user last left it on. Adopting that
  // value keeps the ladder and the page from disagreeing (and an off-ladder
  // stored value snaps onto the ladder instead of stepping from a wrong one).
  contents.on("did-finish-load", () => {
    const restored = snapZoomFactor(contents.getZoomFactor())
    if (restored === factor) return
    factor = restored
    contents.setZoomFactor(factor)
    options.trace?.(`restored zoom=${factor}`)
  })

  const controller = {
    factor: () => factor,
    steps: (steps) => apply(stepZoomFactor(factor, steps), "wheel"),
    accumulator,
  }
  controllers.set(contents, controller)
  return controller
}

/**
 * Route the preload's forwarded gestures to the sending window's controller.
 * @param {{ trace?: (message: string) => void }} [options] optional trace sink.
 */
function registerZoomWheelIpc(options = {}) {
  ipcMain.on(ZOOM_WHEEL_CHANNEL, (event, payload) => {
    const controller = controllers.get(event.sender)
    if (controller === undefined || payload === null || typeof payload !== "object") return
    const { deltaY, deltaMode } = payload
    if (typeof deltaY !== "number") return
    const steps = controller.accumulator.stepsFor(deltaY, typeof deltaMode === "number" ? deltaMode : 0)
    if (steps === 0) return
    controller.steps(steps)
  })
}

module.exports = { ZOOM_WHEEL_CHANNEL, installWindowZoom, registerZoomWheelIpc }
