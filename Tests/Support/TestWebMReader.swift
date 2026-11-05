import Foundation

/// A test-only WebM reader, written from the Matroska spec (RFC 9559) independently of `WebMWriter`,
/// so the tests check the file's structure rather than the writer agreeing with itself.
struct TestWebM {
    struct Block: Equatable {
        var track: Int
        /// Absolute time in milliseconds.
        var time: Int64
        var isKey: Bool
        var data: [UInt8]
    }

    struct Track: Equatable {
        var number: Int
        var type: Int
        var codecID: String
        var codecPrivate: [UInt8]?
        var width: Int?
        var height: Int?
        var channels: Int?
        var sampleRate: Double?
        var codecDelay: UInt64?
        var colour: [UInt32: UInt64] = [:]
    }

    enum Failure: Error { case malformed(String) }

    var docType = ""
    var duration: Double?
    var timecodeScale: UInt64?
    var tracks: [Track] = []
    var blocks: [Block] = []
    /// Cluster times in milliseconds and where each cluster starts (counted from the Segment's content).
    var clusters: [(time: Int64, position: UInt64)] = []
    var cues: [(time: Int64, track: Int, position: UInt64)] = []
    /// SeekHead: element ID → position.
    var seeks: [UInt32: UInt64] = [:]
    /// Each top-level element in the Segment: ID → position.
    var children: [(id: UInt32, position: UInt64)] = []

    init(_ bytes: [UInt8]) throws {
        var cursor = 0
        let header = try Self.element(bytes, &cursor)
        guard header.id == 0x1A45_DFA3 else { throw Failure.malformed("no EBML header") }
        var inner = header.content.lowerBound
        while inner < header.content.upperBound {
            let child = try Self.element(bytes, &inner)
            if child.id == 0x4282 { docType = String(decoding: bytes[child.content], as: UTF8.self) }
        }
        cursor = header.content.upperBound
        let segment = try Self.element(bytes, &cursor)
        guard segment.id == 0x1853_8067 else { throw Failure.malformed("no Segment") }
        guard segment.content.upperBound == bytes.count else { throw Failure.malformed("the Segment's size isn't the file's") }
        let start = segment.content.lowerBound

        var index = start
        while index < segment.content.upperBound {
            let child = try Self.element(bytes, &index)
            let position = UInt64(child.start - start)
            children.append((child.id, position))
            switch child.id {
            case 0x114D_9B74: try readSeekHead(bytes, child.content)
            case 0x1549_A966: try readInfo(bytes, child.content)
            case 0x1654_AE6B: try readTracks(bytes, child.content)
            case 0x1F43_B675: try readCluster(bytes, child.content, position: position)
            case 0x1C53_BB6B: try readCues(bytes, child.content)
            default: break
            }
        }
    }

    private mutating func readSeekHead(_ bytes: [UInt8], _ range: Range<Int>) throws {
        for seek in try Self.children(bytes, range) where seek.id == 0x4DBB {
            var id: UInt32?, position: UInt64?
            for field in try Self.children(bytes, seek.content) {
                if field.id == 0x53AB { id = UInt32(Self.uint(bytes[field.content])) }
                if field.id == 0x53AC { position = Self.uint(bytes[field.content]) }
            }
            if let id, let position { seeks[id] = position }
        }
    }

    private mutating func readInfo(_ bytes: [UInt8], _ range: Range<Int>) throws {
        for field in try Self.children(bytes, range) {
            if field.id == 0x2AD7B1 { timecodeScale = Self.uint(bytes[field.content]) }
            if field.id == 0x4489 { duration = Self.float(bytes[field.content]) }
        }
    }

    private mutating func readTracks(_ bytes: [UInt8], _ range: Range<Int>) throws {
        for entry in try Self.children(bytes, range) where entry.id == 0xAE {
            var track = Track(number: 0, type: 0, codecID: "")
            for field in try Self.children(bytes, entry.content) {
                switch field.id {
                case 0xD7: track.number = Int(Self.uint(bytes[field.content]))
                case 0x83: track.type = Int(Self.uint(bytes[field.content]))
                case 0x86: track.codecID = String(decoding: bytes[field.content], as: UTF8.self)
                case 0x63A2: track.codecPrivate = Array(bytes[field.content])
                case 0x56AA: track.codecDelay = Self.uint(bytes[field.content])
                case 0xE0:
                    for video in try Self.children(bytes, field.content) {
                        if video.id == 0xB0 { track.width = Int(Self.uint(bytes[video.content])) }
                        if video.id == 0xBA { track.height = Int(Self.uint(bytes[video.content])) }
                        if video.id == 0x55B0 {
                            for colour in try Self.children(bytes, video.content) {
                                track.colour[colour.id] = Self.uint(bytes[colour.content])
                            }
                        }
                    }
                case 0xE1:
                    for audio in try Self.children(bytes, field.content) {
                        if audio.id == 0x9F { track.channels = Int(Self.uint(bytes[audio.content])) }
                        if audio.id == 0xB5 { track.sampleRate = Self.float(bytes[audio.content]) }
                    }
                default: break
                }
            }
            tracks.append(track)
        }
    }

