import Foundation
#if canImport(zlib)
import zlib
#else
import CZlib
#endif

/// Reads the files inside a ZIP archive (a .docx is one), stored or deflated, with the system's
/// zlib. Enough for Office documents: no ZIP64, no encryption, no multi-disk archives.
struct ZipArchive {
    enum Failure: Error, Equatable {
        case notAZip
        case unsupported(String)
        case corrupt(String)
    }

    private let data: Data
    /// Each file's name and where its local header starts.
    private(set) var entries: [String: Entry] = [:]

    struct Entry {
        var method: UInt16
        var compressedSize: Int
        var size: Int
        var localHeader: Int
    }

    init(_ data: Data) throws {
        self.data = data
        // The end-of-central-directory record is at the end, before an optional comment.
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw Failure.notAZip }
        var end = -1
        var index = bytes.count - 22
        while index >= max(0, bytes.count - 22 - 65_535) {
            if Self.u32(bytes, index) == 0x0605_4B50 { end = index; break }
            index -= 1
        }
        guard end >= 0 else { throw Failure.notAZip }
        let count = Int(Self.u16(bytes, end + 10))
        var cursor = Int(Self.u32(bytes, end + 16))
        for _ in 0..<count {
            guard cursor + 46 <= bytes.count, Self.u32(bytes, cursor) == 0x0201_4B50 else { throw Failure.corrupt("central directory") }
            let method = Self.u16(bytes, cursor + 10)
            let compressed = Self.u32(bytes, cursor + 20), size = Self.u32(bytes, cursor + 24)
            let nameLength = Int(Self.u16(bytes, cursor + 28)), extra = Int(Self.u16(bytes, cursor + 30))
            let comment = Int(Self.u16(bytes, cursor + 32)), local = Self.u32(bytes, cursor + 42)
            guard compressed != 0xFFFF_FFFF, size != 0xFFFF_FFFF, local != 0xFFFF_FFFF else { throw Failure.unsupported("ZIP64") }
            guard cursor + 46 + nameLength <= bytes.count else { throw Failure.corrupt("name") }
            let name = String(decoding: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
            entries[name] = Entry(method: method, compressedSize: Int(compressed), size: Int(size), localHeader: Int(local))
            cursor += 46 + nameLength + extra + comment
        }
    }

    /// The file's bytes, or nil when the archive has no such file.
    func file(_ name: String) throws -> Data? {
        guard let entry = entries[name] else { return nil }
        let start = entry.localHeader
        guard start + 30 <= data.count else { throw Failure.corrupt(name) }
        let header = [UInt8](data[(data.startIndex + start)..<(data.startIndex + start + 30)])
        guard Self.u32(header, 0) == 0x0403_4B50 else { throw Failure.corrupt(name) }
        let offset = start + 30 + Int(Self.u16(header, 26)) + Int(Self.u16(header, 28))
        guard offset + entry.compressedSize <= data.count else { throw Failure.corrupt(name) }
        let body = data[(data.startIndex + offset)..<(data.startIndex + offset + entry.compressedSize)]
        switch entry.method {
        case 0: return Data(body)
        case 8: return try Self.inflateRaw(Data(body), size: entry.size)
        default: throw Failure.unsupported("compression method \(entry.method)")
        }
    }

    /// Raw deflate (no zlib header), as ZIP stores it.
    static func inflateRaw(_ input: Data, size: Int) throws -> Data {
        var output = [UInt8](repeating: 0, count: max(size, 1))
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw Failure.corrupt("inflate")
        }
        defer { inflateEnd(&stream) }
        var bytes = [UInt8](input)
        let status: Int32 = bytes.withUnsafeMutableBufferPointer { inBuffer in
            output.withUnsafeMutableBufferPointer { outBuffer in
                stream.next_in = inBuffer.baseAddress
                stream.avail_in = uInt(inBuffer.count)
                stream.next_out = outBuffer.baseAddress
                stream.avail_out = uInt(outBuffer.count)
                return inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END || (status == Z_BUF_ERROR && size == 0) else { throw Failure.corrupt("deflate data") }
        return Data(output[0..<Int(stream.total_out)])
    }

    private static func u16(_ bytes: [UInt8], _ at: Int) -> UInt16 {
        UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
    }

    private static func u32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
    }
}
