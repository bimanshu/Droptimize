import AppKit
import QuickLookThumbnailing

/// A finished thumbnail. `NSImage` isn't `Sendable`, but this one is never changed after it's
/// made, so it's safe to hand from the thumbnailing task to the main actor.
struct Thumbnail: @unchecked Sendable {
    let image: NSImage
}

enum Thumbnails {
    /// A thumbnail of the file at `url` (images and videos alike), or its Finder icon.
    static func make(for url: URL, side: CGFloat, scale: CGFloat) async -> Thumbnail {
        let request = QLThumbnailGenerator.Request(fileAt: url,
                                                   size: CGSize(width: side, height: side),
                                                   scale: scale,
                                                   representationTypes: .thumbnail)
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            return Thumbnail(image: representation.nsImage)
        }
        return Thumbnail(image: NSWorkspace.shared.icon(forFile: url.path))
    }
}
