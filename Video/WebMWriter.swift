import Foundation

/// One compressed video frame or audio packet, ready for a container.
struct EncodedPacket: Equatable {
    var data: [UInt8]
    /// When it plays, in milliseconds from the start.
    var milliseconds: Int64
    /// How long it plays, in milliseconds (for the file's duration).
    var durationMilliseconds: Int64
    /// A video frame that decodes on its own (seeking lands on these). Every audio packet is one.
    var isKey: Bool
}

/// Writes a WebM file (the web's subset of Matroska) with one video track and an optional audio
/// track, so WebM needs no muxing library (CORE.md §7.4). Packets go straight to disk a cluster
/// at a time. Clusters start at video keyframes and are indexed in Cues so players can seek.
/// The layout follows the WebM guidelines: header, then SeekHead, Info and Tracks at the front,
/// Clusters, and the Cues at the end (the SeekHead says where).
final class WebMWriter {
    struct VideoTrack {
        /// "V_VP9" or "V_AV1".
        var codecID: String
        var width: Int
        var height: Int
        /// What the decoder needs before the first frame (AV1's av1C); none for VP9.
        var codecPrivate: [UInt8]?
    }

    struct AudioTrack {
        /// "A_OPUS".
        var codecID: String
        var sampleRate: Double
        var channels: Int
        var codecPrivate: [UInt8]
        /// Samples the decoder drops at the start (Opus's pre-skip), in nanoseconds.
        var codecDelayNanoseconds: UInt64
        /// How much audio before a seek point must be decoded to sound right (80 ms for Opus).
        var seekPreRollNanoseconds: UInt64
    }

    enum Track: UInt8 {
        case video = 1, audio = 2
    }

    /// Clusters store each block's time as a signed 16-bit offset from their own.
    static let maxClusterSpan: Int64 = 32_767

    private let handle: FileHandle
    private var buffer: [UInt8] = []
    /// Bytes written to the file so far.
    private var fileOffset: UInt64 = 0
    /// Where the Segment's content starts: every position inside the file is counted from here.
    private var segmentStart: UInt64 = 0
    private var segmentSizeOffset: UInt64 = 0
    private var seekHeadOffset: UInt64 = 0
    private var durationOffset: UInt64 = 0
    private var infoPosition: UInt64 = 0
    private var tracksPosition: UInt64 = 0

    private var queues: [Track: [EncodedPacket]] = [:]
    private var openTracks: Set<Track>
    private var cluster: (time: Int64, body: [UInt8])?
    private var cues: [(time: Int64, position: UInt64)] = []
    private var lastWritten: Int64 = .min
    private var end: Int64 = 0
    private var finished = false

    /// Space kept after the Segment header for the SeekHead, which is only known at the end.
    private static let seekHeadSpace = 96

    init(url: URL, video: VideoTrack, audio: AudioTrack?) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        handle = try FileHandle(forWritingTo: url)
        openTracks = audio == nil ? [.video] : [.video, .audio]

        append(EBML.element(0x1A45_DFA3,
                            EBML.uint(0x4286, 1) + EBML.uint(0x42F7, 1) + EBML.uint(0x42F2, 4) + EBML.uint(0x42F3, 8)
                            + EBML.string(0x4282, "webm") + EBML.uint(0x4287, 4) + EBML.uint(0x4285, 2)))
        append(EBML.id(0x1853_8067))
        segmentSizeOffset = position
        append(EBML.unknownSize)
        segmentStart = position

        seekHeadOffset = position
        append(EBML.void(Self.seekHeadSpace))

        infoPosition = position - segmentStart
        let scale = EBML.uint(0x2AD7B1, 1_000_000)                    // timestamps in milliseconds
        let duration = EBML.id(0x4489) + EBML.size(8) + [UInt8](repeating: 0, count: 8)
        let apps = EBML.string(0x4D80, "Droptimize") + EBML.string(0x5741, "Droptimize")
        let info = scale + duration + apps
        let infoHeader = EBML.id(0x1549_A966) + EBML.size(UInt64(info.count))
        durationOffset = position + UInt64(infoHeader.count + scale.count + 3)
        append(infoHeader + info)

