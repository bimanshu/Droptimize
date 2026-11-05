import Foundation
import PDFKit

/// Makes a smaller copy of a PDF next to it (CORE.md §7b), with Apple's own PDF engine: no new
/// dependency. Synchronous: call it off the main thread.
enum PDFOptimizer {
    /// Apple's image recompression (Preview's "Optimize images for screen" and "Save images as
    /// JPEG"): pictures bigger than a screen needs are scaled down and stored as JPEG. Text, vector
    /// art, links, bookmarks and form fields stay as they are.
    static let compression: [PDFDocumentWriteOption: Any] = [
        .optimizeImagesForScreenOption: true,
        .saveImagesAsJPEGOption: true,
    ]

    static func process(_ input: URL, action: Action, option: ActionOption?) throws -> FileOutcome {
        let inputBytes = fileSize(input) ?? 0
        let plan = try PDFPlan.make(action: action, option: option)
        guard let document = PDFDocument(url: input), document.pageCount > 0 else { throw JobError.unreadablePDF }
        // Rewriting would drop the encryption or break the signature: leave those alone.
        if document.isEncrypted || document.isLocked { throw JobError.protectedPDF }
        if isSigned(document) { throw JobError.signedPDF }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("droptimize-\(UUID().uuidString)").appendingPathExtension(plan.fileExtension)
        defer { try? FileManager.default.removeItem(at: temp) }
        guard document.write(to: temp, withOptions: compression) else { throw JobError.cantSave }
        guard let copy = PDFDocument(url: temp), keepsEverything(copy, of: document) else { throw JobError.cantSave }

        let outputBytes = fileSize(temp) ?? 0
        if plan.appliesSizeGuard, !SizeGuard.accepts(inputBytes: inputBytes, outputBytes: outputBytes) {
            throw JobError.alreadySmallest
        }
        let output = try OutputWriter.move(temp, for: input, fileExtension: plan.fileExtension, suffix: plan.suffix)
        return FileOutcome(input: input, output: output, inputBytes: inputBytes, outputBytes: outputBytes,
                           picture: nil, note: nil)
    }

    /// The copy has every page, each the same size, and all the text (so nothing was turned into a
    /// picture of text).
    static func keepsEverything(_ copy: PDFDocument, of original: PDFDocument) -> Bool {
        guard copy.pageCount == original.pageCount else { return false }
        for index in 0..<original.pageCount {
            guard let before = original.page(at: index), let after = copy.page(at: index),
                  before.bounds(for: .mediaBox) == after.bounds(for: .mediaBox)
            else { return false }
        }
        let text = letters(in: original), kept = letters(in: copy)
        return Double(kept) >= Double(text) * PDFTuning.textKept
    }

    /// Signed: the catalog says signatures exist (AcroForm SigFlags bit 1), or a signature field
    /// holds one. An empty signature field doesn't count: there's nothing to break yet.
    static func isSigned(_ document: PDFDocument) -> Bool {
        if let catalog = document.documentRef?.catalog {
            var form: CGPDFDictionaryRef?
            var flags: CGPDFInteger = 0
            if CGPDFDictionaryGetDictionary(catalog, "AcroForm", &form), let form,
               CGPDFDictionaryGetInteger(form, "SigFlags", &flags), flags & 1 != 0 {
                return true
            }
        }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if page.annotations.contains(where: { $0.widgetFieldType == .signature && $0.value(forAnnotationKey: .widgetValue) != nil }) {
                return true
            }
        }
        return false
    }

    private static func letters(in document: PDFDocument) -> Int {
        (document.string ?? "").unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
    }

    private static func fileSize(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
    }
}
