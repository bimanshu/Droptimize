import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import ImageIO

/// Re-encodes a video as WebM (CORE.md §7.4): AVFoundation decodes it, Core Image turns frames
/// upright and scales them into BT.709 NV12 (WebM has no rotation flag), VP9 or AV1 encodes the
/// picture and Opus the sound, resampled to 48 kHz, and `WebMWriter` puts them together.
enum WebMTranscoder {
    /// `width` × `height` is the stored (unrotated) size, as for the MP4 encoder. `quality` nil aims
    /// at `bitrate` (Compress to a size); otherwise it's a constant quality capped at `bitrate`.
    static func transcode(_ asset: AVAsset, source: VideoSource, width: Int, height: Int, bitrate: Int,
                          quality: Int?, codec: VideoPlan.Codec, to url: URL, keepsQuality: Bool = false,
                          progress: @escaping @Sendable (Double) -> Void) throws {
        let orientation = GIFFrameReader.orientation(of: source.transform)
        let sideways = orientation == .left || orientation == .right
        let frameWidth = sideways ? height : width, frameHeight = sideways ? width : height

        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(track: source.videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw JobError.unreadableVideo }
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderTrackOutput?
        var opus: OpusAudioEncoder?
        if let audioTrack = source.audioTrack {
            let channels = min(max(source.audioChannels, 1), 2)
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVNumberOfChannelsKey: channels,
                AVSampleRateKey: OpusAudioEncoder.sampleRate,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
                opus = try OpusAudioEncoder(channels: channels, bitrate: channels * (keepsQuality ? VideoTuning.convertAudioBitratePerChannel
                                                                                                  : VideoTuning.opusBitratePerChannel))
            }
        }

        let settings = WebMVideoSettings(
            width: frameWidth, height: frameHeight, fps: source.fps, bitrate: bitrate, quality: quality,
            keyframeInterval: VideoTuning.webmKeyframeInterval(fps: source.fps),
            speed: codec == .av1 ? VideoTuning.av1Speed : VideoTuning.vp9Speed,
            threads: min(max(ProcessInfo.processInfo.activeProcessorCount, 1), 16))
        let encoder: WebMVideoEncoder = codec == .av1 ? try AV1Encoder(settings) : try VP9Encoder(settings)
        let writer = try WebMWriter(
            url: url,
            video: .init(codecID: encoder.codecID, width: frameWidth, height: frameHeight, codecPrivate: encoder.codecPrivate),
            audio: opus.map { .init(codecID: "A_OPUS", sampleRate: Double(OpusAudioEncoder.sampleRate), channels: $0.channels,
                                    codecPrivate: $0.codecPrivate, codecDelayNanoseconds: $0.codecDelayNanoseconds,
                                    seekPreRollNanoseconds: 80_000_000) })
        let frames = try FrameConverter(width: frameWidth, height: frameHeight, orientation: orientation)

        guard reader.startReading() else { throw reader.error ?? JobError.unreadableVideo }
        defer { if reader.status == .reading { reader.cancelReading() } }

        // Read both tracks in step, always from the one that's behind, so neither stalls the reader.
        var origin: Double?                            // the first frame's time: the WebM starts there
        var lastVideo = -Double.infinity
        var videoDone = false, audioDone = audioOutput == nil
        var sound = SoundAligner()
        let seconds = source.seconds
        while !videoDone || !audioDone {
            try Task.checkCancellation()
            if !videoDone && (audioDone || lastVideo <= sound.seconds) {
                guard let sample = videoOutput.copyNextSampleBuffer() else {
                    videoDone = true
                    for packet in try encoder.finish() { try writer.add(packet, to: .video) }
                    try writer.endTrack(.video)
                    continue
                }
                guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
                let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                guard time.isFinite else { continue }
                let start = origin ?? time
                origin = start
                // Encoders need times that go forward.
                guard time - start > lastVideo else { continue }
                lastVideo = time - start
                for packet in try frames.encode(pixels, with: encoder, at: lastVideo) { try writer.add(packet, to: .video) }
                if seconds > 0 { progress(min(1, lastVideo / seconds)) }
            } else if let audioOutput, let opus {
                guard let sample = audioOutput.copyNextSampleBuffer() else {
                    audioDone = true
                    for packet in try opus.finish() { try writer.add(packet, to: .audio) }
                    try writer.endTrack(.audio)
                    continue
                }
                let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds - (origin ?? 0)
                let samples = sound.align(Self.floats(in: sample), at: time, channels: opus.channels)
                for packet in try opus.encode(samples) { try writer.add(packet, to: .audio) }
            }
        }
        if reader.status == .failed { throw reader.error ?? JobError.unreadableVideo }
        guard origin != nil else { throw JobError.unreadableVideo }
        try writer.finish()
    }

    /// Interleaved 32-bit float samples, as the reader was asked for.
    private static func floats(in sample: CMSampleBuffer) -> [Float] {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return [] }
        let length = CMBlockBufferGetDataLength(block)
        var samples = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
        let status = samples.withUnsafeMutableBytes { bytes in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: bytes.baseAddress!)
        }
        return status == kCMBlockBufferNoErr ? samples : []
    }
}

