/**
 * Zoom ladder and wheel accumulation for the Electron window.
 *
 * The window owns its zoom factor; Chromium's own Ctrl+wheel page zoom is
 * cancelled by the preload listener, so the ladder, the clamping, and the
 * "one notch = one entry" rule live here. Positive step counts zoom in
 * (Ctrl+wheel up), negative counts zoom out (Ctrl+wheel down).
 */

/** Zoom factors the gesture steps through, ascending. */
const ZOOM_FACTORS = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

/** Factor a window opens with. */
const DEFAULT_ZOOM_FACTOR = 1

/** Accumulated wheel delta that counts as one ladder step. */
const DELTA_PER_STEP = 100

/**
 * Tolerance for the step division, in steps. Chromium converts wheel deltas
 * through the page zoom, so a 100 pixel notch can arrive as 99.99999783; without
 * the tolerance that notch would never reach a whole step.
 */
const STEP_EPSILON = 1e-6

/** Pixels a line-mode wheel notch covers. */
const LINE_HEIGHT_PX = 16

/** Pixels a page-mode wheel notch covers. */
const PAGE_HEIGHT_PX = 800

/** Index of the ladder entry closest to an arbitrary factor. */
function nearestIndex(factor) {
  let best = 0
  let bestDistance = Number.POSITIVE_INFINITY
  for (let index = 0; index < ZOOM_FACTORS.length; index += 1) {
    const distance = Math.abs(ZOOM_FACTORS[index] - factor)
    if (distance >= bestDistance) continue
    best = index
    bestDistance = distance
  }
  return best
}

/**
 * Snap an arbitrary factor onto the ladder.
 * @param {number} factor candidate factor, possibly off-ladder or non-finite.
 * @returns {number} the closest ladder entry.
 */
function snapZoomFactor(factor) {
  if (!Number.isFinite(factor)) return DEFAULT_ZOOM_FACTOR
  return ZOOM_FACTORS[nearestIndex(factor)]
}

/**
 * Factor reached after whole ladder steps; stops at both ends.
 * @param {number} current factor in effect; an off-ladder value snaps first.
 * @param {number} steps signed step count; positive zooms in.
 * @returns {number} the resulting ladder entry.
 */
function stepZoomFactor(current, steps) {
  if (!Number.isFinite(steps) || steps === 0) return snapZoomFactor(current)
  const index = nearestIndex(snapZoomFactor(current))
  const bounded = Math.min(ZOOM_FACTORS.length - 1, Math.max(0, index + Math.trunc(steps)))
  return ZOOM_FACTORS[bounded]
}

/** Convert one wheel delta to pixels (Firefox notch wheels report lines or pages). */
function normalizedDelta(deltaY, deltaMode) {
  if (deltaMode === 1) return deltaY * LINE_HEIGHT_PX
  if (deltaMode === 2) return deltaY * PAGE_HEIGHT_PX
  return deltaY
}

/**
 * Accumulate wheel deltas into whole steps.
 *
 * A mouse wheel reports one large delta per notch while a trackpad reports
 * many small ones, so deltas add up until they cross one step; the remainder
 * below a step carries to the next event instead of being lost.
 * @returns {{ stepsFor: (deltaY: number, deltaMode?: number) => number }} the accumulator.
 */
function createWheelAccumulator() {
  let residual = 0
  return {
    stepsFor(deltaY, deltaMode = 0) {
      if (!Number.isFinite(deltaY)) return 0
      residual += normalizedDelta(deltaY, deltaMode)
      // Wheel up (negative deltaY) is positive, i.e. zoom in; Chromium's own
      // Ctrl+wheel page zoom uses the same orientation.
      const ratio = -residual / DELTA_PER_STEP
      const steps = Math.sign(ratio) * Math.floor(Math.abs(ratio) + STEP_EPSILON)
      if (steps === 0) return 0
      residual += steps * DELTA_PER_STEP
      return steps
    },
  }
}

module.exports = {
  ZOOM_FACTORS,
  DEFAULT_ZOOM_FACTOR,
  DELTA_PER_STEP,
  snapZoomFactor,
  stepZoomFactor,
  normalizedDelta,
  createWheelAccumulator,
}
