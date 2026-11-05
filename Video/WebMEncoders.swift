import CAom
import COpus
import CVpx
import Foundation

/// A frame for the WebM encoders: 8-bit 4:2:0 with the chroma interleaved (NV12, what Apple's
/// decoders hand out as `420v`), limited range, BT.709. The pointers are only read during `encode`.
struct NV12Frame {
    var luma: UnsafePointer<UInt8>
    var lumaStride: Int
    /// Cb and Cr interleaved, half the width and height.
    var chroma: UnsafePointer<UInt8>
    var chromaStride: Int
}

/// How a WebM video encoder spends bits.
struct WebMVideoSettings: Equatable {
    var width: Int
    var height: Int
    var fps: Double
    /// Bits per second: the most it spends when `quality` is set (constrained quality), otherwise
    /// the average it aims for (Compress to a size).
    var bitrate: Int
    /// Constant quality, 0 (best) to 63; nil aims at `bitrate` instead.
    var quality: Int?
    /// Frames between keyframes at most, so players can seek.
    var keyframeInterval: Int
    /// Encoder speed (libvpx/libaom cpu-used): higher is faster and a little larger.
    var speed: Int
    var threads: Int
}

/// VP9 or AV1, the same way: frames in, packets out (CORE.md §7.4).
protocol WebMVideoEncoder: AnyObject {
    var codecID: String { get }
    /// What the WebM track needs before the first frame, if anything.
    var codecPrivate: [UInt8]? { get }
    /// Encodes a frame shown at `seconds` from the start. Returns the packets ready so far:
    /// encoders look ahead, so packets trail the frames.
    func encode(_ frame: NV12Frame, seconds: Double) throws -> [EncodedPacket]
    /// The packets still inside the encoder.
    func finish() throws -> [EncodedPacket]
}

enum WebMEncoderError: Error, Equatable {
    case couldNotStart(String)
    case failed(String)
}

/// Timestamps go to the encoders in 1/90000 s (the usual video clock) and come out in milliseconds.
private let ticksPerSecond = 90_000

private func ticks(_ seconds: Double) -> Int64 { Int64((seconds * Double(ticksPerSecond)).rounded()) }
private func milliseconds(_ ticks: Int64) -> Int64 { (ticks * 1000 + Int64(ticksPerSecond / 2)) / Int64(ticksPerSecond) }

/// Tiles let the encoder (and decoders) use more cores: as many columns as the width allows, at
/// most 4 (each at least 256 px wide), as a power of two.
private func tileColumnsLog2(width: Int) -> Int32 {
    var log2: Int32 = 0
    while log2 < 2, width >> (log2 + 1) >= 256 { log2 += 1 }
    return log2
}

// MARK: VP9 (libvpx)

final class VP9Encoder: WebMVideoEncoder {
    let codecID = "V_VP9"
    let codecPrivate: [UInt8]? = nil
    private let settings: WebMVideoSettings
    private let context = UnsafeMutablePointer<vpx_codec_ctx_t>.allocate(capacity: 1)
    private let frameTicks: Int64

    init(_ settings: WebMVideoSettings) throws {
        self.settings = settings
        frameTicks = max(1, ticks(1 / max(settings.fps, 1)))
        var config = vpx_codec_enc_cfg_t()
        guard vpx_codec_enc_config_default(vpx_codec_vp9_cx(), &config, 0) == VPX_CODEC_OK else {
            context.deallocate()
            throw WebMEncoderError.couldNotStart("VP9")
        }
        config.g_w = UInt32(settings.width)
        config.g_h = UInt32(settings.height)
        config.g_timebase = vpx_rational(num: 1, den: Int32(ticksPerSecond))
        config.g_threads = UInt32(max(1, settings.threads))
        config.g_pass = VPX_RC_ONE_PASS
        config.g_lag_in_frames = 25                       // look ahead: better keyframes and alt-refs
        config.rc_end_usage = settings.quality == nil ? VPX_VBR : VPX_CQ
        config.rc_target_bitrate = UInt32(max(1, settings.bitrate / 1000))
        config.kf_mode = VPX_KF_AUTO
        config.kf_max_dist = UInt32(max(1, settings.keyframeInterval))
        guard droptimize_vpx_vp9_init(context, &config) == VPX_CODEC_OK else {
            context.deallocate()
            throw WebMEncoderError.couldNotStart("VP9")
        }
        set(VP8E_SET_CPUUSED.rawValue, Int32(settings.speed))
        set(VP9E_SET_ROW_MT.rawValue, 1)
        set(VP9E_SET_TILE_COLUMNS.rawValue, tileColumnsLog2(width: settings.width))
        set(VP9E_SET_FRAME_PARALLEL_DECODING.rawValue, 0)
        set(VP8E_SET_ENABLEAUTOALTREF.rawValue, 1)
        set(VP9E_SET_COLOR_SPACE.rawValue, Int32(VPX_CS_BT_709.rawValue))
        set(VP9E_SET_COLOR_RANGE.rawValue, Int32(VPX_CR_STUDIO_RANGE.rawValue))
        if let quality = settings.quality { set(VP8E_SET_CQ_LEVEL.rawValue, Int32(quality)) }
    }

