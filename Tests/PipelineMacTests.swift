import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Droptimize

// macOS only (ImageIO, Core Graphics, AppKit); runs in CI and Xcode, not in scripts/check-linux.sh.
final class PipelineMacTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("PipelineMacTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Writes `image` with ImageIO (Apple's plain encoder, so there's room to optimize).
    @discardableResult
    private func write(_ image: RGBAImage, _ name: String, as type: UTType = .png, quality: Double? = nil) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try ImageIOEncoder.encode(image, as: type, quality: quality).write(to: url)
        return url
    }

    private func size(_ url: URL) throws -> Int {
        try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }

    private func dimensions(_ url: URL) throws -> (Int, Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int),
                try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int))
    }

    private var flatGraphic: RGBAImage {
        TestImages.blocks(width: 300, height: 200, colors: [[255, 255, 255, 255], [24, 24, 27, 255], [0, 122, 255, 255]])
    }

    // MARK: Decoding (CORE.md §6.2)

    func testAppliesEXIFOrientation() throws {
        let url = folder.appendingPathComponent("rotated.jpg")
        let cgImage = try XCTUnwrap(TestImages.gradient(width: 40, height: 20).makeCGImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cgImage, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let decoded = try ImageDecoder.decode(url)
        XCTAssertEqual(decoded.image.width, 20)
        XCTAssertEqual(decoded.image.height, 40)
        XCTAssertEqual(decoded.format, .jpeg)
    }

    func testConvertsOtherColorSpacesToSRGB() throws {
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let components: [CGFloat] = [0.5, 0.4, 0.3, 1]      // inside sRGB, but stored differently
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                              space: p3, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(colorSpace: p3, components: components)!)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let url = folder.appendingPathComponent("p3.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let expected = try XCTUnwrap(CGColor(colorSpace: p3, components: components)?
            .converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .relativeColorimetric, options: nil)?.components)
        let pixel = try ImageDecoder.decode(url).image.pixels.prefix(3).map { CGFloat($0) / 255 }
        for (got, want) in zip(pixel, expected) {
            XCTAssertEqual(got, want, accuracy: 2.0 / 255)
        }
        XCTAssertGreaterThan(abs(pixel[0] - 0.5), 0.01, "the P3 values should have been converted")
    }

    func testKeepsTransparency() throws {
        let url = try write(TestImages.blocks(colors: [[255, 0, 0, 255], [0, 0, 0, 0], [0, 0, 255, 255]]), "alpha.png")
        let decoded = try ImageDecoder.decode(url).image
        XCTAssertFalse(decoded.isOpaque)
        XCTAssertEqual(decoded.pixels, TestImages.blocks(colors: [[255, 0, 0, 255], [0, 0, 0, 0], [0, 0, 255, 255]]).pixels)
    }

    func testHalfSizeHalvesEachSide() throws {
        let url = try write(TestImages.gradient(width: 101, height: 60), "big.png")
        let decoded = try ImageDecoder.decode(url, scale: 0.5).image
        XCTAssertEqual(decoded.width, 51)
        XCTAssertEqual(decoded.height, 30)
    }

    // MARK: Encoders agree with Apple's decoder

    func testImageIOReadsOurPNGsExactly() throws {
        for image in [flatGraphic, TestImages.gradient(), TestImages.blocks(colors: [[9, 9, 9, 255], [200, 200, 200, 255]])] {
            let url = folder.appendingPathComponent("ours-\(UUID().uuidString).png")
            try PNGEncoder.encode(image).write(to: url)
            XCTAssertEqual(try ImageDecoder.decode(url).image.pixels, image.pixels)
        }
    }

    func testImageIOReadsOurWebP() throws {
        let url = folder.appendingPathComponent("ours.webp")
        try WebPEncoder.encode(TestImages.gradient(width: 90, height: 70), quality: 80).write(to: url)
        let decoded = try ImageDecoder.decode(url)
        XCTAssertEqual(decoded.format, .webp)
        XCTAssertEqual(decoded.image.width, 90)
        XCTAssertEqual(decoded.image.height, 70)
    }

    // MARK: Whole files (Rules 2 and 3, CORE.md §6.6)

    func testCompressPNGWritesASmallerCopyAndLeavesTheOriginal() throws {
        let input = try write(flatGraphic, "screen.png")
        let before = try Data(contentsOf: input)
        let outcome = try ImageOptimizer.process(input, action: .compress, wantsPicture: false)

        XCTAssertEqual(outcome.output.lastPathComponent, "screen-min.png")
        XCTAssertLessThan(try size(outcome.output), before.count)
        XCTAssertEqual(try Data(contentsOf: input), before, "the original is untouched")
        XCTAssertEqual(try ImageDecoder.decode(outcome.output).image.pixels, flatGraphic.pixels, "lossless")
    }

    func testWebPConvertsAndIsSmaller() throws {
        let input = try write(TestImages.gradient(width: 300, height: 200), "photo.png")
        let outcome = try ImageOptimizer.process(input, action: .webp, wantsPicture: true)
        XCTAssertEqual(outcome.output.lastPathComponent, "photo.webp")
        XCTAssertLessThan(outcome.outputBytes, outcome.inputBytes)
        XCTAssertNotNil(outcome.picture, "a single file also goes on the clipboard as a picture")
    }

    func testCompressJPEG() throws {
        let input = try write(TestImages.gradient(width: 400, height: 300), "camera.jpg", as: .jpeg, quality: 1)
        let outcome = try ImageOptimizer.process(input, action: .compress, wantsPicture: false)
        XCTAssertEqual(outcome.output.lastPathComponent, "camera-min.jpg")
        XCTAssertLessThan(outcome.outputBytes, outcome.inputBytes)
    }

    func testHalfSizeFile() throws {
        let input = try write(TestImages.gradient(width: 300, height: 200), "retina.png")
        let outcome = try ImageOptimizer.process(input, action: .halfSize, wantsPicture: false)
        XCTAssertEqual(outcome.output.lastPathComponent, "retina-half.png")
        let (width, height) = try dimensions(outcome.output)
        XCTAssertEqual(width, 150)
        XCTAssertEqual(height, 100)
    }

    func testNeverHandsBackABiggerFile() throws {
        let input = folder.appendingPathComponent("tiny.png")
        try PNGEncoder.encode(flatGraphic).write(to: input)       // already as small as we make it
        XCTAssertThrowsError(try ImageOptimizer.process(input, action: .compress, wantsPicture: false)) {
            XCTAssertEqual($0 as? JobError, .alreadySmallest)
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(files, ["tiny.png"], "nothing new is written")
    }

    func testRepeatedDropsNeverOverwrite() throws {
        let input = try write(flatGraphic, "logo.png")
        let first = try ImageOptimizer.process(input, action: .compress, wantsPicture: false).output
        let second = try ImageOptimizer.process(input, action: .compress, wantsPicture: false).output
        XCTAssertEqual(first.lastPathComponent, "logo-min.png")
        XCTAssertEqual(second.lastPathComponent, "logo-min-2.png")
    }

    func testUnbuiltActionsWriteNothing() throws {
        let input = try write(flatGraphic, "x.png")
        XCTAssertThrowsError(try ImageOptimizer.process(input, action: .avif, wantsPicture: false))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["x.png"])
    }

    // MARK: Batches and the clipboard

    @MainActor
    func testBatchRunsEveryFileAndFillsTheClipboard() async throws {
        let inputs = try (0..<3).map { try write(flatGraphic, "batch-\($0).png") }
        var updates: [JobProgress] = []
        let result = try await ImageJobRunner().run(Job(files: inputs, action: .compress)) { updates.append($0) }

        XCTAssertEqual(result.outputs.map(\.lastPathComponent), ["batch-0-min.png", "batch-1-min.png", "batch-2-min.png"])
        XCTAssertGreaterThan(result.saving, 0)
        XCTAssertEqual(updates.last?.completed, 3)
        let pasted = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        XCTAssertEqual(pasted?.map(\.lastPathComponent), result.outputs.map(\.lastPathComponent))
    }

    @MainActor
    func testBatchWhereEverythingIsAlreadySmallSaysSo() async throws {
        let input = folder.appendingPathComponent("done.png")
        try PNGEncoder.encode(flatGraphic).write(to: input)
        do {
            _ = try await ImageJobRunner().run(Job(files: [input], action: .compress)) { _ in }
            XCTFail("expected alreadySmallest")
        } catch {
            XCTAssertEqual(error as? JobError, .alreadySmallest)
        }
    }
}
