import Foundation

/// Everything a drop can ask for. Image actions are Phase 1, video actions Phase 2 (CORE.md §6.5, §7.4).
enum Action: String, CaseIterable, Identifiable {
    case auto
    // Images
    case convert, compress, halfSize, removeBackground
    // Video
    case resize, mute

    var id: String { rawValue }

    /// The one-word label shown while hovering.
    var title: String {
        switch self {
        case .auto: return "Auto"
        case .convert: return "Convert"
        case .compress: return "Compress"
        case .halfSize: return "Half size"
        case .removeBackground: return "Remove BG"
        case .resize: return "Resize"
        case .mute: return "Mute"
        }
    }

    /// SF Symbol name.
    var symbol: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .convert: return "arrow.triangle.2.circlepath"
        case .compress: return "rectangle.compress.vertical"
        case .halfSize: return "arrow.down.right.and.arrow.up.left"
        case .removeBackground: return "scissors"
        case .resize: return "aspectratio"
        case .mute: return "speaker.slash"
        }
    }

    /// What VoiceOver says for the segment.
    var accessibilityLabel: String {
        switch self {
        case .auto: return "Optimize automatically"
        case .convert: return "Convert to another format"
        case .compress: return "Compress, same format"
        case .halfSize: return "Half size"
        case .removeBackground: return "Remove background"
        case .resize: return "Resize the video"
        case .mute: return "Remove the sound"
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

    /// `kind` decides the option bubbles (image sizes in KB, video sizes in MB…); nil for a mixed drop.
    init(center: Action = .auto, segments: [Action], kind: MediaKind? = .image, lastColor: RGBColor? = nil) {
        assert(segments.count <= Self.maxSegments, "More than six segments is unreadable at drag speed")
        self.center = center
        self.segments = segments
        self.options = segments.map { $0.options(for: kind, lastColor: lastColor) }
        assert(options.allSatisfy { $0.count <= Self.maxOptions }, "More than six options is unreadable at drag speed")
    }

    /// Listed top to bottom as they sit on the arc.
    static let imageSegments: [Action] = [.convert, .compress, .halfSize, .removeBackground]
    static let videoSegments: [Action] = [.convert, .compress, .resize, .mute]
    /// Images and videos together: only what applies to both.
    static let mixedSegments: [Action] = [.compress]

    static let image = ActionMenu(segments: imageSegments, kind: .image)
    static let video = ActionMenu(segments: videoSegments, kind: .video)
    static let mixed = ActionMenu(segments: mixedSegments, kind: nil)

    /// The menu for a drag carrying `kinds`, or nil when there's nothing to offer.
    init?(kinds: Set<MediaKind>, lastColor: RGBColor? = nil) {
        switch kinds {
        case []: return nil
        case [.image]: self.init(segments: Self.imageSegments, kind: .image, lastColor: lastColor)
        case [.video]: self.init(segments: Self.videoSegments, kind: .video, lastColor: lastColor)
        default: self.init(segments: Self.mixedSegments, kind: nil, lastColor: lastColor)
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
