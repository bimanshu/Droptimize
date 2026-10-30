import CAvif
import Foundation

/// AVIF through libavif + libaom (CORE.md §6.3): 8-bit for compatibility, tagged sRGB, 4:4:4
/// for graphics and 4:2:0 for photos, alpha kept losslessly. No metadata.
enum AVIFEncoder {
    enum Failure: Error, Equatable {
        case setup
        case conversion(UInt32)
        case encoding(UInt32)
    }

    /// `quality` is libavif's 0–100 (100 is lossless). `speed` is libaom's 0 (slowest, smallest) – 10.
    static func encode(_ image: RGBAImage, quality: Int, speed: Int = EncoderTuning.avifSpeed) throws -> Data {
        let opaque = image.isOpaque
        let chroma = image.looksLikeGraphic ? AVIF_PIXEL_FORMAT_YUV444 : AVIF_PIXEL_FORMAT_YUV420
        guard let avif = avifImageCreate(UInt32(image.width), UInt32(image.height), 8, chroma) else { throw Failure.setup }
        defer { avifImageDestroy(avif) }
        avif.pointee.colorPrimaries = avifColorPrimaries(AVIF_COLOR_PRIMARIES_BT709)
        avif.pointee.transferCharacteristics = avifTransferCharacteristics(AVIF_TRANSFER_CHARACTERISTICS_SRGB)
        avif.pointee.matrixCoefficients = avifMatrixCoefficients(AVIF_MATRIX_COEFFICIENTS_BT601)
        avif.pointee.yuvRange = AVIF_RANGE_FULL

        var rgb = avifRGBImage()
        avifRGBImageSetDefaults(&rgb, avif)
        rgb.format = AVIF_RGB_FORMAT_RGBA
        rgb.depth = 8
        rgb.rowBytes = UInt32(image.width * 4)
        // No alpha plane at all for opaque images: smaller files.
        rgb.ignoreAlpha = opaque ? 1 : 0
        var pixels = image.pixels
        let converted = pixels.withUnsafeMutableBufferPointer { buffer -> avifResult in
            rgb.pixels = buffer.baseAddress
            defer { rgb.pixels = nil }
            return avifImageRGBToYUV(avif, &rgb)
        }
        guard converted == AVIF_RESULT_OK else { throw Failure.conversion(converted.rawValue) }

        guard let encoder = avifEncoderCreate() else { throw Failure.setup }
        defer { avifEncoderDestroy(encoder) }
        encoder.pointee.quality = Int32(min(max(quality, 0), 100))
        encoder.pointee.qualityAlpha = Int32(AVIF_QUALITY_LOSSLESS)
        encoder.pointee.speed = Int32(speed)
        encoder.pointee.maxThreads = Int32(ProcessInfo.processInfo.activeProcessorCount)

        var output = avifRWData()
        defer { avifRWDataFree(&output) }
        let written = avifEncoderWrite(encoder, avif, &output)
        guard written == AVIF_RESULT_OK, let bytes = output.data else { throw Failure.encoding(written.rawValue) }
        return Data(bytes: bytes, count: output.size)
    }
}
