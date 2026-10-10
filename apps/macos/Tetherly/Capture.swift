import CoreMedia
import Foundation
import ScreenCaptureKit
import VideoToolbox

/// ScreenCaptureKit capture of one display → VideoToolbox H.264 (no B-frames) → Annex-B access units.
/// Output callbacks arrive on `outputQueue`; the owner forwards them to the video connection.
final class ScreenEncoder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    struct Settings: Equatable { var maxDimension: Int, fps: Int, showsCursor: Bool = true }

    var onConfig: ((VideoConfig) -> Void)?
    var onFrame: ((_ ptsMicros: UInt64, _ keyframe: Bool, _ annexB: Data) -> Void)?
    var onError: ((String) -> Void)?

    private let outputQueue: DispatchQueue
    private let captureQueue = DispatchQueue(label: "link.tetherly.capture", qos: .userInteractive)
    private let lock = NSLock()
    private var stream: SCStream?
    private var session: VTCompressionSession?
    private var forceKey = true
    private var lastConfig: VideoConfig?
    private var generation = 0
    private(set) var running = false

    init(outputQueue: DispatchQueue) { self.outputQueue = outputQueue }

    /// Every start gets a new generation. Only the current generation may install resources or deliver output, so a
    /// slow start that finishes after stop()/restart is torn down instead of replacing the live encoder.
    func start(displayID: CGDirectDisplayID, settings: Settings) {
        stop()
        let gen = lock.withLock { () -> Int in generation += 1; running = true; return generation }
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                    throw IdentityError("no display")
                }
                // Pixel size of the display, scaled down so the long side is at most maxDimension; even numbers for H.264.
                let mode = CGDisplayCopyDisplayMode(display.displayID)
                let pw = Double(mode?.pixelWidth ?? display.width), ph = Double(mode?.pixelHeight ?? display.height)
                let k = min(1, Double(settings.maxDimension) / max(pw, ph))
                let w = Int(pw * k) & ~1, h = Int(ph * k) & ~1

                let config = SCStreamConfiguration()
                config.width = w
                config.height = h
                config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.fps))
                config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                config.queueDepth = 3
                config.showsCursor = settings.showsCursor
                let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.captureQueue)
                let encoder = try Self.makeEncoder(width: w, height: h, settings: settings)
                guard self.install(gen, stream, encoder) else { return VTCompressionSessionInvalidate(encoder) }
                try await stream.startCapture()
                if !self.isCurrent(gen) { try? await stream.stopCapture() } // stopped while we were starting
            } catch {
                guard self.isCurrent(gen) else { return }
                let message = "capture failed: \(error.localizedDescription)"
                self.outputQueue.async { if self.isCurrent(gen) { self.onError?(message) } }
            }
        }
    }

    private func isCurrent(_ gen: Int) -> Bool { lock.withLock { generation == gen && running } }

    private func install(_ gen: Int, _ stream: SCStream, _ encoder: VTCompressionSession) -> Bool {
        lock.withLock {
            guard generation == gen, running else { return false }
            self.stream = stream
            session = encoder
            forceKey = true
            lastConfig = nil
            return true
        }
    }

    func stop() {
        let (s, e) = lock.withLock { () -> (SCStream?, VTCompressionSession?) in
            defer { stream = nil; session = nil; running = false; lastConfig = nil; generation += 1 }
            return (stream, session)
        }
        s?.stopCapture { _ in }
        if let e { VTCompressionSessionInvalidate(e) }
    }

    func requestKeyframe() { lock.withLock { forceKey = true } }

    private static func makeEncoder(width: Int, height: Int, settings: Settings) throws -> VTCompressionSession {
        var s: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil, width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_H264,
            encoderSpecification: [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true] as CFDictionary,
            imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: nil, refcon: nil, compressionSessionOut: &s)
        guard status == noErr, let s else { throw IdentityError("encoder unavailable (\(status))") }
        // Base rates are for 30 fps; higher rates get more bits, sublinearly since consecutive frames differ less.
        let base = settings.maxDimension >= 1920 ? 8_000_000.0 : settings.maxDimension >= 1280 ? 5_000_000.0 : 3_000_000.0
        let bitrate = Int(base * (Double(settings.fps) / 30).squareRoot())
        let props: [CFString: Any] = [
            kVTCompressionPropertyKey_RealTime: true,
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_Main_AutoLevel,
            kVTCompressionPropertyKey_AllowFrameReordering: false,
            kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration: 2,
            kVTCompressionPropertyKey_ExpectedFrameRate: settings.fps,
            kVTCompressionPropertyKey_AverageBitRate: bitrate,
        ]
        for (k, v) in props { VTSessionSetProperty(s, key: k, value: v as CFTypeRef) }
        VTCompressionSessionPrepareToEncodeFrames(s)
        return s
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pixels = sampleBuffer.imageBuffer,
              let info = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              (info[.status] as? Int).flatMap(SCFrameStatus.init(rawValue:)) == .complete
        else { return }
        // Frames from a stream that is no longer current are dropped.
        let (session, key, gen) = lock.withLock { () -> (VTCompressionSession?, Bool, Int) in
            guard stream === self.stream else { return (nil, false, 0) }
            defer { forceKey = false }
            return (self.session, forceKey, generation)
        }
        guard let session else { return }
        let pts = sampleBuffer.presentationTimeStamp
        let options = key ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        VTCompressionSessionEncodeFrame(session, imageBuffer: pixels, presentationTimeStamp: pts, duration: .invalid,
                                        frameProperties: options, infoFlagsOut: nil) { [weak self] status, _, sample in
            guard status == noErr, let sample, let self else { return }
            nonisolated(unsafe) let encoded = sample // immutable once emitted by VideoToolbox
            self.outputQueue.async { self.emit(encoded, gen) }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let gen = lock.withLock { stream === self.stream ? generation : -1 }
        let message = "capture stopped: \(error.localizedDescription)"
        outputQueue.async { if self.isCurrent(gen) { self.onError?(message) } }
    }

    private func emit(_ sample: CMSampleBuffer, _ gen: Int) {
        guard isCurrent(gen), let block = sample.dataBuffer, let format = sample.formatDescription else { return }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
        let keyframe = !((attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false)
        if keyframe, let config = Self.parameterSets(format), lock.withLock({ () -> Bool in
            defer { lastConfig = config }
            return config != lastConfig
        }) {
            onConfig?(config)
        }
        guard let avcc = try? block.dataBytes() else { return }
        // AVCC (4-byte big-endian lengths) → Annex-B start codes.
        var out = Data(capacity: avcc.count + 16), i = 0
        while i + 4 <= avcc.count {
            let n = Int(avcc[i]) << 24 | Int(avcc[i + 1]) << 16 | Int(avcc[i + 2]) << 8 | Int(avcc[i + 3])
            i += 4
            guard n > 0, i + n <= avcc.count else { break }
            out.append(contentsOf: [0, 0, 0, 1])
            out.append(avcc[i..<i + n])
            i += n
        }
        let micros = UInt64(max(0, sample.presentationTimeStamp.seconds) * 1_000_000)
        if !out.isEmpty { onFrame?(micros, keyframe, out) }
    }

    private static func parameterSets(_ format: CMFormatDescription) -> VideoConfig? {
        func set(_ i: Int) -> Data? {
            var ptr: UnsafePointer<UInt8>?, size = 0
            guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: i, parameterSetPointerOut: &ptr,
                                                                     parameterSetSizeOut: &size, parameterSetCountOut: nil,
                                                                     nalUnitHeaderLengthOut: nil) == noErr, let ptr else { return nil }
            return Data(bytes: ptr, count: size)
        }
        let dims = CMVideoFormatDescriptionGetDimensions(format)
        guard let sps = set(0), let pps = set(1) else { return nil }
        return VideoConfig(width: Int(dims.width), height: Int(dims.height), sps: sps, pps: pps)
    }
}
