import CAvif
import XCTest
@testable import Droptimize

// Portable: also runs on Linux via scripts/check-linux.sh. Decodes with libavif itself.
final class AVIFEncoderTests: XCTestCase {
    private struct Decoded {
        var width: Int
        var height: Int
        var rgba: [UInt8]
        var hasAlphaPlane: Bool
    }

    private func decode(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws -> Decoded {
        let decoder = try XCTUnwrap(avifDecoderCreate())
        defer { avifDecoderDestroy(decoder) }
        let image = try XCTUnwrap(avifImageCreateEmpty())
        defer { avifImageDestroy(image) }
        let read = data.withUnsafeBytes { bytes in
            avifDecoderReadMemory(decoder, image, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
        }
        XCTAssertEqual(read, AVIF_RESULT_OK, file: file, line: line)

        var rgb = avifRGBImage()
        avifRGBImageSetDefaults(&rgb, image)
        rgb.format = AVIF_RGB_FORMAT_RGBA
        rgb.depth = 8
        XCTAssertEqual(avifRGBImageAllocatePixels(&rgb), AVIF_RESULT_OK, file: file, line: line)
        defer { avifRGBImageFreePixels(&rgb) }
        XCTAssertEqual(avifImageYUVToRGB(image, &rgb), AVIF_RESULT_OK, file: file, line: line)

        let width = Int(image.pointee.width), height = Int(image.pointee.height)
        var rgba: [UInt8] = []
        for y in 0..<height {
            let row = UnsafeBufferPointer(start: rgb.pixels + y * Int(rgb.rowBytes), count: width * 4)
            rgba += row
        }
        return Decoded(width: width, height: height, rgba: rgba, hasAlphaPlane: image.pointee.alphaPlane != nil)
    }

    private func meanError(_ a: [UInt8], _ b: [UInt8]) -> Double {
        Double(zip(a, b).map { abs(Int($0) - Int($1)) }.reduce(0, +)) / Double(a.count)
    }

    func testWritesAnAVIFFile() throws {
        let avif = try AVIFEncoder.encode(TestImages.gradient(), quality: 60)
        XCTAssertEqual(String(decoding: avif[4..<12], as: UTF8.self), "ftypavif")
    }

    func testRoundTripsCloseToTheOriginal() throws {
        let image = TestImages.gradient(width: 120, height: 80)
        let decoded = try decode(try AVIFEncoder.encode(image, quality: 60))
        XCTAssertEqual(decoded.width, 120)
        XCTAssertEqual(decoded.height, 80)
        XCTAssertLessThan(meanError(decoded.rgba, image.pixels), 6)
    }

    func testOpaqueImagesHaveNoAlphaPlane() throws {
        XCTAssertFalse(try decode(try AVIFEncoder.encode(TestImages.gradient(), quality: 60)).hasAlphaPlane)
    }

    func testKeepsTransparencyExactly() throws {
        let image = TestImages.gradient(alpha: true)
        let decoded = try decode(try AVIFEncoder.encode(image, quality: 60))
        XCTAssertTrue(decoded.hasAlphaPlane)
        let alphas = stride(from: 3, to: decoded.rgba.count, by: 4).map { decoded.rgba[$0] }
        let original = stride(from: 3, to: image.pixels.count, by: 4).map { image.pixels[$0] }
        XCTAssertEqual(alphas, original)
    }

    func testGraphicsKeepTheirColors() throws {
        let image = TestImages.blocks(width: 64, height: 48, colors: [[255, 255, 255, 255], [0, 122, 255, 255], [255, 59, 48, 255]])
        let decoded = try decode(try AVIFEncoder.encode(image, quality: 60))
        XCTAssertLessThan(meanError(decoded.rgba, image.pixels), 6, "4:4:4 keeps flat colors and edges clean")
    }

    func testQualityControlsTheSize() throws {
        let image = TestImages.gradient(width: 200, height: 150)
        XCTAssertLessThan(try AVIFEncoder.encode(image, quality: 20).count, try AVIFEncoder.encode(image, quality: 85).count)
    }
}
