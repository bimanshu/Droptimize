import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Reads a .docx into a `WordDocument` (CORE.md §7c): styles with what they're based on, the
/// document's defaults and theme fonts, numbered and bulleted lists, tables, pictures in the line
/// and placed on the page, headers and footers with page numbers, page and section breaks, text
/// boxes (as text), and tracked changes as if accepted. Written from the Office Open XML spec
/// (ECMA-376), so it doesn't depend on any Office app.
enum WordReader {
    enum Failure: Error, Equatable { case notAWordDocument, unreadable(String) }

    static func read(_ data: Data) throws -> WordDocument {
        let zip: ZipArchive
        do { zip = try ZipArchive(data) } catch { throw Failure.notAWordDocument }
        var parts: [String: Data] = [:]
        for name in zip.entries.keys where name.hasSuffix(".xml") || name.hasSuffix(".rels") || name.hasPrefix("word/media/") {
            parts[name] = try zip.file(name)
        }
        return try read(parts: parts)
    }

    /// The document from its parts, by path ("word/document.xml"); tests build these from strings.
    static func read(parts: [String: Data]) throws -> WordDocument {
        var reader = Reader(parts: parts)
        return try reader.document()
    }
}

// MARK: A small XML tree

/// One element: its name with the usual Office prefix ("w:p", whatever prefix the file used) and
/// its attributes by local name ("val", "embed").
final class XElement {
    let name: String
    var attributes: [String: String]
    var children: [XElement] = []
    var text = ""

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    func child(_ name: String) -> XElement? { children.first { $0.name == name } }
    func children(_ name: String) -> [XElement] { children.filter { $0.name == name } }
    func attr(_ local: String) -> String? { attributes[local] }

    /// Every element below this one with `name`, in document order.
    func descendants(_ name: String) -> [XElement] {
        var found: [XElement] = []
        for child in children {
            if child.name == name { found.append(child) }
            found += child.descendants(name)
        }
        return found
    }

    /// An on/off property: present and not "0"/"false"/"off".
    var isOn: Bool {
        guard let value = attr("val") else { return true }
        return !["0", "false", "off", "none"].contains(value)
    }
}

enum XMLTree {
    /// Namespace → the prefix Office files use, so names don't depend on the file's own prefixes.
    static let prefixes: [String: String] = [
        "http://schemas.openxmlformats.org/wordprocessingml/2006/main": "w",
        "http://purl.oclc.org/ooxml/wordprocessingml/main": "w",
        "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing": "wp",
        "http://purl.oclc.org/ooxml/drawingml/wordprocessingDrawing": "wp",
        "http://schemas.openxmlformats.org/drawingml/2006/main": "a",
        "http://purl.oclc.org/ooxml/drawingml/main": "a",
        "http://schemas.openxmlformats.org/drawingml/2006/picture": "pic",
        "http://purl.oclc.org/ooxml/drawingml/picture": "pic",
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships": "r",
        "http://purl.oclc.org/ooxml/officeDocument/relationships": "r",
        "http://schemas.openxmlformats.org/package/2006/relationships": "rel",
        "http://schemas.microsoft.com/office/word/2010/wordprocessingShape": "wps",
        "http://schemas.microsoft.com/office/word/2010/wordprocessingGroup": "wpg",
        "http://schemas.openxmlformats.org/markup-compatibility/2006": "mc",
        "urn:schemas-microsoft-com:vml": "v",
    ]

    static func parse(_ data: Data) throws -> XElement {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else {
            throw WordReader.Failure.unreadable(parser.parserError?.localizedDescription ?? "XML")
        }
        return root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XElement?
        private var stack: [XElement] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let prefix = namespaceURI.flatMap { XMLTree.prefixes[$0] }
                ?? qName.flatMap { $0.contains(":") ? String($0.split(separator: ":")[0]) : nil } ?? ""
            let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
            var attributes: [String: String] = [:]
            for (key, value) in attributeDict {
                attributes[key.split(separator: ":").last.map(String.init) ?? key] = value
            }
            let element = XElement(name: prefix.isEmpty ? local : "\(prefix):\(local)", attributes: attributes)
            stack.last?.children.append(element)
            if root == nil { root = element }
            stack.append(element)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            stack.removeLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }
    }
}

// MARK: Properties as Word stores them: only what's set, layered from defaults up to direct formatting

struct ParagraphProps {
    var alignment: ParagraphFormat.Alignment?
    var spaceBefore: Double?, spaceAfter: Double?
    var lineSpacing: ParagraphFormat.LineSpacing?
    var indentLeft: Double?, indentRight: Double?, firstLine: Double?
    var keepWithNext: Bool?, keepLines: Bool?, pageBreakBefore: Bool?, contextualSpacing: Bool?
    /// By position; nil clears a stop set further down the style chain.
    var tabs: [Double: WordTab?] = [:]
    var shading: WordColor??
    var borders: WordBorders?
    var numbering: (id: String, level: Int)?
    var mark = RunProps()

