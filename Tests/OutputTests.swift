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

    func testMovesFinishedFilesInWithoutOverwriting() throws {
        let original = folder.appendingPathComponent("clip.mov")
        try Data("original".utf8).write(to: original)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try Data("a".utf8).write(to: temp)
        let first = try OutputWriter.move(temp, for: original, fileExtension: "mp4", suffix: nil)
        try Data("b".utf8).write(to: temp)
        let second = try OutputWriter.move(temp, for: original, fileExtension: "mp4", suffix: nil)
        XCTAssertEqual(first.lastPathComponent, "clip.mp4")
        XCTAssertEqual(second.lastPathComponent, "clip-2.mp4")
        XCTAssertEqual(try Data(contentsOf: first), Data("a".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
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

    func testFilesReceivedFromOtherAppsSaveToDownloads() throws {
        let received = try ReceivedFiles.newFolder()
        defer { ReceivedFiles.clear() }
        let photo = received.appendingPathComponent("IMG_1234.heic")
        try Data("photo".utf8).write(to: photo)
        XCTAssertTrue(ReceivedFiles.contains(photo))
        XCTAssertFalse(ReceivedFiles.contains(folder.appendingPathComponent("IMG_1234.heic")))

        // `folder` stands in for Downloads.
        let output = try OutputWriter.write(Data("a".utf8), for: photo, fileExtension: "webp", suffix: nil,
                                            fallbackDirectory: folder)
        XCTAssertEqual(output.deletingLastPathComponent().standardizedFileURL.path, folder.standardizedFileURL.path)
        XCTAssertEqual(output.lastPathComponent, "IMG_1234.webp")

        let next = try ReceivedFiles.newFolder()
        XCTAssertFalse(FileManager.default.fileExists(atPath: received.path), "earlier copies are cleared")
        XCTAssertTrue(FileManager.default.fileExists(atPath: next.path))
    }
}

final class ImagePlanTests: XCTestCase {
    func testAutoAndConvert() throws {
        let webp = ImagePlan(encoding: .webp, fileExtension: "webp", suffix: nil, scale: 1)
        XCTAssertEqual(try ImagePlan.make(action: .auto, source: .png, sourceExtension: "png"), webp)
        XCTAssertEqual(try ImagePlan.make(action: .convert, source: .png, sourceExtension: "png"), webp, "Convert itself = WebP")
        XCTAssertEqual(try ImagePlan.make(action: .convert, option: .format(.jpeg), source: .heic, sourceExtension: "HEIC"),
                       ImagePlan(encoding: .jpeg, fileExtension: "jpg", suffix: nil, scale: 1))
        XCTAssertEqual(try ImagePlan.make(action: .convert, option: .format(.png), source: .webp, sourceExtension: "webp"),
                       ImagePlan(encoding: .png, fileExtension: "png", suffix: nil, scale: 1))
        XCTAssertEqual(try ImagePlan.make(action: .convert, option: .format(.webp), source: .webp, sourceExtension: "webp").suffix,
                       "-min", "same format: a recompress, named like one")
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

    func testAVIF() throws {
        XCTAssertEqual(try ImagePlan.make(action: .convert, option: .format(.avif), source: .png, sourceExtension: "png"),
                       ImagePlan(encoding: .avif, fileExtension: "avif", suffix: nil, scale: 1))
        XCTAssertEqual(try ImagePlan.make(action: .compress, source: .avif, sourceExtension: "avif"),
                       ImagePlan(encoding: .avif, fileExtension: "avif", suffix: "-min", scale: 1))
    }

    func testUnbuiltActionsSaySo() {
        XCTAssertThrowsError(try ImagePlan.make(action: .mute, source: .png, sourceExtension: "png")) {
            XCTAssertEqual($0 as? JobError, .notYet("That's for videos."))
        }
        XCTAssertThrowsError(try ImagePlan.scale(for: .resize))
        XCTAssertThrowsError(try ImagePlan.make(action: .compress, source: .gif, sourceExtension: "gif"))
    }
}
