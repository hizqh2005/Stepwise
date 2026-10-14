/**
 * Forward Ctrl+wheel to the main process, which owns the window zoom factor.
 *
 * A sandboxed preload may only require Electron itself, so the channel name is
 * repeated here and must match ZOOM_WHEEL_CHANNEL in zoom-window.cjs.
 *
 * The listener runs on the capture phase and consumes the gesture, so the
 * browser's own page zoom and the page's own Ctrl+wheel handlers (the document
 * preview) do not run: one gesture changes exactly the window factor. Every
 * wheel without Ctrl keeps its native scrolling, propagation included.
 */
const { ipcRenderer } = require("electron")

const ZOOM_WHEEL_CHANNEL = "dsh-electron:zoom-wheel"

window.addEventListener(
  "wheel",
  (event) => {
    if (!event.ctrlKey || event.metaKey || event.altKey) return
    event.preventDefault()
    event.stopPropagation()
    // Raw deltas are forwarded; accumulation and the ladder live in the main
    // process so a trackpad's many small events move one ladder entry.
    ipcRenderer.send(ZOOM_WHEEL_CHANNEL, { deltaY: event.deltaY, deltaMode: event.deltaMode })
  },
  { capture: true, passive: false }
)
