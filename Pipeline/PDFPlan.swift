import Foundation

/// What an action does to a PDF (CORE.md §7b). Portable, so it's tested on Linux too.
struct PDFPlan: Equatable {
    var fileExtension = "pdf"
    var suffix: String
    /// Compress to a size: the copy must come out at most this big.
    var targetBytes: Int?
    /// A smaller copy is the point, so it never hands back a bigger one (Rule 3).
    var appliesSizeGuard = true
    /// Convert: each page as an image in this format instead of a smaller PDF.
    var pageFormat: ImageFormat?

    static func make(action: Action, option: ActionOption?) throws -> PDFPlan {
        switch action {
        case .auto, .compress:
            if action == .compress, case .maxBytes(let bytes) = option {
                return PDFPlan(suffix: ByteCount.suffix(bytes), targetBytes: bytes)
            }
            return PDFPlan(suffix: "-min")
        case .convert:
            var format = PDFTuning.pageFormats[0]
            if case .format(let chosen) = option, PDFTuning.pageFormats.contains(chosen) { format = chosen }
            return PDFPlan(fileExtension: format.fileExtension, suffix: "", appliesSizeGuard: false, pageFormat: format)
        case .halfSize, .removeBackground:
            throw JobError.notYet("That's for images.")
        case .resize, .mute:
            throw JobError.notYet("That's for videos.")
        }
    }
}

/// PDF settings (CORE.md §7b, §7c).
enum PDFTuning {
    /// PDF → images: what Convert offers, the first being what Convert alone makes. PNG keeps text
    /// sharp; JPG is smaller for photo pages.
    static let pageFormats: [ImageFormat] = [.png, .jpeg]
    /// Page images at twice the page's point size: sharp on a Retina screen (A4 → 1191 × 1684).  (tune)
    static let pageImagePPI = 144.0
    /// Never more pixels than this on a page image's longer side (huge posters).
    static let maxPageImageSide = 8000

    /// Images → PDF: each picture becomes a page shaped like it, at most A4's long side (842 pt)
    /// and never bigger than one point per pixel; pictures keep at most 300 ppi on that page. (tune)
    static let maxPageSide = 842.0
    static let maxImagePPI = 300.0
    /// Photos are stored in the PDF as JPEG at this quality; graphics and screenshots stay lossless.
    static let photoQuality = 0.95

    /// The page, in points, for a picture of `width` × `height` pixels.
    static func pageSize(pixelWidth width: Int, pixelHeight height: Int) -> (width: Double, height: Double) {
        let scale = min(1, maxPageSide / Double(max(width, height, 1)))
        return (Double(width) * scale, Double(height) * scale)
    }

    /// How much to shrink a picture before it goes on its page (1: not at all).
    static func pixelScale(pixelWidth width: Int, pixelHeight height: Int) -> Double {
        let page = pageSize(pixelWidth: width, pixelHeight: height)
        let maxPixels = max(page.width, page.height) / 72 * maxImagePPI
        return min(1, maxPixels / Double(max(width, height, 1)))
    }

    /// A page image's size in pixels for a page of `width` × `height` points.
    static func pageImageSize(pointWidth width: Double, pointHeight height: Double) -> (width: Int, height: Int) {
        var scale = pageImagePPI / 72
        scale = min(scale, Double(maxPageImageSide) / max(width, height, 1))
        return (max(1, Int((width * scale).rounded())), max(1, Int((height * scale).rounded())))
    }

    /// A compressed copy must keep at least this share of the original's text, or it's refused
    /// (it would mean text had been turned into pictures).
    static let textKept = 0.98

    /// Compress's sizes: what upload forms (applications, visas, portals) and email commonly allow.
    static let targetSizes = [200_000, 500_000, 1_000_000, 2_000_000, 5_000_000]
    static let defaultCustomSize = 1_000_000

    /// How the pictures in a PDF are stored: scaled down to at most `pixelsPerInch` on the page,
    /// then saved as JPEG at `quality` (0…1).
    struct Step: Hashable {
        var pixelsPerInch: Int
        var quality: Double
    }

    /// Apple's own "optimize images for screen" (measured: 144 ppi, JPEG at about 0.72): what Auto does.
    static let screen = Step(pixelsPerInch: 144, quality: 0.72)

    /// Compress to a size tries these, best first, and keeps the first that fits. Each one is
    /// smaller than the one before. Above `screen`, sharper for printing and zooming; below it,
    /// for tight limits.                                                                    (tune)
    static let ladder: [Step] = [
        Step(pixelsPerInch: 300, quality: 0.85),
        Step(pixelsPerInch: 250, quality: 0.8),
        Step(pixelsPerInch: 200, quality: 0.78),
        Step(pixelsPerInch: 170, quality: 0.75),
        screen,
        Step(pixelsPerInch: 144, quality: 0.6),
        Step(pixelsPerInch: 120, quality: 0.58),
        Step(pixelsPerInch: 100, quality: 0.55),
        Step(pixelsPerInch: 85, quality: 0.5),
        Step(pixelsPerInch: 72, quality: 0.45),
        Step(pixelsPerInch: 72, quality: 0.3),
    ]

    /// The best step whose copy fits, given a way to make one: a binary search over the ladder
    /// (bigger to smaller), so about four tries instead of eleven. nil when even the last is too big.
    static func bestFit(under target: Int, size: (Step) throws -> Int) rethrows -> Step? {
        var low = 0, high = ladder.count - 1
        var best: Int?
        while low <= high {
            let middle = (low + high) / 2
            if try size(ladder[middle]) <= target {
                best = middle
                high = middle - 1
            } else {
                low = middle + 1
            }
        }
        return best.map { ladder[$0] }
    }
}
