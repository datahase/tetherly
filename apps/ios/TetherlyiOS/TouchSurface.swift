import SwiftUI
import UIKit

/// Shared zoom state between the video view and its touch surface. Written directly by the gesture code so pinch
/// steps never read a stale value.
@MainActor @Observable
final class ZoomState {
    var zoom = Zoom()
    var following = true // auto-follow the Mac cursor until the user pans by hand
    var lastTapUp: TimeInterval = 0
}

/// Touch → Mac input, the same gestures as the Android client (SessionScreen.remoteInput):
/// one finger moves (trackpad) or points (direct); tap clicks; two quick taps double-click; two-finger tap right-clicks;
/// press and hold then slide, or double-tap and hold then slide, drags; two fingers scroll or, decided once per gesture,
/// pinch-zoom the local view.
final class TouchSurfaceView: UIView {
    var send: (([String: Any]) -> Void)?
    var transform2: ViewTransform?
    var zoomState: ZoomState?
    var direct = false
    var allowZoom = true

    private enum Phase { case idle, one, two }
    private var phase = Phase.idle
    private var startTime: TimeInterval = 0
    private var travel: CGFloat = 0
    private var moved = false
    private var dragging = false
    private var tapDrag = false
    private var maxTouches = 0
    private var startedInside = true
    private var lastPoint: CGPoint = .zero
    private var mode = TwoFinger.undecided
    private var startSpan: CGFloat = 0
    private var lastSpan: CGFloat = 0
    private var lastCentroid: CGPoint = .zero
    private var centroidTravel: CGFloat = 0
    private var longPress: DispatchWorkItem?
    private var swipeStart: CGPoint?
    private var swipeFingers = 0
    private var swiped = false
    private let slop: CGFloat = 8

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError() }

    private func active(_ event: UIEvent?) -> [UITouch] {
        (event?.allTouches ?? []).filter { $0.view === self && $0.phase != .ended && $0.phase != .cancelled }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let live = active(event)
        if phase == .idle, let t = touches.first {
            phase = .one
            startTime = t.timestamp
            travel = 0; moved = false; dragging = false; maxTouches = 1; mode = .undecided; startSpan = 0; centroidTravel = 0
            swipeStart = nil; swipeFingers = 0; swiped = false
            lastPoint = t.location(in: self)
            tapDrag = !direct && t.timestamp - (zoomState?.lastTapUp ?? 0) < 0.3
            startedInside = !direct || absolute(lastPoint)
            if !direct && !tapDrag { scheduleLongPress() }
        }
        maxTouches = max(maxTouches, live.count)
        if live.count >= 2 { phase = .two; cancelLongPress() }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let live = active(event)
        // Three or more fingers: one Mission Control / desktop switch per swipe, then nothing else this gesture.
        if maxTouches >= 3, !dragging {
            let pts = live.map { $0.location(in: self) }
            guard !pts.isEmpty else { return }
            let c = CGPoint(x: pts.map(\.x).reduce(0, +) / CGFloat(pts.count), y: pts.map(\.y).reduce(0, +) / CGFloat(pts.count))
            if pts.count != swipeFingers { swipeStart = c; swipeFingers = pts.count } // a finger landed or lifted
            moved = true
            if !swiped, pts.count >= 3, let s = swipeStart, let code = swipeShortcut(dx: c.x - s.x, dy: c.y - s.y, threshold: 48) {
                send?(["type": "key", "code": code, "modifiers": ["ctrl"]])
                swiped = true
            }
            return
        }
        if live.count >= 2, !dragging {
            let a = live[0].location(in: self), b = live[1].location(in: self)
            let centroid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let span = hypot(a.x - b.x, a.y - b.y)
            if startSpan == 0 { startSpan = span; lastSpan = span; lastCentroid = centroid }
            centroidTravel += hypot(centroid.x - lastCentroid.x, centroid.y - lastCentroid.y)
            if mode == .undecided { mode = classifyTwoFinger(startSpan: startSpan, span: span, travel: centroidTravel) }
            if mode == .zoom && (transform2 == nil || !allowZoom) { mode = .scroll } // the trackpad panel has nothing to zoom
            switch mode {
            case .zoom:
                if let t = transform2, let z = zoomState, lastSpan > 0 {
                    z.zoom = t.pinch(z.zoom, factor: span / lastSpan, fx: centroid.x, fy: centroid.y,
                                     dx: centroid.x - lastCentroid.x, dy: centroid.y - lastCentroid.y)
                    z.following = false
                    moved = true
                }
            case .scroll:
                send?(["type": "scroll", "dx": Double(centroid.x - lastCentroid.x), "dy": Double(centroid.y - lastCentroid.y)])
                moved = true
            case .undecided: break
            }
            lastSpan = span
            lastCentroid = centroid
            return
        }
        guard live.count == 1, mode == .undecided, let t = live.first else { return }
        let p = t.location(in: self), prev = lastPoint
        lastPoint = p
        let d = CGPoint(x: p.x - prev.x, y: p.y - prev.y)
        if !moved {
            travel += hypot(d.x, d.y)
            if travel > slop {
                moved = true
                cancelLongPress()
                if tapDrag, !dragging {
                    dragging = true
                    send?(["type": "button", "button": "left", "down": true])
                }
            }
        }
        guard moved || dragging else { return }
        if direct {
            if startedInside { _ = absolute(p) }
        } else {
            let k = trackpadGain(Double(hypot(d.x, d.y)))
            send?(["type": "pointer", "dx": Double(d.x) * k, "dy": Double(d.y) * k])
            zoomState?.following = true
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finishIfDone(event, cancelled: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finishIfDone(event, cancelled: true) }

    private func finishIfDone(_ event: UIEvent?, cancelled: Bool) {
        guard active(event).isEmpty, phase != .idle else { return }
        cancelLongPress()
        phase = .idle
        if dragging { return send?(["type": "button", "button": "left", "down": false]) ?? () }
        guard !moved, !cancelled else { return }
        if maxTouches >= 2 { return send?(["type": "click", "button": "right", "count": 1]) ?? () }
        if direct && !startedInside { return }
        send?(["type": "click", "button": "left", "count": 1])
        zoomState?.lastTapUp = ProcessInfo.processInfo.systemUptime
    }

    private func scheduleLongPress() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.phase == .one, !self.moved else { return }
            self.dragging = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            self.send?(["type": "button", "button": "left", "down": true])
        }
        longPress = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func cancelLongPress() { longPress?.cancel(); longPress = nil }

    /// Direct mode: view point → normalized Mac point through zoom and letterbox. False outside the video.
    @discardableResult
    private func absolute(_ p: CGPoint) -> Bool {
        guard let t = transform2, let z = zoomState, let (x, y) = t.toVideo(z.zoom, Double(p.x), Double(p.y)) else { return false }
        send?(["type": "pointer_abs", "x": x, "y": y])
        return true
    }
}

