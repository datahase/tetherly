import Foundation

/// Local zoom of the video view: a view point p is drawn at p * scale + (x, y). Nothing here reaches the Mac.
/// Same maths as the Android client (ViewTransform.kt).
struct Zoom: Equatable {
    var scale: Double = 1, x: Double = 0, y: Double = 0
    var zoomed: Bool { scale > 1.001 }
}

struct Rect: Equatable {
    var left: Double, top: Double, width: Double, height: Double

    /// The largest rect with the video's aspect ratio, centered in the view.
    static func letterbox(viewW: Double, viewH: Double, videoW: Double, videoH: Double) -> Rect {
        let s = min(viewW / videoW, viewH / videoH)
        let w = videoW * s, h = videoH * s
        return Rect(left: (viewW - w) / 2, top: (viewH - h) / 2, width: w, height: h)
    }
}

struct ViewTransform: Equatable {
    static let maxScale = 5.0
    let viewW: Double, viewH: Double, content: Rect

    func clamp(_ z: Zoom) -> Zoom {
        let s = min(max(z.scale, 1), Self.maxScale)
        func axis(_ offset: Double, _ start: Double, _ length: Double, _ view: Double) -> Double {
            let size = length * s
            return size <= view ? (view - size) / 2 - start * s : min(max(offset, view - (start + length) * s), -start * s)
        }
        return Zoom(scale: s, x: axis(z.x, content.left, content.width, viewW), y: axis(z.y, content.top, content.height, viewH))
    }

    /// Zooms by `factor` about the focal point (the point under the fingers stays put), then pans by (dx, dy).
    func pinch(_ z: Zoom, factor: Double, fx: Double, fy: Double, dx: Double, dy: Double) -> Zoom {
        let s = min(max(z.scale * factor, 1), Self.maxScale), k = s / z.scale
        return clamp(Zoom(scale: s, x: fx - (fx - z.x) * k + dx, y: fy - (fy - z.y) * k + dy))
    }

    /// View point → normalized video point, or nil when the touch is outside the video.
    func toVideo(_ z: Zoom, _ vx: Double, _ vy: Double) -> (Double, Double)? {
        let nx = ((vx - z.x) / z.scale - content.left) / content.width
        let ny = ((vy - z.y) / z.scale - content.top) / content.height
        return (0...1).contains(nx) && (0...1).contains(ny) ? (nx, ny) : nil
    }

    func toView(_ z: Zoom, _ nx: Double, _ ny: Double) -> (Double, Double) {
        ((content.left + nx * content.width) * z.scale + z.x, (content.top + ny * content.height) * z.scale + z.y)
    }

    /// Smallest pan that keeps the Mac cursor inside the view with `margin` on each side.
    func follow(_ z: Zoom, _ nx: Double, _ ny: Double, margin: Double = 0.15) -> Zoom {
        guard z.zoomed else { return z }
        let (cx, cy) = toView(z, nx, ny)
        func shift(_ c: Double, _ view: Double) -> Double {
            let m = view * margin
            return c < m ? m - c : c > view - m ? view - m - c : 0
        }
        return clamp(Zoom(scale: z.scale, x: z.x + shift(cx, viewW), y: z.y + shift(cy, viewH)))
    }
}

enum TwoFinger { case undecided, zoom, scroll }

/// Decides once per gesture: a clear change in finger spread means zoom/pan, centroid travel first means scroll.
func classifyTwoFinger(startSpan: Double, span: Double, travel: Double) -> TwoFinger {
    let threshold = max(min(startSpan * 0.08, 40), 12)
    if abs(span - startSpan) > threshold { return .zoom }
    return travel > 24 ? .scroll : .undecided
}

/// Three or more fingers swiping like a Mac trackpad: the macOS shortcut (always with ctrl) as a keycode, or nil
/// until the fingers have travelled `threshold` along one axis. Up is Mission Control, down App Exposé, and
/// left/right move to the next/previous desktop the way the content follows the fingers.
func swipeShortcut(dx: Double, dy: Double, threshold: Double) -> Int? {
    guard max(abs(dx), abs(dy)) >= threshold else { return nil }
    if abs(dy) >= abs(dx) { return dy < 0 ? 126 : 125 } // ctrl+up, ctrl+down
    return dx < 0 ? 124 : 123 // ctrl+right, ctrl+left
}

/// Mac points per screen point for a trackpad move of `distance` points: 1.2 when slow, rising gently to at most 2×.
func trackpadGain(_ distance: Double) -> Double { 1.2 * min(1 + distance / 25, 2) }
