import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct SessionView: View {
    let model: SessionModel
    @State private var zoom = ZoomState()
    @State private var direct = false
    @State private var keyboard = false
    @State private var keysOpen = false
    @State private var mods: Set<String> = []
    @State private var orientation: Orientation = .auto
    @State private var toolbarVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var showGestures = false
    @State private var pickingFile = false
    @State private var pickingFolder = false
    @State private var mouse = MouseBridge()
    @Environment(\.verticalSizeClass) private var vSize

    private var landscape: Bool { vSize == .compact }
    private var send: ([String: Any]) -> Void { { model.engine?.send($0) } }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Brand.ink.ignoresSafeArea()
                VStack(spacing: 0) {
                    if !landscape { toolbarAndNotices.padding(.top, 8).padding(.bottom, 8) }
                    content(size: geo.size)
                    if keyboard || keysOpen {
                        KeyBar(mods: $mods, special: special, shortcut: { send(["type": "key", "code": $0, "modifiers": $1]) },
                               fnPress: { send(["type": "modifier", "key": "fn", "down": $0]) })
                    }
                }
                if landscape {
                    VStack(spacing: 8) {
                        if toolbarVisible { toolbarAndNotices.transition(.opacity) } else {
                            Button { poke() } label: { Image(systemName: "chevron.compact.down").frame(width: 44, height: 32) }
                                .background(Brand.surfaceHigh.opacity(0.5), in: Capsule()).foregroundStyle(Brand.onSurface)
                                .accessibilityLabel("Show controls")
                        }
                    }
                    .padding(.top, 8)
                }
                KeyInput(focused: $keyboard, onText: typed, onKey: { code, m in send(["type": "key", "code": code, "modifiers": m]) })
                    .frame(width: 1, height: 1).opacity(0.01)
            }
        }
        .statusBarHidden(landscape)
        .persistentSystemOverlays(landscape ? .hidden : .automatic)
        .onAppear {
            mouse.send = send
            orientation.apply()
            poke()
        }
        .onDisappear { Orientation.auto.apply() }
        .onChange(of: landscape) { poke() }
        .onChange(of: model.cursor) {
            guard let c = model.cursor, !direct, zoom.following, let t = transformForFollow else { return }
            zoom.zoom = t.follow(zoom.zoom, Double(c.x), Double(c.y))
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { model.engine?.sendFile(url) }
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            model.offer = nil
            if case .success(let url) = result { model.engine?.answerOffer(folder: url) } else { model.engine?.answerOffer(folder: nil) }
        }
        .alert("Receive a file from your Mac?", isPresented: Binding(get: { model.offer != nil && !pickingFolder }, set: { _ in })) {
            Button("Choose folder") { pickingFolder = true }
            Button("Decline", role: .cancel) { model.offer = nil; model.engine?.answerOffer(folder: nil) }
        } message: {
            if let o = model.offer { Text("\(o.name), \(ByteCountFormatter.string(fromByteCount: o.size, countStyle: .file)). Choose where to save it.") }
        }
        .sheet(isPresented: $showGestures) { GesturesSheet().presentationDetents([.medium, .large]) }
    }

    @State private var transformForFollow: ViewTransform?

    // MARK: Layout

    @ViewBuilder
    private func content(size: CGSize) -> some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let v = model.videoSize ?? CGSize(width: 16, height: 10)
            let aspect = v.width / v.height
            let panel = h - w / aspect
            let side = (w - h * aspect) / 2
            // While the keyboard is open, the screen and the key bar get the space; the mouse controls return after.
            if keyboard {
                videoArea
            } else if !landscape && panel >= 180 {
                VStack(spacing: 0) {
                    videoArea.frame(height: w / aspect)
                    TrackpadPanel(send: send).padding(12)
                }
            } else if landscape && side >= 72 {
                HStack(spacing: 0) {
                    ScrollStrip(vertical: true, send: send).padding(8).frame(width: side)
                    videoArea
                    VStack(spacing: 8) {
                        MouseButton(label: "Left", wire: "left", send: send)
                        MouseButton(label: "Right", wire: "right", send: send)
                        ScrollStrip(vertical: false, send: send).frame(height: 64)
                    }
                    .padding(8).frame(width: side)
                }
            } else {
                videoArea
            }
        }
    }

    private var loaderHost: String? {
        switch model.state {
        case .connected(let host, _), .reconnecting(let host, _, _): host
        default: nil
        }
    }

    private var videoArea: some View {
        GeometryReader { g in
            let t = model.videoSize.map { v in
                ViewTransform(viewW: g.size.width, viewH: g.size.height,
                              content: Rect.letterbox(viewW: g.size.width, viewH: g.size.height, videoW: v.width, videoH: v.height))
            }
            ZStack {
                VideoSurface(renderer: model.renderer, transform: t, zoom: zoom.zoom)
                if model.videoSize == nil { SessionLoader(host: loaderHost) }
                TouchSurface(send: { m in if landscape { toolbarVisible = false }; send(m) }, transform: t, zoom: zoom, direct: direct)
            }
            .onAppear { transformForFollow = t }
            .onChange(of: g.size) { zoom.zoom = Zoom(); transformForFollow = t }
            .onChange(of: model.videoSize) { zoom.zoom = Zoom(); transformForFollow = t }
        }
        .clipped()
    }

    private var toolbarAndNotices: some View {
        VStack(spacing: 8) {
            Toolbar(model: model, landscape: landscape, direct: $direct, keyboard: $keyboard, keysOpen: $keysOpen, orientation: $orientation, zoom: zoom,
                    mouse: mouse, poke: poke, showGestures: $showGestures, pickFile: { pickingFile = true })
            VStack(spacing: 8) {
                if case .reconnecting(_, let attempt, let reason) = model.state {
                    Banner(text: "Connection lost. \(reason) Retrying, attempt \(attempt).", action: "Stop") { model.engine?.disconnect() }
                }
                if let v = model.videoStopped { Banner(text: v, action: "Retry video") { model.engine?.retryVideo() } }
                if let n = model.notice { Banner(text: n, action: "Dismiss") { model.notice = nil } }
                if let t = model.outgoing { TransferCard(label: "Sending to Mac", t: t) { t.active ? model.engine?.cancelTransfer(outgoing: true) : (model.outgoing = nil) } }
                if let t = model.incoming { TransferCard(label: "Receiving from Mac", t: t) { t.active ? model.engine?.cancelTransfer(outgoing: false) : (model.incoming = nil) } }
            }
            .frame(maxWidth: 560).padding(.horizontal, 12)
        }
    }

    private func poke() {
        toolbarVisible = true
        hideTask?.cancel()
        guard landscape else { return }
        hideTask = Task { try? await Task.sleep(for: .seconds(3.5)); if !Task.isCancelled { withAnimation { toolbarVisible = false } } }
    }

    // MARK: Keys

    /// Sticky modifiers apply to the next key only. With a modifier active, a character becomes a key press.
    private func typed(_ text: String) {
        guard !mods.isEmpty else {
            for chunk in text.chunked(1000) { send(["type": "text", "text": chunk]) }
            return
        }
        if text.count == 1, let (code, shift) = MacKey.forChar(text.first!) {
            send(["type": "key", "code": code, "modifiers": Array(shift ? mods.union(["shift"]) : mods)])
        } else {
            send(["type": "text", "text": text])
        }
        mods = []
    }

    private func special(_ code: Int) {
        send(["type": "key", "code": mods.contains("fn") ? MacKey.withFn(code) : code, "modifiers": Array(mods)])
        mods = []
    }
}

