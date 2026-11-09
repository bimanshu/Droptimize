import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Images → one PDF (CORE.md §7c): a page per image, in name order, each page shaped like its
/// image and at most A4 (`PDFTuning.pageSize`). Only the format changes: every pixel goes in,
/// JPEGs keep their own bytes and lossless images stay lossless.
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
            let picture = try Picture(url)
            let page = PDFTuning.pageSize(pixelWidth: picture.width, pixelHeight: picture.height)
            var box = CGRect(x: 0, y: 0, width: page.width, height: page.height)
            context.beginPage(mediaBox: &box)
            context.interpolationQuality = .high
            context.concatenate(picture.placement(on: box.size))
            context.draw(picture.image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            context.endPage()
        }
        context.closePDF()

        let outputBytes = fileSize(temp) ?? 0
        let output = try OutputWriter.move(temp, for: first, fileExtension: "pdf",
                                           suffix: images.count > 1 ? "-\(images.count)-pages" : nil)
        return FileOutcome(input: first, output: output, inputBytes: inputBytes, outputBytes: outputBytes, picture: nil,
                           note: images.count > 1 ? "\(images.count) pages" : nil)
    }

    private struct Picture {
        let image: CGImage
        /// `image`'s EXIF orientation: it's stored as it came, and turned as it's drawn.
        let orientation: Int
        /// The upright size in pixels.
        let width: Int
        let height: Int

        init(_ url: URL) throws {
            let noCache = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(url as CFURL, noCache),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let format = CGImageSourceGetType(source).flatMap({ ImageFormat(typeIdentifier: $0 as String) })
                      ?? ImageFormat(fileExtension: url.pathExtension)
            else { throw JobError.unreadable }

            if format == .jpeg || format.isLossless, let stored = CGImageSourceCreateImageAtIndex(source, 0, noCache) {
                image = stored
                orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
                width = orientation >= 5 ? stored.height : stored.width
                height = orientation >= 5 ? stored.width : stored.height
                return
            }

            // A PDF can't hold HEIC, WebP or AVIF, so these go in as a near-top-quality JPEG.
            let decoded = try ImageDecoder.decode(url).image
            orientation = 1
            width = decoded.width
            height = decoded.height
            if decoded.isOpaque {
                let jpeg = try ImageIOEncoder.encode(decoded, as: .jpeg, quality: PDFTuning.photoQuality)
                guard let provider = CGDataProvider(data: jpeg as CFData),
                      let photo = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
                else { throw JobError.cantSave }
                image = photo
            } else {
                guard let graphic = decoded.makeCGImage() else { throw JobError.cantSave }
                image = graphic
            }
        }

        /// Maps the unit square the image is drawn in onto a page of `page`, upright.
        func placement(on page: CGSize) -> CGAffineTransform {
            let w = page.width, h = page.height
            switch orientation {
            case 2: return CGAffineTransform(a: -w, b: 0, c: 0, d: h, tx: w, ty: 0)
            case 3: return CGAffineTransform(a: -w, b: 0, c: 0, d: -h, tx: w, ty: h)
            case 4: return CGAffineTransform(a: w, b: 0, c: 0, d: -h, tx: 0, ty: h)
            case 5: return CGAffineTransform(a: 0, b: -h, c: -w, d: 0, tx: w, ty: h)
            case 6: return CGAffineTransform(a: 0, b: -h, c: w, d: 0, tx: 0, ty: h)
            case 7: return CGAffineTransform(a: 0, b: h, c: w, d: 0, tx: 0, ty: 0)
            case 8: return CGAffineTransform(a: 0, b: h, c: -w, d: 0, tx: w, ty: 0)
            default: return CGAffineTransform(a: w, b: 0, c: 0, d: h, tx: 0, ty: 0)
            }
        }
    }

    private static func fileSize(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
    }
}
