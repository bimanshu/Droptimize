import CWebP
import Foundation

/// WebP through libwebp (CORE.md §6.3). Writes no metadata; untagged WebP is read as sRGB.
enum WebPEncoder {
    enum Failure: Error, Equatable {
        case configuration
        case picture
        case encoding(UInt32)
    }

    /// Lossy at `quality` (0–100), or lossless when `quality` is nil.
    static func encode(_ image: RGBAImage, quality: Float?) throws -> Data {
        var config = WebPConfig()
        guard WebPConfigInit(&config) != 0 else { throw Failure.configuration }
        if let quality {
            guard WebPConfigPreset(&config, WEBP_PRESET_DEFAULT, quality) != 0 else { throw Failure.configuration }
            config.method = EncoderTuning.webpMethod
            // Converts RGB to YUV more carefully: sharper colored edges and text.
            config.use_sharp_yuv = 1
        } else {
            guard WebPConfigLosslessPreset(&config, EncoderTuning.webpLosslessLevel) != 0 else {
                throw Failure.configuration
            }
        }
        config.thread_level = 1
        guard WebPValidateConfig(&config) != 0 else { throw Failure.configuration }

        var picture = WebPPicture()
        guard WebPPictureInit(&picture) != 0 else { throw Failure.picture }
        defer { WebPPictureFree(&picture) }
        // Import as ARGB even for lossy, so the encoder does the YUV conversion (with sharp YUV).
        picture.use_argb = 1
        picture.width = Int32(image.width)
        picture.height = Int32(image.height)
        let imported = image.pixels.withUnsafeBufferPointer { pixels in
            WebPPictureImportRGBA(&picture, pixels.baseAddress, Int32(image.width * 4))
        }
        guard imported != 0 else { throw Failure.picture }

        var writer = WebPMemoryWriter()
        WebPMemoryWriterInit(&writer)
        defer { WebPMemoryWriterClear(&writer) }
        let encoded = withUnsafeMutablePointer(to: &writer) { writerPointer -> Int32 in
            picture.writer = WebPMemoryWrite
            picture.custom_ptr = UnsafeMutableRawPointer(writerPointer)
            return WebPEncode(&config, &picture)
        }
        guard encoded != 0, let bytes = writer.mem else { throw Failure.encoding(picture.error_code.rawValue) }
        return Data(bytes: bytes, count: writer.size)
    }
}
