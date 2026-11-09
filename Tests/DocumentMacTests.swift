import AppKit
import PDFKit
import XCTest
@testable import Droptimize

// macOS only: Word → PDF with the built-in reader (CORE.md §7c). Word and Pages aren't on the CI
// machines, so the scripted path is checked by hand on a Mac that has them (HANDOFF.md).
final class DocumentMacTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("DocumentMacTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A Word document written by macOS itself: a heading, `paragraphs` paragraphs, and an appendix
    /// after a page break when `pageBreak` is set. A4 with one-inch margins.
    private func makeWord(_ name: String, paragraphs: Int, pageBreak: Bool = false,
                          type: NSAttributedString.DocumentType = .officeOpenXML) throws -> URL {
        let text = NSMutableAttributedString(string: "Quarterly report\n",
                                             attributes: [.font: NSFont.boldSystemFont(ofSize: 24)])
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12)]
        for index in 0..<paragraphs {
            text.append(NSAttributedString(string: "Paragraph \(index). Droptimize turns this Word document into a PDF "
                                           + "with every word kept as real text, laid out page by page with the margins "
                                           + "the document asks for. ", attributes: body))
            text.append(NSAttributedString(string: "The end of paragraph \(index).\n", attributes: body))
        }
        if pageBreak { text.append(NSAttributedString(string: "\u{0C}Appendix\n", attributes: body)) }
        let data = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [
            .documentType: type,
            .paperSize: NSValue(size: CGSize(width: 595, height: 842)),
            .leftMargin: 72, .rightMargin: 72, .topMargin: 72, .bottomMargin: 72,
        ])
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func testTheBuiltInReaderMakesAPagedPDF() async throws {
        let input = try makeWord("report.docx", paragraphs: 60)
        let outcome = try await DocumentConverter.process(input, action: .auto, option: nil, engines: [.builtIn])
        XCTAssertEqual(outcome.output.lastPathComponent, "report.pdf")
        XCTAssertEqual(outcome.note, "Without Word or Pages, layout may differ")
        let pdf = try XCTUnwrap(PDFDocument(url: outcome.output))
        XCTAssertGreaterThan(pdf.pageCount, 2, "long enough for several pages")
        let size = try XCTUnwrap(pdf.page(at: 0)?.bounds(for: .mediaBox).size)
        let paper = [CGSize(width: 595, height: 842), CGSize(width: 612, height: 792)]
        XCTAssertTrue(paper.contains(size), "A4 or Letter, not \(size)")
        // Lines wrap wherever the page puts them, so compare the words, not the line breaks.
        let text = (pdf.string ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        XCTAssertTrue(text.contains("Quarterly report"), "the text is still text")
        XCTAssertTrue(text.contains("The end of paragraph 59."), "nothing is cut off at the end: …\(text.suffix(80))")
    }

    func testAPageBreakStartsANewPage() async throws {
        let input = try makeWord("memo.docx", paragraphs: 2, pageBreak: true)
        let outcome = try await DocumentConverter.process(input, action: .convert, option: .pdf, engines: [.builtIn])
        let pdf = try XCTUnwrap(PDFDocument(url: outcome.output))
        XCTAssertEqual(pdf.pageCount, 2)
        XCTAssertFalse(pdf.page(at: 0)?.string?.contains("Appendix") ?? true)
        XCTAssertTrue(pdf.page(at: 1)?.string?.contains("Appendix") ?? false)
    }

    func testTheOlderWordFormatToo() async throws {
        let input = try makeWord("letter.doc", paragraphs: 3, type: .docFormat)
        let outcome = try await DocumentConverter.process(input, action: .auto, option: nil, engines: [.builtIn])
        XCTAssertEqual(outcome.output.lastPathComponent, "letter.pdf")
        XCTAssertTrue(PDFDocument(url: outcome.output)?.string?.contains("Quarterly report") ?? false)
    }

    func testNeverOverwritesAnExistingPDF() async throws {
        let input = try makeWord("cv.docx", paragraphs: 2)
        try Data("not mine to replace".utf8).write(to: folder.appendingPathComponent("cv.pdf"))
        let outcome = try await DocumentConverter.process(input, action: .auto, option: nil, engines: [.builtIn])
        XCTAssertEqual(outcome.output.lastPathComponent, "cv-2.pdf")
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("cv.pdf"), encoding: .utf8), "not mine to replace")
    }

    func testFallsBackWhenWordIsMissing() async throws {
        try XCTSkipIf(AppExport.isInstalled(.word), "Word is installed here; this checks the fallback")
        let input = try makeWord("brief.docx", paragraphs: 2)
        let outcome = try await DocumentConverter.process(input, action: .auto, option: nil, engines: [.word, .builtIn])
        XCTAssertEqual(outcome.output.lastPathComponent, "brief.pdf")
        XCTAssertEqual(outcome.note, "Word didn't help: layout may differ")
    }

    func testABrokenDocumentSaysSo() async throws {
        let input = folder.appendingPathComponent("broken.docx")
        try Data("this is not a Word document".utf8).write(to: input)
        do {
            _ = try await DocumentConverter.process(input, action: .auto, option: nil, engines: [.builtIn])
            XCTFail("expected unreadableDocument")
        } catch {
            XCTAssertEqual(error as? JobError, .unreadableDocument)
        }
    }

    func testWordFilesAreRecognised() {
        XCTAssertEqual(MediaKind(url: URL(fileURLWithPath: "/nonexistent/report.docx")), .document)
        XCTAssertEqual(MediaKind(url: URL(fileURLWithPath: "/nonexistent/OLD.DOC")), .document)
    }
}
