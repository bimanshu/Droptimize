import XCTest
@testable import Droptimize

// Portable: also runs on Linux via scripts/check-linux.sh.
final class OutputNamingTests: XCTestCase {
    private let photo = URL(fileURLWithPath: "/work/photo.png")

    private func name(_ input: URL, _ ext: String, _ suffix: String?, taken: Set<String> = []) -> String {
        OutputNaming.url(for: input, fileExtension: ext, suffix: suffix) { taken.contains($0.lastPathComponent) }
            .lastPathComponent
    }

    func testNewFormatKeepsTheName() {
        XCTAssertEqual(name(photo, "webp", nil), "photo.webp")
    }

    func testSameFormatGetsTheSuffix() {
        XCTAssertEqual(name(photo, "png", "-min"), "photo-min.png")
        XCTAssertEqual(name(photo, "png", "-half"), "photo-half.png")
    }

    func testClashesCountUp() {
        XCTAssertEqual(name(photo, "png", "-min", taken: ["photo-min.png"]), "photo-min-2.png")
        XCTAssertEqual(name(photo, "png", "-min", taken: ["photo-min.png", "photo-min-2.png"]), "photo-min-3.png")
        XCTAssertEqual(name(photo, "webp", nil, taken: ["photo.webp"]), "photo-2.webp")
    }

    func testNeverNamesTheOriginal() {
        XCTAssertEqual(name(photo, "png", nil), "photo-2.png")
    }

    func testStaysInTheSameFolder() {
        let url = OutputNaming.url(for: photo, fileExtension: "webp", suffix: nil) { _ in false }
        XCTAssertEqual(url.deletingLastPathComponent().path, "/work")
    }

    func testNamesWithDotsAndSpaces() {
        XCTAssertEqual(name(URL(fileURLWithPath: "/w/My Shot 2.0.jpeg"), "jpeg", "-min"), "My Shot 2.0-min.jpeg")
    }
}

final class SizeGuardTests: XCTestCase {
    func testRejectsBiggerOrBarelySmaller() {
        XCTAssertFalse(SizeGuard.accepts(inputBytes: 1000, outputBytes: 1200))
        XCTAssertFalse(SizeGuard.accepts(inputBytes: 1000, outputBytes: 1000))
        XCTAssertFalse(SizeGuard.accepts(inputBytes: 1000, outputBytes: 995))
        XCTAssertFalse(SizeGuard.accepts(inputBytes: 0, outputBytes: 0))
    }

    func testAcceptsRealSavings() {
        XCTAssertTrue(SizeGuard.accepts(inputBytes: 1000, outputBytes: 990))
        XCTAssertTrue(SizeGuard.accepts(inputBytes: 1000, outputBytes: 300))
    }
}

final class OutputWriterTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("OutputWriterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testWritesNextToTheOriginalAndNeverOverwrites() throws {
        let original = folder.appendingPathComponent("shot.png")
        try Data("original".utf8).write(to: original)

        let first = try OutputWriter.write(Data("a".utf8), for: original, fileExtension: "png", suffix: "-min")
        let second = try OutputWriter.write(Data("b".utf8), for: original, fileExtension: "png", suffix: "-min")

        XCTAssertEqual(first.lastPathComponent, "shot-min.png")
        XCTAssertEqual(second.lastPathComponent, "shot-min-2.png")
        XCTAssertEqual(try Data(contentsOf: first), Data("a".utf8))
        XCTAssertEqual(try Data(contentsOf: original), Data("original".utf8), "the original is untouched")
    }
}

final class ImagePlanTests: XCTestCase {
    func testWebPAndAuto() throws {
        for action in [Action.auto, .webp] {
            XCTAssertEqual(try ImagePlan.make(action: action, source: .png, sourceExtension: "png"),
                           ImagePlan(encoding: .webp, fileExtension: "webp", suffix: nil, scale: 1))
        }
        XCTAssertEqual(try ImagePlan.make(action: .webp, source: .webp, sourceExtension: "webp").suffix, "-min")
    }

    func testCompressKeepsTheFormatAndItsSpelling() throws {
        XCTAssertEqual(try ImagePlan.make(action: .compress, source: .jpeg, sourceExtension: "JPEG"),
                       ImagePlan(encoding: .jpeg, fileExtension: "jpeg", suffix: "-min", scale: 1))
        XCTAssertEqual(try ImagePlan.make(action: .compress, source: .png, sourceExtension: "png").encoding, .png)
        XCTAssertEqual(try ImagePlan.make(action: .compress, source: .heic, sourceExtension: "heic").encoding, .heic)
    }

    func testTIFFAndBMPBecomePNG() throws {
        XCTAssertEqual(try ImagePlan.make(action: .compress, source: .tiff, sourceExtension: "tiff"),
                       ImagePlan(encoding: .png, fileExtension: "png", suffix: nil, scale: 1))
    }

    func testHalfSize() throws {
        XCTAssertEqual(try ImagePlan.make(action: .halfSize, source: .png, sourceExtension: "png"),
                       ImagePlan(encoding: .png, fileExtension: "png", suffix: "-half", scale: 0.5))
        XCTAssertEqual(try ImagePlan.make(action: .halfSize, source: .bmp, sourceExtension: "bmp").fileExtension, "png")
    }

    func testCompressToATargetSizeNamesTheSize() throws {
        XCTAssertEqual(try ImagePlan.make(action: .compress, option: .maxBytes(500_000), source: .jpeg, sourceExtension: "jpg"),
                       ImagePlan(encoding: .jpeg, fileExtension: "jpg", suffix: "-500kb", scale: 1))
        XCTAssertEqual(try ImagePlan.make(action: .compress, option: .maxBytes(1_500_000), source: .png, sourceExtension: "png").suffix,
                       "-1.5mb")
    }

    func testRemoveBackgroundAlwaysMakesAPNG() throws {
        XCTAssertEqual(try ImagePlan.make(action: .removeBackground, option: .background(nil), source: .jpeg, sourceExtension: "jpg"),
                       ImagePlan(encoding: .png, fileExtension: "png", suffix: "-nobg", scale: 1))
        XCTAssertEqual(try ImagePlan.make(action: .removeBackground, option: .background(.white), source: .heic, sourceExtension: "heic").suffix,
                       "-bg")
        XCTAssertEqual(try ImagePlan.make(action: .removeBackground, source: .png, sourceExtension: "png").suffix, "-nobg")
    }

    func testUnbuiltActionsSaySo() {
        XCTAssertThrowsError(try ImagePlan.make(action: .avif, source: .png, sourceExtension: "png")) {
            XCTAssertEqual($0 as? JobError, .notYet("AVIF is coming soon."))
        }
        XCTAssertThrowsError(try ImagePlan.scale(for: .mp4))
        XCTAssertThrowsError(try ImagePlan.make(action: .compress, source: .gif, sourceExtension: "gif"))
    }
}
