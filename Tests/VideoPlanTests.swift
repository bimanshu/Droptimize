import XCTest
@testable import Droptimize

// Portable: also runs on Linux via scripts/check-linux.sh.
final class VideoPlanTests: XCTestCase {
    func testAutoMakesASmallerWebM() throws {
        XCTAssertEqual(try VideoPlan.make(action: .auto, option: nil, sourceExtension: "MOV"),
                       VideoPlan(work: .encode(.vp9), fileExtension: "webm", appliesSizeGuard: true))
        XCTAssertEqual(try VideoPlan.make(action: .auto, option: nil, sourceExtension: "mp4"),
                       VideoPlan(work: .encode(.vp9), fileExtension: "webm", appliesSizeGuard: true))
    }

    func testConvert() throws {
        XCTAssertEqual(try VideoPlan.make(action: .convert, option: nil, sourceExtension: "mov"),
                       VideoPlan(work: .encode(.vp9), fileExtension: "webm", appliesSizeGuard: false, keepsQuality: true),
                       "Convert itself = WebM")
        XCTAssertEqual(try VideoPlan.make(action: .convert, option: .videoFormat(.webm), sourceExtension: "mp4"),
                       VideoPlan(work: .encode(.vp9), fileExtension: "webm", appliesSizeGuard: false, keepsQuality: true))
        XCTAssertEqual(try VideoPlan.make(action: .convert, option: .videoFormat(.av1), sourceExtension: "mov"),
                       VideoPlan(work: .encode(.av1), fileExtension: "webm", suffix: "-av1", appliesSizeGuard: false, keepsQuality: true))
        XCTAssertEqual(try VideoPlan.make(action: .convert, option: .videoFormat(.mp4), sourceExtension: "mov"),
                       VideoPlan(work: .remuxOrEncode(.h264), fileExtension: "mp4", appliesSizeGuard: false, keepsQuality: true))
        XCTAssertThrowsError(try VideoPlan.make(action: .convert, option: .videoFormat(.mp4), sourceExtension: "mp4"),
                             "MP4 to MP4 has nothing to change") { XCTAssertEqual($0 as? JobError, .alreadyFormat("MP4")) }
        XCTAssertEqual(try VideoPlan.make(action: .convert, option: .videoFormat(.hevc), sourceExtension: "mov"),
                       VideoPlan(work: .encode(.hevc), fileExtension: "mp4", suffix: "-hevc", appliesSizeGuard: false, keepsQuality: true))
        XCTAssertEqual(try VideoPlan.make(action: .convert, option: .videoFormat(.gif), sourceExtension: "mp4"),
                       VideoPlan(work: .gif, fileExtension: "gif", appliesSizeGuard: false))
    }

    func testOnlyConvertKeepsQuality() throws {
        XCTAssertFalse(try VideoPlan.make(action: .auto, option: nil, sourceExtension: "mov").keepsQuality)
        XCTAssertFalse(try VideoPlan.make(action: .compress, option: nil, sourceExtension: "mov").keepsQuality)
        XCTAssertFalse(try VideoPlan.make(action: .resize, option: nil, sourceExtension: "mov").keepsQuality)
    }

    func testConversionsSpendTheSourcesBitrate() {
        let sourceRate = 8_000_000
        XCTAssertEqual(VideoTuning.conversionBitrate(sourceBitrate: sourceRate, width: 1920, height: 1080, fps: 30), sourceRate)
        let pixelsPerSecond = Double(1920 * 1080 * 30)
        XCTAssertEqual(VideoTuning.conversionBitrate(sourceBitrate: nil, width: 1920, height: 1080, fps: 30),
                       Int(pixelsPerSecond * VideoTuning.convertBitsPerPixel), "a generous bitrate when the source doesn't say")
        XCTAssertEqual(VideoTuning.conversionBitrate(sourceBitrate: 700_000_000, width: 1920, height: 1080, fps: 30),
                       Int(pixelsPerSecond * VideoTuning.maxConvertBitsPerPixel), "a ProRes master's bitrate isn't copied")
        XCTAssertLessThan(VideoTuning.quality(for: .vp9, keepsQuality: true)!, VideoTuning.quality(for: .vp9)!, "lower is better")
        XCTAssertLessThan(VideoTuning.quality(for: .av1, keepsQuality: true)!, VideoTuning.quality(for: .av1)!)
    }

