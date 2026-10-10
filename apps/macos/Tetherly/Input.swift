import AppKit
import CoreGraphics

/// Posts mouse and keyboard events for the connected device. Tracks held buttons so they can always be released.
final class InputInjector: @unchecked Sendable {
    private var held: Set<CGMouseButton> = []
    private var lastClick: (button: CGMouseButton, at: Date, point: CGPoint, count: Int)?
    var displayID = CGMainDisplayID()

    private var bounds: CGRect { CGDisplayBounds(displayID) }
    /// Where we last put the pointer. The system location lags behind posted events, so rapid relative moves must
    /// build on our own position; after a pause we re-read the real one in case the local mouse moved.
    private var tracked: (point: CGPoint, at: Date)?
    private var location: CGPoint {
        if let t = tracked, Date().timeIntervalSince(t.at) < 0.25 { return t.point }
        return CGEvent(source: nil)?.location ?? .zero
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        let b = bounds
        return CGPoint(x: min(max(p.x, b.minX), b.maxX - 1), y: min(max(p.y, b.minY), b.maxY - 1))
    }

    private func post(_ type: CGEventType, at point: CGPoint, button: CGMouseButton = .left, clickState: Int = 0) {
        tracked = (point, Date())
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button) else { return }
        if clickState > 0 { e.setIntegerValueField(.mouseEventClickState, value: Int64(clickState)) }
        e.post(tap: .cghidEventTap)
    }

    private var moveType: CGEventType {
        held.contains(.left) ? .leftMouseDragged : held.contains(.right) ? .rightMouseDragged : .mouseMoved
    }

    func move(dx: Double, dy: Double) {
        let p = location
        post(moveType, at: clamp(CGPoint(x: p.x + dx, y: p.y + dy)), button: held.contains(.right) ? .right : .left)
    }

    func moveAbsolute(x: Double, y: Double) {
        let b = bounds
        post(moveType, at: clamp(CGPoint(x: b.minX + x * b.width, y: b.minY + y * b.height)), button: held.contains(.right) ? .right : .left)
    }

    private var pressCount = 1

    /// Press or release. Presses count toward double and triple clicks like a real mouse (physical mouse or the
    /// on-screen buttons), and the release carries the same count.
    func button(_ button: CGMouseButton, down: Bool) {
        guard down != held.contains(button) else { return }
        let p = location
        if down {
            held.insert(button)
            pressCount = nextCount(button, at: p)
        } else {
            held.remove(button)
        }
        let type: CGEventType = button == .left ? (down ? .leftMouseDown : .leftMouseUp) : (down ? .rightMouseDown : .rightMouseUp)
        post(type, at: p, button: button, clickState: pressCount)
    }

    /// A full click; the click count follows the system double-click interval like a real mouse.
    func click(_ button: CGMouseButton) {
        let p = location
        let count = nextCount(button, at: p)
        let (down, up): (CGEventType, CGEventType) = button == .left ? (.leftMouseDown, .leftMouseUp) : (.rightMouseDown, .rightMouseUp)
        post(down, at: p, button: button, clickState: count)
        post(up, at: p, button: button, clickState: count)
    }

    private func nextCount(_ button: CGMouseButton, at p: CGPoint) -> Int {
        let now = Date()
        var count = 1
        if let last = lastClick, last.button == button, now.timeIntervalSince(last.at) < NSEvent.doubleClickInterval,
           hypot(last.point.x - p.x, last.point.y - p.y) < 5 {
            count = min(last.count + 1, 3)
        }
        lastClick = (button, now, p, count)
        return count
    }

    func scroll(dx: Int32, dy: Int32) {
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)?.post(tap: .cghidEventTap)
    }

    func key(code: CGKeyCode, modifiers: [String]) {
        var flags: CGEventFlags = []
        for m in modifiers {
            switch m {
            case "cmd": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "alt": flags.insert(.maskAlternate)
            case "ctrl": flags.insert(.maskControl)
            case "fn": flags.insert(.maskSecondaryFn)
            default: break
            }
        }
        // A real keyboard's arrows carry fn and numeric-pad flags, and Home/End/Page/Forward Delete carry fn; system
        // shortcuts such as Mission Control (ctrl+up) only match with them.
        if (123...126).contains(code) { flags.formUnion([.maskSecondaryFn, .maskNumericPad]) }
        if [115, 116, 117, 119, 121].contains(code) { flags.insert(.maskSecondaryFn) }
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { continue }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
    }

    /// Types Unicode text independent of the active keyboard layout.
    func type(_ text: String) {
        let units = Array(text.utf16)
        for start in stride(from: 0, to: units.count, by: 20) {
            let chunk = Array(units[start..<min(start + 20, units.count)])
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { continue }
                e.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                e.post(tap: .cghidEventTap)
            }
        }
    }

    private var fnHeld = false

    /// A bare fn press or release, as macOS reports it (a flags-changed event, keycode 63). Dictation tools such as
    /// Wispr Flow listen for exactly this, so holding fn on the phone works as push-to-talk.
    func fnKey(down: Bool) {
        guard down != fnHeld else { return }
        fnHeld = down
        guard let e = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: 63, keyDown: down) else { return }
        e.type = .flagsChanged
        e.flags = down ? .maskSecondaryFn : []
        e.post(tap: .cghidEventTap)
    }

    func releaseAll() {
        if fnHeld { fnKey(down: false) }
        for b in held { button(b, down: false) }
        held.removeAll()
        lastClick = nil
        tracked = nil
    }
}
