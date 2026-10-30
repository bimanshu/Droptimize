import Foundation

// Pure geometry: Foundation only, so it's unit-tested on Linux too (scripts/check-linux.sh).
// All offsets are in points relative to the bubble's center, with y pointing up (AppKit's convention).

/// Which screen edge the bubble is docked to.
enum DockSide: String, Codable {
    case left, right

    /// +1 when "into the screen" is +x (docked left), -1 when docked right.
    var inward: CGFloat { self == .left ? 1 : -1 }
}

/// What a drag is over: the bubble's center (Auto), one of the menu's segments, or one of
/// the smaller option bubbles that fan out beyond a segment.
enum MenuTarget: Equatable {
    case center
    case segment(Int)
    case option(segment: Int, index: Int)

    /// The segment this target belongs to, if any.
    var segment: Int? {
        switch self {
        case .center: return nil
        case .segment(let segment), .option(let segment, _): return segment
        }
    }
}

/// Where the radial menu's segments sit, and which one is under the pointer.
///
/// Segments spread over an arc that faces into the screen (the bubble is always docked to an
/// edge, so a full ring would be half off-screen), ordered top to bottom.
struct RadialLayout {
    var count: Int
    var side: DockSide
    var radius: CGFloat
    var span: Double = Motion.arcSpan
    var centerHitRadius: CGFloat = Motion.centerHitRadius

    init(count: Int, side: DockSide) {
        self.count = count
        self.side = side
        self.radius = Self.radius(for: count)
    }

    /// The ring's radius: `Motion.ringRadius`, grown when there are so many segments that a
    /// hovered one would touch its neighbours.
    static func radius(for count: Int) -> CGFloat {
        guard count > 1 else { return Motion.ringRadius }
        let step = Motion.arcSpan / Double(count - 1)
        let spacing = Double(Motion.segmentDiameter * Motion.segmentHoverScale + Motion.segmentGap)
        return max(Motion.ringRadius, CGFloat(spacing / (2 * sin(step / 2))).rounded(.up))
    }

    /// The largest the ring ever gets.
    static var maxRadius: CGFloat { radius(for: ActionMenu.maxSegments) }

    /// Angle between neighbouring segments (radians); zero with one segment.
    var step: Double { count > 1 ? span / Double(count - 1) : 0 }

    /// Angle of a segment, counterclockwise from +x.
    func angle(of index: Int) -> Double {
        let base: Double = side == .right ? .pi : 0
        guard count > 1 else { return base }
        // Docked right the arc runs top → left → bottom (increasing angle); docked left it
        // runs top → right → bottom (decreasing angle). Either way index 0 is the top one.
        let direction: Double = side == .right ? 1 : -1
        return base + direction * (-span / 2 + Double(index) * step)
    }

    func offset(of index: Int) -> CGVector {
        let angle = angle(of: index)
        return CGVector(dx: radius * CGFloat(cos(angle)), dy: radius * CGFloat(sin(angle)))
    }

    /// The target under `point`, or nil when it's outside the center and every segment's sector.
    /// Segments are picked by angle alone, which is forgiving at drag speed.
    func target(at point: CGVector) -> MenuTarget? {
        let distance = hypot(Double(point.dx), Double(point.dy))
        if distance <= Double(centerHitRadius) { return .center }
        guard count > 0 else { return nil }
        let pointAngle = atan2(Double(point.dy), Double(point.dx))
        let halfSector = count > 1 ? step / 2 : span / 2
        var best: (index: Int, delta: Double)?
        for index in 0..<count {
            let delta = Self.angularDistance(pointAngle, angle(of: index))
            if delta <= halfSector, delta < (best?.delta ?? .infinity) {
                best = (index, delta)
            }
        }
        return best.map { .segment($0.index) }
    }

    /// The smaller angle between two directions, in 0...π.
    static func angularDistance(_ a: Double, _ b: Double) -> Double {
        var delta = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
        if delta < 0 { delta += 2 * .pi }
        return min(delta, 2 * .pi - delta)
    }
}