        tracksPosition = position - segmentStart
        var entries = Self.entry(video)
        if let audio { entries += Self.entry(audio) }
        append(EBML.element(0x1654_AE6B, entries))
        try flush()
    }

    deinit {
        try? handle.close()
    }

    /// Queues a packet; it's written once every open track has caught up to its time, so the file
    /// stays in time order across tracks. Each track's packets must come in time order.
    func add(_ packet: EncodedPacket, to track: Track) throws {
        precondition(openTracks.contains(track), "a packet for a track that ended")
        queues[track, default: []].append(packet)
        try writeReady(all: false)
    }

    /// Says a track has no more packets, so the others needn't wait for it.
    func endTrack(_ track: Track) throws {
        openTracks.remove(track)
        try writeReady(all: false)
    }

    /// Writes what's left, the index and the header fields only known now, and closes the file.
    func finish() throws {
        guard !finished else { return }
        finished = true
        openTracks.removeAll()
        try writeReady(all: true)
        try closeCluster()

        var cuesPosition: UInt64?
        if !cues.isEmpty {
            cuesPosition = position - segmentStart
            let points = cues.map { cue in
                EBML.element(0xBB, EBML.uint(0xB3, UInt64(cue.time))
                             + EBML.element(0xB7, EBML.uint(0xF7, UInt64(Track.video.rawValue)) + EBML.uint(0xF1, cue.position)))
            }
            append(EBML.element(0x1C53_BB6B, points.flatMap { $0 }))
        }
        try flush()
        let segmentSize = position - segmentStart

        var seeks = Self.seek(0x1549_A966, infoPosition) + Self.seek(0x1654_AE6B, tracksPosition)
        if let cuesPosition { seeks += Self.seek(0x1C53_BB6B, cuesPosition) }
        let seekHead = EBML.element(0x114D_9B74, seeks)
        try patch(at: seekHeadOffset, seekHead + EBML.void(Self.seekHeadSpace - seekHead.count))
        try patch(at: durationOffset, EBML.bigEndian(Double(end).bitPattern, bytes: 8))
        try patch(at: segmentSizeOffset, EBML.size(segmentSize, bytes: 8))
        try handle.close()
    }

    // MARK: Writing

    private var position: UInt64 { fileOffset + UInt64(buffer.count) }

    private func append(_ bytes: [UInt8]) { buffer += bytes }

    private func flush() throws {
        guard !buffer.isEmpty else { return }
        try handle.write(contentsOf: Data(buffer))
        fileOffset += UInt64(buffer.count)
        buffer.removeAll(keepingCapacity: true)
    }

    private func patch(at offset: UInt64, _ bytes: [UInt8]) throws {
        try handle.seek(toOffset: offset)
        try handle.write(contentsOf: Data(bytes))
    }

    /// Writes the earliest queued packet while no open track could still bring an earlier one.
    private func writeReady(all: Bool) throws {
        while true {
            if !all, openTracks.contains(where: { queues[$0]?.isEmpty ?? true }) { return }
            // The earliest front packet; video first on a tie, so a cluster starts with its keyframe.
            let next = [Track.video, .audio]
                .compactMap { track in queues[track]?.first.map { (track, $0) } }
                .min { $0.1.milliseconds < $1.1.milliseconds }
            guard let (track, packet) = next else { return }
            queues[track]?.removeFirst()
            try write(packet, track: track)
        }
    }

    private func write(_ packet: EncodedPacket, track: Track) throws {
        // Times never go backwards in the file, even if an encoder rounds two packets together.
        let time = max(packet.milliseconds, lastWritten)
        lastWritten = time
        end = max(end, time + max(packet.durationMilliseconds, 0))

        let keyframe = track == .video && packet.isKey
        if let current = cluster, keyframe || time - current.time > Self.maxClusterSpan {
            try closeCluster()
        }
        if cluster == nil {
            if keyframe { cues.append((time, position - segmentStart)) }
            cluster = (time, EBML.uint(0xE7, UInt64(max(time, 0))))
        }
        guard let start = cluster?.time else { return }
        let offset = Int16(clamping: time - start)
        var block: [UInt8] = [0x80 | track.rawValue]                        // track number, as a 1-byte size
        block += EBML.bigEndian(UInt64(UInt16(bitPattern: offset)), bytes: 2)
        block.append(packet.isKey || track == .audio ? 0x80 : 0x00)
        cluster?.body += EBML.id(0xA3) + EBML.size(UInt64(block.count + packet.data.count)) + block + packet.data
    }

    private func closeCluster() throws {
        guard let current = cluster else { return }
        cluster = nil
        append(EBML.element(0x1F43_B675, current.body))
        try flush()
    }

    // MARK: Elements

    private static func entry(_ video: VideoTrack) -> [UInt8] {
        // BT.709 colors, limited range: what the encoders are told and what they're given.
        let colour = EBML.element(0x55B0, EBML.uint(0x55B1, 1) + EBML.uint(0x55B9, 1) + EBML.uint(0x55BA, 1)
                                  + EBML.uint(0x55BB, 1))
        var body = EBML.uint(0xD7, UInt64(Track.video.rawValue)) + EBML.uint(0x73C5, UInt64(Track.video.rawValue))
            + EBML.uint(0x83, 1) + EBML.uint(0x9C, 0) + EBML.string(0x86, video.codecID)
        if let codecPrivate = video.codecPrivate { body += EBML.element(0x63A2, codecPrivate) }
        body += EBML.element(0xE0, EBML.uint(0xB0, UInt64(video.width)) + EBML.uint(0xBA, UInt64(video.height)) + colour)
        return EBML.element(0xAE, body)
    }

    private static func entry(_ audio: AudioTrack) -> [UInt8] {
        let body = EBML.uint(0xD7, UInt64(Track.audio.rawValue)) + EBML.uint(0x73C5, UInt64(Track.audio.rawValue))
            + EBML.uint(0x83, 2) + EBML.uint(0x9C, 0) + EBML.string(0x86, audio.codecID)
            + EBML.element(0x63A2, audio.codecPrivate)
            + EBML.uint(0x56AA, audio.codecDelayNanoseconds) + EBML.uint(0x56BB, audio.seekPreRollNanoseconds)
            + EBML.element(0xE1, EBML.float(0xB5, audio.sampleRate) + EBML.uint(0x9F, UInt64(audio.channels)))
        return EBML.element(0xAE, body)
    }

    /// A SeekHead entry. Positions take 8 bytes, so the SeekHead's size never depends on them.
    private static func seek(_ id: UInt32, _ position: UInt64) -> [UInt8] {
        EBML.element(0x4DBB, EBML.element(0x53AB, EBML.id(id))
                     + EBML.id(0x53AC) + EBML.size(8) + EBML.bigEndian(position, bytes: 8))
    }
}

