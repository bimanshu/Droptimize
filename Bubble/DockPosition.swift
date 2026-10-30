import Foundation

/// Where the bubble rests on one display: which edge, and how far up it (0 = lowest, 1 = highest).
/// Stored as a fraction so it survives resolution and Dock changes.
struct DockPosition: Codable, Equatable {
    var side: DockSide
    var height: Double

    /// Right edge, vertically centered (CORE.md §4.1).
    static let `default` = DockPosition(side: .right, height: 0.5)

    /// The bubble's center for this position inside a screen's `visibleFrame`.
    func center(in visibleFrame: CGRect) -> CGPoint {
        let x = side == .right
            ? visibleFrame.maxX - Motion.edgeInset - Motion.bubbleDiameter / 2
            : visibleFrame.minX + Motion.edgeInset + Motion.bubbleDiameter / 2
        let range = Self.verticalRange(in: visibleFrame)
        let y = range.lowerBound + CGFloat(Self.clamp(height)) * (range.upperBound - range.lowerBound)
        return CGPoint(x: x, y: y)
    }

    /// The resting position nearest to a bubble that's been dragged to `point`.
    static func nearest(to point: CGPoint, in visibleFrame: CGRect) -> DockPosition {
        let side: DockSide = point.x < visibleFrame.midX ? .left : .right
        let range = verticalRange(in: visibleFrame)
        let length = range.upperBound - range.lowerBound
        let height = length > 0 ? Double((point.y - range.lowerBound) / length) : 0.5
        return DockPosition(side: side, height: clamp(height))
    }

    /// Bubble centers stay this far inside the top and bottom so the whole menu fits on screen.
    static func verticalRange(in visibleFrame: CGRect) -> ClosedRange<CGFloat> {
        let clearance = BubbleLayout.verticalClearance
        let low = visibleFrame.minY + clearance
        let high = visibleFrame.maxY - clearance
        return low <= high ? low...high : visibleFrame.midY...visibleFrame.midY
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}

/// Remembers the bubble's position per display, and which display it was last on.
struct DockStore {
    var defaults: UserDefaults = .standard

    func position(forDisplay id: String) -> DockPosition? {
        defaults.data(forKey: key(id)).flatMap { try? JSONDecoder().decode(DockPosition.self, from: $0) }
    }

    func save(_ position: DockPosition, forDisplay id: String) {
        guard let data = try? JSONEncoder().encode(position) else { return }
        defaults.set(data, forKey: key(id))
        defaults.set(id, forKey: Self.lastDisplayKey)
    }

    var lastDisplay: String? { defaults.string(forKey: Self.lastDisplayKey) }

    private static let lastDisplayKey = "bubble.lastDisplay"
    private func key(_ id: String) -> String { "bubble.position.\(id)" }
}
