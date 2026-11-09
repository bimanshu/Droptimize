import Foundation

/// What an action does to a Word document: it becomes a PDF (CORE.md §7c). Portable, so it's
/// tested on Linux too.
struct DocumentPlan: Equatable {
    var fileExtension = "pdf"

    /// The extensions Droptimize treats as Word documents.
    static let extensions: Set<String> = ["docx", "doc"]

    static func make(action: Action, option: ActionOption?) throws -> DocumentPlan {
        switch action {
        case .auto, .convert:
            return DocumentPlan()
        case .compress:
            throw JobError.notYet("Word documents become PDFs: drop on Convert.")
        case .halfSize, .removeBackground:
            throw JobError.notYet("That's for images.")
        case .resize, .mute:
            throw JobError.notYet("That's for videos.")
        }
    }
}

/// What makes the PDF, best first: Word itself (the layout exactly as the author saw it), then
/// Pages (very close), then macOS's built-in Word reader (fine for simple documents; headers,
/// footers, text boxes and exact page breaks can differ). The owner's choice, 2026-11-09.
enum DocumentEngine: Equatable {
    case word, pages, builtIn

    var bundleIdentifier: String? {
        switch self {
        case .word: return "com.microsoft.Word"
        case .pages: return "com.apple.iWork.Pages"
        case .builtIn: return nil
        }
    }

    var appName: String {
        switch self {
        case .word: return "Word"
        case .pages: return "Pages"
        case .builtIn: return "macOS"
        }
    }

    /// The engines to try, in order, given which apps are installed. The built-in one is always last.
    static func order(wordInstalled: Bool, pagesInstalled: Bool) -> [DocumentEngine] {
        (wordInstalled ? [.word] : []) + (pagesInstalled ? [.pages] : []) + [.builtIn]
    }

    /// What the done card says when the built-in reader made the PDF: the layout may differ, and why.
    static func builtInNote(tried: [DocumentEngine], refused: DocumentEngine?) -> String {
        if let refused { return "Allow \(refused.appName) in Settings for an exact copy" }
        if let app = tried.first(where: { $0 != .builtIn }) { return "\(app.appName) didn't help: layout may differ" }
        return "Without Word or Pages, layout may differ"
    }
}

/// Word → PDF settings (CORE.md §7c).
enum DocumentTuning {
    /// How long Word or Pages may take to open, convert and close one document (a cold start of
    /// Word alone can take 10 s).                                                       (tune)
    static let appTimeout: Double = 90
    /// The built-in reader: margins when the document doesn't say (one inch), and a page limit.
    static let defaultMargin = 72.0
    static let maxPages = 2000
    /// Paper when the document doesn't say: Letter in the US, A4 elsewhere.
    static let a4 = (width: 595.0, height: 842.0)
    static let letter = (width: 612.0, height: 792.0)
}
