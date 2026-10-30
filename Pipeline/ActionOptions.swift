import Foundation

/// A choice within an action, picked from the smaller bubbles that fan out around it.
enum ActionOption: Hashable {
    /// Convert to this format.
    case format(ImageFormat)
    /// Compress to at most this many bytes.
    case maxBytes(Int)
    /// Remove BG and put this color behind the subject; nil keeps it transparent.
    case background(RGBColor?)
    /// Ask after the drop (you can't type mid-drag): a size for Compress, a color for Remove BG.
    case custom
}

/// One option bubble: what it shows, and what it means.
struct MenuOption: Equatable {
    enum Label: Equatable {
        case text(String)
        case symbol(String)
        case swatch(RGBColor)
    }

    var option: ActionOption
    var label: Label
    /// Shown inside the bubble while hovered.
    var title: String
    var accessibilityLabel: String
}

/// Remembers custom choices between drops: the last color becomes its own bubble, and the
/// last size fills in the size field.
struct OptionMemory {
    var defaults: UserDefaults = .standard

    var lastColor: RGBColor? {
        get { defaults.string(forKey: "options.lastColor").flatMap(RGBColor.init(hex:)) }
        nonmutating set { defaults.set(newValue?.hex, forKey: "options.lastColor") }
    }

    var lastCustomSize: Int? {
        get { let bytes = defaults.integer(forKey: "options.lastCustomSize"); return bytes > 0 ? bytes : nil }
        nonmutating set { defaults.set(newValue, forKey: "options.lastCustomSize") }
    }
}

extension Action {
    /// Convert's formats: what web pages and upload fields take (the owner's choice, 2026-10-30).
    static let convertFormats: [ImageFormat] = [.webp, .avif, .jpeg, .png, .heic]

    /// Compress's target sizes (the owner's choice, 2026-10-30).
    static let targetSizes = [100_000, 250_000, 500_000, 1_000_000, 2_000_000]

    /// The option bubbles that fan out when this segment is hovered; empty when it has none.
    /// `lastColor` is the last custom background, offered again as its own bubble.
    func options(lastColor: RGBColor?) -> [MenuOption] {
        switch self {
        case .convert:
            return Self.convertFormats.map { format in
                MenuOption(option: .format(format), label: .text(format.displayName), title: "To \(format.displayName)",
                           accessibilityLabel: "Convert to \(format.displayName)")
            }
        case .compress:
            let sizes = Self.targetSizes.map { bytes in
                MenuOption(option: .maxBytes(bytes), label: .text(ByteCount.short(bytes)),
                           title: "Under \(ByteCount.describe(bytes))",
                           accessibilityLabel: "Compress to under \(ByteCount.describe(bytes))")
            }
            return sizes + [MenuOption(option: .custom, label: .symbol("ellipsis"), title: "Custom size",
                                       accessibilityLabel: "Compress to a size you choose")]
        case .removeBackground:
            var options = [
                MenuOption(option: .background(nil), label: .symbol("checkerboard.rectangle"),
                           title: "No background", accessibilityLabel: "Remove background, keep it transparent"),
                MenuOption(option: .background(.white), label: .swatch(.white),
                           title: "White", accessibilityLabel: "Remove background, put white behind"),
                MenuOption(option: .background(.black), label: .swatch(.black),
                           title: "Black", accessibilityLabel: "Remove background, put black behind"),
            ]
            if let lastColor, lastColor != .white, lastColor != .black {
                options.append(MenuOption(option: .background(lastColor), label: .swatch(lastColor),
                                          title: lastColor.hex,
                                          accessibilityLabel: "Remove background, put \(lastColor.hex) behind"))
            }
            options.append(MenuOption(option: .custom, label: .symbol("eyedropper"), title: "Custom color",
                                      accessibilityLabel: "Remove background, put a color you choose behind"))
            return options
        default:
            return []
        }
    }
}
