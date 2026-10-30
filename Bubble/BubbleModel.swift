import AppKit

/// Everything the bubble's views draw from. `BubbleController` changes it; views only read it.
@MainActor
final class BubbleModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        /// A drag with files we can handle is over the bubble.
        case menu
        /// Dropped on a Custom option; waiting for a size or color in the input panel.
        case asking
        case working(JobProgress)
        case done(DoneInfo)
        /// A short error or notice beside the bubble.
        case message(String)
    }

    @Published var phase: Phase = .idle
    @Published var side: DockSide = .right
    @Published var isHovering = false
    /// The menu last opened. Kept after it closes so the segments can animate out.
    @Published var menu: ActionMenu = .image
    @Published var target: MenuTarget?
    /// The segment whose option bubbles are showing, if any.
    @Published var submenu: Int?
    @Published var ripples: [Ripple] = []
    /// Bumped to shake the bubble once.
    @Published var shakes = 0

    var isMenuOpen: Bool { phase == .menu }
}

/// What the done state shows: the saving and a thumbnail to drag out.
struct DoneInfo: Equatable {
    let id = UUID()
    var saving: Double
    var count: Int
    var thumbnail: NSImage?
    /// Replaces the card's second line, such as "Resized to 1600 × 1200 to fit".
    var detail: String? = nil

    /// "−68%" (with a real minus sign), or "Done" when there's no saving to show.
    var savingText: String {
        let percent = Int((saving * 100).rounded())
        return percent > 0 ? "\u{2212}\(percent)%" : "Done"
    }
}

/// A ring that ripples out from where something was dropped.
struct Ripple: Identifiable, Equatable {
    let id = UUID()
    /// From the bubble's center, y up.
    var offset: CGVector
}
