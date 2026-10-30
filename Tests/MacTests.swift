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
        names += ["drop.fill", "drop.circle", "checkmark", "exclamationmark", "xmark"]
        for name in names {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), "missing SF Symbol \(name)")
        }
    }
}

final class DoneInfoTests: XCTestCase {
    func testSavingTextUsesARealMinusSign() {
        XCTAssertEqual(DoneInfo(saving: 0.678, count: 1).savingText, "\u{2212}68%")
        XCTAssertEqual(DoneInfo(saving: 0, count: 1).savingText, "Done")
    }
}
