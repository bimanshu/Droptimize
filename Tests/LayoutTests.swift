import XCTest
@testable import Droptimize

// Portable: also runs on Linux via scripts/check-linux.sh.
final class RadialLayoutTests: XCTestCase {
    func testSegmentsRunTopToBottomOnBothSides() {
        for side in [DockSide.left, .right] {
            let ring = RadialLayout(count: 5, side: side)
            let heights = (0..<5).map { ring.offset(of: $0).dy }
            XCTAssertEqual(heights, heights.sorted(by: >), "\(side): index 0 should be the top segment")
        }
    }

    func testSegmentsFaceIntoTheScreen() {
        for index in 0..<5 {
            XCTAssertLessThan(RadialLayout(count: 5, side: .right).offset(of: index).dx, 0)
            XCTAssertGreaterThan(RadialLayout(count: 5, side: .left).offset(of: index).dx, 0)
        }
    }

    func testSingleSegmentSitsStraightInward() {
        let offset = RadialLayout(count: 1, side: .right).offset(of: 0)
        XCTAssertEqual(offset.dx, -Motion.ringRadius, accuracy: 0.001)
        XCTAssertEqual(offset.dy, 0, accuracy: 0.001)
    }

    func testNeighbouringSegmentsNeverTouchEvenWhenHovered() {
        for count in 2...ActionMenu.maxSegments {
            let ring = RadialLayout(count: count, side: .right)
            for index in 1..<count {
                let a = ring.offset(of: index - 1), b = ring.offset(of: index)
                let distance = hypot(Double(a.dx - b.dx), Double(a.dy - b.dy))
                XCTAssertGreaterThanOrEqual(distance, Double(Motion.segmentDiameter * Motion.segmentHoverScale), "\(count) segments")
            }
        }
    }

    func testRingOnlyGrowsWhenItHasTo() {
        XCTAssertEqual(RadialLayout.radius(for: 5), Motion.ringRadius)
        XCTAssertGreaterThan(RadialLayout.radius(for: 6), Motion.ringRadius)
        XCTAssertEqual(RadialLayout.maxRadius, RadialLayout.radius(for: ActionMenu.maxSegments))
    }

    func testCenterIsAuto() {
        let ring = RadialLayout(count: 5, side: .right)
        XCTAssertEqual(ring.target(at: CGVector(dx: 0, dy: 0)), .center)
        XCTAssertEqual(ring.target(at: CGVector(dx: Motion.centerHitRadius - 1, dy: 0)), .center)
    }

    func testEachSegmentIsHitAtItsOwnPosition() {
        for side in [DockSide.left, .right] {
            for count in 1...ActionMenu.maxSegments {
                let ring = RadialLayout(count: count, side: side)
                for index in 0..<count {
                    XCTAssertEqual(ring.target(at: ring.offset(of: index)), .segment(index), "\(side) \(count) #\(index)")
                }
            }
        }
    }

    func testPointingAtTheDockedEdgeHitsNothing() {
        XCTAssertNil(RadialLayout(count: 5, side: .right).target(at: CGVector(dx: 60, dy: 0)))
        XCTAssertNil(RadialLayout(count: 5, side: .left).target(at: CGVector(dx: -60, dy: 0)))
    }

    func testAngularDistanceWrapsAround() {
        XCTAssertEqual(RadialLayout.angularDistance(0.1, 2 * .pi - 0.1), 0.2, accuracy: 1e-9)
        XCTAssertEqual(RadialLayout.angularDistance(.pi, -.pi), 0, accuracy: 1e-9)
    }
}

final class BubbleLayoutTests: XCTestCase {
    private let center = CGPoint(x: 1000, y: 500)

    func testEveryPanelFitsInsideTheCanvas() {
        let canvas = CGRect(x: center.x - BubbleLayout.canvasSide / 2, y: center.y - BubbleLayout.canvasSide / 2,
                            width: BubbleLayout.canvasSide, height: BubbleLayout.canvasSide)
        for side in [DockSide.left, .right] {
            let layout = BubbleLayout(side: side)
            var contents: [PanelContent] = [.bubble, .accessory]
            contents += (1...ActionMenu.maxSegments).map { PanelContent.menu(segments: $0) }
            for content in contents {
                let frame = layout.panelFrame(for: content, center: center)
                XCTAssertTrue(canvas.contains(frame), "\(side) \(content): \(frame) outside \(canvas)")
            }
        }
    }

    func testMenuPanelHoldsEverySegment() {
        let layout = BubbleLayout(side: .right)
        let frame = layout.panelFrame(for: .menu(segments: 5), center: center)
        let ring = RadialLayout(count: 5, side: .right)
        let reach = Motion.segmentDiameter * Motion.segmentHoverScale / 2
        for index in 0..<5 {
            let offset = ring.offset(of: index)
            let segment = CGRect(x: center.x + offset.dx - reach, y: center.y + offset.dy - reach,
                                 width: 2 * reach, height: 2 * reach)
            XCTAssertTrue(frame.contains(segment))
        }
    }

    func testIdlePanelIsCenteredOnTheBubble() {
        let frame = BubbleLayout(side: .right).panelFrame(for: .bubble, center: center)
        XCTAssertEqual(frame.midX, center.x, accuracy: 1)
        XCTAssertEqual(frame.midY, center.y, accuracy: 1)
    }

    func testAccessorySitsOnTheInwardSide() {
        XCTAssertLessThan(BubbleLayout(side: .right).accessoryRect(center: center).maxX, center.x)
        XCTAssertGreaterThan(BubbleLayout(side: .left).accessoryRect(center: center).minX, center.x)
        XCTAssertLessThan(BubbleLayout(side: .right).accessoryOffset.dx, 0)
        XCTAssertGreaterThan(BubbleLayout(side: .left).accessoryOffset.dx, 0)
    }
}
