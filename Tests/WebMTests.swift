import XCTest
@testable import Droptimize

// Portable: also run on Linux by scripts/check-linux.sh. Files are checked with `TestWebM`, a reader
// written separately from the spec, and, where FFmpeg is installed, decoded by FFmpeg as players would.
final class WebMTests: XCTestCase {
    private enum Codec { case vp9, av1 }

    // MARK: EBML

    func testEBMLEncoding() {
        XCTAssertEqual(EBML.size(0), [0x80])
        XCTAssertEqual(EBML.size(126), [0xFE])
        XCTAssertEqual(EBML.size(127), [0x40, 0x7F], "all ones in one byte means unknown, so 127 takes two")
        XCTAssertEqual(EBML.size(16_382), [0x7F, 0xFE])
        XCTAssertEqual(EBML.size(5, bytes: 8), [0x01, 0, 0, 0, 0, 0, 0, 5])
        XCTAssertEqual(EBML.id(0x1A45_DFA3), [0x1A, 0x45, 0xDF, 0xA3])
        XCTAssertEqual(EBML.id(0xA3), [0xA3])
        XCTAssertEqual(EBML.uint(0xD7, 0), [0xD7, 0x81, 0x00])
        XCTAssertEqual(EBML.uint(0x2AD7B1, 1_000_000), [0x2A, 0xD7, 0xB1, 0x83, 0x0F, 0x42, 0x40])
        XCTAssertEqual(EBML.string(0x86, "V_VP9"), [0x86, 0x85] + Array("V_VP9".utf8))
        XCTAssertEqual(EBML.void(2), [0xEC, 0x80])
        XCTAssertEqual(EBML.void(5), [0xEC, 0x83, 0, 0, 0])
    }

    // MARK: AV1 bitstream

    func testAV1TemporalDelimitersAreDropped() {
        let delimiter: [UInt8] = [0x12, 0x00]                         // type 2, has size, empty
        let frame: [UInt8] = [0x32, 0x03, 0xAA, 0xBB, 0xCC]            // type 6 (frame), 3 bytes
        XCTAssertEqual(AV1Bitstream.withoutTemporalDelimiters(delimiter + frame), frame)
        XCTAssertEqual(AV1Bitstream.withoutTemporalDelimiters(frame), frame)
        XCTAssertEqual(AV1Bitstream.obus(delimiter + frame)?.map(\.type), [2, 6])
        XCTAssertNil(AV1Bitstream.obus([0x32, 0x09, 0x00]), "a size past the end")
    }

    func testAV1ConfigurationRecord() {
        // A sequence header payload: profile 0, not still, not reduced, no timing info, no display
        // delay, one operating point (idc 0), level 8 (4.0), tier 1, then the rest.
        // Bits: 000 0 0 0 0 00000 000000000000 01000 1 …
        let payload: [UInt8] = [0b0000_0000, 0b0000_0000, 0b0000_0000, 0b0100_0100, 0b0000_0000]
        let obu: [UInt8] = [0x0A, UInt8(payload.count)] + payload        // type 1, has size
        XCTAssertTrue(AV1Bitstream.profileLevelTier(payload)! == (0, 8, 1))
        let record = AV1Bitstream.configurationRecord(sequenceHeader: obu)
        XCTAssertEqual(Array(record.prefix(4)), [0x81, 0 << 5 | 8, 1 << 7 | 0b0000_1100, 0])
        XCTAssertEqual(Array(record.dropFirst(4)), obu)
    }

    // MARK: Files

    func testVP9WithOpus() throws {
        let file = try encode(.vp9, audioChannels: 2)
        try checkStructure(file, codecID: "V_VP9", audio: true)
        try checkWithFFmpeg(file, codec: "vp9", audioChannels: 2)
    }

