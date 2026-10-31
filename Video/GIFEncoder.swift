import Foundation

/// A GIF89a writer for video clips (CORE.md §7.4), with no dependencies. What makes it look better
/// than ImageIO's GIF encoder:
/// - **One palette for the whole clip** (`GIFPalette`), so colors don't jump from frame to frame.
/// - **Floyd–Steinberg dithering**, so gradients don't band.
/// - **Only what changed is redrawn.** Pixels that stay put keep the color they were drawn with, so
///   still areas don't shimmer, and each frame is cropped to what moved, so the file stays small.
/// Portable, so it's tested on Linux too.
struct GIFColor: Equatable, Hashable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
}

// MARK: - Palette

enum GIFPalette {
    /// Index 255 is kept for "unchanged" (transparent), so a palette has at most 255 colors.
    static let maxColors = 255

    /// Counts colors across frames: 32,768 bins of 5 bits per channel, each with the sum of its
    /// colors (so its mean is exact), plus the exact colors themselves while there are few enough.
    struct Histogram {
        fileprivate var counts = [Int](repeating: 0, count: 1 << 15)
        fileprivate var sums = [Int](repeating: 0, count: 3 << 15)
        /// A small open-addressing set of exact colors (0xRRGGBB; `UInt32.max` is empty).
        fileprivate var exact = [UInt32](repeating: .max, count: 1024)
        fileprivate var exactCount = 0
        fileprivate var tooManyColors = false

        init() {}

        /// Adds every `step`th pixel of an RGBA frame (alpha is ignored).
        mutating func add(rgba: [UInt8], step: Int = 1) {
            let stride = max(1, step) * 4
            rgba.withUnsafeBufferPointer { p in
                var i = 0
                while i + 3 < p.count {
                    let r = Int(p[i]), g = Int(p[i + 1]), b = Int(p[i + 2])
                    let bin = (r >> 3) << 10 | (g >> 3) << 5 | b >> 3
                    if !tooManyColors { remember(UInt32(r << 16 | g << 8 | b)) }
                    counts[bin] += 1
                    sums[bin * 3] += r
                    sums[bin * 3 + 1] += g
                    sums[bin * 3 + 2] += b
                    i += stride
                }
            }
        }

        private mutating func remember(_ color: UInt32) {
            var slot = Int((color &* 2_654_435_761) >> 22) & (exact.count - 1)
            while true {
                if exact[slot] == color { return }
                if exact[slot] == .max {
                    exact[slot] = color
                    exactCount += 1
                    if exactCount > GIFPalette.maxColors { tooManyColors = true }
                    return
                }
                slot = (slot + 1) & (exact.count - 1)
            }
        }
    }

    /// The palette for everything added to `histogram`: its exact colors when there are few enough
    /// (screen recordings, flat graphics), otherwise median cut refined by a few rounds of k-means.
    static func make(from histogram: Histogram, maxColors: Int = maxColors) -> [GIFColor] {
        if !histogram.tooManyColors && histogram.exactCount <= maxColors {
            let exact = histogram.exact.filter { $0 != .max }.sorted()
                .map { GIFColor(r: UInt8($0 >> 16 & 0xFF), g: UInt8($0 >> 8 & 0xFF), b: UInt8($0 & 0xFF)) }
            return exact.isEmpty ? [GIFColor(r: 0, g: 0, b: 0)] : exact
        }
        var points: [Point] = []
        for bin in 0..<histogram.counts.count where histogram.counts[bin] > 0 {
            let count = Double(histogram.counts[bin])
            points.append(((Double(histogram.sums[bin * 3]) / count, Double(histogram.sums[bin * 3 + 1]) / count,
                            Double(histogram.sums[bin * 3 + 2]) / count), count))
        }
        if points.isEmpty { return [GIFColor(r: 0, g: 0, b: 0)] }

        var centers = medianCut(points, maxColors: maxColors)
        for _ in 0..<VideoTuning.gifPaletteRefinements {
            centers = refine(points, centers: centers)
        }
        return centers.map { GIFColor(r: UInt8(clamping: Int($0.0.rounded())), g: UInt8(clamping: Int($0.1.rounded())),
                                      b: UInt8(clamping: Int($0.2.rounded()))) }
    }

