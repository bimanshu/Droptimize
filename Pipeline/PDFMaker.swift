import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Images → one PDF (CORE.md §7c): a page per image, in name order, each page shaped like its
/// image and at most A4 (`PDFTuning.pageSize`). Photos go in as JPEG (the PDF keeps the JPEG as it
/// is); graphics, screenshots and anything see-through stay lossless.
enum PDFMaker {
    static func combine(_ files: [URL]) throws -> FileOutcome {
        let images = files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard let first = images.first else { throw JobError.unreadable }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("droptimize-\(UUID().uuidString)").appendingPathExtension("pdf")
        defer { try? FileManager.default.removeItem(at: temp) }
        let info: [CFString: Any] = [kCGPDFContextCreator: "Droptimize",
                                     kCGPDFContextTitle: first.deletingPathExtension().lastPathComponent]
        guard let context = CGContext(temp as CFURL, mediaBox: nil, info as CFDictionary) else { throw JobError.cantSave }

        var inputBytes = 0
        for url in images {
            try Task.checkCancellation()
            inputBytes += fileSize(url) ?? 0
            let (width, height) = try pixelSize(of: url)
            let image = try ImageDecoder.decode(url, scale: PDFTuning.pixelScale(pixelWidth: width, pixelHeight: height)).image
            let page = PDFTuning.pageSize(pixelWidth: image.width, pixelHeight: image.height)
            var box = CGRect(x: 0, y: 0, width: page.width, height: page.height)
            context.beginPage(mediaBox: &box)
            context.interpolationQuality = .high
            context.draw(try picture(for: image), in: box)
            context.endPage()
        }
        context.closePDF()

        let outputBytes = fileSize(temp) ?? 0
        let output = try OutputWriter.move(temp, for: first, fileExtension: "pdf",
                                           suffix: images.count > 1 ? "-\(images.count)-pages" : nil)
        return FileOutcome(input: first, output: output, inputBytes: inputBytes, outputBytes: outputBytes, picture: nil,
                           note: images.count > 1 ? "\(images.count) pages" : nil)
    }

    /// Photos as JPEG; graphics and anything with transparency as they are (the PDF compresses them losslessly).
    private static func picture(for image: RGBAImage) throws -> CGImage {
        if image.isOpaque && !image.looksLikeGraphic {
            let jpeg = try ImageIOEncoder.encode(image, as: .jpeg, quality: PDFTuning.photoQuality)
            guard let provider = CGDataProvider(data: jpeg as CFData),
                  let photo = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
            else { throw JobError.cantSave }
            return photo
        }
        guard let graphic = image.makeCGImage() else { throw JobError.cantSave }
        return graphic
    }

    /// The stored size in pixels, read without decoding.
    private static func pixelSize(of url: URL) throws -> (Int, Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw JobError.unreadable }
        return (width, height)
    }

    private static func fileSize(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
    }
}
