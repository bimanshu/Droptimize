import XCTest
@testable import Droptimize

// Portable: also runs on Linux via scripts/check-linux.sh.
final class ActionMenuTests: XCTestCase {
    func testImagesGetTheImageMenu() {
        XCTAssertEqual(ActionMenu(kinds: [.image])?.segments, [.convert, .compress, .halfSize, .removeBackground])
    }

    func testVideosGetTheVideoMenu() {
        XCTAssertEqual(ActionMenu(kinds: [.video])?.segments, [.convert, .compress, .resize, .mute])
    }

    func testMixedDropsOnlyOfferWhatAppliesToBoth() {
        let menu = ActionMenu(kinds: [.image, .video])
        XCTAssertEqual(menu?.center, .auto)
        XCTAssertEqual(menu?.segments, [.compress])
    }

    func testNothingUsefulMeansNoMenu() {
        XCTAssertNil(ActionMenu(kinds: []))
    }

    func testNoMenuHasMoreThanSixSegments() {
        for menu in [ActionMenu.image, .video, .mixed] {
            XCTAssertLessThanOrEqual(menu.segments.count, ActionMenu.maxSegments)
        }
    }

    func testTargetsMapToActions() {
        let menu = ActionMenu.image
        XCTAssertEqual(menu.action(for: .center), .auto)
        XCTAssertEqual(menu.action(for: .segment(0)), .convert)
        XCTAssertNil(menu.action(for: .segment(99)))
    }

    func testEveryActionHasLabels() {
        for action in Action.allCases {
            XCTAssertFalse(action.title.isEmpty)
            XCTAssertFalse(action.symbol.isEmpty)
            XCTAssertFalse(action.accessibilityLabel.isEmpty)
        }
    }

    func testSavingNeverGoesNegative() {
        XCTAssertEqual(JobResult(outputs: [], inputBytes: 100, outputBytes: 32).saving, 0.68, accuracy: 1e-9)
        XCTAssertEqual(JobResult(outputs: [], inputBytes: 100, outputBytes: 150).saving, 0)
        XCTAssertEqual(JobResult(outputs: [], inputBytes: 0, outputBytes: 0).saving, 0)
    }
}
