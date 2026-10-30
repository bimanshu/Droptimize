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

/// What the radial menu offers for one drag: Auto in the center, up to six segments around it,
/// and for some segments a second ring of options (CORE.md §4.2).
struct ActionMenu: Equatable {
    static let maxSegments = 6
    static let maxOptions = 6

    var center: Action
    var segments: [Action]
    /// Each segment's option bubbles, in segment order (empty when it has none).
    var options: [[MenuOption]]

    init(center: Action = .auto, segments: [Action], lastColor: RGBColor? = nil) {
        assert(segments.count <= Self.maxSegments, "More than six segments is unreadable at drag speed")
        self.center = center
        self.segments = segments
        self.options = segments.map { $0.options(lastColor: lastColor) }
        assert(options.allSatisfy { $0.count <= Self.maxOptions }, "More than six options is unreadable at drag speed")
    }

    /// Listed top to bottom as they sit on the arc.
    static let imageSegments: [Action] = [.webp, .avif, .compress, .halfSize, .removeBackground]
    static let videoSegments: [Action] = [.mp4, .webm, .gif, .scale1080p, .mute]
    /// Images and videos together: only what applies to both.
    static let mixedSegments: [Action] = [.compress]

    static let image = ActionMenu(segments: imageSegments)
    static let video = ActionMenu(segments: videoSegments)
    static let mixed = ActionMenu(segments: mixedSegments)

    /// The menu for a drag carrying `kinds`, or nil when there's nothing to offer.
    init?(kinds: Set<MediaKind>, lastColor: RGBColor? = nil) {
        switch kinds {
        case []: return nil
        case [.image]: self.init(segments: Self.imageSegments, lastColor: lastColor)
        case [.video]: self.init(segments: Self.videoSegments, lastColor: lastColor)
        default: self.init(segments: Self.mixedSegments, lastColor: lastColor)
        }
    }

    func action(for target: MenuTarget) -> Action? {
        switch target {
        case .center: return center
        case .segment(let index), .option(let index, _):
            return segments.indices.contains(index) ? segments[index] : nil
        }
    }

    /// The option bubble `target` points at, if it's one.
    func option(for target: MenuTarget) -> MenuOption? {
        guard case .option(let segment, let index) = target,
              options.indices.contains(segment), options[segment].indices.contains(index) else { return nil }
        return options[segment][index]
    }

    /// What the bubble shows while `target` is hovered.
    func title(for target: MenuTarget) -> String? {
        option(for: target)?.title ?? action(for: target)?.title
    }

    var geometryOptionCounts: [Int] { options.map(\.count) }
}
