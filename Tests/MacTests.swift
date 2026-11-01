import AppKit
import XCTest
@testable import Droptimize

// macOS only (AppKit, UniformTypeIdentifiers); runs in CI and Xcode, not in scripts/check-linux.sh.
final class MediaKindTests: XCTestCase {
    func testRecognisesImagesAndVideosByExtension() {
        let cases: [(String, MediaKind?)] = [
            ("photo.jpg", .image), ("shot.PNG", .image), ("pic.heic", .image), ("art.webp", .image),
            ("a.avif", .image), ("scan.tiff", .image), ("anim.gif", .image),
            ("clip.mov", .video), ("clip.mp4", .video), ("clip.m4v", .video),
            ("logo.svg", nil), ("doc.pdf", nil), ("notes.txt", nil), ("archive.zip", nil),
        ]
        for (name, expected) in cases {
            let url = URL(fileURLWithPath: "/nonexistent/\(name)")
            XCTAssertEqual(MediaKind(url: url), expected, name)
        }
    }
}

final class SymbolTests: XCTestCase {
    func testEverySymbolExists() {
        var names = Action.allCases.map(\.symbol)
        names += ["checkmark", "exclamationmark", "xmark", "ellipsis"]
        names += ["infinity", "photo.on.rectangle.angled", "square.stack.3d.up"]           // the Pro window
        for option in Action.allCases.flatMap({ $0.options(lastColor: nil) }) {
            if case .symbol(let name) = option.label { names.append(name) }
        }
        for name in names {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), "missing SF Symbol \(name)")
        }
    }
}

final class LogoTests: XCTestCase {
    func testMenuBarImageIsATemplateOfTheMark() throws {
        let image = Logo.menuBarImage()
        XCTAssertTrue(image.isTemplate, "so the menu bar tints it for light and dark")
        XCTAssertEqual(image.size, NSSize(width: Motion.menuBarLogoSize, height: Motion.menuBarLogoSize))

        let side = 48
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        func alpha(_ x: CGFloat, _ y: CGFloat) -> CGFloat {      // grid units, y down
            let scale = CGFloat(side) / Logo.grid
            return rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.alphaComponent ?? 0
        }
        XCTAssertGreaterThan(alpha(Logo.dot.x, Logo.dot.y), 0.9, "the solid dot, bottom left")
        XCTAssertGreaterThan(alpha(12, 2.5), 0.9, "the outer ring's top")
        XCTAssertLessThan(alpha(12, 12), 0.1, "the middle is open")
        XCTAssertLessThan(alpha(23.5, 23.5), 0.1, "nothing outside the ring")
    }

    func testTheMarkStaysOnItsGrid() {
        for disc in Logo.rings + [Logo.dot] {
            let rect = disc.rect(1).insetBy(dx: -Logo.stroke / 2, dy: -Logo.stroke / 2)
            XCTAssertTrue(CGRect(x: 0, y: 0, width: Logo.grid, height: Logo.grid).contains(rect), "\(disc)")
        }
    }
}

final class DoneInfoTests: XCTestCase {
    func testSavingTextUsesARealMinusSign() {
        XCTAssertEqual(DoneInfo(saving: 0.678, count: 1).savingText, "\u{2212}68%")
        XCTAssertEqual(DoneInfo(saving: 0, count: 1).savingText, "Done")
    }
}

final class HistoryStoreTests: XCTestCase {
    @MainActor
    func testPersistsAcrossLaunches() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryStoreTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HistoryStore(url: url)
        store.record([HistoryEntry(action: "Convert", detail: "To JPG", input: URL(fileURLWithPath: "/w/a.png"),
                                   output: URL(fileURLWithPath: "/w/a.jpg"), inputBytes: 900, outputBytes: 300)])
        XCTAssertEqual(HistoryStore(url: url).log.entries.map(\.summary), ["Convert · To JPG"])
        store.clear()
        XCTAssertTrue(HistoryStore(url: url).log.entries.isEmpty)
    }
}

final class ProStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        suite = "ProStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    @MainActor
    func testFreePlanCountsFilesPerDayAndRemembersThem() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = ProStore(defaults: defaults, selling: true, now: { now })
        XCTAssertTrue(store.isLimited)
        XCTAssertEqual(store.grant(5), 3)
        store.record(3)
        XCTAssertEqual(store.grant(1), 0)
        XCTAssertEqual(ProStore(defaults: defaults, selling: true, now: { now }).grant(1), 0, "survives a relaunch")
        now = now.addingTimeInterval(24 * 3600)
        XCTAssertEqual(store.grant(5), 3, "a new day")
    }

    @MainActor
    func testUnlimitedUntilProIsOnSale() {
        let store = ProStore(defaults: defaults, selling: false)
        XCTAssertFalse(store.isLimited)
        store.record(10)
        XCTAssertEqual(store.grant(50), 50)
    }
}
