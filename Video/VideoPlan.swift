import Foundation

/// What Convert can turn a video into (CORE.md §7.4). WebM waits for FFmpeg or libvpx (owner's OK).
enum VideoFormat: String, Hashable, CaseIterable {
    case mp4, hevc, gif

    var displayName: String {
        switch self {
        case .mp4: return "MP4"
        case .hevc: return "HEVC"
        case .gif: return "GIF"
        }
    }
}

/// What an action turns a video into (CORE.md §7.4). Portable, so it's tested on Linux too.
struct VideoPlan: Equatable {
    enum Codec: Equatable {
        case h264, hevc
    }

    enum Work: Equatable {
        /// Copy the streams into an MP4 without re-encoding when they're already H.264/HEVC + AAC
        /// (instant and lossless, CORE.md §7.2); otherwise encode with this codec.
        case remuxOrEncode(Codec)
        case encode(Codec)
        case gif
        /// Copy the video as it is, without the sound.
        case dropAudio
    }

    var work: Work
    var fileExtension: String
    var suffix: String?
    /// Resize: the shorter side's limit, as in "720p".
    var maxShortSide: Int?
    /// Compress to a size.
    var targetBytes: Int?
    /// Conversions and Mute do what was asked even if bigger; the rest never hand back a bigger file (Rule 3).
    var appliesSizeGuard: Bool

    static func make(action: Action, option: ActionOption?, sourceExtension: String) throws -> VideoPlan {
        let ext = sourceExtension.lowercased()
        let container = ["mov", "mp4", "m4v"].contains(ext) ? ext : "mp4"
        switch action {
        case .auto:
            return VideoPlan(work: .encode(.h264), fileExtension: "mp4", suffix: ext == "mp4" ? "-min" : nil,
                             appliesSizeGuard: true)
        case .convert:
            var format = VideoFormat.mp4
            if case .videoFormat(let chosen) = option { format = chosen }
            switch format {
            case .mp4 where ext == "mp4":
                return try make(action: .auto, option: nil, sourceExtension: ext)    // already MP4: a recompress
            case .mp4:
                return VideoPlan(work: .remuxOrEncode(.h264), fileExtension: "mp4", appliesSizeGuard: false)
            case .hevc:
                return VideoPlan(work: .encode(.hevc), fileExtension: "mp4", suffix: "-hevc", appliesSizeGuard: false)
            case .gif:
                return VideoPlan(work: .gif, fileExtension: "gif", appliesSizeGuard: false)
            }
        case .compress:
            if case .maxBytes(let bytes) = option {
                return VideoPlan(work: .encode(.h264), fileExtension: container, suffix: ByteCount.suffix(bytes),
                                 targetBytes: bytes, appliesSizeGuard: true)
            }
            return VideoPlan(work: .encode(.h264), fileExtension: container, suffix: "-min", appliesSizeGuard: true)
        case .resize:
            var side = VideoTuning.resizeSides[0]
            if case .maxShortSide(let chosen) = option { side = chosen }
            return VideoPlan(work: .encode(.h264), fileExtension: container, suffix: "-\(side)p", maxShortSide: side,
                             appliesSizeGuard: true)
        case .mute:
            return VideoPlan(work: .dropAudio, fileExtension: container, suffix: "-muted", appliesSizeGuard: false)
        case .halfSize, .removeBackground:
            throw JobError.notYet("That's for images.")
        }
    }

    init(work: Work, fileExtension: String, suffix: String? = nil, maxShortSide: Int? = nil,
         targetBytes: Int? = nil, appliesSizeGuard: Bool) {
        self.work = work
        self.fileExtension = fileExtension
        self.suffix = suffix
        self.maxShortSide = maxShortSide
        self.targetBytes = targetBytes
        self.appliesSizeGuard = appliesSizeGuard
    }
}

/// Video settings until VMAF auto-tuning picks them per video (CORE.md §7.3).
enum VideoTuning {
    /// Bits per pixel per frame. Screen recordings and most phone clips look good here.   (tune)
    static let h264BitsPerPixel = 0.08
    static let hevcBitsPerPixel = 0.05
    static let minBitrate = 250_000
    static let maxBitrate = 25_000_000
    /// Auto and Compress never encode above this share of the source's bitrate, so they shrink.
    static let maxShareOfSource = 0.7
    /// AAC, CORE.md §7.4.
    static let audioBitrate = 128_000
    /// Room left for the container and bitrate wobble when aiming at a file size.
    static let targetSizeSafety = 0.92
    /// Below this, a frame size looks smeared; drop to a smaller standard size instead.
    static let minBitsPerPixelForSize = 0.03
    static let standardShortSides = [1080, 720, 480, 360]
    /// Compress's sizes: common upload limits (Discord, email, Slack…).
    static let targetSizes = [10_000_000, 25_000_000, 50_000_000, 100_000_000]
    static let resizeSides = [1080, 720, 480]
    static let defaultCustomSize = 25_000_000
    /// GIF (CORE.md §7.4: ~15–20 fps, ~800 px wide).                                       (tune)
    static let gifFrameRate = 15.0
    static let gifMaxSide = 800
    static let gifMaxSeconds = 30.0

    /// A good-looking bitrate for this size and frame rate.
    static func bitrate(width: Int, height: Int, fps: Double, codec: VideoPlan.Codec) -> Int {
        let bitsPerPixel = codec == .h264 ? h264BitsPerPixel : hevcBitsPerPixel
        return clamp(Int(Double(width * height) * max(fps, 1) * bitsPerPixel))
    }

    /// The video bitrate that lands a file of `bytes` for this duration, leaving room for sound.
    static func bitrate(fitting bytes: Int, seconds: Double, hasAudio: Bool) -> Int {
        guard seconds > 0 else { return maxBitrate }
        let total = Double(bytes) * 8 * targetSizeSafety / seconds
        return max(minBitrate, Int(total) - (hasAudio ? audioBitrate : 0))
    }

    /// `width` × `height` scaled so the shorter side is at most `maxShortSide`: never larger, and
    /// even on both sides (H.264 and HEVC need that).
    static func size(width: Int, height: Int, maxShortSide: Int?) -> (width: Int, height: Int) {
        var scale = 1.0
        if let maxShortSide, min(width, height) > maxShortSide {
            scale = Double(maxShortSide) / Double(min(width, height))
        }
        func even(_ value: Double) -> Int { max(2, Int((value / 2).rounded()) * 2) }
        return (even(Double(width) * scale), even(Double(height) * scale))
    }

    /// When `bitrate` is too low for this frame size, the largest standard short side that suits it;
    /// nil when the size is fine as it is.
    static func shortSide(for bitrate: Int, width: Int, height: Int, fps: Double) -> Int? {
        func fits(_ w: Int, _ h: Int) -> Bool {
            Double(bitrate) / (Double(w * h) * max(fps, 1)) >= minBitsPerPixelForSize
        }
        guard !fits(width, height) else { return nil }
        for side in standardShortSides where side < min(width, height) {
            let scaled = size(width: width, height: height, maxShortSide: side)
            if fits(scaled.width, scaled.height) { return side }
        }
        return standardShortSides.last
    }

    private static func clamp(_ bitrate: Int) -> Int { min(max(bitrate, minBitrate), maxBitrate) }
}