/// The smaller option bubbles that fan out beyond a hovered segment (Compress sizes, Remove BG
/// backgrounds) on a second, outer ring.
///
/// They're centered on their segment's angle, but pushed back toward the middle of the inward
/// side when that would put one past the screen edge.
struct SubmenuLayout: Equatable {
    var count: Int
    var side: DockSide
    var parentAngle: Double
    /// The main ring's radius; the options sit `Motion.optionRingDistance` beyond it.
    var ringRadius: CGFloat

    var radius: CGFloat { ringRadius + Motion.optionRingDistance }

    /// Angle between neighbouring options, so hovered ones never touch.
    var step: Double {
        let spacing = Double(Motion.optionDiameter * Motion.optionHoverScale + Motion.segmentGap)
        return 2 * asin(min(1, spacing / (2 * Double(radius))))
    }

    var span: Double { step * Double(max(count - 1, 0)) }

    var centerAngle: Double {
        let base: Double = side == .right ? .pi : 0
        let relative = atan2(sin(parentAngle - base), cos(parentAngle - base))
        let room = max(0, Motion.optionArcLimit - span / 2)
        return base + min(max(relative, -room), room)
    }

    /// Index 0 is the top one, like the main ring.
    func angle(of index: Int) -> Double {
        let direction: Double = side == .right ? 1 : -1
        return centerAngle + direction * (-span / 2 + Double(index) * step)
    }

    func offset(of index: Int) -> CGVector {
        let angle = angle(of: index)
        return CGVector(dx: radius * CGFloat(cos(angle)), dy: radius * CGFloat(sin(angle)))
    }

    /// Past this distance from the bubble's center, the pointer picks options instead of segments:
    /// halfway between the two rings.
    var innerBoundary: CGFloat { (ringRadius + radius) / 2 }

    /// The option under `point` (already in the outer zone), or nil between or beyond them.
    func option(at point: CGVector) -> Int? {
        guard count > 0 else { return nil }
        let pointAngle = atan2(Double(point.dy), Double(point.dx))
        var best: (index: Int, delta: Double)?
        for index in 0..<count {
            let delta = RadialLayout.angularDistance(pointAngle, angle(of: index))
            if delta <= step / 2, delta < (best?.delta ?? .infinity) { best = (index, delta) }
        }
        return best?.index
    }
}

/// The whole menu's geometry: the main ring plus whichever segment's options are showing.
struct MenuGeometry {
    var side: DockSide
    var ring: RadialLayout
    /// How many options each segment has (0: none).
    var optionCounts: [Int]

    init(side: DockSide, optionCounts: [Int]) {
        self.side = side
        self.ring = RadialLayout(count: optionCounts.count, side: side)
        self.optionCounts = optionCounts
    }

    func submenu(for segment: Int) -> SubmenuLayout? {
        guard optionCounts.indices.contains(segment), optionCounts[segment] > 0 else { return nil }
        return SubmenuLayout(count: optionCounts[segment], side: side,
                             parentAngle: ring.angle(of: segment), ringRadius: ring.radius)
    }

    /// The target under `point`, given which segment's options are showing.
    func target(at point: CGVector, openSubmenu: Int?) -> MenuTarget? {
        if let segment = openSubmenu, let submenu = submenu(for: segment),
           hypot(Double(point.dx), Double(point.dy)) >= Double(submenu.innerBoundary) {
            return submenu.option(at: point).map { .option(segment: segment, index: $0) }
        }
        return ring.target(at: point)
    }

    /// Which segment's options should show with the pointer over `target`. Hovering a segment
    /// opens its options; they stay open while the pointer is out among them.
    func openSubmenu(after target: MenuTarget?, current: Int?) -> Int? {
        switch target {
        case .segment(let segment): return submenu(for: segment) != nil ? segment : nil
        case .option(let segment, _): return segment
        case .center: return nil
        case nil: return current
        }
    }
}

/// What the panel currently has to show, which decides its size.
enum PanelContent: Equatable {
    /// Idle or working: just the bubble.
    case bubble
    /// The open radial menu with this many segments, and one segment's options if showing.
    case menu(segments: Int, submenu: SubmenuLayout?)
    /// The result card or a one-line message beside the bubble.
    case accessory
}

