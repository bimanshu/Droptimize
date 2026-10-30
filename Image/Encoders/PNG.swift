import Foundation
#if canImport(zlib)
import zlib
#else
import CZlib
#endif

/// Lossless PNG encoder. It writes the smallest standard layout that holds the image exactly:
/// a palette (1, 2, 4 or 8 bits) for 256 colors or fewer, grayscale when every pixel is gray,
/// RGB when nothing is transparent. Rows are filtered adaptively and compressed with zlib at
/// level 9, and no metadata is written (CORE.md §6.2).
///
/// A license-free stand-in for the PNG pipeline in CORE.md §6.3 (pngquant → oxipng), which
/// waits on the free-or-paid decision.
enum PNGEncoder {
    enum Failure: Error, Equatable {
        case compression(Int32)
    }

    static func encode(_ image: RGBAImage) throws -> Data {
        let layout = Layout(analyzing: image)
        let compressed = try deflate(layout.filteredScanlines(of: image))

        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var header = Data()
        header.appendBigEndian(UInt32(image.width))
        header.appendBigEndian(UInt32(image.height))
        header.append(contentsOf: [layout.bitDepth, layout.colorType.rawValue, 0, 0, 0])
        png.appendChunk("IHDR", header)
        if let palette = layout.palette {
            png.appendChunk("PLTE", Data(palette.flatMap { color in
                [UInt8(truncatingIfNeeded: color >> 24), UInt8(truncatingIfNeeded: color >> 16),
                 UInt8(truncatingIfNeeded: color >> 8)]
            }))
            // Transparent entries come first, so tRNS can stop at the last of them.
            let alphas = palette.map { UInt8(truncatingIfNeeded: $0) }
            if let last = alphas.lastIndex(where: { $0 != 255 }) {
                png.appendChunk("tRNS", Data(alphas[...last]))
            }
        }
        png.appendChunk("IDAT", compressed)
        png.appendChunk("IEND", Data())
        return png
    }

    enum ColorType: UInt8 {
        case gray = 0, rgb = 2, palette = 3, grayAlpha = 4, rgba = 6

        var channels: Int {
            switch self {
            case .gray, .palette: return 1
            case .grayAlpha: return 2
            case .rgb: return 3
            case .rgba: return 4
            }
        }
    }

    /// How the image will be stored.
    struct Layout {
        var colorType: ColorType
        var bitDepth: UInt8
        /// Palette colors as 0xRRGGBBAA, transparent ones first.
        var palette: [UInt32]?

        init(analyzing image: RGBAImage) {
            var opaque = true
            var gray = true
            var colors = Set<UInt32>()
            var tooManyColors = false
            image.pixels.withUnsafeBufferPointer { p in
                var previous: UInt32?
                var index = 0
                while index < p.count {
                    if p[index + 3] != 255 { opaque = false }
                    if p[index] != p[index + 1] || p[index + 1] != p[index + 2] { gray = false }
                    if !tooManyColors {
                        let color = RGBAImage.pack(p, at: index)
                        if color != previous {
                            colors.insert(color)
                            previous = color
                            tooManyColors = colors.count > 256
                        }
                    }
                    index += 4
                }
            }

            func usePalette() -> Layout {
                let transparent = colors.filter { $0 & 0xFF != 0xFF }.sorted()
                let solid = colors.filter { $0 & 0xFF == 0xFF }.sorted()
                let depth: UInt8 = colors.count <= 2 ? 1 : colors.count <= 4 ? 2 : colors.count <= 16 ? 4 : 8
                return Layout(colorType: .palette, bitDepth: depth, palette: transparent + solid)
            }

            if !tooManyColors && colors.count <= 16 {
                self = usePalette()               // packs several pixels per byte
            } else if gray {
                self = Layout(colorType: opaque ? .gray : .grayAlpha, bitDepth: 8, palette: nil)
            } else if !tooManyColors {
                self = usePalette()
            } else {
                self = Layout(colorType: opaque ? .rgb : .rgba, bitDepth: 8, palette: nil)
            }
        }

        private init(colorType: ColorType, bitDepth: UInt8, palette: [UInt32]?) {
            self.colorType = colorType
            self.bitDepth = bitDepth
            self.palette = palette
        }

        func rowBytes(width: Int) -> Int {
            (width * colorType.channels * Int(bitDepth) + 7) / 8
        }

        /// Every row, each prefixed with the filter type that makes it compress best.
        func filteredScanlines(of image: RGBAImage) -> [UInt8] {
            let rowBytes = rowBytes(width: image.width)
            let packed = pack(image, rowBytes: rowBytes)
            var output = [UInt8](repeating: 0, count: (rowBytes + 1) * image.height)
            // Byte distance to "the pixel to the left", as PNG filters define it.
            let unit = max(1, colorType.channels * Int(bitDepth) / 8)
            // The PNG spec's advice: no filtering for palette and sub-byte images.
            let adaptive = colorType != .palette && bitDepth == 8
            var scratch = [[UInt8]](repeating: [UInt8](repeating: 0, count: rowBytes), count: 5)

            packed.withUnsafeBufferPointer { packed in
                output.withUnsafeMutableBufferPointer { output in
                    for y in 0..<image.height {
                        let row = packed.baseAddress! + y * rowBytes
                        let above: UnsafePointer<UInt8>? = y > 0 ? row - rowBytes : nil
                        let destination = output.baseAddress! + y * (rowBytes + 1)
                        guard adaptive else {
                            destination[0] = 0
                            (destination + 1).update(from: row, count: rowBytes)
                            continue
                        }
                        var best = (type: 0, cost: Int.max)
                        for type in 0..<5 {
                            let cost = scratch[type].withUnsafeMutableBufferPointer { out in
                                Self.filter(type, row: row, above: above, count: rowBytes, unit: unit, into: out.baseAddress!)
                            }
                            if cost < best.cost { best = (type, cost) }
                        }
                        destination[0] = UInt8(best.type)
                        scratch[best.type].withUnsafeBufferPointer { filtered in
                            (destination + 1).update(from: filtered.baseAddress!, count: rowBytes)
                        }
                    }
                }
            }
            return output
        }

