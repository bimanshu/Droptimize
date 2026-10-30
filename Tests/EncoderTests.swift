import CWebP
import XCTest
@testable import Droptimize

// Portable: also runs on Linux via scripts/check-linux.sh.
final class PNGEncoderTests: XCTestCase {
    private func roundTrip(_ image: RGBAImage, file: StaticString = #filePath, line: UInt = #line) throws -> TestPNGReader.Image {
        let decoded = try TestPNGReader.read(PNGEncoder.encode(image))
        XCTAssertEqual(decoded.width, image.width, file: file, line: line)
        XCTAssertEqual(decoded.height, image.height, file: file, line: line)
        XCTAssertEqual(decoded.rgba, image.pixels, "pixels changed", file: file, line: line)
        return decoded
    }

    func testPhotoLikeImagesStayExactAsRGB() throws {
        let decoded = try roundTrip(TestImages.gradient())
        XCTAssertEqual(decoded.colorType, 2)
        XCTAssertEqual(decoded.bitDepth, 8)
    }

    func testTransparencyStaysExactAsRGBA() throws {
        XCTAssertEqual(try roundTrip(TestImages.gradient(alpha: true)).colorType, 6)
    }

    func testFewColorsBecomeAPalette() throws {
        let two = try roundTrip(TestImages.blocks(colors: [[255, 255, 255, 255], [20, 120, 220, 255]]))
        XCTAssertEqual(two.colorType, 3)
        XCTAssertEqual(two.bitDepth, 1)

        let colors = (0..<5).map { [UInt8($0 * 50), 80, UInt8(250 - $0 * 50), 255] }
        let five = try roundTrip(TestImages.blocks(colors: colors))
        XCTAssertEqual(five.bitDepth, 4)
    }

    func testPaletteKeepsTransparency() throws {
        let decoded = try roundTrip(TestImages.blocks(colors: [[0, 0, 0, 0], [255, 0, 0, 128], [0, 200, 0, 255]]))
        XCTAssertEqual(decoded.colorType, 3)
        XCTAssertEqual(decoded.bitDepth, 2)
        XCTAssertTrue(decoded.chunkTypes.contains("tRNS"))
    }

    func testOpaquePaletteHasNoTransparencyChunk() throws {
        let decoded = try roundTrip(TestImages.blocks(colors: [[1, 2, 3, 255], [4, 5, 6, 255], [7, 8, 9, 255]]))
        XCTAssertFalse(decoded.chunkTypes.contains("tRNS"))
    }

    func testGrayImagesBecomeGrayscale() throws {
        var pixels: [UInt8] = []
        for i in 0..<(60 * 20) { let v = UInt8(i % 251); pixels += [v, v, v, 255] }
        XCTAssertEqual(try roundTrip(RGBAImage(width: 60, height: 20, pixels: pixels)).colorType, 0)

        var withAlpha: [UInt8] = []
        for i in 0..<(60 * 20) { let v = UInt8(i % 251); withAlpha += [v, v, v, UInt8(i % 256)] }
        XCTAssertEqual(try roundTrip(RGBAImage(width: 60, height: 20, pixels: withAlpha)).colorType, 4)
    }

    func testOddSizesAndSinglePixels() throws {
        _ = try roundTrip(RGBAImage(width: 1, height: 1, pixels: [9, 8, 7, 255]))
        _ = try roundTrip(TestImages.blocks(width: 13, height: 7, colors: [[0, 0, 0, 255], [255, 255, 255, 255]]))
        _ = try roundTrip(TestImages.noise(width: 3, height: 17))
    }

    func testNoMetadataChunks() throws {
        let decoded = try roundTrip(TestImages.gradient())
        XCTAssertEqual(Set(decoded.chunkTypes), ["IHDR", "IDAT", "IEND"])
    }

