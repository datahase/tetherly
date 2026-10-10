import AppKit
import Foundation

/// Main-actor face of `BridgeHost`: holds the latest snapshot and runs the prompts that need a person.
@MainActor @Observable
final class HostModel {
    private(set) var snapshot = BridgeHost.Snapshot()
    private(set) var startupError: String?
    private(set) var addresses: [String] = []
    private var host: BridgeHost?
    private var pairingAlert: NSAlert?
    private static let hostingKey = "hostingEnabled"

    init() {
        do {
            let host = BridgeHost(identity: try HostIdentity.loadOrCreate())
            host.onSnapshot = { [weak self] in self?.snapshot = $0; self?.addresses = Self.localAddresses() }
            host.askPairing = { [weak self] device, code, reply in self?.confirmPairing(device: device, code: code, reply: reply) }
            host.pairingEnded = { [weak self] in self?.dismissPairingAlert() }
            host.askSaveLocation = { name, size, device, reply in Self.chooseSaveLocation(name: name, size: size, device: device, reply: reply) }
            self.host = host
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak host] _ in
                host?.displayChanged()
            }
            UserDefaults.standard.register(defaults: [Self.hostingKey: true])
            host.setHosting(UserDefaults.standard.bool(forKey: Self.hostingKey))
        } catch {
            startupError = "Couldn't create this Mac's identity: \(error)"
        }
    }

    /// SPEC §4a pairing link: addresses, port and this Mac's pin; no secrets.
    var pairingLink: String {
        var c = URLComponents()
        c.scheme = "tetherly"
        c.host = "pair"
        let pin = snapshot.hostPin.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        c.queryItems = [
            URLQueryItem(name: "v", value: "1"), URLQueryItem(name: "n", value: snapshot.hostName),
            URLQueryItem(name: "a", value: addresses.prefix(4).map { $0.replacingOccurrences(of: " (Tailscale)", with: "") }.joined(separator: ",")),
            URLQueryItem(name: "p", value: String(BridgeHost.port.rawValue)), URLQueryItem(name: "k", value: pin),
            URLQueryItem(name: "e", value: String(Int(snapshot.pairingUntil?.timeIntervalSince1970 ?? 0))),
        ]
        return c.string ?? ""
    }

    func setHosting(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.hostingKey)
        host?.setHosting(on)
    }

    func startPairing() { host?.startPairing() }
    func stopPairing() { host?.stopPairing() }
    func disconnect() { host?.disconnect() }
    func cancelTransfer(_ id: String) { host?.cancelTransfer(id) }

    func revoke(_ device: BridgeHost.Snapshot.Device) {
        let alert = NSAlert()
        alert.messageText = "Revoke \(device.name)?"
        alert.informativeText = "It will be disconnected now and can't reconnect unless you pair it again."
        alert.addButton(withTitle: "Revoke")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { host?.revoke(device.id) }
    }

    func sendFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose one file to send to \(snapshot.sessionDevice ?? "your device")"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { host?.offerFile(url) }
    }

    private func confirmPairing(device: String, code: [Int], reply: @escaping @Sendable (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Pair with \(device)?"
        alert.informativeText = "Allow only if your phone shows exactly this code:\n\n\(PairingMath.formatted(code))\n\nA paired device can see and control this Mac."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Reject")
        pairingAlert = alert
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        let wasShowing = pairingAlert === alert
        pairingAlert = nil
        reply(wasShowing && response == .alertFirstButtonReturn)
    }

    private func dismissPairingAlert() {
        guard let alert = pairingAlert else { return }
        pairingAlert = nil
        NSApp.stopModal(withCode: .abort)
        alert.window.orderOut(nil)
    }

    private static func chooseSaveLocation(name: String, size: Int64, device: String, reply: @escaping @Sendable (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.message = "\(device) wants to send “\(name)” (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))). Choose where to save it."
        panel.prompt = "Receive"
        NSApp.activate(ignoringOtherApps: true)
        reply(panel.runModal() == .OK ? panel.url : nil)
    }

    private static func localAddresses() -> [String] {
        BridgeHost.localAddresses().map { $0.kind == "tailscale" ? "\($0.ip) (Tailscale)" : $0.ip }
    }
}
