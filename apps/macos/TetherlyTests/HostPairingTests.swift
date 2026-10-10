import CryptoKit
import XCTest

/// SPEC §4.1/§4.2 state machine on the Mac side, driven by a simulated phone that uses the same math.
final class HostPairingTests: XCTestCase {
    private let pinC = Data(repeating: 0xC1, count: 32), pinS = Data(repeating: 0x5E, count: 32)
    private let cb = Data(repeating: 0xCB, count: 32), pid = Data(repeating: 0x1D, count: 16)

    private struct Phone {
        let eph = P256.KeyAgreement.PrivateKey()
        let pinC: Data, pinS: Data, cb: Data, pid: Data
        var pub: Data { eph.publicKey.x963Representation }
        var commit: [String: Any] { ["type": "pair_commit", "commitment": PairingMath.commitment(pub).base64EncodedString()] }
        var reveal: [String: Any] { ["type": "pair_reveal", "key": pub.base64EncodedString()] }
        func derive(_ serverKey: Data) throws -> PairingMath.Derived {
            PairingMath.derive(z: try PairingMath.agree(eph, peerX963: serverKey), pairingId: pid, pinC: pinC, pinS: pinS, cb: cb,
                               ephC: pub, ephS: serverKey)
        }
        func confirm(_ d: PairingMath.Derived) -> [String: Any] {
            ["type": "pair_confirm", "mac": PairingMath.mac(d.key, role: "client", pin: pinC).base64EncodedString()]
        }
    }

    private func make() -> (HostPairing, Phone) {
        (HostPairing(pairingId: pid, pinC: pinC, pinS: pinS, cb: cb), Phone(pinC: pinC, pinS: pinS, cb: cb, pid: pid))
    }

    private func serverKey(_ actions: [HostPairing.Action]) throws -> Data {
        guard case .send(let m) = actions.first, m["type"] == "pair_key" else { throw XCTSkip("no pair_key") }
        return Data(base64Encoded: m["key"]!)!
    }

    private func isFail(_ a: [HostPairing.Action]) -> Bool { a.contains { if case .fail = $0 { true } else { false } } }

    /// Runs commit + reveal and returns the phone's derived values.
    private func toConfirmations(_ host: HostPairing, _ phone: Phone) throws -> PairingMath.Derived {
        let key = try serverKey(host.receive(phone.commit))
        let d = try phone.derive(key)
        XCTAssertEqual(host.receive(phone.reveal), [.showCode(d.sas)], "both sides must show the same code")
        return d
    }

    func testHappyPathPhoneConfirmsFirst() throws {
        let (host, phone) = make()
        let d = try toConfirmations(host, phone)
        XCTAssertEqual(host.receive(phone.confirm(d)), [], "no persist before the Mac user approves")
        let actions = host.decide(true)
        guard case .send(let confirm) = actions.first else { return XCTFail() }
        XCTAssertTrue(PairingMath.verify(Data(base64Encoded: confirm["mac"]!)!, key: d.key, role: "server", pin: pinS))
        XCTAssertEqual(Array(actions.dropFirst()), [.persist])
        XCTAssertEqual(host.persisted(true), [.send(["type": "pair_done"]), .close])
        XCTAssertEqual(host.state, .done)
    }

    func testHappyPathMacApprovesFirst() throws {
        let (host, phone) = make()
        let d = try toConfirmations(host, phone)
        XCTAssertFalse(host.decide(true).contains(.persist), "no persist before the phone's MAC")
        XCTAssertEqual(host.receive(phone.confirm(d)), [.persist])
    }

    func testPersistFailureSendsNoPairDone() throws {
        let (host, phone) = make()
        let d = try toConfirmations(host, phone)
        _ = host.receive(phone.confirm(d))
        _ = host.decide(true)
        let after = host.persisted(false)
        XCTAssertTrue(isFail(after))
        XCTAssertFalse(after.contains(.send(["type": "pair_done"])))
    }

