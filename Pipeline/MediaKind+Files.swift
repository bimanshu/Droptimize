import Foundation
import UniformTypeIdentifiers

extension MediaKind {
    /// The kind of media at `url`, or nil when Droptimize can't handle it (yet).
    init?(url: URL) {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        guard let type else { return nil }
        // SVG conforms to public.image but is out of scope for v1 (CORE.md §6.1).
        if type.conforms(to: .svg) { return nil }
        if type.conforms(to: .image) {
            self = .image
        } else if type.conforms(to: .movie) || type.conforms(to: .video) {
            self = .video
        } else {
            return nil
        }
    }
}
