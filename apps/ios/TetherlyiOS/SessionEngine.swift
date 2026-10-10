import CryptoKit
import Foundation
import Network
import UIKit

enum SessionState: Equatable {
    case idle
    case connecting(label: String, pairing: Bool)
    case pairing(host: String, code: [Int]?, confirmed: Bool, macApproved: Bool)
    case connected(host: String, address: String)
    case reconnecting(host: String, attempt: Int, reason: String)
    case failed(String)
}

struct TransferInfo: Equatable {
    var name: String, size: Int64, done: Int64, status: String, active: Bool
}

struct VideoSettings: Equatable {
    var maxDimension = 1920
    var fps = 60
}

/// The phone side of protocol/SPEC.md. Every stored property and method runs on `queue`; the UI sees state through
/// `SessionModel`, which receives snapshots on the main actor.
final class SessionEngine: @unchecked Sendable {
    let queue = DispatchQueue(label: "link.tetherly.session", qos: .userInitiated)
    weak var model: SessionModel?
    let renderer: VideoRenderer
    private let identity: PhoneIdentity

    private var generation = 0
    private var control: Peer?
    private var video: Peer?
    private var audio: Peer?
    private var wantMacSound = false
    let audioIO = AudioIO()
    private var pairing: ClientPairing?
    private var pairingHost = ""
    private var target: (endpoint: NWEndpoint, label: String, expectedPin: String?)?
    private var host = ""
    private var paired = false
    private var userStopped = false
    private var attempt = 0
    private var macPin = ""
    private var settings = VideoSettings()
    private var videoRetries = 0
    private var heartbeat: DispatchSourceTimer?
    private var ping = 0
    // Pointer and scroll moves merge between sends, so input stays well under the Mac's rate limit (SPEC §5).
    private var pendingMove: (dx: Double, dy: Double)?
    private var pendingScroll: (dx: Double, dy: Double)?
    private var pendingAbs: (x: Double, y: Double)?
    private var flushScheduled = false
    private var outgoing: Outgoing?
    private var incoming: Incoming?

    static let terminal: Set = ["unsupported_version", "not_paired", "pairing_closed", "pairing_failed", "busy", "revoked", "rate_limited"]

    init(identity: PhoneIdentity, renderer: VideoRenderer) {
        self.identity = identity
        self.renderer = renderer
    }

    // MARK: - Public API (any thread)

    func connect(_ endpoints: [NWEndpoint], label: String, pair: Bool, expectedPin: Data? = nil) {
        queue.async { self.start(endpoints, label: label, pair: pair, expectedPin: expectedPin?.hex) }
    }

    func disconnect() { queue.async { self.userStopped = true; self.stop(); self.publish(.idle) } }
    func send(_ m: [String: Any]) { queue.async { self.enqueue(m) } }
    func confirmPairing() { queue.async { self.pairingConfirm() } }
    func cancelPairing() { queue.async { self.pairingCancel() } }
    func setVideo(_ s: VideoSettings) { queue.async { self.settings = s; self.retryVideo() } }
    func retryVideo() { queue.async { self.videoRetries = 0; self.requestVideo() } }
    func requestClipboard() { send(["type": "clipboard_get"]) }
    func sendClipboard(_ text: String) {
        guard text.utf8.count <= 60_000 else { return notice("That text is too long to send (over 60 KB).") }
        send(["type": "clipboard_set", "text": text])
        notice("Sent the clipboard to your Mac.")
    }
    func sendFile(_ url: URL) { queue.async { self.offerFile(url) } }
    func setMacSound(_ on: Bool) { queue.async { self.wantMacSound = on; self.requestAudio() } }
    func answerOffer(folder: URL?) { queue.async { self.acceptIncoming(folder) } }
    func cancelTransfer(outgoing isOut: Bool) { queue.async { isOut ? self.failOutgoing("Cancelled", tell: true) : self.failIncoming("Cancelled", tell: true) } }

    // MARK: - Connect