    deinit {
        vpx_codec_destroy(context)
        context.deallocate()
    }

    private func set(_ control: UInt32, _ value: Int32) {
        _ = droptimize_vpx_control(context, Int32(control), value)
    }

    func encode(_ frame: NV12Frame, seconds: Double) throws -> [EncodedPacket] {
        var image = vpx_image_t()
        let luma = UnsafeMutablePointer(mutating: frame.luma), chroma = UnsafeMutablePointer(mutating: frame.chroma)
        guard vpx_img_wrap(&image, VPX_IMG_FMT_NV12, UInt32(settings.width), UInt32(settings.height), 1, luma) != nil
        else { throw WebMEncoderError.failed("VP9") }
        // libvpx's NV12: V starts one byte after U, with the same stride.
        image.planes = (luma, chroma, chroma + 1, nil)
        image.stride = (Int32(frame.lumaStride), Int32(frame.chromaStride), Int32(frame.chromaStride), 0)
        image.cs = VPX_CS_BT_709
        image.range = VPX_CR_STUDIO_RANGE
        return try run(&image, pts: ticks(seconds))
    }

    func finish() throws -> [EncodedPacket] {
        var packets: [EncodedPacket] = []
        while true {
            let more = try run(nil, pts: -1)
            if more.isEmpty { return packets }
            packets += more
        }
    }

    private func run(_ image: UnsafeMutablePointer<vpx_image_t>?, pts: Int64) throws -> [EncodedPacket] {
        guard vpx_codec_encode(context, image, pts, UInt(frameTicks), 0, UInt(VPX_DL_GOOD_QUALITY)) == VPX_CODEC_OK
        else { throw WebMEncoderError.failed(String(cString: vpx_codec_error(context))) }
        var packets: [EncodedPacket] = []
        var iterator: vpx_codec_iter_t?
        while let packet = vpx_codec_get_cx_data(context, &iterator) {
            guard packet.pointee.kind == VPX_CODEC_CX_FRAME_PKT else { continue }
            let frame = packet.pointee.data.frame
            guard let bytes = frame.buf, frame.sz > 0 else { continue }
            let start = frame.pts
            packets.append(EncodedPacket(
                data: Array(UnsafeRawBufferPointer(start: bytes, count: frame.sz)),
                milliseconds: milliseconds(start),
                durationMilliseconds: milliseconds(start + Int64(frame.duration)) - milliseconds(start),
                isKey: frame.flags & UInt32(VPX_FRAME_IS_KEY) != 0))
        }
        return packets
    }
}

// MARK: AV1 (libaom)

final class AV1Encoder: WebMVideoEncoder {
    let codecID = "V_AV1"
    private(set) var codecPrivate: [UInt8]?
    private let settings: WebMVideoSettings
    private let context = UnsafeMutablePointer<aom_codec_ctx_t>.allocate(capacity: 1)
    private let frameTicks: Int64