    private mutating func readCluster(_ bytes: [UInt8], _ range: Range<Int>, position: UInt64) throws {
        var time: Int64?
        for field in try Self.children(bytes, range) {
            if field.id == 0xE7 {
                time = Int64(Self.uint(bytes[field.content]))
                clusters.append((time!, position))
            } else if field.id == 0xA3 {
                guard let time else { throw Failure.malformed("a block before its cluster's time") }
                var cursor = field.content.lowerBound
                let track = try Self.vint(bytes, &cursor)
                guard cursor + 3 <= field.content.upperBound else { throw Failure.malformed("short block") }
                let offset = Int16(bitPattern: UInt16(bytes[cursor]) << 8 | UInt16(bytes[cursor + 1]))
                let flags = bytes[cursor + 2]
                guard flags & 0x06 == 0 else { throw Failure.malformed("laced block") }
                blocks.append(Block(track: Int(track), time: time + Int64(offset), isKey: flags & 0x80 != 0,
                                    data: Array(bytes[(cursor + 3)..<field.content.upperBound])))
            }
        }
    }

    private mutating func readCues(_ bytes: [UInt8], _ range: Range<Int>) throws {
        for point in try Self.children(bytes, range) where point.id == 0xBB {
            var time: Int64 = -1, track = 0, position: UInt64 = 0
            for field in try Self.children(bytes, point.content) {
                if field.id == 0xB3 { time = Int64(Self.uint(bytes[field.content])) }
                if field.id == 0xB7 {
                    for spot in try Self.children(bytes, field.content) {
                        if spot.id == 0xF7 { track = Int(Self.uint(bytes[spot.content])) }
                        if spot.id == 0xF1 { position = Self.uint(bytes[spot.content]) }
                    }
                }
            }
            cues.append((time, track, position))
        }
    }

    // MARK: EBML

    struct Element {
        var id: UInt32
        var start: Int
        var content: Range<Int>
    }

    static func children(_ bytes: [UInt8], _ range: Range<Int>) throws -> [Element] {
        var cursor = range.lowerBound
        var result: [Element] = []
        while cursor < range.upperBound {
            let child = try element(bytes, &cursor)
            guard child.content.upperBound <= range.upperBound else { throw Failure.malformed("child overruns parent") }
            result.append(child)
        }
        return result
    }

    static func element(_ bytes: [UInt8], _ cursor: inout Int) throws -> Element {
        let start = cursor
        guard cursor < bytes.count else { throw Failure.malformed("past the end") }
        let first = bytes[cursor]
        guard first != 0 else { throw Failure.malformed("bad ID") }
        let idLength = first.leadingZeroBitCount + 1
        guard idLength <= 4, cursor + idLength <= bytes.count else { throw Failure.malformed("bad ID") }
        let id = bytes[cursor..<(cursor + idLength)].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        cursor += idLength
        let size = try vint(bytes, &cursor)
        guard cursor + Int(size) <= bytes.count else { throw Failure.malformed("element \(String(id, radix: 16)) overruns the file") }
        let content = cursor..<(cursor + Int(size))
        cursor = content.upperBound
        return Element(id: id, start: start, content: content)
    }

    static func vint(_ bytes: [UInt8], _ cursor: inout Int) throws -> UInt64 {
        guard cursor < bytes.count, bytes[cursor] != 0 else { throw Failure.malformed("bad size") }
        let length = bytes[cursor].leadingZeroBitCount + 1
        guard cursor + length <= bytes.count else { throw Failure.malformed("bad size") }
        var value = UInt64(bytes[cursor] & (0xFF >> length))
        for i in 1..<length { value = value << 8 | UInt64(bytes[cursor + i]) }
        cursor += length
        guard value != (UInt64(1) << (7 * UInt64(length))) - 1 else { throw Failure.malformed("unknown size left in the file") }
        return value
    }

    static func uint(_ bytes: ArraySlice<UInt8>) -> UInt64 { bytes.reduce(0) { $0 << 8 | UInt64($1) } }

    static func float(_ bytes: ArraySlice<UInt8>) -> Double {
        bytes.count == 4 ? Double(Float(bitPattern: UInt32(uint(bytes)))) : Double(bitPattern: uint(bytes))
    }
}