    private func start(_ endpoints: [NWEndpoint], label: String, pair: Bool, expectedPin: String?) {
        stop()
        userStopped = false
        attempt = 0
        publish(.connecting(label: label, pairing: pair))
        tryConnect(endpoints, index: 0, label: label, pair: pair, expectedPin: expectedPin, lastError: nil)
    }

    private func tryConnect(_ endpoints: [NWEndpoint], index: Int, label: String, pair: Bool, expectedPin: String?, lastError: String?) {
        guard index < endpoints.count else {
            return publish(.failed(lastError ?? "Couldn't reach \(label). Check that both devices are on the same Wi-Fi or on Tailscale."))
        }
        let gen = generation
        let endpoint = endpoints[index]
        var verdict: ClientTrust?
        let params = tlsParameters { [weak self] pin in
            guard let self else { return false }
            let v = ClientTrust.decide(pin: pin.hex, address: Self.describe(endpoint), macs: MacStore.load(), pairIntent: pair, expectedPin: expectedPin)
            verdict = v
            if case .rejected = v { return false }
            return true
        }
        let p = Peer(NWConnection(to: endpoint, using: params), queue: queue, role: .client)
        var ready = false
        p.onReady = { [weak self] p in
            ready = true
            p.send(json: ["type": "hello", "versions": [1], "kind": "control", "device": String(UIDevice.current.name.prefix(64))])
            _ = self
        }
        p.onFrame = { [weak self] p, f in
            guard let self, gen == self.generation, case .json(let m) = f else { return }
            if self.control === p { self.controlMessage(m) } else { self.welcome(m, p, endpoint, verdict, pair: pair, label: label) }
        }
        p.onClose = { [weak self] p, error in
            guard let self, gen == self.generation else { return }
            if self.control === p { return self.lost(error?.code ?? "connection lost") }
            if case .rejected(let why) = verdict { return self.publish(.failed(why)) }
            if !ready { return self.tryConnect(endpoints, index: index + 1, label: label, pair: pair, expectedPin: expectedPin, lastError: lastErrorText(error)) }
            self.publish(.failed(error.map { Self.explain($0.code) } ?? "The Mac closed the connection."))
        }
        p.start()
        // Bound each candidate address to 5 seconds, then move on.
        queue.asyncAfter(deadline: .now() + 5) { if gen == self.generation, !ready, !p.terminated { p.close() } }
    }

    private func lastErrorText(_ e: ProtocolError?) -> String? { e.map { Self.explain($0.code) } }

    private func welcome(_ m: [String: Any], _ p: Peer, _ endpoint: NWEndpoint, _ verdict: ClientTrust?, pair: Bool, label: String) {
        guard m["type"] as? String == "welcome", let state = m["state"] as? String, let verdict else {
            return fail(p, Self.explain((m["code"] as? String) ?? "malformed"))
        }
        let hostName = String((m["host"] as? String ?? label).prefix(64))
        switch ClientTrust.checkWelcome(verdict, state: state, host: hostName, macs: MacStore.load(), pairIntent: pair) {
        case .session(let mac):
            control = p
            target = (endpoint, hostName, nil)
            paired = true
            host = hostName
            macPin = mac.pin
            let address = Self.remote(p) ?? mac.address
            MacStore.save(MacStore.load().map { $0.pin == mac.pin ? PairedMac(hostName: hostName, pin: $0.pin, address: address, routes: $0.routes) : $0 })
            attempt = 0
            publish(.connected(host: hostName, address: address))
            model.map { m in Task { @MainActor in m.macsChanged() } }
            startHeartbeat()
            requestVideo()
            if wantMacSound { requestAudio() }
        case .pair:
            guard let pid = (m["pairingId"] as? String).flatMap({ Data(base64Encoded: $0) }), pid.count == 16,
                  let pinS = p.pin, let cb = p.channelBinding else { return fail(p, "The Mac didn't start pairing correctly.") }
            control = p
            target = (endpoint, hostName, nil)
            pairingHost = hostName
            let machine = ClientPairing(pairingId: pid, pinC: identity.pin, pinS: pinS, cb: cb)
            pairing = machine
            p.send(json: machine.commit())
            publish(.pairing(host: hostName, code: nil, confirmed: false, macApproved: false))
            startHeartbeat()
        case .rejected(let why):
            fail(p, why)
        }
    }

