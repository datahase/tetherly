import Foundation

/// Approved device pins, persisted as JSON (public keys only, no secrets).
final class TrustStore: @unchecked Sendable {
    struct Device: Codable { let pin: String, name: String, pairedAt: Date }
    private let lock = NSLock()
    private var devices: [Device]
    private let url: URL

    static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Tetherly")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("devices.json")
    }

    init(url: URL) {
        self.url = url
        devices = (try? JSONDecoder().decode([Device].self, from: Data(contentsOf: url))) ?? []
    }

    var all: [Device] { lock.withLock { devices } }
    func isApproved(_ pin: Data) -> Bool { lock.withLock { devices.contains { $0.pin == pin.hex } } }
    func name(_ pin: Data) -> String? { lock.withLock { devices.first { $0.pin == pin.hex }?.name } }
    func pin(named name: String) -> Data? { lock.withLock { devices.first { $0.name == name }.flatMap { Data(hex: $0.pin) } } }

    /// Durable add: memory changes only after the file write succeeded, so a failed pairing approves nothing.
    func add(pin: Data, name: String) throws {
        try lock.withLock {
            var next = devices.filter { $0.pin != pin.hex }
            next.append(Device(pin: pin.hex, name: name, pairedAt: Date()))
            try save(next)
            devices = next
        }
    }

    /// Fail closed: the pin is dropped from memory even if the write fails; the error is reported to the caller.
    func remove(pin: Data) throws {
        try lock.withLock {
            devices.removeAll { $0.pin == pin.hex }
            try save(devices)
        }
    }

    private func save(_ list: [Device]) throws { try JSONEncoder().encode(list).write(to: url, options: .atomic) }
}
