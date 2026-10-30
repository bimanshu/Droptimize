import Foundation

/// Applies a subject mask from background removal (CORE.md §6.5).
enum Compositor {
    /// Cuts the subject out: each pixel's alpha is scaled by its `mask` value (0 = background,
    /// 1 = subject). With a `background` color, the result is laid over it and comes out opaque;
    /// without one it stays transparent.
    static func cutOut(_ image: RGBAImage, mask: [Float], background: RGBColor?) -> RGBAImage {
        precondition(mask.count == image.pixelCount, "the mask doesn't match the image")
        var pixels = image.pixels
        pixels.withUnsafeMutableBufferPointer { p in
            mask.withUnsafeBufferPointer { mask in
                for i in 0..<mask.count {
                    let o = i * 4
                    let alpha = Float(p[o + 3]) / 255 * min(max(mask[i], 0), 1)
                    if let background {
                        p[o] = blend(p[o], over: background.red, alpha: alpha)
                        p[o + 1] = blend(p[o + 1], over: background.green, alpha: alpha)
                        p[o + 2] = blend(p[o + 2], over: background.blue, alpha: alpha)
                        p[o + 3] = 255
                    } else {
                        let value = UInt8((alpha * 255).rounded())
                        if value == 0 {
                            p[o] = 0; p[o + 1] = 0; p[o + 2] = 0     // invisible: keep RGBAImage's 0,0,0,0
                        }
                        p[o + 3] = value
                    }
                }
            }
        }
        return RGBAImage(width: image.width, height: image.height, pixels: pixels)
    }

    @inline(__always)
    private static func blend(_ foreground: UInt8, over background: UInt8, alpha: Float) -> UInt8 {
        UInt8((Float(foreground) * alpha + Float(background) * (1 - alpha)).rounded())
    }
}