/// Keeps the sound in sync with the picture: silence where the sound starts late or skips, and
/// anything before the first frame dropped. Small timing wobble between buffers is ignored.
private struct SoundAligner {
    private var written = 0
    /// Gaps shorter than this are timing wobble, not missing sound.
    private static let gapTolerance = OpusAudioEncoder.sampleRate / 10

    var seconds: Double { Double(written) / Double(OpusAudioEncoder.sampleRate) }

    mutating func align(_ samples: [Float], at time: Double, channels: Int) -> [Float] {
        guard !samples.isEmpty, time.isFinite else { return [] }
        let start = Int((time * Double(OpusAudioEncoder.sampleRate)).rounded())
        var aligned = samples
        if written == 0 || start - written > Self.gapTolerance {
            if start > written {
                aligned = [Float](repeating: 0, count: (start - written) * channels) + samples
            } else if written == 0, start < 0 {
                aligned = Array(samples.dropFirst(min(-start * channels, samples.count)))
            }
        }
        written += aligned.count / channels
        return aligned
    }
}

/// Turns decoded frames into what the WebM encoders take: upright, at the output size, NV12 in
/// BT.709. Frames that already are pass straight through, untouched.
private final class FrameConverter {
    private let width: Int
    private let height: Int
    private let orientation: CGImagePropertyOrientation
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let pool: CVPixelBufferPool
    private let colorSpace: CGColorSpace

    init(width: Int, height: Int, orientation: CGImagePropertyOrientation) throws {
        self.width = width
        self.height = height
        self.orientation = orientation
        guard let colorSpace = CGColorSpace(name: CGColorSpace.itur_709) else { throw JobError.unreadableVideo }
        self.colorSpace = colorSpace
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        var pool: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess, let pool
        else { throw JobError.unreadableVideo }
        self.pool = pool
    }

    func encode(_ pixels: CVPixelBuffer, with encoder: WebMVideoEncoder, at seconds: Double) throws -> [EncodedPacket] {
        let frame = try convert(pixels)
        CVPixelBufferLockBaseAddress(frame, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
        guard let luma = CVPixelBufferGetBaseAddressOfPlane(frame, 0),
              let chroma = CVPixelBufferGetBaseAddressOfPlane(frame, 1)
        else { throw JobError.unreadableVideo }
        return try encoder.encode(NV12Frame(luma: UnsafePointer(luma.assumingMemoryBound(to: UInt8.self)),
                                            lumaStride: CVPixelBufferGetBytesPerRowOfPlane(frame, 0),
                                            chroma: UnsafePointer(chroma.assumingMemoryBound(to: UInt8.self)),
                                            chromaStride: CVPixelBufferGetBytesPerRowOfPlane(frame, 1)),
                                  seconds: seconds)
    }

    private func convert(_ pixels: CVPixelBuffer) throws -> CVPixelBuffer {
        if passesThrough(pixels) { return pixels }

        var image = CIImage(cvPixelBuffer: pixels).oriented(orientation)
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let scaleX = Double(width) / image.extent.width, scaleY = Double(height) / image.extent.height
        if abs(scaleX - 1) > 1e-6 || abs(scaleY - 1) > 1e-6 {
            let filter = CIFilter.lanczosScaleTransform()
            filter.inputImage = image.clampedToExtent()            // no see-through edges
            filter.scale = Float(scaleY)
            filter.aspectRatio = Float(scaleX / scaleY)
            guard let scaled = filter.outputImage else { throw JobError.unreadableVideo }
            image = scaled
        }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)

        var output: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output) == kCVReturnSuccess, let output
        else { throw JobError.unreadableVideo }
        // What the encoders are told the frames are (Core Image converts to them).
        CVBufferSetAttachment(output, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(output, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(output, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        context.render(image.cropped(to: bounds), to: output, bounds: bounds, colorSpace: colorSpace)
        return output
    }

    /// Already upright, the right size, NV12 and tagged BT.709: most screen recordings and phone clips.
    private func passesThrough(_ pixels: CVPixelBuffer) -> Bool {
        guard orientation == .up, CVPixelBufferGetWidth(pixels) == width, CVPixelBufferGetHeight(pixels) == height,
              CVPixelBufferGetPixelFormatType(pixels) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        else { return false }
        func tag(_ key: CFString) -> String? { CVBufferCopyAttachment(pixels, key, nil) as? String }
        return tag(kCVImageBufferYCbCrMatrixKey) == kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String
            && tag(kCVImageBufferColorPrimariesKey) == kCVImageBufferColorPrimaries_ITU_R_709_2 as String
            && tag(kCVImageBufferTransferFunctionKey) == kCVImageBufferTransferFunction_ITU_R_709_2 as String
    }
}
