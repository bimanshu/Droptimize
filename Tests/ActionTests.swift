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

    func testPDFsGetConvertAndCompress() {
        let menu = ActionMenu(kinds: [.pdf])
        XCTAssertEqual(menu?.center, .auto)
        XCTAssertEqual(menu?.segments, [.convert, .compress])
        XCTAssertEqual(menu?.options.first?.map(\.option), [.format(.png), .format(.jpeg)], "each page as an image")
        XCTAssertEqual(menu?.options.last?.map(\.title),
                       ["Under 200 KB", "Under 500 KB", "Under 1 MB", "Under 2 MB", "Under 5 MB", "Custom size"])
        XCTAssertEqual(menu?.options.last?.first?.option, .maxBytes(200_000))
    }

    func testWordDocumentsGetConvertToPDF() {
        let menu = ActionMenu(kinds: [.document])
        XCTAssertEqual(menu?.center, .auto)
        XCTAssertEqual(menu?.segments, [.convert])
        XCTAssertEqual(menu?.options.first?.map(\.option), [.pdf])
        XCTAssertEqual(menu?.options.first?.first?.title, "To PDF")
        XCTAssertEqual(ActionMenu(kinds: [.document, .image])?.segments, [.compress], "mixed: only what's shared")
    }

    func testImagesCanBecomeAPDF() {
        let convert = Action.convert.options(for: .image, lastColor: nil)
        XCTAssertEqual(convert.last?.option, .pdf)
        XCTAssertEqual(convert.last?.label, .text("PDF"))
        XCTAssertEqual(ActionOption.pdf.title, "To PDF")
    }

    func testMixedDropsOnlyOfferWhatAppliesToBoth() {
        let menu = ActionMenu(kinds: [.image, .video])
        XCTAssertEqual(menu?.center, .auto)
        XCTAssertEqual(menu?.segments, [.compress])
        XCTAssertEqual(ActionMenu(kinds: [.image, .pdf])?.segments, [.compress])
    }

    func testNothingUsefulMeansNoMenu() {
        XCTAssertNil(ActionMenu(kinds: []))
    }

    func testNoMenuHasMoreThanSixSegments() {
        for menu in [ActionMenu.image, .video, .pdf, .document, .mixed] {
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
