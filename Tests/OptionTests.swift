import XCTest
@testable import Droptimize

// Portable: also runs on Linux via scripts/check-linux.sh.
final class SubmenuLayoutTests: XCTestCase {
    private let optionReach = Motion.optionDiameter * Motion.optionHoverScale / 2
    private let segmentReach = Motion.segmentDiameter * Motion.segmentHoverScale / 2

    /// Every segment of every menu, on both sides, with the most options a segment can have.
    private var everySubmenu: [(MenuGeometry, Int)] {
        var all: [(MenuGeometry, Int)] = []
        for side in [DockSide.left, .right] {
            for segments in 1...ActionMenu.maxSegments {
                let geometry = MenuGeometry(side: side, optionCounts: Array(repeating: ActionMenu.maxOptions, count: segments))
                all += (0..<segments).map { (geometry, $0) }
            }
        }
        return all
    }

    func testOptionsNeverGoPastTheScreenEdge() {
        // The bubble's center sits this far from the edge it's docked to.
        let room = Motion.edgeInset + Motion.bubbleDiameter / 2
        for (geometry, segment) in everySubmenu {
            let submenu = geometry.submenu(for: segment)!
            for index in 0..<submenu.count {
                let towardEdge = -submenu.offset(of: index).dx * geometry.side.inward
                XCTAssertLessThanOrEqual(towardEdge + optionReach, room, "\(geometry.side) segment \(segment) option \(index)")
            }
        }
    }

    func testOptionsNeverTouchEachOtherOrTheSegments() {
        for (geometry, segment) in everySubmenu {
            let submenu = geometry.submenu(for: segment)!
            let options = (0..<submenu.count).map(submenu.offset(of:))
            for i in options.indices {
                for j in options.indices where j > i {
                    XCTAssertGreaterThanOrEqual(distance(options[i], options[j]), Double(2 * optionReach))
                }
                for s in 0..<geometry.ring.count {
                    XCTAssertGreaterThanOrEqual(distance(options[i], geometry.ring.offset(of: s)), Double(optionReach + segmentReach))
                }
            }
        }
    }

    func testEachOptionIsHitAtItsOwnPosition() {
        for (geometry, segment) in everySubmenu {
            let submenu = geometry.submenu(for: segment)!
            for index in 0..<submenu.count {
                XCTAssertEqual(geometry.target(at: submenu.offset(of: index), openSubmenu: segment),
                               .option(segment: segment, index: index))
            }
        }
    }

    func testSegmentsStillWorkInsideTheOptions() {
        let geometry = MenuGeometry(side: .right, optionCounts: [0, 0, 6, 0, 5])
        for segment in 0..<5 {
            XCTAssertEqual(geometry.target(at: geometry.ring.offset(of: segment), openSubmenu: 2), .segment(segment))
        }
        XCTAssertEqual(geometry.target(at: CGVector(dx: 0, dy: 0), openSubmenu: 2), .center)
    }

    func testHoveringASegmentOpensItsOptions() {
        let geometry = MenuGeometry(side: .right, optionCounts: [0, 0, 6, 0, 5])
        XCTAssertEqual(geometry.openSubmenu(after: .segment(2), current: nil), 2)
        XCTAssertEqual(geometry.openSubmenu(after: .segment(4), current: 2), 4)
        XCTAssertNil(geometry.openSubmenu(after: .segment(0), current: 2), "a segment without options closes them")
        XCTAssertNil(geometry.openSubmenu(after: .center, current: 2))
        XCTAssertEqual(geometry.openSubmenu(after: .option(segment: 2, index: 3), current: 2), 2)
        XCTAssertEqual(geometry.openSubmenu(after: nil, current: 2), 2, "stays open while the pointer is between options")
        XCTAssertNil(geometry.submenu(for: 0))
    }

    func testPanelHoldsTheOptionsAndFitsTheCanvas() {
        let center = CGPoint(x: 1000, y: 500)
        let half = BubbleLayout.canvasSide / 2
        let canvas = CGRect(x: center.x - half, y: center.y - half, width: 2 * half, height: 2 * half)
        for (geometry, segment) in everySubmenu {
            let submenu = geometry.submenu(for: segment)!
            let frame = BubbleLayout(side: geometry.side)
                .panelFrame(for: .menu(segments: geometry.ring.count, submenu: submenu), center: center)
            XCTAssertTrue(canvas.contains(frame))
            for index in 0..<submenu.count {
                let offset = submenu.offset(of: index)
                XCTAssertTrue(frame.contains(CGRect(x: center.x + offset.dx - optionReach, y: center.y + offset.dy - optionReach,
                                                    width: 2 * optionReach, height: 2 * optionReach)))
            }
            XCTAssertGreaterThanOrEqual(BubbleLayout.catchDiameter(segments: geometry.ring.count, submenu: submenu) / 2,
                                        submenu.radius + optionReach)
        }
    }