        /// The unfiltered rows in this layout's color type and bit depth.
        private func pack(_ image: RGBAImage, rowBytes: Int) -> [UInt8] {
            var packed = [UInt8](repeating: 0, count: rowBytes * image.height)
            var indices: [UInt32: UInt8] = [:]
            if let palette {
                for (index, color) in palette.enumerated() { indices[color] = UInt8(index) }
            }
            let depth = Int(bitDepth)
            image.pixels.withUnsafeBufferPointer { p in
                packed.withUnsafeMutableBufferPointer { out in
                    var last: (color: UInt32, index: UInt8)?
                    for y in 0..<image.height {
                        let rowStart = y * rowBytes
                        for x in 0..<image.width {
                            let i = (y * image.width + x) * 4
                            switch colorType {
                            case .gray:
                                out[rowStart + x] = p[i]
                            case .grayAlpha:
                                out[rowStart + x * 2] = p[i]
                                out[rowStart + x * 2 + 1] = p[i + 3]
                            case .rgb:
                                out[rowStart + x * 3] = p[i]
                                out[rowStart + x * 3 + 1] = p[i + 1]
                                out[rowStart + x * 3 + 2] = p[i + 2]
                            case .rgba:
                                for channel in 0..<4 { out[rowStart + x * 4 + channel] = p[i + channel] }
                            case .palette:
                                let color = RGBAImage.pack(p, at: i)
                                let index: UInt8
                                if let last, last.color == color {
                                    index = last.index
                                } else {
                                    index = indices[color] ?? 0
                                    last = (color, index)
                                }
                                if depth == 8 {
                                    out[rowStart + x] = index
                                } else {
                                    let perByte = 8 / depth
                                    let shift = 8 - depth * (x % perByte + 1)
                                    out[rowStart + x / perByte] |= index << UInt8(shift)
                                }
                            }
                        }
                    }
                }
            }
            return packed
        }

        /// Applies PNG filter `type` (0 None, 1 Sub, 2 Up, 3 Average, 4 Paeth) to one row and
        /// returns the sum of the filtered bytes as signed values, the usual "smallest wins" score.
        private static func filter(_ type: Int, row: UnsafePointer<UInt8>, above: UnsafePointer<UInt8>?,
                                   count: Int, unit: Int, into out: UnsafeMutablePointer<UInt8>) -> Int {
            var cost = 0
            for i in 0..<count {
                let x = row[i]
                let a: UInt8 = i >= unit ? row[i - unit] : 0
                let b: UInt8 = above?[i] ?? 0
                let c: UInt8 = i >= unit ? (above?[i - unit] ?? 0) : 0
                let value: UInt8
                switch type {
                case 1: value = x &- a
                case 2: value = x &- b
                case 3: value = x &- UInt8((Int(a) + Int(b)) / 2)
                case 4: value = x &- PNGEncoder.paeth(a, b, c)
                default: value = x
                }
                out[i] = value
                cost += Int(Int8(bitPattern: value).magnitude)
            }
            return cost
        }
    }

    @inline(__always)
    static func paeth(_ a: UInt8, _ b: UInt8, _ c: UInt8) -> UInt8 {
        let p = Int(a) + Int(b) - Int(c)
        let pa = abs(p - Int(a)), pb = abs(p - Int(b)), pc = abs(p - Int(c))
        if pa <= pb && pa <= pc { return a }
        return pb <= pc ? b : c
    }

    private static func deflate(_ bytes: [UInt8]) throws -> Data {
        var length = compressBound(uLong(bytes.count))
        var output = [UInt8](repeating: 0, count: Int(length))
        let status = bytes.withUnsafeBufferPointer { input in
            compress2(&output, &length, input.baseAddress, uLong(bytes.count), Z_BEST_COMPRESSION)
        }
        guard status == Z_OK else { throw Failure.compression(status) }
        return Data(output[..<Int(length)])
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        append(contentsOf: [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
                            UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
    }

    /// Length, type, body and CRC-32 of the type and body.
    mutating func appendChunk(_ type: String, _ body: Data) {
        let typeBytes = Data(type.utf8)
        appendBigEndian(UInt32(body.count))
        append(typeBytes)
        append(body)
        var crc = typeBytes.withUnsafeBytes { crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt($0.count)) }
        if !body.isEmpty {
            // (zlib's crc32 restarts at 0 when handed no bytes, so only call it with some.)
            crc = body.withUnsafeBytes { crc32(crc, $0.bindMemory(to: UInt8.self).baseAddress, uInt($0.count)) }
        }
        appendBigEndian(UInt32(truncatingIfNeeded: crc))
    }
}
