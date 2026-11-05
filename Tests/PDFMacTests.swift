import AppKit
import CoreText
import ImageIO
import PDFKit
import Quartz
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

    /// Not a check: prints what each of Apple's options does to a photo PDF and a scan, to tune
    /// Compress PDF from (CI prints lines starting with "MEASURE").
    func testMeasureApplesCompressionOptions() throws {
        let inputs = [try makePDF("m-photo.pdf", pages: [.photo]), try makePDF("m-scan.pdf", pages: [.scan])]
        let system = URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter")
        if let plist = try? String(contentsOf: system, encoding: .utf8) {
            for line in plist.split(separator: "\n") { print("MEASURE qfilter| \(line)") }
        } else if let data = try? Data(contentsOf: system),
                  let object = try? PropertyListSerialization.propertyList(from: data, format: nil) {
            print("MEASURE qfilter| \(object)")
        } else {
            print("MEASURE qfilter| not found")
        }
        var custom: [(String, URL)] = []
        for quality in [0.5, 0.75] {
            if let url = try customFilter(from: system, quality: quality) { custom.append(("custom q\(quality)", url)) }
        }

        for input in inputs {
            let document = try XCTUnwrap(PDFDocument(url: input))
            let original = render(input, page: 0)
            report(input.lastPathComponent, "original", input, original)
            var variants: [(String, [PDFDocumentWriteOption: Any])] = [
                ("plain write", [:]),
                ("JPEG", [.saveImagesAsJPEGOption: true]),
                ("screen", [.optimizeImagesForScreenOption: true]),
                ("screen + JPEG", [.optimizeImagesForScreenOption: true, .saveImagesAsJPEGOption: true]),
            ]
            if let filter = QuartzFilter(url: system) {
                variants.append(("Reduce File Size", [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter]))
            }
            for (name, url) in custom {
                if let filter = QuartzFilter(url: url) {
                    variants.append((name, [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter]))
                }
            }
            for (name, options) in variants {
                let out = folder.appendingPathComponent("\(UUID().uuidString).pdf")
                guard document.write(to: out, withOptions: options) else {
                    print("MEASURE \(input.lastPathComponent) | \(name) | write failed")
                    continue
                }
                report(input.lastPathComponent, name, out, original)
            }
            // A custom filter applied while redrawing each page into a new PDF.
            for (name, url) in custom {
                guard let filter = QuartzFilter(url: url), let source = CGPDFDocument(input as CFURL) else { continue }
                let out = folder.appendingPathComponent("\(UUID().uuidString).pdf")
                var box = CGRect(x: 0, y: 0, width: 595, height: 842)
                guard let context = CGContext(out as CFURL, mediaBox: &box, nil) else { continue }
                let applied = filter.apply(to: context)
                for number in 1...source.numberOfPages {
                    guard let page = source.page(at: number) else { continue }
                    context.beginPDFPage(nil)
                    context.drawPDFPage(page)
                    context.endPDFPage()
                }
                context.closePDF()
                report(input.lastPathComponent, "\(name) redrawn (applied: \(applied))", out, original)
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

    /// The system's "Reduce File Size" filter with its JPEG quality set to `quality` and its
    /// downscaling turned off, saved as a new .qfilter (nil when the system one isn't there).
    private func customFilter(from system: URL, quality: Double) throws -> URL? {
        guard let data = try? Data(contentsOf: system),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil)
        else { return nil }
        func adjust(_ value: Any) -> Any {
            if let dictionary = value as? NSMutableDictionary {
                for key in dictionary.allKeys {
                    guard let name = key as? String, let child = dictionary[key] else { continue }
                    if name.localizedCaseInsensitiveContains("quality") { dictionary[key] = quality }
                    else if name.localizedCaseInsensitiveContains("scalefactor") { dictionary[key] = 1.0 }
                    else if name.localizedCaseInsensitiveContains("sizemax") { dictionary[key] = 4000 }
                    else if name == "Name" { dictionary[key] = "Droptimize q\(quality)" }
                    else { dictionary[key] = adjust(child) }
                }
                return dictionary
            }
            if let array = value as? NSMutableArray {
                for index in 0..<array.count { array[index] = adjust(array[index]) }
                return array
            }
            return value
        }
        let adjusted = adjust(plist)
        let url = folder.appendingPathComponent("droptimize-\(quality).qfilter")
        try PropertyListSerialization.data(fromPropertyList: adjusted, format: .xml, options: 0).write(to: url)
        return url
    }

    // MARK: Looking at PDFs

    private func report(_ input: String, _ variant: String, _ url: URL, _ original: [UInt8]) {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        let letters = PDFDocument(url: url)?.string?.filter { !$0.isWhitespace }.count ?? 0
        let quality = psnr(original, render(url, page: 0))
        print("MEASURE \(input) | \(variant) | \(bytes) bytes | images \(Self.images(in: url).joined(separator: ", ")) | "
              + "PSNR at 150 dpi \(String(format: "%.1f", quality)) dB | \(letters) letters")
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
