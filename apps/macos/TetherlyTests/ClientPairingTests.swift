import CryptoKit
import XCTest

/// The phone machine against the real Mac machine: both ends of SPEC §4 in one process.
final class ClientPairingTests: XCTestCase {
    private let pinC = Data(repeating: 0xC1, count: 32), pinS = Data(repeating: 0x5E, count: 32)
    private let cb = Data(repeating: 0xCB, count: 32), pid = Data(repeating: 0x1D, count: 16)

    private func pair() -> (HostPairing, ClientPairing) {
        (HostPairing(pairingId: pid, pinC: pinC, pinS: pinS, cb: cb), ClientPairing(pairingId: pid, pinC: pinC, pinS: pinS, cb: cb))
    }

    private func sends(_ a: [HostPairing.Action]) -> [[String: String]] { a.compactMap { if case .send(let m) = $0 { m } else { nil } } }

    func testFullExchangeBothSidesAgreeAndStore() throws {
        let (mac, phone) = pair()
        let key = try XCTUnwrap(sends(mac.receive(phone.commit())).first)
        let reveal = try XCTUnwrap(try phone.receive(key))
        let shown = mac.receive(reveal)
        XCTAssertEqual(shown, [.showCode(phone.code!)], "both screens show the same code")
        _ = mac.receive(try XCTUnwrap(phone.confirm()))
        let approve = mac.decide(true)
        XCTAssertNil(try phone.receive(sends(approve)[0]))
        XCTAssertEqual(phone.state, .awaitDone)
        XCTAssertTrue(approve.contains(.persist))
        let done = sends(mac.persisted(true))
        XCTAssertNil(try phone.receive(done[0]))
        XCTAssertEqual(phone.state, .done)
        XCTAssertEqual(mac.state, .done)
    }

    func testPhoneRejectsBadServerMacAndEarlyDone() throws {
        let (mac, phone) = pair()
        let key = sends(mac.receive(phone.commit()))[0]
        _ = mac.receive(try XCTUnwrap(try phone.receive(key)))
        XCTAssertThrowsError(try phone.receive(["type": "pair_done"])) // before the server confirmed
        XCTAssertEqual(phone.state, .failed)

        let (_, phone2) = pair()
        let host2 = HostPairing(pairingId: pid, pinC: pinC, pinS: pinS, cb: cb)
        let key2 = sends(host2.receive(phone2.commit()))[0]
        _ = try phone2.receive(key2)
        XCTAssertThrowsError(try phone2.receive(["type": "pair_confirm", "mac": Data(count: 32).base64EncodedString()]))
    }

    func testDuplicatesAndInvalidKeysFailWithoutStoring() throws {
        let (mac, phone) = pair()
        let key = sends(mac.receive(phone.commit()))[0]
        _ = try phone.receive(key)
        XCTAssertThrowsError(try phone.receive(key), "duplicate pair_key")
        let fresh = ClientPairing(pairingId: pid, pinC: pinC, pinS: pinS, cb: cb)
        XCTAssertThrowsError(try fresh.receive(["type": "pair_key", "key": (Data([4]) + Data(repeating: 7, count: 64)).base64EncodedString()]))
        XCTAssertNotEqual(fresh.state, .done)
    }

    func testCancelAtAnyPointNeverReachesDone() throws {
        let (mac, phone) = pair()
        _ = try phone.receive(sends(mac.receive(phone.commit()))[0])
        XCTAssertEqual(phone.cancel(), ["type": "pair_cancel"])
        XCTAssertThrowsError(try phone.receive(["type": "pair_done"]))
        XCTAssertEqual(phone.state, .failed)
    }
}