    init(_ settings: WebMVideoSettings) throws {
        self.settings = settings
        frameTicks = max(1, ticks(1 / max(settings.fps, 1)))
        var config = aom_codec_enc_cfg_t()
        guard aom_codec_enc_config_default(aom_codec_av1_cx(), &config, UInt32(AOM_USAGE_GOOD_QUALITY)) == AOM_CODEC_OK else {
            context.deallocate()
            throw WebMEncoderError.couldNotStart("AV1")
        }
        config.g_w = UInt32(settings.width)
        config.g_h = UInt32(settings.height)
        config.g_timebase = aom_rational(num: 1, den: Int32(ticksPerSecond))
        config.g_threads = UInt32(max(1, settings.threads))
        config.g_pass = AOM_RC_ONE_PASS
        config.g_lag_in_frames = 25
        config.g_bit_depth = AOM_BITS_8
        config.g_input_bit_depth = 8
        config.rc_end_usage = settings.quality == nil ? AOM_VBR : AOM_CQ
        config.rc_target_bitrate = UInt32(max(1, settings.bitrate / 1000))
        config.kf_mode = AOM_KF_AUTO
        config.kf_max_dist = UInt32(max(1, settings.keyframeInterval))
        guard droptimize_aom_av1_init(context, &config) == AOM_CODEC_OK else {
            context.deallocate()
            throw WebMEncoderError.couldNotStart("AV1")
        }
        set(AOME_SET_CPUUSED.rawValue, Int32(settings.speed))
        set(AV1E_SET_ROW_MT.rawValue, 1)
        set(AV1E_SET_TILE_COLUMNS.rawValue, tileColumnsLog2(width: settings.width))
        set(AV1E_SET_COLOR_PRIMARIES.rawValue, Int32(AOM_CICP_CP_BT_709.rawValue))
        set(AV1E_SET_TRANSFER_CHARACTERISTICS.rawValue, Int32(AOM_CICP_TC_BT_709.rawValue))
        set(AV1E_SET_MATRIX_COEFFICIENTS.rawValue, Int32(AOM_CICP_MC_BT_709.rawValue))
        set(AV1E_SET_COLOR_RANGE.rawValue, Int32(AOM_CR_STUDIO_RANGE.rawValue))
        if let quality = settings.quality { set(AOME_SET_CQ_LEVEL.rawValue, Int32(quality)) }

        // The sequence header, which WebM keeps in the track's av1C (Matroska's AV1 mapping).
        if let headers = aom_codec_get_global_headers(context) {
            defer { free(headers.pointee.buf); free(headers) }
            if let bytes = headers.pointee.buf {
                codecPrivate = AV1Bitstream.configurationRecord(
                    sequenceHeader: Array(UnsafeRawBufferPointer(start: bytes, count: headers.pointee.sz)))
            }
        }
    }

    deinit {
        aom_codec_destroy(context)
        context.deallocate()
    }

    private func set(_ control: UInt32, _ value: Int32) {
        _ = droptimize_aom_control(context, Int32(control), value)
    }

    func encode(_ frame: NV12Frame, seconds: Double) throws -> [EncodedPacket] {
        var image = aom_image_t()
        let luma = UnsafeMutablePointer(mutating: frame.luma), chroma = UnsafeMutablePointer(mutating: frame.chroma)
        guard aom_img_wrap(&image, AOM_IMG_FMT_NV12, UInt32(settings.width), UInt32(settings.height), 1, luma) != nil
        else { throw WebMEncoderError.failed("AV1") }
        // libaom's NV12: the interleaved chroma in the U plane, and no V plane.
        image.planes = (luma, chroma, nil)
        image.stride = (Int32(frame.lumaStride), Int32(frame.chromaStride), 0)
        image.cp = AOM_CICP_CP_BT_709
        image.tc = AOM_CICP_TC_BT_709
        image.mc = AOM_CICP_MC_BT_709
        image.range = AOM_CR_STUDIO_RANGE
        return try run(&image, pts: ticks(seconds))
    }

    func finish() throws -> [EncodedPacket] {
        var packets: [EncodedPacket] = []
        while true {
            let more = try run(nil, pts: 0)
            if more.isEmpty { return packets }
            packets += more
        }
    }

