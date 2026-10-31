import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO

/// Turns one video into a new file next to it (CORE.md §7), with no new dependencies: passthrough
/// remux, H.264/HEVC through VideoToolbox, GIF through our own encoder (`GIFWriter`).
enum VideoOptimizer {
    /// `progress` gets 0…1 as the work goes (from any thread).
    static func process(_ input: URL, action: Action, option: ActionOption?,
                        progress: @escaping @Sendable (Double) -> Void) async throws -> FileOutcome {
        let inputBytes = (try? input.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let plan = try VideoPlan.make(action: action, option: option, sourceExtension: input.pathExtension)
        if let target = plan.targetBytes, inputBytes <= target { throw JobError.alreadyUnder(target) }

        let asset = AVURLAsset(url: input)
        let source = try await VideoSource.load(asset)
        if let side = plan.maxShortSide, source.shortSide <= side { throw JobError.alreadyAtMost(side) }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("droptimize-\(UUID().uuidString)").appendingPathExtension(plan.fileExtension)
        defer { try? FileManager.default.removeItem(at: temp) }
        let fileType = Self.fileType(forExtension: plan.fileExtension)
        var note: String?

        switch plan.work {
        case .dropAudio:
            guard source.audioTrack != nil else { throw JobError.noAudio }
            try await passthrough(asset, source: source, includeAudio: false, to: temp, fileType: fileType)
        case .remuxOrEncode(let codec):
            if source.canRemuxToMP4 {
                try await passthrough(asset, source: source, includeAudio: true, to: temp, fileType: fileType)
            } else {
                note = try await encode(asset, source: source, plan: plan, codec: codec, to: temp, fileType: fileType,
                                        progress: progress)
            }
        case .encode(let codec):
            note = try await encode(asset, source: source, plan: plan, codec: codec, to: temp, fileType: fileType,
                                    progress: progress)
        case .gif:
            note = try await makeGIF(asset, source: source, to: temp, progress: progress)
        }

        let outputBytes = fileSize(temp) ?? 0
        if let target = plan.targetBytes, outputBytes > target { throw JobError.cantFit(target) }
        if plan.appliesSizeGuard, !SizeGuard.accepts(inputBytes: inputBytes, outputBytes: outputBytes) {
            throw JobError.alreadySmallest
        }
        let output = try OutputWriter.move(temp, for: input, fileExtension: plan.fileExtension, suffix: plan.suffix)
        return FileOutcome(input: input, output: output, inputBytes: inputBytes, outputBytes: outputBytes,
                           picture: nil, note: note)
    }

    static func fileType(forExtension ext: String) -> AVFileType {
        switch ext {
        case "mov": return .mov
        case "m4v": return .m4v
        default: return .mp4
        }
    }

    // MARK: Passthrough (remux, mute)

    /// Copies the streams into a new container without re-encoding: instant and lossless.
    static func passthrough(_ asset: AVAsset, source: VideoSource, includeAudio: Bool, to url: URL,
                            fileType: AVFileType) async throws {
        var exportAsset: AVAsset = asset
        if !includeAudio {
            let composition = AVMutableComposition()
            guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { throw JobError.unreadableVideo }
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: source.duration), of: source.videoTrack, at: .zero)
            track.preferredTransform = source.transform
            exportAsset = composition
        }
        try await export(exportAsset, preset: AVAssetExportPresetPassthrough, to: url, fileType: fileType)
    }

    static func export(_ asset: AVAsset, preset: String, to url: URL, fileType: AVFileType) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw JobError.unreadableVideo }
        session.shouldOptimizeForNetworkUse = true          // index at the front: plays while downloading
        if #available(macOS 15, *) {
            try await session.export(to: url, as: fileType)
        } else {
            session.outputURL = url
            session.outputFileType = fileType
            let box = Unchecked(session)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                box.value.exportAsynchronously { continuation.resume() }
            }
            guard session.status == .completed else { throw session.error ?? JobError.cantSave }
        }
    }

    // MARK: Encode

    /// Re-encodes to `codec`: the size from `plan.maxShortSide`, the bitrate from the frame size,
    /// the source's bitrate (so it shrinks) or the target file size. Returns a note for the card.
    private static func encode(_ asset: AVAsset, source: VideoSource, plan: VideoPlan, codec: VideoPlan.Codec,
                               to url: URL, fileType: AVFileType,
                               progress: @escaping @Sendable (Double) -> Void) async throws -> String? {
        var size = VideoTuning.size(width: source.width, height: source.height, maxShortSide: plan.maxShortSide)
        var note: String?
        var bitrate: Int
        if let target = plan.targetBytes {
            bitrate = VideoTuning.bitrate(fitting: target, seconds: source.seconds, hasAudio: source.audioTrack != nil)
            if let side = VideoTuning.shortSide(for: bitrate, width: size.width, height: size.height, fps: source.fps) {
                size = VideoTuning.size(width: source.width, height: source.height, maxShortSide: side)
                note = "Scaled to \(side)p to fit"
            }
        } else {
            bitrate = VideoTuning.bitrate(width: size.width, height: size.height, fps: source.fps, codec: codec)
            if plan.appliesSizeGuard, let sourceBitrate = source.videoBitrate {
                bitrate = min(bitrate, Int(Double(sourceBitrate) * VideoTuning.maxShareOfSource))
            }
        }
        // Retries fill part of what's left of the ring, so it keeps moving forward.
        var shown = 0.0
        func stage(_ share: Double) -> @Sendable (Double) -> Void {
            let start = shown, span = (1 - shown) * share
            shown = start + span
            return { progress(start + span * $0) }
        }
        try await transcode(asset, source: source, width: size.width, height: size.height, bitrate: bitrate,
                            codec: codec, to: url, fileType: fileType,
                            progress: stage(plan.targetBytes == nil ? 1 : VideoTuning.firstTryShare))

        // Encoders don't hit a bitrate exactly, and busy footage (grain, confetti, noise) can come out
        // far over it whatever it's asked for. Try a lower bitrate, then smaller frames, then give up
        // (process() says it couldn't fit).
        guard let target = plan.targetBytes else { return note }
        var attempt = 1
        while attempt < VideoTuning.fitAttempts, let written = fileSize(url), written > target {
            attempt += 1
            let share = Double(target) / Double(written) * VideoTuning.fitRetryMargin
            if attempt == 2 {
                bitrate = max(VideoTuning.minBitrate, Int(Double(bitrate) * share))
            } else if let side = VideoTuning.shortSide(below: min(size.width, size.height), pixelShare: share) {
                // The bitrate didn't hold, so take pixels away instead.
                size = VideoTuning.size(width: source.width, height: source.height, maxShortSide: side)
                note = "Scaled to \(side)p to fit"
            } else {
                break
            }
            try? FileManager.default.removeItem(at: url)
            try await transcode(asset, source: source, width: size.width, height: size.height, bitrate: bitrate,
                                codec: codec, to: url, fileType: fileType, progress: stage(VideoTuning.retryShare))
        }
        return note
    }

    /// Read from disk each time: a URL's resource values are cached, and these files are rewritten.
    private static func fileSize(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
    }

    private static func transcode(_ asset: AVAsset, source: VideoSource, width: Int, height: Int, bitrate: Int,
                                  codec: VideoPlan.Codec, to url: URL, fileType: AVFileType,
                                  progress: @escaping @Sendable (Double) -> Void) async throws {
        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(track: source.videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw JobError.unreadableVideo }
        reader.add(videoOutput)

        let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        writer.shouldOptimizeForNetworkUse = true
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: max(1, Int(source.fps.rounded())),
            AVVideoMaxKeyFrameIntervalKey: max(1, Int((source.fps * 2).rounded())),
        ]
        if codec == .h264 { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec == .h264 ? AVVideoCodecType.h264 : AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCompressionPropertiesKey: compression,
        ]
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else {
            throw JobError.notYet("This Mac can't encode \(codec == .h264 ? "H.264" : "HEVC") video.")
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = source.transform
        writer.add(videoInput)

        var audio: (output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)?
        if let audioTrack = source.audioTrack {
            let channels = min(max(source.audioChannels, 1), 2)
            let sampleRate = min(source.audioSampleRate > 0 ? source.audioSampleRate : 44_100, 48_000)
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVNumberOfChannelsKey: channels,
                AVSampleRateKey: sampleRate,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: channels,
                AVSampleRateKey: sampleRate,
                AVEncoderBitRateKey: VideoTuning.audioBitrate,
            ])
            input.expectsMediaDataInRealTime = false
            if reader.canAdd(output), writer.canAdd(input) {
                reader.add(output)
                writer.add(input)
                audio = (output, input)
            }
        }

        guard reader.startReading() else { throw reader.error ?? JobError.unreadableVideo }
        guard writer.startWriting() else { throw writer.error ?? JobError.cantSave }
        writer.startSession(atSourceTime: .zero)

        let stop = Flag()
        let seconds = source.seconds
        await withTaskCancellationHandler {
            let group = DispatchGroup()
            pump(videoOutput, into: videoInput, group: group, stop: stop) { time in
                if seconds > 0 { progress(min(1, time / seconds)) }
            }
            if let audio { pump(audio.output, into: audio.input, group: group, stop: stop, onSample: nil) }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                group.notify(queue: .global()) { continuation.resume() }
            }
        } onCancel: {
            stop.set()
        }

        if Task.isCancelled || stop.isSet {
            reader.cancelReading()
            writer.cancelWriting()
            throw CancellationError()
        }
        if reader.status == .failed {
            writer.cancelWriting()
            throw reader.error ?? JobError.unreadableVideo
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? JobError.cantSave }
    }

    /// Feeds samples from `output` into `input` as fast as the writer takes them, then marks it finished.
    private static func pump(_ output: AVAssetReaderOutput, into input: AVAssetWriterInput, group: DispatchGroup,
                             stop: Flag, onSample: (@Sendable (Double) -> Void)?) {
        group.enter()
        let pair = Unchecked((output, input))
        let done = Flag()
        input.requestMediaDataWhenReady(on: DispatchQueue(label: "droptimize.video.pump")) {
            let (output, input) = pair.value
            guard !done.isSet else { return }
            while input.isReadyForMoreMediaData {
                guard !stop.isSet, let sample = output.copyNextSampleBuffer() else {
                    input.markAsFinished()
                    done.set()
                    group.leave()
                    return
                }
                onSample?(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
                if !input.append(sample) {
                    stop.set()
                    input.markAsFinished()
                    done.set()
                    group.leave()
                    return
                }
            }
        }
    }

    // MARK: GIF

    /// A looping GIF (CORE.md §7.4) through our own encoder (`GIFWriter`): evenly spaced frames up to
    /// `gifMaxFrameRate`, at most `gifMaxSide` px and `gifMaxSeconds` long. Two passes over the
    /// video: the first picks one palette for the whole clip, the second dithers and writes.
    /// Many sites turn GIFs into video anyway; MP4 is usually far smaller.
    private static func makeGIF(_ asset: AVAsset, source: VideoSource, to url: URL,
                                progress: @escaping @Sendable (Double) -> Void) async throws -> String? {
        let seconds = min(source.seconds, VideoTuning.gifMaxSeconds)
        let frames = GIFFrameReader(asset: asset, source: source, seconds: seconds)
        let paletteShare = VideoTuning.gifPaletteShare
        func done(_ time: Double) -> Double { seconds > 0 ? min(1, max(0, time / seconds)) : 0 }

        var histogram = GIFPalette.Histogram()
        try frames.read { frame, time in
            histogram.add(rgba: frame, step: 2)
            progress(paletteShare * done(time))
        }
        let writer = GIFWriter(width: frames.width, height: frames.height, palette: GIFPalette.make(from: histogram))
        // Each frame is written when the next arrives, which says how long it stays up.
        var previous: (frame: [UInt8], time: Double)?
        try frames.read { frame, time in
            if let previous {
                writer.add(rgba: previous.frame, centiseconds: VideoTuning.gifCentiseconds(from: previous.time, to: time))
            }
            previous = (frame, time)
            progress(paletteShare + (1 - paletteShare) * done(time))
        }
        guard let last = previous else { throw JobError.unreadableVideo }
        writer.add(rgba: last.frame,
                   centiseconds: VideoTuning.gifCentiseconds(from: last.time, to: max(seconds, last.time + frames.interval / 2)))
        do {
            try writer.finish().write(to: url)
        } catch {
            throw JobError.cantSave
        }
        return source.seconds > VideoTuning.gifMaxSeconds ? "First \(Int(VideoTuning.gifMaxSeconds)) seconds" : nil
    }
}

