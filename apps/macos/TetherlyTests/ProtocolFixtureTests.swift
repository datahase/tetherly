import CryptoKit
import XCTest

/// Runs the shared golden vectors in protocol/fixtures (generated independently by scripts/gen-fixtures.py).
final class ProtocolFixtureTests: XCTestCase {
    private func fixture(_ name: String) throws -> Any {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../protocol/fixtures/\(name)").standardized
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    func testFrames() throws {
        let cases = try XCTUnwrap(fixture("frames.json") as? [[String: String]])
        XCTAssertGreaterThan(cases.count, 20)
        for c in cases {
            let kind = try XCTUnwrap(ConnKind(rawValue: c["kind"]!)), name = c["name"]!
            // "c2s" frames are judged by the server, "s2c" by the client; "any" must hold for both.
            let roles: [Role] = c["dir"] == "c2s" ? [.server] : c["dir"] == "s2c" ? [.client] : [.server, .client]
            for role in roles {
                let verdict: String
                do {
                    let frame = try Frame.decode(Data(hex: c["hex"]!)!, kind: kind, receiver: role)
                    verdict = switch frame {
                    case .json: "ok:1"
                    case .videoConfig: "ok:16"
                    case .videoFrame: "ok:17"
                    case .fileChunk: "ok:32"
                    case .audio: "ok:48"
                    }
                } catch let e as ProtocolError {
                    verdict = e.code
                }
                XCTAssertEqual(verdict, c["expect"], name)
            }
        }
    }

    func testEncodeRoundTrip() throws {
        let cfg = VideoConfig(width: 1920, height: 1080, sps: Data([0x67, 1, 2]), pps: Data([0x68, 3]))
        guard case .videoConfig(let back) = try Frame.decode(Frame.encode(cfg), kind: .video, receiver: .client) else { return XCTFail() }
        XCTAssertEqual(back, cfg)
        guard case .videoFrame(let pts, let key, let data) = try Frame.decode(
            Frame.encodeVideoFrame(ptsMicros: 1 << 40 + 5, keyframe: true, data: Data([0, 0, 0, 1, 0x65])), kind: .video, receiver: .client)
        else { return XCTFail() }
        XCTAssertEqual(pts, 1 << 40 + 5); XCTAssertTrue(key); XCTAssertEqual(data, Data([0, 0, 0, 1, 0x65]))
    }

    func testPairingVectors() throws {
        let root = try XCTUnwrap(fixture("pairing.json") as? [String: Any])
        let rfc = try XCTUnwrap(root["rfc5869"] as? [String: Any])
        let okm = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(hex: rfc["ikm"] as! String)!),
                                         salt: Data(hex: rfc["salt"] as! String)!, info: Data(hex: rfc["info"] as! String)!,
                                         outputByteCount: rfc["length"] as! Int).withUnsafeBytes { Data($0) }
        XCTAssertEqual(okm.hex, rfc["okm"] as? String)

        for v in try XCTUnwrap(root["vectors"] as? [[String: Any]]) {
            func d(_ k: String) -> Data { Data(hex: v[k] as! String)! }
            XCTAssertEqual(PairingMath.commitment(d("ephC")), d("commitment"))
            let derived = PairingMath.derive(z: d("z"), pairingId: d("pairingId"), pinC: d("pinC"), pinS: d("pinS"), cb: d("cb"),
                                             ephC: d("ephC"), ephS: d("ephS"))
            XCTAssertEqual(derived.sas, v["sas"] as? [Int])
            XCTAssertEqual(derived.key.withUnsafeBytes { Data($0) }, d("k"))
            XCTAssertEqual(PairingMath.mac(derived.key, role: "client", pin: d("pinC")), d("clientMac"))
            XCTAssertEqual(PairingMath.mac(derived.key, role: "server", pin: d("pinS")), d("serverMac"))
            XCTAssertTrue(PairingMath.verify(d("serverMac"), key: derived.key, role: "server", pin: d("pinS")))
            // A MAC for the other role or another pin must not verify.
            XCTAssertFalse(PairingMath.verify(d("serverMac"), key: derived.key, role: "client", pin: d("pinS")))
            XCTAssertFalse(PairingMath.verify(d("clientMac"), key: derived.key, role: "client", pin: d("pinS")))
        }
    }

    /// Valid P-256 agreement computed by the generator's independent implementation (checked against NIST CAVS).
    func testEcdhVectors() throws {
        let root = try XCTUnwrap(fixture("pairing.json") as? [String: Any])
        let vectors = try XCTUnwrap(root["ecdh"] as? [[String: String]])
        XCTAssertEqual(vectors.count, 3)
        for v in vectors {
            let privC = try P256.KeyAgreement.PrivateKey(rawRepresentation: Data(hex: v["privC"]!)!)
            let privS = try P256.KeyAgreement.PrivateKey(rawRepresentation: Data(hex: v["privS"]!)!)
            XCTAssertEqual(privC.publicKey.x963Representation.hex, v["ephC"])
            XCTAssertEqual(try PairingMath.agree(privC, peerX963: Data(hex: v["ephS"]!)!).hex, v["z"])
            XCTAssertEqual(try PairingMath.agree(privS, peerX963: Data(hex: v["ephC"]!)!).hex, v["z"])
        }
    }

    func testInvalidPointsRejected() throws {
        let root = try XCTUnwrap(fixture("pairing.json") as? [String: Any])
        let points = try XCTUnwrap(root["invalidPoints"] as? [[String: String]])
        XCTAssertGreaterThanOrEqual(points.count, 8)
        let me = P256.KeyAgreement.PrivateKey()
        for p in points {
            XCTAssertThrowsError(try PairingMath.agree(me, peerX963: Data(hex: p["hex"]!)!), p["name"]!)
        }
        // The old KDF-vector "points" are arbitrary bytes and must not pass as keys either.
        for v in try XCTUnwrap(root["vectors"] as? [[String: Any]]) {
            XCTAssertThrowsError(try PairingMath.agree(me, peerX963: Data(hex: v["ephC"] as! String)!))
        }
    }

    func testEcdhAgreesBothWays() throws {
        let a = P256.KeyAgreement.PrivateKey(), b = P256.KeyAgreement.PrivateKey()
        XCTAssertEqual(try PairingMath.agree(a, peerX963: b.publicKey.x963Representation),
                       try PairingMath.agree(b, peerX963: a.publicKey.x963Representation))
        XCTAssertThrowsError(try PairingMath.agree(a, peerX963: Data(repeating: 4, count: 65)))
        XCTAssertThrowsError(try PairingMath.agree(a, peerX963: Data([4])))
    }

    func testFileNames() throws {
        for c in try XCTUnwrap(fixture("filenames.json") as? [[String: String]]) {
            XCTAssertEqual(FileNames.sanitize(c["raw"]!), c["sanitized"], c["raw"]!.debugDescription)
        }
        let taken: Set = ["a.txt", "a (2).txt", "noext"]
        XCTAssertEqual(FileNames.unique("a.txt", exists: taken.contains), "a (3).txt")
        XCTAssertEqual(FileNames.unique("noext", exists: taken.contains), "noext (2)")
        XCTAssertEqual(FileNames.unique("new.txt", exists: taken.contains), "new.txt")
    }
}