struct TouchSurface: UIViewRepresentable {
    let send: ([String: Any]) -> Void
    var transform: ViewTransform?
    var zoom: ZoomState?
    var direct = false
    var allowZoom = true

    func makeUIView(context: Context) -> TouchSurfaceView { TouchSurfaceView() }

    func updateUIView(_ v: TouchSurfaceView, context: Context) {
        v.send = send
        v.transform2 = transform
        v.zoomState = zoom
        v.direct = direct
        v.allowZoom = allowZoom
    }
}

/// The Mac screen: the display layer placed at the letterboxed, zoomed rect.
struct VideoSurface: UIViewRepresentable {
    let renderer: VideoRenderer
    var transform: ViewTransform?
    var zoom: Zoom

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.clipsToBounds = true
        v.layer.addSublayer(renderer.layer)
        return v
    }

    func updateUIView(_ v: UIView, context: Context) {
        guard let c = transform?.content else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderer.layer.frame = CGRect(x: c.left * zoom.scale + zoom.x, y: c.top * zoom.scale + zoom.y,
                                      width: c.width * zoom.scale, height: c.height * zoom.scale)
        CATransaction.commit()
    }
}

/// An invisible text input that forwards the software keyboard to the Mac: committed text as `text`, Backspace and
/// Return as macOS keycodes. The default keyboard type lets third-party keyboards (Wispr Flow) type into it too.
/// A hardware keyboard's shortcuts arrive through `pressesBegan`.
final class KeyInputView: UIView, UIKeyInput {
    var onText: ((String) -> Void)?
    var onKey: ((Int, [String]) -> Void)?
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var keyboardType: UIKeyboardType = .default

