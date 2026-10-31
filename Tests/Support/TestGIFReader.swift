import Foundation

/// A small GIF reader for tests only, written from the GIF89a spec independently of `GIFWriter`,
/// so a bug in the encoder can't hide behind the same bug here. Composes frames the way browsers
/// do (disposal 0/1: draw over the previous frame, skipping transparent pixels).
struct TestGIF {
    struct Frame {
        /// The whole canvas after this frame, RGB.
        var canvas: [UInt8]
        var centiseconds: Int
        var x: Int, y: Int, width: Int, height: Int
    }

    struct Malformed: Error {
        var reason: String
    }

    var width = 0
    var height = 0
    var palette: [UInt8] = []
    var loops = false
    var frames: [Frame] = []

    init(_ data: Data) throws {
        let bytes = [UInt8](data)
        var at = 0
        func byte() throws -> Int {
            guard at < bytes.count else { throw Malformed(reason: "ended early") }
            defer { at += 1 }
            return Int(bytes[at])
        }
        func short() throws -> Int { try byte() | (try byte()) << 8 }
        func subBlocks() throws -> [UInt8] {
            var out: [UInt8] = []
            while true {
                let size = try byte()
                if size == 0 { return out }
                guard at + size <= bytes.count else { throw Malformed(reason: "sub-block overruns") }
                out += bytes[at..<at + size]
                at += size
            }
        }

        guard bytes.count > 13, String(decoding: bytes[0..<6], as: UTF8.self) == "GIF89a" else {
            throw Malformed(reason: "not GIF89a")
        }
        at = 6
        width = try short()
        height = try short()
        let flags = try byte()
        _ = try byte(); _ = try byte()
        if flags & 0x80 != 0 {
            let count = 3 << ((flags & 7) + 1)
            palette = Array(bytes[at..<at + count])
            at += count
        }
        var canvas = [UInt8](repeating: 0, count: width * height * 3)
        var delay = 0
        var transparent: Int?

        loop: while true {
            switch try byte() {
            case 0x21:
                let label = try byte()
                let body = try subBlocks()
                if label == 0xF9, body.count == 4 {
                    delay = Int(body[1]) | Int(body[2]) << 8
                    transparent = body[0] & 1 != 0 ? Int(body[3]) : nil
                } else if label == 0xFF, body.starts(with: Array("NETSCAPE2.0".utf8)) {
                    loops = true
                }
            case 0x2C:
                let x = try short(), y = try short(), w = try short(), h = try short()
                let imageFlags = try byte()
                var colors = palette
                if imageFlags & 0x80 != 0 {
                    let count = 3 << ((imageFlags & 7) + 1)
                    colors = Array(bytes[at..<at + count])
                    at += count
                }
                guard imageFlags & 0x40 == 0 else { throw Malformed(reason: "interlaced isn't expected") }
                let minCodeSize = try byte()
                let indices = try Self.decodeLZW(try subBlocks(), minCodeSize: minCodeSize, count: w * h)
                guard x + w <= width, y + h <= height else { throw Malformed(reason: "frame outside the canvas") }
                for row in 0..<h {
                    for column in 0..<w {
                        let index = Int(indices[row * w + column])
                        if index == transparent { continue }
                        let to = ((y + row) * width + x + column) * 3
                        canvas[to] = colors[index * 3]
                        canvas[to + 1] = colors[index * 3 + 1]
                        canvas[to + 2] = colors[index * 3 + 2]
                    }
                }
                frames.append(Frame(canvas: canvas, centiseconds: delay, x: x, y: y, width: w, height: h))
                delay = 0
                transparent = nil
            case 0x3B:
                break loop
            case let other:
                throw Malformed(reason: "unknown block \(other)")
            }
        }
    }

    /// The textbook GIF LZW decoder.
    static func decodeLZW(_ data: [UInt8], minCodeSize: Int, count: Int) throws -> [UInt8] {
        let clear = 1 << minCodeSize, end = clear + 1
        var table: [[UInt8]] = (0..<clear).map { [UInt8($0)] } + [[], []]
        var codeSize = minCodeSize + 1
        var previous: [UInt8]?
        var out: [UInt8] = []
        var bitPosition = 0
        while true {
            guard bitPosition + codeSize <= data.count * 8 else { throw Malformed(reason: "no end code") }
            var code = 0
            for bit in 0..<codeSize where data[(bitPosition + bit) / 8] >> ((bitPosition + bit) % 8) & 1 != 0 {
                code |= 1 << bit
            }
            bitPosition += codeSize
            if code == clear {
                table = (0..<clear).map { [UInt8($0)] } + [[], []]
                codeSize = minCodeSize + 1
                previous = nil
                continue
            }
            if code == end { break }
            let entry: [UInt8]
            if let previous {
                if code < table.count {
                    entry = table[code]
                } else if code == table.count {
                    entry = previous + [previous[0]]
                } else {
                    throw Malformed(reason: "code \(code) beyond the table (\(table.count))")
                }
                if table.count < 4096 { table.append(previous + [entry[0]]) }
                if table.count == 1 << codeSize && codeSize < 12 { codeSize += 1 }
            } else {
                guard code < clear else { throw Malformed(reason: "first code \(code) isn't a root") }
                entry = table[code]
            }
            out += entry
            previous = entry
        }
        guard out.count == count else { throw Malformed(reason: "\(out.count) pixels, expected \(count)") }
        return out
    }
}