    mutating func apply(_ other: ParagraphProps) {
        alignment = other.alignment ?? alignment
        spaceBefore = other.spaceBefore ?? spaceBefore
        spaceAfter = other.spaceAfter ?? spaceAfter
        lineSpacing = other.lineSpacing ?? lineSpacing
        indentLeft = other.indentLeft ?? indentLeft
        indentRight = other.indentRight ?? indentRight
        firstLine = other.firstLine ?? firstLine
        keepWithNext = other.keepWithNext ?? keepWithNext
        keepLines = other.keepLines ?? keepLines
        pageBreakBefore = other.pageBreakBefore ?? pageBreakBefore
        contextualSpacing = other.contextualSpacing ?? contextualSpacing
        tabs.merge(other.tabs) { $1 }
        if let shading = other.shading { self.shading = shading }
        borders = other.borders ?? borders
        numbering = other.numbering ?? numbering
        mark.apply(other.mark)
    }

    func resolved(mark: RunFormat) -> ParagraphFormat {
        var format = ParagraphFormat()
        format.alignment = alignment ?? .left
        format.spaceBefore = spaceBefore ?? 0
        format.spaceAfter = spaceAfter ?? 0
        format.lineSpacing = lineSpacing ?? .multiple(1)
        format.indentLeft = indentLeft ?? 0
        format.indentRight = indentRight ?? 0
        format.firstLine = firstLine ?? 0
        format.keepWithNext = keepWithNext ?? false
        format.keepLines = keepLines ?? false
        format.pageBreakBefore = pageBreakBefore ?? false
        format.contextualSpacing = contextualSpacing ?? false
        format.tabStops = tabs.values.compactMap { $0 }.sorted { $0.position < $1.position }
        format.shading = shading ?? nil
        if let borders, [borders.top, borders.left, borders.bottom, borders.right, borders.insideHorizontal]
            .contains(where: { ($0?.width ?? 0) > 0 }) {
            format.borders = borders
        }
        format.markFormat = mark
        return format
    }
}

struct RunProps {
    var font: String?
    var size: Double?
    var bold: Bool?, italic: Bool?, underline: Bool?, strike: Bool?, caps: Bool?, smallCaps: Bool?, hidden: Bool?
    var color: WordColor??
    var highlight: WordColor??
    var verticalAlign: RunFormat.VerticalAlign?

    mutating func apply(_ other: RunProps) {
        font = other.font ?? font
        size = other.size ?? size
        bold = other.bold ?? bold
        italic = other.italic ?? italic
        underline = other.underline ?? underline
        strike = other.strike ?? strike
        caps = other.caps ?? caps
        smallCaps = other.smallCaps ?? smallCaps
        hidden = other.hidden ?? hidden
        if let color = other.color { self.color = color }
        if let highlight = other.highlight { self.highlight = highlight }
        verticalAlign = other.verticalAlign ?? verticalAlign
    }

    var resolved: RunFormat {
        var format = RunFormat()
        format.font = font ?? format.font
        format.size = size ?? format.size
        format.bold = bold ?? false
        format.italic = italic ?? false
        format.underline = underline ?? false
        format.strike = strike ?? false
        format.caps = caps ?? false
        format.smallCaps = smallCaps ?? false
        format.hidden = hidden ?? false
        format.color = color ?? nil
        format.highlight = highlight ?? nil
        format.verticalAlign = verticalAlign ?? .baseline
        return format
    }
}

private struct StyleDefinition {
    var type = "paragraph"
    var basedOn: String?
    var paragraph = ParagraphProps()
    var run = RunProps()
    var tableBorders: WordBorders?
    var tableCellMargins: [String: Double] = [:]
    var firstRowRun: RunProps?
    var firstRowShading: WordColor??
}

private struct NumberingLevel {
    var format = "decimal"
    var text = "%1."
    var start = 1
    var paragraph = ParagraphProps()
    var run = RunProps()
}

// MARK: The reader

private struct Reader {
    let parts: [String: Data]
    var styles: [String: StyleDefinition] = [:]
    var defaultParagraphStyle: String?
    var defaultTableStyle: String?
    var defaultParagraph = ParagraphProps()
    var defaultRun = RunProps()
    var majorFont: String?, minorFont: String?
    var abstractNumbering: [String: [Int: NumberingLevel]] = [:]
    var numbering: [String: (abstract: String, starts: [Int: Int])] = [:]
    var counters: [String: [Int: Int]] = [:]
    var images: [String: Data] = [:]
    /// A field (PAGE, a table of contents…) can run across runs and paragraphs.
    var fields: [(instruction: String, inResult: Bool, replaced: Bool)] = []

    init(parts: [String: Data]) {
        self.parts = parts
    }

    mutating func document() throws -> WordDocument {
        let main = mainPart()
        guard let data = parts[main] else { throw WordReader.Failure.notAWordDocument }
        let root = try XMLTree.parse(data)
        guard let body = root.child("w:body") else { throw WordReader.Failure.notAWordDocument }
        readTheme()
        readStyles()
        readNumbering()

        var document = WordDocument()
        let rels = relationships(of: main)
        document.blocks = blocks(in: body, rels: rels, table: nil)
        if let section = body.child("w:sectPr") {
            document.page = page(section)
            func part(_ kind: String, _ type: String) -> [WordBlock]? {
                guard let reference = section.children("w:\(kind)Reference").first(where: { ($0.attr("type") ?? "default") == type }),
                      let id = reference.attr("id"), let path = rels[id], let data = parts[path],
                      let root = try? XMLTree.parse(data)
                else { return nil }
                return blocks(in: root, rels: relationships(of: path), table: nil)
            }
            document.header = part("header", "default")
            document.footer = part("footer", "default")
            if document.page.differentFirstPage {
                document.firstHeader = part("header", "first") ?? []
                document.firstFooter = part("footer", "first") ?? []
            }
        }
        document.images = images
        return document
    }