    private typealias Point = (color: (Double, Double, Double), weight: Double)

    /// Splits the color cloud into boxes, always the box with the most weighted error, along its
    /// widest channel, at its weighted median. Each box's mean becomes a color.
    private static func medianCut(_ points: [Point], maxColors: Int) -> [(Double, Double, Double)] {
        struct Box {
            var members: [Int]
            var mean: (Double, Double, Double)
            var error: Double
        }
        func box(_ members: [Int]) -> Box {
            var total = 0.0, r = 0.0, g = 0.0, b = 0.0
            for i in members {
                let p = points[i]
                total += p.weight
                r += p.color.0 * p.weight; g += p.color.1 * p.weight; b += p.color.2 * p.weight
            }
            let mean = (r / total, g / total, b / total)
            var error = 0.0
            for i in members { error += points[i].weight * distance(points[i].color, mean) }
            return Box(members: members, mean: mean, error: error)
        }

        var boxes = [box(Array(points.indices))]
        while boxes.count < maxColors {
            guard let worst = boxes.indices.max(by: { boxes[$0].error < boxes[$1].error }),
                  boxes[worst].error > 0, boxes[worst].members.count > 1 else { break }
            let members = boxes[worst].members
            // The channel with the largest weighted spread.
            var spread = [0.0, 0.0, 0.0]
            let mean = boxes[worst].mean
            for i in members {
                let c = points[i].color, w = points[i].weight
                spread[0] += w * (c.0 - mean.0) * (c.0 - mean.0)
                spread[1] += w * (c.1 - mean.1) * (c.1 - mean.1)
                spread[2] += w * (c.2 - mean.2) * (c.2 - mean.2)
            }
            let axis = spread.indices.max { spread[$0] < spread[$1] } ?? 0
            func value(_ i: Int) -> Double {
                axis == 0 ? points[i].color.0 : axis == 1 ? points[i].color.1 : points[i].color.2
            }
            let sorted = members.sorted { value($0) < value($1) }
            let half = sorted.reduce(0.0) { $0 + points[$1].weight } / 2
            var running = 0.0
            var cut = 1
            for (position, i) in sorted.enumerated() {
                running += points[i].weight
                if running >= half { cut = position + 1; break }
            }
            cut = min(max(cut, 1), sorted.count - 1)
            boxes[worst] = box(Array(sorted[..<cut]))
            boxes.append(box(Array(sorted[cut...])))
        }
        return boxes.map(\.mean)
    }

    /// One round of k-means: every point to its nearest color, every color to the mean of its points.
    private static func refine(_ points: [Point], centers: [(Double, Double, Double)]) -> [(Double, Double, Double)] {
        var sums = [(Double, Double, Double, Double)](repeating: (0, 0, 0, 0), count: centers.count)
        for point in points {
            var best = 0, bestDistance = Double.infinity
            for (index, center) in centers.enumerated() {
                let d = distance(point.color, center)
                if d < bestDistance { bestDistance = d; best = index }
            }
            let w = point.weight
            sums[best].0 += point.color.0 * w; sums[best].1 += point.color.1 * w; sums[best].2 += point.color.2 * w
            sums[best].3 += w
        }
        return centers.indices.map { i in
            sums[i].3 > 0 ? (sums[i].0 / sums[i].3, sums[i].1 / sums[i].3, sums[i].2 / sums[i].3) : centers[i]
        }
    }

    /// Squared distance, weighted toward green and red the way eyes are.
    static func distance(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let dr = a.0 - b.0, dg = a.1 - b.1, db = a.2 - b.2
        return 3 * dr * dr + 4 * dg * dg + 2 * db * db
    }
}

// MARK: - Writer

/// Writes frames as they come; `finish()` returns the file.
final class GIFWriter {
    let width: Int
    let height: Int
    let palette: [GIFColor]
    static let transparentIndex: UInt8 = 255

