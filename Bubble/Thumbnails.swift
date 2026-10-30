import AppKit
import QuickLookThumbnailing

enum Thumbnails {
    /// A square-ish thumbnail of the file at `url` (images and videos alike), or its Finder icon.
    static func make(for url: URL, side: CGFloat, scale: CGFloat) async -> NSImage {
        let request = QLThumbnailGenerator.Request(fileAt: url,
                                                   size: CGSize(width: side, height: side),
                                                   scale: scale,
                                                   representationTypes: .thumbnail)
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            return representation.nsImage
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