    private func run(_ image: UnsafeMutablePointer<aom_image_t>?, pts: Int64) throws -> [EncodedPacket] {
        guard aom_codec_encode(context, image, pts, UInt(frameTicks), 0) == AOM_CODEC_OK
        else { throw WebMEncoderError.failed(String(cString: aom_codec_error(context))) }
        var packets: [EncodedPacket] = []
        var iterator: aom_codec_iter_t?
        while let packet = aom_codec_get_cx_data(context, &iterator) {
            guard packet.pointee.kind == AOM_CODEC_CX_FRAME_PKT else { continue }
            let frame = packet.pointee.data.frame
            guard let bytes = frame.buf, frame.sz > 0 else { continue }
            let start = frame.pts
            let data = AV1Bitstream.withoutTemporalDelimiters(Array(UnsafeRawBufferPointer(start: bytes, count: frame.sz)))
            packets.append(EncodedPacket(
                data: data,
                milliseconds: milliseconds(start),
                durationMilliseconds: milliseconds(start + Int64(frame.duration)) - milliseconds(start),
                isKey: frame.flags & UInt32(AOM_FRAME_IS_KEY) != 0))
        }
        return packets
    }
}

/// The bits of AV1's format the WebM mapping needs (https://www.matroska.org/technical/codec_specs.html).
enum AV1Bitstream {
    /// OBU types (AV1 spec §6.2.2).
    static let sequenceHeaderOBU: UInt8 = 1
    static let temporalDelimiterOBU: UInt8 = 2

    /// One OBU: its type and where it sits in the data, header included.
    struct OBU: Equatable {
        var type: UInt8
        var range: Range<Int>
        /// Where its payload starts.
        var payloadStart: Int
    }

    /// Splits AV1 data into its OBUs; nil if it isn't well formed (every OBU must say its size).
    static func obus(_ data: [UInt8]) -> [OBU]? {
        var result: [OBU] = []
        var index = 0
        while index < data.count {
            let header = data[index]
            let type = (header >> 3) & 0x0F
            let hasExtension = header & 0x04 != 0
            guard header & 0x02 != 0 else { return nil }
            var cursor = index + 1 + (hasExtension ? 1 : 0)
            var size = 0
            var shift = 0
            while true {
                guard cursor < data.count, shift < 56 else { return nil }
                let byte = data[cursor]
                cursor += 1
                size |= Int(byte & 0x7F) << shift
                shift += 7
                if byte & 0x80 == 0 { break }
            }
            guard cursor + size <= data.count else { return nil }
            result.append(OBU(type: type, range: index..<(cursor + size), payloadStart: cursor))
            index = cursor + size
        }
        return result
    }

    /// Matroska blocks leave out temporal delimiters (each block is already one temporal unit).
    static func withoutTemporalDelimiters(_ data: [UInt8]) -> [UInt8] {
        guard let units = obus(data), units.contains(where: { $0.type == temporalDelimiterOBU }) else { return data }
        return units.filter { $0.type != temporalDelimiterOBU }.flatMap { data[$0.range] }
    }

    /// The AV1CodecConfigurationRecord ("av1C") for 8-bit 4:2:0, followed by the sequence header OBU.
    static func configurationRecord(sequenceHeader: [UInt8]) -> [UInt8] {
        var profile: UInt8 = 0, level: UInt8 = 31, tier: UInt8 = 0
        if let header = obus(sequenceHeader)?.first(where: { $0.type == sequenceHeaderOBU }),
           let parsed = profileLevelTier(Array(sequenceHeader[header.payloadStart..<header.range.upperBound])) {
            (profile, level, tier) = parsed
        }
        // marker + version 1 · profile + level · tier, 8-bit, not mono, 4:2:0 (subsampled x and y),
        // chroma position unknown · no initial presentation delay.
        return [0x81, profile << 5 | level, tier << 7 | 0b0000_1100, 0x00] + sequenceHeader
    }

    /// seq_profile, seq_level_idx[0] and seq_tier[0] from a sequence header's payload (AV1 spec §5.5).
    static func profileLevelTier(_ payload: [UInt8]) -> (UInt8, UInt8, UInt8)? {
        var reader = BitReader(payload)
        guard let profile = reader.read(3), let _ = reader.read(1), let reduced = reader.read(1) else { return nil }
        if reduced == 1 {
            guard let level = reader.read(5) else { return nil }
            return (UInt8(profile), UInt8(level), 0)
        }
        // Timing info has variable-length fields; libaom leaves it out unless asked.
        guard let timing = reader.read(1), timing == 0,
              let _ = reader.read(1),                           // initial_display_delay_present_flag
              let _ = reader.read(5),                           // operating_points_cnt_minus_1
              let _ = reader.read(12),                          // operating_point_idc[0]
              let level = reader.read(5)
        else { return nil }
        var tier: UInt32 = 0
        if level > 7 { guard let bit = reader.read(1) else { return nil }; tier = bit }
        return (UInt8(profile), UInt8(level), UInt8(tier))
    }

