import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// A spring described the way SwiftUI describes one: `response` is roughly the period in
/// seconds, `damping` is the damping fraction (1 = no overshoot, lower = more bounce).
struct SpringSpec: Equatable {
    var response: Double
    var damping: Double
}

/// Every size, spring, delay and opacity that shapes how the bubble feels.
/// Tune here and nowhere else (CORE.md §4.5). Values marked (tune) are starting points.
enum Motion {
    // MARK: Bubble

    static let bubbleDiameter: CGFloat = 44                // (tune)
    static let bubbleIdleOpacity: Double = 0.6             // (tune)
    static let bubbleHoverScale: CGFloat = 1.06
    /// How much the bubble grows while a drag is over it.
    static let bubbleAwakeScale: CGFloat = 1.2
    static let bubbleShadowRadius: CGFloat = 8
    /// Gap between the bubble and the screen edge it docks to.
    static let edgeInset: CGFloat = 12
    /// The panel while idle or working: room for hover growth, the shadow and the progress ring.
    static let idlePanelSide: CGFloat = 80
    static let progressRingDiameter: CGFloat = 54
    static let progressLineWidth: CGFloat = 3

    // MARK: Radial menu

    /// The ring's radius with up to five segments; it grows for six (see RadialLayout.radius(for:)).
    static let ringRadius: CGFloat = 80                    // (tune)
    static let segmentDiameter: CGFloat = 40               // (tune)
    static let segmentHoverScale: CGFloat = 1.15
    /// The least space between neighbouring segments, even with one hovered. The ring grows to keep it.
    static let segmentGap: CGFloat = 4
    /// The arc the segments spread over, facing into the screen (radians).
    static let arcSpan: Double = 160 * .pi / 180          // (tune)
    /// Inside this distance from the bubble's center, a drop means Auto.
    static let centerHitRadius: CGFloat = 30
    /// Delay between segments as they fan out (CORE.md §4.2: ~20–30ms).
    static let fanStagger: Double = 0.025                  // (tune)
    /// Empty space kept around everything the panel has to show.
    static let panelMargin: CGFloat = 12
    /// Fill behind the open menu so the gaps between segments still catch the drag. Fully
    /// transparent pixels let drags fall through to the window below; this must stay
    /// at or above 1/255 to survive 8-bit alpha.
    static let hitCatchOpacity: Double = 0.01

    // MARK: Accessory (the result card or a one-line message beside the bubble)

    static let accessoryGap: CGFloat = 10
    static let accessoryMaxWidth: CGFloat = 240
    static let accessoryHeight: CGFloat = 56
    static let thumbnailSide: CGFloat = 40

    // MARK: Springs

    static let spring = SpringSpec(response: 0.35, damping: 0.75)        // (tune)
    static let hoverSpring = SpringSpec(response: 0.2, damping: 0.8)
    /// Springing the bubble back to an edge after it's been moved.
    static let snapSpring = SpringSpec(response: 0.4, damping: 0.8)

    // MARK: Timing (seconds)

    /// How long the result rests beside the bubble (CORE.md §4.3: ~4s).
    static let doneDuration: Double = 4                    // (tune)
    static let messageDuration: Double = 2.5
    /// Extra time the result stays when the pointer has just left it.
    static let hoverGrace: Double = 1
    /// How long the panel stays big after the menu folds, so the fold-in and ripple can finish.
    static let collapseSettle: Double = 0.45
    static let rippleDuration: Double = 0.4
    static let rippleDiameter: CGFloat = 24
    static let shakeDuration: Double = 0.4
    static let shakeTravel: CGFloat = 6
    /// With Reduce Motion on, everything fades over this long instead of scaling or moving.
    static let reducedMotionFade: Double = 0.15

    // MARK: Pointer

    /// How far the pointer must travel before a press becomes a drag.
    static let dragThreshold: CGFloat = 3
}

#if canImport(SwiftUI)
extension SpringSpec {
    var animation: Animation { .spring(response: response, dampingFraction: damping) }
}
#endif