    private var data = Data()
    /// For each pixel: the source color when it was last drawn (to tell whether it changed since),
    /// and the palette index on screen.
    private var drawnSource: [UInt8]
    private var shown: [UInt8]
    private var isFirstFrame = true
    /// The last frame waits until we know how long it stays up (identical frames extend it).
    private var pending: (bytes: [UInt8], delayOffset: Int, centiseconds: Int)?
    private var lookup = [Int16](repeating: -1, count: 1 << 18)
    private let lzw = LZWEncoder()

    init(width: Int, height: Int, palette: [GIFColor], loops: Bool = true) {
        precondition(width > 0 && height > 0 && width <= 0xFFFF && height <= 0xFFFF)
        precondition(!palette.isEmpty && palette.count <= GIFPalette.maxColors)
        self.width = width
        self.height = height
        self.palette = palette
        drawnSource = [UInt8](repeating: 0, count: width * height * 3)
        shown = [UInt8](repeating: 0, count: width * height)
        // Cells holding two or more palette colors are searched exactly, so exact colors stay exact.
        for (index, color) in palette.enumerated() {
            let key = Self.cell(Int(color.r), Int(color.g), Int(color.b))
            lookup[key] = lookup[key] == -1 ? Int16(index) : -2
        }

        data.append(contentsOf: Array("GIF89a".utf8))
        appendShort(width)
        appendShort(height)
        data.append(0xF7)                    // global color table of 256 entries, 8 bits per channel
        data.append(0)                       // background color index
        data.append(0)                       // square pixels
        for index in 0..<256 {
            let color = index < palette.count ? palette[index] : GIFColor(r: 0, g: 0, b: 0)
            data.append(contentsOf: [color.r, color.g, color.b])
        }
        if loops {
            data.append(contentsOf: [0x21, 0xFF, 0x0B])
            data.append(contentsOf: Array("NETSCAPE2.0".utf8))
            data.append(contentsOf: [0x03, 0x01, 0x00, 0x00, 0x00])       // loop forever
        }
    }

