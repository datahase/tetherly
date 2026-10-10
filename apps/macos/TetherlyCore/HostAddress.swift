import Foundation

/// A host the user typed or scanned: IPv4, DNS name (LAN, .local, Tailscale MagicDNS) or IPv6 literal, with optional
/// port. Same strict grammar as the Android client; purely syntactic, never touches DNS. IPv6 zone IDs are rejected.
struct HostAddress: Equatable, Hashable, CustomStringConvertible {
    static let defaultPort = 47800
    var host: String
    var port: Int

    var description: String { host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)" }

    static func parse(_ input: String) -> HostAddress? {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= 261, text.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) else { return nil }
        if text.hasPrefix("[") {
            guard let end = text.firstIndex(of: "]") else { return nil }
            let host = String(text[text.index(after: text.startIndex)..<end])
            guard isIPv6(host) else { return nil }
            let rest = text[text.index(after: end)...]
            if rest.isEmpty { return HostAddress(host: host, port: defaultPort) }
            guard rest.hasPrefix(":"), let p = port(String(rest.dropFirst())) else { return nil }
            return HostAddress(host: host, port: p)
        }
        if text.filter({ $0 == ":" }).count > 1 { return isIPv6(text) ? HostAddress(host: text, port: defaultPort) : nil }
        let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let host = parts[0]
        var p = defaultPort
        if parts.count == 2 { guard let parsed = port(parts[1]) else { return nil }; p = parsed }
        let numeric = host.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
        guard isIPv4(host) || (!numeric && isHostname(host)) else { return nil }
        return HostAddress(host: host, port: p)
    }

    static func isIPLiteral(_ host: String) -> Bool { isIPv4(host) || isIPv6(host) }

    private static func port(_ text: String) -> Int? {
        guard (1...5).contains(text.count), text.allSatisfy({ $0.isASCII && $0.isNumber }), let v = Int(text), (1...65535).contains(v) else { return nil }
        return v
    }

    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { p in
            (1...3).contains(p.count) && p.allSatisfy { $0.isASCII && $0.isNumber } && (p == "0" || !p.hasPrefix("0")) && Int(p)! <= 255
        }
    }

    private static func isHostname(_ host: String) -> Bool {
        host.count <= 253 && host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            (1...63).contains(label.count) && label.first != "-" && label.last != "-" &&
                label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    private static func isIPv6(_ host: String) -> Bool {
        guard (2...45).contains(host.count), host.filter({ $0 == ":" }).count >= 2 else { return false }
        // RFC 4291 §2.2: a dotted IPv4 part may only occupy the final 32 bits.
        if let dot = host.firstIndex(of: "."), let colon = host.lastIndex(of: ":"), dot < colon { return false }
        let halves = host.components(separatedBy: "::")
        guard halves.count <= 2 else { return false }
        let groups = halves.flatMap { $0.isEmpty ? [] : $0.split(separator: ":", omittingEmptySubsequences: false).map(String.init) }
        guard !groups.contains(where: \.isEmpty) else { return false }
        let tail = groups.last.map { $0.contains(".") } ?? false
        if tail, !isIPv4(groups.last!) { return false }
        let hex = tail ? Array(groups.dropLast()) : groups
        guard hex.allSatisfy({ g in (1...4).contains(g.count) && g.allSatisfy(\.isHexDigit) }) else { return false }
        let count = hex.count + (tail ? 2 : 0)
        return halves.count == 2 ? count <= 7 : count == 8
    }
}

/// Tailscale addresses (100.64.0.0/10) and MagicDNS names.
func isTailscaleHost(_ host: String) -> Bool {
    if host.lowercased().hasSuffix(".ts.net") { return true }
    let p = host.split(separator: ".").compactMap { Int($0) }
    return p.count == 4 && p[0] == 100 && (64...127).contains(p[1])
}

/// SPEC §4a QR pairing link. Returns nil for anything that isn't a valid v1 link; the QR is untrusted input.
struct PairLink: Equatable {
    let name: String
    let addresses: [HostAddress]
    let pin: Data

    static func parse(_ text: String, now: Date = Date()) -> PairLink? {
        guard text.count <= 1024, let c = URLComponents(string: text.trimmingCharacters(in: .whitespaces)),
              c.scheme?.lowercased() == "tetherly", c.host == "pair", let items = c.queryItems else { return nil }
        var q: [String: String] = [:]
        for i in items { q[i.name] = i.value ?? "" }
        guard q["v"] == "1" else { return nil }
        // Expired pairing windows are refused; 300 s allows for clock skew between the Mac and the phone.
        guard let e = q["e"], (1...12).contains(e.count), e.allSatisfy(\.isNumber), let exp = Double(e), exp >= now.timeIntervalSince1970 - 300 else { return nil }
        guard let p = q["p"], (1...5).contains(p.count), p.allSatisfy(\.isNumber), let port = Int(p), (1...65535).contains(port) else { return nil }
        guard let k = q["k"], let pin = Data(base64URL: k), pin.count == 32 else { return nil }
        guard let raw = q["a"]?.split(separator: ",", omittingEmptySubsequences: false).map(String.init), (1...4).contains(raw.count) else { return nil }
        var addresses: [HostAddress] = []
        for a in raw {
            // Each entry is a bare host; the port comes from `p`.
            guard var parsed = HostAddress.parse(a), parsed.port == HostAddress.defaultPort, !a.hasSuffix(":\(HostAddress.defaultPort)") else { return nil }
            parsed.port = port
            addresses.append(parsed)
        }
        return PairLink(name: String((q["n"] ?? "").prefix(64)), addresses: addresses, pin: pin)
    }
}

extension Data {
    init?(base64URL s: String) {
        guard s.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        self.init(base64Encoded: b)
    }
}
