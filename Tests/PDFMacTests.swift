import AppKit
import CoreText
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Droptimize

// macOS only: Compress PDF on real (generated) PDFs. Runs in CI and Xcode.
final class PDFMacTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("PDFMacTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: Tests

    func testCompressesAPDFWithAPhotoAndKeepsTheText() throws {
        let input = try makePDF("report.pdf", pages: [.photo, .text])
        let outcome = try PDFOptimizer.process(input, action: .auto, option: nil)
        XCTAssertEqual(outcome.output.lastPathComponent, "report-min.pdf")
        XCTAssertLessThan(outcome.outputBytes, outcome.inputBytes * 8 / 10, "\(outcome.inputBytes) → \(outcome.outputBytes)")
        let copy = try XCTUnwrap(PDFDocument(url: outcome.output))
        XCTAssertEqual(copy.pageCount, 2)
        XCTAssertTrue(copy.string?.contains("Quarterly report") ?? false, "the text is still text")
        XCTAssertEqual(copy.page(at: 0)?.bounds(for: .mediaBox), CGRect(x: 0, y: 0, width: 595, height: 842))
        XCTAssertGreaterThan(psnr(render(input, page: 0), render(outcome.output, page: 0)), 30, "looks the same on screen")
    }

    func testCompressesAScan() throws {
        let input = try makePDF("scan.pdf", pages: [.scan])
        let outcome = try PDFOptimizer.process(input, action: .compress, option: nil)
        XCTAssertEqual(outcome.output.lastPathComponent, "scan-min.pdf")
        XCTAssertLessThan(outcome.outputBytes, outcome.inputBytes)
    }

    func testNeverHandsBackABiggerPDF() throws {
        // Text only: little or nothing to gain. Either a smaller copy, or "Already as small as it gets."
        let input = try makePDF("letter.pdf", pages: [.text, .text])
        do {
            let outcome = try PDFOptimizer.process(input, action: .auto, option: nil)
            XCTAssertLessThan(outcome.outputBytes, outcome.inputBytes)
        } catch {
            XCTAssertEqual(error as? JobError, .alreadySmallest)
        }
    }

    func testLeavesPasswordProtectedPDFsAlone() throws {
        let input = try makePDF("statement.pdf", pages: [.photo], password: "secret")
        XCTAssertThrowsError(try PDFOptimizer.process(input, action: .auto, option: nil)) { error in
            XCTAssertEqual(error as? JobError, .protectedPDF)
        }
    }

    func testLeavesSignedPDFsAlone() throws {
        let input = folder.appendingPathComponent("contract.pdf")
        try Self.minimalPDF(catalog: "/AcroForm << /Fields [] /SigFlags 3 >>").write(to: input)
        XCTAssertThrowsError(try PDFOptimizer.process(input, action: .auto, option: nil)) { error in
            XCTAssertEqual(error as? JobError, .signedPDF)
        }
        // The same file without signatures is fine to rewrite.
        let plain = folder.appendingPathComponent("plain.pdf")
        try Self.minimalPDF(catalog: "").write(to: plain)
        XCTAssertFalse(PDFOptimizer.isSigned(try XCTUnwrap(PDFDocument(url: plain))))
    }

    func testRefusesACopyThatLostItsText() throws {
        let input = try makePDF("words.pdf", pages: [.text])
        let original = try XCTUnwrap(PDFDocument(url: input))
        let blank = try makePDF("blank.pdf", pages: [.blank])
        XCTAssertFalse(PDFOptimizer.keepsEverything(try XCTUnwrap(PDFDocument(url: blank)), of: original))
        XCTAssertTrue(PDFOptimizer.keepsEverything(original, of: original))
    }

    @MainActor
    func testTheRunnerSendsPDFsToTheOptimizer() async throws {
        let input = try makePDF("brochure.pdf", pages: [.photo])
        let result = try await ImageJobRunner().run(Job(files: [input], action: .auto)) { _ in }
        XCTAssertEqual(result.outputs.map(\.lastPathComponent), ["brochure-min.pdf"])
        XCTAssertLessThan(result.outputBytes, result.inputBytes)
    }

    func testCompressesToASizeAsSharpAsFits() throws {
        let input = try makePDF("scan.pdf", pages: [.scan])
        let outcome = try PDFOptimizer.process(input, action: .compress, option: .maxBytes(1_000_000))
        XCTAssertEqual(outcome.output.lastPathComponent, "scan-1mb.pdf")
        XCTAssertLessThanOrEqual(outcome.outputBytes, 1_000_000)
        // There's room for more than Auto's 144 ppi (1190 px across an A4 page), so it uses it.
        let width = try XCTUnwrap(Self.imageWidths(in: outcome.output).first)
        XCTAssertGreaterThan(width, 1190, "sharper than Auto when the size allows")
        XCTAssertTrue(PDFDocument(url: outcome.output)?.string?.contains("Quarterly report") ?? false)
    }

    func testSaysWhenASizeIsOutOfReach() throws {
        let input = try makePDF("poster.pdf", pages: [.photo])
        XCTAssertThrowsError(try PDFOptimizer.process(input, action: .compress, option: .maxBytes(5_000))) { error in
            XCTAssertEqual(error as? JobError, .cantFit(5_000))
        }
        XCTAssertThrowsError(try PDFOptimizer.process(input, action: .compress, option: .maxBytes(5_000_000))) { error in
            XCTAssertEqual(error as? JobError, .alreadyUnder(5_000_000))
        }
    }

    /// Not a check: prints what each step of `PDFTuning.ladder` gives a photo PDF and a scan,
    /// against Auto, to tune from (CI prints lines starting with "MEASURE").
    func testMeasureTheLadder() throws {
        for input in [try makePDF("m-photo.pdf", pages: [.photo]), try makePDF("m-scan.pdf", pages: [.scan])] {
            let document = try XCTUnwrap(PDFDocument(url: input))
            let original = render(input, page: 0)
            report(input.lastPathComponent, "original", input, original)
            let auto = folder.appendingPathComponent("auto-\(input.lastPathComponent)")
            if document.write(to: auto, withOptions: PDFOptimizer.compression) { report(input.lastPathComponent, "Auto", auto, original) }
            for step in PDFTuning.ladder {
                let out = folder.appendingPathComponent("\(UUID().uuidString).pdf")
                try PDFOptimizer.write(document, step: step, to: out, scratch: folder)
                report(input.lastPathComponent, "\(step.pixelsPerInch) ppi, q \(step.quality)", out, original)
            }
        }
    }

    // MARK: Making test PDFs

    private enum Content { case photo, scan, text, blank }

    /// A4 pages (595 × 842 pt), each with a heading and a paragraph of real text, and:
    /// photo, a 3000 × 2000 JPEG (as a camera makes) drawn 500 pt wide, about 430 ppi;
    /// scan, a 2480 × 3508 grayscale page (a 300 dpi scan), stored losslessly.
    private func makePDF(_ name: String, pages: [Content], password: String? = nil) throws -> URL {
        let url = folder.appendingPathComponent(name)
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        var info: [CFString: Any] = [kCGPDFContextTitle: "Droptimize test"]
        if let password {
            info[kCGPDFContextUserPassword] = password
            info[kCGPDFContextOwnerPassword] = password
        }
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, info as CFDictionary))
        for content in pages {
            context.beginPDFPage(nil)
            switch content {
            case .photo: context.draw(Self.photo, in: CGRect(x: 47, y: 300, width: 500, height: 333))
            case .scan: context.draw(Self.scan, in: box)
            case .text, .blank: break
            }
            if content != .blank { Self.drawText(in: context) }
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    private static func drawText(in context: CGContext) {
        let paragraph = "Quarterly report. Droptimize keeps every word of this page as real text, so it can be "
            + "searched, selected and read aloud after compression. Only the pictures get smaller."
        let text = NSAttributedString(string: paragraph, attributes: [.font: NSFont.systemFont(ofSize: 13)])
        let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(text), CFRange(location: 0, length: 0),
                                             CGPath(rect: CGRect(x: 47, y: 680, width: 500, height: 120), transform: nil), nil)
        CTFrameDraw(frame, context)
    }

    /// Smooth shapes with fine grain, like a photo, saved as a high-quality JPEG.
    private static let photo: CGImage = {
        let width = 3000, height = 2000
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        var seed: UInt32 = 7
        let columns = (0..<width).map { sin(Double($0) / 190) }, rows = (0..<height).map { cos(Double($0) / 130) }
        for y in 0..<height {
            for x in 0..<width {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let grain = Int(seed >> 28) - 8
                let i = (y * width + x) * 4
                let shade = 110 + 70 * columns[x] * rows[y]
                pixels[i] = UInt8(clamping: Int(shade + 40) + grain)
                pixels[i + 1] = UInt8(clamping: Int(shade) + grain)
                pixels[i + 2] = UInt8(clamping: Int(200 - shade * 0.6) + grain)
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let bitmap = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                             bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                             decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, bitmap, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        CGImageDestinationFinalize(destination)
        // Made from JPEG data, so the PDF stores the JPEG itself, as when a photo is placed in a document.
        return CGImage(jpegDataProviderSource: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)!
    }()

    /// Off-white paper with lines of dark "writing", 8-bit gray.
    private static let scan: CGImage = {
        let width = 2480, height = 3508
        var pixels = [UInt8](repeating: 0, count: width * height)
        var seed: UInt32 = 3
        for y in 0..<height {
            let line = (y / 70) % 2 == 0 && y > 300 && y < 3200
            for x in 0..<width {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let ink = line && x > 250 && x < 2230 && (x / 23 + y / 9) % 5 != 0
                pixels[y * width + x] = ink ? UInt8(40 + seed >> 28) : UInt8(228 + seed >> 29)
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }()

    /// A one-page PDF written by hand, with `catalog` added to its catalog dictionary.
    private static func minimalPDF(catalog: String) -> Data {
        let content = "BT /F1 18 Tf 20 100 Td (Signed contract) Tj ET"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R \(catalog) >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
            "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        ]
        var file = "%PDF-1.7\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(file.utf8.count)
            file += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = file.utf8.count
        file += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { file += String(format: "%010d 00000 n \n", offset) }
        file += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(file.utf8)
    }

    // MARK: Looking at PDFs

    private func report(_ input: String, _ variant: String, _ url: URL, _ original: [UInt8]) {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        let letters = PDFDocument(url: url)?.string?.filter { !$0.isWhitespace }.count ?? 0
        let quality = psnr(original, render(url, page: 0))
        print("MEASURE \(input) | \(variant) | \(bytes) bytes | images \(Self.images(in: url).joined(separator: ", ")) | "
              + "PSNR at 150 dpi \(String(format: "%.1f", quality)) dB | \(letters) letters")
    }

    private static func imageWidths(in url: URL) -> [Int] {
        images(in: url).compactMap { Int($0.prefix { $0 != "×" }) }
    }

    /// Each image on each page: pixel size and how it's stored.
    private static func images(in url: URL) -> [String] {
        guard let document = CGPDFDocument(url as CFURL), document.numberOfPages > 0 else { return [] }
        var found: [String] = []
        for number in 1...document.numberOfPages {
            guard let page = document.page(at: number), let dictionary = page.dictionary else { continue }
            var resources: CGPDFDictionaryRef?, objects: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources,
                  CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects
            else { continue }
            CGPDFDictionaryApplyBlock(objects, { _, object, _ in
                var stream: CGPDFStreamRef?
                guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                      let info = CGPDFStreamGetDictionary(stream) else { return true }
                var width: CGPDFInteger = 0, height: CGPDFInteger = 0
                var filter: UnsafePointer<CChar>?
                CGPDFDictionaryGetInteger(info, "Width", &width)
                CGPDFDictionaryGetInteger(info, "Height", &height)
                let stored = CGPDFDictionaryGetName(info, "Filter", &filter) ? filter.map { String(cString: $0) } ?? "?" : "other"
                found.append("\(width)×\(height) \(stored)")
                return true
            }, nil)
        }
        return found
    }

    /// A page drawn at `dpi` on white, RGBA.
    private func render(_ url: URL, page index: Int, dpi: CGFloat = 150) -> [UInt8] {
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: index + 1) else { return [] }
        let box = page.getBoxRect(.mediaBox)
        let width = Int(box.width * dpi / 72), height = Int(box.height * dpi / 72)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: dpi / 72, y: dpi / 72)
            context.drawPDFPage(page)
        }
        return pixels
    }

    private func psnr(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var sum = 0.0
        for i in a.indices where i % 4 != 3 { let d = Double(a[i]) - Double(b[i]); sum += d * d }
        let mse = sum / Double(a.count / 4 * 3)
        return mse == 0 ? 99 : 10 * log10(255 * 255 / mse)
    }
}

