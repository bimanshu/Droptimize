import AppKit
import Foundation
import PDFKit

/// Word documents → PDF (CORE.md §7c): with Word or Pages when one is installed (the layout exactly
/// as written), otherwise with macOS's own Word reader. A try that fails falls through to the next,
/// so a drop always gets a PDF, and the card says when the layout may differ.
enum DocumentConverter {
    /// `engines` overrides the order (tests); normally it comes from what's installed.
    static func process(_ input: URL, action: Action, option: ActionOption?,
                        engines: [DocumentEngine]? = nil) async throws -> FileOutcome {
        let plan = try DocumentPlan.make(action: action, option: option)
        let inputBytes = fileSize(input) ?? 0
        let order = engines ?? DocumentEngine.order(wordInstalled: AppExport.isInstalled(.word),
                                                    pagesInstalled: AppExport.isInstalled(.pages))
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("droptimize-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var tried: [DocumentEngine] = []
        var refused: DocumentEngine?
        for engine in order {
            try Task.checkCancellation()
            tried.append(engine)
            do {
                let output: URL
                if engine == .builtIn {
                    let temp = scratch.appendingPathComponent("document").appendingPathExtension(plan.fileExtension)
                    try BuiltInDocumentRenderer.render(input, to: temp)
                    try check(temp)
                    output = try OutputWriter.move(temp, for: input, fileExtension: plan.fileExtension, suffix: nil)
                } else {
                    // Word and Pages are sandboxed: they write where the PDF will stay, next to the original.
                    let target = OutputNaming.url(for: input, fileExtension: plan.fileExtension, suffix: nil,
                                                  in: OutputWriter.folder(for: input, fallback: OutputWriter.defaultFallback))
                    do {
                        try await AppExport.convert(input, to: target, with: engine)
                        try check(target)
                    } catch {
                        try? FileManager.default.removeItem(at: target)       // a fresh name: only ever a half-written PDF
                        throw error
                    }
                    output = target
                }
                return FileOutcome(input: input, output: output, inputBytes: inputBytes, outputBytes: fileSize(output) ?? 0,
                                   picture: nil,
                                   note: engine == .builtIn ? DocumentEngine.builtInNote(tried: tried, refused: refused) : nil)
            } catch is CancellationError {
                throw CancellationError()
            } catch AppExport.Failure.notAllowed {
                refused = refused ?? engine
            } catch {
                if engine == .builtIn { throw (error as? JobError) ?? JobError.unreadableDocument }
            }
        }
        throw JobError.unreadableDocument
    }

    /// A PDF with at least one page, or it doesn't count.
    private static func check(_ url: URL) throws {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { throw JobError.cantSave }
    }

    private static func fileSize(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
    }
}

// MARK: Word and Pages

/// Word or Pages, scripted (JavaScript for Automation through `osascript`, so it never blocks the
/// main thread): opened out of sight, the document saved as PDF, closed again, and the app quit if
/// Droptimize started it. A document the person already had open is never closed. The first time,
/// macOS asks whether Droptimize may control the app (`NSAppleEventsUsageDescription`).
enum AppExport {
    enum Failure: Error, Equatable {
        case notInstalled
        /// The person said no to "Droptimize wants to control …" (Privacy & Security → Automation).
        case notAllowed
        case timedOut
        case failed(String)
    }

    static func isInstalled(_ engine: DocumentEngine) -> Bool {
        guard let identifier = engine.bundleIdentifier else { return true }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) != nil
    }

    static func convert(_ input: URL, to output: URL, with engine: DocumentEngine) async throws {
        guard let identifier = engine.bundleIdentifier,
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        else { throw Failure.notInstalled }
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty
        if !wasRunning {
            // Hidden, so its windows never show (Rule 1).
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.hides = true
            configuration.addsToRecentItems = false
            _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        }
        try await run(engine == .word ? wordScript : pagesScript,
                      arguments: [input.path, output.path, wasRunning ? "0" : "1"], timeout: DocumentTuning.appTimeout)
        guard FileManager.default.fileExists(atPath: output.path) else { throw Failure.failed("no PDF was written") }
    }

    /// argv: the document, the PDF to write, "1" to quit Word afterwards (Droptimize started it).
    private static let wordScript = """
        function run(argv) {
          var input = argv[0], output = argv[1], quitAfter = argv[2] === "1";
          var word = Application("com.microsoft.Word");
          var name = input.split("/").pop();
          var before = word.documents().length;
          word.open(Path(input));
          var doc;
          try { doc = word.documents.byName(name); doc.name(); } catch (e) { doc = word.activeDocument; }
          doc.saveAs({ fileName: output, fileFormat: "format PDF" });
          if (word.documents().length > before) doc.close({ saving: "no" });
          if (quitAfter && word.documents().length === 0) word.quit({ saving: "no" });
        }
        """