    private func mainPart() -> String {
        if let data = parts["_rels/.rels"], let root = try? XMLTree.parse(data),
           let main = root.children.first(where: { ($0.attr("Type") ?? "").hasSuffix("/officeDocument") })?.attr("Target") {
            return main.hasPrefix("/") ? String(main.dropFirst()) : main
        }
        return "word/document.xml"
    }

    /// rId → part path, for a part ("word/document.xml" → "word/_rels/document.xml.rels").
    private func relationships(of part: String) -> [String: String] {
        let folder = (part as NSString).deletingLastPathComponent
        let file = (part as NSString).lastPathComponent
        guard let data = parts["\(folder)/_rels/\(file).rels"], let root = try? XMLTree.parse(data) else { return [:] }
        var map: [String: String] = [:]
        for relationship in root.children where relationship.attr("TargetMode") != "External" {
            guard let id = relationship.attr("Id"), let target = relationship.attr("Target") else { continue }
            map[id] = target.hasPrefix("/") ? String(target.dropFirst()) : Self.normalize("\(folder)/\(target)")
        }
        return map
    }

    /// "word/../word/media/a.png" → "word/media/a.png".
    private static func normalize(_ path: String) -> String {
        var out: [Substring] = []
        for piece in path.split(separator: "/") {
            if piece == ".." { _ = out.popLast() } else if piece != "." { out.append(piece) }
        }
        return out.joined(separator: "/")
    }

    // MARK: Theme, styles, numbering

    private mutating func readTheme() {
        guard let path = parts.keys.sorted().first(where: { $0.hasPrefix("word/theme/") && $0.hasSuffix(".xml") }),
              let data = parts[path], let root = try? XMLTree.parse(data),
              let scheme = root.descendants("a:fontScheme").first
        else { return }
        majorFont = scheme.child("a:majorFont")?.child("a:latin")?.attr("typeface")
        minorFont = scheme.child("a:minorFont")?.child("a:latin")?.attr("typeface")
    }

    private mutating func readStyles() {
        guard let data = parts["word/styles.xml"], let root = try? XMLTree.parse(data) else { return }
        if let defaults = root.child("w:docDefaults") {
            if let rPr = defaults.child("w:rPrDefault")?.child("w:rPr") { defaultRun = runProps(rPr) }
            if let pPr = defaults.child("w:pPrDefault")?.child("w:pPr") { defaultParagraph = paragraphProps(pPr) }
        }
        for style in root.children("w:style") {
            guard let id = style.attr("styleId") else { continue }
            var definition = StyleDefinition()
            definition.type = style.attr("type") ?? "paragraph"
            definition.basedOn = style.child("w:basedOn")?.attr("val")
            if let pPr = style.child("w:pPr") { definition.paragraph = paragraphProps(pPr) }
            if let rPr = style.child("w:rPr") { definition.run = runProps(rPr) }
            if let tblPr = style.child("w:tblPr") {
                definition.tableBorders = tblPr.child("w:tblBorders").map(borders)
                definition.tableCellMargins = cellMargins(tblPr.child("w:tblCellMar"))
            }
            for conditional in style.children("w:tblStylePr") where conditional.attr("type") == "firstRow" {
                if let rPr = conditional.child("w:rPr") { definition.firstRowRun = runProps(rPr) }
                if let shd = conditional.child("w:tcPr")?.child("w:shd") { definition.firstRowShading = shading(shd) }
            }
            styles[id] = definition
            if style.attr("default") == "1" {
                if definition.type == "paragraph" { defaultParagraphStyle = id }
                if definition.type == "table" { defaultTableStyle = id }
            }
        }
    }

    /// A style and everything it's based on, base first.
    private func chain(_ id: String?) -> [StyleDefinition] {
        var result: [StyleDefinition] = []
        var current = id
        var seen: Set<String> = []
        while let id = current, !seen.contains(id), let style = styles[id] {
            seen.insert(id)
            result.insert(style, at: 0)
            current = style.basedOn
        }
        return result
    }

    private mutating func readNumbering() {
        guard let data = parts["word/numbering.xml"], let root = try? XMLTree.parse(data) else { return }
        for abstract in root.children("w:abstractNum") {
            guard let id = abstract.attr("abstractNumId") else { continue }
            var levels: [Int: NumberingLevel] = [:]
            for lvl in abstract.children("w:lvl") {
                guard let index = lvl.attr("ilvl").flatMap(Int.init) else { continue }
                var level = NumberingLevel()
                level.format = lvl.child("w:numFmt")?.attr("val") ?? "decimal"
                level.text = lvl.child("w:lvlText")?.attr("val") ?? ""
                level.start = lvl.child("w:start")?.attr("val").flatMap(Int.init) ?? 1
                if let pPr = lvl.child("w:pPr") { level.paragraph = paragraphProps(pPr) }
                if let rPr = lvl.child("w:rPr") { level.run = runProps(rPr) }
                levels[index] = level
            }
            abstractNumbering[id] = levels
        }
        for num in root.children("w:num") {
            guard let id = num.attr("numId"), let abstract = num.child("w:abstractNumId")?.attr("val") else { continue }
            var starts: [Int: Int] = [:]
            for override in num.children("w:lvlOverride") {
                if let level = override.attr("ilvl").flatMap(Int.init),
                   let start = override.child("w:startOverride")?.attr("val").flatMap(Int.init) {
                    starts[level] = start
                }
            }
            numbering[id] = (abstract, starts)
        }
    }

