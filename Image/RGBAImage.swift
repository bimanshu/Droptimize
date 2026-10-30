import Foundation

/// Decoded pixels, ready to encode: 8-bit RGBA in sRGB, orientation applied, alpha not
/// premultiplied, rows packed with no padding (CORE.md §6.2). Fully transparent pixels are
/// stored as 0,0,0,0, since their color can't be seen.
///
/// Portable (Foundation only), so the encoders can be tested on Linux too.
struct RGBAImage {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(width > 0 && height > 0 && pixels.count == width * height * 4, "pixel buffer doesn't match the size")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    var pixelCount: Int { width * height }

    /// True when no pixel has any transparency.
    var isOpaque: Bool {
        pixels.withUnsafeBufferPointer { p in
            var index = 3
            while index < p.count {
                if p[index] != 255 { return false }
                index += 4
            }
            return true
        }
    }

    /// The number of distinct colors (RGBA), counting only up to `limit`: anything over it
    /// returns `limit + 1`. Looks at every `step`th pixel, so it can be an estimate.
    func distinctColorCount(limit: Int, step: Int = 1) -> Int {
        var seen = Set<UInt32>(minimumCapacity: min(limit + 1, 1 << 16))
        return pixels.withUnsafeBufferPointer { p in
            var index = 0
            let stride = max(1, step) * 4
            while index < p.count {
                seen.insert(Self.pack(p, at: index))
                if seen.count > limit { return limit + 1 }
                index += stride
            }
            return seen.count
        }
    }

    /// Flat graphics (screenshots, UI, illustrations, anything with transparency) usually
    /// compress better losslessly; photos don't. A rough check until Auto classification
    /// (CORE.md §6.5, Phase 1 step 2).
    var looksLikeGraphic: Bool {
        !isOpaque || distinctColorCount(limit: EncoderTuning.graphicColorLimit,
                                        step: max(1, pixelCount / EncoderTuning.colorSampleSize))
            <= EncoderTuning.graphicColorLimit
    }

    /// The color at byte offset `index`, packed as 0xRRGGBBAA.
    @inline(__always)
    static func pack(_ p: UnsafeBufferPointer<UInt8>, at index: Int) -> UInt32 {
        UInt32(p[index]) << 24 | UInt32(p[index + 1]) << 16 | UInt32(p[index + 2]) << 8 | UInt32(p[index + 3])
    }
}

/// Encoder settings, until SSIMULACRA 2 auto-tuning picks them per image (CORE.md §6.4).
enum EncoderTuning {
    /// libwebp quality, 0–100.                                                   (tune)
    static let webpQuality: Float = 80
    /// libwebp effort, 0 (fast) – 6 (smallest).                                  (tune)
    static let webpMethod: Int32 = 4
    /// libwebp lossless effort, 0–9.                                              (tune)
    static let webpLosslessLevel: Int32 = 6
    /// ImageIO JPEG quality, 0–1. Stand-in until jpegli (CORE.md §6.3).          (tune)
    static let jpegQuality: Double = 0.8
    /// ImageIO HEIC quality, 0–1.                                                 (tune)
    static let heicQuality: Double = 0.75
    /// libavif quality, 0–100. AVIF at 60 looks about like WebP at 80.             (tune)
    static let avifQuality = 60
    /// libaom speed, 0 (slowest, smallest) – 10. CORE.md §6.3 suggests ~6.         (tune)
    static let avifSpeed = 6
    /// Faster speed while searching for a target size (each step is an encode).
    static let avifSearchSpeed = 8
    /// With this many distinct colors or fewer, an image is treated as a graphic.  (tune)
    static let graphicColorLimit = 4096
    /// How many pixels the color count looks at.
    static let colorSampleSize = 1_000_000
    /// Above this many pixels, the clipboard gets the file but no picture (building one is slow).
    static let clipboardImagePixelLimit = 30_000_000

    // Compress to a target size
    /// Quality ranges searched for the best fit (format-native units).
    static let jpegQualities: ClosedRange<Double> = 0.1...0.95
    static let heicQualities: ClosedRange<Double> = 0.1...0.9
    static let webpQualities: ClosedRange<Double> = 5...95
    static let avifQualities: ClosedRange<Double> = 10...90
    /// Bisection steps per search (each one is an encode).                         (tune)
    static let searchSteps = 6
    /// When the lowest quality is still too big, shrink by this much and try again.  (tune)
    static let fitScaleStep = 0.8
    /// Never shrink an image below this many pixels on its short side to hit a size.
    static let minimumFitSide = 64
    /// Custom sizes users can type.
    static let customSizeRange = 10_000...500_000_000
}