    func testAV1WithOpus() throws {
        let file = try encode(.av1, audioChannels: 1)
        let webm = try checkStructure(file, codecID: "V_AV1", audio: true)
        XCTAssertEqual(webm.tracks.first?.codecPrivate?.first, 0x81, "av1C")
        try checkWithFFmpeg(file, codec: "av1", audioChannels: 1)

        // libaom's own decoder sees the same pictures (this check needs no FFmpeg).
        let pictures = try TestAV1Decoder.decode(webm.blocks.filter { $0.track == 1 }.map(\.data))
        XCTAssertEqual(pictures.count, 60)
        for index in [0, 45] {
            let (luma, chroma) = Self.frame(index, width: width, height: height)
            let picture = pictures[index]
            XCTAssertGreaterThan(Self.psnr(picture.y, luma), 30, "luma, frame \(index)")
            XCTAssertGreaterThan(Self.psnr(picture.cb, stride(from: 0, to: chroma.count, by: 2).map { chroma[$0] }), 30)
            XCTAssertGreaterThan(Self.psnr(picture.cr, stride(from: 1, to: chroma.count, by: 2).map { chroma[$0] }), 30)
        }
    }

    func testVideoOnly() throws {
        let file = try encode(.vp9, audioChannels: nil)
        try checkStructure(file, codecID: "V_VP9", audio: false)
        try checkWithFFmpeg(file, codec: "vp9", audioChannels: nil)
    }

    func testCompressToASizeFollowsTheBitrate() throws {
        // Grainy frames, which would take far more. Two seconds with two keyframes overshoot (one-pass
        // rate control settles over longer clips), but the bitrate asked for decides the size.
        for codec in [Codec.vp9, .av1] {
            let low = try encode(codec, audioChannels: nil, bitrate: 200_000, quality: nil, grain: true)
            let high = try encode(codec, audioChannels: nil, bitrate: 1_000_000, quality: nil, grain: true)
            let lowRate = Double(try Data(contentsOf: low).count * 8) / seconds
            let highRate = Double(try Data(contentsOf: high).count * 8) / seconds
            XCTAssertLessThan(lowRate, 200_000 * 3, "\(codec)")
            XCTAssertGreaterThan(highRate, lowRate * 1.8, "\(codec)")
        }
    }

    func testOpusPadsTheEndAndCountsFromZero() throws {
        let encoder = try OpusAudioEncoder(channels: 2, bitrate: 96_000)
        XCTAssertGreaterThan(encoder.preSkip, 0)
        XCTAssertEqual(encoder.codecPrivate.count, 19)
        XCTAssertEqual(Array(encoder.codecPrivate.prefix(8)), Array("OpusHead".utf8))
        var packets = try encoder.encode([Float](repeating: 0, count: 1500 * 2))
        packets += try encoder.finish()
        // 1500 samples + the pre-skip, in whole 960-sample packets.
        XCTAssertEqual(packets.count, (1500 + encoder.preSkip + 959) / 960)
        XCTAssertEqual(packets.map(\.milliseconds), (0..<Int64(packets.count)).map { $0 * 20 })
    }

    // MARK: Helpers

    private let width = 320, height = 240, fps = 30.0, seconds = 2.0

