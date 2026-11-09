import Foundation
#if canImport(zlib)
import zlib
#else
import CZlib
#endif

/// Test-only ZIP writer: each file stored or deflated (raw deflate, as ZIP keeps it), so the
/// Word reader's tests can build a .docx from strings without a real Office file.
enum TestZipWriter {
    static func make(_ files: [(name: String, data: Data)], deflated: Bool = true) -> Data {
        var out = Data()
        var central = Data()
        for file in files {
            let raw = [UInt8](file.data)
            let body = deflated ? deflateRaw(raw) : raw
            let crc = raw.isEmpty ? 0 : UInt32(raw.withUnsafeBufferPointer { crc32(0, $0.baseAddress, uInt($0.count)) })
            let name = [UInt8](file.name.utf8)
            let offset = UInt32(out.count)
            let method: UInt16 = deflated ? 8 : 0
            out.le32(0x0403_4B50); out.le16(20); out.le16(0); out.le16(method); out.le16(0); out.le16(0)
            out.le32(crc); out.le32(UInt32(body.count)); out.le32(UInt32(raw.count))
            out.le16(UInt16(name.count)); out.le16(0)
            out.append(contentsOf: name); out.append(contentsOf: body)
            central.le32(0x0201_4B50); central.le16(20); central.le16(20); central.le16(0); central.le16(method)
            central.le16(0); central.le16(0); central.le32(crc); central.le32(UInt32(body.count)); central.le32(UInt32(raw.count))
            central.le16(UInt16(name.count)); central.le16(0); central.le16(0); central.le16(0); central.le16(0)
            central.le32(0); central.le32(offset)
            central.append(contentsOf: name)
        }
        let start = UInt32(out.count)
        out.append(central)
        out.le32(0x0605_4B50); out.le16(0); out.le16(0)
        out.le16(UInt16(files.count)); out.le16(UInt16(files.count))
        out.le32(UInt32(central.count)); out.le32(start); out.le16(0)
        return out
    }

    private static func deflateRaw(_ input: [UInt8]) -> [UInt8] {
        var stream = z_stream()
        _ = deflateInit2_(&stream, Z_BEST_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY,
                          ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        defer { deflateEnd(&stream) }
        var output = [UInt8](repeating: 0, count: Int(deflateBound(&stream, uLong(input.count))) + 16)
        var source = input
        source.withUnsafeMutableBufferPointer { inBuffer in
            output.withUnsafeMutableBufferPointer { outBuffer in
                stream.next_in = inBuffer.baseAddress
                stream.avail_in = uInt(inBuffer.count)
                stream.next_out = outBuffer.baseAddress
                stream.avail_out = uInt(outBuffer.count)
                _ = deflate(&stream, Z_FINISH)
            }
        }
        return Array(output[0..<Int(stream.total_out)])
    }
}

private extension Data {
    mutating func le16(_ value: UInt16) { append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)]) }
    mutating func le32(_ value: UInt32) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)])
    }
}
