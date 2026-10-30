import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Apple's built-in encoders: JPEG until jpegli arrives (CORE.md §6.3), HEIC, and plain PNG
/// for the clipboard. Only the pixels are written, so no metadata comes along (CORE.md §6.2).
enum ImageIOEncoder {
    enum Failure: Error {
        case encoding
    }

    static func encode(_ image: RGBAImage, as type: UTType, quality: Double? = nil) throws -> Data {
        guard let cgImage = image.makeCGImage() else { throw Failure.encoding }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw Failure.encoding
        }
        var properties: [CFString: Any] = [:]
        if let quality { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        if type == .jpeg {
            properties[kCGImagePropertyJFIFDictionary] = [kCGImagePropertyJFIFIsProgressive: true]
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encoding }
        return data as Data
    }
}
