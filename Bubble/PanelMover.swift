import AppKit
import QuartzCore

/// Springs the bubble's center to a point, frame by frame, in step with the display.
@MainActor
final class PanelMover: NSObject {
    private let view: NSView
    private var link: CADisplayLink?
    private var spring: SpringSimulation?
    private var lastTimestamp: CFTimeInterval?
    private var onStep: ((CGPoint) -> Void)?

    init(view: NSView) {
        self.view = view
    }

    var isMoving: Bool { link != nil }

    /// Calls `onStep` with each new center until the spring settles on `end`.
    func animate(from start: CGPoint, to end: CGPoint, onStep: @escaping (CGPoint) -> Void) {
        stop()
        spring = SpringSimulation(spec: Motion.snapSpring, position: start, target: end)
        self.onStep = onStep
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        spring = nil
        lastTimestamp = nil
        onStep = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard var spring, let onStep else { return stop() }
        let elapsed = lastTimestamp.map { link.timestamp - $0 } ?? (link.targetTimestamp - link.timestamp)
        lastTimestamp = link.timestamp
        let settled = spring.step(elapsed)
        self.spring = spring
        onStep(spring.position)
        if settled { stop() }
    }
}