private extension String {
    func chunked(_ n: Int) -> [String] {
        var out: [String] = [], current = ""
        for ch in self {
            if current.utf16.count + String(ch).utf16.count > n { out.append(current); current = "" }
            current.append(ch)
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

// MARK: - Toolbar

private struct Toolbar: View {
    let model: SessionModel
    let landscape: Bool
    @Binding var direct: Bool
    @Binding var keyboard: Bool
    @Binding var keysOpen: Bool
    @Binding var orientation: Orientation
    let zoom: ZoomState
    let mouse: MouseBridge
    let poke: () -> Void
    @Binding var showGestures: Bool
    let pickFile: () -> Void

    private var title: (String, String?) {
        switch model.state {
        case .connected(let host, let address):
            (host, isTailscaleHost(HostAddress.parse(address)?.host ?? address) ? "via Tailscale" : "via Wi-Fi")
        case .reconnecting(let host, _, _): ("Reconnecting to \(host)", nil)
        default: ("", nil)
        }
    }

    var body: some View {
      // Scrolls on narrow screens so every control stays reachable; Disconnect stays pinned outside it.
      HStack(spacing: 2) {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title.0).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let r = title.1 { Text(r).font(.caption2).foregroundStyle(Brand.onSurfaceVariant) }
                }
                .frame(maxWidth: 110, alignment: .leading).padding(.leading, 16).padding(.trailing, 4)
                tool("rectangle.3.group", "Mission Control: show all windows") { model.engine?.send(["type": "key", "code": 126, "modifiers": ["ctrl"]]) }
                tool(model.macSound ? "speaker.wave.2.fill" : "speaker.slash", model.macSound ? "Mute Mac sound" : "Play Mac sound", selected: model.macSound) {
                    model.toggleMacSound()
                }
                tool(keyboard ? "keyboard.chevron.compact.down" : "keyboard", keyboard ? "Hide keyboard" : "Show keyboard") { keyboard.toggle() }
                tool("command", keysOpen ? "Hide Mac keys" : "Show Mac keys", selected: keysOpen) { keysOpen.toggle() }
                tool(direct ? "hand.point.up.left" : "hand.draw", direct ? "Direct touch, switch to trackpad" : "Trackpad, switch to direct touch") { direct.toggle() }
                if mouse.connected {
                    tool("computermouse", mouse.enabled ? "Mouse controls the Mac. Tap to release" : "Use mouse for the Mac", selected: mouse.enabled) { mouse.enabled.toggle() }
                }
                if zoom.zoom.zoomed { tool("arrow.down.right.and.arrow.up.left", "Fit screen") { zoom.zoom = Zoom(); zoom.following = true } }
                // One toggle: switches to the other orientation and locks it. Sessions start on the system's rotation.
                tool(landscape ? "rectangle.portrait" : "rectangle", landscape ? "Switch to portrait" : "Switch to landscape") {
                    orientation = landscape ? .portrait : .landscape
                    orientation.apply()
                }
                Menu {
                    Button { model.engine?.sendClipboard(UIPasteboard.general.string ?? "") } label: { Label("Send clipboard to Mac", systemImage: "doc.on.clipboard") }
                    Button { model.engine?.requestClipboard() } label: { Label("Get Mac clipboard", systemImage: "clipboard") }
                    Button { pickFile() } label: { Label("Send file", systemImage: "arrow.up.doc") }
                    Divider()
                    Picker("Quality", selection: Binding(get: { model.settings.maxDimension }, set: { model.setVideo(VideoSettings(maxDimension: $0, fps: model.settings.fps)) })) {
                        ForEach([1920, 1280, 960], id: \.self) { Text("Quality \($0)p").tag($0) }
                    }
                    Picker("Frame rate", selection: Binding(get: { model.settings.fps }, set: { model.setVideo(VideoSettings(maxDimension: model.settings.maxDimension, fps: $0)) })) {
                        ForEach([model.maxFps] + [60, 30].filter { $0 < model.maxFps }, id: \.self) { f in
                            Text(f == model.maxFps ? "Smoothest, up to \(f) fps" : "\(f) fps").tag(f)
                        }
                    }
                    Divider()
                    Button { showGestures = true } label: { Label("Gestures", systemImage: "hand.tap") }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
                .accessibilityLabel("More")
            }
            .foregroundStyle(Brand.onSurface)
        }
        Button { model.engine?.disconnect() } label: {
            Image(systemName: "power").font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.onErrorContainer)
                .frame(width: 36, height: 36).background(Brand.errorContainer, in: Circle())
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Disconnect")
        .padding(.trailing, 2)
      }
        .fixedSize(horizontal: false, vertical: true)
        .background(Brand.surfaceHigh.opacity(0.8), in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        .padding(.horizontal, 12)
        .simultaneousGesture(TapGesture().onEnded { poke() })
    }

    private func tool(_ symbol: String, _ label: String, selected: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                .foregroundStyle(selected ? Brand.primary : Brand.onSurface).frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Panels

/// Laptop-style trackpad for the space under the Mac screen: surface, scroll strips and click buttons.
private struct TrackpadPanel: View {
    let send: ([String: Any]) -> Void
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Brand.surface)
                    Text("Trackpad").font(.subheadline.weight(.medium)).foregroundStyle(Brand.onSurfaceVariant.opacity(0.6))
                    TouchSurface(send: send, allowZoom: false)
                }
                ScrollStrip(vertical: true, send: send).frame(width: 56)
            }
            ScrollStrip(vertical: false, send: send).frame(height: 48)
            HStack(spacing: 8) {
                MouseButton(label: "Left", wire: "left", send: send)
                MouseButton(label: "Right", wire: "right", send: send)
            }
            .frame(height: 56)
        }
    }
}

