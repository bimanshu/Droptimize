import AppKit
import ImageIO
import PDFKit
import XCTest
@testable import Droptimize

// macOS only: our own Word reader laid out on PDF pages (CORE.md §7c). The document is built like
// a real one people send — a logo on the cover, a page break, a heading, 1.5-spaced justified text,
// a numbered list, a bordered table, a header logo and "Page X of Y" in the footer — without any
// personal content, and the PDF is checked by its text and by looking at its pixels.
final class WordLayoutMacTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("WordLayoutMacTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// The look-alike report as a PDF, made by the built-in reader.
    private func convertReport() async throws -> URL {
        let input = folder.appendingPathComponent("report.docx")
        try Self.report().write(to: input)
        return try await DocumentConverter.process(input, action: .auto, option: nil, engines: [.builtIn]).output
    }

    func testAReportKeepsItsPagesAndText() async throws {
        let output = try await convertReport()
        keepSample(output, as: "lookalike-report.pdf")
        let pdf = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(pdf.pageCount, 2, "the cover, then a page break")
        let paper = try XCTUnwrap(pdf.page(at: 0)?.bounds(for: .mediaBox).size)
        XCTAssertEqual(paper.width, 595.3, accuracy: 0.01, "A4, as the file says")
        XCTAssertEqual(paper.height, 841.9, accuracy: 0.01)

        let cover = Self.words(pdf.page(at: 0)?.string)
        let content = Self.words(pdf.page(at: 1)?.string)
        XCTAssertTrue(cover.contains("Quarterly Coping Report"), cover)
        XCTAssertTrue(cover.contains("Page 1 of 2"), "page numbers in the footer: \(cover)")
        XCTAssertFalse(cover.contains("Introduction"), "the heading is after the page break")
        XCTAssertTrue(content.contains("Introduction"), content)
        XCTAssertTrue(content.contains("1. First point") && content.contains("2. Second point"), "numbered: \(content)")
        XCTAssertTrue(content.contains("Coping strategy"), "the table's text: \(content)")
        XCTAssertTrue(content.contains("Page 2 of 2"), content)
    }

    func testAReportKeepsItsPictures() async throws {
        let output = try await convertReport()
        // The cover logo: red above blue, the full width of the text, at the top of the page.
        let scale: CGFloat = 2
        let first = Pixels(output, page: 0, scale: scale)
        XCTAssertTrue(first.isColor(x: 297, y: 108, red: true), "the logo's red top: \(first.describe(x: 297, y: 108))")
        XCTAssertTrue(first.isColor(x: 297, y: 178, blue: true), "the logo's blue bottom, so not upside down: \(first.describe(x: 297, y: 178))")
        XCTAssertTrue(first.isColor(x: 80, y: 120, red: true), "6.5 inches wide: \(first.describe(x: 80, y: 120))")

        // The header's small green logo on every page.
        let second = Pixels(output, page: 1, scale: scale)
        for (page, pixels) in [(1, first), (2, second)] {
            XCTAssertTrue(pixels.isColor(x: 99, y: 53, green: true), "page \(page)'s header logo: \(pixels.describe(x: 99, y: 53))")
        }

        // The stamp placed on the page behind the text, at 400, 700.
        XCTAssertTrue(second.isColor(x: 450, y: 725, red: true, blue: true), "the placed picture: \(second.describe(x: 450, y: 725))")
    }

    func testAReportKeepsItsTableBorders() async throws {
        let output = try await convertReport()
        // The table's left edge: a long unbroken line down the page, where the text has none.
        let scale: CGFloat = 2
        let edge = Pixels(output, page: 1, scale: scale).longestDarkRun(columns: 176...180)
        XCTAssertGreaterThan(edge, 60 * scale, "the table's border is drawn")
    }

    /// The demo document in docs/samples (python-docx's own styles: theme fonts, a title with a rule,
    /// a styled table, a chart picture, page numbers, a page break).
    func testTheDemoDocument() async throws {
        let demo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/samples/droptimize-demo.docx")
        let input = folder.appendingPathComponent("demo.docx")
        try FileManager.default.copyItem(at: demo, to: input)
        let outcome = try await DocumentConverter.process(input, action: .auto, option: nil, engines: [.builtIn])
        let pdf = try XCTUnwrap(PDFDocument(url: outcome.output))
        // Two pages in Word; Calibri isn't on a Mac, and its stand-in is a little wider.
        XCTAssertTrue((2...3).contains(pdf.pageCount), "the summary, then the appendix: \(pdf.pageCount) pages")
        let last = Self.words(pdf.page(at: pdf.pageCount - 1)?.string)
        XCTAssertTrue(last.contains("Appendix: how the PDF is made"), "the appendix starts a page: \(last)")
        XCTAssertTrue(last.contains("Page \(pdf.pageCount) of \(pdf.pageCount)"), last)
        let text = Self.words(pdf.string)
        for words in ["Launch Plan: Droptimize for Mac", "Why it matters", "Results so far", "Drop it. Done."] {
            XCTAssertTrue(text.contains(words), "\(words): \(text)")
        }
        XCTAssertEqual(Self.pictures(in: outcome.output), 1, "the chart")
        keepSample(outcome.output, as: "demo.pdf")
    }

    /// CI keeps the PDFs these tests make (TEST_RUNNER_WORD_SAMPLES in the workflow), to look at.
    private func keepSample(_ url: URL, as name: String) {
        guard let folder = ProcessInfo.processInfo.environment["WORD_SAMPLES"], !folder.isEmpty else { return }
        let target = URL(fileURLWithPath: folder).appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.copyItem(at: url, to: target)
    }

    /// How many pictures the PDF's pages draw.
    private static func pictures(in url: URL) -> Int {
        guard let document = CGPDFDocument(url as CFURL), document.numberOfPages > 0 else { return 0 }
        var count = 0
        for number in 1...document.numberOfPages {
            guard let page = document.page(at: number), let dictionary = page.dictionary else { continue }
            var resources: CGPDFDictionaryRef?, objects: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources,
                  CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects
            else { continue }
            count += CGPDFDictionaryGetCount(objects)
        }
        return count
    }

    // MARK: The document

    private static func words(_ text: String?) -> String {
        (text ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static let namespaces = """
        xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
        xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" \
        xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
        xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"
        """

    private static func picture(_ id: String, cx: Int, cy: Int) -> String {
        """
        <w:r><w:drawing><wp:inline><wp:extent cx="\(cx)" cy="\(cy)"/><wp:docPr id="1" name="Picture"/>
        <a:graphic><a:graphicData><pic:pic><pic:blipFill><a:blip r:embed="\(id)"/></pic:blipFill></pic:pic>
        </a:graphicData></a:graphic></wp:inline></w:drawing></w:r>
        """
    }

    private static func text(_ string: String, bold: Bool = false, size: Int? = nil) -> String {
        let props = (bold ? "<w:b/>" : "") + (size.map { "<w:sz w:val=\"\($0)\"/>" } ?? "")
        return "<w:r>\(props.isEmpty ? "" : "<w:rPr>\(props)</w:rPr>")<w:t xml:space=\"preserve\">\(string)</w:t></w:r>"
    }

    private static func report() throws -> Data {
        let styles = """
            <w:styles \(namespaces)><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>
            <w:sz w:val="24"/></w:rPr></w:rPrDefault></w:docDefaults>
            <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:pPr><w:spacing w:after="160" w:line="360" w:lineRule="auto"/>
            <w:jc w:val="both"/></w:pPr></w:style>
            <w:style w:type="paragraph" w:styleId="Header"><w:basedOn w:val="Normal"/><w:pPr><w:tabs><w:tab w:val="center" w:pos="4680"/>
            <w:tab w:val="right" w:pos="9360"/></w:tabs><w:spacing w:after="0" w:line="240" w:lineRule="auto"/><w:jc w:val="left"/></w:pPr></w:style>
            <w:style w:type="paragraph" w:styleId="Footer"><w:basedOn w:val="Header"/></w:style>
            <w:style w:type="paragraph" w:styleId="Heading1"><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/>
            <w:spacing w:before="240" w:after="120"/><w:jc w:val="left"/></w:pPr><w:rPr><w:b/><w:sz w:val="28"/></w:rPr></w:style>
            </w:styles>
            """
        let numbering = """
            <w:numbering \(namespaces)><w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/>
            <w:lvlText w:val="%1."/><w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl></w:abstractNum>
            <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num></w:numbering>
            """
        let centered = "<w:pPr><w:jc w:val=\"center\"/><w:spacing w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr>"
        func item(_ string: String) -> String {
            "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr></w:pPr>\(text(string))</w:p>"
        }
        func cell(_ string: String, bold: Bool = false) -> String {
            "<w:tc><w:tcPr><w:tcW w:w=\"1600\" w:type=\"dxa\"/><w:vAlign w:val=\"center\"/></w:tcPr><w:p>\(text(string, bold: bold))</w:p></w:tc>"
        }
        let table = """
            <w:tbl><w:tblPr><w:jc w:val="center"/><w:tblCellSpacing w:w="15" w:type="dxa"/><w:tblBorders>
            <w:top w:val="single" w:sz="4"/><w:left w:val="single" w:sz="4"/><w:bottom w:val="single" w:sz="4"/>
            <w:right w:val="single" w:sz="4"/><w:insideH w:val="single" w:sz="4"/><w:insideV w:val="single" w:sz="4"/></w:tblBorders>
            <w:tblCellMar><w:top w:w="15" w:type="dxa"/><w:left w:w="15" w:type="dxa"/><w:bottom w:w="15" w:type="dxa"/>
            <w:right w:w="15" w:type="dxa"/></w:tblCellMar></w:tblPr>
            <w:tblGrid><w:gridCol w:w="1600"/><w:gridCol w:w="1600"/><w:gridCol w:w="1600"/></w:tblGrid>
            <w:tr>\(cell("Participant", bold: true))\(cell("Challenge", bold: true))\(cell("Coping strategy", bold: true))</w:tr>
            <w:tr>\(cell("One"))\(cell("Money"))\(cell("A budget"))</w:tr>
            <w:tr>\(cell("Two"))\(cell("Friends"))\(cell("Talking"))</w:tr>
            <w:tr>\(cell("Three"))\(cell("Exams"))\(cell("Practice"))</w:tr>
            </w:tbl>
            """
        let stamp = """
            <w:p><w:r><w:drawing><wp:anchor behindDoc="1"><wp:positionH relativeFrom="page"><wp:posOffset>5080000</wp:posOffset></wp:positionH>
            <wp:positionV relativeFrom="page"><wp:posOffset>8890000</wp:posOffset></wp:positionV><wp:extent cx="1270000" cy="635000"/>
            <wp:wrapNone/><a:graphic><a:graphicData><pic:pic><pic:blipFill><a:blip r:embed="rId12"/></pic:blipFill></pic:pic>
            </a:graphicData></a:graphic></wp:anchor></w:drawing></w:r></w:p>
            """
        let body = """
            <w:p>\(centered)\(picture("rId10", cx: 5_943_600, cy: 1_741_805))</w:p>
            <w:p>\(centered)\(text("Quarterly Coping Report", bold: true, size: 32))</w:p>
            <w:p>\(centered)\(text("Prepared for the layout tests"))</w:p>
            <w:p><w:r><w:br w:type="page"/></w:r></w:p>
            <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>\(text("Introduction"))</w:p>
            <w:p>\(text("Coping skills are the thoughts and habits people use to handle stress. This short report keeps "
                       + "its pictures, its headings, its spacing and its table when it becomes a PDF."))</w:p>
            \(item("First point"))\(item("Second point"))
            <w:p>\(text("Notes", bold: true))</w:p>
            \(table)
            \(stamp)
            <w:sectPr><w:headerReference w:type="default" r:id="rId20"/><w:footerReference w:type="default" r:id="rId21"/>
            <w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1273" w:bottom="1440" w:left="1273" w:header="708" w:footer="708"/></w:sectPr>
            """
        let document = "<w:document \(namespaces)><w:body>\(body)</w:body></w:document>"
        let header = "<w:hdr \(namespaces)><w:p><w:pPr><w:pStyle w:val=\"Header\"/></w:pPr>\(picture("rId1", cx: 914_400, cy: 457_200))</w:p></w:hdr>"
        let footer = """
            <w:ftr \(namespaces)><w:p><w:pPr><w:pStyle w:val="Footer"/><w:jc w:val="center"/></w:pPr>\(text("Page "))
            <w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>
            <w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>1</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r>
            \(text(" of "))<w:fldSimple w:instr=" NUMPAGES "><w:r><w:t>1</w:t></w:r></w:fldSimple></w:p></w:ftr>
            """
        func rels(_ items: [(String, String)]) -> String {
            "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
                + items.map { "<Relationship Id=\"\($0.0)\" Type=\"x\" Target=\"\($0.1)\"/>" }.joined() + "</Relationships>"
        }
        let root = """
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" \
            Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
            """
        let files: [(String, Data)] = [
            ("[Content_Types].xml", Data("<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"/>".utf8)),
            ("_rels/.rels", Data(root.utf8)),
            ("word/document.xml", Data(document.utf8)),
            ("word/styles.xml", Data(styles.utf8)),
            ("word/numbering.xml", Data(numbering.utf8)),
            ("word/header1.xml", Data(header.utf8)),
            ("word/footer1.xml", Data(footer.utf8)),
            ("word/_rels/document.xml.rels", Data(rels([("rId10", "media/logo.png"), ("rId12", "media/stamp.png"),
                                                         ("rId20", "header1.xml"), ("rId21", "footer1.xml")]).utf8)),
            ("word/_rels/header1.xml.rels", Data(rels([("rId1", "media/mark.png")]).utf8)),
            ("word/media/logo.png", try png(width: 600, height: 176, colors: [(1, 0, 0), (0, 0, 1)])),
            ("word/media/mark.png", try png(width: 200, height: 100, colors: [(0, 0.7, 0)])),
            ("word/media/stamp.png", try png(width: 100, height: 50, colors: [(1, 0, 1)])),
        ]
        return TestZipWriter.make(files.map { (name: $0.0, data: $0.1) })
    }

    /// A PNG in bands of color, top to bottom.
    private static func png(width: Int, height: Int, colors: [(CGFloat, CGFloat, CGFloat)]) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let band = CGFloat(height) / CGFloat(colors.count)
        for (index, color) in colors.enumerated() {
            context.setFillColor(CGColor(srgbRed: color.0, green: color.1, blue: color.2, alpha: 1))
            // CoreGraphics counts up from the bottom; the first band is the top one.
            context.fill(CGRect(x: 0, y: CGFloat(height) - band * CGFloat(index + 1), width: CGFloat(width), height: band))
        }
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

/// A PDF page drawn on white, read by points from the top-left.
private struct Pixels {
    let bytes: [UInt8]
    let width: Int, height: Int
    let scale: CGFloat

    init(_ url: URL, page index: Int, scale: CGFloat) {
        self.scale = scale
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: index + 1) else {
            bytes = []; width = 0; height = 0
            return
        }
        let box = page.getBoxRect(.mediaBox)
        let width = Int(box.width * scale), height = Int(box.height * scale)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            context.drawPDFPage(page)
        }
        bytes = pixels
        self.width = width
        self.height = height
    }

    /// Red, green and blue at a point (0…255); the bitmap's first row is the page's top.
    func rgb(x: CGFloat, y: CGFloat) -> (Int, Int, Int) {
        let column = Int(x * scale), row = Int(y * scale)
        guard column >= 0, row >= 0, column < width, row < height else { return (255, 255, 255) }
        let index = (row * width + column) * 4
        return (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]))
    }

    /// Each named channel strong and the others weak.
    func isColor(x: CGFloat, y: CGFloat, red: Bool = false, green: Bool = false, blue: Bool = false) -> Bool {
        let (r, g, b) = rgb(x: x, y: y)
        func matches(_ value: Int, _ wanted: Bool) -> Bool { wanted ? value > 120 : value < 90 }
        return matches(r, red) && matches(g, green) && matches(b, blue)
    }

    func describe(x: CGFloat, y: CGFloat) -> String {
        let (r, g, b) = rgb(x: x, y: y)
        return "rgb(\(r), \(g), \(b)) at \(x), \(y)"
    }

    /// The most bitmap rows in a row with something dark in any of these columns (points).
    func longestDarkRun(columns: ClosedRange<CGFloat>) -> CGFloat {
        var best = 0, run = 0
        for row in 0..<height {
            var dark = false
            var column = Int(columns.lowerBound * scale)
            while column <= Int(columns.upperBound * scale), column < width {
                let index = (row * width + column) * 4
                if Int(bytes[index]) + Int(bytes[index + 1]) + Int(bytes[index + 2]) < 3 * 170 { dark = true; break }
                column += 1
            }
            run = dark ? run + 1 : 0
            best = max(best, run)
        }
        return CGFloat(best)
    }
}
