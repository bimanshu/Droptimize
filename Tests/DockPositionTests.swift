import XCTest
@testable import Droptimize

// Portable: also runs on Linux via scripts/check-linux.sh.
final class DockPositionTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)

    func testDefaultIsRightEdgeVerticallyCentered() {
        let center = DockPosition.default.center(in: screen)
        XCTAssertEqual(center.x, screen.maxX - Motion.edgeInset - Motion.bubbleDiameter / 2)
        XCTAssertEqual(center.y, screen.midY, accuracy: 0.5)
    }

    func testSnapsToTheNearestSide() {
        XCTAssertEqual(DockPosition.nearest(to: CGPoint(x: 300, y: 400), in: screen).side, .left)
        XCTAssertEqual(DockPosition.nearest(to: CGPoint(x: 1100, y: 400), in: screen).side, .right)
    }

    func testRoundTripsThroughCenter() {
        for side in [DockSide.left, .right] {
            for height in [0.0, 0.25, 0.5, 1.0] {
                let position = DockPosition(side: side, height: height)
                let back = DockPosition.nearest(to: position.center(in: screen), in: screen)
                XCTAssertEqual(back.side, side)
                XCTAssertEqual(back.height, height, accuracy: 0.001)
            }
        }
    }

    func testKeepsTheWholeMenuOnScreen() {
        let low = DockPosition.nearest(to: CGPoint(x: 1400, y: -500), in: screen).center(in: screen)
        let high = DockPosition.nearest(to: CGPoint(x: 1400, y: 5000), in: screen).center(in: screen)
        XCTAssertEqual(low.y, screen.minY + BubbleLayout.verticalClearance, accuracy: 0.001)
        XCTAssertEqual(high.y, screen.maxY - BubbleLayout.verticalClearance, accuracy: 0.001)
    }

    func testWorksOnScreensWithAnOffsetOrigin() {
        let secondary = CGRect(x: -1920, y: 200, width: 1920, height: 1055)
        let center = DockPosition(side: .left, height: 0.5).center(in: secondary)
        XCTAssertEqual(center.x, secondary.minX + Motion.edgeInset + Motion.bubbleDiameter / 2)
        XCTAssertEqual(center.y, secondary.midY, accuracy: 0.5)
    }

    func testTinyScreensStillGetACenter() {
        let tiny = CGRect(x: 0, y: 0, width: 400, height: 100)
        XCTAssertEqual(DockPosition.default.center(in: tiny).y, tiny.midY)
    }

    func testStoreRemembersPositionPerDisplay() throws {
        let suite = "DockPositionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DockStore(defaults: defaults)
        XCTAssertNil(store.position(forDisplay: "a"))
        store.save(DockPosition(side: .left, height: 0.2), forDisplay: "a")
        store.save(DockPosition(side: .right, height: 0.9), forDisplay: "b")
        XCTAssertEqual(store.position(forDisplay: "a"), DockPosition(side: .left, height: 0.2))
        XCTAssertEqual(store.position(forDisplay: "b"), DockPosition(side: .right, height: 0.9))
        XCTAssertEqual(store.lastDisplay, "b")
    }
}
