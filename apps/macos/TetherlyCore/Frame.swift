import Foundation

/// Wire framing per protocol/SPEC.md §2. Pure logic, shared by the app and the test bundle.
enum ConnKind: String { case control, video, file, audio }
enum Role { case server, client }

struct ProtocolError: Error, Equatable {
    let code: String
    var message = ""
    static func == (a: Self, b: Self) -> Bool { a.code == b.code }
    static let malformed = ProtocolError(code: "malformed")
    static let tooLarge = ProtocolError(code: "frame_too_large")
    static let unknownType = ProtocolError(code: "unknown_type")
}

struct VideoConfig: Equatable {
    var width: Int, height: Int, sps: Data, pps: Data
}

enum Frame {
    case json([String: Any])
    case videoConfig(VideoConfig)
    case videoFrame(ptsMicros: UInt64, keyframe: Bool, data: Data)
    case fileChunk(Data)
    /// Mac sound: 48 kHz s16le stereo PCM.
    case audio(ptsMicros: UInt64, pcm: Data)

    static let jsonType: UInt8 = 0x01, videoConfigType: UInt8 = 0x10, videoFrameType: UInt8 = 0x11, fileChunkType: UInt8 = 0x20
    static let macAudioType: UInt8 = 0x30
    static let headerSize = 5

    private static func maxLength(type: UInt8) -> Int? {
        switch type {
        case jsonType: 65_536
        case videoConfigType: 4_096
        case videoFrameType: 4_194_304
        case fileChunkType: 262_145
        case macAudioType: 16_393
        default: nil
        }
    }

    private static func maxLength(kind: ConnKind) -> Int {
        switch kind {
        case .control: 65_536
        case .video: 4_194_304
        case .file: 262_145
        case .audio: 65_536
        }
    }

    private static func allowed(_ type: UInt8, kind: ConnKind, receiver: Role) -> Bool {
        switch type {
        case jsonType: true
        case videoConfigType, videoFrameType: kind == .video && receiver == .client
        case fileChunkType: kind == .file
        case macAudioType: kind == .audio && receiver == .client
        default: false
        }
    }

    /// Validates the 5-byte header before any payload buffer exists. Returns (type, payload length).
    static func header(_ bytes: Data, kind: ConnKind, receiver: Role) throws -> (type: UInt8, payloadLength: Int) {
        let b = [UInt8](bytes.prefix(headerSize))
        guard b.count == headerSize else { throw ProtocolError.malformed }
        let length = Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
        guard length > 0 else { throw ProtocolError.malformed }
        guard length <= maxLength(kind: kind) else { throw ProtocolError.tooLarge }
        guard allowed(b[4], kind: kind, receiver: receiver), let typeMax = maxLength(type: b[4]) else { throw ProtocolError.unknownType }
        guard length <= typeMax else { throw ProtocolError.tooLarge }
        return (b[4], length - 1)
    }

    static func payload(type: UInt8, _ p: Data) throws -> Frame {
        let p = Data(p) // rebase indices to 0
        switch type {
        case jsonType:
            guard String(data: p, encoding: .utf8) != nil,
                  let obj = try? JSONSerialization.jsonObject(with: p) as? [String: Any],
                  obj["type"] is String, !(obj["type"] is NSNumber)
            else { throw ProtocolError.malformed }
            return .json(obj)
        case videoConfigType:
            var r = Reader(p)
            let w = try r.u16(), h = try r.u16()
            let sps = try r.bytes(Int(try r.u16())), pps = try r.bytes(Int(try r.u16()))
            guard r.atEnd, (16...8192).contains(w), (16...8192).contains(h), !sps.isEmpty, !pps.isEmpty else { throw ProtocolError.malformed }
            return .videoConfig(VideoConfig(width: Int(w), height: Int(h), sps: sps, pps: pps))
        case videoFrameType:
            var r = Reader(p)
            let pts = try r.u64(), flags = try r.u8()
            guard flags & ~1 == 0, !r.atEnd else { throw ProtocolError.malformed }
            return .videoFrame(ptsMicros: pts, keyframe: flags & 1 == 1, data: r.rest())
        case fileChunkType:
            guard !p.isEmpty else { throw ProtocolError.malformed }
            return .fileChunk(p)
        case macAudioType:
            var r = Reader(p)
            let pts = try r.u64()
            let pcm = r.rest()
            guard !pcm.isEmpty, pcm.count % 4 == 0 else { throw ProtocolError.malformed }
            return .audio(ptsMicros: pts, pcm: pcm)
        default:
            throw ProtocolError.unknownType
        }
    }

