import AVFoundation
import ImageIO
import XCTest
@testable import Droptimize

// macOS only: every video action on real (synthetic) videos. Runs in CI and Xcode.
final class VideoMacTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("VideoMacTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: Making test videos

    /// An H.264 .mov of noise (so it's big, like a screen recording at a high bitrate), with an
    /// AAC sine tone when `sound` is true. With `halves`, a still frame instead: the stored left half
    /// red, the right half blue (for checking colors and rotation).
    private func makeVideo(_ name: String, width: Int = 1280, height: Int = 720, seconds: Double = 1.5,
                           bitrate: Int = 12_000_000, sound: Bool = true, halves: Bool = false,
                           transform: CGAffineTransform = .identity) async throws -> URL {
        let silent = folder.appendingPathComponent("silent-\(name)")
        try await writeNoise(to: silent, width: width, height: height, seconds: seconds, bitrate: bitrate,
                             halves: halves, transform: transform)
        let url = folder.appendingPathComponent(name)
        guard sound else {
            try FileManager.default.moveItem(at: silent, to: url)
            return url
        }
        let tone = folder.appendingPathComponent("tone-\(UUID().uuidString).m4a")
        try writeTone(to: tone, seconds: seconds)

        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: silent), audioAsset = AVURLAsset(url: tone)
        let duration = try await videoAsset.load(.duration)
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        let videoTrack = try XCTUnwrap(videoTracks.first)
        let audioTrack = try XCTUnwrap(audioTracks.first)
        let audioDuration = try await audioAsset.load(.duration)
        try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
            .insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)
        try XCTUnwrap(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
            .insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, audioDuration)), of: audioTrack, at: .zero)
        try await VideoOptimizer.export(composition, preset: AVAssetExportPresetPassthrough, to: url, fileType: .mov)
        try? FileManager.default.removeItem(at: silent)
        try? FileManager.default.removeItem(at: tone)
        return url
    }

    private func writeNoise(to url: URL, width: Int, height: Int, seconds: Double, bitrate: Int,
                            halves: Bool, transform: CGAffineTransform) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate],
        ])
        input.expectsMediaDataInRealTime = false
        input.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let fps: Int32 = 30
        for frame in 0..<Int(seconds * Double(fps)) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &buffer)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels))
            let rowBytes = CVPixelBufferGetBytesPerRow(pixels)
            if halves {
                let bytes = base.assumingMemoryBound(to: UInt8.self)
                for y in 0..<height {
                    for x in 0..<width {
                        let i = y * rowBytes + x * 4                          // BGRA
                        let (r, g, b): (UInt8, UInt8, UInt8) = x < width / 2 ? (220, 40, 40) : (40, 60, 220)
                        bytes[i] = b; bytes[i + 1] = g; bytes[i + 2] = r; bytes[i + 3] = 255
                    }
                }
            } else {
                arc4random_buf(base, rowBytes * height)
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error.map { "\($0)" } ?? "")
    }

    private func writeTone(to url: URL, seconds: Double) throws {
        let rate = 44_100.0
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
        ])
        let frames = AVAudioFrameCount(rate * seconds)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        for i in 0..<Int(frames) { samples[i] = Float(sin(Double(i) * 2 * .pi * 440 / rate) * 0.3) }
        try file.write(from: buffer)
    }

    private func info(_ url: URL) async throws -> (width: Int, height: Int, hasAudio: Bool, codec: FourCharCode?, seconds: Double) {
        let asset = AVURLAsset(url: url)
        let videos = try await asset.loadTracks(withMediaType: .video)
        let video = try XCTUnwrap(videos.first)
        let (size, formats) = try await video.load(.naturalSize, .formatDescriptions)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration)
        return (Int(size.width), Int(size.height), !audio.isEmpty, formats.first.map(CMFormatDescriptionGetMediaSubType),
                duration.seconds)
    }

    private func process(_ input: URL, _ action: Action, _ option: ActionOption? = nil) async throws -> FileOutcome {
        try await VideoOptimizer.process(input, action: action, option: option) { _ in }
    }

    // MARK: Tests

    func testConvertMOVToMP4RemuxesWithoutReencoding() async throws {
        let input = try await makeVideo("clip.mov")
        let outcome = try await process(input, .convert, .videoFormat(.mp4))
        XCTAssertEqual(outcome.output.lastPathComponent, "clip.mp4")
        let out = try await info(outcome.output)
        XCTAssertEqual(out.codec, kCMVideoCodecType_H264)
        XCTAssertTrue(out.hasAudio)
        XCTAssertEqual(out.width, 1280)
        XCTAssertEqual(Double(outcome.outputBytes), Double(outcome.inputBytes), accuracy: Double(outcome.inputBytes) * 0.05,
                       "a remux keeps the streams, so the size barely changes")
    }

    func testAutoMakesASmallerMP4() async throws {
        let input = try await makeVideo("recording.mov")
        let outcome = try await process(input, .auto)
        XCTAssertEqual(outcome.output.lastPathComponent, "recording.mp4")
        XCTAssertLessThan(outcome.outputBytes, outcome.inputBytes)
        let out = try await info(outcome.output)
        XCTAssertTrue(out.hasAudio, "the sound is kept")
        XCTAssertEqual(out.seconds, 1.5, accuracy: 0.2)
    }

    func testResizeTo480p() async throws {
        let input = try await makeVideo("wide.mov")
        let outcome = try await process(input, .resize, .maxShortSide(480))
        XCTAssertEqual(outcome.output.lastPathComponent, "wide-480p.mov")
        let out = try await info(outcome.output)
        XCTAssertEqual(out.height, 480)
        XCTAssertEqual(out.width, 854)
    }

    func testResizeNeverUpscales() async throws {
        let input = try await makeVideo("small.mov", width: 640, height: 360, sound: false)
        do {
            _ = try await process(input, .resize, .maxShortSide(720))
            XCTFail("expected alreadyAtMost")
        } catch {
            XCTAssertEqual(error as? JobError, .alreadyAtMost(720))
        }
    }

    func testCompressToATargetSize() async throws {
        let input = try await makeVideo("big.mov", seconds: 2)
        let limit = outcomeSize(input) / 3
        let outcome = try await process(input, .compress, .maxBytes(limit))
        XCTAssertLessThanOrEqual(outcome.outputBytes, limit)
        XCTAssertEqual(outcome.output.pathExtension, "mov")
    }

    func testMuteDropsTheSound() async throws {
        let input = try await makeVideo("talk.mov")
        let outcome = try await process(input, .mute)
        XCTAssertEqual(outcome.output.lastPathComponent, "talk-muted.mov")
        let out = try await info(outcome.output)
        XCTAssertFalse(out.hasAudio)
        XCTAssertEqual(out.width, 1280, "the picture is untouched")
    }

    func testMuteWithoutSoundSaysSo() async throws {
        let input = try await makeVideo("quiet.mov", sound: false)
        do {
            _ = try await process(input, .mute)
            XCTFail("expected noAudio")
        } catch {
            XCTAssertEqual(error as? JobError, .noAudio)
        }
    }

    func testGIFKeepsEveryFrameAndTheTiming() async throws {
        let input = try await makeVideo("loop.mov", width: 640, height: 360, seconds: 1, sound: false)
        let outcome = try await process(input, .convert, .videoFormat(.gif))
        XCTAssertEqual(outcome.output.lastPathComponent, "loop.gif")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(outcome.output as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 30, "every frame of a 30 fps second (noise changes every one)")
        var total = 0.0
        for index in 0..<CGImageSourceGetCount(source) {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            total += (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? 0
        }
        XCTAssertEqual(total, 1, accuracy: 0.05, "plays for as long as the video")
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 640)
        XCTAssertEqual(image.height, 360)
    }

    func testGIFColorsAndPortraitRotation() async throws {
        // Stored landscape and turned a quarter clockwise for display, as iPhones record portrait.
        let input = try await makeVideo("portrait.mov", width: 320, height: 180, seconds: 0.5, sound: false,
                                        halves: true, transform: CGAffineTransform(rotationAngle: .pi / 2))
        let outcome = try await process(input, .convert, .videoFormat(.gif))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(outcome.output as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 180, "upright: portrait")
        XCTAssertEqual(image.height, 320)

        var pixels = [UInt8](repeating: 0, count: 180 * 320 * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 180, height: 320, bitsPerComponent: 8, bytesPerRow: 180 * 4,
                                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: 180, height: 320))
        }
        func color(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {           // y from the top
            let i = (y * 180 + x) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
        }
        // The stored left half (red) is the top once turned; the right half (blue) the bottom.
        let top = color(90, 80), bottom = color(90, 240)
        XCTAssertGreaterThan(top.r, 170, "top: \(top)")
        XCTAssertLessThan(top.b, 100, "top: \(top)")
        XCTAssertGreaterThan(bottom.b, 170, "bottom: \(bottom)")
        XCTAssertLessThan(bottom.r, 100, "bottom: \(bottom)")
        XCTAssertEqual(top.r, 220, accuracy: 25, "colors survive the trip: \(top)")
        XCTAssertEqual(bottom.b, 220, accuracy: 25, "colors survive the trip: \(bottom)")
    }

    func testHEVC() async throws {
        let input = try await makeVideo("phone.mov")
        do {
            let outcome = try await process(input, .convert, .videoFormat(.hevc))
            XCTAssertEqual(outcome.output.lastPathComponent, "phone-hevc.mp4")
            let out = try await info(outcome.output)
            XCTAssertEqual(out.codec, kCMVideoCodecType_HEVC)
        } catch JobError.notYet(let message) where message.contains("HEVC") {
            throw XCTSkip("This machine has no HEVC encoder")
        }
    }

    @MainActor
    func testRunnerReportsProgressWithinAVideo() async throws {
        let input = try await makeVideo("progress.mov", seconds: 2)
        var updates: [JobProgress] = []
        let result = try await ImageJobRunner().run(Job(files: [input], action: .auto)) { updates.append($0) }
        XCTAssertEqual(result.outputs.count, 1)
        XCTAssertTrue(updates.contains { $0.completed == 0 && $0.fraction > 0 }, "progress moves before the file is done")
    }

    private func outcomeSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }
}
