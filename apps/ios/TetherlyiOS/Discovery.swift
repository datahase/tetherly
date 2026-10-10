import Foundation
import Network
import Observation

/// Finds Macs: Bonjour on the local network, plus Tailscale routes the Mac reported (probed with a bare TCP connect).
@MainActor @Observable
final class Discovery {
    enum Reach { case wifi, tailscale, offline }

    private(set) var nearby: [String] = []
    private(set) var failed: String?
    private(set) var tailscaleOn = false
    private(set) var reachByPin: [String: Reach] = [:]
    private(set) var tailscaleAddress: [String: HostAddress] = [:]
    private var endpoints: [String: NWEndpoint] = [:]
    private var browser: NWBrowser?
    private var probeTimer: Timer?

    func start() {
        browser?.cancel()
        let b = NWBrowser(for: .bonjour(type: "_tetherly._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self else { return }
                var names: [String] = [], map: [String: NWEndpoint] = [:]
                for r in results.prefix(32) {
                    if case .service(let name, _, _, _) = r.endpoint { let n = String(name.prefix(63)); names.append(n); map[n] = r.endpoint }
                }
                self.nearby = names.sorted()
                self.endpoints = map
            }
        }
        b.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .failed: self?.failed = "Can't search this network. Allow Local Network access in Settings, or connect by address."
                case .ready: self?.failed = nil
                default: break
                }
            }
        }
        b.start(queue: .main)
        browser = b
        probeTimer?.invalidate()
        probeTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.probe(MacStore.load()) }
        }
    }

    func restart() { start() }

    func endpoint(named name: String) -> NWEndpoint? { endpoints[name] }

    func reach(of mac: PairedMac) -> Reach {
        nearby.contains(mac.hostName) ? .wifi : reachByPin[mac.pin] ?? .offline
    }

    /// Checks each paired Mac's Tailscale address with a plain TCP connect (no TLS, nothing sent).
    func probe(_ macs: [PairedMac]) {
        tailscaleOn = Self.tailscaleActive()
        guard tailscaleOn else { for m in macs { reachByPin[m.pin] = .offline }; return }
        for mac in macs {
            let port = HostAddress.parse(mac.address)?.port ?? HostAddress.defaultPort
            var hosts = mac.routes.filter(\.tailscale).map(\.ip)
            if let h = HostAddress.parse(mac.address)?.host, isTailscaleHost(h) { hosts.append(h) }
            guard let ip = Array(Set(hosts)).first else { reachByPin[mac.pin] = .offline; continue }
            let c = NWConnection(host: NWEndpoint.Host(ip), port: NWEndpoint.Port(integerLiteral: UInt16(port)), using: .tcp)
            let pin = mac.pin
            c.stateUpdateHandler = { [weak self] state in
                let result: Reach? = switch state {
                case .ready: .tailscale
                case .failed, .waiting: .offline
                default: nil
                }
                guard let result else { return }
                c.cancel()
                Task { @MainActor in
                    self?.reachByPin[pin] = result
                    if result == .tailscale { self?.tailscaleAddress[pin] = HostAddress(host: ip, port: port) }
                }
            }
            c.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { c.cancel() }
        }
    }

    /// Tailscale shows up as a utun interface with a 100.64.0.0/10 address.
    static func tailscaleActive() -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return false }
        defer { freeifaddrs(ifaddr) }
        var p = ifaddr
        while let a = p?.pointee {
            defer { p = a.ifa_next }
            guard let sa = a.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            if isTailscaleHost(String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)) { return true }
        }
        return false
    }
}