    func testOptionsStayOnScreenVertically() {
        for (geometry, segment) in everySubmenu {
            let submenu = geometry.submenu(for: segment)!
            for index in 0..<submenu.count {
                XCTAssertLessThanOrEqual(abs(submenu.offset(of: index).dy) + optionReach, BubbleLayout.verticalClearance)
            }
        }
    }

    private func distance(_ a: CGVector, _ b: CGVector) -> Double {
        hypot(Double(a.dx - b.dx), Double(a.dy - b.dy))
    }
}

final class ActionOptionTests: XCTestCase {
    func testCompressOffersTheTargetSizesAndCustom() {
        let options = Action.compress.options(lastColor: nil)
        XCTAssertEqual(options.map(\.option), [.maxBytes(100_000), .maxBytes(250_000), .maxBytes(500_000),
                                               .maxBytes(1_000_000), .maxBytes(2_000_000), .custom])
        XCTAssertEqual(options.map(\.title).prefix(2), ["Under 100 KB", "Under 250 KB"])
        XCTAssertEqual(options[3].label, .text("1M"))
    }

    func testRemoveBackgroundOffersNoneWhiteBlackAndCustom() {
        XCTAssertEqual(Action.removeBackground.options(lastColor: nil).map(\.option),
                       [.background(nil), .background(.white), .background(.black), .custom])
    }

    func testTheLastCustomColorGetsItsOwnBubble() {
        let teal = RGBColor(hex: "#14B8A6")!
        let options = Action.removeBackground.options(lastColor: teal)
        XCTAssertEqual(options.map(\.option), [.background(nil), .background(.white), .background(.black), .background(teal), .custom])
        XCTAssertEqual(options[3].title, "#14B8A6")
        XCTAssertEqual(Action.removeBackground.options(lastColor: .white).count, 4, "no duplicate of White")
    }

    func testOtherActionsHaveNoOptions() {
        for action in Action.allCases where action != .compress && action != .removeBackground {
            XCTAssertTrue(action.options(lastColor: nil).isEmpty, "\(action)")
        }
    }

    func testMenuTitlesAndTargets() {
        let menu = ActionMenu(segments: ActionMenu.imageSegments)
        XCTAssertEqual(menu.title(for: .center), "Auto")
        XCTAssertEqual(menu.title(for: .segment(2)), "Compress")
        XCTAssertEqual(menu.title(for: .option(segment: 2, index: 2)), "Under 500 KB")
        XCTAssertEqual(menu.action(for: .option(segment: 4, index: 0)), .removeBackground)
        XCTAssertEqual(menu.option(for: .option(segment: 4, index: 1))?.option, .background(.white))
        XCTAssertNil(menu.option(for: .segment(2)))
        XCTAssertNil(menu.option(for: .option(segment: 0, index: 0)), "WebP has no options")
        XCTAssertEqual(menu.geometryOptionCounts, [0, 0, 6, 0, 4])
    }
}

final class ColorAndSizeTests: XCTestCase {
    func testReadsHex() {
        XCTAssertEqual(RGBColor(hex: "#1A2B3C"), RGBColor(red: 0x1A, green: 0x2B, blue: 0x3C))
        XCTAssertEqual(RGBColor(hex: "ff8000"), RGBColor(red: 255, green: 128, blue: 0))
        XCTAssertEqual(RGBColor(hex: " #fff "), .white)
        XCTAssertEqual(RGBColor(hex: "#000"), .black)
        for bad in ["", "#12", "#12345", "#GGGGGG", "1234567", "#12 456"] {
            XCTAssertNil(RGBColor(hex: bad), bad)
        }
    }

    func testWritesHex() {
        XCTAssertEqual(RGBColor(red: 0x0A, green: 0x84, blue: 0xFF).hex, "#0A84FF")
        XCTAssertEqual(RGBColor(hex: "#abcdef")?.hex, "#ABCDEF")
    }

