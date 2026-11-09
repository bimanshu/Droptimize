import Foundation

/// A Word document as Droptimize lays it out (CORE.md §7c): read by `WordReader` from the .docx
/// itself, all lengths in points. Portable, so the reading is tested on Linux.
struct WordDocument {
    var page = WordPage()
    var blocks: [WordBlock] = []
    /// Header and footer for every page, and for the first page when `page.differentFirstPage`.
    var header: [WordBlock]?
    var footer: [WordBlock]?
    var firstHeader: [WordBlock]?
    var firstFooter: [WordBlock]?
    /// The pictures the document uses, by their path in the .docx ("word/media/image1.png").
    var images: [String: Data] = [:]
}

struct WordPage: Equatable {
    /// Letter, Word's default when a document doesn't say.
    var width = 612.0
    var height = 792.0
    var top = 72.0, bottom = 72.0, left = 90.0, right = 90.0
    /// From the paper's edge to the header's top and the footer's bottom.
    var header = 36.0, footer = 36.0
    var differentFirstPage = false
}

enum WordBlock: Equatable {
    case paragraph(WordParagraph)
    case table(WordTable)
}

struct WordParagraph: Equatable {
    var format = ParagraphFormat()
    var inlines: [WordInline] = []
    /// The list number or bullet, already counted ("3.", "•"), shown before the text.
    var marker: WordInline?
    /// The style it was given (contextual spacing compares these).
    var styleID: String?

    var text: String {
        inlines.map { inline -> String in
            switch inline {
            case .text(let text, _): return text
            case .tab: return "\t"
            case .lineBreak: return "\n"
            default: return ""
            }
        }.joined()
    }
}

enum WordInline: Equatable {
    case text(String, RunFormat)
    case tab(RunFormat)
    case lineBreak
    /// A page break inside a paragraph: what follows starts a new page.
    case pageBreak
    case image(WordImage)
    /// Filled in per page when the page is drawn.
    case field(WordField, RunFormat)
}

enum WordField: Equatable {
    case page, numberOfPages
}

struct WordImage: Equatable {
    /// Its path in the .docx, a key of `WordDocument.images`.
    var part: String
    var width: Double
    var height: Double
    /// Nil for a picture in the line of text; set for one placed freely on the page.
    var floating: WordFloat?
}

/// Where a freely placed picture sits. Behind or in front of the text, it's drawn there without
/// moving any text; with text wrapped around it, it gets its own line where it's anchored instead.
struct WordFloat: Equatable {
    enum Frame: String { case page, margin, column, paragraph, character, line }
    enum Align: String { case left, center, right, top, bottom, inside, outside }
    var horizontalFrame: Frame = .column
    var verticalFrame: Frame = .paragraph
    var x = 0.0, y = 0.0
    var horizontalAlign: Align?
    var verticalAlign: Align?
    /// Behind or in front of the text, so no text moves out of its way.
    var overText = false
    /// Drawn under the text rather than over it.
    var behindText = false
}

struct ParagraphFormat: Equatable {
    enum Alignment: Equatable { case left, center, right, justified }
    enum LineSpacing: Equatable {
        /// A multiple of single spacing (1.5 for "1.5 lines").
        case multiple(Double)
        case exactly(Double)
        case atLeast(Double)
    }
    var alignment: Alignment = .left
    var spaceBefore = 0.0
    var spaceAfter = 0.0
    var lineSpacing: LineSpacing = .multiple(1)
    var indentLeft = 0.0
    var indentRight = 0.0
    /// Positive: the first line starts further in; negative: it hangs out (list items).
    var firstLine = 0.0
    var keepWithNext = false
    /// All its lines on one page.
    var keepLines = false
    var pageBreakBefore = false
    /// Spacing between paragraphs of the same style is left out.
    var contextualSpacing = false
    var tabStops: [WordTab] = []
    var shading: WordColor?
    /// Lines above, below and beside the paragraph (`insideHorizontal`: between paragraphs that share them).
    var borders: WordBorders?
    /// The font used for an empty paragraph's line (Word sizes the line by it).
    var markFormat = RunFormat()
}

struct WordTab: Equatable {
    enum Alignment: Equatable { case left, center, right, decimal }
    var position: Double
    var alignment: Alignment = .left
}

struct RunFormat: Equatable {
    enum VerticalAlign: Equatable { case baseline, superscript, subscriptText }
    var font = "Times New Roman"
    var size = 10.0
    var bold = false
    var italic = false
    var underline = false
    var strike = false
    var caps = false
    var smallCaps = false
    var color: WordColor?
    var highlight: WordColor?
    var verticalAlign: VerticalAlign = .baseline
    var hidden = false
}

struct WordColor: Equatable {
    var red: Double, green: Double, blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }

    /// "2E74B5"; nil for "auto" or anything else that isn't a color.
    init?(hex: String?) {
        guard let hex, hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }

    /// Word's named highlight colors.
    init?(highlight name: String?) {
        let names: [String: String] = [
            "yellow": "FFFF00", "green": "00FF00", "cyan": "00FFFF", "magenta": "FF00FF", "blue": "0000FF",
            "red": "FF0000", "darkBlue": "000080", "darkCyan": "008080", "darkGreen": "008000",
            "darkMagenta": "800080", "darkRed": "800000", "darkYellow": "808000", "darkGray": "808080",
            "lightGray": "C0C0C0", "black": "000000", "white": "FFFFFF",
        ]
        guard let name, let hex = names[name] else { return nil }
        self.init(hex: hex)
    }
}

struct WordBorder: Equatable {
    var width: Double
    var color: WordColor?
}

struct WordTable: Equatable {
    enum Alignment: Equatable { case left, center, right }
    /// Each grid column's width.
    var columns: [Double] = []
    var rows: [WordRow] = []
    var alignment: Alignment = .left
    var indent = 0.0
    /// Word's default: 0.08" left and right, nothing above or below.
    var cellMargins = WordInsets(top: 0, left: 5.4, bottom: 0, right: 5.4)
    var cellSpacing = 0.0
    var borders = WordBorders()
}

struct WordInsets: Equatable {
    var top: Double, left: Double, bottom: Double, right: Double
}

struct WordBorders: Equatable {
    var top: WordBorder?, left: WordBorder?, bottom: WordBorder?, right: WordBorder?
    var insideHorizontal: WordBorder?, insideVertical: WordBorder?
}

struct WordRow: Equatable {
    var cells: [WordCell] = []
    var minimumHeight = 0.0
}

struct WordCell: Equatable {
    enum VerticalMerge: Equatable { case none, start, continued }
    enum VerticalAlign: Equatable { case top, center, bottom }
    var blocks: [WordBlock] = []
    var columnSpan = 1
    var verticalMerge: VerticalMerge = .none
    var shading: WordColor?
    var borders: WordBorders?
    var verticalAlign: VerticalAlign = .top
}

/// Word's units, in points.
enum WordUnits {
    static func twips(_ value: String?) -> Double? { value.flatMap(Double.init).map { $0 / 20 } }
    static func halfPoints(_ value: String?) -> Double? { value.flatMap(Double.init).map { $0 / 2 } }
    static func eighthPoints(_ value: String?) -> Double? { value.flatMap(Double.init).map { $0 / 8 } }
    static func emu(_ value: String?) -> Double? { value.flatMap(Double.init).map { $0 / 12_700 } }
}