    /// Adds a frame of `width` × `height` RGBA pixels (alpha ignored), shown for `centiseconds`.
    func add(rgba frame: [UInt8], centiseconds: Int) {
        precondition(frame.count == width * height * 4)
        let indices = quantize(frame)
        guard let rect = indices.changed else {
            // Nothing moved: the previous frame just stays up longer.
            if pending != nil { pending!.centiseconds += centiseconds }
            return
        }
        flushPending()

        var bytes: [UInt8] = []
        // Graphic control extension: keep the previous frame underneath (disposal 1), and treat
        // index 255 as see-through on every frame after the first.
        let transparent: UInt8 = isFirstFrame ? 0 : 1
        bytes += [0x21, 0xF9, 0x04, 1 << 2 | transparent]
        let delayOffset = bytes.count
        bytes += [0, 0, Self.transparentIndex, 0]
        // Image descriptor: just the rectangle that changed.
        bytes.append(0x2C)
        for value in [rect.x, rect.y, rect.width, rect.height] {
            bytes += [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)]
        }
        bytes.append(0)
        bytes.append(8)                       // LZW minimum code size
        var cropped = [UInt8](repeating: 0, count: rect.width * rect.height)
        for row in 0..<rect.height {
            let from = (rect.y + row) * width + rect.x
            for column in 0..<rect.width { cropped[row * rect.width + column] = indices.pixels[from + column] }
        }
        let compressed = lzw.encode(cropped)
        var start = 0
        while start < compressed.count {
            let end = min(start + 255, compressed.count)
            bytes.append(UInt8(end - start))
            bytes += compressed[start..<end]
            start = end
        }
        bytes.append(0)
        pending = (bytes, delayOffset, centiseconds)
        isFirstFrame = false
    }

    /// The finished file. Call once, after the last frame.
    func finish() -> Data {
        flushPending()
        data.append(0x3B)
        return data
    }

    private func flushPending() {
        guard var frame = pending else { return }
        let delay = min(max(frame.centiseconds, VideoTuning.gifMinCentiseconds), 0xFFFF)
        frame.bytes[frame.delayOffset] = UInt8(delay & 0xFF)
        frame.bytes[frame.delayOffset + 1] = UInt8(delay >> 8)
        data.append(contentsOf: frame.bytes)
        pending = nil
    }

    private func appendShort(_ value: Int) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8(value >> 8 & 0xFF))
    }

    // MARK: Dithering

    /// Palette indices for the whole frame (255 where nothing changed) and the rectangle around
    /// what did change, nil when nothing did.
    private func quantize(_ frame: [UInt8]) -> (pixels: [UInt8], changed: (x: Int, y: Int, width: Int, height: Int)?) {
        var out = [UInt8](repeating: Self.transparentIndex, count: width * height)
        var minX = width, minY = height, maxX = -1, maxY = -1
        let strength = Float(VideoTuning.gifDitherStrength)
        let limit = Float(VideoTuning.gifDitherErrorLimit)
        let threshold = VideoTuning.gifChangeThreshold
        let first = isFirstFrame
        // Errors carried to this row and the next, 3 channels, one pixel of padding on each side.
        var current = [Float](repeating: 0, count: (width + 2) * 3)
        var next = current
        frame.withUnsafeBufferPointer { src in
            for y in 0..<height {
                let leftToRight = y % 2 == 0          // serpentine, so errors don't drift one way
                for i in next.indices { next[i] = 0 }
                for step in 0..<width {
                    let x = leftToRight ? step : width - 1 - step
                    let p = y * width + x
                    let s = p * 4
                    let r = Int(src[s]), g = Int(src[s + 1]), b = Int(src[s + 2])
                    let e = (x + 1) * 3
                    let wantR = Float(r) + current[e], wantG = Float(g) + current[e + 1], wantB = Float(b) + current[e + 2]

                    let index: UInt8
                    let d = p * 3
                    let dr = r - Int(drawnSource[d]), dg = g - Int(drawnSource[d + 1]), db = b - Int(drawnSource[d + 2])
                    if first || dr * dr + dg * dg + db * db > threshold {
                        index = nearest(wantR, wantG, wantB)
                        shown[p] = index
                        drawnSource[d] = UInt8(r); drawnSource[d + 1] = UInt8(g); drawnSource[d + 2] = UInt8(b)
                        out[p] = index
                        if x < minX { minX = x }
                        if x > maxX { maxX = x }
                        if y < minY { minY = y }
                        if y > maxY { maxY = y }
                    } else {
                        index = shown[p]                 // stays as drawn; 255 in `out`
                    }

                    // Spread what the chosen color misses to the neighbours still to come.
                    let color = palette[Int(index)]
                    let er = min(max((wantR - Float(color.r)) * strength, -limit), limit)
                    let eg = min(max((wantG - Float(color.g)) * strength, -limit), limit)
                    let eb = min(max((wantB - Float(color.b)) * strength, -limit), limit)
                    let ahead = leftToRight ? e + 3 : e - 3
                    let behind = leftToRight ? e - 3 : e + 3
                    current[ahead] += er * 7 / 16; current[ahead + 1] += eg * 7 / 16; current[ahead + 2] += eb * 7 / 16
                    next[behind] += er * 3 / 16; next[behind + 1] += eg * 3 / 16; next[behind + 2] += eb * 3 / 16
                    next[e] += er * 5 / 16; next[e + 1] += eg * 5 / 16; next[e + 2] += eb * 5 / 16
                    next[ahead] += er / 16; next[ahead + 1] += eg / 16; next[ahead + 2] += eb / 16
                }
                swap(&current, &next)
            }
        }
        guard maxX >= 0 else { return (out, nil) }
        return (out, (minX, minY, maxX - minX + 1, maxY - minY + 1))
    }

    /// The nearest palette color, cached per cell of 6 bits per channel: -1 not looked up yet,
    /// -2 holds several palette colors (search exactly every time).
    private func nearest(_ r: Float, _ g: Float, _ b: Float) -> UInt8 {
        let ri = Int(min(max(r.rounded(), 0), 255)), gi = Int(min(max(g.rounded(), 0), 255))
        let bi = Int(min(max(b.rounded(), 0), 255))
        let key = Self.cell(ri, gi, bi)
        let cached = lookup[key]
        if cached >= 0 { return UInt8(cached) }
        if cached == -2 { return search((Double(ri), Double(gi), Double(bi))) }
        let best = search((Double(ri & ~3 | 2), Double(gi & ~3 | 2), Double(bi & ~3 | 2)))   // the cell's middle
        lookup[key] = Int16(best)
        return best
    }

    private func search(_ target: (Double, Double, Double)) -> UInt8 {
        var best = 0, bestDistance = Double.infinity
        for (index, color) in palette.enumerated() {
            let d = GIFPalette.distance(target, (Double(color.r), Double(color.g), Double(color.b)))
            if d < bestDistance { bestDistance = d; best = index }
        }
        return UInt8(best)
    }

    private static func cell(_ r: Int, _ g: Int, _ b: Int) -> Int {
        (r >> 2) << 12 | (g >> 2) << 6 | b >> 2
    }
}

