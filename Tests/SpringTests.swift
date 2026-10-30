import XCTest
@testable import Droptimize

// Portable: also runs on Linux via scripts/check-linux.sh.
final class SpringTests: XCTestCase {
    /// Runs at 120 fps until settled; returns the path and how long it took.
    private func run(_ spec: SpringSpec, from start: CGPoint, to end: CGPoint) -> (path: [CGPoint], seconds: Double) {
        var spring = SpringSimulation(spec: spec, position: start, target: end)
        var path: [CGPoint] = []
        var elapsed = 0.0
        while elapsed < 5 {
            elapsed += 1.0 / 120
            let settled = spring.step(1.0 / 120)
            path.append(spring.position)
            if settled { break }
        }
        return (path, elapsed)
    }

    func testSettlesExactlyOnTheTarget() {
        let end = CGPoint(x: 1400, y: 300)
        let result = run(Motion.snapSpring, from: CGPoint(x: 900, y: 420), to: end)
        XCTAssertEqual(result.path.last, end)
        XCTAssertLessThan(result.seconds, 1.5, "the snap should feel quick")
    }

    func testCriticallyDampedNeverOvershoots() {
        let result = run(SpringSpec(response: 0.4, damping: 1), from: .zero, to: CGPoint(x: 100, y: 0))
        XCTAssertLessThanOrEqual(result.path.map(\.x).max() ?? 0, 100.0001)
    }

    func testBouncySpringOvershootsALittle() {
        let result = run(SpringSpec(response: 0.4, damping: 0.5), from: .zero, to: CGPoint(x: 100, y: 0))
        let peak = result.path.map(\.x).max() ?? 0
        XCTAssertGreaterThan(peak, 100)
        XCTAssertLessThan(peak, 130)
    }

    func testAHitchDoesNotFlingIt() {
        var spring = SpringSimulation(spec: Motion.snapSpring, position: .zero, target: CGPoint(x: 100, y: 0))
        _ = spring.step(2)     // a two-second stall
        XCTAssertLessThan(abs(spring.position.x), 200)
    }
}
