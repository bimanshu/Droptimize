import Foundation

/// What an action turns an image into (CORE.md §6.5): which encoder, which extension and suffix, and the scale.
struct ImagePlan: Equatable {
    enum Encoding: Equatable {
        case webp, png, jpeg, heic, avif
    }

    var encoding: Encoding
    var fileExtension: String
    /// Added to the original's name, as in `photo-min.png`. Nil when the new extension is enough.
    var suffix: String?
    /// 1, or 0.5 for Half size.
    var scale: Double

    static let compressSuffix = "-min"
    static let halfSizeSuffix = "-half"

    /// Fails for actions that aren't built yet, before any work is done.
    static func scale(for action: Action) throws -> Double {
        switch action {
        case .auto, .webp, .avif, .compress, .removeBackground: return 1
        case .halfSize: return 0.5
        case .mp4, .webm, .gif, .scale1080p, .mute: throw JobError.notYet("Video is coming soon.")
        }
    }

    static let noBackgroundSuffix = "-nobg"
    static let backgroundSuffix = "-bg"

    /// The plan for `action` (and the option bubble it was dropped on, if any) on an image in
    /// `source` format, whose file ends in `sourceExtension`.
    static func make(action: Action, option: ActionOption? = nil, source: ImageFormat,
                     sourceExtension: String) throws -> ImagePlan {
        let scale = try scale(for: action)
        switch action {
        case .compress:
            let encoding = try sameFormatEncoding(for: source)
            let keepsFormat = encoding == sameFormatEncoding(ofExactly: source)
            let fileExtension = keepsFormat ? sourceExtension.lowercased() : extensionFor(encoding)
            let suffix: String?
            if case .maxBytes(let bytes) = option {
                suffix = ByteCount.suffix(bytes)            // photo-500kb.jpg
            } else {
                suffix = keepsFormat ? compressSuffix : nil
            }
            return ImagePlan(encoding: encoding, fileExtension: fileExtension, suffix: suffix, scale: scale)
        case .removeBackground:
            // Always PNG: it keeps the transparency, or the exact background color (CORE.md §6.5).
            var hasColor = false
            if case .background(.some) = option { hasColor = true }
            return ImagePlan(encoding: .png, fileExtension: "png",
                             suffix: hasColor ? backgroundSuffix : noBackgroundSuffix, scale: scale)
        case .auto, .webp:
            // Auto picks between formats once it can classify images (Phase 1 step 2); until then, WebP.
            return ImagePlan(encoding: .webp, fileExtension: "webp",
                             suffix: source == .webp ? compressSuffix : nil, scale: scale)
        case .avif:
            return ImagePlan(encoding: .avif, fileExtension: "avif",
                             suffix: source == .avif ? compressSuffix : nil, scale: scale)
        case .halfSize:
            let encoding = try sameFormatEncoding(for: source)
            let keepsFormat = encoding == sameFormatEncoding(ofExactly: source)
            let fileExtension = keepsFormat ? sourceExtension.lowercased() : extensionFor(encoding)
            return ImagePlan(encoding: encoding, fileExtension: fileExtension, suffix: halfSizeSuffix, scale: scale)
        default:
            throw JobError.notYet("Coming soon.")
        }
    }

    /// Compress keeps the format where it can (CORE.md §6.5). TIFF and BMP become PNG, losslessly.
    private static func sameFormatEncoding(for source: ImageFormat) throws -> Encoding {
        switch source {
        case .jpeg: return .jpeg
        case .png, .tiff, .bmp: return .png
        case .webp: return .webp
        case .heic: return .heic
        case .gif: throw JobError.notYet("GIFs can't be compressed yet.")
        case .avif: return .avif
        }
    }

    private static func sameFormatEncoding(ofExactly source: ImageFormat) -> Encoding? {
        switch source {
        case .jpeg: return .jpeg
        case .png: return .png
        case .webp: return .webp
        case .heic: return .heic
        case .avif: return .avif
        default: return nil
        }
    }

    private static func extensionFor(_ encoding: Encoding) -> String {
        switch encoding {
        case .webp: return "webp"
        case .png: return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .avif: return "avif"
        }
    }
}
