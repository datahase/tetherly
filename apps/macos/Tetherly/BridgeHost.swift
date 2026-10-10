import AppKit
import CryptoKit
import Foundation
import Network

/// The Mac side of protocol/SPEC.md. Every field and method is confined to `queue`; UI talks to it through the
/// closures below, which are always invoked on the main actor.
final class BridgeHost: @unchecked Sendable {
    static let port: NWEndpoint.Port = 47800

    struct Snapshot: Sendable {
        struct Device: Sendable, Identifiable { let id: String, name: String, pairedAt: Date }
        struct Transfer: Sendable, Identifiable { let id: String, name: String, size: Int64, done: Int64, incoming: Bool, state: String }
        var hosting = false
        var hostPin = Data()
        var hostName = ""
        var listener = "Off"
        var pairingUntil: Date?
        var pairingDevice: String?
        var pairingCode: [Int]?
        var sessionDevice: String?
        var sessionSince: Date?
        var videoActive = false
        var devices: [Device] = []
        var transfers: [Transfer] = []
        var lastEvent: String?
        var audioOut = false
    }

    var onSnapshot: (@MainActor @Sendable (Snapshot) -> Void)?
    var askPairing: (@MainActor @Sendable (_ device: String, _ code: [Int], _ reply: @escaping @Sendable (Bool) -> Void) -> Void)?
    var pairingEnded: (@MainActor @Sendable () -> Void)?
    var askSaveLocation: (@MainActor @Sendable (_ name: String, _ size: Int64, _ device: String, _ reply: @escaping @Sendable (URL?) -> Void) -> Void)?

    let queue = DispatchQueue(label: "link.tetherly.host", qos: .userInitiated)
    private let identity: HostIdentity
    private var listener: NWListener?
    private var listenerState = "Off"
    private var peers: [UUID: Peer] = [:]
    private var awaitingHello: Set<UUID> = []
    private let trust = TrustStore(url: TrustStore.defaultURL)
    private var pairingUntil: Date?
    private var pairingFailures = 0
    private var pairing: PairingExchange?
    private var axLostNotified = false
    private var session: Session?
    private var tickets: [Data: Ticket] = [:]
    private let input = InputInjector()
    private lazy var encoder = makeEncoder()
    private var timer: DispatchSourceTimer?
    private var cursorTimer: DispatchSourceTimer?
    private var lastEvent: String?
    private let audioCapture = SystemAudioCapture()

    private static let maxConnections = 8
    /// One source address may hold at most this many connections, so a single LAN or tailnet peer cannot fill the cap.
    private static let maxPerSource = 4 // control + video + file, plus a brief overlap while reconnecting
    private static let inputTypes: Set = ["pointer", "pointer_abs", "button", "click", "scroll", "key", "text", "modifier"]

    init(identity: HostIdentity) {
        self.identity = identity
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
        let c = DispatchSource.makeTimerSource(queue: queue)
        c.schedule(deadline: .now() + 1, repeating: 1.0 / 60)
        c.setEventHandler { [weak self] in self?.sendCursor() }
        c.resume()
        cursorTimer = c
    }

    // MARK: - Public controls (any thread)

    func setHosting(_ on: Bool) { queue.async { on ? self.startListener() : self.stopHosting() } }
    func startPairing() { queue.async { self.openPairingWindow() } }
    func stopPairing() { queue.async { self.closePairingWindow(event: "Pairing mode closed") } }
    func disconnect() { queue.async { self.session.map { self.teardown($0, code: nil, event: "Disconnected from this Mac") } } }
    func revoke(_ pinHex: String) { queue.async { self.revokeDevice(pinHex) } }
    func offerFile(_ url: URL) { queue.async { self.startOutgoing(url) } }
    func cancelTransfer(_ id: String) { queue.async { self.cancelTransfer(id: id, notifyPeer: true) } }
    func displayChanged() { queue.async { self.handleDisplayChange() } }
    func refresh() { queue.async { self.publish() } }

    // MARK: - Listener