/// Drag along the strip to scroll the Mac; content follows the finger, like two-finger scrolling.
private struct ScrollStrip: View {
    let vertical: Bool
    let send: ([String: Any]) -> Void
    @State private var last: CGPoint?

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(last == nil ? Brand.surfaceHigh : Brand.primaryContainer)
            .overlay { Image(systemName: vertical ? "arrow.up.arrow.down" : "arrow.left.arrow.right").foregroundStyle(Brand.onSurfaceVariant) }
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let p = g.location
                if let l = last {
                    let d = vertical ? (p.y - l.y) : (p.x - l.x)
                    send(["type": "scroll", "dx": vertical ? 0 : Double(d) * 1.6, "dy": vertical ? Double(d) * 1.6 : 0])
                }
                last = p
            }.onEnded { _ in last = nil })
            .accessibilityLabel(vertical ? "Vertical scroll strip" : "Horizontal scroll strip")
    }
}

/// A physical-style mouse button: press sends button down, release sends button up, so holding it drags.
private struct MouseButton: View {
    let label: String, wire: String
    let send: ([String: Any]) -> Void
    @State private var pressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(pressed ? Brand.primary : Brand.surfaceHigh)
            .overlay { Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(pressed ? Brand.onPrimary : Brand.onSurface) }
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in
                guard !pressed else { return }
                pressed = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                send(["type": "button", "button": wire, "down": true])
            }.onEnded { _ in
                pressed = false
                send(["type": "button", "button": wire, "down": false])
            })
            .accessibilityLabel("\(label) mouse button")
            .accessibilityAddTraits(.isButton)
    }
}