    override var canBecomeFirstResponder: Bool { true }
    var hasText: Bool { true }

    func insertText(_ text: String) {
        if text == "\n" { onKey?(MacKey.returnKey, []) } else { onText?(text) }
    }

    func deleteBackward() { onKey?(MacKey.delete, []) }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            var mods: [String] = []
            if key.modifierFlags.contains(.command) { mods.append("cmd") }
            if key.modifierFlags.contains(.shift) { mods.append("shift") }
            if key.modifierFlags.contains(.alternate) { mods.append("alt") }
            if key.modifierFlags.contains(.control) { mods.append("ctrl") }
            if let code = MacKey.fromHID[key.keyCode.rawValue], !mods.filter({ $0 != "shift" }).isEmpty || MacKey.special.contains(code) {
                onKey?(code, mods)
                handled = true
            }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }
}

struct KeyInput: UIViewRepresentable {
    @Binding var focused: Bool
    let onText: (String) -> Void
    let onKey: (Int, [String]) -> Void

    func makeUIView(context: Context) -> KeyInputView { KeyInputView() }

    func updateUIView(_ v: KeyInputView, context: Context) {
        v.onText = onText
        v.onKey = onKey
        DispatchQueue.main.async {
            if focused, !v.isFirstResponder { v.becomeFirstResponder() } else if !focused, v.isFirstResponder { v.resignFirstResponder() }
        }
    }
}

/// macOS virtual keycodes (US ANSI) and the HID usages a hardware keyboard reports.
enum MacKey {
    static let returnKey = 36, tab = 48, space = 49, delete = 51, escape = 53
    static let left = 123, right = 124, down = 125, up = 126
    static let special: Set = [returnKey, tab, delete, escape, left, right, down, up, 117, 115, 119, 116, 121]
    static let fKeys = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111] // F1…F12

    /** What fn turns a key into on a MacBook keyboard: arrows become Home, End, Page Up, Page Down; Delete deletes forward. */
    static func withFn(_ code: Int) -> Int {
        switch code {
        case left: 115
        case right: 119
        case up: 116
        case down: 121
        case delete: 117
        default: code
        }
    }

    static let fromHID: [Int: Int] = {
        var m: [Int: Int] = [:]
        let letters: [Character: Int] = ["a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
                                         "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38,
                                         "k": 40, "n": 45, "m": 46]
        for (c, code) in letters { m[0x04 + Int(c.asciiValue! - 97)] = code } // HID 0x04 = a … 0x1D = z
        let digits = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29] // 1…9, 0
        for (i, code) in digits.enumerated() { m[0x1E + i] = code }
        m[0x28] = returnKey; m[0x29] = escape; m[0x2A] = delete; m[0x2B] = tab; m[0x2C] = space
        m[0x2D] = 27; m[0x2E] = 24; m[0x2F] = 33; m[0x30] = 30; m[0x31] = 42; m[0x33] = 41; m[0x34] = 39; m[0x35] = 50
        m[0x36] = 43; m[0x37] = 47; m[0x38] = 44
        m[0x4F] = right; m[0x50] = left; m[0x51] = down; m[0x52] = up
        m[0x4A] = 115; m[0x4D] = 119; m[0x4B] = 116; m[0x4E] = 121; m[0x4C] = 117 // Home End PageUp PageDown ForwardDelete
        return m
    }()

    /// US-layout keycode for a typed character, and whether it needs Shift. Used when a sticky modifier is active.
    static func forChar(_ c: Character) -> (Int, Bool)? {
        let lower: [Character: Int] = ["a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
                                       "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
                                       "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
                                       "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50, " ": 49]
        if let code = lower[c] { return (code, false) }
        if c.isUppercase, let code = lower[Character(c.lowercased())] { return (code, true) }
        let shifted: [Character: Character] = ["!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
                                               "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/", "~": "`"]
        if let base = shifted[c], let code = lower[base] { return (code, true) }
        return nil
    }
}
