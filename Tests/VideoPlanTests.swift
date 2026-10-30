import XCTest
@testable import Droptimize

// Portable: also runs on Linux via scripts/check-linux.sh.
final class VideoPlanTests: XCTestCase {
    func testAutoMakesASmallerMP4() throws {
        XCTAssertEqual(try VideoPlan.make(action: .auto, option: nil, sourceExtension: "MOV"),
                       VideoPlan(work: .encode(.h264), fileExtension: "mp4", appliesSizeGuard: true))
        XCTAssertEqual(try VideoPlan.make(action: .auto, option: nil, sourceExtension: "mp4").suffix, "-min")
    }

    func testConvert() throws {
        XCTAssertEqual(try VideoPlan.make(action: .convert, option: .videoFormat(.mp4), sourceExtension: "mov"),
                       VideoPlan(work: .remuxOrEncode(.h264), fileExtension: "mp4", appliesSizeGuard: false))
        XCTAssertEqual(try VideoPlan.make(action: .convert, option: nil, sourceExtension: "mov").work, .remuxOrEncode(.h264),
                       "Convert itself = MP4")
        XCTAssertEqual(try VideoPlan.make(action: .convert, option: .videoFormat(.mp4), sourceExtension: "mp4"),
                       try VideoPlan.make(action: .auto, option: nil, sourceExtension: "mp4"), "MP4 to MP4 is a recompress")
        XCTAssertEqual(try VideoPlan.make(action: .convert, option: .videoFormat(.hevc), sourceExtension: "mov"),
                       VideoPlan(work: .encode(.hevc), fileExtension: "mp4", suffix: "-hevc", appliesSizeGuard: false))
        XCTAssertEqual(try VideoPlan.make(action: .convert, option: .videoFormat(.gif), sourceExtension: "mp4"),
                       VideoPlan(work: .gif, fileExtension: "gif", appliesSizeGuard: false))
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

    func testVideoOptionBubbles() {
        XCTAssertEqual(Action.convert.options(for: .video, lastColor: nil).map(\.option),
                       [.videoFormat(.mp4), .videoFormat(.hevc), .videoFormat(.gif)])
        XCTAssertEqual(Action.compress.options(for: .video, lastColor: nil).map(\.title),
                       ["Under 10 MB", "Under 25 MB", "Under 50 MB", "Under 100 MB", "Custom size"])
        XCTAssertEqual(Action.resize.options(for: .video, lastColor: nil).map(\.label), [.text("1080p"), .text("720p"), .text("480p")])
        XCTAssertTrue(Action.mute.options(for: .video, lastColor: nil).isEmpty)
        XCTAssertTrue(Action.compress.options(for: nil, lastColor: nil).isEmpty, "mixed drops: plain Compress")
        XCTAssertEqual(ActionMenu.video.geometryOptionCounts, [3, 5, 3, 0])
        XCTAssertEqual(ActionOption.maxShortSide(720).title, "720p")
        XCTAssertEqual(ActionOption.videoFormat(.gif).title, "To GIF")
    }
}
