import XCTest
@testable import Droptimize

// Portable: also run on Linux by scripts/check-linux.sh. Files are read back with `TestGIF`, a
// separate decoder written from the spec.
final class GIFTests: XCTestCase {
    private func frame(_ width: Int, _ height: Int, _ color: (Int, Int) -> (Int, Int, Int)) -> [UInt8] {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = color(x, y)
                let i = (y * width + x) * 4
                pixels[i] = UInt8(r); pixels[i + 1] = UInt8(g); pixels[i + 2] = UInt8(b)
            }
        }
        return pixels
    }

    private func palette(for frames: [[UInt8]]) -> [GIFColor] {
        var histogram = GIFPalette.Histogram()
        for frame in frames { histogram.add(rgba: frame) }
        return GIFPalette.make(from: histogram)
    }

    func testLZWRoundTripsIncludingTableResets() throws {
        var generator = SystemRandomNumberGenerator()
        let encoder = LZWEncoder()
        let cases: [[UInt8]] = [
            [7],
            [UInt8](repeating: 3, count: 10_000),                                  // long runs
            (0..<60_000).map { _ in UInt8.random(in: 0...255, using: &generator) },  // many clears
            (0..<50_000).map { UInt8(($0 / 7) % 5) },                               // small alphabet
            (0..<4_000).map { UInt8($0 % 256) },
        ]
        for symbols in cases {
            let decoded = try TestGIF.decodeLZW(encoder.encode(symbols), minCodeSize: 8, count: symbols.count)
            XCTAssertEqual(decoded, symbols, "\(symbols.count) symbols")
        }
    }

    func testFewColorsAreKeptExactly() throws {
        // Screen recordings and flat graphics: 3 colors, two of them nearly the same gray.
        let image = frame(40, 20) { x, _ in x < 10 ? (250, 250, 250) : x < 20 ? (251, 251, 251) : (20, 120, 220) }
        let colors = palette(for: [image])
        XCTAssertEqual(Set(colors), [GIFColor(r: 250, g: 250, b: 250), GIFColor(r: 251, g: 251, b: 251),
                                     GIFColor(r: 20, g: 120, b: 220)])
        let writer = GIFWriter(width: 40, height: 20, palette: colors)
        writer.add(rgba: image, centiseconds: 10)
        let gif = try TestGIF(writer.finish())
        XCTAssertEqual(gif.frames.count, 1)
        for y in 0..<20 {
            for x in 0..<40 {
                let i = (y * 40 + x)
                XCTAssertEqual(Array(gif.frames[0].canvas[i * 3..<i * 3 + 3]), Array(image[i * 4..<i * 4 + 3]))
            }
        }
    }

    func testGradientsDitherInsteadOfBanding() throws {
        // A smooth two-way gradient with far more colors than a GIF holds.
        let width = 128, height = 64
        let image = frame(width, height) { x, y in (x * 2, y * 4, 255 - x) }
        let writer = GIFWriter(width: width, height: height, palette: palette(for: [image]))
        writer.add(rgba: image, centiseconds: 10)
        let canvas = try TestGIF(writer.finish()).frames[0].canvas

        // Averaged over 4 × 4 blocks (what the eye does), the GIF matches the source closely. The
        // last corner has nowhere left to pass its error, so it gets a looser bound.
        var worst = 0.0, total = 0.0, blocks = 0.0
        for by in stride(from: 0, to: height, by: 4) {
            for bx in stride(from: 0, to: width, by: 4) {
                for channel in 0..<3 {
                    var source = 0.0, result = 0.0
                    for y in by..<by + 4 {
                        for x in bx..<bx + 4 {
                            source += Double(image[(y * width + x) * 4 + channel])
                            result += Double(canvas[(y * width + x) * 3 + channel])
                        }
                    }
                    let error = abs(source - result) / 16
                    worst = max(worst, error)
                    total += error
                    blocks += 1
                }
            }
        }
        XCTAssertLessThan(total / blocks, 2.5, "dithering keeps the average color: no bands")
        XCTAssertLessThan(worst, 12)
    }

    func testOnlyWhatMovedIsRedrawnAndStillAreasDontShimmer() throws {
        let width = 64, height = 48
        func scene(boxAt left: Int) -> [UInt8] {
            frame(width, height) { x, y in
                if (left..<left + 8).contains(x) && (20..<28).contains(y) { return (230, 40, 40) }
                return (x * 4, y * 5, 128 + x)                 // a gradient, so it's dithered
            }
        }
        let frames = [scene(boxAt: 4), scene(boxAt: 12), scene(boxAt: 20)]
        let writer = GIFWriter(width: width, height: height, palette: palette(for: frames))
        for frame in frames { writer.add(rgba: frame, centiseconds: 5) }
        let gif = try TestGIF(writer.finish())

        XCTAssertEqual(gif.frames.count, 3)
        XCTAssertEqual(gif.frames[0].width, width)
        XCTAssertLessThanOrEqual(gif.frames[1].width, 16, "just the strip the box moved through")
        XCTAssertLessThanOrEqual(gif.frames[1].height, 8)
        // The top rows never change, so their dithered pixels must be identical in every frame.
        let top = 0..<(10 * width * 3)
        XCTAssertEqual(Array(gif.frames[1].canvas[top]), Array(gif.frames[0].canvas[top]))
        XCTAssertEqual(Array(gif.frames[2].canvas[top]), Array(gif.frames[0].canvas[top]))
        // And the box really moved.
        let boxPixel = ((24 * width) + 22) * 3
        XCTAssertGreaterThan(gif.frames[2].canvas[boxPixel], 180)
        XCTAssertLessThan(gif.frames[2].canvas[boxPixel + 1], 100)
    }

    func testIdenticalFramesBecomeOneLongerFrameAndItLoops() throws {
        let still = frame(16, 16) { x, y in (x * 16, y * 16, 90) }
        let moved = frame(16, 16) { x, y in (y * 16, x * 16, 90) }
        let writer = GIFWriter(width: 16, height: 16, palette: palette(for: [still, moved]))
        writer.add(rgba: still, centiseconds: 3)
        writer.add(rgba: still, centiseconds: 3)
        writer.add(rgba: still, centiseconds: 4)
        writer.add(rgba: moved, centiseconds: 5)
        let gif = try TestGIF(writer.finish())
        XCTAssertTrue(gif.loops)
        XCTAssertEqual(gif.frames.map(\.centiseconds), [10, 5])
    }

    func testFrameTiming() {
        XCTAssertEqual(VideoTuning.gifFrameStep(sourceFPS: 30), 1)
        XCTAssertEqual(VideoTuning.gifFrameStep(sourceFPS: 29.97), 1)
        XCTAssertEqual(VideoTuning.gifFrameStep(sourceFPS: 24), 1)
        XCTAssertEqual(VideoTuning.gifFrameStep(sourceFPS: 60), 2, "every other frame: still even")
        XCTAssertEqual(VideoTuning.gifFrameStep(sourceFPS: 59.94), 2)
        XCTAssertEqual(VideoTuning.gifFrameStep(sourceFPS: 120), 4)
        // 30 fps: delays of 3, 3, 4… add up to the real time instead of drifting.
        let times = (0...30).map { Double($0) / 30 }
        let delays = zip(times, times.dropFirst()).map { VideoTuning.gifCentiseconds(from: $0, to: $1) }
        XCTAssertEqual(delays.reduce(0, +), 100)
        XCTAssertEqual(Set(delays), [3, 4])
        XCTAssertTrue(VideoTuning.gifSize(width: 1920, height: 1080) == (800, 450))
        XCTAssertTrue(VideoTuning.gifSize(width: 1080, height: 1920) == (450, 800), "portrait")
        XCTAssertTrue(VideoTuning.gifSize(width: 320, height: 240) == (320, 240), "never larger")
    }
}
