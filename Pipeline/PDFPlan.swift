import Foundation

/// What an action does to a PDF (CORE.md §7b). Portable, so it's tested on Linux too.
struct PDFPlan: Equatable {
    var fileExtension = "pdf"
    var suffix: String
    /// A smaller copy is the point, so it never hands back a bigger one (Rule 3).
    var appliesSizeGuard = true

    static func make(action: Action, option: ActionOption?) throws -> PDFPlan {
        switch action {
        case .auto, .compress:
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
}
