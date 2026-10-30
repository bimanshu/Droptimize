import Foundation

/// The image formats Droptimize reads (CORE.md §6.1).
enum ImageFormat: String, CaseIterable {
    case jpeg, png, webp, heic, avif, tiff, gif, bmp

    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg", "jpe": self = .jpeg
        case "png": self = .png
        case "webp": self = .webp
        case "heic", "heif": self = .heic
        case "avif": self = .avif
        case "tif", "tiff": self = .tiff
        case "gif": self = .gif
        case "bmp": self = .bmp
        default: return nil
        }
    }

    /// How the format is named in the menu.
    var displayName: String {
        switch self {
        case .jpeg: return "JPG"
        case .webp: return "WebP"
        default: return rawValue.uppercased()
        }
    }

    /// The extension for a new file in this format.
    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        default: return rawValue
        }
    }
}