    private func startListener() {
        guard listener == nil else { return }
        let tls = NWProtocolTLS.Options()
        let o = tls.securityProtocolOptions
        sec_protocol_options_set_local_identity(o, identity.identity)
        sec_protocol_options_set_min_tls_protocol_version(o, .TLSv13)
        sec_protocol_options_set_peer_authentication_required(o, true)
        sec_protocol_options_set_verify_block(o, { [weak self] _, trust, complete in
            // Admit approved pins, or unknown P-256 pins only while pairing mode is open and idle. Fail closed.
            let leaf = (SecTrustCopyCertificateChain(sec_trust_copy_ref(trust).takeRetainedValue()) as? [SecCertificate])?.first
            guard let self, let leaf, let pin = SPKI.pin(of: leaf) else { return complete(false) }
            complete(self.trust.isApproved(pin) || self.pairingAdmits)
        }, queue)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        let params = NWParameters(tls: tls, tcp: tcp)
        do {
            let l = try NWListener(using: params, on: Self.port)
            l.service = NWListener.Service(name: Host.current().localizedName ?? "Mac", type: "_tetherly._tcp")
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready: self.listenerState = "Listening on port \(Self.port)"
                case .failed(let e): self.listenerState = "Failed: \(e.localizedDescription)"; self.listener?.cancel(); self.listener = nil
                case .cancelled: self.listenerState = "Off"
                default: break
                }
                self.publish()
            }
            listener = l
            l.start(queue: queue)
        } catch {
            listenerState = "Failed: \(error.localizedDescription)"
        }
        publish()
    }

    private func stopHosting() {
        session.map { teardown($0, code: "bye", event: "Hosting disabled") }
        abortPairing(event: nil)
        pairingUntil = nil
        listener?.cancel()
        listener = nil
        for p in peers.values { p.close() }
        peers.removeAll()
        awaitingHello.removeAll()
        listenerState = "Off"
        publish()
    }

    private var pairingAdmits: Bool { (pairingUntil.map { $0 > Date() } ?? false) && pairing == nil }

    private func accept(_ c: NWConnection) {
        guard peers.count < Self.maxConnections,
              peers.values.filter({ Self.source($0.connection) == Self.source(c) }).count < Self.maxPerSource
        else { return c.cancel() }
        let p = Peer(c, queue: queue)
        peers[p.id] = p
        // The hello deadline starts at accept, so a peer that stalls mid-handshake is dropped too (SPEC §3).
        awaitingHello.insert(p.id)
        p.onFrame = { [weak self] p, f in self?.received(f, from: p) }
        p.onClose = { [weak self] p, _ in self?.closed(p) }
        p.start()
    }

    // MARK: - Routing

    private func received(_ frame: Frame, from p: Peer) {
        if awaitingHello.contains(p.id) {
            guard case .json(let m) = frame, m["type"] as? String == "hello" else { return p.close(ProtocolError(code: "malformed", message: "expected hello")) }
            awaitingHello.remove(p.id)
            return hello(m, from: p)
        }
        if let s = session, s.control === p, case .json(let m) = frame { return control(m, s) }
        // The audio channel only carries Mac sound to the phone; nothing is accepted on it.
        if let s = session, s.audio === p { return p.close(.unknownType) }
        if let x = pairing, x.peer === p, case .json(let m) = frame { return pairingMessage(m, x) }
        if let s = session, let t = [s.incoming, s.outgoing].compactMap({ $0 }).first(where: { $0.peer === p }) { return fileFrame(frame, t, s) }
        p.close(ProtocolError.unknownType)
    }

    private func closed(_ p: Peer) {
        peers[p.id] = nil
        awaitingHello.remove(p.id)
        if let s = session {
            if s.control === p { teardown(s, code: nil, event: "\(s.device) disconnected") }
            else if s.video === p { s.video = nil; encoder.stop(); publish() }
            else if s.audio === p { s.audio = nil; audioCapture.stop(); publish() }
            else if let t = [s.incoming, s.outgoing].compactMap({ $0 }).first(where: { $0.peer === p }), !t.finished {
                failTransfer(t, s, "Connection lost")
            }
        }
        if let x = pairing, x.peer === p { abortPairing(event: "Pairing cancelled") }
    }

    private func hello(_ m: [String: Any], from p: Peer) {
        guard let versions = m["versions"] as? [Int], versions.contains(1) else {
            return p.close(ProtocolError(code: "unsupported_version", message: "This Mac speaks protocol version 1"))
        }
        guard let kind = (m["kind"] as? String).flatMap(ConnKind.init), let pin = p.pin else { return p.close(.malformed) }
        p.kind = kind
        switch kind {
        case .control:
            let device = String((m["device"] as? String ?? "Android device").prefix(64))
            if trust.isApproved(pin) {
                if let s = session {
                    guard s.pin == pin else { return p.close(ProtocolError(code: "busy", message: "Another device is connected")) }
                    teardown(s, code: nil, event: nil) // same device reconnecting replaces its old session
                }
                let s = Session(control: p, pin: pin, device: trust.name(pin) ?? device)
                session = s
                p.send(json: ["type": "welcome", "version": 1, "state": "paired", "host": hostName])
                // Routes the phone can use next time (Wi-Fi or Tailscale); it merges them under this Mac's pin.
                p.send(json: ["type": "host_info", "addresses": Self.localAddresses().map { ["ip": $0.ip, "kind": $0.kind] }])
                sendDisplay(s)
                event("\(s.device) connected")
            } else if pairingAdmits, let cb = p.channelBinding {
                if let other = trust.pin(named: device), other != pin {
                    return p.close(ProtocolError(code: "pairing_failed", message: "A device named \(device) is already paired. Revoke it on the Mac first."))
                }
                let pairingId = Self.random(16)
                pairing = PairingExchange(peer: p, device: device,
                                          machine: HostPairing(pairingId: pairingId, pinC: pin, pinS: identity.pin, cb: cb))
                p.send(json: ["type": "welcome", "version": 1, "state": "pairing", "host": hostName, "pairingId": pairingId.base64EncodedString()])
                publish()
            } else {
                p.close(ProtocolError(code: "not_paired", message: "Turn on pairing mode on the Mac"))
            }
        case .video, .file, .audio:
            guard let raw = (m["ticket"] as? String).flatMap({ Data(base64Encoded: $0) }),
                  let t = tickets.removeValue(forKey: raw), t.expires > Date(), t.purpose == kind,
                  let s = session, s.id == t.sessionID, s.pin == pin
            else { return p.close(ProtocolError(code: "bad_ticket")) }
            p.send(json: ["type": "welcome", "version": 1])
            if kind == .video {
                s.video?.close()
                s.video = p
                startVideo(s)
            } else if kind == .audio {
                s.audio?.close()
                s.audio = p
                applyAudio(s)
                publish()
            } else if let tr = [s.incoming, s.outgoing].compactMap({ $0 }).first(where: { $0.id == t.transferID }) {
                tr.peer = p
                tr.state = "Transferring"
                if !tr.incoming { pumpOutgoing(tr, s) }
                publish()
            } else {
                p.close(ProtocolError(code: "bad_ticket"))
            }
        }
    }

    private var hostName: String { String((Host.current().localizedName ?? "Mac").prefix(64)) }

    private static func source(_ c: NWConnection) -> String {
        if case .hostPort(let host, _) = c.endpoint { return "\(host)" }
        return "\(c.endpoint)"
    }

    /// IPv4 addresses a phone could reach this Mac on: LAN interfaces and Tailscale (100.64.0.0/10), at most 8.
    static func localAddresses() -> [(ip: String, kind: String)] {
        var result: [(String, String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return [] }
        defer { freeifaddrs(ifaddr) }
        var p = ifaddr
        while let a = p?.pointee {
            defer { p = a.ifa_next }
            guard let sa = a.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET), a.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  a.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self), name = String(cString: a.ifa_name)
            let parts = ip.split(separator: ".").compactMap { Int($0) }
            let tailscale = parts.count == 4 && parts[0] == 100 && (64...127).contains(parts[1])
            if tailscale { result.append((ip, "tailscale")) } else if name.hasPrefix("en") { result.append((ip, "lan")) }
        }
        return Array(result.prefix(8))
    }

    static func random(_ n: Int) -> Data {
        var raw = Data(count: n)
        let ok = raw.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, n, $0.baseAddress!) } == errSecSuccess
        precondition(ok, "system RNG failed") // never fall back to weaker randomness
        return raw
    }

    private func issueTicket(_ purpose: ConnKind, _ s: Session, transfer: String? = nil) -> String {
        let raw = Self.random(32)
        tickets[raw] = Ticket(purpose: purpose, sessionID: s.id, transferID: transfer, expires: Date().addingTimeInterval(10))
        return raw.base64EncodedString()
    }

    // MARK: - Paired session

    private func control(_ m: [String: Any], _ s: Session) {
        let type = m["type"] as! String
        // SPEC §5 flood bounds, for approved devices too.
        guard s.allowControl(), s.control.pendingSends <= 256 else { return teardown(s, code: "rate_limited", event: "\(s.device) flooded the connection") }
        if Self.inputTypes.contains(type) {
            if !s.allowInput() { return teardown(s, code: "rate_limited", event: "\(s.device) sent too much input") }
            guard AXIsProcessTrusted() else { return s.control.sendError("permission_accessibility", "Grant Accessibility to Tetherly on the Mac") }
            guard applyInput(type, m) else { return teardown(s, code: "malformed", event: nil) }
            return
        }
        switch type {
        case "ping":
            s.control.send(json: ["type": "pong", "n": m["n"] ?? 0])
        case "video_start":
            guard let dim = m["maxDimension"] as? Int, [960, 1280, 1920].contains(dim), let fps = m["fps"] as? Int, (15...240).contains(fps),
                  ["hidden", "shown", nil].contains(m["cursor"] as? String), m["cursor"] == nil || m["cursor"] is String
            else { return teardown(s, code: "malformed", event: nil) }
            guard CGPreflightScreenCaptureAccess() else {
                return s.control.sendError("permission_screen_recording", "Grant Screen Recording to Tetherly on the Mac")
            }
            guard s.allowVideoStart() else { return teardown(s, code: "rate_limited", event: nil) }
            // The stream runs at the lower of the phone's request and this display's real maximum.
            s.settings = .init(maxDimension: dim, fps: min(fps, max(maxRefreshRate(), 30)), showsCursor: m["cursor"] as? String != "hidden")
            if s.video != nil { startVideo(s) } else { s.control.send(json: ["type": "video_ticket", "ticket": issueTicket(.video, s)]) }
        case "audio_start":
            guard let mac = m["mac"] as? Bool else { return teardown(s, code: "malformed", event: nil) }
            if mac, !CGPreflightScreenCaptureAccess() {
                s.control.sendError("permission_screen_recording", "Grant Screen Recording to Tetherly on the Mac to hear its sound")
            }
            guard s.allowVideoStart() else { return teardown(s, code: "rate_limited", event: nil) }
            s.wantsMacAudio = mac && CGPreflightScreenCaptureAccess()
            if s.audio != nil { applyAudio(s) } else { s.control.send(json: ["type": "audio_ticket", "ticket": issueTicket(.audio, s)]) }
            publish()
        case "audio_stop":
            s.wantsMacAudio = false
            s.audio?.close()
            s.audio = nil
            audioCapture.stop()
            publish()
        case "video_stop":
            encoder.stop()
            s.video?.close()
            s.video = nil
            publish()
        case "keyframe":
            encoder.requestKeyframe()
        case "clipboard_set":
            guard let text = m["text"] as? String, text.utf8.count <= 60_000 else { return teardown(s, code: "malformed", event: nil) }
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            event("Clipboard received from \(s.device)")
        case "clipboard_get":
            var text = DispatchQueue.main.sync { NSPasteboard.general.string(forType: .string) } ?? ""
            while text.utf8.count > 60_000 { text.removeLast(max(1, (text.utf8.count - 60_000) / 4)) }
            s.control.send(json: ["type": "clipboard", "text": text])
            event("Clipboard sent to \(s.device)")
        case "file_offer":
            incomingOffer(m, s)
        case "file_accept":
            guard let t = s.outgoing, t.id == m["id"] as? String, t.state == "Waiting for phone" else { return }
            t.state = "Connecting"
            s.control.send(json: ["type": "file_ticket", "id": t.id, "ticket": issueTicket(.file, s, transfer: t.id)])
            publish()
        case "file_reject":
            if let t = s.outgoing, t.id == m["id"] as? String { failTransfer(t, s, "Declined on phone", notifyPeer: false) }
        case "file_cancel":
            if let id = m["id"] as? String { cancelTransfer(id: id, notifyPeer: false) }
        case "file_result":
            guard let t = s.outgoing, t.id == m["id"] as? String else { return }
            if m["ok"] as? Bool == true { finishTransfer(t, s, "Sent") } else { failTransfer(t, s, m["error"] as? String ?? "Failed on phone", notifyPeer: false) }
        case "bye":
            teardown(s, code: nil, event: "\(s.device) disconnected")
        case "error":
            break // informational from the phone
        default:
            teardown(s, code: "unknown_type", event: nil)
        }
    }

    /// Returns false for out-of-range values (fatal `malformed`).
    private func applyInput(_ type: String, _ m: [String: Any]) -> Bool {
        func num(_ k: String, _ r: ClosedRange<Double>) -> Double? { (m[k] as? NSNumber)?.doubleValue.nilIfOutside(r) }
        func button() -> CGMouseButton? { (m["button"] as? String).flatMap { $0 == "left" ? .left : $0 == "right" ? .right : nil } }
        switch type {
        case "pointer":
            guard let dx = num("dx", -10_000...10_000), let dy = num("dy", -10_000...10_000) else { return false }
            input.move(dx: dx, dy: dy)
        case "pointer_abs":
            guard let x = num("x", 0...1), let y = num("y", 0...1) else { return false }
            input.moveAbsolute(x: x, y: y)
        case "button":
            guard let b = button(), let down = m["down"] as? Bool else { return false }
            input.button(b, down: down)
        case "click":
            guard let b = button() else { return false }
            input.click(b)
        case "scroll":
            guard let dx = num("dx", -5_000...5_000), let dy = num("dy", -5_000...5_000) else { return false }
            input.scroll(dx: Int32(dx), dy: Int32(dy))
        case "key":
            guard let code = num("code", 0...127), let mods = m["modifiers"] as? [String] ?? (m["modifiers"] == nil ? [] : nil),
                  mods.allSatisfy(["cmd", "shift", "alt", "ctrl", "fn"].contains) else { return false }
            input.key(code: CGKeyCode(code), modifiers: mods)
        case "text":
            guard let text = m["text"] as? String, (1...1000).contains(text.utf16.count) else { return false }
            input.type(text)
        case "modifier":
            guard m["key"] as? String == "fn", let down = m["down"] as? Bool else { return false }
            input.fnKey(down: down)
        default:
            return false
        }
        return true
    }

    /// ProMotion and other variable-refresh panels report their nominal mode (often 60) through CoreGraphics;
    /// NSScreen.maximumFramesPerSecond has the true ceiling. NSScreen is main-thread API; main never waits on us.
    private func maxRefreshRate() -> Int {
        let id = input.displayID
        return DispatchQueue.main.sync {
            NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }?
                .maximumFramesPerSecond ?? 60
        }
    }

    private func sendDisplay(_ s: Session) {
        let id = input.displayID, b = CGDisplayBounds(id)
        let scale = CGDisplayCopyDisplayMode(id).map { Double($0.pixelWidth) / Double(max(1, $0.width)) } ?? 1
        s.control.send(json: ["type": "display", "id": Int(id), "width": Int(b.width), "height": Int(b.height), "scale": scale])
    }

    private func handleDisplayChange() {
        input.displayID = CGMainDisplayID()
        guard let s = session else { return }
        sendDisplay(s)
        if s.video != nil { startVideo(s) }
    }

    // MARK: - Audio

    private func applyAudio(_ s: Session) {
        guard let audio = s.audio else { return }
        guard s.wantsMacAudio else { return audioCapture.stop() }
        audioCapture.onPCM = { [weak self, weak s, weak audio] pts, pcm in
            self?.queue.async {
                // Bounded: if the phone isn't keeping up, drop audio rather than build latency.
                guard let self, let s, let a = audio, self.session === s,
                      s.audio === a, s.wantsMacAudio, a.pendingSends < 16 else { return }
                for start in stride(from: 0, to: pcm.count, by: 16_384) {
                    a.send(Frame.encodeAudio(ptsMicros: pts, pcm: pcm.subdata(in: start..<min(start + 16_384, pcm.count))))
                }
            }
        }
        audioCapture.start(displayID: input.displayID)
    }

    // MARK: - Video

    private func makeEncoder() -> ScreenEncoder {
        let e = ScreenEncoder(outputQueue: queue)
        e.onConfig = { [weak self] cfg in
            guard let v = self?.session?.video else { return }
            v.send(Frame.encode(cfg))
        }
        e.onFrame = { [weak self] pts, key, data in
            guard let self, let s = self.session, let v = s.video else { return }
            // Bounded queue: never more than 2 frames in flight; after a drop, wait for a keyframe (SPEC §6).
            if v.pendingSends >= 2 || data.count + 10 > 4_194_304 || (s.needKeyframe && !key) {
                s.needKeyframe = true
                self.encoder.requestKeyframe()
                return
            }
            if key { s.needKeyframe = false }
            v.send(Frame.encodeVideoFrame(ptsMicros: pts, keyframe: key, data: data))
        }
        e.onError = { [weak self] message in
            guard let self, let s = self.session else { return }
            s.control.sendError(CGPreflightScreenCaptureAccess() ? "busy" : "permission_screen_recording", message)
            s.video?.close()
        }
        return e
    }

    private func startVideo(_ s: Session) {
        guard let settings = s.settings else { return }
        guard CGPreflightScreenCaptureAccess() else {
            s.video?.close()
            return s.control.sendError("permission_screen_recording", "Grant Screen Recording to Tetherly on the Mac")
        }
        s.needKeyframe = true
        encoder.start(displayID: input.displayID, settings: settings)
        publish()
    }

    // MARK: - Pairing

    private func openPairingWindow() {
        pairingUntil = Date().addingTimeInterval(120)
        pairingFailures = 0
        event("Pairing mode on for 2 minutes")
    }

    private func closePairingWindow(event e: String?) {
        pairingUntil = nil
        abortPairing(event: nil)
        if let e { event(e) } else { publish() }
    }

    private func pairingMessage(_ m: [String: Any], _ x: PairingExchange) {
        if m["type"] as? String == "ping" { return x.peer.send(json: ["type": "pong", "n": m["n"] ?? 0]) }
        perform(x.machine.receive(m), x)
    }

    private func userDecided(_ ok: Bool, _ id: ObjectIdentifier) {
        guard let x = pairing, ObjectIdentifier(x) == id else { return }
        perform(x.machine.decide(ok), x)
    }

    /// Executes the state machine's actions (SPEC §4.1/§4.2).
    private func perform(_ actions: [HostPairing.Action], _ x: PairingExchange) {
        for action in actions {
            guard pairing === x else { return }
            switch action {
            case .send(let m):
                x.peer.send(json: m)
            case .showCode(let code):
                publish()
                let id = ObjectIdentifier(x), device = x.device
                Task { @MainActor [weak self, askPairing] in
                    askPairing?(device, code) { [weak self] ok in
                        guard let self else { return }
                        self.queue.async { self.userDecided(ok, id) }
                    }
                }
            case .persist:
                let saved: Bool
                do { try trust.add(pin: x.machine.pinC, name: x.device); saved = true } catch { saved = false }
                perform(x.machine.persisted(saved), x)
            case .close:
                x.peer.sendAndClose(Data()) // ends the stream after the queued pair_done; bounded by the flush deadline
                pairing = nil
                pairingUntil = nil
                endPairingPrompt()
                event("Paired with \(x.device)")
            case .fail(let why):
                pairingFailures += 1
                if pairingFailures >= 5 { pairingUntil = nil }
                x.peer.close(ProtocolError(code: "pairing_failed", message: why))
                pairing = nil
                endPairingPrompt()
                event("Pairing failed: \(why)")
            }
        }
    }

    private func abortPairing(event e: String?) {
        guard let x = pairing else { return }
        pairing = nil
        // Dropped or timed-out exchanges count like failures; otherwise connect-and-drop gets unlimited attempts.
        pairingFailures += 1
        if pairingFailures >= 5 { pairingUntil = nil }
        x.peer.close()
        endPairingPrompt()
        if let e { event(e) }
    }

    private func endPairingPrompt() { Task { @MainActor [pairingEnded] in pairingEnded?() } }

    private func revokeDevice(_ pinHex: String) {
        guard let pin = Data(hex: pinHex) else { return }
        let name = trust.name(pin) ?? "Device"
        // Fail closed: the in-memory list drops the pin even if the file can't be written; the user is told.
        let saved = (try? trust.remove(pin: pin)) != nil
        if let s = session, s.pin == pin { teardown(s, code: "revoked", event: nil) }
        event(saved ? "\(name) revoked" : "\(name) revoked for now, but saving failed. It may be trusted again after a restart.")
    }

    // MARK: - Teardown and timers

    /// SPEC §9: close every channel of the session, stop capture, release input, drop tickets and partial files.
    private func teardown(_ s: Session, code: String?, event e: String?) {
        guard session === s else { return }
        session = nil
        for t in [s.incoming, s.outgoing].compactMap({ $0 }) where !t.finished { t.cleanUp() }
        s.incoming = nil; s.outgoing = nil
        tickets = tickets.filter { $0.value.sessionID != s.id }
        encoder.stop()
        audioCapture.stop()
        input.releaseAll()
        s.video?.close()
        s.audio?.close()
        if let code { s.control.close(ProtocolError(code: code)) } else { s.control.close() }
        if let e { event(e) } else { publish() }
    }

    private func tick() {
        let now = Date()
        for id in awaitingHello where now.timeIntervalSince(peers[id]?.lastReceived ?? now) > 10 {
            peers[id]?.close(ProtocolError(code: "timeout"))
        }
        if let s = session, now.timeIntervalSince(s.control.lastReceived) > 15 { teardown(s, code: "timeout", event: "\(s.device) timed out") }
        if let s = session {
            // SPEC §5: permission revoked mid-session stops the affected channel; control stays up.
            if (s.video != nil || s.audio != nil), !CGPreflightScreenCaptureAccess() {
                encoder.stop()
                s.video?.close()
                s.video = nil
                audioCapture.stop()
                s.wantsMacAudio = false
                s.audio?.close()
                s.audio = nil
                tickets = tickets.filter { $0.value.sessionID != s.id || ($0.value.purpose != .video && $0.value.purpose != .audio) }
                s.control.sendError("permission_screen_recording", "Screen Recording was turned off for Tetherly")
                event("Screen Recording permission lost: viewing and sound stopped")
            }
            let trusted = AXIsProcessTrusted()
            if !trusted, !axLostNotified {
                axLostNotified = true
                input.releaseAll()
                s.control.sendError("permission_accessibility", "Accessibility was turned off for Tetherly")
            } else if trusted {
                axLostNotified = false
            }
        }
        if let x = pairing, now.timeIntervalSince(x.peer.lastReceived) > 15 { abortPairing(event: "Pairing timed out") }
        if let until = pairingUntil {
            if until <= now { closePairingWindow(event: "Pairing mode expired") } else { publish() }
        }
        tickets = tickets.filter { $0.value.expires > now }
    }

    /// SPEC §5 `cursor`: up to 60 Hz while video is active and the pointer moved; the phone draws its cursor from this.
    private func sendCursor() {
        guard let s = session, s.video != nil else { return }
        let b = CGDisplayBounds(input.displayID), p = CGEvent(source: nil)?.location ?? .zero
        let x = min(max((p.x - b.minX) / b.width, 0), 1), y = min(max((p.y - b.minY) / b.height, 0), 1)
        guard abs(x - s.lastCursor.x) > 0.0005 || abs(y - s.lastCursor.y) > 0.0005 else { return }
        s.lastCursor = CGPoint(x: x, y: y)
        s.control.send(json: ["type": "cursor", "x": (x * 10_000).rounded() / 10_000, "y": (y * 10_000).rounded() / 10_000])
    }

    // MARK: - File transfer (SPEC §7)

    private func incomingOffer(_ m: [String: Any], _ s: Session) {
        guard let id = m["id"] as? String, id.count == 16, id.allSatisfy(\.isHexDigit), let raw = m["name"] as? String,
              raw.utf8.count <= 255, let size = (m["size"] as? NSNumber)?.int64Value, (0...(4 << 30)).contains(size)
        else { return teardown(s, code: "malformed", event: nil) }
        guard s.incoming == nil else { return s.control.send(json: ["type": "file_reject", "id": id, "reason": "busy"]) }
        let t = Transfer(id: id, name: FileNames.sanitize(raw), size: size, incoming: true)
        t.state = "Waiting for you"
        s.incoming = t
        publish()
        let device = s.device, name = t.name, sid = s.id
        Task { @MainActor [weak self, askSaveLocation] in
            askSaveLocation?(name, size, device) { [weak self] url in
                guard let self else { return }
                self.queue.async { self.saveChosen(url, id: id, session: sid) }
            }
        }
    }

    private func saveChosen(_ url: URL?, id: String, session sid: UUID) {
        guard let s = session, s.id == sid, let t = s.incoming, t.id == id, t.state == "Waiting for you" else { return }
        guard let url else {
            s.incoming = nil
            s.control.send(json: ["type": "file_reject", "id": id, "reason": "declined"])
            return event("Declined \(t.name)")
        }
        let dir = url.deletingLastPathComponent()
        t.destination = dir
        t.name = FileNames.sanitize(url.lastPathComponent)
        // Our own random name, created exclusively and never through a symlink, so we only ever touch a file we made.
        guard let (temp, h) = FileNames.createExclusiveTemp(in: dir, tag: Self.random(16).hex) else {
            return failTransfer(t, s, "Can't write to \(dir.lastPathComponent)")
        }
        t.temp = temp
        t.handle = h
        t.state = "Connecting"
        s.control.send(json: ["type": "file_accept", "id": id])
        s.control.send(json: ["type": "file_ticket", "id": id, "ticket": issueTicket(.file, s, transfer: id)])
        publish()
    }

    private func fileFrame(_ f: Frame, _ t: Transfer, _ s: Session) {
        guard t.incoming else { return t.peer?.close(.unknownType) ?? () }
        switch f {
        case .fileChunk(let d):
            guard t.done + Int64(d.count) <= t.size else { return failTransfer(t, s, "Phone sent more data than offered") }
            do { try t.handle?.write(contentsOf: d) } catch { return failTransfer(t, s, "Write failed (disk full?)") }
            t.hasher.update(data: d)
            t.done += Int64(d.count)
            t.publishProgress { publish() }
        case .json(let m) where m["type"] as? String == "file_end":
            guard t.done == t.size, let sha = (m["sha256"] as? String).flatMap({ Data(base64Encoded: $0) }),
                  sha == Data(t.hasher.finalize()) else { return failTransfer(t, s, "Integrity check failed") }
            try? t.handle?.close()
            t.handle = nil
            guard let dir = t.destination, let temp = t.temp, let final = FileNames.publishExclusive(temp, in: dir, name: t.name) else {
                return failTransfer(t, s, "Couldn't save the file")
            }
            t.name = final
            t.temp = nil
            s.control.send(json: ["type": "file_result", "id": t.id, "ok": true])
            finishTransfer(t, s, "Saved")
        default:
            t.peer?.close(.unknownType)
        }
    }

    private func startOutgoing(_ url: URL) {
        guard let s = session else { return event("Connect a device first") }
        guard s.outgoing == nil else { return event("A file is already being sent") }
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value,
              size <= 4 << 30, let h = try? FileHandle(forReadingFrom: url)
        else { return event("Can't read \(url.lastPathComponent) (or it is over 4 GB)") }
        let t = Transfer(id: Self.random(8).hex, name: FileNames.sanitize(url.lastPathComponent), size: size, incoming: false)
        t.handle = h
        t.state = "Waiting for phone"
        s.outgoing = t
        s.control.send(json: ["type": "file_offer", "id": t.id, "name": t.name, "size": size])
        publish()
    }

    /// Sends one chunk at a time, paced by send completion so file data never queues ahead of control traffic.
    private func pumpOutgoing(_ t: Transfer, _ s: Session) {
        guard session === s, s.outgoing === t, let p = t.peer, !t.finished else { return }
        let chunk: Data
        do { chunk = try t.handle?.read(upToCount: 262_144) ?? Data() } catch { return failTransfer(t, s, "Read failed") }
        if chunk.isEmpty {
            guard t.done == t.size else { return failTransfer(t, s, "File changed while sending") }
            t.state = "Verifying on phone"
            p.send(json: ["type": "file_end", "sha256": Data(t.hasher.finalize()).base64EncodedString()])
            return publish()
        }
        t.hasher.update(data: chunk)
        t.done += Int64(chunk.count)
        t.publishProgress { publish() }
        p.send(Frame.encode(type: Frame.fileChunkType, chunk)) { [weak self] in self?.pumpOutgoing(t, s) }
    }

    private func cancelTransfer(id: String, notifyPeer: Bool) {
        guard let s = session, let t = [s.incoming, s.outgoing].compactMap({ $0 }).first(where: { $0.id == id }) else { return }
        failTransfer(t, s, "Cancelled", notifyPeer: notifyPeer, code: "file_cancel")
    }

    private func failTransfer(_ t: Transfer, _ s: Session, _ why: String, notifyPeer: Bool = true, code: String = "file_result") {
        t.cleanUp()
        t.state = why
        if notifyPeer {
            s.control.send(json: code == "file_cancel" ? ["type": "file_cancel", "id": t.id]
                : t.incoming ? ["type": "file_result", "id": t.id, "ok": false, "error": why] : ["type": "file_cancel", "id": t.id])
        }
        detach(t, s, event: "\(t.name): \(why)")
    }

    private func finishTransfer(_ t: Transfer, _ s: Session, _ verb: String) {
        t.finished = true
        t.peer?.close()
        t.state = verb
        detach(t, s, event: "\(verb) \(t.name)")
    }

    private func detach(_ t: Transfer, _ s: Session, event e: String) {
        if s.incoming === t { s.incoming = nil }
        if s.outgoing === t { s.outgoing = nil }
        tickets = tickets.filter { $0.value.transferID != t.id }
        event(e)
    }

    // MARK: - Snapshot

    private func event(_ e: String) {
        lastEvent = e
        publish()
    }

    private func publish() {
        var snap = Snapshot()
        snap.hosting = listener != nil
        snap.hostPin = identity.pin
        snap.hostName = hostName
        snap.listener = listenerState
        snap.pairingUntil = pairingUntil
        snap.pairingDevice = pairing?.device
        snap.pairingCode = pairing?.machine.code
        snap.sessionDevice = session?.device
        snap.sessionSince = session?.since
        snap.videoActive = session?.video != nil
        snap.devices = trust.all.map { .init(id: $0.pin, name: $0.name, pairedAt: $0.pairedAt) }
        snap.transfers = [session?.incoming, session?.outgoing].compactMap { $0 }
            .map { .init(id: $0.id, name: $0.name, size: $0.size, done: $0.done, incoming: $0.incoming, state: $0.state) }
        snap.lastEvent = lastEvent
        snap.audioOut = session?.audio != nil && session?.wantsMacAudio == true
        Task { @MainActor [onSnapshot] in onSnapshot?(snap) }
    }
}