    /// The next number or bullet for a list paragraph, its formatting, and the list's indents.
    private mutating func listMarker(_ id: String, level: Int) -> (text: String, run: RunProps, paragraph: ParagraphProps)? {
        guard id != "0", let num = numbering[id], let levels = abstractNumbering[num.abstract], let current = levels[level] else {
            return nil
        }
        var counts = counters[id] ?? [:]
        let start = num.starts[level] ?? current.start
        counts[level] = (counts[level] ?? (start - 1)) + 1
        for deeper in (level + 1)..<9 { counts[deeper] = nil }
        counters[id] = counts
        var text = current.text
        for index in 0...level {
            let format = levels[index]?.format ?? "decimal"
            let value = counts[index] ?? (num.starts[index] ?? levels[index]?.start ?? 1)
            text = text.replacingOccurrences(of: "%\(index + 1)", with: Self.number(value, format: format))
        }
        if current.format == "bullet" { text = Self.bullet(text, font: current.run.font) }
        if current.format == "none" { text = "" }
        var run = current.run
        if current.format == "bullet", let font = run.font, Self.symbolFonts.contains(font) { run.font = nil }
        return (text, run, current.paragraph)
    }

    private static let symbolFonts: Set<String> = ["Symbol", "Wingdings", "Wingdings 2", "Wingdings 3", "Webdings"]

    /// Symbol and Wingdings bullets live in the private-use area; draw them as the plain shape.
    private static func bullet(_ text: String, font: String?) -> String {
        let map: [UInt32: String] = [0xF0B7: "•", 0xF0A7: "▪", 0xF0A8: "◆", 0xF0D8: "➢", 0xF0FC: "✓", 0xF076: "❖",
                                     0xF06E: "■", 0xF06C: "●", 0xF0E8: "➔", 0xF0A1: "○", 0xF0B2: "◇", 0xF02D: "–"]
        if font == "Courier New", text == "o" { return "◦" }
        return String(text.unicodeScalars.map { map[$0.value].map(Character.init) ?? Character($0) })
    }

    static func number(_ value: Int, format: String) -> String {
        switch format {
        case "lowerLetter", "upperLetter":
            let letter = Character(UnicodeScalar(UInt8(97 + (max(value, 1) - 1) % 26)))
            let text = String(repeating: letter, count: (max(value, 1) - 1) / 26 + 1)
            return format == "upperLetter" ? text.uppercased() : text
        case "lowerRoman", "upperRoman":
            let text = roman(value)
            return format == "upperRoman" ? text : text.lowercased()
        case "decimalZero":
            return value < 10 ? "0\(value)" : "\(value)"
        default:
            return "\(value)"
        }
    }