    private func fail(_ p: Peer, _ why: String) {
        generation += 1
        p.close()
        publish(.failed(why))
    }

    // MARK: - Pairing

    private func pairingMessage(_ m: [String: Any]) {
        guard let machine = pairing, let p = control else { return }
        // Heartbeats run during pairing too (SPEC §4.1 allows ping/pong); they are not part of the exchange.
        switch m["type"] as? String {
        case "ping": return p.send(json: ["type": "pong", "n": m["n"] ?? 0])
        case "pong": return
        default: break
        }
        do {
            if let reply = try machine.receive(m) { p.send(json: reply) }
            if machine.state == .done {
                let mac = PairedMac(hostName: pairingHost, pin: p.pin!.hex, address: Self.remote(p) ?? pairingHost)
                MacStore.save(MacStore.load().filter { $0.pin != mac.pin } + [mac])
                pairing = nil
                let endpoint = target?.endpoint
                stop()
                notice("Paired with \(mac.hostName).")
                model.map { m in Task { @MainActor in m.macsChanged() } }
                if let endpoint { start([endpoint], label: mac.hostName, pair: false, expectedPin: nil) }
                return
            }
            publish(.pairing(host: pairingHost, code: machine.code, confirmed: machine.userConfirmed, macApproved: machine.serverConfirmed))
        } catch let f as ClientPairing.Failure {
            if let reply = f.reply { p.send(json: reply) }
            pairing = nil
            fail(p, f.message)
        } catch {}
    }

    private func pairingConfirm() {
        guard let machine = pairing, let reply = machine.confirm() else { return }
        control?.send(json: reply)
        publish(.pairing(host: pairingHost, code: machine.code, confirmed: true, macApproved: machine.serverConfirmed))
    }

    private func pairingCancel() {
        if let machine = pairing { control?.send(json: machine.cancel()) }
        pairing = nil
        userStopped = true
        stop()
        publish(.idle)
    }

    // MARK: - Paired session (SPEC §5)

    private func controlMessage(_ m: [String: Any]) {
        if pairing != nil, !paired { return pairingMessage(m) }
        let type = m["type"] as? String ?? ""
        switch type {
        case "ping": control?.send(json: ["type": "pong", "n": m["n"] ?? 0])
        case "pong": break
        case "display":
            guard let w = (m["width"] as? NSNumber)?.doubleValue, let h = (m["height"] as? NSNumber)?.doubleValue, w > 0, h > 0 else { return }
            model.map { model in Task { @MainActor in model.display = CGSize(width: w, height: h) } }
        case "cursor":
            guard let x = (m["x"] as? NSNumber)?.doubleValue, let y = (m["y"] as? NSNumber)?.doubleValue, (0...1).contains(x), (0...1).contains(y) else {
                return protocolError("malformed")
            }
            model.map { model in Task { @MainActor in model.cursor = CGPoint(x: x, y: y) } }
        case "host_info":
            guard let routes = ClientTrust.routes(m) else { return protocolError("malformed") }
            MacStore.save(MacStore.load().map { $0.pin == macPin ? PairedMac(hostName: $0.hostName, pin: $0.pin, address: $0.address, routes: routes) : $0 })
            model.map { m in Task { @MainActor in m.macsChanged() } }
        case "video_ticket":
            guard let t = m["ticket"] as? String else { return protocolError("malformed") }
            openVideo(ticket: t)
        case "audio_ticket":
            guard let t = m["ticket"] as? String else { return protocolError("malformed") }
            openAudio(ticket: t)
        case "clipboard":
            guard let text = m["text"] as? String, text.utf8.count <= 60_000 else { return protocolError("malformed") }
            DispatchQueue.main.async { UIPasteboard.general.string = text }
            notice(text.isEmpty ? "The Mac clipboard has no text." : "Copied the Mac's clipboard to this device.")
        case "file_offer": incomingOffer(m)
        case "file_accept", "file_reject", "file_ticket", "file_cancel", "file_result": fileMessage(type, m)
        case "error":
            let code = m["code"] as? String ?? "unknown"
            if Self.terminal.contains(code) {
                userStopped = true
                stop()
                return publish(.failed(Self.explain(code)))
            }
            if code == "permission_screen_recording" { videoStopped(Self.explain(code)) } else { notice(Self.explain(code)) }
        case "bye":
            userStopped = true
            stop()
            publish(.failed("The Mac ended the session."))
        default:
            protocolError("unknown_type")
        }
    }