// MARK: Conversions (CORE.md §7c), here to share the test PDFs and pictures above

extension PDFMacTests {
    func testAPDFsPagesBecomeImagesInAFolder() throws {
        let input = try makePDF("deck.pdf", pages: [.photo, .text, .scan])
        let outcome = try PDFOptimizer.process(input, action: .convert, option: nil)
        XCTAssertEqual(outcome.output.lastPathComponent, "deck pages")
        XCTAssertEqual(outcome.files?.map(\.lastPathComponent), ["deck-1.png", "deck-2.png", "deck-3.png"])
        XCTAssertEqual(outcome.note, "3 pages, in “deck pages”")
        for file in outcome.files ?? [] {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(file as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.width, 1190, "A4 at 144 ppi: sharp on a Retina screen")
            XCTAssertEqual(image.height, 1684)
        }
        // A second time: a new folder, nothing overwritten.
        let again = try PDFOptimizer.process(input, action: .convert, option: .format(.png))
        XCTAssertEqual(again.output.lastPathComponent, "deck pages 2")
    }

    func testAOnePagePDFBecomesOneImage() throws {
        let input = try makePDF("flyer.pdf", pages: [.photo])
        let outcome = try PDFOptimizer.process(input, action: .convert, option: .format(.jpeg))
        XCTAssertEqual(outcome.output.lastPathComponent, "flyer.jpg")
        XCTAssertNil(outcome.files)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(outcome.output as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        // The photo is still there, drawn where it was.
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 1190)
    }

