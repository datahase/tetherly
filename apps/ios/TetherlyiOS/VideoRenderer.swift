import AVFoundation
import CoreMedia

/// Feeds H.264 access units (Annex-B, SPEC §6) into an AVSampleBufferDisplayLayer for immediate display.
/// Called on the session queue; the display layer accepts samples from any thread.
final class VideoRenderer: @unchecked Sendable {
    let layer = AVSampleBufferDisplayLayer()
    private let lock = NSLock()
    private var format: CMVideoFormatDescription?
    private var waitingForKey = true

    init() { layer.videoGravity = .resize }

    func configure(_ c: VideoConfig) {
        var f: CMVideoFormatDescription?
        let status = c.sps.withUnsafeBytes { sps in
            c.pps.withUnsafeBytes { pps in
                let ptrs = [sps.bindMemory(to: UInt8.self).baseAddress!, pps.bindMemory(to: UInt8.self).baseAddress!]
                let sizes = [c.sps.count, c.pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: nil, parameterSetCount: 2, parameterSetPointers: ptrs,
                                                                           parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &f)
            }
        }
        lock.withLock {
            format = status == noErr ? f : nil
            waitingForKey = true
        }
        layer.sampleBufferRenderer.flush()
    }

    /// Returns false when the stream needs a keyframe (decoder error, or a frame before the first keyframe).
    func decode(ptsMicros: UInt64, keyframe: Bool, annexB: Data) -> Bool {
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush(); lock.withLock { waitingForKey = true } }
        guard let format = lock.withLock({ format }) else { return false }
        if lock.withLock({ waitingForKey }) {
            guard keyframe else { return false }
            lock.withLock { waitingForKey = false }
        }
        let avcc = AnnexB.toAVCC(annexB)
        guard !avcc.isEmpty, let sample = Self.sample(avcc, format: format, ptsMicros: ptsMicros) else { return false }
        renderer.enqueue(sample)
        return true
    }

    func reset() {
        lock.withLock { format = nil; waitingForKey = true }
        layer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
    }

    private static func sample(_ avcc: Data, format: CMVideoFormatDescription, ptsMicros: UInt64) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: avcc.count, blockAllocator: nil,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: avcc.count, flags: 0,
                                                 blockBufferOut: &block) == noErr, let block else { return nil }
        let copied = avcc.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: avcc.count) }
        guard copied == noErr else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(value: CMTimeValue(ptsMicros), timescale: 1_000_000), decodeTimeStamp: .invalid)
        var size = avcc.count
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1,
                                        sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        // Show each frame as soon as it arrives instead of scheduling by timestamp: lowest latency for a live desktop.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary] {
            attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        return sample
    }
}
