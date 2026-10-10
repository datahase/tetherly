import Foundation
import Testing

private let qrTestNow = Date(timeIntervalSince1970: 1_800_000_000)
private let qrTestPin = Data(repeating: 7, count: 32)
private let qrTestKey = qrTestPin.base64EncodedString().replacingOccurrences(of: "=", with: "")

@Test func pairingQRRetainsIdentityAndBothRoutes() throws {
    let link = try #require(PairLink.parse(
        "tetherly://pair?v=1&n=Test%20Mac&a=192.0.2.10,100.101.102.103&p=47800&k=\(qrTestKey)&e=1800000120",
        now: qrTestNow
    ))
    #expect(link.name == "Test Mac")
    #expect(link.pin == qrTestPin)
    #expect(link.addresses.map(\.host) == ["192.0.2.10", "100.101.102.103"])
    #expect(link.addresses.allSatisfy { $0.port == 47800 })
}

@Test(arguments: [
    "tetherly://pair?v=1&a=192.0.2.10&p=47800&k=KEY&e=1799999699", // Expired beyond clock skew.
    "tetherly://pair?v=2&a=192.0.2.10&p=47800&k=KEY&e=1800000120", // Unsupported contract.
    "tetherly://pair?v=1&a=192.0.2.10&p=0&k=KEY&e=1800000120", // Invalid port.
    "tetherly://pair?v=1&a=192.0.2.10&p=47800&k=short&e=1800000120", // Invalid identity pin.
    "tetherly://pair?v=1&a=192.0.2.10,bad_host&p=47800&k=KEY&e=1800000120", // Invalid route.
    "https://pair?v=1&a=192.0.2.10&p=47800&k=KEY&e=1800000120", // Unrelated QR scheme.
])
func pairingQRRejectsInvalidOrExpiredLinks(_ text: String) {
    #expect(PairLink.parse(text.replacingOccurrences(of: "KEY", with: qrTestKey), now: qrTestNow) == nil)
}