    func testCompressKeepsTheContainer() throws {
        XCTAssertEqual(try VideoPlan.make(action: .compress, option: nil, sourceExtension: "mov"),
                       VideoPlan(work: .encode(.h264), fileExtension: "mov", suffix: "-min", appliesSizeGuard: true))
        XCTAssertEqual(try VideoPlan.make(action: .compress, option: .maxBytes(25_000_000), sourceExtension: "mp4"),
                       VideoPlan(work: .encode(.h264), fileExtension: "mp4", suffix: "-25mb", targetBytes: 25_000_000,
                                 appliesSizeGuard: true))
        XCTAssertEqual(try VideoPlan.make(action: .compress, option: nil, sourceExtension: "mkv").fileExtension, "mp4")
    }

    func testResizeAndMute() throws {
        XCTAssertEqual(try VideoPlan.make(action: .resize, option: .maxShortSide(720), sourceExtension: "mov"),
                       VideoPlan(work: .encode(.h264), fileExtension: "mov", suffix: "-720p", maxShortSide: 720,
                                 appliesSizeGuard: true))
        XCTAssertEqual(try VideoPlan.make(action: .resize, option: nil, sourceExtension: "mp4").maxShortSide, 1080)
        XCTAssertEqual(try VideoPlan.make(action: .mute, option: nil, sourceExtension: "mp4"),
                       VideoPlan(work: .dropAudio, fileExtension: "mp4", suffix: "-muted", appliesSizeGuard: false))
    }

    func testImageActionsDontApply() {
        XCTAssertThrowsError(try VideoPlan.make(action: .removeBackground, option: nil, sourceExtension: "mov"))
        XCTAssertThrowsError(try VideoPlan.make(action: .halfSize, option: nil, sourceExtension: "mov"))
    }
}

final class VideoTuningTests: XCTestCase {
    func testBitrateFollowsSizeAndCodec() {
        let fullHD = VideoTuning.bitrate(width: 1920, height: 1080, fps: 30, codec: .h264)
        XCTAssertEqual(Double(fullHD), 1920 * 1080 * 30 * VideoTuning.h264BitsPerPixel, accuracy: 1)
        XCTAssertLessThan(VideoTuning.bitrate(width: 1920, height: 1080, fps: 30, codec: .hevc), fullHD)
        XCTAssertLessThan(VideoTuning.bitrate(width: 1920, height: 1080, fps: 30, codec: .vp9), fullHD)
        XCTAssertLessThan(VideoTuning.bitrate(width: 1920, height: 1080, fps: 30, codec: .av1),
                          VideoTuning.bitrate(width: 1920, height: 1080, fps: 30, codec: .vp9))
        XCTAssertEqual(VideoTuning.bitrate(width: 16, height: 16, fps: 1, codec: .h264), VideoTuning.minBitrate)
        XCTAssertEqual(VideoTuning.bitrate(width: 7680, height: 4320, fps: 60, codec: .h264), VideoTuning.maxBitrate)
    }

    func testBitrateForATargetSize() {
        // 25 MB over 100 s with sound: a little under 2 Mbps of video.
        let bitrate = VideoTuning.bitrate(fitting: 25_000_000, seconds: 100, hasAudio: true)
        XCTAssertEqual(bitrate, Int(25_000_000 * 8 * VideoTuning.targetSizeSafety / 100) - VideoTuning.audioBitrate)
        XCTAssertGreaterThan(VideoTuning.bitrate(fitting: 25_000_000, seconds: 100, hasAudio: false), bitrate)
        XCTAssertEqual(VideoTuning.bitrate(fitting: 1000, seconds: 600, hasAudio: true), VideoTuning.minBitrate)
    }

