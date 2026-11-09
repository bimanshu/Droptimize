import AppKit
import CoreText
import Foundation
import ImageIO

/// Draws a `WordDocument` (read by `WordReader`) onto PDF pages (CORE.md §7c), so a Word file
/// keeps its pictures, styles, spacing, lists, tables, headers and footers without Word or Pages.
///
/// TextKit breaks each paragraph into lines; everything else is placed here, the way Word does:
/// lines and table rows go down the page, a page breaks between them, headings stay with the
/// paragraph after them, a paragraph doesn't leave one line alone at either end of a page, and
/// headers and footers are drawn on every page with its number. Coordinates are in points with y
/// growing down the page, as TextKit draws.
enum WordPDFRenderer {
    static func render(_ document: WordDocument, title: String, to output: URL) throws {
        try Composer(document).write(to: output, title: title)
    }
}

// MARK: Pieces of a page

/// The paper, its margins and where the header and footer start, all in points.
private struct Geometry {
    var size: CGSize
    var top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat
    var header: CGFloat, footer: CGFloat
    var width: CGFloat { size.width - left - right }
}

/// One page as it's drawn: its number and how many there are, for page-number fields.
private struct Sheet {
    var geometry: Geometry
    var number = 1
    var count = 1
}

/// Where something is drawn: its top-left corner, the column it sits in, and the page.
private struct Spot {
    let context: CGContext
    let origin: CGPoint
    let width: CGFloat
    let sheet: Sheet
}

/// A line of a paragraph or a few rows of a table: the smallest thing a page can't split.
private final class Unit {
    let height: CGFloat
    let draw: (Spot) -> Void

    init(height: CGFloat, draw: @escaping (Spot) -> Void) {
        self.height = height
        self.draw = draw
    }
}

/// A paragraph's lines (or a table's rows) and the rules for placing them on pages.
private final class Group {
    var units: [Unit] = []
    var spaceBefore: CGFloat = 0
    var spaceAfter: CGFloat = 0
    var keepWithNext = false
    var keepLines = false
    var pageBreakBefore = false
    /// No single line of it left alone at the foot or the head of a page.
    var widowControl = false
    /// Pictures placed on the page with no text moving out of their way, anchored here.
    var floats: [WordImage] = []

    var height: CGFloat { units.reduce(0) { $0 + $1.height } }
    var total: CGFloat { spaceBefore + height + spaceAfter }
}

/// A picture in a line of text. TextKit only leaves room for it (an invisible space as wide as
/// the picture, in a font as tall as it), and it's drawn here, upright: no AppKit image cells.
private final class PictureBox: NSObject {
    let image: CGImage?
    let size: CGSize
    init(_ image: CGImage?, size: CGSize) {
        self.image = image
        self.size = size
    }
}

private extension NSAttributedString.Key {
    static let droptimizePicture = NSAttributedString.Key("DroptimizeWordPicture")
}

// MARK: The composer

private final class Composer {
    let document: WordDocument
    let geometry: Geometry
    private var pictures: [String: CGImage] = [:]

    init(_ document: WordDocument) {
        self.document = document
        let page = document.page
        var geometry = Geometry(size: CGSize(width: page.width, height: page.height),
                                top: page.top, bottom: page.bottom, left: page.left, right: page.right,
                                header: page.header, footer: page.footer)
        if geometry.size.width < geometry.left + geometry.right + 72 || geometry.size.height < geometry.top + geometry.bottom + 72 {
            // Nonsense from the file: the usual paper and one-inch margins.
            let paper = Locale.current.measurementSystem == .us ? DocumentTuning.letter : DocumentTuning.a4
            geometry = Geometry(size: CGSize(width: paper.width, height: paper.height),
                                top: 72, bottom: 72, left: 72, right: 72, header: 36, footer: 36)
        }
        self.geometry = geometry
    }

