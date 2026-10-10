import Foundation
import Security

/// Minimal DER for one self-signed X.509 v3 certificate. Encoding only; signing is done by Security.framework.
enum DER {
    static func tlv(_ tag: UInt8, _ content: Data) -> Data {
        var d = Data([tag])
        let n = content.count
        if n < 0x80 {
            d.append(UInt8(n))
        } else {
            let bytes = withUnsafeBytes(of: UInt32(n).bigEndian) { Data($0) }.drop { $0 == 0 }
            d.append(0x80 | UInt8(bytes.count))
            d.append(contentsOf: bytes)
        }
        return d + content
    }

    static func seq(_ parts: Data...) -> Data { tlv(0x30, parts.reduce(Data(), +)) }
    static let ecdsaWithSHA256 = seq(tlv(0x06, Data([0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02])))

    static func name(_ cn: String) -> Data {
        seq(tlv(0x31, seq(tlv(0x06, Data([0x55, 0x04, 0x03])), tlv(0x0c, Data(cn.utf8)))))
    }

    static func utcTime(_ date: Date) -> Data {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyMMddHHmmss'Z'"
        return tlv(0x17, Data(f.string(from: date).utf8))
    }

    static func tbsCertificate(spki: Data, commonName: String) -> Data {
        var serial = Data(count: 16)
        _ = serial.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        serial[0] &= 0x7f // positive INTEGER
        let notAfter = Date(timeIntervalSince1970: 2_524_607_999) // 2049-12-31, the last UTCTime year
        return seq(
            tlv(0xa0, tlv(0x02, Data([2]))), // version v3
            tlv(0x02, serial),
            ecdsaWithSHA256,
            name(commonName),
            seq(utcTime(Date().addingTimeInterval(-86_400)), utcTime(notAfter)),
            name(commonName),
            spki
        )
    }

    static func certificate(tbs: Data, signature: Data) -> Data {
        seq(tbs, ecdsaWithSHA256, tlv(0x03, Data([0]) + signature))
    }
}
