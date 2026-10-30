import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Droptimize

// macOS only: Compress to a size and Remove BG on real files. Runs in CI and Xcode.
final class OptionMacTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("OptionMacTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func write(_ image: RGBAImage, _ name: String, as type: UTType, quality: Double? = nil) throws -> (URL, Int) {
        let url = folder.appendingPathComponent(name)
        let data = try ImageIOEncoder.encode(image, as: type, quality: quality)
        try data.write(to: url)
        return (url, data.count)
    }

    /// A gradient with some grain: compresses like a photo.
    private func photo(width: Int, height: Int) -> RGBAImage {
        var image = TestImages.gradient(width: width, height: height)
        let noise = TestImages.noise(width: width, height: height)
        for i in stride(from: 0, to: image.pixels.count, by: 4) {
            for c in 0..<3 {
                image.pixels[i + c] = UInt8((Int(image.pixels[i + c]) * 7 + Int(noise.pixels[i + c])) / 8)
            }
        }
        return image
    }

    // MARK: Compress to a target size

    func testJPEGLandsUnderTheTarget() throws {
        let (input, size) = try write(photo(width: 800, height: 600), "big.jpg", as: .jpeg, quality: 1)
        let limit = size / 3
        let outcome = try ImageOptimizer.process(input, action: .compress, option: .maxBytes(limit), wantsPicture: false)
        XCTAssertLessThanOrEqual(outcome.outputBytes, limit)
        XCTAssertGreaterThan(outcome.outputBytes, limit / 2, "uses the room it has rather than crushing it")
        XCTAssertTrue(outcome.output.lastPathComponent.hasPrefix("big-"))
        XCTAssertEqual(outcome.output.pathExtension, "jpg")
        XCTAssertNil(outcome.note, "fits without resizing")
    }

    func testPNGShrinksToFitAndSaysSo() throws {
        let (input, _) = try write(TestImages.noise(width: 400, height: 400), "noise.png", as: .png)
        let outcome = try ImageOptimizer.process(input, action: .compress, option: .maxBytes(100_000), wantsPicture: false)
        XCTAssertLessThanOrEqual(try XCTUnwrap(outcome.output.resourceValues(forKeys: [.fileSizeKey]).fileSize), 100_000)
        XCTAssertEqual(outcome.output.lastPathComponent, "noise-100kb.png")
        XCTAssertTrue(outcome.note?.hasPrefix("Resized to") == true, outcome.note ?? "no note")
        let decoded = try ImageDecoder.decode(outcome.output).image
        XCTAssertLessThan(decoded.width, 400)
        XCTAssertEqual(decoded.width, decoded.height, "keeps the aspect ratio")
    }

    func testAlreadyUnderTheTarget() throws {
        let (input, size) = try write(TestImages.gradient(), "small.png", as: .png)
        XCTAssertThrowsError(try ImageOptimizer.process(input, action: .compress, option: .maxBytes(size + 1000), wantsPicture: false)) {
            XCTAssertEqual($0 as? JobError, .alreadyUnder(size + 1000))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["small.png"])
    }

    func testImpossibleTargetsSaySo() throws {
        let (input, _) = try write(TestImages.noise(width: 200, height: 200), "hard.png", as: .png)
        XCTAssertThrowsError(try ImageOptimizer.process(input, action: .compress, option: .maxBytes(200), wantsPicture: false)) {
            XCTAssertEqual($0 as? JobError, .cantFit(200))
        }
    }

    @MainActor
    func testRunnerPassesTheOptionAndTheNote() async throws {
        let (input, _) = try write(TestImages.noise(width: 400, height: 400), "batch.png", as: .png)
        let result = try await ImageJobRunner().run(Job(files: [input], action: .compress, option: .maxBytes(100_000))) { _ in }
        XCTAssertEqual(result.outputs.map(\.lastPathComponent), ["batch-100kb.png"])
        XCTAssertNotNil(result.note)
    }

    // MARK: Remove BG

    /// A dark disc on a light background. Vision may or may not call that a subject (it's tuned
    /// for photos), so these tests accept "no subject" but check everything else.
    private var objectOnWhite: RGBAImage {
        var pixels: [UInt8] = []
        for y in 0..<240 {
            for x in 0..<320 {
                let inside = hypot(Double(x - 160), Double(y - 120)) < 70
                pixels += inside ? [180, 40, 30, 255] : [245, 245, 245, 255]
            }
        }
        return RGBAImage(width: 320, height: 240, pixels: pixels)
    }

    func testRemoveBackgroundMakesATransparentPNG() throws {
        let (input, _) = try write(objectOnWhite, "product.jpg", as: .jpeg, quality: 0.9)
        do {
            let outcome = try ImageOptimizer.process(input, action: .removeBackground, option: .background(nil), wantsPicture: false)
            XCTAssertEqual(outcome.output.lastPathComponent, "product-nobg.png")
            XCTAssertFalse(try ImageDecoder.decode(outcome.output).image.isOpaque)
            XCTAssertEqual(outcome.note, "Background removed")
        } catch JobError.noSubject {
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["product.jpg"], "nothing written")
        }
    }

    func testRemoveBackgroundWithAColorIsOpaque() throws {
        let (input, _) = try write(objectOnWhite, "item.png", as: .png)
        do {
            let teal = try XCTUnwrap(RGBColor(hex: "#14B8A6"))
            let outcome = try ImageOptimizer.process(input, action: .removeBackground, option: .background(teal), wantsPicture: false)
            XCTAssertEqual(outcome.output.lastPathComponent, "item-bg.png")
            XCTAssertTrue(try ImageDecoder.decode(outcome.output).image.isOpaque)
            XCTAssertEqual(outcome.note, "Background: #14B8A6")
        } catch JobError.noSubject {
            // Vision didn't see a subject in a synthetic image; the compositing is covered by CompositorTests.
        }
    }
}
