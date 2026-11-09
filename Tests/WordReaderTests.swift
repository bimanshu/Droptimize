import XCTest
@testable import Droptimize

// Portable: also runs on Linux via scripts/check-linux.sh. Documents are built from XML strings
// (the parts of a .docx), so each test shows exactly what Word would have written.
final class WordReaderTests: XCTestCase {
    private static let namespaces = """
        xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
        xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" \
        xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
        xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture" \
        xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape" \
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" \
        xmlns:v="urn:schemas-microsoft-com:vml"
        """
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])

    /// The parts of a small .docx: `body` goes inside <w:body>, the others are whole parts.
    private func parts(body: String, styles: String? = nil, numbering: String? = nil,
                       relationships: [(id: String, target: String)] = [], extra: [String: String] = [:],
                       media: [String: Data] = [:]) -> [String: Data] {
        var parts: [String: Data] = [:]
        parts["word/document.xml"] = Data("<w:document \(Self.namespaces)><w:body>\(body)</w:body></w:document>".utf8)
        if let styles { parts["word/styles.xml"] = Data("<w:styles \(Self.namespaces)>\(styles)</w:styles>".utf8) }
        if let numbering { parts["word/numbering.xml"] = Data("<w:numbering \(Self.namespaces)>\(numbering)</w:numbering>".utf8) }
        let rels = relationships.map { "<Relationship Id=\"\($0.id)\" Type=\"x\" Target=\"\($0.target)\"/>" }.joined()
        parts["word/_rels/document.xml.rels"] = Data(
            "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(rels)</Relationships>".utf8)
        for (name, xml) in extra { parts[name] = Data(xml.utf8) }
        for (name, data) in media { parts[name] = data }
        return parts
    }

    private func paragraphs(_ document: WordDocument) -> [WordParagraph] {
        document.blocks.compactMap { if case .paragraph(let paragraph) = $0 { return paragraph } else { return nil } }
    }

    private static func inlinePicture(_ id: String, cx: Int, cy: Int) -> String {
        """
        <w:r><w:drawing><wp:inline><wp:extent cx="\(cx)" cy="\(cy)"/><wp:docPr id="1" name="Logo"/>
        <a:graphic><a:graphicData><pic:pic><pic:blipFill><a:blip r:embed="\(id)"/></pic:blipFill></pic:pic>
        </a:graphicData></a:graphic></wp:inline></w:drawing></w:r>
        """
    }

    // MARK: Pictures

    func testAPictureInTheLineKeepsItsSize() throws {
        let document = try WordReader.read(parts: parts(
            body: "<w:p><w:pPr><w:jc w:val=\"center\"/></w:pPr>\(Self.inlinePicture("rId5", cx: 5_943_600, cy: 1_741_805))</w:p>",
            relationships: [("rId5", "media/image1.png")], media: ["word/media/image1.png": Self.png]))
        let paragraph = try XCTUnwrap(paragraphs(document).first)
        XCTAssertEqual(paragraph.format.alignment, .center)
        guard case .image(let image) = paragraph.inlines.first else { return XCTFail("the logo is a picture: \(paragraph.inlines)") }
        XCTAssertEqual(image.part, "word/media/image1.png")
        XCTAssertEqual(image.width, 468, accuracy: 0.01, "5943600 EMU is 6.5 inches")
        XCTAssertEqual(image.height, 137.15, accuracy: 0.01)
        XCTAssertNil(image.floating)
        XCTAssertEqual(document.images["word/media/image1.png"], Self.png, "the picture's bytes come along")
    }

    func testAPicturePlacedOnThePage() throws {
        let anchor = """
            <w:p><w:r><w:drawing><wp:anchor behindDoc="1">
            <wp:positionH relativeFrom="page"><wp:posOffset>914400</wp:posOffset></wp:positionH>
            <wp:positionV relativeFrom="margin"><wp:align>top</wp:align></wp:positionV>
            <wp:extent cx="1270000" cy="635000"/><wp:wrapNone/>
            <a:graphic><a:graphicData><pic:pic><pic:blipFill><a:blip r:embed="rId1"/></pic:blipFill></pic:pic></a:graphicData></a:graphic>
            </wp:anchor></w:drawing></w:r></w:p>
            """
        let document = try WordReader.read(parts: parts(body: anchor, relationships: [("rId1", "media/stamp.png")],
                                                        media: ["word/media/stamp.png": Self.png]))
        guard case .image(let image) = paragraphs(document).first?.inlines.first else { return XCTFail("a picture") }
        XCTAssertEqual(image.width, 100, accuracy: 0.01)
        XCTAssertEqual(image.height, 50, accuracy: 0.01)
        let float = try XCTUnwrap(image.floating)
        XCTAssertTrue(float.overText, "no wrapping: drawn over or under the text")
        XCTAssertEqual(float.horizontalFrame, .page)
        XCTAssertEqual(float.x, 72, accuracy: 0.01)
        XCTAssertEqual(float.verticalFrame, .margin)
        XCTAssertEqual(float.verticalAlign, .top)
    }

    func testAnOlderVMLPicture() throws {
        let body = """
            <w:p><w:r><w:pict><v:shape style="width:144pt;height:1in"><v:imagedata r:id="rId2"/></v:shape></w:pict></w:r></w:p>
            """
        let document = try WordReader.read(parts: parts(body: body, relationships: [("rId2", "media/old.png")],
                                                        media: ["word/media/old.png": Self.png]))
        guard case .image(let image) = paragraphs(document).first?.inlines.first else { return XCTFail("a picture") }
        XCTAssertEqual(image.width, 144)
        XCTAssertEqual(image.height, 72)
    }

    func testATextBoxKeepsItsText() throws {
        let body = """
            <w:p><w:r><w:t>Before</w:t></w:r><w:r><mc:AlternateContent><mc:Choice Requires="wps"><w:drawing><wp:anchor>
            <wp:extent cx="100" cy="100"/><a:graphic><a:graphicData><wps:wsp><wps:txbx><w:txbxContent>
            <w:p><w:r><w:t>Inside the box</w:t></w:r></w:p></w:txbxContent></wps:txbx></wps:wsp></a:graphicData></a:graphic>
            </wp:anchor></w:drawing></mc:Choice><mc:Fallback><w:pict/></mc:Fallback></mc:AlternateContent></w:r></w:p>
            """
        let texts = paragraphs(try WordReader.read(parts: parts(body: body))).map(\.text)
        XCTAssertEqual(texts, ["Before", "Inside the box"])
    }

    // MARK: Styles and spacing

    private static let styles = """
        <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>
        <w:sz w:val="24"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="259" w:lineRule="auto"/>
        </w:pPr></w:pPrDefault></w:docDefaults>
        <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/>
        <w:pPr><w:spacing w:line="360" w:lineRule="auto"/><w:jc w:val="both"/></w:pPr></w:style>
        <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/>
        <w:pPr><w:keepNext/><w:spacing w:before="240" w:after="120"/><w:jc w:val="left"/></w:pPr>
        <w:rPr><w:b/><w:sz w:val="28"/><w:color w:val="2E74B5"/></w:rPr></w:style>
        <w:style w:type="character" w:styleId="Strong"><w:rPr><w:b/></w:rPr></w:style>
        """

    func testStylesBuildOnTheDefaultsAndEachOther() throws {
        let body = """
            <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>1. Introduction</w:t></w:r></w:p>
            <w:p><w:r><w:t xml:space="preserve">Plain and </w:t></w:r><w:r><w:rPr><w:rStyle w:val="Strong"/></w:rPr><w:t>strong</w:t></w:r></w:p>
            """
        let list = paragraphs(try WordReader.read(parts: parts(body: body, styles: Self.styles)))
        XCTAssertEqual(list.count, 2)
        let heading = list[0], text = list[1]

        XCTAssertEqual(heading.format.spaceBefore, 12)
        XCTAssertEqual(heading.format.spaceAfter, 6)
        XCTAssertEqual(heading.format.lineSpacing, .multiple(1.5), "Normal's 1.5 lines carry into the heading")
        XCTAssertEqual(heading.format.alignment, .left)
        XCTAssertTrue(heading.format.keepWithNext)
        guard case .text(_, let headingRun) = heading.inlines.first else { return XCTFail() }
        XCTAssertEqual(headingRun.font, "Times New Roman")
        XCTAssertEqual(headingRun.size, 14)
        XCTAssertTrue(headingRun.bold)
        XCTAssertEqual(headingRun.color, WordColor(hex: "2E74B5"))

        XCTAssertEqual(text.styleID, "Normal", "no style named: the default paragraph style")
        XCTAssertEqual(text.format.alignment, .justified)
        XCTAssertEqual(text.format.spaceAfter, 8, "from the document's defaults")
        XCTAssertEqual(text.text, "Plain and strong", "spaces kept")
        guard case .text(_, let plain) = text.inlines[0], case .text(_, let strong) = text.inlines[1] else { return XCTFail() }
        XCTAssertEqual(plain.size, 12)
        XCTAssertFalse(plain.bold)
        XCTAssertTrue(strong.bold, "a character style")
    }

    func testLineSpacingKinds() throws {
        let body = """
            <w:p><w:pPr><w:spacing w:line="276" w:lineRule="auto"/></w:pPr></w:p>
            <w:p><w:pPr><w:spacing w:line="280" w:lineRule="exact"/></w:pPr></w:p>
            <w:p><w:pPr><w:spacing w:line="300" w:lineRule="atLeast"/></w:pPr></w:p>
            <w:p/>
            """
        let spacing = paragraphs(try WordReader.read(parts: parts(body: body))).map(\.format.lineSpacing)
        XCTAssertEqual(spacing, [.multiple(1.15), .exactly(14), .atLeast(15), .multiple(1)])
    }

    func testIndentsTabsAndShading() throws {
        let body = """
            <w:p><w:pPr><w:tabs><w:tab w:val="right" w:pos="9000"/><w:tab w:val="left" w:pos="720"/></w:tabs>
            <w:ind w:left="720" w:right="360" w:hanging="360"/><w:shd w:val="clear" w:fill="FFFF00"/></w:pPr>
            <w:r><w:t>A</w:t></w:r><w:r><w:tab/><w:t>B</w:t></w:r></w:p>
            """
        let paragraph = try XCTUnwrap(paragraphs(try WordReader.read(parts: parts(body: body))).first)
        XCTAssertEqual(paragraph.format.indentLeft, 36)
        XCTAssertEqual(paragraph.format.indentRight, 18)
        XCTAssertEqual(paragraph.format.firstLine, -18, "a hanging indent")
        XCTAssertEqual(paragraph.format.tabStops, [36, 450])
        XCTAssertEqual(paragraph.format.shading, WordColor(red: 1, green: 1, blue: 0))
        XCTAssertEqual(paragraph.text, "A\tB")
    }

    func testThemeFonts() throws {
        let theme = """
            <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:themeElements><a:fontScheme name="Office">
            <a:majorFont><a:latin typeface="Calibri Light"/></a:majorFont><a:minorFont><a:latin typeface="Calibri"/></a:minorFont>
            </a:fontScheme></a:themeElements></a:theme>
            """
        let styles = "<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:asciiTheme=\"minorHAnsi\" w:hAnsiTheme=\"minorHAnsi\"/></w:rPr></w:rPrDefault></w:docDefaults>"
        let body = """
            <w:p><w:r><w:t>Body</w:t></w:r><w:r><w:rPr><w:rFonts w:asciiTheme="majorHAnsi"/></w:rPr><w:t>Title</w:t></w:r></w:p>
            """
        let paragraph = try XCTUnwrap(paragraphs(try WordReader.read(parts: parts(body: body, styles: styles,
                                                                                   extra: ["word/theme/theme1.xml": theme]))).first)
        guard case .text(_, let body1) = paragraph.inlines[0], case .text(_, let title) = paragraph.inlines[1] else { return XCTFail() }
        XCTAssertEqual(body1.font, "Calibri")
        XCTAssertEqual(title.font, "Calibri Light")
        XCTAssertEqual(body1.size, 10, "Word's own default when nothing sets a size")
    }

    func testRunFormatting() throws {
        let body = """
            <w:p><w:r><w:rPr><w:i/><w:u w:val="single"/><w:strike/><w:caps/><w:highlight w:val="yellow"/><w:vertAlign w:val="superscript"/></w:rPr>
            <w:t>x</w:t></w:r><w:r><w:rPr><w:b w:val="0"/><w:u w:val="none"/><w:vanish/></w:rPr><w:t>hidden</w:t></w:r></w:p>
            """
        let paragraph = try XCTUnwrap(paragraphs(try WordReader.read(parts: parts(body: body))).first)
        XCTAssertEqual(paragraph.text, "x", "hidden text isn't shown")
        guard case .text(_, let run) = paragraph.inlines[0] else { return XCTFail() }
        XCTAssertTrue(run.italic && run.underline && run.strike && run.caps)
        XCTAssertEqual(run.highlight, WordColor(red: 1, green: 1, blue: 0))
        XCTAssertEqual(run.verticalAlign, .superscript)
    }

    // MARK: Breaks

    func testAParagraphThatOnlyBreaksThePage() throws {
        let body = """
            <w:p><w:r><w:t>Page one</w:t></w:r></w:p>
            <w:p><w:r><w:br w:type="page"/></w:r></w:p>
            <w:p><w:r><w:t>Page two</w:t></w:r></w:p>
            <w:p><w:r><w:t>Still two</w:t><w:br w:type="page"/><w:t>Page three</w:t></w:r></w:p>
            """
        let list = paragraphs(try WordReader.read(parts: parts(body: body)))
        XCTAssertEqual(list.map(\.text), ["Page one", "Page two", "Still twoPage three"], "no empty page-break paragraph")
        XCTAssertEqual(list.map(\.format.pageBreakBefore), [false, true, false])
        XCTAssertEqual(list[2].inlines.filter { $0 == .pageBreak }.count, 1, "a break inside a paragraph stays inside it")
    }

    func testASectionBreakStartsANewPage() throws {
        let body = """
            <w:p><w:pPr><w:sectPr><w:pgSz w:w="11906" w:h="16838"/></w:sectPr></w:pPr><w:r><w:t>End of one</w:t></w:r></w:p>
            <w:p><w:r><w:t>Start of two</w:t></w:r></w:p>
            <w:p><w:pPr><w:sectPr><w:type w:val="continuous"/></w:sectPr></w:pPr><w:r><w:t>End of two</w:t></w:r></w:p>
            <w:p><w:r><w:t>Same page</w:t></w:r></w:p>
            <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1273" w:bottom="1440" w:left="1273" w:header="708" w:footer="708"/></w:sectPr>
            """
        let document = try WordReader.read(parts: parts(body: body))
        XCTAssertEqual(paragraphs(document).map(\.format.pageBreakBefore), [false, true, false, false])
        XCTAssertEqual(document.page.width, 595.3, accuracy: 0.01, "A4")
        XCTAssertEqual(document.page.height, 841.9, accuracy: 0.01)
        XCTAssertEqual(document.page.left, 63.65, accuracy: 0.01)
        XCTAssertEqual(document.page.top, 72)
        XCTAssertEqual(document.page.header, 35.4, accuracy: 0.01)
    }

    func testTrackedChangesReadAsAccepted() throws {
        let body = """
            <w:p><w:r><w:t xml:space="preserve">Keep </w:t></w:r><w:del><w:r><w:delText>gone </w:delText></w:r></w:del>
            <w:ins><w:r><w:t>added</w:t></w:r></w:ins><w:hyperlink r:id="rId9"><w:r><w:t xml:space="preserve"> link</w:t></w:r></w:hyperlink></w:p>
            """
        XCTAssertEqual(paragraphs(try WordReader.read(parts: parts(body: body))).first?.text, "Keep added link")
    }

    // MARK: Lists

    func testNumberedAndBulletedLists() throws {
        let numbering = """
            <w:abstractNum w:abstractNumId="0">
            <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/><w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl>
            <w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="lowerLetter"/><w:lvlText w:val="%2)"/></w:lvl>
            <w:lvl w:ilvl="2"><w:start w:val="1"/><w:numFmt w:val="lowerRoman"/><w:lvlText w:val="%1.%3"/></w:lvl>
            </w:abstractNum>
            <w:abstractNum w:abstractNumId="1"><w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/><w:lvlText w:val="\u{F0B7}"/>
            <w:rPr><w:rFonts w:ascii="Symbol" w:hAnsi="Symbol"/></w:rPr></w:lvl></w:abstractNum>
            <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
            <w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>
            """
        func item(_ text: String, num: Int, level: Int = 0) -> String {
            "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"\(level)\"/><w:numId w:val=\"\(num)\"/></w:numPr></w:pPr><w:r><w:t>\(text)</w:t></w:r></w:p>"
        }
        let body = [item("One", num: 1), item("Sub", num: 1, level: 1), item("Sub two", num: 1, level: 1),
                    item("Deep", num: 1, level: 2), item("Two", num: 1), item("Sub again", num: 1, level: 1),
                    item("Dot", num: 2)].joined()
        let list = paragraphs(try WordReader.read(parts: parts(body: body, numbering: numbering)))
        let markers = list.map { paragraph -> String in
            guard case .text(let text, _) = paragraph.marker else { return "" }
            return text
        }
        XCTAssertEqual(markers, ["1.", "a)", "b)", "1.i", "2.", "a)", "•"], "deeper levels restart under a new item")
        XCTAssertEqual(list[0].format.indentLeft, 36)
        XCTAssertEqual(list[0].format.firstLine, -18)
        guard case .text(_, let bulletRun) = list[6].marker else { return XCTFail() }
        XCTAssertNotEqual(bulletRun.font, "Symbol", "drawn as a plain bullet, not in the Symbol font")
    }

    // MARK: Tables

    func testABorderedTable() throws {
        let body = """
            <w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblCellSpacing w:w="15" w:type="dxa"/>
            <w:tblBorders><w:top w:val="single" w:sz="4" w:color="000000"/><w:left w:val="single" w:sz="4"/>
            <w:bottom w:val="single" w:sz="4"/><w:right w:val="single" w:sz="4"/><w:insideH w:val="single" w:sz="4"/>
            <w:insideV w:val="single" w:sz="4"/></w:tblBorders><w:tblCellMar><w:top w:w="15" w:type="dxa"/>
            <w:left w:w="15" w:type="dxa"/><w:bottom w:w="15" w:type="dxa"/><w:right w:w="15" w:type="dxa"/></w:tblCellMar></w:tblPr>
            <w:tblGrid><w:gridCol w:w="1272"/><w:gridCol w:w="3797"/><w:gridCol w:w="4281"/></w:tblGrid>
            <w:tr><w:trPr><w:trHeight w:val="400"/></w:trPr>
              <w:tc><w:tcPr><w:vMerge w:val="restart"/><w:vAlign w:val="center"/></w:tcPr><w:p><w:r><w:t>S.No</w:t></w:r></w:p></w:tc>
              <w:tc><w:tcPr><w:gridSpan w:val="2"/><w:shd w:val="clear" w:fill="D9E2F3"/></w:tcPr><w:p><w:r><w:t>Wide</w:t></w:r></w:p></w:tc></w:tr>
            <w:tr><w:tc><w:tcPr><w:vMerge/></w:tcPr><w:p/></w:tc>
              <w:tc><w:p><w:r><w:t>B</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>C</w:t></w:r></w:p></w:tc></w:tr>
            </w:tbl><w:p/>
            """
        let document = try WordReader.read(parts: parts(body: body))
        guard case .table(let table) = document.blocks.first else { return XCTFail("a table first: \(document.blocks)") }
        XCTAssertEqual(table.columns, [63.6, 189.85, 214.05])
        XCTAssertEqual(table.cellSpacing, 0.75)
        XCTAssertEqual(table.cellMargins, WordInsets(top: 0.75, left: 0.75, bottom: 0.75, right: 0.75))
        XCTAssertEqual(table.borders.top, WordBorder(width: 0.5, color: WordColor(hex: "000000")))
        XCTAssertEqual(table.borders.insideVertical?.width, 0.5)
        XCTAssertEqual(table.rows.count, 2)
        XCTAssertEqual(table.rows[0].minimumHeight, 20)
        let first = table.rows[0].cells
        XCTAssertEqual(first.map(\.columnSpan), [1, 2])
        XCTAssertEqual(first[0].verticalMerge, .start)
        XCTAssertEqual(first[0].verticalAlign, .center)
        XCTAssertEqual(first[1].shading, WordColor(hex: "D9E2F3"))
        XCTAssertEqual(table.rows[1].cells[0].verticalMerge, .continued)
        guard case .paragraph(let wide) = first[1].blocks.first else { return XCTFail() }
        XCTAssertEqual(wide.text, "Wide")
    }

    func testATableStyleGivesBordersAndHeaderFormatting() throws {
        let styles = """
            <w:style w:type="table" w:default="1" w:styleId="TableNormal"><w:tblPr><w:tblCellMar><w:left w:w="108" w:type="dxa"/>
            <w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>
            <w:style w:type="table" w:styleId="TableGrid"><w:basedOn w:val="TableNormal"/><w:tblPr><w:tblBorders>
            <w:top w:val="single" w:sz="4"/><w:insideH w:val="single" w:sz="8"/></w:tblBorders></w:tblPr>
            <w:tblStylePr w:type="firstRow"><w:rPr><w:b/></w:rPr><w:tcPr><w:shd w:val="clear" w:fill="4472C4"/></w:tcPr></w:tblStylePr></w:style>
            """
        let body = """
            <w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:jc w:val="center"/><w:tblLook w:firstRow="1"/></w:tblPr>
            <w:tblGrid><w:gridCol w:w="2000"/></w:tblGrid>
            <w:tr><w:tc><w:p><w:r><w:t>Head</w:t></w:r></w:p></w:tc></w:tr><w:tr><w:tc><w:p><w:r><w:t>Body</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
            """
        guard case .table(let table) = try WordReader.read(parts: parts(body: body, styles: styles)).blocks.first else { return XCTFail() }
        XCTAssertEqual(table.alignment, .center)
        XCTAssertEqual(table.cellMargins.left, 5.4)
        XCTAssertEqual(table.borders.insideHorizontal?.width, 1)
        XCTAssertNil(table.borders.bottom)
        XCTAssertEqual(table.rows[0].cells[0].shading, WordColor(hex: "4472C4"))
        XCTAssertNil(table.rows[1].cells[0].shading)
        func run(_ row: Int) -> RunFormat? {
            guard case .paragraph(let paragraph) = table.rows[row].cells[0].blocks.first,
                  case .text(_, let format) = paragraph.inlines.first else { return nil }
            return format
        }
        XCTAssertEqual(run(0)?.bold, true, "the header row is bold")
        XCTAssertEqual(run(1)?.bold, false)
    }

    // MARK: Headers and footers

    func testHeadersAndFootersWithALogoAndPageNumbers() throws {
        let header = """
            <w:hdr \(Self.namespaces)><w:p>\(Self.inlinePicture("rId1", cx: 914_400, cy: 457_200))</w:p></w:hdr>
            """
        let footer = """
            <w:ftr \(Self.namespaces)><w:p><w:pPr><w:jc w:val="right"/></w:pPr><w:r><w:t xml:space="preserve">Page </w:t></w:r>
            <w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText xml:space="preserve"> PAGE \\* MERGEFORMAT </w:instrText></w:r>
            <w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>7</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r>
            <w:r><w:t xml:space="preserve"> of </w:t></w:r><w:fldSimple w:instr=" NUMPAGES "><w:r><w:t>9</w:t></w:r></w:fldSimple></w:p></w:ftr>
            """
        let first = "<w:hdr \(Self.namespaces)><w:p><w:r><w:t>Cover</w:t></w:r></w:p></w:hdr>"
        let rels = "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + "<Relationship Id=\"rId1\" Type=\"x\" Target=\"media/logo.png\"/></Relationships>"
        let body = """
            <w:p><w:r><w:t>Body</w:t></w:r></w:p>
            <w:sectPr><w:headerReference w:type="default" r:id="rId7"/><w:headerReference w:type="first" r:id="rId8"/>
            <w:footerReference w:type="default" r:id="rId9"/><w:titlePg/></w:sectPr>
            """
        let document = try WordReader.read(parts: parts(
            body: body, relationships: [("rId7", "header1.xml"), ("rId8", "header2.xml"), ("rId9", "footer1.xml")],
            extra: ["word/header1.xml": header, "word/header2.xml": first, "word/footer1.xml": footer,
                    "word/_rels/header1.xml.rels": rels],
            media: ["word/media/logo.png": Self.png]))
        XCTAssertTrue(document.page.differentFirstPage)
        guard case .paragraph(let logoLine) = document.header?.first, case .image(let logo) = logoLine.inlines.first else {
            return XCTFail("the header's logo: \(String(describing: document.header))")
        }
        XCTAssertEqual(logo.part, "word/media/logo.png")
        XCTAssertEqual(logo.width, 72)
        XCTAssertNotNil(document.images["word/media/logo.png"])
        guard case .paragraph(let cover) = document.firstHeader?.first else { return XCTFail() }
        XCTAssertEqual(cover.text, "Cover")
        XCTAssertEqual(document.firstFooter, [], "a first page with no footer of its own has none")

        guard case .paragraph(let numbers) = document.footer?.first else { return XCTFail() }
        XCTAssertEqual(numbers.format.alignment, .right)
        let kinds = numbers.inlines.map { inline -> String in
            switch inline {
            case .text(let text, _): return text
            case .field(.page, _): return "{PAGE}"
            case .field(.numberOfPages, _): return "{NUMPAGES}"
            default: return "?"
            }
        }
        XCTAssertEqual(kinds, ["Page ", "{PAGE}", " of ", "{NUMPAGES}"], "the saved numbers 7 and 9 aren't shown")
    }

    func testOtherFieldsShowTheirSavedResult() throws {
        let body = """
            <w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText>DATE \\@ "d MMMM yyyy"</w:instrText></w:r>
            <w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>9 November 2026</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>
            """
        XCTAssertEqual(paragraphs(try WordReader.read(parts: parts(body: body))).first?.text, "9 November 2026")
    }

    // MARK: The file itself

    func testReadsTheZipFile() throws {
        let contentTypes = "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"/>"
        let root = """
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
            </Relationships>
            """
        var files = parts(body: "<w:p>\(Self.inlinePicture("rId5", cx: 1_270_000, cy: 1_270_000))<w:r><w:t>Hello</w:t></w:r></w:p>",
                          relationships: [("rId5", "media/image1.png")], media: ["word/media/image1.png": Self.png])
        files["[Content_Types].xml"] = Data(contentTypes.utf8)
        files["_rels/.rels"] = Data(root.utf8)
        for deflated in [true, false] {
            let zip = TestZipWriter.make(files.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }, deflated: deflated)
            let document = try WordReader.read(zip)
            XCTAssertEqual(paragraphs(document).first?.text, "Hello")
            XCTAssertEqual(document.images["word/media/image1.png"], Self.png, deflated ? "deflated" : "stored")
        }
    }

    func testSomethingElseIsNotAWordDocument() {
        XCTAssertThrowsError(try WordReader.read(Data("this is not a Word document".utf8))) { error in
            XCTAssertEqual(error as? WordReader.Failure, .notAWordDocument)
        }
        let zip = TestZipWriter.make([("hello.txt", Data("hi".utf8))])
        XCTAssertThrowsError(try WordReader.read(zip)) { error in
            XCTAssertEqual(error as? WordReader.Failure, .notAWordDocument)
        }
    }
}