    func testDescribesSizesLikeFinder() {
        XCTAssertEqual(ByteCount.describe(100_000), "100 KB")
        XCTAssertEqual(ByteCount.describe(1_000_000), "1 MB")
        XCTAssertEqual(ByteCount.describe(1_500_000), "1.5 MB")
        XCTAssertEqual(ByteCount.short(250_000), "250K")
        XCTAssertEqual(ByteCount.short(2_000_000), "2M")
        XCTAssertEqual(ByteCount.suffix(500_000), "-500kb")
        XCTAssertEqual(ByteCount.suffix(1_500_000), "-1.5mb")
    }

    func testErrorLines() {
        XCTAssertEqual(JobError.alreadyUnder(500_000).errorDescription, "Already under 500 KB.")
        XCTAssertEqual(JobError.cantFit(100_000).errorDescription, "Couldn't get it under 100 KB.")
    }
}

final class SizeSearchTests: XCTestCase {
    /// A pretend encoder whose output is `quality × 1000` bytes; records every call.
    private final class FakeEncoder {
        var calls: [Double] = []
        func encode(_ quality: Double) -> Data {
            calls.append(quality)
            return Data(count: Int(quality * 1000))
        }
    }

    func testFindsTheBestQualityUnderTheLimit() throws {
        let encoder = FakeEncoder()
        let data = try XCTUnwrap(SizeSearch.bestFit(limit: 500, qualities: 0.1...0.95, encode: encoder.encode))
        XCTAssertLessThanOrEqual(data.count, 500)
        XCTAssertGreaterThan(data.count, 480, "close to the limit, not just under it")
        XCTAssertLessThanOrEqual(encoder.calls.count, EncoderTuning.searchSteps + 2)
    }

    func testTakesTheTopQualityWhenItFits() throws {
        let encoder = FakeEncoder()
        let data = try XCTUnwrap(SizeSearch.bestFit(limit: 10_000, qualities: 0.1...0.95, encode: encoder.encode))
        XCTAssertEqual(data.count, 950)
        XCTAssertEqual(encoder.calls, [0.95])
    }

    func testGivesUpWhenEvenTheLowestIsTooBig() {
        XCTAssertNil(SizeSearch.bestFit(limit: 50, qualities: 0.1...0.95, encode: FakeEncoder().encode))
    }

    func testShrinksStepByStepButNotTooFar() {
        let scales = SizeSearch.scales(width: 4000, height: 3000)
        XCTAssertEqual(scales.first, 1)
        XCTAssertEqual(scales, scales.sorted(by: >))
        XCTAssertGreaterThanOrEqual(3000 * scales.last!, Double(EncoderTuning.minimumFitSide))
        XCTAssertEqual(SizeSearch.scales(width: 50, height: 50), [1], "tiny images aren't shrunk")
    }
}

final class CompositorTests: XCTestCase {
    private let image = RGBAImage(width: 2, height: 2, pixels: [
        200, 100, 50, 255,   10, 20, 30, 255,
        0, 0, 255, 255,      90, 90, 90, 128,
    ])

    func testKeepsTheSubjectAndClearsTheRest() {
        let cut = Compositor.cutOut(image, mask: [1, 0, 1, 0], background: nil)
        XCTAssertEqual(Array(cut.pixels[0..<4]), [200, 100, 50, 255])
        XCTAssertEqual(Array(cut.pixels[4..<8]), [0, 0, 0, 0], "fully cut pixels are 0,0,0,0")
        XCTAssertEqual(Array(cut.pixels[8..<12]), [0, 0, 255, 255])
    }

    func testSoftEdgesBecomePartlyTransparent() {
        let cut = Compositor.cutOut(image, mask: [0.5, 1, 1, 1], background: nil)
        XCTAssertEqual(cut.pixels[3], 128)
        XCTAssertEqual(cut.pixels[15], 128, "existing transparency is kept")
    }

    func testPutsAColorBehind() {
        let cut = Compositor.cutOut(image, mask: [1, 0, 0.5, 1], background: .white)
        XCTAssertTrue(cut.isOpaque)
        XCTAssertEqual(Array(cut.pixels[0..<3]), [200, 100, 50])
        XCTAssertEqual(Array(cut.pixels[4..<7]), [255, 255, 255], "background shows where the mask is 0")
        XCTAssertEqual(Array(cut.pixels[8..<11]), [128, 128, 255], "half and half")
    }
}