/// The byte encoding Matroska is built on (RFC 8794): elements are an ID, a size, then content.
enum EBML {
    /// The "size unknown" marker, as 8 bytes so it can be overwritten with the real size.
    static let unknownSize: [UInt8] = [0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]

    /// An element ID: already self-delimiting, so it's written as is, without its leading zero bytes.
    static func id(_ id: UInt32) -> [UInt8] {
        let bytes = id > 0xFF_FFFF ? 4 : id > 0xFFFF ? 3 : id > 0xFF ? 2 : 1
        return bigEndian(UInt64(id), bytes: bytes)
    }

    /// A size as a variable-length integer: the first byte's leading zeros say how many bytes follow.
    /// The shortest form unless `bytes` is given. All ones means "unknown", so it's never used.
    static func size(_ value: UInt64, bytes: Int? = nil) -> [UInt8] {
        let length = bytes ?? (1...8).first { value < (UInt64(1) << (7 * UInt64($0))) - 1 } ?? 8
        precondition(length == 8 || value < (UInt64(1) << (7 * UInt64(length))) - 1, "size doesn't fit")
        var encoded = bigEndian(value, bytes: length)
        encoded[0] |= UInt8(0x80 >> (length - 1))
        return encoded
    }

    static func element(_ id: UInt32, _ content: [UInt8]) -> [UInt8] {
        self.id(id) + size(UInt64(content.count)) + content
    }

    /// An unsigned integer in as few bytes as it needs (at least one).
    static func uint(_ id: UInt32, _ value: UInt64) -> [UInt8] {
        let bytes = max(1, (64 - value.leadingZeroBitCount + 7) / 8)
        return element(id, bigEndian(value, bytes: bytes))
    }

    static func float(_ id: UInt32, _ value: Double) -> [UInt8] {
        element(id, bigEndian(value.bitPattern, bytes: 8))
    }

    static func string(_ id: UInt32, _ value: String) -> [UInt8] {
        element(id, Array(value.utf8))
    }

    /// Padding of exactly `total` bytes (at least 2) that readers skip.
    static func void(_ total: Int) -> [UInt8] {
        precondition(total >= 2 && total <= 128, "void padding out of range")
        return [0xEC] + size(UInt64(total - 2), bytes: 1) + [UInt8](repeating: 0, count: total - 2)
    }

    static func bigEndian(_ value: UInt64, bytes: Int) -> [UInt8] {
        (0..<bytes).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64(bytes - 1 - $0))) }
    }
}
