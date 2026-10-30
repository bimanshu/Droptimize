import CoreVideo
import Foundation
import Vision

/// Finds the subject of a photo (people, pets, products, objects) with Vision, on device
/// (CORE.md §6.5, Rule 4).
enum SubjectMask {
    /// One value per pixel: 1 on the subject, 0 on the background, in between on soft edges.
    static func make(for image: RGBAImage) throws -> [Float] {
        guard let cgImage = image.makeCGImage() else { throw JobError.unreadable }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([request])
        } catch {
            throw JobError.noSubject
        }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw JobError.noSubject
        }
        let buffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
        return try read(buffer, width: image.width, height: image.height)
    }

    private static func read(_ buffer: CVPixelBuffer, width: Int, height: Int) throws -> [Float] {
        guard CVPixelBufferGetWidth(buffer) == width, CVPixelBufferGetHeight(buffer) == height else {
            throw JobError.noSubject
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw JobError.noSubject }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var mask = [Float](repeating: 0, count: width * height)
        switch CVPixelBufferGetPixelFormatType(buffer) {
        case kCVPixelFormatType_OneComponent32Float:
            for y in 0..<height {
                let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
                for x in 0..<width { mask[y * width + x] = row[x] }
            }
        case kCVPixelFormatType_OneComponent8:
            for y in 0..<height {
                let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
                for x in 0..<width { mask[y * width + x] = Float(row[x]) / 255 }
            }
        default:
            throw JobError.noSubject
        }
        return mask
    }
}
