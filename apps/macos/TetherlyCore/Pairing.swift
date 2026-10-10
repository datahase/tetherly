import CryptoKit
import Foundation
import Security

/// SAS pairing math per protocol/SPEC.md §4 (commitment-based, adapted from Matrix m.sas.v1). Not security-approved yet.
enum PairingMath {
    static func commitment(_ ephC: Data) -> Data { Data(SHA256.hash(data: ephC)) }

    struct Derived {
        let sas: [Int]
        let key: SymmetricKey
    }

    static func derive(z: Data, pairingId: Data, pinC: Data, pinS: Data, cb: Data, ephC: Data, ephS: Data) -> Derived {
        let suffix = pairingId + pinC + pinS + cb + ephC + ephS
        let ikm = SymmetricKey(data: z)
        let sasBytes = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: Data(), info: Data("TETHERLY-SAS-v1".utf8) + suffix, outputByteCount: 5)
            .withUnsafeBytes { [UInt8]($0) }
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: Data(), info: Data("TETHERLY-MAC-v1".utf8) + suffix, outputByteCount: 32)
        return Derived(sas: sasNumbers(sasBytes), key: key)
    }

    static func sasNumbers(_ b: [UInt8]) -> [Int] {
        let b = b.map(Int.init)
        return [(b[0] << 5 | b[1] >> 3) + 1000,
                ((b[1] & 7) << 10 | b[2] << 2 | b[3] >> 6) + 1000,
                ((b[3] & 63) << 7 | b[4] >> 1) + 1000]
    }

    static func mac(_ key: SymmetricKey, role: String, pin: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(role.utf8) + pin, using: key))
    }

    static func verify(_ mac: Data, key: SymmetricKey, role: String, pin: Data) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: Data(role.utf8) + pin, using: key)
    }

    /// Accepts only a 65-byte uncompressed point; CryptoKit rejects off-curve points and coordinates ≥ p.
    static func publicKey(x963: Data) throws -> P256.KeyAgreement.PublicKey {
        guard x963.count == 65, x963.first == 4 else { throw ProtocolError(code: "pairing_failed", message: "bad key") }
        do { return try P256.KeyAgreement.PublicKey(x963Representation: x963) } catch {
            throw ProtocolError(code: "pairing_failed", message: "bad key")
        }
    }

    /// Raw ECDH x-coordinate (`z`) between our ephemeral private key and the peer's X9.63 public key.
    static func agree(_ priv: P256.KeyAgreement.PrivateKey, peerX963: Data) throws -> Data {
        try priv.sharedSecretFromKeyAgreement(with: publicKey(x963: peerX963)).withUnsafeBytes { Data($0) }
    }

    static func formatted(_ sas: [Int]) -> String { sas.map(String.init).joined(separator: " ") }
}

/// SubjectPublicKeyInfo DER for a P-256 key given its 65-byte X9.63 point, and the protocol's pin over it.
enum SPKI {
    static let p256Prefix = Data(hex: "3059301306072a8648ce3d020106082a8648ce3d030107034200")!
    static func der(x963: Data) -> Data { p256Prefix + x963 }
    static func pin(x963: Data) -> Data { Data(SHA256.hash(data: der(x963: x963))) }

    /// Pin of a peer certificate, or nil unless it carries an EC P-256 key.
    static func pin(of cert: SecCertificate) -> Data? {
        guard let key = SecCertificateCopyKey(cert),
              let attrs = SecKeyCopyAttributes(key) as? [CFString: Any],
              (attrs[kSecAttrKeyType] as? String) == (kSecAttrKeyTypeECSECPrimeRandom as String),
              (attrs[kSecAttrKeySizeInBits] as? Int) == 256,
              let x963 = SecKeyCopyExternalRepresentation(key, nil) as Data?, x963.count == 65
        else { return nil }
        return pin(x963: x963)
    }
}

/// Mac side of the pairing state machine (SPEC §4.1). Pure: the host performs the returned actions.
final class HostPairing {
    enum State: Equatable { case awaitCommit, awaitReveal, awaitConfirmations, persisting, done, failed }
    enum Action: Equatable {
        case send([String: String])
        case showCode([Int])
        case persist
        case close
        case fail(String)
    }

    let pairingId: Data, pinC: Data, pinS: Data, cb: Data
    private let eph: P256.KeyAgreement.PrivateKey
    private(set) var state = State.awaitCommit
    private(set) var code: [Int]?
    private var commitment: Data?
    private var key: SymmetricKey?
    private var clientConfirmed = false
    private var approved = false

    init(pairingId: Data, pinC: Data, pinS: Data, cb: Data, eph: P256.KeyAgreement.PrivateKey = .init()) {
        self.pairingId = pairingId
        self.pinC = pinC
        self.pinS = pinS
        self.cb = cb
        self.eph = eph
    }

    func receive(_ m: [String: Any]) -> [Action] {
        guard state != .failed, state != .done else { return [] }
        func b64(_ k: String) -> Data? { (m[k] as? String).flatMap { Data(base64Encoded: $0) } }
        switch (m["type"] as? String, state) {
        case ("pair_commit", .awaitCommit):
            guard let c = b64("commitment"), c.count == 32 else { return fail("bad commitment") }
            commitment = c
            state = .awaitReveal
            return [.send(["type": "pair_key", "key": eph.publicKey.x963Representation.base64EncodedString()])]
        case ("pair_reveal", .awaitReveal):
            guard let ephC = b64("key"), PairingMath.commitment(ephC) == commitment,
                  let z = try? PairingMath.agree(eph, peerX963: ephC) else { return fail("key does not match commitment") }
            let d = PairingMath.derive(z: z, pairingId: pairingId, pinC: pinC, pinS: pinS, cb: cb,
                                       ephC: ephC, ephS: eph.publicKey.x963Representation)
            key = d.key
            code = d.sas
            state = .awaitConfirmations
            return [.showCode(d.sas)]
        case ("pair_confirm", .awaitConfirmations) where !clientConfirmed:
            guard let key, let mac = b64("mac"), PairingMath.verify(mac, key: key, role: "client", pin: pinC) else {
                return fail("confirmation did not verify")
            }
            clientConfirmed = true
            return persistIfReady()
        case ("pair_cancel", _):
            return fail("cancelled on the phone")
        default:
            return fail("unexpected message")
        }
    }

