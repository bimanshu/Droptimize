import Accelerate
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An image read from disk and normalized (CORE.md §6.2).
struct DecodedImage {
    var image: RGBAImage
    var format: ImageFormat
}

enum ImageDecoder {
    /// Reads the first frame, applies the EXIF orientation, converts to sRGB, drops all metadata
    /// and, for `scale` below 1, resizes with high-quality resampling.
    static func decode(_ url: URL, scale: Double = 1) throws -> DecodedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let format = CGImageSourceGetType(source).flatMap({ ImageFormat(typeIdentifier: $0 as String) })
                ?? ImageFormat(fileExtension: url.pathExtension),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { throw JobError.unreadable }

        // Asking for a full-size "thumbnail" with the transform applied is ImageIO's way of
        // returning the pixels already rotated by their EXIF orientation.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let oriented = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw JobError.unreadable
        }
        var image = try render(oriented)
        if scale < 1 { image = try resize(image, scale: scale) }
        unpremultiply(&image)
        return DecodedImage(image: image, format: format)
    }

    /// Draws into 8-bit sRGB RGBA, premultiplied (what Core Graphics draws into). Drawing does the
    /// color conversion from whatever profile the file had.
    private static func render(_ cgImage: CGImage) throws -> RGBAImage {
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw JobError.unreadable }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    /// Lanczos resampling with vImage, on premultiplied pixels so edges don't get dark fringes.
    private static func resize(_ image: RGBAImage, scale: Double) throws -> RGBAImage {
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        var source = image.pixels
        var output = [UInt8](repeating: 0, count: width * height * 4)
        let error = source.withUnsafeMutableBytes { src in
            output.withUnsafeMutableBytes { dst in
                var from = vImage_Buffer(data: src.baseAddress, height: vImagePixelCount(image.height),
                                         width: vImagePixelCount(image.width), rowBytes: image.width * 4)
                var to = vImage_Buffer(data: dst.baseAddress, height: vImagePixelCount(height),
                                       width: vImagePixelCount(width), rowBytes: width * 4)
                return vImageScale_ARGB8888(&from, &to, nil, vImage_Flags(kvImageHighQualityResampling))
            }
        }
        guard error == kvImageNoError else { throw JobError.unreadable }
        return RGBAImage(width: width, height: height, pixels: output)
    }

    private static func unpremultiply(_ image: inout RGBAImage) {
        let width = image.width, height = image.height
        image.pixels.withUnsafeMutableBytes { bytes in
            // In place: source and destination describe the same pixels.
            var source = vImage_Buffer(data: bytes.baseAddress, height: vImagePixelCount(height),
                                       width: vImagePixelCount(width), rowBytes: width * 4)
            var destination = source
            _ = vImageUnpremultiplyData_RGBA8888(&source, &destination, vImage_Flags(kvImageNoFlags))
        }
    }
}

extension ImageFormat {
    init?(typeIdentifier: String) {
        guard let type = UTType(typeIdentifier) else { return nil }
        if type.conforms(to: .jpeg) {
            self = .jpeg
        } else if type.conforms(to: .png) {
            self = .png
        } else if type.conforms(to: .webP) {
            self = .webp
        } else if type.conforms(to: .heic) || type.conforms(to: .heif) {
            self = .heic
        } else if let avif = UTType("public.avif"), type.conforms(to: avif) {
            self = .avif
        } else if type.conforms(to: .tiff) {
            self = .tiff
        } else if type.conforms(to: .gif) {
            self = .gif
        } else if type.conforms(to: .bmp) {
            self = .bmp
        } else {
            return nil
        }
    }
}

extension RGBAImage {
    /// The pixels as a CGImage (sRGB, straight alpha), for ImageIO's encoders.
    func makeCGImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let alpha: CGImageAlphaInfo = isOpaque ? .noneSkipLast : .last
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: alpha.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