// MARK: - LZW

/// GIF's variable-width LZW, 8-bit symbols. Mirrors giflib's encoder: codes grow a bit as soon as
/// the next free code no longer fits, and the table restarts (clear code) before code 4095.
final class LZWEncoder {
    private static let maxCode = 4095
    /// (prefix code << 8 | byte) → code, valid only where `generation` matches, so a clear is O(1).
    private var codes = [Int16](repeating: 0, count: 4096 * 256)
    private var generation = [UInt32](repeating: 0, count: 4096 * 256)
    private var currentGeneration: UInt32 = 0

    func encode(_ symbols: [UInt8]) -> [UInt8] {
        let minCodeSize = 8
        let clear = 1 << minCodeSize, end = clear + 1
        var codeSize = minCodeSize + 1
        var nextCode = end + 1
        var writer = BitWriter()
        currentGeneration &+= 1
        if currentGeneration == 0 {                    // wrapped: forget everything for real
            for i in generation.indices { generation[i] = 0 }
            currentGeneration = 1
        }

        func emit(_ code: Int) {
            writer.write(code, bits: codeSize)
            if nextCode >= 1 << codeSize && codeSize < 12 { codeSize += 1 }
        }

        writer.write(clear, bits: codeSize)
        guard var prefix = symbols.first.map(Int.init) else {
            writer.write(end, bits: codeSize)
            return writer.finish()
        }
        symbols.withUnsafeBufferPointer { input in
            for position in input.indices.dropFirst() {
                let byte = Int(input[position])
                let key = prefix << 8 | byte
                if generation[key] == currentGeneration {
                    prefix = Int(codes[key])
                    continue
                }
                emit(prefix)
                if nextCode >= Self.maxCode {
                    writer.write(clear, bits: codeSize)
                    currentGeneration &+= 1
                    if currentGeneration == 0 {
                        for i in generation.indices { generation[i] = 0 }
                        currentGeneration = 1
                    }
                    codeSize = minCodeSize + 1
                    nextCode = end + 1
                } else {
                    codes[key] = Int16(nextCode)
                    generation[key] = currentGeneration
                    nextCode += 1
                }
                prefix = byte
            }
        }
        emit(prefix)
        writer.write(end, bits: codeSize)
        return writer.finish()
    }

    /// Packs codes least significant bit first, as GIF wants.
    private struct BitWriter {
        var bytes: [UInt8] = []
        var buffer: UInt64 = 0
        var count = 0

        mutating func write(_ code: Int, bits: Int) {
            buffer |= UInt64(code) << UInt64(count)
            count += bits
            while count >= 8 {
                bytes.append(UInt8(buffer & 0xFF))
                buffer >>= 8
                count -= 8
            }
        }

        mutating func finish() -> [UInt8] {
            if count > 0 { bytes.append(UInt8(buffer & 0xFF)) }
            buffer = 0
            count = 0
            return bytes
        }
    }
}