    /// The Mac user's Allow / Reject after comparing codes.
    func decide(_ allow: Bool) -> [Action] {
        guard state == .awaitConfirmations, !approved, let key else { return [] }
        guard allow else { return [.send(["type": "pair_cancel"])] + fail("rejected on this Mac") }
        approved = true
        return [.send(["type": "pair_confirm", "mac": PairingMath.mac(key, role: "server", pin: pinS).base64EncodedString()])] + persistIfReady()
    }

    /// Result of the durable write requested by `.persist`. `pair_done` is only sent after success (SPEC §4.2).
    func persisted(_ ok: Bool) -> [Action] {
        guard state == .persisting else { return [] }
        guard ok else { return fail("couldn't save the pairing on this Mac") }
        state = .done
        return [.send(["type": "pair_done"]), .close]
    }

    private func persistIfReady() -> [Action] {
        guard approved, clientConfirmed else { return [] }
        state = .persisting
        return [.persist]
    }

    private func fail(_ why: String) -> [Action] {
        state = .failed
        return [.fail(why)]
    }
}


/// Phone side of the pairing state machine (SPEC §4.1), the mirror of `HostPairing`. Pure: the caller sends the
/// returned messages and stores the Mac's pin only when `state` reaches `.done`.
final class ClientPairing {
    enum State: Equatable { case awaitKey, awaitConfirmations, awaitDone, done, failed }
    struct Failure: Error, Equatable {
        let message: String
        let reply: [String: String]?
    }

    let pairingId: Data, pinC: Data, pinS: Data, cb: Data
    private let eph: P256.KeyAgreement.PrivateKey
    private(set) var state = State.awaitKey
    private(set) var code: [Int]?
    private(set) var userConfirmed = false
    private(set) var serverConfirmed = false
    private var key: SymmetricKey?

    init(pairingId: Data, pinC: Data, pinS: Data, cb: Data, eph: P256.KeyAgreement.PrivateKey = .init()) {
        self.pairingId = pairingId
        self.pinC = pinC
        self.pinS = pinS
        self.cb = cb
        self.eph = eph
    }

    private var ephC: Data { eph.publicKey.x963Representation }

    /// First message, right after a `welcome` in pairing state.
    func commit() -> [String: String] {
        ["type": "pair_commit", "commitment": PairingMath.commitment(ephC).base64EncodedString()]
    }

    /// Handles one Mac message; returns the reply to send, if any. Throws `Failure` (nothing stored) on anything off-script.
    func receive(_ m: [String: Any]) throws -> [String: String]? {
        guard state != .done, state != .failed else { throw fail("Pairing ended.", nil) }
        func b64(_ k: String) -> Data? { (m[k] as? String).flatMap { Data(base64Encoded: $0) } }
        switch (m["type"] as? String, state) {
        case ("pair_key", .awaitKey):
            guard let ephS = b64("key"), let z = try? PairingMath.agree(eph, peerX963: ephS) else {
                throw fail("Pairing failed: the Mac sent an invalid key. Nothing was saved.", ["type": "pair_cancel"])
            }
            let d = PairingMath.derive(z: z, pairingId: pairingId, pinC: pinC, pinS: pinS, cb: cb, ephC: ephC, ephS: ephS)
            key = d.key
            code = d.sas
            state = .awaitConfirmations
            return ["type": "pair_reveal", "key": ephC.base64EncodedString()]
        case ("pair_confirm", .awaitConfirmations) where !serverConfirmed:
            guard let key, let mac = b64("mac"), PairingMath.verify(mac, key: key, role: "server", pin: pinS) else {
                throw fail("Pairing failed: the Mac's confirmation didn't match. Nothing was saved.",
                           ["type": "error", "code": "pairing_failed", "message": "bad MAC"])
            }
            serverConfirmed = true
            advance()
            return nil
        case ("pair_done", .awaitDone):
            state = .done
            return nil
        case ("pair_cancel", _):
            throw fail("Pairing was cancelled on the Mac.", nil)
        default:
            throw fail("Pairing failed: unexpected \(m["type"] as? String ?? "message") from the Mac. Nothing was saved.", ["type": "pair_cancel"])
        }
    }

    /// The phone user confirmed that the codes match; returns the client `pair_confirm`.
    func confirm() -> [String: String]? {
        guard state == .awaitConfirmations, !userConfirmed, let key else { return nil }
        userConfirmed = true
        advance()
        return ["type": "pair_confirm", "mac": PairingMath.mac(key, role: "client", pin: pinC).base64EncodedString()]
    }

    func cancel() -> [String: String] {
        state = .failed
        return ["type": "pair_cancel"]
    }

    private func advance() { if userConfirmed && serverConfirmed { state = .awaitDone } }

    private func fail(_ message: String, _ reply: [String: String]?) -> Failure {
        state = .failed
        return Failure(message: message, reply: reply)
    }
}
