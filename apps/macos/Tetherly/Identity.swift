import Foundation
import Network
import Security

/// The Mac's long-term TLS identity: a non-extractable P-256 key in the login keychain plus a self-signed
/// certificate signed by that key. See docs/SECURITY.md ("Mac host key") for why this is not Secure Enclave yet.
struct HostIdentity {
    let identity: sec_identity_t
    let pin: Data

    private static let tag = Data("link.tetherly.host.identity".utf8)
    private static let label = "Tetherly host identity"

    static func loadOrCreate() throws -> HostIdentity {
        let key = try existingKey() ?? createKey()
        guard let publicKey = SecKeyCopyPublicKey(key),
              let x963 = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else { throw IdentityError("public key unavailable") }
        let cert = try existingCertificate(matching: x963) ?? createCertificate(key: key, x963: x963)
        var identity: SecIdentity?
        let status = SecIdentityCreateWithCertificate(nil, cert, &identity)
        guard status == errSecSuccess, let identity, let secIdentity = sec_identity_create(identity) else {
            throw IdentityError("identity unavailable (\(status))")
        }
        return HostIdentity(identity: secIdentity, pin: SPKI.pin(x963: x963))
    }

    private static func existingKey() throws -> SecKey? {
        var out: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassKey, kSecAttrApplicationTag: tag, kSecAttrKeyClass: kSecAttrKeyClassPrivate, kSecReturnRef: true,
        ] as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw IdentityError("keychain read failed (\(status))") }
        return (out as! SecKey)
    }

    private static func createKey() throws -> SecKey {
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey([
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecAttrLabel: label,
            kSecPrivateKeyAttrs: [kSecAttrIsPermanent: true, kSecAttrApplicationTag: tag, kSecAttrIsExtractable: false],
        ] as CFDictionary, &error) else { throw IdentityError("key creation failed: \(error!.takeRetainedValue())") }
        return key
    }

    private static func existingCertificate(matching x963: Data) throws -> SecCertificate? {
        var out: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassCertificate, kSecAttrLabel: label, kSecReturnRef: true, kSecMatchLimit: kSecMatchLimitAll,
        ] as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw IdentityError("keychain read failed (\(status))") }
        return (out as? [SecCertificate] ?? []).first { cert in
            SecCertificateCopyKey(cert).flatMap { SecKeyCopyExternalRepresentation($0, nil) as Data? } == x963
        }
    }

    private static func createCertificate(key: SecKey, x963: Data) throws -> SecCertificate {
        let tbs = DER.tbsCertificate(spki: SPKI.der(x963: x963), commonName: "Tetherly host")
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, tbs as CFData, &error) as Data? else {
            throw IdentityError("signing failed: \(error!.takeRetainedValue())")
        }
        let der = DER.certificate(tbs: tbs, signature: signature)
        guard let cert = SecCertificateCreateWithData(nil, der as CFData) else { throw IdentityError("certificate encoding rejected") }
        let status = SecItemAdd([kSecClass: kSecClassCertificate, kSecValueRef: cert, kSecAttrLabel: label] as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw IdentityError("keychain write failed (\(status))") }
        return cert
    }
}

struct IdentityError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}