    /// Two seconds of a moving gradient with different patterns in Cb and Cr (so swapped planes
    /// show), and a 440 Hz tone.
    private func encode(_ codec: Codec, audioChannels: Int?, bitrate: Int = 800_000, quality: Int? = 32,
                        grain: Bool = false) throws -> URL {
        let settings = WebMVideoSettings(width: width, height: height, fps: fps, bitrate: bitrate, quality: quality,
                                         keyframeInterval: 30, speed: codec == .vp9 ? 8 : 9, threads: 4)
        let video: WebMVideoEncoder = codec == .vp9 ? try VP9Encoder(settings) : try AV1Encoder(settings)
        let audio = try audioChannels.map { try OpusAudioEncoder(channels: $0, bitrate: 64_000 * $0) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("webm-\(UUID().uuidString).webm")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let writer = try WebMWriter(
            url: url,
            video: .init(codecID: video.codecID, width: width, height: height, codecPrivate: video.codecPrivate),
            audio: audio.map { .init(codecID: "A_OPUS", sampleRate: 48_000, channels: $0.channels,
                                     codecPrivate: $0.codecPrivate, codecDelayNanoseconds: $0.codecDelayNanoseconds,
                                     seekPreRollNanoseconds: 80_000_000) })

        let frames = Int(seconds * fps)
        let samplesPerFrame = 48_000 / Int(fps)
        var seed: UInt64 = 1
        func noise() -> Int {                                              // ±12, fast and repeatable
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(seed >> 59) * 25 / 31 - 12
        }
        for index in 0..<frames {
            var (luma, chroma) = Self.frame(index, width: width, height: height)
            if grain { for i in luma.indices { luma[i] = UInt8(clamping: Int(luma[i]) + noise()) } }
            let packets = try luma.withUnsafeBufferPointer { y in
                try chroma.withUnsafeBufferPointer { uv in
                    try video.encode(NV12Frame(luma: y.baseAddress!, lumaStride: width, chroma: uv.baseAddress!,
                                               chromaStride: width), seconds: Double(index) / fps)
                }
            }
            for packet in packets { try writer.add(packet, to: .video) }
            if let audio {
                let start = index * samplesPerFrame
                let samples = (start..<(start + samplesPerFrame)).flatMap { sample in
                    [Float](repeating: Self.tone(sample), count: audio.channels)
                }
                for packet in try audio.encode(samples) { try writer.add(packet, to: .audio) }
            }
        }
        for packet in try video.finish() { try writer.add(packet, to: .video) }
        try writer.endTrack(.video)
        if let audio { for packet in try audio.finish() { try writer.add(packet, to: .audio) } }
        try writer.finish()
        return url
    }

    private static func tone(_ sample: Int) -> Float { 0.5 * Float(sin(2 * Double.pi * 440 * Double(sample) / 48_000)) }

    private static func frame(_ index: Int, width: Int, height: Int) -> (luma: [UInt8], chroma: [UInt8]) {
        var luma = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width { luma[y * width + x] = UInt8(16 + (x + y + index * 4) % 220) }
        }
        var chroma = [UInt8](repeating: 128, count: width * height / 2)
        for y in 0..<(height / 2) {
            for x in 0..<(width / 2) {
                chroma[y * width + 2 * x] = UInt8(64 + x % 128)          // Cb: across
                chroma[y * width + 2 * x + 1] = UInt8(64 + y % 128)      // Cr: down
            }
        }
        return (luma, chroma)
    }

