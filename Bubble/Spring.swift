import Foundation

/// A damped spring for a 2D point, stepped frame by frame. Drives motion SwiftUI can't
/// animate for us, like springing the panel back to the screen edge. Uses the same model as
/// SwiftUI's `.spring(response:dampingFraction:)` (unit mass).
struct SpringSimulation {
    var spec: SpringSpec
    var position: CGPoint
    var target: CGPoint
    var velocity = CGVector(dx: 0, dy: 0)

    /// Within this distance (pt) and speed (pt/s) the spring counts as settled.
    static let restDistance: Double = 0.5
    static let restSpeed: Double = 10

    init(spec: SpringSpec, position: CGPoint, target: CGPoint) {
        self.spec = spec
        self.position = position
        self.target = target
    }

    /// Advances by `elapsed` seconds. Returns true once settled, with the position snapped to the target.
    mutating func step(_ elapsed: Double) -> Bool {
        let stiffness = pow(2 * .pi / spec.response, 2)
        let damping = 4 * .pi * spec.damping / spec.response
        let substep = 1.0 / 240
        // A long hitch shouldn't fling the bubble across the screen.
        var remaining = min(max(elapsed, 0), 1.0 / 15)
        var x = Double(position.x), y = Double(position.y)
        var vx = Double(velocity.dx), vy = Double(velocity.dy)
        let tx = Double(target.x), ty = Double(target.y)
        while remaining > 0 {
            let h = min(substep, remaining)
            vx += (-stiffness * (x - tx) - damping * vx) * h
            vy += (-stiffness * (y - ty) - damping * vy) * h
            x += vx * h
            y += vy * h
            remaining -= h
        }
        if hypot(x - tx, y - ty) < Self.restDistance, hypot(vx, vy) < Self.restSpeed {
            position = target
            velocity = CGVector(dx: 0, dy: 0)
            return true
        }
        position = CGPoint(x: x, y: y)
        velocity = CGVector(dx: vx, dy: vy)
        return false
    }
}
