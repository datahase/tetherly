import Foundation
import Network
import Observation
import UIKit

/// Main-actor face of the session engine and discovery: everything the SwiftUI screens read.
@MainActor @Observable
final class SessionModel {
    var state: SessionState = .idle
    var notice: String?
    var display: CGSize?
    var cursor: CGPoint?
    var videoSize: CGSize?
    var videoStopped: String?
    var outgoing: TransferInfo?
    var incoming: TransferInfo?
    var offer: (name: String, size: Int64)?
    var macs: [PairedMac] = MacStore.load()
    var settings = VideoSettings()
    var pendingLink: PairLink?
    var macSound = false
    let maxFps: Int
    let startupError: String?
    let engine: SessionEngine?
    let renderer = VideoRenderer()
    let discovery = Discovery()

    init() {
        maxFps = max(30, UIScreen.main.maximumFramesPerSecond)
        do {
            let e = SessionEngine(identity: try PhoneIdentity.loadOrCreate(), renderer: renderer)
            engine = e
            startupError = nil
            e.model = self
        } catch {
            engine = nil
            startupError = "Couldn't create this device's identity: \(error)"
        }
        settings.fps = maxFps
        engine?.setVideo(settings)
        discovery.start()
        #if DEBUG
        // Test harness for the Simulator (no UI to tap): `simctl launch … -MBConnect 127.0.0.1 -MBPair YES -MBAutoConfirm YES`.
        // Debug builds only; the Mac still requires its own code comparison and approval.
        let d = UserDefaults.standard
        if let a = d.string(forKey: "MBConnect") { connect(address: a, pair: d.bool(forKey: "MBPair")) }
        if d.bool(forKey: "MBAutoConfirm") { autoConfirm = true }
        #endif
    }

    #if DEBUG
    var autoConfirm = false
    #endif

    func macsChanged() {
        macs = MacStore.load()
        discovery.probe(macs)
    }

    func connect(_ mac: PairedMac) {
        switch discovery.reach(of: mac) {
        case .wifi:
            if let ep = discovery.endpoint(named: mac.hostName) { engine?.connect([ep], label: mac.hostName, pair: false) }
        case .tailscale:
            if let a = discovery.tailscaleAddress[mac.pin] { engine?.connect([Self.endpoint(a)], label: mac.hostName, pair: false) }
        case .offline:
            guard let a = HostAddress.parse(mac.address) else { return notice = "This saved address can't be used. Connect by address instead." }
            engine?.connect([Self.endpoint(a)], label: mac.hostName, pair: false)
        }
    }

    func connect(address: String, pair: Bool) {
        guard let a = HostAddress.parse(address) else { return }
        engine?.connect([Self.endpoint(a)], label: a.description, pair: pair)
    }

    func connectNearby(_ name: String, pair: Bool) {
        guard let ep = discovery.endpoint(named: name) else { return }
        engine?.connect([ep], label: name, pair: pair)
    }

    func pair(with link: PairLink) {
        engine?.connect(link.addresses.map(Self.endpoint), label: link.name.isEmpty ? "your Mac" : link.name, pair: true, expectedPin: link.pin)
    }

    func forget(_ mac: PairedMac) {
        MacStore.save(MacStore.load().filter { $0.pin != mac.pin })
        macsChanged()
    }

    func setVideo(_ s: VideoSettings) {
        guard s != settings else { return }
        settings = s
        engine?.setVideo(s)
    }

    func refresh() async {
        discovery.restart()
        discovery.probe(macs)
        try? await Task.sleep(for: .seconds(1.2))
    }

    func toggleMacSound() {
        macSound.toggle()
        engine?.setMacSound(macSound)
    }

    static func endpoint(_ a: HostAddress) -> NWEndpoint {
        .hostPort(host: NWEndpoint.Host(a.host), port: NWEndpoint.Port(integerLiteral: UInt16(a.port)))
    }
}