    func testFlatGraphicsCompressWell() throws {
        let image = TestImages.blocks(width: 400, height: 300, colors: [[255, 255, 255, 255], [30, 30, 30, 255], [0, 122, 255, 255]])
        let png = try PNGEncoder.encode(image)
        XCTAssertLessThan(png.count, image.pixels.count / 100)
    }
}

final class WebPEncoderTests: XCTestCase {
    private func decode(_ data: Data) -> (width: Int, height: Int, rgba: [UInt8])? {
        var width: Int32 = 0, height: Int32 = 0
        let decoded = data.withUnsafeBytes { bytes in
            WebPDecodeRGBA(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &width, &height)
        }
        guard let decoded else { return nil }
        defer { WebPFree(decoded) }
        return (Int(width), Int(height), Array(UnsafeBufferPointer(start: decoded, count: Int(width * height * 4))))
    }

    func testLosslessIsExact() throws {
        for image in [TestImages.gradient(alpha: true), TestImages.noise(), TestImages.blocks(colors: [[1, 2, 3, 255], [200, 100, 0, 255]])] {
            let webp = try WebPEncoder.encode(image, quality: nil)
            let decoded = try XCTUnwrap(decode(webp))
            XCTAssertEqual(decoded.width, image.width)
            XCTAssertEqual(decoded.height, image.height)
            XCTAssertEqual(decoded.rgba, image.pixels)
        }
    }

    func testLossyKeepsSizeAndIsClose() throws {
        let image = TestImages.gradient(width: 120, height: 80)
        let webp = try WebPEncoder.encode(image, quality: 80)
        let decoded = try XCTUnwrap(decode(webp))
        XCTAssertEqual(decoded.width, 120)
        XCTAssertEqual(decoded.height, 80)
        let error = zip(decoded.rgba, image.pixels).map { abs(Int($0) - Int($1)) }.reduce(0, +)
        XCTAssertLessThan(Double(error) / Double(image.pixels.count), 8, "lossy output drifted too far")
        XCTAssertLessThan(webp.count, image.pixels.count / 4)
    }

    func testLossyKeepsTransparency() throws {
        let image = TestImages.gradient(alpha: true)
        let decoded = try XCTUnwrap(decode(try WebPEncoder.encode(image, quality: 80)))
        let alphas = stride(from: 3, to: decoded.rgba.count, by: 4).map { decoded.rgba[$0] }
        let original = stride(from: 3, to: image.pixels.count, by: 4).map { image.pixels[$0] }
        XCTAssertEqual(alphas, original, "alpha is kept losslessly")
    }

    func testWritesAPlainRIFFWithNoMetadata() throws {
        let webp = try WebPEncoder.encode(TestImages.gradient(), quality: 80)
        XCTAssertEqual(String(decoding: webp.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: webp[8..<12], as: UTF8.self), "WEBP")
        XCTAssertNil(webp.range(of: Data("EXIF".utf8)))
        XCTAssertNil(webp.range(of: Data("ICCP".utf8)))
    }
}

final class RGBAImageTests: XCTestCase {
    func testOpacity() {
        XCTAssertTrue(TestImages.gradient().isOpaque)
        XCTAssertFalse(TestImages.gradient(alpha: true).isOpaque)
    }

    func testColorCountStopsAtTheLimit() {
        XCTAssertEqual(TestImages.blocks(colors: [[1, 1, 1, 255], [2, 2, 2, 255], [3, 3, 3, 255]]).distinctColorCount(limit: 10), 3)
        XCTAssertEqual(TestImages.noise().distinctColorCount(limit: 100), 101)
    }

    func testGraphicsAndPhotos() {
        XCTAssertTrue(TestImages.blocks(colors: [[255, 255, 255, 255], [0, 0, 0, 255]]).looksLikeGraphic)
        XCTAssertTrue(TestImages.gradient(alpha: true).looksLikeGraphic, "anything transparent tries lossless too")
        XCTAssertFalse(TestImages.noise(width: 100, height: 100).looksLikeGraphic)
    }
}
