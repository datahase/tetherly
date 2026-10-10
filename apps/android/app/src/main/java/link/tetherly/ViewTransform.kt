package link.tetherly

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** A rectangle in view pixels. */
data class Box(val left: Float, val top: Float, val width: Float, val height: Float) {
    companion object {
        /** The largest rect with the video's aspect ratio, centered in the view. */
        fun letterbox(viewW: Float, viewH: Float, videoW: Float, videoH: Float): Box {
            val s = min(viewW / videoW, viewH / videoH)
            val w = videoW * s
            val h = videoH * s
            return Box((viewW - w) / 2, (viewH - h) / 2, w, h)
        }
    }
}

/** Local zoom of the video view: a view point p is drawn at p * scale + (x, y). Nothing here reaches the Mac. */
data class Zoom(val scale: Float = 1f, val x: Float = 0f, val y: Float = 0f) {
    val zoomed get() = scale > 1.001f
}

class ViewTransform(private val viewW: Float, private val viewH: Float, val content: Box) {
    /** Scale within 1..MAX; on each axis the zoomed video either covers the view edge to edge or is centered. */
    fun clamp(z: Zoom): Zoom {
        val s = z.scale.coerceIn(1f, MAX_SCALE)
        fun axis(offset: Float, start: Float, length: Float, view: Float): Float {
            val size = length * s
            return if (size <= view) (view - size) / 2 - start * s else offset.coerceIn(view - (start + length) * s, -start * s)
        }
        return Zoom(s, axis(z.x, content.left, content.width, viewW), axis(z.y, content.top, content.height, viewH))
    }

    /** Zooms by [factor] about the focal point (the point under the fingers stays put), then pans by (dx, dy). */
    fun pinch(z: Zoom, factor: Float, fx: Float, fy: Float, dx: Float, dy: Float): Zoom {
        val s = (z.scale * factor).coerceIn(1f, MAX_SCALE)
        val k = s / z.scale
        return clamp(Zoom(s, fx - (fx - z.x) * k + dx, fy - (fy - z.y) * k + dy))
    }

    /** View point → normalized video point, or null when the touch is outside the video. */
    fun toVideo(z: Zoom, vx: Float, vy: Float): Pair<Float, Float>? {
        val nx = ((vx - z.x) / z.scale - content.left) / content.width
        val ny = ((vy - z.y) / z.scale - content.top) / content.height
        return if (nx in 0f..1f && ny in 0f..1f) nx to ny else null
    }

    fun toView(z: Zoom, nx: Float, ny: Float): Pair<Float, Float> =
        (content.left + nx * content.width) * z.scale + z.x to (content.top + ny * content.height) * z.scale + z.y

    /** Smallest pan that keeps the Mac cursor inside the view with [margin] on each side. */
    fun follow(z: Zoom, nx: Float, ny: Float, margin: Float = 0.15f): Zoom {
        if (!z.zoomed) return z
        val (cx, cy) = toView(z, nx, ny)
        fun shift(c: Float, view: Float): Float {
            val m = view * margin
            return when {
                c < m -> m - c
                c > view - m -> view - m - c
                else -> 0f
            }
        }
        return clamp(z.copy(x = z.x + shift(cx, viewW), y = z.y + shift(cy, viewH)))
    }

    companion object {
        const val MAX_SCALE = 5f
    }
}

enum class TwoFinger { Undecided, Zoom, Scroll }

/**
 * Decides once per gesture: a clear change in finger spread means zoom/pan, centroid travel first means scroll.
 * The small floor keeps finger jitter on a narrow pinch from reading as zoom.
 */
fun classifyTwoFinger(startSpan: Float, span: Float, travel: Float): TwoFinger {
    val zoomThreshold = max(min(startSpan * 0.08f, 40f), 12f)
    return when {
        abs(span - startSpan) > zoomThreshold -> TwoFinger.Zoom
        travel > 24f -> TwoFinger.Scroll
        else -> TwoFinger.Undecided
    }
}

/**
 * Three or more fingers swiping like a Mac trackpad: the macOS shortcut (always with ctrl) as a keycode, or null until
 * the fingers have travelled [threshold] along one axis. Up is Mission Control, down App Exposé, and left/right move
 * to the next/previous desktop the way the content follows the fingers.
 */
fun swipeShortcut(dx: Float, dy: Float, threshold: Float): Int? = when {
    maxOf(abs(dx), abs(dy)) < threshold -> null
    abs(dy) >= abs(dx) -> if (dy < 0) MacKeys.UP else MacKeys.DOWN
    else -> if (dx < 0) MacKeys.RIGHT else MacKeys.LEFT
}

/** Mac points per phone dp for a trackpad move of [distanceDp]: 1.2 when slow, rising gently to at most 2×. */
fun trackpadGain(distanceDp: Float): Float = 1.2f * (1f + distanceDp / 25f).coerceAtMost(2f)