    @discardableResult
    private func checkStructure(_ url: URL, codecID: String, audio: Bool) throws -> TestWebM {
        let webm = try TestWebM([UInt8](Data(contentsOf: url)))
        XCTAssertEqual(webm.docType, "webm")
        XCTAssertEqual(webm.timecodeScale, 1_000_000)
        XCTAssertEqual(webm.duration ?? 0, seconds * 1000, accuracy: 60)

        // The SeekHead points at what's really there.
        let ids = Dictionary(webm.children.map { ($0.position, $0.id) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(Set(webm.seeks.keys), [0x1549_A966, 0x1654_AE6B, 0x1C53_BB6B])
        for (id, position) in webm.seeks { XCTAssertEqual(ids[position], id, "SeekHead entry \(String(id, radix: 16))") }

        let video = try XCTUnwrap(webm.tracks.first)
        XCTAssertEqual(video.codecID, codecID)
        XCTAssertEqual(video.type, 1)
        XCTAssertEqual(video.width, width)
        XCTAssertEqual(video.height, height)
        XCTAssertEqual(video.colour, [0x55B1: 1, 0x55B9: 1, 0x55BA: 1, 0x55BB: 1], "BT.709, limited range")
        XCTAssertEqual(webm.tracks.count, audio ? 2 : 1)
        if audio {
            let sound = webm.tracks[1]
            XCTAssertEqual(sound.codecID, "A_OPUS")
            XCTAssertEqual(sound.sampleRate, 48_000)
            XCTAssertGreaterThan(sound.codecDelay ?? 0, 0)
        }

        let videoBlocks = webm.blocks.filter { $0.track == 1 }
        XCTAssertEqual(videoBlocks.count, Int(seconds * fps), "one block per frame")
        XCTAssertEqual(videoBlocks.first?.isKey, true)
        XCTAssertEqual(videoBlocks.filter(\.isKey).count, 2, "a keyframe every 30 frames")
        XCTAssertEqual(webm.blocks.map(\.time), webm.blocks.map(\.time).sorted(), "in time order across tracks")
        if audio {
            let audioBlocks = webm.blocks.filter { $0.track == 2 }
            XCTAssertEqual(audioBlocks.first?.time, 0)
            XCTAssertGreaterThanOrEqual(audioBlocks.count, Int(seconds * 50))
        }

        // Every cue points at a cluster that starts with a video keyframe at the cue's time.
        XCTAssertEqual(webm.cues.count, 2)
        for cue in webm.cues {
            XCTAssertEqual(cue.track, 1)
            let cluster = try XCTUnwrap(webm.clusters.first { $0.position == cue.position }, "cue at \(cue.time)")
            XCTAssertEqual(cluster.time, cue.time)
            XCTAssertTrue(videoBlocks.contains { $0.time == cue.time && $0.isKey })
        }
        return webm
    }

    // MARK: FFmpeg

    private func checkWithFFmpeg(_ url: URL, codec: String, audioChannels: Int?) throws {
        guard let ffmpeg = Self.tool("ffmpeg"), let ffprobe = Self.tool("ffprobe") else {
            print("FFmpeg isn't installed: skipping the decode check")
            return
        }
        // Decodes cleanly from start to end.
        let decode = try Self.run(ffmpeg, ["-v", "error", "-i", url.path, "-f", "null", "-"])
        XCTAssertEqual(decode.status, 0)
        XCTAssertEqual(String(decoding: decode.error, as: UTF8.self), "", "FFmpeg reported errors")

        let probe = try Self.run(ffprobe, ["-v", "error", "-count_frames", "-show_entries",
                                           "stream=codec_name,width,height,channels,sample_rate,nb_read_frames",
                                           "-of", "csv=p=0", url.path])
        let lines = String(decoding: probe.output, as: UTF8.self).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first?.split(separator: ",").map(String.init), [codec, "\(width)", "\(height)", "60"])
        if let audioChannels {
            XCTAssertEqual(lines.dropFirst().first?.split(separator: ",").first, "opus")
            XCTAssertTrue(lines.dropFirst().first?.contains(",48000,\(audioChannels)") ?? false, lines.joined(separator: " | "))
        }

        // The picture is the one that went in: luma and both chroma planes, the right way round.
        for index in [0, 45] {
            let raw = try Self.run(ffmpeg, ["-v", "error", "-i", url.path, "-vf", "select=eq(n\\,\(index))", "-frames:v", "1",
                                            "-f", "rawvideo", "-pix_fmt", "nv12", "-"]).output
            let (luma, chroma) = Self.frame(index, width: width, height: height)
            XCTAssertEqual(raw.count, luma.count + chroma.count)
            guard raw.count == luma.count + chroma.count else { continue }
            XCTAssertGreaterThan(Self.psnr(Array(raw.prefix(luma.count)), luma), 30, "luma, frame \(index)")
            let decoded = Array(raw.dropFirst(luma.count))
            let cb = stride(from: 0, to: chroma.count, by: 2), cr = stride(from: 1, to: chroma.count, by: 2)
            XCTAssertGreaterThan(Self.psnr(cb.map { decoded[$0] }, cb.map { chroma[$0] }), 30, "Cb, frame \(index)")
            XCTAssertGreaterThan(Self.psnr(cr.map { decoded[$0] }, cr.map { chroma[$0] }), 30, "Cr, frame \(index)")
        }

        // The sound starts on time (the pre-skip is dropped) and lasts as long as what went in.
        if audioChannels != nil {
            let pcm = try Self.run(ffmpeg, ["-v", "error", "-i", url.path, "-map", "0:a", "-ac", "1", "-f", "f32le", "-"]).output
            let samples = pcm.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            XCTAssertEqual(Double(samples.count), seconds * 48_000, accuracy: 960)
            let window = 4_800..<9_600
            let tone = window.map(Self.tone)
            func error(shift: Int) -> Float { zip(window, tone).map { pow(samples[$0 + shift] - $1, 2) }.reduce(0, +) }
            let best = (-48...48).min { error(shift: $0) < error(shift: $1) }
            XCTAssertEqual(best ?? 99, 0, accuracy: 2, "audio offset in samples")
        }
    }

    private static func psnr(_ a: [UInt8], _ b: [UInt8]) -> Double {
        let mse = zip(a, b).map { pow(Double($0) - Double($1), 2) }.reduce(0, +) / Double(max(a.count, 1))
        return mse == 0 ? 99 : 10 * log10(255 * 255 / mse)
    }

    private static func tool(_ name: String) -> String? {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        return paths.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws -> (status: Int32, output: Data, error: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe(), error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        // Read before waiting, so a full pipe can't stall the tool.
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, out, err)
    }
}