private struct KeyBar: View {
    @Binding var mods: Set<String>
    let special: (Int) -> Void
    let shortcut: (Int, [String]) -> Void
    let fnPress: (Bool) -> Void

    private let modifiers = [("fn", "fn"), ("cmd", "⌘ Cmd"), ("shift", "⇧ Shift"), ("alt", "⌥ Opt"), ("ctrl", "⌃ Ctrl")]
    private let keys = [("Esc", MacKey.escape), ("Tab", MacKey.tab), ("←", MacKey.left), ("→", MacKey.right), ("↑", MacKey.up),
                        ("↓", MacKey.down), ("⌫", MacKey.delete), ("⏎", MacKey.returnKey)]
    private let shortcuts: [(String, Int, [String])] = [("⌘C", 8, ["cmd"]), ("⌘V", 9, ["cmd"]), ("⌘X", 7, ["cmd"]), ("⌘Z", 6, ["cmd"]),
                                                        ("⌘A", 0, ["cmd"]), ("⌘Tab", MacKey.tab, ["cmd"]), ("⌘Space", MacKey.space, ["cmd"]),
                                                        ("⌘W", 13, ["cmd"]), ("⌘Q", 12, ["cmd"]), ("Mission Control", MacKey.up, ["ctrl"])]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FnChip(selected: mods.contains("fn"), toggle: { if mods.contains("fn") { mods.remove("fn") } else { mods.insert("fn") } }, press: fnPress)
                ForEach(modifiers.filter { $0.0 != "fn" }, id: \.0) { wire, label in
                    chip(label, selected: mods.contains(wire)) { if mods.contains(wire) { mods.remove(wire) } else { mods.insert(wire) } }
                }
                // fn shows the function keys, like the top row of a MacBook.
                if mods.contains("fn") {
                    ForEach(Array(MacKey.fKeys.enumerated()), id: \.offset) { i, code in chip("F\(i + 1)") { special(code) } }
                }
                ForEach(keys, id: \.0) { label, code in chip(label) { special(code) } }
                ForEach(shortcuts, id: \.0) { label, code, m in chip(label) { shortcut(code, m) } }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
        }
        .background(Brand.surface)
    }

    private func chip(_ text: String, selected: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.subheadline.weight(.medium)).padding(.horizontal, 12).frame(minHeight: 36)
                .foregroundStyle(selected ? Brand.onPrimaryContainer : Brand.onSurface)
                .background(selected ? Brand.primaryContainer : Brand.surfaceHigh, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// The fn key behaves like the real one: touching sends fn down and lifting sends fn up, so holding it is push-to-talk
/// for dictation apps on the Mac. A quick tap also makes fn sticky for the next key (fn + arrows, F1-F12).
private struct FnChip: View {
    let selected: Bool
    let toggle: () -> Void
    let press: (Bool) -> Void
    @State private var downAt: Date?

    var body: some View {
        Text("fn").font(.subheadline.weight(.semibold)).padding(.horizontal, 16).frame(minHeight: 36)
            .foregroundStyle(downAt != nil ? Brand.onPrimary : selected ? Brand.onPrimaryContainer : Brand.onSurface)
            .background(downAt != nil ? Brand.primary : selected ? Brand.primaryContainer : Brand.surfaceHigh, in: RoundedRectangle(cornerRadius: 12))
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in
                guard downAt == nil else { return }
                downAt = Date()
                press(true)
            }.onEnded { _ in
                press(false)
                if let d = downAt, Date().timeIntervalSince(d) < 0.4 { toggle() }
                downAt = nil
            })
            .accessibilityLabel("fn key")
            .accessibilityAddTraits(.isButton)
    }
}

