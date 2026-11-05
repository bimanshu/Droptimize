import CAom
import Foundation

/// Test-only: decodes AV1 with libaom's decoder, to look at the pictures an AV1 WebM shows
/// without needing FFmpeg (macOS can't play WebM).
enum TestAV1Decoder {
    /// One decoded 4:2:0 picture, planes packed without padding.
    struct Picture {
        var width: Int
        var height: Int
        var y: [UInt8]
        var cb: [UInt8]
        var cr: [UInt8]

        /// The color at a point, converted from limited-range BT.709 to RGB (0…255).
        func rgb(x: Int, y row: Int) -> (r: Int, g: Int, b: Int) {
            let luma = 1.164 * (Double(y[row * width + x]) - 16)
            let chroma = (row / 2) * ((width + 1) / 2) + x / 2
            let u = Double(cb[chroma]) - 128, v = Double(cr[chroma]) - 128
            func clamp(_ value: Double) -> Int { min(255, max(0, Int(value.rounded()))) }
            return (clamp(luma + 1.793 * v), clamp(luma - 0.213 * u - 0.533 * v), clamp(luma + 2.112 * u))
        }
    }

    enum Failure: Error { case couldNotDecode }

    static func decode(_ packets: [[UInt8]]) throws -> [Picture] {
        let context = UnsafeMutablePointer<aom_codec_ctx_t>.allocate(capacity: 1)
        defer { context.deallocate() }
        guard droptimize_aom_av1_decoder_init(context) == AOM_CODEC_OK else { throw Failure.couldNotDecode }
        defer { aom_codec_destroy(context) }
        var pictures: [Picture] = []
        for packet in packets {
            guard aom_codec_decode(context, packet, packet.count, nil) == AOM_CODEC_OK else { throw Failure.couldNotDecode }
            var iterator: aom_codec_iter_t?
            while let image = aom_codec_get_frame(context, &iterator) { pictures.append(try picture(image.pointee)) }
        }
        return pictures
    }

    private static func picture(_ image: aom_image_t) throws -> Picture {
        let width = Int(image.d_w), height = Int(image.d_h)
        let wide = image.fmt.rawValue & UInt32(AOM_IMG_FMT_HIGHBITDEPTH) != 0      // 16-bit samples holding 8-bit values
        func plane(_ pointer: UnsafeMutablePointer<UInt8>?, stride: Int32, width: Int, height: Int) throws -> [UInt8] {
            guard let pointer else { throw Failure.couldNotDecode }
            var out = [UInt8](repeating: 0, count: width * height)
            for row in 0..<height {
                let line = pointer + row * Int(stride)
                for column in 0..<width {
                    out[row * width + column] = wide ? line[column * 2] : line[column]
                }
            }
            return out
        }
        let chromaWidth = (width + 1) / 2, chromaHeight = (height + 1) / 2
        return Picture(width: width, height: height,
                       y: try plane(image.planes.0, stride: image.stride.0, width: width, height: height),
                       cb: try plane(image.planes.1, stride: image.stride.1, width: chromaWidth, height: chromaHeight),
                       cr: try plane(image.planes.2, stride: image.stride.2, width: chromaWidth, height: chromaHeight))
    }
}
