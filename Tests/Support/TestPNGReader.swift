import Foundation
#if canImport(zlib)
import zlib
#else
import CZlib
#endif
@testable import Droptimize

/// Test-only PNG reader for what `PNGEncoder` writes (no interlacing). It checks every CRC and
/// undoes the filters itself, so encoder tests don't rely on another decoder.
enum TestPNGReader {
    struct Image {
        var width: Int
        var height: Int
        var colorType: UInt8
        var bitDepth: UInt8
        var rgba: [UInt8]
        var chunkTypes: [String]
    }

    enum Failure: Error { case signature, crc(String), truncated, inflate(Int32), unsupported }

    static func read(_ data: Data) throws -> Image {
        let bytes = [UInt8](data)
        guard bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else { throw Failure.signature }
        var offset = 8
        var width = 0, height = 0
        var bitDepth: UInt8 = 0, colorType: UInt8 = 0
        var palette: [UInt8] = [], transparency: [UInt8] = []
        var idat: [UInt8] = []
        var types: [String] = []
        func u32(_ at: Int) -> Int { Int(bytes[at]) << 24 | Int(bytes[at + 1]) << 16 | Int(bytes[at + 2]) << 8 | Int(bytes[at + 3]) }
        while offset + 12 <= bytes.count {
            let length = u32(offset)
            guard offset + 12 + length <= bytes.count else { throw Failure.truncated }
            let type = String(decoding: bytes[offset + 4..<offset + 8], as: UTF8.self)
            let body = Array(bytes[offset + 8..<offset + 8 + length])
            let stored = UInt(u32(offset + 8 + length))
            let computed = Array(bytes[offset + 4..<offset + 8 + length]).withUnsafeBufferPointer {
                UInt(crc32(0, $0.baseAddress, uInt($0.count)))
            }
            guard stored == computed else { throw Failure.crc(type) }
            types.append(type)
            switch type {
            case "IHDR":
                width = u32(offset + 8); height = u32(offset + 12)
                bitDepth = body[8]; colorType = body[9]
                guard body[12] == 0 else { throw Failure.unsupported }
            case "PLTE": palette = body
            case "tRNS": transparency = body
            case "IDAT": idat += body
            default: break
            }
            offset += 12 + length
        }

        let channels: Int = [0: 1, 2: 3, 3: 1, 4: 2, 6: 4][colorType] ?? 0
        guard channels > 0 else { throw Failure.unsupported }
        let rowBytes = (width * channels * Int(bitDepth) + 7) / 8
        var raw = [UInt8](repeating: 0, count: (rowBytes + 1) * height)
        var rawLength = uLong(raw.count)
        let status = idat.withUnsafeBufferPointer { uncompress(&raw, &rawLength, $0.baseAddress, uLong($0.count)) }
        guard status == Z_OK, Int(rawLength) == raw.count else { throw Failure.inflate(status) }

        // Undo the filters.
        let unit = max(1, channels * Int(bitDepth) / 8)
        var rows = [UInt8](repeating: 0, count: rowBytes * height)
        for y in 0..<height {
            let filter = raw[y * (rowBytes + 1)]
            for i in 0..<rowBytes {
                let x = raw[y * (rowBytes + 1) + 1 + i]
                let a: UInt8 = i >= unit ? rows[y * rowBytes + i - unit] : 0
                let b: UInt8 = y > 0 ? rows[(y - 1) * rowBytes + i] : 0
                let c: UInt8 = (i >= unit && y > 0) ? rows[(y - 1) * rowBytes + i - unit] : 0
                switch filter {
                case 0: rows[y * rowBytes + i] = x
                case 1: rows[y * rowBytes + i] = x &+ a
                case 2: rows[y * rowBytes + i] = x &+ b
                case 3: rows[y * rowBytes + i] = x &+ UInt8((Int(a) + Int(b)) / 2)
                case 4: rows[y * rowBytes + i] = x &+ PNGEncoder.paeth(a, b, c)
                default: throw Failure.unsupported
                }
            }
        }

        // Expand to RGBA.
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * 4
                let row = y * rowBytes
                switch colorType {
                case 0:
                    let v = rows[row + x]
                    rgba[o] = v; rgba[o + 1] = v; rgba[o + 2] = v; rgba[o + 3] = 255
                case 4:
                    let v = rows[row + x * 2]
                    rgba[o] = v; rgba[o + 1] = v; rgba[o + 2] = v; rgba[o + 3] = rows[row + x * 2 + 1]
                case 2:
                    for k in 0..<3 { rgba[o + k] = rows[row + x * 3 + k] }
                    rgba[o + 3] = 255
                case 6:
                    for k in 0..<4 { rgba[o + k] = rows[row + x * 4 + k] }
                default: // palette
                    let depth = Int(bitDepth)
                    let index: Int
                    if depth == 8 {
                        index = Int(rows[row + x])
                    } else {
                        let perByte = 8 / depth
                        let shift = 8 - depth * (x % perByte + 1)
                        index = Int(rows[row + x / perByte] >> UInt8(shift)) & ((1 << depth) - 1)
                    }
                    for k in 0..<3 { rgba[o + k] = palette[index * 3 + k] }
                    rgba[o + 3] = index < transparency.count ? transparency[index] : 255
                }
            }
        }
        return Image(width: width, height: height, colorType: colorType, bitDepth: bitDepth, rgba: rgba, chunkTypes: types)
    }
}

/// Small deterministic test images.
enum TestImages {
    /// A smooth color gradient: lots of colors, like a photo.
    static func gradient(width: Int = 64, height: Int = 48, alpha: Bool = false) -> RGBAImage {
        var pixels: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                let a: UInt8 = alpha ? UInt8((x + y) * 255 / (width + height)) : 255
                if a == 0 {
                    pixels += [0, 0, 0, 0]
                } else {
                    pixels += [UInt8(x * 255 / width), UInt8(y * 255 / height), UInt8((x + y) * 255 / (width + height)), a]
                }
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    /// Flat blocks of `colors.count` colors, like a UI screenshot or a logo.
    static func blocks(width: Int = 50, height: Int = 30, colors: [[UInt8]]) -> RGBAImage {
        var pixels: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                pixels += colors[(x / 5 + y / 5) % colors.count]
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    /// Pseudo-random noise: nothing compresses it.
    static func noise(width: Int = 40, height: Int = 40, seed: UInt32 = 1) -> RGBAImage {
        var state = seed
        var pixels: [UInt8] = []
        for _ in 0..<(width * height) {
            for _ in 0..<3 {
                state = state &* 1_664_525 &+ 1_013_904_223
                pixels.append(UInt8(truncatingIfNeeded: state >> 24))
            }
            pixels.append(255)
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }
}