// MARK: - Session state (host queue only)

final class Session {
    let id = UUID()
    let control: Peer
    let pin: Data
    let device: String
    let since = Date()
    var video: Peer?
    var audio: Peer?
    var wantsMacAudio = false
    var settings: ScreenEncoder.Settings?
    var needKeyframe = true
    var lastCursor = CGPoint(x: -1, y: -1)
    var incoming: Transfer?
    var outgoing: Transfer?
    private var windowStart = Date()
    private var count = 0

    init(control: Peer, pin: Data, device: String) {
        self.control = control
        self.pin = pin
        self.device = device
    }

    private var controlWindow = Date(), controlCount = 0
    private var videoStarts: [Date] = []

    /// SPEC §5: at most 500 input messages per second.
    func allowInput() -> Bool {
        let now = Date()
        if now.timeIntervalSince(windowStart) >= 1 { windowStart = now; count = 0 }
        count += 1
        return count <= 500
    }

    /// SPEC §5: at most 1000 control messages of any kind per second.
    func allowControl() -> Bool {
        let now = Date()
        if now.timeIntervalSince(controlWindow) >= 1 { controlWindow = now; controlCount = 0 }
        controlCount += 1
        return controlCount <= 1000
    }

    /// SPEC §5: at most 20 video_start per minute (each one issues a ticket).
    func allowVideoStart() -> Bool {
        let now = Date()
        videoStarts.removeAll { now.timeIntervalSince($0) > 60 }
        videoStarts.append(now)
        return videoStarts.count <= 20
    }
}