private struct Banner: View {
    let text: String, action: String
    let onAction: () -> Void
    var body: some View {
        HStack {
            Text(text).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            Button(action, action: onAction).font(.footnote.weight(.semibold))
        }
        .foregroundStyle(Brand.onSurface)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Brand.surfaceHighest.opacity(0.96), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct TransferCard: View {
    let label: String
    let t: TransferInfo
    let onAction: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(label): \(t.name)").font(.subheadline).lineLimit(1).truncationMode(.middle)
                    Text(t.status).font(.caption).foregroundStyle(Brand.onSurfaceVariant)
                }
                Spacer()
                Button(t.active ? "Cancel" : "OK", action: onAction).font(.subheadline.weight(.semibold))
            }
            if t.active { ProgressView(value: t.size == 0 ? 0 : Double(t.done) / Double(t.size)).tint(Brand.primary) }
        }
        .foregroundStyle(Brand.onSurface)
        .padding(14)
        .background(Brand.surfaceHigh.opacity(0.96), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct GesturesSheet: View {
    var body: some View {
        List {
            ForEach([("Move", "Slide one finger"), ("Click", "Tap"), ("Double-click", "Tap twice quickly"), ("Right-click", "Tap with two fingers"),
                     ("Drag", "Double-tap and hold, then slide. Or press and hold, then slide."), ("Scroll", "Slide two fingers, or use the scroll strips"),
                     ("Zoom this view", "Pinch with two fingers. Fit resets it."), ("Mouse", "Connect a mouse to control the Mac directly")], id: \.0) { what, how in
                VStack(alignment: .leading, spacing: 2) {
                    Text(what).font(.headline)
                    Text(how).font(.subheadline).foregroundStyle(Brand.onSurfaceVariant)
                }
            }
        }
        .navigationTitle("Trackpad gestures")
    }
}

/// Shown until the first video frame arrives.
private struct SessionLoader: View {
    let host: String?

    var body: some View {
        VStack(spacing: 16) {
            LoaderRing(accent: Brand.orange, content: Brand.cream)
            VStack(spacing: 4) {
                Text(host.map { "Opening \($0)" } ?? "Opening your Mac").font(.headline).foregroundStyle(Brand.cream)
                Text("Starting the screen stream").font(.subheadline).foregroundStyle(Brand.cream.opacity(0.6))
            }
        }
        .padding(24)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

/// The one loading mark for connecting and opening a session: the Mac tile breathes inside a thin spinning ring.
struct LoaderRing: View {
    let accent: Color
    let content: Color
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle().fill(accent.opacity(0.10)).frame(width: 104, height: 104).scaleEffect(animate ? 1.08 : 0.9)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: animate)
            Circle().stroke(content.opacity(0.08), lineWidth: 2).frame(width: 84, height: 84)
            Circle().trim(from: 0, to: 0.28).stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 84, height: 84).rotationEffect(.degrees(animate ? 360 : 0))
                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: animate)
            Image(systemName: "desktopcomputer").font(.system(size: 24)).foregroundStyle(content)
                .frame(width: 56, height: 56).background(content.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        }
        .frame(width: 104, height: 104)
        .accessibilityHidden(true)
        .onAppear { animate = true }
    }
}
