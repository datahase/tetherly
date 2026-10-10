import CoreMedia
import ScreenCaptureKit

/// Captures the Mac's system audio (not this app's own) with ScreenCaptureKit and hands out 48 kHz s16le stereo PCM.
/// Runs its own audio-only stream so sound works whether or not video is streaming.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var onPCM: ((_ ptsMicros: UInt64, _ pcm: Data) -> Void)?
    private let queue = DispatchQueue(label: "link.tetherly.audio-capture", qos: .userInteractive)
    private let lock = NSLock()
    private var stream: SCStream?
    private var generation = 0

    func start(displayID: CGDirectDisplayID) {
        stop()
        let gen = lock.withLock { generation += 1; return generation }
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else { return }
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.sampleRate = 48_000
                config.channelCount = 2
                config.excludesCurrentProcessAudio = true
                // Video is unused here; keep it as cheap as possible.
                config.width = 2
                config.height = 2
                config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                let s = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: self)
                try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.queue)
                guard self.lock.withLock({
                    guard self.generation == gen else { return false }
                    self.stream = s
                    return true
                }) else { return }
                try await s.startCapture()
                if !self.lock.withLock({ self.generation == gen }) { try? await s.stopCapture() }
            } catch {}
        }
    }

    func stop() {
        let s = lock.withLock { () -> SCStream? in
            defer { stream = nil; generation += 1 }
            return stream
        }
        s?.stopCapture { _ in }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, lock.withLock({ stream === self.stream }), let pcm = Self.interleavedS16(sb) else { return }
        onPCM?(UInt64(max(0, sb.presentationTimeStamp.seconds) * 1_000_000), pcm)
    }

    /// ScreenCaptureKit delivers Float32, usually one buffer per channel; the wire format is interleaved s16le stereo.
    static func interleavedS16(_ sb: CMSampleBuffer) -> Data? {
        var out: Data?
        try? sb.withAudioBufferList { abl, _ in
            let buffers = Array(abl)
            guard let first = buffers.first, let p0 = first.mData else { return }
            if buffers.count >= 2, let p1 = buffers[1].mData {
                let n = Int(first.mDataByteSize) / 4
                let l = p0.assumingMemoryBound(to: Float.self), r = p1.assumingMemoryBound(to: Float.self)
                var d = Data(count: n * 4)
                d.withUnsafeMutableBytes { raw in
                    let o = raw.bindMemory(to: Int16.self)
                    for i in 0..<n { o[2 * i] = s16(l[i]).littleEndian; o[2 * i + 1] = s16(r[i]).littleEndian }
                }
                out = d
            } else {
                let channels = Int(first.mNumberChannels)
                let n = Int(first.mDataByteSize) / 4 / max(channels, 1)
                let f = p0.assumingMemoryBound(to: Float.self)
                var d = Data(count: n * 4)
                d.withUnsafeMutableBytes { raw in
                    let o = raw.bindMemory(to: Int16.self)
                    for i in 0..<n {
                        let a = f[i * channels], b = channels > 1 ? f[i * channels + 1] : a
                        o[2 * i] = s16(a).littleEndian; o[2 * i + 1] = s16(b).littleEndian
                    }
                }
                out = d
            }
        }
        return out
    }

    private static func s16(_ v: Float) -> Int16 { Int16(max(-1, min(1, v)) * 32_767) }
}