struct Ticket {
    let purpose: ConnKind
    let sessionID: UUID
    let transferID: String?
    let expires: Date
}

final class PairingExchange {
    let peer: Peer
    let device: String
    let machine: HostPairing

    init(peer: Peer, device: String, machine: HostPairing) {
        self.peer = peer
        self.device = device
        self.machine = machine
    }
}

final class Transfer {
    let id: String
    var name: String
    let size: Int64
    let incoming: Bool
    var state = ""
    var done: Int64 = 0
    var peer: Peer?
    var handle: FileHandle?
    var destination: URL?
    var temp: URL?
    var hasher = SHA256()
    var finished = false
    private var lastPublish = Date.distantPast

    init(id: String, name: String, size: Int64, incoming: Bool) {
        self.id = id
        self.name = name
        self.size = size
        self.incoming = incoming
    }

    func publishProgress(_ publish: () -> Void) {
        if Date().timeIntervalSince(lastPublish) > 0.25 || done == size { lastPublish = Date(); publish() }
    }

    /// Closes the connection and file, deleting any partial download.
    func cleanUp() {
        finished = true
        peer?.close()
        try? handle?.close()
        handle = nil
        if let temp { try? FileManager.default.removeItem(at: temp) }
        temp = nil
    }
}

private extension Double {
    func nilIfOutside(_ r: ClosedRange<Double>) -> Double? { isFinite && r.contains(self) ? self : nil }
}