    /// Whole-buffer decode (tests and small reads). The streaming reader uses `header` then `payload`.
    static func decode(_ data: Data, kind: ConnKind, receiver: Role) throws -> Frame {
        let (type, length) = try header(data, kind: kind, receiver: receiver)
        guard data.count == headerSize + length else { throw ProtocolError.malformed }
        return try payload(type: type, data.dropFirst(headerSize))
    }

    static func encode(type: UInt8, _ payload: Data) -> Data {
        var d = Data(capacity: headerSize + payload.count)
        let length = UInt32(payload.count + 1)
        d.append(contentsOf: [UInt8(length >> 24), UInt8(length >> 16 & 0xff), UInt8(length >> 8 & 0xff), UInt8(length & 0xff), type])
        d.append(payload)
        return d
    }

    static func encode(json obj: [String: Any]) -> Data {
        encode(type: jsonType, (try? JSONSerialization.data(withJSONObject: obj)) ?? Data())
    }

    static func encode(_ config: VideoConfig) -> Data {
        var p = Data()
        for v in [config.width, config.height] { p.append(u16: v) }
        p.append(u16: config.sps.count); p.append(config.sps)
        p.append(u16: config.pps.count); p.append(config.pps)
        return encode(type: videoConfigType, p)
    }

    static func encodeAudio(ptsMicros: UInt64, pcm: Data) -> Data {
        var p = Data(capacity: 8 + pcm.count)
        for shift in stride(from: 56, through: 0, by: -8) { p.append(UInt8(ptsMicros >> UInt64(shift) & 0xff)) }
        p.append(pcm)
        return encode(type: macAudioType, p)
    }

    static func encodeVideoFrame(ptsMicros: UInt64, keyframe: Bool, data: Data) -> Data {
        var p = Data(capacity: 9 + data.count)
        for shift in stride(from: 56, through: 0, by: -8) { p.append(UInt8(ptsMicros >> UInt64(shift) & 0xff)) }
        p.append(keyframe ? 1 : 0)
        p.append(data)
        return encode(type: videoFrameType, p)
    }
}

private struct Reader {
    let d: Data
    var i = 0
    init(_ d: Data) { self.d = d }
    var atEnd: Bool { i == d.count }
    mutating func bytes(_ n: Int) throws -> Data {
        guard n >= 0, i + n <= d.count else { throw ProtocolError.malformed }
        defer { i += n }
        return d.subdata(in: i..<i + n)
    }
    mutating func u8() throws -> UInt8 { try bytes(1)[0] }
    mutating func u16() throws -> UInt16 { let b = try bytes(2); return UInt16(b[0]) << 8 | UInt16(b[1]) }
    mutating func u64() throws -> UInt64 { try bytes(8).reduce(0) { $0 << 8 | UInt64($1) } }
    func rest() -> Data { d.subdata(in: i..<d.count) }
}

extension Data {
    mutating func append(u16 v: Int) { append(contentsOf: [UInt8(v >> 8 & 0xff), UInt8(v & 0xff)]) }
    var hex: String { map { String(format: "%02x", $0) }.joined() }
    init?(hex: String) {
        var d = Data(capacity: hex.count / 2), it = hex.makeIterator()
        while let a = it.next() {
            guard let b = it.next(), let v = UInt8(String([a, b]), radix: 16) else { return nil }
            d.append(v)
        }
        self = d
    }
}