    private func protocolError(_ code: String) {
        control?.close(ProtocolError(code: code))
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 5, repeating: 5)
        t.setEventHandler { [weak self] in
            guard let self, let c = self.control else { return }
            if Date().timeIntervalSince(c.lastReceived) > 15 { return c.close(ProtocolError(code: "timeout")) }
            self.ping += 1
            c.send(json: ["type": "ping", "n": self.ping])
        }
        t.resume()
        heartbeat = t
    }

    /// Unexpected loss: reconnect with backoff 1, 2, 4 … 30 s. Input queued before the loss is dropped, never replayed.
    private func lost(_ reason: String) {
        let endpoint = target?.endpoint, label = host
        let wasPaired = paired
        stop()
        guard wasPaired, !userStopped, let endpoint else { return publish(.failed(Self.explain(reason))) }
        attempt += 1
        publish(.reconnecting(host: label, attempt: attempt, reason: Self.explain(reason)))
        let delay = Double(min(30, 1 << min(attempt - 1, 5)))
        let gen = generation
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, gen == self.generation, !self.userStopped else { return }
            let a = self.attempt
            self.tryConnect([endpoint], index: 0, label: label, pair: false, expectedPin: nil, lastError: nil)
            self.attempt = a
        }
    }

    private func stop() {
        generation += 1
        heartbeat?.cancel()
        heartbeat = nil
        control?.close()
        video?.close()
        audio?.close()
        audio = nil
        audioIO.stop()
        control = nil
        video = nil
        paired = false
        pairing = nil
        pendingMove = nil; pendingScroll = nil; pendingAbs = nil
        failOutgoing("Connection lost", tell: false)
        failIncoming("Connection lost", tell: false)
        renderer.reset()
        model.map { m in Task { @MainActor in m.cursor = nil; m.videoSize = nil; m.videoStopped = nil } }
    }

    // MARK: - Video

    private func requestVideo() {
        guard paired, let c = control else { return }
        c.send(json: ["type": "video_start", "maxDimension": settings.maxDimension, "fps": settings.fps])
        model.map { m in Task { @MainActor in m.videoStopped = nil } }
    }

    private func openVideo(ticket: String) {
        guard let endpoint = target?.endpoint, let expected = control?.pin else { return }
        video?.close()
        let gen = generation
        let params = tlsParameters { pin in pin == expected } // the video channel must reach the same Mac
        let p = Peer(NWConnection(to: Self.sameHost(control, fallback: endpoint), using: params), queue: queue, role: .client)
        p.kind = .video
        p.onReady = { p in p.send(json: ["type": "hello", "versions": [1], "kind": "video", "ticket": ticket]) }
        p.onFrame = { [weak self] _, f in
            guard let self, gen == self.generation else { return }
            switch f {
            case .videoConfig(let cfg):
                self.renderer.configure(cfg)
                model.map { m in Task { @MainActor in m.videoSize = CGSize(width: cfg.width, height: cfg.height) } }
                self.control?.send(json: ["type": "keyframe"])
            case .videoFrame(let pts, let key, let data):
                if !self.renderer.decode(ptsMicros: pts, keyframe: key, annexB: data) { self.control?.send(json: ["type": "keyframe"]) }
            default: break
            }
        }
        p.onClose = { [weak self] p, _ in
            guard let self, gen == self.generation, self.video === p else { return }
            self.video = nil
            self.videoRetries += 1
            if self.videoRetries <= 3 { self.requestVideo() } else { self.videoStopped("The screen stream stopped.") }
        }
        video = p
        p.start()
    }

    // MARK: - Audio (SPEC §5)

    private func requestAudio() {
        guard paired, let c = control else { return }
        c.send(json: wantMacSound ? ["type": "audio_start", "mac": true] : ["type": "audio_stop"])
        if !wantMacSound { audioIO.stop() }
    }

    private func openAudio(ticket: String) {
        guard let endpoint = target?.endpoint, let expected = control?.pin else { return }
        audio?.close()
        let gen = generation
        let p = Peer(NWConnection(to: Self.sameHost(control, fallback: endpoint), using: tlsParameters { $0 == expected }), queue: queue, role: .client)
        p.kind = .audio
        p.onReady = { p in p.send(json: ["type": "hello", "versions": [1], "kind": "audio", "ticket": ticket]) }
        p.onFrame = { [weak self] p, f in
            guard let self, gen == self.generation else { return }
            switch f {
            case .audio(_, let pcm):
                if self.wantMacSound { self.audioIO.play(pcm) }
            default: break
            }
        }
        p.onClose = { [weak self] p, _ in
            guard let self, gen == self.generation, self.audio === p else { return }
            self.audio = nil
            self.audioIO.stop()
        }
        audio = p
        p.start()
    }

    private func videoStopped(_ why: String) { model.map { m in Task { @MainActor in m.videoStopped = why } } }

    // MARK: - Input

    private func enqueue(_ m: [String: Any]) {
        guard paired, let c = control else { return }
        let type = m["type"] as? String
        switch type {
        case "pointer":
            let dx = (m["dx"] as? Double) ?? 0, dy = (m["dy"] as? Double) ?? 0
            pendingMove = ((pendingMove?.dx ?? 0) + dx, (pendingMove?.dy ?? 0) + dy)
        case "scroll":
            let dx = (m["dx"] as? Double) ?? 0, dy = (m["dy"] as? Double) ?? 0
            pendingScroll = ((pendingScroll?.dx ?? 0) + dx, (pendingScroll?.dy ?? 0) + dy)
        case "pointer_abs":
            pendingAbs = ((m["x"] as? Double) ?? 0, (m["y"] as? Double) ?? 0)
        default:
            flush() // keep order: moves before the click that follows them
            c.send(json: m)
            return
        }
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + 0.008) { [weak self] in self?.flush() } // ~120 Hz
    }

    private func flush() {
        flushScheduled = false
        guard let c = control else { return }
        if c.pendingSends > 64 { return } // the network is backed up: keep merging instead of queueing
        if let a = pendingAbs { c.send(json: ["type": "pointer_abs", "x": a.x, "y": a.y]); pendingAbs = nil }
        if let mv = pendingMove {
            let dx = Int(mv.dx.rounded(.towardZero)), dy = Int(mv.dy.rounded(.towardZero))
            if dx != 0 || dy != 0 { c.send(json: ["type": "pointer", "dx": max(-10_000, min(10_000, dx)), "dy": max(-10_000, min(10_000, dy))]) }
            let rx = mv.dx - Double(dx), ry = mv.dy - Double(dy)
            pendingMove = rx == 0 && ry == 0 ? nil : (rx, ry)
        }
        if let sc = pendingScroll {
            let dx = Int(sc.dx.rounded(.towardZero)), dy = Int(sc.dy.rounded(.towardZero))
            if dx != 0 || dy != 0 { c.send(json: ["type": "scroll", "dx": max(-5_000, min(5_000, dx)), "dy": max(-5_000, min(5_000, dy))]) }
            let rx = sc.dx - Double(dx), ry = sc.dy - Double(dy)
            pendingScroll = rx == 0 && ry == 0 ? nil : (rx, ry)
        }
    }

    // MARK: - Files (SPEC §7)

    private final class Outgoing {
        let id: String, name: String, size: Int64, url: URL
        var handle: FileHandle?
        var peer: Peer?
        var done: Int64 = 0
        var hasher = SHA256()
        init(id: String, name: String, size: Int64, url: URL) { self.id = id; self.name = name; self.size = size; self.url = url }
    }

    private final class Incoming {
        let id: String, name: String, size: Int64
        var folder: URL?
        var temp: URL?
        var handle: FileHandle?
        var peer: Peer?
        var done: Int64 = 0
        var hasher = SHA256()
        init(id: String, name: String, size: Int64) { self.id = id; self.name = name; self.size = size }
    }

    private func offerFile(_ url: URL) {
        guard paired, let c = control else { return }
        guard outgoing == nil else { return notice("A file is already being sent.") }
        let scoped = url.startAccessingSecurityScopedResource()
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init), size <= 4 << 30,
              let handle = try? FileHandle(forReadingFrom: url) else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            return notice("Can't read that file, or it is over 4 GB.")
        }
        var raw = Data(count: 8)
        _ = raw.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 8, $0.baseAddress!) }
        let t = Outgoing(id: raw.hex, name: FileNames.sanitize(url.lastPathComponent), size: size, url: url)
        t.handle = handle
        outgoing = t
        c.send(json: ["type": "file_offer", "id": t.id, "name": t.name, "size": size])
        progress(outgoing: true, "Waiting for your Mac", active: true)
    }

    private func fileMessage(_ type: String, _ m: [String: Any]) {
        let id = m["id"] as? String
        switch type {
        case "file_ticket":
            guard let t = m["ticket"] as? String else { return }
            if let o = outgoing, o.id == id { openFilePeer(ticket: t, sending: o) }
            else if let i = incoming, i.id == id { openFilePeer(ticket: t, receiving: i) }
        case "file_accept": if outgoing?.id == id { progress(outgoing: true, "Connecting", active: true) }
        case "file_reject": if outgoing?.id == id { failOutgoing("Declined on the Mac", tell: false) }
        case "file_cancel":
            if outgoing?.id == id { failOutgoing("Cancelled on the Mac", tell: false) }
            if incoming?.id == id { failIncoming("Cancelled on the Mac", tell: false) }
        case "file_result":
            guard let o = outgoing, o.id == id else { return }
            if m["ok"] as? Bool == true { finishOutgoing() } else { failOutgoing(m["error"] as? String ?? "Failed on the Mac", tell: false) }
        default: break
        }
    }

    private func openFilePeer(ticket: String, sending o: Outgoing? = nil, receiving i: Incoming? = nil) {
        guard let endpoint = target?.endpoint, let expected = control?.pin else { return }
        let gen = generation
        let p = Peer(NWConnection(to: Self.sameHost(control, fallback: endpoint), using: tlsParameters { $0 == expected }), queue: queue, role: .client)
        p.kind = .file
        p.onReady = { p in p.send(json: ["type": "hello", "versions": [1], "kind": "file", "ticket": ticket]) }
        p.onFrame = { [weak self] p, f in
            guard let self, gen == self.generation else { return }
            if case .json(let m) = f, m["type"] as? String == "welcome" { if let o { self.pump(o) }; return }
            guard let i, self.incoming === i else { return }
            switch f {
            case .fileChunk(let d):
                guard i.done + Int64(d.count) <= i.size else { return self.failIncoming("The Mac sent more data than offered", tell: true) }
                do { try i.handle?.write(contentsOf: d) } catch { return self.failIncoming("Couldn't write the file (storage full?)", tell: true) }
                i.hasher.update(data: d)
                i.done += Int64(d.count)
                self.progress(outgoing: false, "Receiving", active: true, done: i.done, size: i.size, name: i.name)
            case .json(let m) where m["type"] as? String == "file_end":
                self.finishIncoming(i, sha: (m["sha256"] as? String).flatMap { Data(base64Encoded: $0) })
            default:
                p.close(.unknownType)
            }
        }
        p.onClose = { [weak self] p, _ in
            guard let self, gen == self.generation else { return }
            if let o, self.outgoing === o, o.peer === p, o.done < o.size || o.size == 0 && o.handle != nil { self.failOutgoing("Connection lost", tell: false) }
            if let i, self.incoming === i, i.peer === p, i.handle != nil { self.failIncoming("Connection lost", tell: false) }
        }
        o?.peer = p
        i?.peer = p
        p.start()
    }

    /// One chunk at a time, paced by send completion, so file data never queues ahead of input.
    private func pump(_ o: Outgoing) {
        guard outgoing === o, let p = o.peer, let h = o.handle else { return }
        let chunk: Data
        do { chunk = try h.read(upToCount: 262_144) ?? Data() } catch { return failOutgoing("Couldn't read the file", tell: true) }
        if chunk.isEmpty {
            guard o.done == o.size else { return failOutgoing("The file changed while sending", tell: true) }
            try? h.close(); o.handle = nil
            p.send(json: ["type": "file_end", "sha256": Data(o.hasher.finalize()).base64EncodedString()])
            return progress(outgoing: true, "Verifying on your Mac", active: true, done: o.done, size: o.size, name: o.name)
        }
        o.hasher.update(data: chunk)
        o.done += Int64(chunk.count)
        progress(outgoing: true, "Sending", active: true, done: o.done, size: o.size, name: o.name)
        p.send(Frame.encode(type: Frame.fileChunkType, chunk)) { [weak self] in self?.pump(o) }
    }

    private func finishOutgoing() {
        guard let o = outgoing else { return }
        o.peer?.close()
        o.url.stopAccessingSecurityScopedResource()
        outgoing = nil
        progress(outgoing: true, "Sent", active: false, done: o.size, size: o.size, name: o.name)
    }

    private func failOutgoing(_ why: String, tell: Bool) {
        guard let o = outgoing else { return }
        if tell { control?.send(json: ["type": "file_cancel", "id": o.id]) }
        try? o.handle?.close()
        o.peer?.close()
        o.url.stopAccessingSecurityScopedResource()
        outgoing = nil
        progress(outgoing: true, why, active: false, done: o.done, size: o.size, name: o.name)
    }

    private func incomingOffer(_ m: [String: Any]) {
        guard let id = m["id"] as? String, id.count == 16, id.allSatisfy(\.isHexDigit), let raw = m["name"] as? String, raw.utf8.count <= 255,
              let size = (m["size"] as? NSNumber)?.int64Value, (0...(4 << 30)).contains(size) else { return protocolError("malformed") }
        guard incoming == nil else { return control?.send(json: ["type": "file_reject", "id": id, "reason": "busy"]) ?? () }
        let i = Incoming(id: id, name: FileNames.sanitize(raw), size: size)
        incoming = i
        let name = i.name
        model.map { m in Task { @MainActor in m.offer = (name, size) } }
    }

    /// The user picked a destination folder (or declined). Data goes to an exclusive temp file there first.
    private func acceptIncoming(_ folder: URL?) {
        guard let i = incoming, i.folder == nil else { return }
        guard let folder else {
            incoming = nil
            control?.send(json: ["type": "file_reject", "id": i.id, "reason": "declined"])
            return
        }
        _ = folder.startAccessingSecurityScopedResource()
        var tag = Data(count: 16)
        _ = tag.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard let (temp, handle) = FileNames.createExclusiveTemp(in: folder, tag: tag.hex) else {
            folder.stopAccessingSecurityScopedResource()
            incoming = nil
            control?.send(json: ["type": "file_reject", "id": i.id, "reason": "failed"])
            return notice("Can't write to that folder.")
        }
        i.folder = folder; i.temp = temp; i.handle = handle
        control?.send(json: ["type": "file_accept", "id": i.id])
        progress(outgoing: false, "Connecting", active: true, done: 0, size: i.size, name: i.name)
    }

    private func finishIncoming(_ i: Incoming, sha: Data?) {
        guard i.done == i.size, let sha, sha == Data(i.hasher.finalize()) else { return failIncoming("The file arrived damaged (hash mismatch)", tell: true) }
        try? i.handle?.close(); i.handle = nil
        guard let folder = i.folder, let temp = i.temp, let final = FileNames.publishExclusive(temp, in: folder, name: i.name) else {
            return failIncoming("Couldn't save the file", tell: true)
        }
        i.temp = nil
        control?.send(json: ["type": "file_result", "id": i.id, "ok": true])
        i.peer?.close()
        folder.stopAccessingSecurityScopedResource()
        incoming = nil
        progress(outgoing: false, "Saved as \(final)", active: false, done: i.size, size: i.size, name: final)
    }

    private func failIncoming(_ why: String, tell: Bool) {
        guard let i = incoming else { return }
        if tell { control?.send(json: ["type": "file_result", "id": i.id, "ok": false, "error": why]) }
        try? i.handle?.close()
        if let temp = i.temp { try? FileManager.default.removeItem(at: temp) } // only ever our own temp file
        i.peer?.close()
        i.folder?.stopAccessingSecurityScopedResource()
        incoming = nil
        if i.folder != nil { progress(outgoing: false, why, active: false, done: i.done, size: i.size, name: i.name) }
    }

    private func progress(outgoing isOut: Bool, _ status: String, active: Bool, done: Int64? = nil, size: Int64? = nil, name: String? = nil) {
        let o = outgoing
        let info = TransferInfo(name: name ?? o?.name ?? "", size: size ?? o?.size ?? 0, done: done ?? o?.done ?? 0, status: status, active: active)
        model.map { m in Task { @MainActor in if isOut { m.outgoing = info } else { m.incoming = info } } }
    }

    // MARK: - Helpers

    private func publish(_ s: SessionState) { model.map { m in Task { @MainActor in m.state = s } } }
    private func notice(_ text: String) { model.map { m in Task { @MainActor in m.notice = text } } }

    /// Mutual TLS 1.3 with this device's identity; `accept` sees the server's pin inside the handshake.
    private func tlsParameters(accept: @escaping (Data) -> Bool) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let o = tls.securityProtocolOptions
        sec_protocol_options_set_local_identity(o, identity.identity)
        sec_protocol_options_set_min_tls_protocol_version(o, .TLSv13)
        sec_protocol_options_set_verify_block(o, { _, trust, complete in
            let leaf = (SecTrustCopyCertificateChain(sec_trust_copy_ref(trust).takeRetainedValue()) as? [SecCertificate])?.first
            guard let leaf, let pin = SPKI.pin(of: leaf) else { return complete(false) }
            complete(accept(pin))
        }, queue)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true // input frames are tiny; Nagle would hold each one back
        tcp.connectionTimeout = 5
        return NWParameters(tls: tls, tcp: tcp)
    }

    static func describe(_ e: NWEndpoint) -> String {
        switch e {
        case .hostPort(let h, let p): return HostAddress(host: "\(h)".components(separatedBy: "%").first ?? "\(h)", port: Int(p.rawValue)).description
        case .service(let name, _, _, _): return name
        default: return "\(e)"
        }
    }

    /// The peer's resolved address as host:port, so the next connection can go straight there.
    static func remote(_ p: Peer) -> String? {
        guard case .hostPort(let h, let port)? = p.connection.currentPath?.remoteEndpoint else { return nil }
        let host = "\(h)".components(separatedBy: "%").first ?? "\(h)"
        return HostAddress(host: host, port: Int(port.rawValue)).description
    }

    /// Video and file channels go to the exact address the control channel reached.
    static func sameHost(_ control: Peer?, fallback: NWEndpoint) -> NWEndpoint {
        control?.connection.currentPath?.remoteEndpoint ?? fallback
    }

    static func explain(_ code: String) -> String {
        switch code {
        case "permission_accessibility": "Grant Accessibility to Tetherly on the Mac to use the pointer and keyboard."
        case "permission_screen_recording": "Grant Screen Recording to Tetherly on the Mac to see the screen."
        case "not_paired": "This Mac isn't paired with this device. Turn on pairing on the Mac, then tap Pair."
        case "pairing_closed": "Pairing mode is off on the Mac."
        case "pairing_failed": "Pairing failed. Nothing was saved."
        case "busy": "Another device is connected to this Mac."
        case "revoked": "This device was removed on the Mac. Pair again to reconnect."
        case "rate_limited": "The Mac received input too quickly and ended the session."
        case "unsupported_version": "Update Tetherly on both devices."
        case "timeout": "The connection timed out."
        case "frame_too_large", "malformed", "unknown_type": "The Mac rejected a message (\(code)). Make sure both apps are up to date."
        default: "The connection was lost."
        }
    }
}