    /// argv as for Word. Pages imports a Word file as a new, untitled document: exported, then closed unsaved.
    private static let pagesScript = """
        function run(argv) {
          var input = argv[0], output = argv[1], quitAfter = argv[2] === "1";
          var pages = Application("com.apple.iWork.Pages");
          var before = pages.documents().length;
          var doc = pages.open(Path(input));
          pages.export(doc, { to: Path(output), as: "PDF" });
          if (pages.documents().length > before) pages.close(doc, { saving: "no" });
          if (quitAfter && pages.documents().length === 0) pages.quit();
        }
        """

    /// Runs a JavaScript for Automation script with `osascript`, off the main thread, stopping it
    /// after `timeout` seconds or when the task is cancelled.
    private static func run(_ script: String, arguments: [String], timeout: Double) async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("droptimize-\(UUID().uuidString).js")
        try script.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", file.path] + arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        let box = Unchecked(process)

        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                let once = OneShot()
                box.value.terminationHandler = { finished in
                    if once.claim() { continuation.resume(returning: finished.terminationStatus) }
                }
                do {
                    try box.value.run()
                } catch {
                    if once.claim() { continuation.resume(throwing: Failure.failed("osascript didn't start")) }
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if once.claim() {
                        box.value.terminate()
                        continuation.resume(throwing: Failure.timedOut)
                    }
                }
            }
        } onCancel: {
            box.value.terminate()
        }
        try Task.checkCancellation()
        guard status == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            // -1743: not allowed to send Apple events to the app (the person said no, or hasn't been asked).
            if message.contains("-1743") || message.localizedCaseInsensitiveContains("not authorized") {
                throw Failure.notAllowed
            }
            throw Failure.failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

/// True the first time `claim()` is called, from any thread; false after that.
private final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

// MARK: The built-in reader

/// macOS's own Word reader (the one TextEdit uses) laid out page by page with TextKit: the
/// document's paper size and margins when it gives them, the page breaks it has (TextKit starts a
/// new page at each), its fonts, lists, tables and pictures as far as the reader brings them in.
/// Headers, footers, text boxes and columns aren't read.
enum BuiltInDocumentRenderer {
    static func render(_ input: URL, to output: URL) throws {
        let type: NSAttributedString.DocumentType = input.pathExtension.lowercased() == "doc" ? .docFormat : .officeOpenXML
        var attributes: NSDictionary?
        let text: NSAttributedString
        do {
            text = try NSAttributedString(url: input, options: [.documentType: type], documentAttributes: &attributes)
        } catch {
            throw JobError.unreadableDocument
        }
        let details = attributes as? [NSAttributedString.DocumentAttributeKey: Any] ?? [:]
        let fallback = Locale.current.measurementSystem == .us ? DocumentTuning.letter : DocumentTuning.a4
        var paper = (details[.paperSize] as? NSValue)?.sizeValue ?? CGSize(width: fallback.width, height: fallback.height)
        func margin(_ key: NSAttributedString.DocumentAttributeKey) -> CGFloat {
            CGFloat((details[key] as? NSNumber)?.doubleValue ?? DocumentTuning.defaultMargin)
        }
        var (left, right, top, bottom) = (margin(.leftMargin), margin(.rightMargin), margin(.topMargin), margin(.bottomMargin))
        if paper.width < left + right + 72 || paper.height < top + bottom + 72 {       // nonsense from the file
            paper = CGSize(width: fallback.width, height: fallback.height)
            (left, right, top, bottom) = (72, 72, 72, 72)
        }

        // One text container per page, until the text runs out.
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let area = CGSize(width: paper.width - left - right, height: paper.height - top - bottom)
        while layout.textContainers.count < DocumentTuning.maxPages {
            let container = NSTextContainer(size: area)
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            let range = layout.glyphRange(for: container)
            if NSMaxRange(range) >= layout.numberOfGlyphs { break }
            if range.length == 0, layout.textContainers.count > 1 {
                layout.removeTextContainer(at: layout.textContainers.count - 1)   // something taller than a page
                break
            }
        }

        var media = CGRect(origin: .zero, size: paper)
        let title = (details[.title] as? String) ?? input.deletingPathExtension().lastPathComponent
        let info: [CFString: Any] = [kCGPDFContextCreator: "Droptimize", kCGPDFContextTitle: title]
        guard let context = CGContext(output as CFURL, mediaBox: &media, info as CFDictionary) else { throw JobError.cantSave }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        for container in layout.textContainers {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: paper.height)                        // TextKit draws top-down
            context.scaleBy(x: 1, y: -1)
            let range = layout.glyphRange(for: container)
            let origin = CGPoint(x: left, y: top)
            layout.drawBackground(forGlyphRange: range, at: origin)
            layout.drawGlyphs(forGlyphRange: range, at: origin)
            context.restoreGState()
            context.endPDFPage()
        }
        NSGraphicsContext.restoreGraphicsState()
        context.closePDF()
    }
}
