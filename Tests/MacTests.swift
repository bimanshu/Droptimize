import AppKit
import XCTest
@testable import Droptimize

// macOS only (AppKit, UniformTypeIdentifiers); runs in CI and Xcode, not in scripts/check-linux.sh.
final class MediaKindTests: XCTestCase {
    func testRecognisesImagesVideosAndPDFsByExtension() {
        let cases: [(String, MediaKind?)] = [
            ("photo.jpg", .image), ("shot.PNG", .image), ("pic.heic", .image), ("art.webp", .image),
            ("a.avif", .image), ("scan.tiff", .image), ("anim.gif", .image),
            ("clip.mov", .video), ("clip.mp4", .video), ("clip.m4v", .video),
            ("doc.pdf", .pdf), ("Scan.PDF", .pdf),
            ("logo.svg", nil), ("notes.txt", nil), ("archive.zip", nil),
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

@MainActor
final class FreeLimitGuardRailTests: XCTestCase {
    private let suite = "FreeLimitGuardRailTests-\(UUID().uuidString)"
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FreeLimitGuardRailTests-\(UUID().uuidString)")
    private let pasteboard = NSPasteboard(name: NSPasteboard.Name("FreeLimitGuardRailTests-\(UUID().uuidString)"))
    private var opened = 0

    override func tearDown() async throws {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
        pasteboard.releaseGlobally()
    }

    private func bubble(filesUsed: Int) throws -> BubbleController {
        let pro = ProStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)), selling: true)
        pro.record(filesUsed)
        let bubble = BubbleController(history: HistoryStore(url: folder.appendingPathComponent("history.json")), pro: pro)
        bubble.onShowPro = { [weak self] in self?.opened += 1 }
        return bubble
    }

    private func photoDrag() throws -> DroppedItems {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let photo = folder.appendingPathComponent("photo.jpg")
        try Data([0xFF]).write(to: photo)
        pasteboard.clearContents()
        pasteboard.writeObjects([photo as NSURL])
        return DroppedItems(pasteboard, withData: false)
    }

    private func settle() async {
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
    }

    func testLettingGoWithNoFreeFilesLeftAsksForTheLicenseKey() async throws {
        let bubble = try bubble(filesUsed: FreeAllowance.perDay)
        let drag = try photoDrag()
        XCTAssertTrue(bubble.dragEntered(drag), "taken, so it can be let go on the bubble")
        XCTAssertFalse(bubble.model.isMenuOpen, "no menu without free files")
        XCTAssertEqual(bubble.dragMoved(), .copy)
        XCTAssertFalse(bubble.drop(drag), "the file itself isn't taken")
        await settle()
        XCTAssertEqual(opened, 1)
    }

    func testDraggingAwayDoesNotAsk() async throws {
        let bubble = try bubble(filesUsed: FreeAllowance.perDay)
        XCTAssertTrue(bubble.dragEntered(try photoDrag()))
        bubble.dragExited()
        await settle()
        XCTAssertEqual(opened, 0)
    }

    func testFilesLeftOpenTheMenuAsUsual() async throws {
        let bubble = try bubble(filesUsed: FreeAllowance.perDay - 1)
        XCTAssertTrue(bubble.dragEntered(try photoDrag()))
        XCTAssertTrue(bubble.model.isMenuOpen)
        bubble.dragExited()
        await settle()
        XCTAssertEqual(opened, 0)
    }
}

/// A menu bar app has no Edit menu, so its windows route ⌘V and friends themselves (owner, 2026-11-11:
/// ⌘V did nothing in the Pro window's key field).
@MainActor
final class EditShortcutTests: XCTestCase {
    private func key(_ character: String, _ flags: NSEvent.ModifierFlags = .command, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                       windowNumber: window.windowNumber, context: nil, characters: character,
                                       charactersIgnoringModifiers: character, isARepeat: false, keyCode: 0))
    }

    func testPasteSelectAllAndCutInTheProWindowsKind() throws {
        let window = ClosableWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
                                    styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let field = NSTextField(frame: NSRect(x: 10, y: 20, width: 300, height: 24))
        window.contentView?.addSubview(field)
        XCTAssertTrue(window.makeFirstResponder(field))

        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        defer { pasteboard.clearContents(); if let saved { pasteboard.setString(saved, forType: .string) } }
        pasteboard.clearContents()
        pasteboard.setString("PRO-AAAA-BBBB", forType: .string)

        XCTAssertTrue(window.performKeyEquivalent(with: try key("v", in: window)))
        XCTAssertEqual(field.stringValue, "PRO-AAAA-BBBB")
        XCTAssertTrue(window.performKeyEquivalent(with: try key("a", in: window)))
        XCTAssertTrue(window.performKeyEquivalent(with: try key("x", in: window)))
        XCTAssertEqual(field.stringValue, "")
        XCTAssertEqual(pasteboard.string(forType: .string), "PRO-AAAA-BBBB")
    }

    func testOnlyTheEditShortcuts() throws {
        let window = NSWindow()
        XCTAssertEqual(EditShortcuts.action(for: try key("v", in: window)), #selector(NSText.paste(_:)))
        XCTAssertEqual(EditShortcuts.action(for: try key("Z", [.command, .shift], in: window)), Selector(("redo:")))
        XCTAssertNil(EditShortcuts.action(for: try key("v", [.command, .option], in: window)))
        XCTAssertNil(EditShortcuts.action(for: try key("q", in: window)))
    }
}

@MainActor
final class DroppedItemsTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("DroppedItemsTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
        ReceivedFiles.clear()
    }

    private func png() throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    func testAPictureFromABrowserBecomesAFileNamedAfterIt() async throws {
        let data = try png()
        let item = NSPasteboardItem()
        item.setData(data, forType: .png)
        item.setString("https://example.com/photos/sunset.png?w=800", forType: .URL)
        pasteboard.writeObjects([item])

        let peek = DroppedItems(pasteboard, withData: false)
        XCTAssertEqual(peek.kinds, [.image], "the image menu, before anything is read")
        XCTAssertEqual(peek.count, 1)
        XCTAssertFalse(peek.isReady)

        let files = try await DroppedItems(pasteboard, withData: true).files(limit: 3)
        XCTAssertEqual(files.map(\.lastPathComponent), ["sunset.png"])
        XCTAssertTrue(ReceivedFiles.contains(files[0]), "so its result goes to Downloads")
        XCTAssertEqual(try Data(contentsOf: files[0]), data)
    }

    func testFinderFilesAreUsedWhereTheyAre() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DroppedItemsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = folder.appendingPathComponent("a.png"), notes = folder.appendingPathComponent("b.txt")
        try png().write(to: photo)
        try Data("hi".utf8).write(to: notes)
        pasteboard.writeObjects([photo as NSURL, notes as NSURL])

        let items = DroppedItems(pasteboard, withData: true)
        XCTAssertTrue(items.isReady)
        XCTAssertEqual(items.kinds, [.image])
        let files = try await items.files(limit: 3)
        XCTAssertEqual(files.map { $0.resolvingSymlinksInPath().path }, [photo.resolvingSymlinksInPath().path],
                       "the text file is left out")
    }

    func testTextIsNothingToDrop() {
        pasteboard.setString("just words", forType: .string)
        let items = DroppedItems(pasteboard, withData: false)
        XCTAssertFalse(items.hasItems)
        XCTAssertTrue(items.kinds.isEmpty)
    }
}