    func testWebMEncodesAtAQualityAndKeyframesEveryFewSeconds() {
        XCTAssertEqual(VideoTuning.quality(for: .vp9), VideoTuning.vp9Quality)
        XCTAssertEqual(VideoTuning.quality(for: .av1), VideoTuning.av1Quality)
        XCTAssertNil(VideoTuning.quality(for: .h264), "Apple's encoders aim at a bitrate")
        XCTAssertEqual(VideoTuning.webmKeyframeInterval(fps: 30), Int(30 * VideoTuning.webmKeyframeSeconds))
        XCTAssertEqual(VideoTuning.webmKeyframeInterval(fps: 0), Int(VideoTuning.webmKeyframeSeconds))
        XCTAssertTrue(VideoPlan.Codec.vp9.isWebM && VideoPlan.Codec.av1.isWebM && !VideoPlan.Codec.h264.isWebM)
    }

    func testResizingKeepsTheShapeNeverUpscalesAndStaysEven() {
        XCTAssertTrue(VideoTuning.size(width: 1920, height: 1080, maxShortSide: 720) == (1280, 720))
        XCTAssertTrue(VideoTuning.size(width: 1080, height: 1920, maxShortSide: 720) == (720, 1280), "portrait")
        XCTAssertTrue(VideoTuning.size(width: 1280, height: 720, maxShortSide: 480) == (854, 480))
        XCTAssertTrue(VideoTuning.size(width: 640, height: 360, maxShortSide: 1080) == (640, 360), "never upscales")
        XCTAssertTrue(VideoTuning.size(width: 641, height: 361, maxShortSide: nil) == (642, 362), "even sizes")
    }

    func testDropsToASmallerSizeWhenTheBitrateIsTooLow() {
        XCTAssertNil(VideoTuning.shortSide(for: 5_000_000, width: 1920, height: 1080, fps: 30))
        XCTAssertEqual(VideoTuning.shortSide(for: 1_000_000, width: 1920, height: 1080, fps: 30), 720)
        XCTAssertEqual(VideoTuning.shortSide(for: 100_000, width: 1920, height: 1080, fps: 30), 360)
    }

    func testFittingStepsDownByPixels() {
        XCTAssertEqual(VideoTuning.shortSide(below: 1080, pixelShare: 0.5), 720, "720p has 44% of 1080p's pixels")
        XCTAssertEqual(VideoTuning.shortSide(below: 720, pixelShare: 0.35), 360, "480p (44%) is still too many")
        XCTAssertEqual(VideoTuning.shortSide(below: 720, pixelShare: 0.01), 360, "the smallest when none is enough")
        XCTAssertNil(VideoTuning.shortSide(below: 360, pixelShare: 0.5), "nothing smaller than 360p")
    }

    func testVideoOptionBubbles() {
        XCTAssertEqual(Action.convert.options(for: .video, lastColor: nil).map(\.option),
                       [.videoFormat(.webm), .videoFormat(.av1), .videoFormat(.mp4), .videoFormat(.hevc), .videoFormat(.gif)])
        XCTAssertEqual(Action.convert.options(for: .video, lastColor: nil).map(\.label),
                       [.text("WebM"), .text("AV1"), .text("MP4"), .text("HEVC"), .text("GIF")])
        XCTAssertEqual(Action.compress.options(for: .video, lastColor: nil).map(\.title),
                       ["Under 10 MB", "Under 25 MB", "Under 50 MB", "Under 100 MB", "Custom size"])
        XCTAssertEqual(Action.resize.options(for: .video, lastColor: nil).map(\.label), [.text("1080p"), .text("720p"), .text("480p")])
        XCTAssertTrue(Action.mute.options(for: .video, lastColor: nil).isEmpty)
        XCTAssertTrue(Action.compress.options(for: nil, lastColor: nil).isEmpty, "mixed drops: plain Compress")
        XCTAssertEqual(ActionMenu.video.geometryOptionCounts, [5, 5, 3, 0])
        XCTAssertEqual(ActionOption.maxShortSide(720).title, "720p")
        XCTAssertEqual(ActionOption.videoFormat(.gif).title, "To GIF")
        XCTAssertEqual(ActionOption.videoFormat(.webm).title, "To WebM")
    }
}