    private struct BitReader {
        let bytes: [UInt8]
        var bit = 0
        init(_ bytes: [UInt8]) { self.bytes = bytes }

        mutating func read(_ count: Int) -> UInt32? {
            var value: UInt32 = 0
            for _ in 0..<count {
                guard bit / 8 < bytes.count else { return nil }
                value = value << 1 | UInt32((bytes[bit / 8] >> (7 - UInt8(bit % 8))) & 1)
                bit += 1
            }
            return value
        }
    }
}

// MARK: Opus (libopus)

/// Opus sound for WebM: 48 kHz, one or two channels, 20 ms packets.
final class OpusAudioEncoder {
    static let sampleRate = 48_000
    /// 20 ms, the usual Opus frame for music and speech alike.
    static let frameSamples = 960

    let channels: Int
    /// Samples the decoder drops at the start ("pre-skip"): the encoder's lookahead.
    let preSkip: Int
    private let encoder: OpaquePointer
    private var pending: [Float] = []
    private var framesWritten: Int64 = 0
    private var samplesIn = 0
    private var output = [UInt8](repeating: 0, count: 4000)

    init(channels: Int, bitrate: Int) throws {
        self.channels = min(max(channels, 1), 2)
        var error: Int32 = 0
        guard let encoder = opus_encoder_create(Int32(Self.sampleRate), Int32(self.channels), OPUS_APPLICATION_AUDIO, &error),
              error == OPUS_OK
        else { throw WebMEncoderError.couldNotStart("Opus") }
        self.encoder = encoder
        _ = droptimize_opus_set_bitrate(encoder, Int32(bitrate))
        preSkip = Int(droptimize_opus_lookahead(encoder))
    }

    deinit {
        opus_encoder_destroy(encoder)
    }

    /// OpusHead (RFC 7845 §5.1): what the WebM track's CodecPrivate holds.
    var codecPrivate: [UInt8] {
        func littleEndian(_ value: Int, _ bytes: Int) -> [UInt8] { (0..<bytes).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) } }
        return Array("OpusHead".utf8) + [1, UInt8(channels)] + littleEndian(preSkip, 2)
            + littleEndian(Self.sampleRate, 4) + [0, 0, 0]       // no output gain, channel mapping family 0
    }

    var codecDelayNanoseconds: UInt64 { UInt64(preSkip) * 1_000_000_000 / UInt64(Self.sampleRate) }

    /// Adds interleaved samples (-1…1) and returns the packets now complete.
    func encode(_ samples: [Float]) throws -> [EncodedPacket] {
        samplesIn += samples.count / channels
        pending += samples
        return try drain()
    }

    /// Pads the end with silence so the last real samples make it out past the lookahead.
    func finish() throws -> [EncodedPacket] {
        let needed = samplesIn + preSkip
        let frames = (needed + Self.frameSamples - 1) / Self.frameSamples
        let missing = frames * Self.frameSamples - Int(framesWritten) * Self.frameSamples - pending.count / channels
        if missing > 0 { pending += [Float](repeating: 0, count: missing * channels) }
        return try drain()
    }

    private func drain() throws -> [EncodedPacket] {
        let frameLength = Self.frameSamples * channels
        var packets: [EncodedPacket] = []
        var start = 0
        while pending.count - start >= frameLength {
            let written = pending.withUnsafeBufferPointer { samples in
                opus_encode_float(encoder, samples.baseAddress! + start, Int32(Self.frameSamples), &output, Int32(output.count))
            }
            guard written > 0 else { throw WebMEncoderError.failed("Opus") }
            // Each packet starts 20 ms after the last: the block times count from the first decoded
            // sample, and CodecDelay tells the player to drop the pre-skip.
            packets.append(EncodedPacket(data: Array(output[0..<Int(written)]), milliseconds: framesWritten * 20,
                                         durationMilliseconds: 20, isKey: true))
            framesWritten += 1
            start += frameLength
        }
        pending.removeFirst(start)
        return packets
    }
}
