import Foundation

/// What an action does to a PDF (CORE.md §7b). Portable, so it's tested on Linux too.
struct PDFPlan: Equatable {
    var fileExtension = "pdf"
    var suffix: String
    /// Compress to a size: the copy must come out at most this big.
    var targetBytes: Int?
    /// A smaller copy is the point, so it never hands back a bigger one (Rule 3).
    var appliesSizeGuard = true

    static func make(action: Action, option: ActionOption?) throws -> PDFPlan {
        switch action {
        case .auto, .compress:
            if action == .compress, case .maxBytes(let bytes) = option {
                return PDFPlan(suffix: ByteCount.suffix(bytes), targetBytes: bytes)
            }
            return PDFPlan(suffix: "-min")
        case .convert, .halfSize, .removeBackground:
            throw JobError.notYet("That's for images.")
        case .resize, .mute:
            throw JobError.notYet("That's for videos.")
        }
    }
}

/// PDF settings (CORE.md §7b).
enum PDFTuning {
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