    func write(to output: URL, title: String) throws {
        let body = stack(document.blocks, width: geometry.width) { _ in "" }
        let pages = paginate(body)

        var media = CGRect(origin: .zero, size: geometry.size)
        let info: [CFString: Any] = [kCGPDFContextCreator: "Droptimize", kCGPDFContextTitle: title]
        guard let context = CGContext(output as CFURL, mediaBox: &media, info as CFDictionary) else { throw JobError.cantSave }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        for (index, page) in pages.enumerated() {
            let sheet = Sheet(geometry: geometry, number: index + 1, count: pages.count)
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: geometry.size.height)            // top-down, as TextKit draws
            context.scaleBy(x: 1, y: -1)
            let fields: (WordField) -> String = { $0 == .page ? "\(sheet.number)" : "\(sheet.count)" }
            if let blocks = header(for: index) {
                let groups = stack(blocks, width: geometry.width, fields: fields)
                draw(groups, at: CGPoint(x: geometry.left, y: geometry.header), width: geometry.width, sheet: sheet, context: context)
            }
            if let blocks = footer(for: index) {
                let groups = stack(blocks, width: geometry.width, fields: fields)
                let top = geometry.size.height - geometry.footer - height(of: groups)
                draw(groups, at: CGPoint(x: geometry.left, y: top), width: geometry.width, sheet: sheet, context: context)
            }
            for float in page.floats where float.behind { paint(float.image, in: float.rect, context: context) }
            for placed in page.placed {
                placed.unit.draw(Spot(context: context, origin: placed.origin, width: geometry.width, sheet: sheet))
            }
            for float in page.floats where !float.behind { paint(float.image, in: float.rect, context: context) }
            context.restoreGState()
            context.endPDFPage()
        }
        NSGraphicsContext.restoreGraphicsState()
        context.closePDF()
    }

    private func header(for page: Int) -> [WordBlock]? {
        page == 0 && document.page.differentFirstPage ? document.firstHeader : document.header
    }

    private func footer(for page: Int) -> [WordBlock]? {
        page == 0 && document.page.differentFirstPage ? document.firstFooter : document.footer
    }

    // MARK: Pages

    private struct Page {
        var placed: [(unit: Unit, origin: CGPoint)] = []
        var floats: [(image: CGImage?, rect: CGRect, behind: Bool)] = []
    }

    /// Where the body text may go on a page: inside the margins, and clear of a header or footer
    /// that runs into them.
    private func bodyArea(_ page: Int) -> (top: CGFloat, bottom: CGFloat) {
        let fields: (WordField) -> String = { _ in "9" }
        var top = geometry.top
        var bottom = geometry.size.height - geometry.bottom
        if let blocks = header(for: page) {
            top = max(top, geometry.header + height(of: stack(blocks, width: geometry.width, fields: fields)))
        }
        if let blocks = footer(for: page) {
            bottom = min(bottom, geometry.size.height - geometry.footer - height(of: stack(blocks, width: geometry.width, fields: fields)))
        }
        if bottom - top < 72 { return (geometry.top, geometry.size.height - geometry.bottom) }
        return (top, bottom)
    }

    private func paginate(_ groups: [Group]) -> [Page] {
        let areas = [bodyArea(0), bodyArea(1)]                     // the first page, and every other
        func area(_ page: Int) -> (top: CGFloat, bottom: CGFloat) { areas[min(page, 1)] }
        let fullHeight = area(1).bottom - area(1).top

        var pages = [Page()]
        var y = area(0).top
        var empty = true                    // nothing on this page yet
        var afterHardBreak = true           // the page began with the document or a page break
        func newPage(hard: Bool) {
            guard pages.count < DocumentTuning.maxPages else { return }
            pages.append(Page())
            y = area(pages.count - 1).top
            empty = true
            afterHardBreak = hard
        }
        var bottom: CGFloat { area(pages.count - 1).bottom }

        for (index, group) in groups.enumerated() {
            if group.pageBreakBefore {
                if empty { afterHardBreak = true } else { newPage(hard: true) }
            }
            // A heading (and anything else kept with the next paragraph) goes where that one starts.
            var chain = (empty && !afterHardBreak ? 0 : group.spaceBefore) + group.height
            if group.keepWithNext {
                chain += group.spaceAfter
                var next = index + 1
                while next < groups.count, groups[next - 1].keepWithNext {
                    let following = groups[next]
                    if following.pageBreakBefore { break }
                    if following.keepWithNext {
                        chain += following.total
                    } else {
                        let lines = following.units.prefix(following.widowControl ? 2 : 1)
                        chain += following.spaceBefore + lines.reduce(0) { $0 + $1.height }
                    }
                    next += 1
                }
            }
            let together = group.keepWithNext || group.keepLines || (group.widowControl && group.units.count <= 3)
            if together, !empty, y + chain > bottom, chain <= fullHeight { newPage(hard: false) }

            var anchored = false
            let count = group.units.count
            for (line, unit) in group.units.enumerated() {
                var before = line == 0 && !(empty && !afterHardBreak) ? group.spaceBefore : 0
                var need = before + unit.height
                if group.widowControl, count >= 4 {
                    if line == 0 { need += group.units[1].height }                          // no orphan
                    if line == count - 2 { need += group.units[count - 1].height }          // no widow
                }
                if !empty, y + need > bottom {
                    newPage(hard: false)
                    before = 0
                }
                let origin = CGPoint(x: geometry.left, y: y + before)
                pages[pages.count - 1].placed.append((unit, origin))
                if !anchored {
                    anchored = true
                    for image in group.floats {
                        let rect = place(image, anchor: origin.y, column: CGRect(x: geometry.left, y: origin.y, width: geometry.width, height: 0),
                                         sheet: Sheet(geometry: geometry))
                        pages[pages.count - 1].floats.append((picture(image), rect, image.floating?.behindText ?? false))
                    }
                }
                y += before + unit.height
                empty = false
            }
            y += group.spaceAfter
        }
        return pages
    }

    // MARK: Stacks of blocks

    private func height(of groups: [Group]) -> CGFloat {
        groups.reduce(0) { $0 + $1.total }
    }

    /// A stack drawn as it is, with no pages: a table cell, a header or a footer.
    private func draw(_ groups: [Group], at origin: CGPoint, width: CGFloat, sheet: Sheet, context: CGContext) {
        var y = origin.y
        for group in groups {
            y += group.spaceBefore
            let column = CGRect(x: origin.x, y: y, width: width, height: 0)
            for image in group.floats where image.floating?.behindText ?? false {
                paint(picture(image), in: place(image, anchor: y, column: column, sheet: sheet), context: context)
            }
            let top = y
            for unit in group.units {
                unit.draw(Spot(context: context, origin: CGPoint(x: origin.x, y: y), width: width, sheet: sheet))
                y += unit.height
            }
            for image in group.floats where !(image.floating?.behindText ?? false) {
                paint(picture(image), in: place(image, anchor: top, column: column, sheet: sheet), context: context)
            }
            y += group.spaceAfter
        }
    }

    /// Blocks laid out in a column `width` wide. `fields` gives page numbers their text.
    private func stack(_ blocks: [WordBlock], width: CGFloat, fields: @escaping (WordField) -> String) -> [Group] {
        func paragraphAt(_ index: Int) -> WordParagraph? {
            guard blocks.indices.contains(index), case .paragraph(let paragraph) = blocks[index] else { return nil }
            return paragraph
        }
        var groups: [Group] = []
        for (index, block) in blocks.enumerated() {
            switch block {
            case .table(let table):
                groups += tableGroups(table, width: width, fields: fields)
            case .paragraph(let paragraph):
                let format = paragraph.format
                let previous = paragraphAt(index - 1), next = paragraphAt(index + 1)
                var before = CGFloat(format.spaceBefore), after = CGFloat(format.spaceAfter)
                if format.contextualSpacing, let previous, previous.styleID == paragraph.styleID { before = 0 }
                if format.contextualSpacing, let next, next.styleID == paragraph.styleID { after = 0 }
                // Paragraphs with the same lines around them share one box.
                let ruleAbove = format.borders != nil && previous?.format.borders != format.borders
                let ruleBelow = format.borders != nil && next?.format.borders != format.borders
                let pieces = Self.split(paragraph)
                for (number, piece) in pieces.enumerated() {
                    let first = number == 0, last = number == pieces.count - 1
                    let group = paragraphGroup(piece.paragraph, width: width, fields: fields,
                                               ruleAbove: ruleAbove && first, ruleBelow: ruleBelow && last)
                    group.spaceBefore = first ? before : 0
                    group.spaceAfter = last ? after : 0
                    group.pageBreakBefore = piece.breakBefore
                    group.keepWithNext = last && format.keepWithNext
                    groups.append(group)
                }
            }
        }
        return groups
    }

    /// A paragraph cut where it breaks the page: each piece after a break starts a new page.
    private static func split(_ paragraph: WordParagraph) -> [(paragraph: WordParagraph, breakBefore: Bool)] {
        guard paragraph.inlines.contains(.pageBreak) else { return [(paragraph, paragraph.format.pageBreakBefore)] }
        var pieces: [(paragraph: WordParagraph, breakBefore: Bool)] = []
        var current = paragraph
        current.inlines = []
        var breakBefore = paragraph.format.pageBreakBefore
        for inline in paragraph.inlines {
            if inline == .pageBreak {
                let blank = current.marker == nil && current.inlines.allSatisfy { piece in
                    if case .text(let text, _) = piece { return text.isEmpty }
                    return false
                }
                if blank && pieces.isEmpty {
                    breakBefore = true                          // the break comes first: no empty line
                } else {
                    pieces.append((current, breakBefore))
                    breakBefore = true
                }
                current = paragraph
                current.inlines = []
                current.marker = nil
                current.format.firstLine = 0                    // the same paragraph, carried on
            } else {
                current.inlines.append(inline)
            }
        }
        pieces.append((current, breakBefore))
        return pieces
    }

    // MARK: Paragraphs

    private func paragraphGroup(_ paragraph: WordParagraph, width: CGFloat, fields: (WordField) -> String,
                                ruleAbove: Bool, ruleBelow: Bool) -> Group {
        let group = Group()
        let format = paragraph.format
        group.keepLines = format.keepLines
        group.widowControl = true

        var hasWords = paragraph.marker != nil
        var inlinePictures: [WordImage] = []
        for inline in paragraph.inlines {
            switch inline {
            case .image(let image):
                if let float = image.floating {
                    // Text wraps around it in Word; here it gets the line where it's anchored.
                    if float.overText { group.floats.append(image) } else { group.units.append(pictureLine(image, width: width)) }
                } else {
                    inlinePictures.append(image)
                }
            case .text(let text, _): if !text.isEmpty { hasWords = true }
            case .tab, .lineBreak, .field: hasWords = true
            case .pageBreak: break
            }
        }
        if !hasWords {
            // A logo or a chart on its own: rows of pictures, no text to lay out.
            if !inlinePictures.isEmpty {
                group.units += pictureRows(inlinePictures, format: format, width: width)
                return group
            }
            if !group.units.isEmpty { return group }
        }

        let shift = CGFloat(min(0, format.indentLeft, format.indentLeft + format.firstLine))   // into the margin
        let containerWidth = max(width - shift - CGFloat(min(0, format.indentRight)), 1)
        let text = attributedText(paragraph, width: width, shift: shift, fields: fields)
        let layout = TextLayout(text, width: containerWidth, justified: format.alignment == .justified,
                                rightEdge: containerWidth - CGFloat(max(0, format.indentRight)))
        let lines = layout.lines
        let left = CGFloat(max(0, format.indentLeft)), right = CGFloat(max(0, format.indentRight))
        let borders = format.borders
        for (index, line) in lines.enumerated() {
            let first = index == 0, last = index == lines.count - 1
            group.units.append(Unit(height: line.rect.height) { spot in
                let context = spot.context
                let box = CGRect(x: spot.origin.x + left, y: spot.origin.y, width: max(spot.width - left - right, 0), height: line.rect.height)
                if let shading = format.shading {
                    context.setFillColor(Self.color(shading).cgColor)
                    context.fill(box)
                }
                layout.draw(line, at: CGPoint(x: spot.origin.x + shift, y: spot.origin.y - line.rect.minY), context: context)
                if let borders {
                    let outer = box.insetBy(dx: -4, dy: 0)
                    if first, ruleAbove { Self.stroke(borders.top, from: CGPoint(x: outer.minX, y: outer.minY - 1), to: CGPoint(x: outer.maxX, y: outer.minY - 1), context) }
                    if last, ruleBelow { Self.stroke(borders.bottom, from: CGPoint(x: outer.minX, y: outer.maxY + 1), to: CGPoint(x: outer.maxX, y: outer.maxY + 1), context) }
                    Self.stroke(borders.left, from: CGPoint(x: outer.minX, y: outer.minY - (first ? 1 : 0)), to: CGPoint(x: outer.minX, y: outer.maxY + (last ? 1 : 0)), context)
                    Self.stroke(borders.right, from: CGPoint(x: outer.maxX, y: outer.minY - (first ? 1 : 0)), to: CGPoint(x: outer.maxX, y: outer.maxY + (last ? 1 : 0)), context)
                }
            })
        }
        return group
    }

    /// Pictures in a paragraph with no text: side by side on lines, sitting on the baseline as in
    /// Word, the line spaced like the paragraph.
    private func pictureRows(_ images: [WordImage], format: ParagraphFormat, width: CGFloat) -> [Unit] {
        let left = CGFloat(max(0, format.indentLeft)), right = CGFloat(max(0, format.indentRight))
        let available = max(width - left - right, 1)
        let descent = abs(Typeface.font(format.markFormat).font.descender)
        var rows: [[(image: WordImage, size: CGSize)]] = []
        var current: [(image: WordImage, size: CGSize)] = []
        var used: CGFloat = 0
        for image in images {
            let scale = min(1, available / max(CGFloat(image.width), 1))
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            if !current.isEmpty, used + size.width > available {
                rows.append(current)
                current = []
                used = 0
            }
            current.append((image, size))
            used += size.width
        }
        if !current.isEmpty { rows.append(current) }
        return rows.map { row in
            let rowWidth = row.reduce(0) { $0 + $1.size.width }
            let natural = (row.map(\.size.height).max() ?? 0) + descent
            let height: CGFloat
            switch format.lineSpacing {
            case .multiple(let multiple): height = natural * CGFloat(max(multiple, 1))
            case .exactly(let exact): height = max(natural, CGFloat(exact))       // the whole picture, not clipped
            case .atLeast(let least): height = max(natural, CGFloat(least))
            }
            let offset: CGFloat
            switch format.alignment {
            case .center: offset = max(0, (available - rowWidth) / 2)
            case .right: offset = max(0, available - rowWidth)
            case .left, .justified: offset = 0
            }
            let pictures = row.map { (image: picture($0.image), size: $0.size) }
            let baseline = height - descent
            return Unit(height: height) { [weak self] spot in
                var x = spot.origin.x + left + offset
                for item in pictures {
                    let rect = CGRect(x: x, y: spot.origin.y + baseline - item.size.height, width: item.size.width, height: item.size.height)
                    self?.paint(item.image, in: rect, context: spot.context)
                    x += item.size.width
                }
            }
        }
    }

    /// A picture that text wraps around in Word, on a line of its own at its own position across.
    private func pictureLine(_ image: WordImage, width: CGFloat) -> Unit {
        let scale = min(1, geometry.size.width / max(CGFloat(image.width), 1))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let float = image.floating ?? WordFloat()
        let drawing = picture(image)
        let page = geometry
        return Unit(height: size.height + 4) { [weak self] spot in
            let across: (min: CGFloat, max: CGFloat)
            switch float.horizontalFrame {
            case .page: across = (0, page.size.width)
            case .margin: across = (page.left, page.size.width - page.right)
            default: across = (spot.origin.x, spot.origin.x + spot.width)
            }
            var x: CGFloat
            switch float.horizontalAlign {
            case .center?: x = (across.min + across.max - size.width) / 2
            case .right?, .outside?: x = across.max - size.width
            case .left?, .inside?: x = across.min
            default: x = across.min + CGFloat(float.x)
            }
            x = min(max(x, 0), page.size.width - size.width)
            self?.paint(drawing, in: CGRect(origin: CGPoint(x: x, y: spot.origin.y + 2), size: size), context: spot.context)
        }
    }

    private func attributedText(_ paragraph: WordParagraph, width: CGFloat, shift: CGFloat,
                                fields: (WordField) -> String) -> NSAttributedString {
        let format = paragraph.format
        let style = NSMutableParagraphStyle()
        switch format.alignment {
        case .left: style.alignment = .left
        case .center: style.alignment = .center
        case .right: style.alignment = .right
        case .justified: style.alignment = .left           // justified by TextLayout, the way Word does
        }
        style.headIndent = CGFloat(format.indentLeft) - shift
        style.firstLineHeadIndent = CGFloat(format.indentLeft + format.firstLine) - shift
        style.tailIndent = -CGFloat(max(0, format.indentRight))
        switch format.lineSpacing {
        case .multiple(let multiple): style.lineHeightMultiple = CGFloat(max(multiple, 0.5))
        case .exactly(let height): style.minimumLineHeight = CGFloat(height); style.maximumLineHeight = CGFloat(height)
        case .atLeast(let height): style.minimumLineHeight = CGFloat(height)
        }
        var stops = format.tabStops.map { tab -> NSTextTab in
            let location = CGFloat(tab.position) - shift
            switch tab.alignment {
            case .left: return NSTextTab(textAlignment: .left, location: location, options: [:])
            case .center: return NSTextTab(textAlignment: .center, location: location, options: [:])
            case .right: return NSTextTab(textAlignment: .right, location: location, options: [:])
            case .decimal:
                return NSTextTab(textAlignment: .right, location: location,
                                 options: [.columnTerminators: NSTextTab.columnTerminators(for: Locale.current)])
            }
        }
        // A hanging indent works as a tab stop: a list's text lines up after its number.
        if format.firstLine < 0, !format.tabStops.contains(where: { abs($0.position - format.indentLeft) < 0.5 }) {
            stops.append(NSTextTab(textAlignment: .left, location: CGFloat(format.indentLeft) - shift, options: [:]))
        }
        style.tabStops = stops.sorted { $0.location < $1.location }
        style.defaultTabInterval = 36
        style.lineBreakMode = .byWordWrapping

        let text = NSMutableAttributedString()
        var lastFormat = format.markFormat
        func append(_ string: String, _ run: RunFormat) {
            text.append(Self.styled(string, run))
            lastFormat = run
        }
        if case .text(let marker, let run)? = paragraph.marker {
            append(marker, run)
            append("\t", run)
        }
        let available = max(width - CGFloat(max(0, format.indentLeft)) - CGFloat(max(0, format.indentRight)) - 1, 1)
        for inline in paragraph.inlines {
            switch inline {
            case .text(let string, let run): append(string, run)
            case .tab(let run): append("\t", run)
            case .lineBreak: append("\u{2028}", lastFormat)
            case .field(let field, let run): append(fields(field), run)
            case .image(let image) where image.floating == nil:
                let scale = min(1, available / max(CGFloat(image.width), 1))
                let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                // A figure space in a font whose ascent is the picture's height, widened to its width.
                let base = Typeface.font(lastFormat).font
                let ascent = max(base.ascender / max(base.pointSize, 1), 0.5)
                let font = NSFont(descriptor: base.fontDescriptor, size: max(size.height / ascent, 1)) ?? base
                let space = ("\u{2007}" as NSString).size(withAttributes: [.font: font]).width
                text.append(NSAttributedString(string: "\u{2007}", attributes: [
                    .font: font, .kern: size.width - space,
                    .droptimizePicture: PictureBox(picture(image), size: size),
                ]))
            default: continue
            }
        }
        if text.length == 0 { append(" ", format.markFormat) }       // an empty paragraph still has its line
        text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
        return text
    }

    /// A run's text with its font, color and decoration.
    private static func styled(_ string: String, _ run: RunFormat) -> NSAttributedString {
        var size = CGFloat(max(run.size, 1))
        var offset: CGFloat = 0
        switch run.verticalAlign {
        case .superscript: offset = size * 0.33; size *= 0.65
        case .subscriptText: offset = -size * 0.14; size *= 0.65
        case .baseline: break
        }
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: run.color.map(color) ?? NSColor.black,
        ]
        if offset != 0 { attributes[.baselineOffset] = offset }
        if run.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if run.strike { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let highlight = run.highlight { attributes[.backgroundColor] = color(highlight) }

        func with(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
            var scaled = run
            scaled.size = Double(size)
            let face = Typeface.font(scaled)
            var all = attributes
            all[.font] = face.font
            if face.fakeBold { all[.strokeWidth] = -3.0 }            // a family with no bold face
            if face.fakeItalic { all[.obliqueness] = 0.2 }
            return all
        }
        if run.caps { return NSAttributedString(string: string.uppercased(), attributes: with(size)) }
        guard run.smallCaps else { return NSAttributedString(string: string, attributes: with(size)) }
        // Small capitals: lower-case letters as smaller capitals.
        let result = NSMutableAttributedString()
        var chunk = "", chunkIsLower = false
        func flush() {
            guard !chunk.isEmpty else { return }
            result.append(NSAttributedString(string: chunkIsLower ? chunk.uppercased() : chunk,
                                             attributes: with(chunkIsLower ? size * 0.8 : size)))
            chunk = ""
        }
        for character in string {
            let lower = character.isLowercase
            if lower != chunkIsLower { flush(); chunkIsLower = lower }
            chunk.append(character)
        }
        flush()
        return result
    }

    // MARK: Tables

    private struct CellLayout {
        var row: Int, column: Int, span: Int, rowSpan: Int
        var cell: WordCell
        var content: [Group]
        var contentWidth: CGFloat
        var height: CGFloat
    }

    /// Rows go down the page; rows joined by a merged cell stay on one page together.
    private func tableGroups(_ table: WordTable, width available: CGFloat, fields: @escaping (WordField) -> String) -> [Group] {
        let rows = table.rows
        guard !rows.isEmpty else { return [] }
        var columnOf: [[Int]] = []                           // each cell's first grid column
        for row in rows {
            var column = row.gridBefore
            var list: [Int] = []
            for cell in row.cells {
                list.append(column)
                column += max(1, cell.columnSpan)
            }
            columnOf.append(list)
        }
        var needed = 1                                       // grid columns the rows fill
        for (index, list) in columnOf.enumerated() {
            needed = max(needed, (list.last ?? 0) + max(1, rows[index].cells.last?.columnSpan ?? 1))
        }
        var columns = table.columns.map { CGFloat($0) }.filter { $0 > 0 }
        if columns.count < needed {
            let known = columns.reduce(0, +)
            let share = max((available - known) / CGFloat(needed - columns.count), 18)
            columns += Array(repeating: columns.isEmpty ? available / CGFloat(needed) : share, count: needed - columns.count)
        }
        var starts: [CGFloat] = []
        var running: CGFloat = 0
        for column in columns { starts.append(running); running += column }
        let total = running
        func span(_ column: Int, _ count: Int) -> CGFloat {
            guard column < columns.count else { return 0 }
            return columns[column..<min(column + count, columns.count)].reduce(0, +)
        }
        let left: CGFloat
        switch table.alignment {
        case .left: left = CGFloat(table.indent)
        case .center: left = (available - total) / 2
        case .right: left = available - total
        }
        let spacing = CGFloat(table.cellSpacing)
        let margins = table.cellMargins

        var cells: [CellLayout] = []
        var heights = rows.map { CGFloat($0.minimumHeight) }
        for (r, row) in rows.enumerated() {
            for (k, cell) in row.cells.enumerated() where cell.verticalMerge != .continued {
                let column = columnOf[r][k]
                let count = max(1, cell.columnSpan)
                var rowSpan = 1
                if cell.verticalMerge == .start {
                    var next = r + 1
                    while next < rows.count, let below = columnOf[next].firstIndex(of: column),
                          rows[next].cells[below].verticalMerge == .continued {
                        rowSpan += 1
                        next += 1
                    }
                }
                let contentWidth = max(span(column, count) - CGFloat(margins.left + margins.right) - 2 * spacing, 1)
                let content = stack(cell.blocks, width: contentWidth, fields: fields)
                let cellHeight = height(of: content) + CGFloat(margins.top + margins.bottom) + 2 * spacing
                cells.append(CellLayout(row: r, column: column, span: count, rowSpan: rowSpan, cell: cell,
                                        content: content, contentWidth: contentWidth, height: cellHeight))
                if rowSpan == 1 { heights[r] = max(heights[r], cellHeight) }
            }
        }
        for cell in cells where cell.rowSpan > 1 {                // a merged cell grows its last row if it must
            let have = heights[cell.row..<(cell.row + cell.rowSpan)].reduce(0, +)
            if cell.height > have { heights[cell.row + cell.rowSpan - 1] += cell.height - have }
        }

        let borders = table.borders
        var groups: [Group] = []
        var start = 0
        while start < rows.count {
            var end = start + 1
            var grew = true
            while grew {
                grew = false
                for cell in cells where cell.row >= start && cell.row < end && cell.row + cell.rowSpan > end {
                    end = cell.row + cell.rowSpan
                    grew = true
                }
            }
            let range = start..<end
            var tops: [Int: CGFloat] = [:]
            var y: CGFloat = 0
            for row in range { tops[row] = y; y += heights[row] }
            let groupHeight = y
            let here = cells.filter { range.contains($0.row) }
            let isFirst = start == 0, isLast = end == rows.count
            let group = Group()
            group.units = [Unit(height: groupHeight) { [weak self] spot in
                guard let self else { return }
                let context = spot.context
                let x0 = spot.origin.x + left
                for item in here {
                    let slot = CGRect(x: x0 + (item.column < starts.count ? starts[item.column] : total),
                                      y: spot.origin.y + (tops[item.row] ?? 0),
                                      width: span(item.column, item.span),
                                      height: heights[item.row..<(item.row + item.rowSpan)].reduce(0, +))
                    let box = slot.insetBy(dx: spacing, dy: spacing)
                    if let shading = item.cell.shading {
                        context.setFillColor(Self.color(shading).cgColor)
                        context.fill(box)
                    }
                    let inner = box.height - CGFloat(margins.top + margins.bottom) - self.height(of: item.content)
                    let offset: CGFloat
                    switch item.cell.verticalAlign {
                    case .top: offset = 0
                    case .center: offset = max(0, inner / 2)
                    case .bottom: offset = max(0, inner)
                    }
                    self.draw(item.content, at: CGPoint(x: box.minX + CGFloat(margins.left), y: box.minY + CGFloat(margins.top) + offset),
                              width: item.contentWidth, sheet: spot.sheet, context: context)
                    // Each side: the cell's own line, else the table's edge or the line between cells.
                    let own = item.cell.borders
                    let top = own?.top ?? (item.row == 0 ? borders.top : borders.insideHorizontal)
                    let bottom = own?.bottom ?? (item.row + item.rowSpan == rows.count ? borders.bottom : borders.insideHorizontal)
                    let leftSide = own?.left ?? (item.column == 0 ? borders.left : borders.insideVertical)
                    let rightSide = own?.right ?? (item.column + item.span >= needed ? borders.right : borders.insideVertical)
                    Self.stroke(top, from: CGPoint(x: box.minX, y: box.minY), to: CGPoint(x: box.maxX, y: box.minY), context)
                    Self.stroke(bottom, from: CGPoint(x: box.minX, y: box.maxY), to: CGPoint(x: box.maxX, y: box.maxY), context)
                    Self.stroke(leftSide, from: CGPoint(x: box.minX, y: box.minY), to: CGPoint(x: box.minX, y: box.maxY), context)
                    Self.stroke(rightSide, from: CGPoint(x: box.maxX, y: box.minY), to: CGPoint(x: box.maxX, y: box.maxY), context)
                }
                if spacing > 0 {                                       // cells apart: the table has its own frame
                    let frame = CGRect(x: x0, y: spot.origin.y, width: total, height: groupHeight)
                    if isFirst { Self.stroke(borders.top, from: CGPoint(x: frame.minX, y: frame.minY), to: CGPoint(x: frame.maxX, y: frame.minY), context) }
                    if isLast { Self.stroke(borders.bottom, from: CGPoint(x: frame.minX, y: frame.maxY), to: CGPoint(x: frame.maxX, y: frame.maxY), context) }
                    Self.stroke(borders.left, from: CGPoint(x: frame.minX, y: frame.minY), to: CGPoint(x: frame.minX, y: frame.maxY), context)
                    Self.stroke(borders.right, from: CGPoint(x: frame.maxX, y: frame.minY), to: CGPoint(x: frame.maxX, y: frame.maxY), context)
                }
            }]
            groups.append(group)
            start = end
        }
        return groups
    }

    // MARK: Pictures and lines

    /// The picture's pixels, cropped as the document says.
    private func picture(_ image: WordImage) -> CGImage? {
        let decoded: CGImage
        if let cached = pictures[image.part] {
            decoded = cached
        } else {
            guard let data = document.images[image.part], let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let made = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return nil }                            // EMF and WMF: room is left, nothing drawn
            pictures[image.part] = made
            decoded = made
        }
        let crop = image.crop
        guard crop.top > 0 || crop.left > 0 || crop.bottom > 0 || crop.right > 0 else { return decoded }
        let width = CGFloat(decoded.width), height = CGFloat(decoded.height)
        let keep = CGRect(x: width * CGFloat(crop.left), y: height * CGFloat(crop.top),
                          width: width * CGFloat(max(0.05, 1 - crop.left - crop.right)),
                          height: height * CGFloat(max(0.05, 1 - crop.top - crop.bottom)))
        return decoded.cropping(to: keep.integral) ?? decoded
    }

    /// Where a picture placed on the page goes: measured from the page, the margins or the paragraph.
    private func place(_ image: WordImage, anchor: CGFloat, column: CGRect, sheet: Sheet) -> CGRect {
        let float = image.floating ?? WordFloat()
        let page = sheet.geometry
        let size = CGSize(width: image.width, height: image.height)
        let across: (min: CGFloat, max: CGFloat)
        switch float.horizontalFrame {
        case .page: across = (0, page.size.width)
        case .margin: across = (page.left, page.size.width - page.right)
        default: across = (column.minX, column.maxX)
        }
        let x: CGFloat
        switch float.horizontalAlign {
        case .center?: x = (across.min + across.max - size.width) / 2
        case .right?, .outside?: x = across.max - size.width
        case .left?, .inside?: x = across.min
        default: x = across.min + CGFloat(float.x)
        }
        let down: (min: CGFloat, max: CGFloat)
        switch float.verticalFrame {
        case .page: down = (0, page.size.height)
        case .margin: down = (page.top, page.size.height - page.bottom)
        default: down = (anchor, anchor + size.height)
        }
        let y: CGFloat
        switch float.verticalAlign {
        case .center?: y = (down.min + down.max - size.height) / 2
        case .bottom?, .outside?: y = down.max - size.height
        case .top?, .inside?: y = down.min
        default: y = down.min + CGFloat(float.y)
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// Draws a picture upright in the page's top-down coordinates.
    func paint(_ image: CGImage?, in rect: CGRect, context: CGContext) {
        guard let image, rect.width > 0, rect.height > 0 else { return }
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    static func stroke(_ border: WordBorder?, from start: CGPoint, to end: CGPoint, _ context: CGContext) {
        guard let border, border.width > 0 else { return }
        context.saveGState()
        context.setStrokeColor((border.color.map(color) ?? NSColor.black).cgColor)
        context.setLineWidth(CGFloat(border.width))
        context.strokeLineSegments(between: [start, end])
        context.restoreGState()
    }

    static func color(_ color: WordColor) -> NSColor {
        NSColor(srgbRed: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1)
    }
}

// MARK: Lines of text

/// One paragraph broken into lines by TextKit, in a column of a given width.
private final class TextLayout {
    struct Line {
        var rect: CGRect
        var glyphs: NSRange
        /// Justified: the spaces that widen, and by how much each.
        var gaps: [Int] = []
        var stretch: CGFloat = 0
    }

    private let storage: NSTextStorage
    private let manager = NSLayoutManager()
    private let container: NSTextContainer
    private(set) var lines: [Line] = []

    /// `justified`: lines are laid out flush left, then widened to `rightEdge` at their spaces, as
    /// Word does: not the last line, not a line ended by a line break, and never by spacing out the
    /// letters of a line with one word (TextKit's own justification does that).
    init(_ text: NSAttributedString, width: CGFloat, justified: Bool = false, rightEdge: CGFloat = 0) {
        storage = NSTextStorage(attributedString: text)
        container = NSTextContainer(size: CGSize(width: width, height: 10_000_000))   // one paragraph, never cut
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        var lines: [Line] = []
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { rect, _, _, glyphs, _ in
            lines.append(Line(rect: rect, glyphs: glyphs))
        }
        if justified {
            let string = storage.string as NSString
            for index in lines.indices.dropLast() {
                let characters = manager.characterRange(forGlyphRange: lines[index].glyphs, actualGlyphRange: nil)
                var end = NSMaxRange(characters)
                guard end > characters.location, string.character(at: end - 1) != 0x2028 else { continue }
                while end > characters.location, string.character(at: end - 1) == 0x20 { end -= 1 }
                var start = characters.location
                while start < end, string.character(at: start) == 0x20 { start += 1 }
                guard start < end else { continue }
                let words = NSRange(location: start, length: end - start)
                if string.range(of: "\t", options: [], range: words).location != NSNotFound { continue }   // tabs set their own places
                var gaps: [Int] = []
                for character in start..<end where string.character(at: character) == 0x20 {
                    gaps.append(manager.glyphIndexForCharacter(at: character))
                }
                guard !gaps.isEmpty else { continue }
                let last = manager.glyphIndexForCharacter(at: end - 1)
                let used = manager.boundingRect(forGlyphRange: NSRange(location: last, length: 1), in: container).maxX
                let extra = rightEdge - used
                guard extra > 0.01, extra < width / 2 else { continue }
                lines[index].gaps = gaps
                lines[index].stretch = extra / CGFloat(gaps.count)
            }
        }
        self.lines = lines
    }

    /// The line's text at `origin` (where the container's top-left lands), and its pictures.
    func draw(_ line: Line, at origin: CGPoint, context: CGContext) {
        // Word by word when justified: each piece after a widened space moves right.
        var ends = line.gaps.map { $0 + 1 }.filter { $0 > line.glyphs.location && $0 < NSMaxRange(line.glyphs) }
        ends.append(NSMaxRange(line.glyphs))
        var from = line.glyphs.location
        for (piece, to) in ends.enumerated() where to > from {
            let range = NSRange(location: from, length: to - from)
            let at = CGPoint(x: origin.x + CGFloat(piece) * line.stretch, y: origin.y)
            manager.drawBackground(forGlyphRange: range, at: at)
            manager.drawGlyphs(forGlyphRange: range, at: at)
            from = to
        }
        let characters = manager.characterRange(forGlyphRange: line.glyphs, actualGlyphRange: nil)
        storage.enumerateAttribute(.droptimizePicture, in: characters, options: []) { value, range, _ in
            guard let box = value as? PictureBox, let image = box.image else { return }
            let glyph = manager.glyphIndexForCharacter(at: range.location)
            let size = box.size
            let fragment = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let baseline = manager.location(forGlyphAt: glyph)       // the picture sits on the baseline
            let moved = CGFloat(line.gaps.filter { $0 < glyph }.count) * line.stretch
            let rect = CGRect(x: origin.x + fragment.minX + baseline.x + moved, y: origin.y + fragment.minY + baseline.y - size.height,
                              width: size.width, height: size.height)
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(origin: .zero, size: rect.size))
            context.restoreGState()
        }
    }
}

// MARK: Fonts

/// Word's fonts, or the nearest a Mac has: Office's own (Calibri, Cambria…) aren't on a Mac
/// unless Office is.
private enum Typeface {
    static let families: Set<String> = Set((CTFontManagerCopyAvailableFontFamilyNames() as NSArray) as? [String] ?? [])

    private static let substitutes: [(prefix: String, family: String)] = [
        ("calibri", "Helvetica Neue"), ("aptos", "Helvetica Neue"), ("segoe", "Helvetica Neue"), ("carlito", "Helvetica Neue"),
        ("corbel", "Helvetica Neue"), ("candara", "Helvetica Neue"), ("roboto", "Helvetica Neue"), ("open sans", "Helvetica Neue"),
        ("lato", "Helvetica Neue"), ("noto sans", "Helvetica Neue"), ("source sans", "Helvetica Neue"), ("inter", "Helvetica Neue"),
        ("montserrat", "Avenir Next"), ("poppins", "Avenir Next"), ("century gothic", "Avenir Next"),
        ("cambria", "Charter"), ("constantia", "Charter"), ("caladea", "Charter"), ("century schoolbook", "Charter"),
        ("book antiqua", "Palatino"), ("palatino", "Palatino"), ("garamond", "Baskerville"), ("bookman", "Palatino"),
        ("consolas", "Menlo"), ("lucida console", "Menlo"), ("source code", "Menlo"), ("cascadia", "Menlo"),
        ("times", "Times New Roman"), ("liberation serif", "Times New Roman"), ("liberation sans", "Arial"),
        ("arial", "Arial"), ("helvetica", "Helvetica"),
    ]

    static func family(_ requested: String) -> String {
        if families.contains(requested) { return requested }
        let name = requested.lowercased()
        for substitute in substitutes where name.hasPrefix(substitute.prefix) && families.contains(substitute.family) {
            return substitute.family
        }
        if name.contains("mono") || name.contains("courier") || name.contains("code") { return "Menlo" }
        if name.contains("serif") && !name.contains("sans") { return "Times New Roman" }
        return families.contains("Helvetica Neue") ? "Helvetica Neue" : "Helvetica"
    }

    static func font(_ run: RunFormat) -> (font: NSFont, fakeBold: Bool, fakeItalic: Bool) {
        let size = CGFloat(max(run.size, 1))
        var traits: NSFontDescriptor.SymbolicTraits = []
        if run.bold { traits.insert(.bold) }
        if run.italic { traits.insert(.italic) }
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family(run.font)]).withSymbolicTraits(traits)
        let font = NSFont(descriptor: descriptor, size: size)
            ?? NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: family(run.font)]), size: size)
            ?? NSFont(name: "Times New Roman", size: size)
            ?? NSFont.systemFont(ofSize: size)
        let has = font.fontDescriptor.symbolicTraits
        return (font, run.bold && !has.contains(.bold), run.italic && !has.contains(.italic))
    }
}
