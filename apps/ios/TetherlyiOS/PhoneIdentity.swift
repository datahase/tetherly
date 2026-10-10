import Foundation
import Network
import Security

/// This device's long-term TLS identity: a non-extractable P-256 key in the keychain plus a self-signed certificate
/// signed by that key (encoding in DER.swift). The Mac pins SHA-256 of its SPKI.
struct PhoneIdentity {
    let identity: sec_identity_t
    let pin: Data

    private static let tag = Data("link.tetherly.client.identity".utf8)
    private static let label = "Tetherly device identity"

    static func loadOrCreate() throws -> PhoneIdentity {
        let key = try existingKey() ?? createKey()
        guard let pub = SecKeyCopyPublicKey(key), let x963 = SecKeyCopyExternalRepresentation(pub, nil) as Data? else {
            throw IdentityFailure("public key unavailable")
        }
        if try !hasCertificate() { try addCertificate(key: key, x963: x963) }
        var out: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassIdentity, kSecAttrLabel: label, kSecReturnRef: true] as CFDictionary, &out)
        guard status == errSecSuccess, let out, let identity = sec_identity_create(out as! SecIdentity) else {
            throw IdentityFailure("identity unavailable (\(status))")
        }
        return PhoneIdentity(identity: identity, pin: SPKI.pin(x963: x963))
    }

    private static func existingKey() throws -> SecKey? {
        var out: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassKey, kSecAttrApplicationTag: tag, kSecReturnRef: true] as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw IdentityFailure("keychain read failed (\(status))") }
        return (out as! SecKey)
    }

    private static func createKey() throws -> SecKey {
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey([
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: true, kSecAttrApplicationTag: tag, kSecAttrLabel: label, kSecAttrIsExtractable: false,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ],
        ] as CFDictionary, &error) else { throw IdentityFailure("key creation failed: \(error!.takeRetainedValue())") }
        return key
    }

    private static func hasCertificate() throws -> Bool {
        let status = SecItemCopyMatching([kSecClass: kSecClassCertificate, kSecAttrLabel: label] as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw IdentityFailure("keychain read failed (\(status))") }
        return true
    }

    private static func addCertificate(key: SecKey, x963: Data) throws {
        let tbs = DER.tbsCertificate(spki: SPKI.der(x963: x963), commonName: "Tetherly device")
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, tbs as CFData, &error) as Data?,
              let cert = SecCertificateCreateWithData(nil, DER.certificate(tbs: tbs, signature: signature) as CFData)
        else { throw IdentityFailure("certificate creation failed") }
        let status = SecItemAdd([kSecClass: kSecClassCertificate, kSecValueRef: cert, kSecAttrLabel: label,
                                 kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw IdentityFailure("keychain write failed (\(status))") }
    }
}

struct IdentityFailure: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

/// Paired Macs, as JSON in UserDefaults. Public keys and addresses only; nothing secret.
enum MacStore {
    private static let key = "pairedMacs"
    static func load() -> [PairedMac] {
        (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode([PairedMac].self, from: $0) } ?? []
    }
    static func save(_ macs: [PairedMac]) { UserDefaults.standard.set(try? JSONEncoder().encode(macs), forKey: key) }
}
