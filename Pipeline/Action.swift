import Foundation

/// Everything a drop can ask for. Image actions are Phase 1, video actions Phase 2 (CORE.md §6.5, §7.4).
enum Action: String, CaseIterable, Identifiable {
    case auto
    // Images
    case webp, avif, compress, halfSize, removeBackground
    // Video
    case mp4, webm, gif, scale1080p, mute

    var id: String { rawValue }

    /// The one-word label shown while hovering.
    var title: String {
        switch self {
        case .auto: return "Auto"
        case .webp: return "WebP"
        case .avif: return "AVIF"
        case .compress: return "Compress"
        case .halfSize: return "Half size"
        case .removeBackground: return "Remove BG"
        case .mp4: return "MP4"
        case .webm: return "WebM"
        case .gif: return "GIF"
        case .scale1080p: return "1080p"
        case .mute: return "Mute"
        }
    }

    /// SF Symbol name.
    var symbol: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .webp: return "w.circle"
        case .avif: return "a.circle"
        case .compress: return "rectangle.compress.vertical"
        case .halfSize: return "arrow.down.right.and.arrow.up.left"
        case .removeBackground: return "scissors"
        case .mp4: return "film"
        case .webm: return "globe"
        case .gif: return "repeat"
        case .scale1080p: return "arrow.down.right.and.arrow.up.left"
        case .mute: return "speaker.slash"
        }
    }

    /// What VoiceOver says for the segment.
    var accessibilityLabel: String {
        switch self {
        case .auto: return "Optimize automatically"
        case .webp: return "Convert to WebP"
        case .avif: return "Convert to AVIF"
        case .compress: return "Compress, same format"
        case .halfSize: return "Half size"
        case .removeBackground: return "Remove background"
        case .mp4: return "Convert to MP4"
        case .webm: return "Convert to WebM"
        case .gif: return "Convert to GIF"
        case .scale1080p: return "Scale down to 1080p"
        case .mute: return "Remove audio"
        }
    }
}

/// What the media in a drag is.
enum MediaKind: Hashable {
    case image, video
}

/// What the radial menu offers for one drag: Auto in the center, up to six segments around it.
struct ActionMenu: Equatable {
    static let maxSegments = 6

    var center: Action
    var segments: [Action]

    init(center: Action = .auto, segments: [Action]) {
        assert(segments.count <= Self.maxSegments, "More than six segments is unreadable at drag speed")
        self.center = center
        self.segments = segments
    }

    /// Listed top to bottom as they sit on the arc (CORE.md §4.2).
    static let image = ActionMenu(segments: [.webp, .avif, .compress, .halfSize, .removeBackground])
    static let video = ActionMenu(segments: [.mp4, .webm, .gif, .scale1080p, .mute])
    /// Images and videos together: only what applies to both.
    static let mixed = ActionMenu(segments: [.compress])

    /// The menu for a drag carrying `kinds`, or nil when there's nothing to offer.
    init?(kinds: Set<MediaKind>) {
        switch kinds {
        case []: return nil
        case [.image]: self = .image
        case [.video]: self = .video
        default: self = .mixed
        }
    }

    func action(for target: MenuTarget) -> Action? {
        switch target {
        case .center: return center
        case .segment(let index): return segments.indices.contains(index) ? segments[index] : nil
        }
    }
}
