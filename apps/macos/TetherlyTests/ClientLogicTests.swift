import XCTest

/// Same cases as the Android client's HostAddressTest, PairLinkTest, ViewTransformTest and TrustTest.
final class ClientLogicTests: XCTestCase {
    func testHostAddressAcceptsSupportedForms() {
        let d = HostAddress.defaultPort
        let cases: [(String, HostAddress)] = [
            (" 192.168.1.20 ", .init(host: "192.168.1.20", port: d)), ("my-mac.local:9000", .init(host: "my-mac.local", port: 9000)),
            ("my-mac.tail1234.ts.net", .init(host: "my-mac.tail1234.ts.net", port: d)), ("::1", .init(host: "::1", port: d)),
            ("::ffff:192.168.1.1", .init(host: "::ffff:192.168.1.1", port: d)), ("[fd7a:115c:a1e0::1]:5", .init(host: "fd7a:115c:a1e0::1", port: 5)),
            ("1:2:3:4:5:6:7:8", .init(host: "1:2:3:4:5:6:7:8", port: d)),
        ]
        for (input, expected) in cases { XCTAssertEqual(HostAddress.parse(input), expected, input) }
    }

    func testHostAddressRejectsMalformed() {
        for bad in ["", "host:0", "host:65536", "host:", "host:+1", "http://host", "user@host", "my mac", ".local", "-host",
                    "foo:bar:baz", "256.1.1.1", "01.2.3.4", "123", "[::1", "[::1]:", "[host]", "1::2::3", "fe80::1%en0",
                    "192.0.2.1::", "1:192.0.2.1::", "mäc.local"] {
            XCTAssertNil(HostAddress.parse(bad), bad)
        }
    }

    func testPairLink() {
        let pin = Data((0..<32).map { UInt8($0 * 7 & 0xff) })
        let k = pin.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let link = PairLink.parse("tetherly://pair?v=1&n=Studio%20MacBook&a=192.168.1.20,100.101.102.103&p=47801&k=\(k)&e=1800000120", now: now)
        XCTAssertEqual(link?.name, "Studio MacBook")
        XCTAssertEqual(link?.addresses, [.init(host: "192.168.1.20", port: 47801), .init(host: "100.101.102.103", port: 47801)])
        XCTAssertEqual(link?.pin, pin)
        let base = "tetherly://pair?v=1&n=M&a=10.0.0.1&p=47800&k=\(k)&e="
        XCTAssertNotNil(PairLink.parse(base + "1799999700", now: now))
        XCTAssertNil(PairLink.parse(base + "1799999699", now: now), "expired beyond skew")
        for bad in ["tetherly://pair?v=2&n=M&a=10.0.0.1&p=47800&k=\(k)&e=1800000000",
                    "tetherly://pair?v=1&n=M&a=10.0.0.1&p=47800&k=\(k.dropLast(2))&e=1800000000",
                    "tetherly://pair?v=1&n=M&a=10.0.0.1:99&p=47800&k=\(k)&e=1800000000",
                    "tetherly://pair?v=1&n=M&a=1.1.1.1,2.2.2.2,3.3.3.3,4.4.4.4,5.5.5.5&p=47800&k=\(k)&e=1800000000",
                    "https://pair?v=1&n=M&a=10.0.0.1&p=47800&k=\(k)&e=1800000000"] {
            XCTAssertNil(PairLink.parse(bad, now: now), bad)
        }
    }

    func testViewTransformMatchesAndroid() {
        let content = Rect.letterbox(viewW: 1080, viewH: 1800, videoW: 1710, videoH: 1112)
        let t = ViewTransform(viewW: 1080, viewH: 1800, content: content)
        XCTAssertEqual(t.clamp(Zoom()), Zoom())
        let z = t.pinch(Zoom(), factor: 3, fx: 400, fy: 900, dx: 0, dy: 0)
        let before = t.toVideo(Zoom(), 400, 900)!, after = t.toVideo(z, 400, 900)!
        XCTAssertEqual(before.0, after.0, accuracy: 1e-6); XCTAssertEqual(before.1, after.1, accuracy: 1e-6)
        let zz = t.clamp(Zoom(scale: 3, x: -1080, y: -1800))
        XCTAssertEqual(t.toView(t.follow(zz, 0.95, 0.5), 0.95, 0.5).0, 1080 * 0.85, accuracy: 0.5)
        XCTAssertNil(t.toVideo(Zoom(), 500, content.top - 1))
        XCTAssertEqual(classifyTwoFinger(startSpan: 400, span: 440, travel: 5), .zoom)
        XCTAssertEqual(classifyTwoFinger(startSpan: 400, span: 410, travel: 30), .scroll)
        XCTAssertEqual(classifyTwoFinger(startSpan: 60, span: 70, travel: 10), .undecided)
        XCTAssertEqual(trackpadGain(500), 2.4, accuracy: 1e-9)
        XCTAssertNil(swipeShortcut(dx: 10, dy: -20, threshold: 100))
        XCTAssertEqual(swipeShortcut(dx: 30, dy: -120, threshold: 100), 126)
        XCTAssertEqual(swipeShortcut(dx: 0, dy: 150, threshold: 100), 125)
        XCTAssertEqual(swipeShortcut(dx: -130, dy: 40, threshold: 100), 124)
        XCTAssertEqual(swipeShortcut(dx: 130, dy: 0, threshold: 100), 123)
    }

    func testTrustDecisions() {
        let studio = PairedMac(hostName: "Studio", pin: "aa", address: "old.local:47800")
        XCTAssertEqual(ClientTrust.decide(pin: "aa", address: "x:1", macs: [studio], pairIntent: false), .known(studio))
        XCTAssertEqual(ClientTrust.decide(pin: "bb", address: "old.local:47800", macs: [studio], pairIntent: true), .rejected(ClientTrust.identityChanged))
        XCTAssertEqual(ClientTrust.decide(pin: "bb", address: "new:1", macs: [studio], pairIntent: true), .newPairing)
        XCTAssertEqual(ClientTrust.decide(pin: "bb", address: "new:1", macs: [], pairIntent: true, expectedPin: "cc"), .rejected("This isn't the Mac from the QR code."))
        XCTAssertEqual(ClientTrust.checkWelcome(.newPairing, state: "paired", host: "Studio", macs: [], pairIntent: true), .rejected(ClientTrust.alreadyKnown))
        XCTAssertEqual(ClientTrust.checkWelcome(.newPairing, state: "pairing", host: "Studio", macs: [studio], pairIntent: true), .rejected(ClientTrust.identityChanged))
        XCTAssertEqual(ClientTrust.routes(["addresses": [["ip": "100.101.102.103", "kind": "tailscale"]]]), [MacRoute(ip: "100.101.102.103", kind: "tailscale")])
        XCTAssertNil(ClientTrust.routes(["addresses": [["ip": "mac.local", "kind": "lan"]]]))
        XCTAssertNil(ClientTrust.routes(["addresses": Array(repeating: ["ip": "10.0.0.1", "kind": "lan"], count: 9)]))
        XCTAssertTrue(isTailscaleHost("100.64.0.1")); XCTAssertFalse(isTailscaleHost("100.128.0.1"))
    }
}