/// Decodes the frames a GIF keeps: evenly spaced (`VideoTuning.gifFrameStep`), turned upright,
/// scaled to `VideoTuning.gifSize` with Lanczos and color-managed into sRGB by Core Image.
struct GIFFrameReader {
    let asset: AVAsset
    let source: VideoSource
    let seconds: Double
    let width: Int
    let height: Int
    /// Seconds between kept frames.
    let interval: Double
    private let orientation: CGImagePropertyOrientation

    init(asset: AVAsset, source: VideoSource, seconds: Double) {
        self.asset = asset
        self.source = source
        self.seconds = seconds
        orientation = Self.orientation(of: source.transform)
        let sideways = orientation == .left || orientation == .right
        let size = VideoTuning.gifSize(width: sideways ? source.height : source.width,
                                       height: sideways ? source.width : source.height)
        width = size.width
        height = size.height
        interval = Double(VideoTuning.gifFrameStep(sourceFPS: source.fps)) / source.fps
    }

    /// Calls `body` with each kept frame (RGBA, `width` × `height`) and its time in seconds.
    func read(_ body: ([UInt8], Double) throws -> Void) throws {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: seconds, preferredTimescale: 600))
        let output = AVAssetReaderTrackOutput(track: source.videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw JobError.unreadableVideo }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? JobError.unreadableVideo }
        defer { if reader.status == .reading { reader.cancelReading() } }

        let context = CIContext(options: [.cacheIntermediates: false])
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { throw JobError.unreadableVideo }
        var lastSlot = -1
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard time.isFinite, time < seconds else { continue }
            // The first frame in each slot of `interval`: even steps, even for variable frame rates.
            let slot = Int((time / interval + 1e-6).rounded(.down))
            guard slot > lastSlot else { continue }
            lastSlot = slot
            try body(render(pixels, context: context, colorSpace: sRGB), time)
        }
        if reader.status == .failed { throw reader.error ?? JobError.unreadableVideo }
    }

    private func render(_ pixels: CVPixelBuffer, context: CIContext, colorSpace: CGColorSpace) throws -> [UInt8] {
        var image = CIImage(cvPixelBuffer: pixels).oriented(orientation)
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let scaleY = Double(height) / image.extent.height
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image.clampedToExtent()            // no see-through edges
        filter.scale = Float(scaleY)
        filter.aspectRatio = Float((Double(width) / image.extent.width) / scaleY)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        guard let scaled = filter.outputImage?.cropped(to: bounds),
              let cgImage = context.createCGImage(scaled, from: bounds, format: .RGBA8, colorSpace: colorSpace)
        else { throw JobError.unreadableVideo }

        // Drawn into a plain sRGB bitmap: rows top to bottom, opaque.
        var frame = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = frame.withUnsafeMutableBytes { bytes -> Bool in
            guard let bitmap = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                         bytesPerRow: width * 4, space: colorSpace,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            bitmap.draw(cgImage, in: bounds)
            return true
        }
        guard drawn else { throw JobError.unreadableVideo }
        return frame
    }

    /// Phones store video sideways and say how to turn it in the track's transform.
    static func orientation(of transform: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (transform.a.rounded(), transform.b.rounded(), transform.c.rounded(), transform.d.rounded()) {
        case (0, 1, -1, 0): return .right           // portrait, as iPhones record it
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }
}