    @MainActor
    func testThePagesGoOnTheClipboardAndCountAsOneFile() async throws {
        let input = try makePDF("slides.pdf", pages: [.text, .text])
        let result = try await ImageJobRunner().run(Job(files: [input], action: .convert, option: .format(.png))) { _ in }
        XCTAssertEqual(result.outputs.map(\.lastPathComponent), ["slides-1.png", "slides-2.png"], "the pages, to paste")
        XCTAssertEqual(result.items.map(\.output.lastPathComponent), ["slides pages"], "one result: the folder")
    }

    @MainActor
    func testImagesBecomeOnePDFInNameOrder() async throws {
        // A photo (JPEG), a screenshot-like graphic (PNG) and a tall scan, named so that only a
        // natural sort puts them in order: 1, 2, 10.
        let photo = folder.appendingPathComponent("scan 2.jpg")
        let graphic = folder.appendingPathComponent("scan 10.png")
        let page = folder.appendingPathComponent("scan 1.png")
        try write(Self.photo, to: photo, type: .jpeg)
        try write(Self.graphic, to: graphic, type: .png)
        try write(Self.scan, to: page, type: .png)
        let job = Job(files: [graphic, photo, page], action: .convert, option: .pdf)
        let result = try await ImageJobRunner().run(job) { _ in }
        XCTAssertEqual(result.outputs.map(\.lastPathComponent), ["scan 1-3-pages.pdf"])
        XCTAssertEqual(result.items.count, 1, "one PDF, one free file")
        XCTAssertEqual(result.note, "3 pages")

        let pdf = try XCTUnwrap(result.outputs.first)
        let document = try XCTUnwrap(CGPDFDocument(pdf as CFURL))
        XCTAssertEqual(document.numberOfPages, 3)
        func size(_ number: Int) -> CGSize { document.page(at: number)?.getBoxRect(.mediaBox).size ?? .zero }
        XCTAssertEqual(size(1).height, 842, accuracy: 0.5, "the A4 scan: an A4 page")
        XCTAssertEqual(size(1).width, 595.3, accuracy: 0.5)
        XCTAssertEqual(size(2).width, 842, accuracy: 0.5, "the photo: landscape, at most A4")
        XCTAssertEqual(size(2).height, 561.3, accuracy: 0.5)
        XCTAssertEqual(size(3), CGSize(width: 800, height: 500), "the small graphic isn't blown up")
        let stored = Self.images(in: pdf)
        XCTAssertEqual(stored.count, 3)
        XCTAssertTrue(stored[1].hasSuffix("DCTDecode"), "the photo as JPEG: \(stored)")
        XCTAssertFalse(stored[2].hasSuffix("DCTDecode"), "the graphic stays lossless: \(stored)")
    }

    /// Flat colors and hard edges, like a screenshot.
    private static let graphic: CGImage = {
        let width = 800, height = 500
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 0.24, green: 0.86, blue: 0.59, alpha: 1))
        context.fill(CGRect(x: 60, y: 300, width: 300, height: 120))
        context.setFillColor(CGColor(srgbRed: 0.05, green: 0.05, blue: 0.06, alpha: 1))
        context.fill(CGRect(x: 60, y: 80, width: 680, height: 40))
        return context.makeImage()!
    }()

    private func write(_ image: CGImage, to url: URL, type: UTType) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