    func testOutOfOrderAndDuplicatesFail() throws {
        let (_, phone) = make()
        var host = make().0
        XCTAssertTrue(isFail(host.receive(phone.reveal)), "reveal before commit")
        host = make().0
        _ = host.receive(phone.commit)
        XCTAssertTrue(isFail(host.receive(phone.commit)), "duplicate commit")
        host = make().0
        XCTAssertTrue(isFail(host.receive(["type": "pair_confirm", "mac": Data(count: 32).base64EncodedString()])), "confirm before key")
        host = make().0
        XCTAssertTrue(isFail(host.receive(["type": "video_start"])), "non-pairing message")
        host = make().0
        XCTAssertTrue(isFail(host.receive(["type": "pair_commit", "commitment": Data(count: 31).base64EncodedString()])), "short commitment")
        XCTAssertEqual(host.receive(phone.commit), [], "nothing after failure")
        XCTAssertEqual(host.decide(true), [])
    }

    func testRevealMustMatchCommitmentAndBeAValidPoint() throws {
        let (host, phone) = make()
        _ = host.receive(phone.commit)
        let other = P256.KeyAgreement.PrivateKey().publicKey.x963Representation
        XCTAssertTrue(isFail(host.receive(["type": "pair_reveal", "key": other.base64EncodedString()])))

        let host2 = make().0
        let bogus = Data([4]) + Data(repeating: 7, count: 64) // committed to, but not on the curve
        _ = host2.receive(["type": "pair_commit", "commitment": PairingMath.commitment(bogus).base64EncodedString()])
        XCTAssertTrue(isFail(host2.receive(["type": "pair_reveal", "key": bogus.base64EncodedString()])))
    }

    func testWrongAndDuplicateClientMacFail() throws {
        let (host, phone) = make()
        let d = try toConfirmations(host, phone)
        XCTAssertTrue(isFail(host.receive(["type": "pair_confirm", "mac": PairingMath.mac(d.key, role: "server", pin: pinC).base64EncodedString()])),
                      "MAC for the wrong role")
        let (host2, phone2) = make()
        let d2 = try toConfirmations(host2, phone2)
        _ = host2.receive(phone2.confirm(d2))
        XCTAssertTrue(isFail(host2.receive(phone2.confirm(d2))), "duplicate confirm")
    }

    func testCancelOrRejectAtEveryStageStoresNothing() throws {
        let cancel: [String: Any] = ["type": "pair_cancel"]
        for stage in 0..<4 {
            let (host, phone) = make()
            var all: [HostPairing.Action] = []
            if stage >= 1 { all += host.receive(phone.commit) }
            if stage >= 2 { all += host.receive(phone.reveal) }
            if stage >= 3 { all += host.decide(true) }
            all += host.receive(cancel)
            XCTAssertFalse(all.contains(.persist), "stage \(stage)")
            XCTAssertEqual(host.state, .failed)
        }
        let (host, phone) = make()
        let d = try toConfirmations(host, phone)
        _ = host.receive(phone.confirm(d))
        let rejected = host.decide(false)
        XCTAssertEqual(rejected.first, .send(["type": "pair_cancel"]))
        XCTAssertFalse(rejected.contains(.persist))
    }

    /// An attacker relaying between two TLS sessions sees different channel bindings and pins on each side.
    func testMitmProducesDifferentCodesAndFailsConfirmation() throws {
        let host = HostPairing(pairingId: pid, pinC: pinC, pinS: pinS, cb: Data(repeating: 1, count: 32))
        let phone = Phone(pinC: pinC, pinS: Data(repeating: 0xAA, count: 32), cb: Data(repeating: 2, count: 32), pid: pid)
        let key = try serverKey(host.receive(phone.commit))
        let d = try phone.derive(key)
        guard case .showCode(let hostCode) = host.receive(phone.reveal).first else { return XCTFail() }
        XCTAssertNotEqual(hostCode, d.sas)
        XCTAssertTrue(isFail(host.receive(phone.confirm(d))))
    }
}