/// How big the panel is in each state, and where things sit inside it.
///
/// The SwiftUI canvas is a fixed square centered on the bubble that's big enough for every
/// state. Only the panel (the window) grows and shrinks around it, so the drawn content never
/// moves when the panel resizes.
struct BubbleLayout {
    var side: DockSide

    static var canvasSide: CGFloat {
        let ring = RadialLayout.maxRadius + Motion.optionRingDistance + optionReach + Motion.panelMargin
        let accessory = accessoryNear + Motion.accessoryMaxWidth + Motion.panelMargin
        return 2 * max(ring, accessory, Motion.idlePanelSide / 2).rounded(.up)
    }

    /// Diameter of the invisible disc that keeps catching the drag between segments (and
    /// out to the options, when they're showing).
    static func catchDiameter(segments: Int, submenu: SubmenuLayout?) -> CGFloat {
        let reach = submenu.map { $0.radius + optionReach } ?? RadialLayout.radius(for: segments) + segmentReach
        return 2 * (reach + Motion.panelMargin)
    }

    /// How far the bubble's center must stay from the top and bottom of the screen so the
    /// whole menu fits.
    static var verticalClearance: CGFloat {
        let ring = RadialLayout.maxRadius * CGFloat(sin(min(Motion.arcSpan / 2, .pi / 2))) + segmentReach
        let options = (RadialLayout.maxRadius + Motion.optionRingDistance)
            * CGFloat(sin(min(Motion.optionArcLimit, .pi / 2))) + optionReach
        return max(max(ring, options) + Motion.panelMargin, Motion.idlePanelSide / 2)
    }

    /// The panel's frame for `content`, given the bubble's center in screen coordinates.
    func panelFrame(for content: PanelContent, center: CGPoint) -> CGRect {
        let half = Motion.idlePanelSide / 2
        let idle = CGRect(x: center.x - half, y: center.y - half, width: 2 * half, height: 2 * half)
        switch content {
        case .bubble:
            return idle.integral
        case .menu(let count, let submenu):
            let ring = RadialLayout(count: count, side: side)
            var frame = idle
            func include(_ offset: CGVector, reach: CGFloat) {
                frame = frame.union(CGRect(x: center.x + offset.dx - reach, y: center.y + offset.dy - reach,
                                           width: 2 * reach, height: 2 * reach))
            }
            for index in 0..<count {
                include(ring.offset(of: index), reach: Self.segmentReach + Motion.panelMargin)
            }
            if let submenu {
                for index in 0..<submenu.count {
                    include(submenu.offset(of: index), reach: Self.optionReach + Motion.panelMargin)
                }
            }
            return frame.integral
        case .accessory:
            let accessory = accessoryRect(center: center).insetBy(dx: -Motion.panelMargin, dy: -Motion.panelMargin)
            return idle.union(accessory).integral
        }
    }

    /// The room for the result card or message, beside the bubble on the side facing into the screen.
    func accessoryRect(center: CGPoint) -> CGRect {
        let x = side == .right
            ? center.x - Self.accessoryNear - Motion.accessoryMaxWidth
            : center.x + Self.accessoryNear
        return CGRect(x: x, y: center.y - Motion.accessoryHeight / 2,
                      width: Motion.accessoryMaxWidth, height: Motion.accessoryHeight)
    }

    /// The accessory's center relative to the bubble's center.
    var accessoryOffset: CGVector {
        CGVector(dx: side.inward * (Self.accessoryNear + Motion.accessoryMaxWidth / 2), dy: 0)
    }

    /// Half a segment at its largest (hovered).
    private static var segmentReach: CGFloat { Motion.segmentDiameter * Motion.segmentHoverScale / 2 }

    /// Half an option bubble at its largest (hovered).
    private static var optionReach: CGFloat { Motion.optionDiameter * Motion.optionHoverScale / 2 }

    /// Distance from the bubble's center to the accessory's near edge.
    private static var accessoryNear: CGFloat { Motion.bubbleDiameter / 2 + Motion.accessoryGap }
}