    private static func roman(_ value: Int) -> String {
        let table: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                                      (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var rest = max(1, value), out = ""
        for (amount, letters) in table { while rest >= amount { out += letters; rest -= amount } }
        return out
    }

    // MARK: Property elements

    private func paragraphProps(_ pPr: XElement) -> ParagraphProps {
        var props = ParagraphProps()
        if let jc = pPr.child("w:jc")?.attr("val") {
            switch jc {
            case "center": props.alignment = .center
            case "right", "end": props.alignment = .right
            case "both", "distribute", "lowKashida", "mediumKashida", "highKashida", "thaiDistribute": props.alignment = .justified
            default: props.alignment = .left
            }
        }
        if let spacing = pPr.child("w:spacing") {
            props.spaceBefore = spacing.attr("beforeAutospacing") == "1" ? 14 : WordUnits.twips(spacing.attr("before"))
            props.spaceAfter = spacing.attr("afterAutospacing") == "1" ? 14 : WordUnits.twips(spacing.attr("after"))
            if let line = spacing.attr("line").flatMap(Double.init) {
                switch spacing.attr("lineRule") ?? "auto" {
                case "exact": props.lineSpacing = .exactly(abs(line) / 20)
                case "atLeast": props.lineSpacing = .atLeast(line / 20)
                default: props.lineSpacing = .multiple(line / 240)
                }
            }
        }
        if let ind = pPr.child("w:ind") {
            props.indentLeft = WordUnits.twips(ind.attr("left") ?? ind.attr("start"))
            props.indentRight = WordUnits.twips(ind.attr("right") ?? ind.attr("end"))
            if let hanging = WordUnits.twips(ind.attr("hanging")) { props.firstLine = -hanging }
            else if let first = WordUnits.twips(ind.attr("firstLine")) { props.firstLine = first }
        }
        if let element = pPr.child("w:keepNext") { props.keepWithNext = element.isOn }
        if let element = pPr.child("w:keepLines") { props.keepLines = element.isOn }
        if let element = pPr.child("w:pageBreakBefore") { props.pageBreakBefore = element.isOn }
        if let element = pPr.child("w:contextualSpacing") { props.contextualSpacing = element.isOn }
        for tab in pPr.child("w:tabs")?.children("w:tab") ?? [] {
            guard let position = WordUnits.twips(tab.attr("pos")) else { continue }
            let alignment: WordTab.Alignment
            switch tab.attr("val") {
            case "clear":
                props.tabs[position] = .some(nil)
                continue
            case "center": alignment = .center
            case "right", "end": alignment = .right
            case "decimal": alignment = .decimal
            default: alignment = .left
            }
            props.tabs[position] = WordTab(position: position, alignment: alignment)
        }
        if let shd = pPr.child("w:shd") { props.shading = shading(shd) }
        if let pBdr = pPr.child("w:pBdr") {
            var lines = borders(pBdr)
            lines.insideHorizontal = border(pBdr.child("w:between"))
            props.borders = lines
        }
        if let numPr = pPr.child("w:numPr"), let id = numPr.child("w:numId")?.attr("val") {
            props.numbering = (id, numPr.child("w:ilvl")?.attr("val").flatMap(Int.init) ?? 0)
        }
        if let rPr = pPr.child("w:rPr") { props.mark = runProps(rPr) }
        return props
    }

    private func runProps(_ rPr: XElement) -> RunProps {
        var props = RunProps()
        if let fonts = rPr.child("w:rFonts") {
            if let font = fonts.attr("ascii") ?? fonts.attr("hAnsi") { props.font = font }
            else if let theme = fonts.attr("asciiTheme") ?? fonts.attr("hAnsiTheme") {
                props.font = theme.hasPrefix("major") ? majorFont : minorFont
            }
        }
        if let size = WordUnits.halfPoints(rPr.child("w:sz")?.attr("val")) { props.size = size }
        if let element = rPr.child("w:b") { props.bold = element.isOn }
        if let element = rPr.child("w:i") { props.italic = element.isOn }
        if let element = rPr.child("w:caps") { props.caps = element.isOn }
        if let element = rPr.child("w:smallCaps") { props.smallCaps = element.isOn }
        if let element = rPr.child("w:strike") ?? rPr.child("w:dstrike") { props.strike = element.isOn }
        if let element = rPr.child("w:vanish") { props.hidden = element.isOn }
        if let element = rPr.child("w:u") { props.underline = element.isOn }
        if let color = rPr.child("w:color")?.attr("val") { props.color = .some(WordColor(hex: color)) }
        if let name = rPr.child("w:highlight")?.attr("val") { props.highlight = .some(WordColor(highlight: name)) }
        else if let shd = rPr.child("w:shd") { props.highlight = shading(shd) }
        switch rPr.child("w:vertAlign")?.attr("val") {
        case "superscript": props.verticalAlign = .superscript
        case "subscript": props.verticalAlign = .subscriptText
        case "baseline": props.verticalAlign = .baseline
        default: break
        }
        return props
    }

    /// A fill color; `.some(nil)` for an explicit "no fill".
    private func shading(_ shd: XElement) -> WordColor?? {
        let fill = shd.attr("fill")
        if fill == nil || fill == "auto" { return .some(nil) }
        return .some(WordColor(hex: fill))
    }

    private func border(_ element: XElement?) -> WordBorder? {
        guard let element else { return nil }
        if ["nil", "none"].contains(element.attr("val") ?? "") { return WordBorder(width: 0, color: nil) }
        return WordBorder(width: max(0.25, WordUnits.eighthPoints(element.attr("sz")) ?? 0.5), color: WordColor(hex: element.attr("color")))
    }

    private func borders(_ element: XElement) -> WordBorders {
        WordBorders(top: border(element.child("w:top")), left: border(element.child("w:left") ?? element.child("w:start")),
                    bottom: border(element.child("w:bottom")), right: border(element.child("w:right") ?? element.child("w:end")),
                    insideHorizontal: border(element.child("w:insideH")), insideVertical: border(element.child("w:insideV")))
    }

    private func cellMargins(_ element: XElement?) -> [String: Double] {
        guard let element else { return [:] }
        var margins: [String: Double] = [:]
        for (side, names) in [("top", ["w:top"]), ("left", ["w:left", "w:start"]), ("bottom", ["w:bottom"]), ("right", ["w:right", "w:end"])] {
            if let value = names.lazy.compactMap({ element.child($0)?.attr("w") }).first.flatMap({ WordUnits.twips($0) }) {
                margins[side] = value
            }
        }
        return margins
    }

    private func page(_ section: XElement) -> WordPage {
        var page = WordPage()
        if let size = section.child("w:pgSz") {
            page.width = WordUnits.twips(size.attr("w")) ?? page.width
            page.height = WordUnits.twips(size.attr("h")) ?? page.height
        }
        if let margins = section.child("w:pgMar") {
            page.top = abs(WordUnits.twips(margins.attr("top")) ?? page.top)
            page.bottom = abs(WordUnits.twips(margins.attr("bottom")) ?? page.bottom)
            page.left = WordUnits.twips(margins.attr("left") ?? margins.attr("start")) ?? page.left
            page.right = WordUnits.twips(margins.attr("right") ?? margins.attr("end")) ?? page.right
            page.header = WordUnits.twips(margins.attr("header")) ?? page.header
            page.footer = WordUnits.twips(margins.attr("footer")) ?? page.footer
        }
        page.differentFirstPage = section.child("w:titlePg")?.isOn ?? false
        return page
    }

    // MARK: Blocks

    /// The context of a table's cells: its style's paragraph and run formatting.
    struct TableContext {
        var paragraph = ParagraphProps()
        var run = RunProps()
    }

    private mutating func blocks(in container: XElement, rels: [String: String], table: TableContext?) -> [WordBlock] {
        var result: [WordBlock] = []
        var breakBeforeNext = false
        func add(_ block: WordBlock) {
            var block = block
            if breakBeforeNext {
                if case .paragraph(var paragraph) = block {
                    paragraph.format.pageBreakBefore = true
                    block = .paragraph(paragraph)
                } else {
                    var empty = WordParagraph()
                    empty.format.pageBreakBefore = true
                    empty.format.lineSpacing = .exactly(1)
                    result.append(.paragraph(empty))
                }
                breakBeforeNext = false
            }
            result.append(block)
        }
        for child in container.children {
            switch child.name {
            case "w:p":
                let (paragraph, extra) = self.paragraph(child, rels: rels, table: table)
                let onlyBreak = paragraph.inlines.allSatisfy { inline in
                    if case .pageBreak = inline { return true }
                    if case .text(let text, _) = inline { return text.isEmpty }
                    return false
                } && paragraph.inlines.contains(.pageBreak) && paragraph.marker == nil
                if onlyBreak {
                    breakBeforeNext = true                  // a paragraph that only breaks the page
                } else {
                    add(.paragraph(paragraph))
                }
                extra.forEach(add)
                if let type = child.child("w:pPr")?.child("w:sectPr")?.child("w:type")?.attr("val") ?? (child.child("w:pPr")?.child("w:sectPr") != nil ? "nextPage" : nil),
                   type != "continuous" {
                    breakBeforeNext = true                  // a section break: the next section starts a page
                }
            case "w:tbl":
                add(.table(self.table(child, rels: rels)))
            case "w:sdt":
                if let content = child.child("w:sdtContent") { blocks(in: content, rels: rels, table: table).forEach(add) }
            case "w:customXml", "w:ins", "w:moveTo":
                blocks(in: child, rels: rels, table: table).forEach(add)
            case "mc:AlternateContent":
                if let chosen = choose(child) { blocks(in: chosen, rels: rels, table: table).forEach(add) }
            default:
                continue
            }
        }
        return result
    }

    /// Markup compatibility: the first choice this reader knows, else the fallback.
    private func choose(_ alternate: XElement) -> XElement? {
        let known: Set<String> = ["wps", "wpg", "wp14", "w14", "w15", "a14", "wpc", "wpi", "w16se", "v", "w10", "o"]
        for choice in alternate.children("mc:Choice") {
            let needs = (choice.attr("Requires") ?? "").split(separator: " ").map(String.init)
            if needs.allSatisfy(known.contains) { return choice }
        }
        return alternate.child("mc:Fallback")
    }

    private mutating func paragraph(_ p: XElement, rels: [String: String], table: TableContext?) -> (WordParagraph, [WordBlock]) {
        let pPr = p.child("w:pPr")
        let direct = pPr.map(paragraphProps) ?? ParagraphProps()
        let styleID = pPr?.child("w:pStyle")?.attr("val") ?? defaultParagraphStyle
        let styleChain = chain(styleID)

        var props = defaultParagraph
        var runBase = defaultRun
        if let table {
            props.apply(table.paragraph)
            runBase.apply(table.run)
        }
        for style in styleChain {
            props.apply(style.paragraph)
            runBase.apply(style.run)
        }
        let numberingRef = direct.numbering ?? props.numbering
        var marker: WordInline?
        if let numberingRef, let list = listMarker(numberingRef.id, level: numberingRef.level) {
            props.apply(list.paragraph)
            var markerRun = runBase
            markerRun.apply(direct.mark)
            markerRun.apply(list.run)
            if !list.text.isEmpty { marker = .text(list.text, markerRun.resolved) }
        }
        props.apply(direct)
        var mark = runBase
        mark.apply(direct.mark)

        var paragraph = WordParagraph()
        paragraph.styleID = styleID
        paragraph.format = props.resolved(mark: mark.resolved)
        paragraph.marker = marker
        var extra: [WordBlock] = []
        inlines(in: p, into: &paragraph.inlines, extra: &extra, runBase: runBase, rels: rels, table: table)
        return (paragraph, extra)
    }

    /// The runs of a paragraph, and of hyperlinks, insertions and content controls inside it.
    private mutating func inlines(in parent: XElement, into inlines: inout [WordInline], extra: inout [WordBlock],
                                  runBase: RunProps, rels: [String: String], table: TableContext?) {
        for child in parent.children {
            switch child.name {
            case "w:r":
                run(child, into: &inlines, extra: &extra, runBase: runBase, rels: rels, table: table)
            case "w:hyperlink", "w:ins", "w:moveTo", "w:smartTag", "w:customXml", "w:dir", "w:bdo":
                self.inlines(in: child, into: &inlines, extra: &extra, runBase: runBase, rels: rels, table: table)
            case "w:sdt":
                if let content = child.child("w:sdtContent") {
                    self.inlines(in: content, into: &inlines, extra: &extra, runBase: runBase, rels: rels, table: table)
                }
            case "w:fldSimple":
                let instruction = (child.attr("instr") ?? "").trimmingCharacters(in: .whitespaces).uppercased()
                if let field = Self.field(instruction) {
                    let format = child.children("w:r").first.flatMap { $0.child("w:rPr") }.map { formatted(runBase, rPr: $0) } ?? runBase.resolved
                    inlines.append(.field(field, format))
                } else {
                    self.inlines(in: child, into: &inlines, extra: &extra, runBase: runBase, rels: rels, table: table)
                }
            case "mc:AlternateContent":
                if let chosen = choose(child) {
                    self.inlines(in: chosen, into: &inlines, extra: &extra, runBase: runBase, rels: rels, table: table)
                }
            default:
                continue                                         // w:del, w:moveFrom, bookmarks, proofing marks
            }
        }
    }

    private static func field(_ instruction: String) -> WordField? {
        let word = instruction.split(separator: " ").first.map(String.init) ?? ""
        switch word {
        case "PAGE": return .page
        case "NUMPAGES", "SECTIONPAGES": return .numberOfPages
        default: return nil
        }
    }

    private func formatted(_ base: RunProps, rPr: XElement?) -> RunFormat {
        var props = base
        if let styleID = rPr?.child("w:rStyle")?.attr("val") {
            for style in chain(styleID) { props.apply(style.run) }
        }
        if let rPr { props.apply(runProps(rPr)) }
        return props.resolved
    }

    private mutating func run(_ r: XElement, into inlines: inout [WordInline], extra: inout [WordBlock],
                              runBase: RunProps, rels: [String: String], table: TableContext?) {
        let format = formatted(runBase, rPr: r.child("w:rPr"))
        // Inside a field's instructions, or the cached result of PAGE or NUMPAGES, nothing shows.
        var hiding: Bool {
            guard let field = fields.last else { return false }
            return !field.inResult || field.replaced
        }
        for child in r.children {
            switch child.name {
            case "w:fldChar":
                switch child.attr("fldCharType") {
                case "begin": fields.append(("", false, false))
                case "separate":
                    if var field = fields.popLast() {
                        field.inResult = true
                        if let kind = Self.field(field.instruction.trimmingCharacters(in: .whitespaces).uppercased()) {
                            field.replaced = true
                            if fields.allSatisfy({ $0.inResult && !$0.replaced }) { inlines.append(.field(kind, format)) }
                        }
                        fields.append(field)
                    }
                case "end": _ = fields.popLast()
                default: break
                }
            case "w:instrText":
                if var field = fields.popLast() { field.instruction += child.text; fields.append(field) }
            case _ where hiding:
                continue
            case "w:t":
                if !format.hidden { inlines.append(.text(child.text, format)) }
            case "w:tab", "w:ptab":
                inlines.append(.tab(format))
            case "w:br":
                inlines.append(child.attr("type") == "page" ? .pageBreak : .lineBreak)
            case "w:cr":
                inlines.append(.lineBreak)
            case "w:noBreakHyphen":
                inlines.append(.text("\u{2011}", format))
            case "w:sym":
                let code = child.attr("char").flatMap { UInt32($0, radix: 16) } ?? 0
                inlines.append(.text(Self.bullet(String(UnicodeScalar(code).map(Character.init) ?? "•"), font: child.attr("font")), format))
            case "w:drawing", "w:pict", "w:object":
                drawing(child, into: &inlines, extra: &extra, rels: rels, table: table)
            case "mc:AlternateContent":
                if let chosen = choose(child) {
                    let wrapper = XElement(name: "w:r", attributes: [:])
                    wrapper.children = (r.child("w:rPr").map { [$0] } ?? []) + chosen.children
                    run(wrapper, into: &inlines, extra: &extra, runBase: runBase, rels: rels, table: table)
                }
            default:
                continue
            }
        }
    }

    /// A picture (DrawingML or VML) and any text box inside a drawing.
    private mutating func drawing(_ element: XElement, into inlines: inout [WordInline], extra: inout [WordBlock],
                                  rels: [String: String], table: TableContext?) {
        let frame = element.descendants("wp:inline").first ?? element.descendants("wp:anchor").first
        if let blip = element.descendants("a:blip").first, let id = blip.attr("embed") ?? blip.attr("link"),
           let path = rels[id], let data = parts[path] {
            images[path] = data
            let extent = frame?.child("wp:extent")
            var image = WordImage(part: path, width: WordUnits.emu(extent?.attr("cx")) ?? 72, height: WordUnits.emu(extent?.attr("cy")) ?? 72)
            if let anchor = frame, anchor.name == "wp:anchor" { image.floating = float(anchor) }
            inlines.append(.image(image))
        } else if let imagedata = element.descendants("v:imagedata").first, let id = imagedata.attr("id"),
                  let path = rels[id], let data = parts[path] {
            images[path] = data
            let style = element.descendants("v:shape").first?.attr("style") ?? ""
            inlines.append(.image(WordImage(part: path, width: Self.cssLength(style, "width") ?? 72, height: Self.cssLength(style, "height") ?? 72)))
        }
        // Text boxes: their text follows the paragraph they're anchored in.
        for content in element.descendants("w:txbxContent") {
            extra += blocks(in: content, rels: rels, table: table)
        }
    }

    private func float(_ anchor: XElement) -> WordFloat {
        var float = WordFloat()
        float.overText = anchor.child("wp:wrapNone") != nil
        float.behindText = anchor.attr("behindDoc") == "1" || anchor.attr("behindDoc") == "true"
        if let position = anchor.child("wp:positionH") {
            float.horizontalFrame = Self.frame(position.attr("relativeFrom"), otherwise: .column)
            float.x = WordUnits.emu(position.child("wp:posOffset")?.text) ?? 0
            float.horizontalAlign = position.child("wp:align").flatMap { WordFloat.Align(rawValue: $0.text) }
        }
        if let position = anchor.child("wp:positionV") {
            float.verticalFrame = Self.frame(position.attr("relativeFrom"), otherwise: .paragraph)
            float.y = WordUnits.emu(position.child("wp:posOffset")?.text) ?? 0
            float.verticalAlign = position.child("wp:align").flatMap { WordFloat.Align(rawValue: $0.text) }
        }
        return float
    }

    /// What a placed picture's position is measured from. The margin areas themselves ("leftMargin")
    /// are measured from the paper's edge, as near as this gets.
    private static func frame(_ value: String?, otherwise fallback: WordFloat.Frame) -> WordFloat.Frame {
        guard let value else { return fallback }
        if let frame = WordFloat.Frame(rawValue: value) { return frame }
        switch value {
        case "insideMargin", "outsideMargin": return .margin
        case "leftMargin", "rightMargin", "topMargin", "bottomMargin": return .page
        default: return fallback
        }
    }

    /// "width:123.4pt;height:56pt" (VML) → points.
    private static func cssLength(_ style: String, _ property: String) -> Double? {
        for declaration in style.split(separator: ";") {
            let pair = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2, pair[0] == property else { continue }
            let value = pair[1]
            if value.hasSuffix("pt") { return Double(value.dropLast(2)) }
            if value.hasSuffix("in") { return Double(value.dropLast(2)).map { $0 * 72 } }
            if value.hasSuffix("px") { return Double(value.dropLast(2)).map { $0 * 0.75 } }
            return Double(value)
        }
        return nil
    }

    // MARK: Tables

    private mutating func table(_ tbl: XElement, rels: [String: String]) -> WordTable {
        var table = WordTable()
        let tblPr = tbl.child("w:tblPr")
        let styleChain = chain(tblPr?.child("w:tblStyle")?.attr("val") ?? defaultTableStyle)
        var context = TableContext()
        var firstRowRun: RunProps?
        var firstRowShading: WordColor??
        var styleBorders = WordBorders()
        var margins: [String: Double] = [:]
        for style in styleChain {
            context.paragraph.apply(style.paragraph)
            context.run.apply(style.run)
            if let borders = style.tableBorders { styleBorders = Self.merge(styleBorders, borders) }
            margins.merge(style.tableCellMargins) { $1 }
            if let run = style.firstRowRun { firstRowRun = run }
            if let shading = style.firstRowShading { firstRowShading = shading }
        }
        if let direct = tblPr?.child("w:tblBorders") { styleBorders = Self.merge(styleBorders, borders(direct)) }
        table.borders = styleBorders
        margins.merge(cellMargins(tblPr?.child("w:tblCellMar"))) { $1 }
        table.cellMargins = WordInsets(top: margins["top"] ?? 0, left: margins["left"] ?? 5.4,
                                       bottom: margins["bottom"] ?? 0, right: margins["right"] ?? 5.4)
        table.cellSpacing = WordUnits.twips(tblPr?.child("w:tblCellSpacing")?.attr("w")) ?? 0
        switch tblPr?.child("w:jc")?.attr("val") {
        case "center": table.alignment = .center
        case "right", "end": table.alignment = .right
        default: table.alignment = .left
        }
        table.indent = WordUnits.twips(tblPr?.child("w:tblInd")?.attr("w")) ?? 0
        table.columns = tbl.child("w:tblGrid")?.children("w:gridCol").compactMap { WordUnits.twips($0.attr("w")) } ?? []
        let look = tblPr?.child("w:tblLook")
        let headerStyled = look?.attr("firstRow") == "1" || (look?.attr("val").flatMap { Int($0, radix: 16) }.map { $0 & 0x20 != 0 } ?? false)

        var rowElements: [XElement] = []
        func collectRows(_ parent: XElement) {
            for child in parent.children {
                switch child.name {
                case "w:tr": rowElements.append(child)
                case "w:sdt": child.child("w:sdtContent").map(collectRows)
                case "w:customXml": collectRows(child)
                default: continue
                }
            }
        }
        collectRows(tbl)
        for (index, tr) in rowElements.enumerated() {
            var row = WordRow()
            row.minimumHeight = WordUnits.twips(tr.child("w:trPr")?.child("w:trHeight")?.attr("val")) ?? 0
            var rowContext = context
            if index == 0, headerStyled, let run = firstRowRun { rowContext.run.apply(run) }
            for tc in tr.children("w:tc") {
                var cell = WordCell()
                let tcPr = tc.child("w:tcPr")
                cell.columnSpan = max(1, tcPr?.child("w:gridSpan")?.attr("val").flatMap(Int.init) ?? 1)
                if let merge = tcPr?.child("w:vMerge") { cell.verticalMerge = merge.attr("val") == "restart" ? .start : .continued }
                if let shd = tcPr?.child("w:shd") { cell.shading = shading(shd) ?? nil }
                else if index == 0, headerStyled, let shading = firstRowShading { cell.shading = shading }
                cell.borders = tcPr?.child("w:tcBorders").map(borders)
                switch tcPr?.child("w:vAlign")?.attr("val") {
                case "center": cell.verticalAlign = .center
                case "bottom": cell.verticalAlign = .bottom
                default: cell.verticalAlign = .top
                }
                cell.blocks = blocks(in: tc, rels: rels, table: rowContext)
                row.cells.append(cell)
            }
            table.rows.append(row)
        }
        return table
    }

    private static func merge(_ base: WordBorders, _ top: WordBorders) -> WordBorders {
        WordBorders(top: top.top ?? base.top, left: top.left ?? base.left, bottom: top.bottom ?? base.bottom,
                    right: top.right ?? base.right, insideHorizontal: top.insideHorizontal ?? base.insideHorizontal,
                    insideVertical: top.insideVertical ?? base.insideVertical)
    }
}