/// What the optimizer needs to know about a video before deciding how to handle it (CORE.md §7.1).
struct VideoSource {
    let videoTrack: AVAssetTrack
    let audioTrack: AVAssetTrack?
    /// Stored size, before rotation (the transform rotates it for display).
    let width: Int
    let height: Int
    let transform: CGAffineTransform
    let fps: Double
    let duration: CMTime
    let videoCodec: FourCharCode?
    let audioCodec: FourCharCode?
    let videoBitrate: Int?
    let audioChannels: Int
    let audioSampleRate: Double

    var seconds: Double { duration.seconds.isFinite ? duration.seconds : 0 }
    var shortSide: Int { min(width, height) }

    /// Already H.264 or HEVC with AAC (or no) sound, so it can go into an MP4 untouched.
    var canRemuxToMP4: Bool {
        guard videoCodec == kCMVideoCodecType_H264 || videoCodec == kCMVideoCodecType_HEVC else { return false }
        return audioTrack == nil || audioCodec == kAudioFormatMPEG4AAC
    }

    static func load(_ asset: AVAsset) async throws -> VideoSource {
        guard let video = try? await asset.loadTracks(withMediaType: .video).first,
              let duration = try? await asset.load(.duration)
        else { throw JobError.unreadableVideo }
        let (size, transform, fps, rate, formats) = try await video.load(
            .naturalSize, .preferredTransform, .nominalFrameRate, .estimatedDataRate, .formatDescriptions)
        let audio = try? await asset.loadTracks(withMediaType: .audio).first
        var audioCodec: FourCharCode?
        var channels = 0
        var sampleRate = 0.0
        if let audio, let description = try? await audio.load(.formatDescriptions).first {
            audioCodec = CMFormatDescriptionGetMediaSubType(description)
            if let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
                channels = Int(basic.mChannelsPerFrame)
                sampleRate = basic.mSampleRate
            }
        }
        return VideoSource(videoTrack: video, audioTrack: audio,
                           width: Int(abs(size.width).rounded()), height: Int(abs(size.height).rounded()),
                           transform: transform, fps: fps > 0 ? Double(fps) : 30, duration: duration,
                           videoCodec: formats.first.map(CMFormatDescriptionGetMediaSubType), audioCodec: audioCodec,
                           videoBitrate: rate > 0 ? Int(rate) : nil, audioChannels: channels, audioSampleRate: sampleRate)
    }
}

/// Hands a non-Sendable value to a callback that runs elsewhere, when we know it's only used there.
struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// A thread-safe on/off switch.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock(); defer { lock.unlock() }
        value = true
    }
}
