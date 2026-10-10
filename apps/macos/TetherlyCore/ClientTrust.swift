import Foundation

/// An address the Mac reported for itself (SPEC §5 host_info). A hint for reaching it; identity is still the pin.
struct MacRoute: Codable, Equatable, Hashable {
    let ip: String, kind: String
    var tailscale: Bool { kind == "tailscale" }
}

/// A Mac this device has paired with. `pin` is lowercase hex; `address` is the last address that worked (host:port).
struct PairedMac: Codable, Equatable, Identifiable {
    var hostName: String
    let pin: String
    var address: String
    var routes: [MacRoute] = []
    var id: String { pin }
}

enum ClientTrust: Equatable {
    case known(PairedMac), newPairing, rejected(String)

    static let alreadyKnown = "This Mac already knows this device. Revoke it on the Mac and pair again."
    static let identityChanged = "This Mac's identity changed. Forget it and pair again."

    /// Decided inside the TLS verify step from the server pin alone. Names and addresses are hints, never trust.
    static func decide(pin: String, address: String, macs: [PairedMac], pairIntent: Bool, expectedPin: String? = nil) -> ClientTrust {
        if let expectedPin, expectedPin != pin { return .rejected("This isn't the Mac from the QR code.") }
        if let m = macs.first(where: { $0.pin == pin }) { return .known(m) }
        // A stored Mac's address answering with another key is never silently re-paired, even when the user tapped Pair.
        if macs.contains(where: { $0.address == address }) { return .rejected(identityChanged) }
        return pairIntent ? .newPairing : .rejected("This Mac isn't paired with this device. Turn on pairing on the Mac, then tap Pair.")
    }

    enum Welcome: Equatable { case session(PairedMac), pair, rejected(String) }

    /// Combines the handshake decision with what the Mac says about us in `welcome` (SPEC §4.2).
    static func checkWelcome(_ trust: ClientTrust, state: String, host: String, macs: [PairedMac], pairIntent: Bool) -> Welcome {
        switch trust {
        case .known(let m) where state == "paired": return .session(m)
        case .known where pairIntent: return .pair
        case .known: return .rejected("This Mac no longer recognizes this device. Turn on pairing on the Mac, then tap Pair.")
        default:
            if state == "paired" { return .rejected(alreadyKnown) }
            if macs.contains(where: { $0.hostName == host }) { return .rejected(identityChanged) }
            return .pair
        }
    }

    /// Validates a host_info payload: at most 8 IPv4 literals, kinds lan or tailscale.
    static func routes(_ m: [String: Any]) -> [MacRoute]? {
        guard let a = m["addresses"] as? [[String: Any]], a.count <= 8 else { return nil }
        var out: [MacRoute] = []
        for e in a {
            guard let ip = e["ip"] as? String, ip.count <= 15, let kind = e["kind"] as? String, kind == "lan" || kind == "tailscale",
                  let parsed = HostAddress.parse(ip), parsed.host == ip, !ip.contains(":"), HostAddress.isIPLiteral(ip) else { return nil }
            out.append(MacRoute(ip: ip, kind: kind))
        }
        return out
    }
}
