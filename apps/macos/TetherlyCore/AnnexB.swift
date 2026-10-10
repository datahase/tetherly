import Foundation

/// H.264 byte-stream helpers shared by the clients (SPEC §6 frames are Annex-B).
enum AnnexB {
    /// Annex-B start codes (00 00 01 or 00 00 00 01) → 4-byte big-endian NAL lengths.
    static func toAVCC(_ d: Data) -> Data {
        let b = [UInt8](d)
        var starts: [(at: Int, len: Int)] = []
        var i = 0
        while i + 3 <= b.count {
            if b[i] == 0, b[i + 1] == 0 {
                if b[i + 2] == 1 { starts.append((i, 3)); i += 3; continue }
                if i + 4 <= b.count, b[i + 2] == 0, b[i + 3] == 1 { starts.append((i, 4)); i += 4; continue }
            }
            i += 1
        }
        var out = Data(capacity: b.count + 8)
        for (n, s) in starts.enumerated() {
            let begin = s.at + s.len, end = n + 1 < starts.count ? starts[n + 1].at : b.count
            guard end > begin else { continue }
            let len = UInt32(end - begin).bigEndian
            withUnsafeBytes(of: len) { out.append(contentsOf: $0) }
            out.append(contentsOf: b[begin..<end])
        }
        return out
    }
}
