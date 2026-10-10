import AVFoundation

/// Mac sound out of the speaker, 48 kHz s16le stereo on the wire.
/// Playback queues at most about 150 ms; anything beyond is dropped rather than added as delay.
final class AudioIO: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let playFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
    private let lock = NSLock()
    private var queued = 0
    private var running = false

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playFormat)
    }

    private func ensureRunning() -> Bool {
        if lock.withLock({ running }) { return true }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
            if !engine.isRunning { try engine.start() }
            player.play()
            lock.withLock { running = true }
            return true
        } catch {
            return false
        }
    }

    func play(_ pcm: Data) {
        let n = pcm.count / 4
        guard n > 0, ensureRunning(), lock.withLock({ queued < 7_200 }),
              let buf = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: AVAudioFrameCount(n)) else { return }
        buf.frameLength = AVAudioFrameCount(n)
        let l = buf.floatChannelData![0], r = buf.floatChannelData![1]
        pcm.withUnsafeBytes { raw in
            let s = raw.bindMemory(to: Int16.self)
            for i in 0..<n {
                l[i] = Float(Int16(littleEndian: s[2 * i])) / 32_768
                r[i] = Float(Int16(littleEndian: s[2 * i + 1])) / 32_768
            }
        }
        lock.withLock { queued += n }
        player.scheduleBuffer(buf) { [weak self] in self?.lock.withLock { self?.queued -= n } }
    }

    func stop() {
        player.stop()
        engine.stop()
        lock.withLock { running = false; queued = 0 }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
