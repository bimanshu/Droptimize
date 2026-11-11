import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

// For a Mac without ffmpeg: blends rendered subframes into the film and copies in an existing cut's soundtrack.
//   swiftc -O encode-mac.swift -o encode-mac && ./encode-mac sub/ 3555 renders/droptimize-launch.mp4 out.mp4
// Averages 8 subframes per frame (motion blur), encodes H.264 at 60 fps, BT.709, and copies the source's audio as is.
let args = CommandLine.arguments
let dir = args[1], frames = Int(args[2])!, audioSource = URL(fileURLWithPath: args[3]), out = URL(fileURLWithPath: args[4])
let sub = 8, w = 1920, h = 1080, fps: Int32 = 60

func decode(_ path: String, into bytes: UnsafeMutablePointer<UInt8>) {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("can't read \(path)") }
    let c = CGContext(data: bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    c.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
}

/// One frame: the mean of its subframes, as BGRA.
func blend(_ k: Int, into dst: UnsafeMutablePointer<UInt8>, stride dstStride: Int) {
    let n = w * h * 4
    let sum = UnsafeMutablePointer<UInt16>.allocate(capacity: n); sum.initialize(repeating: 0, count: n)
    let px = UnsafeMutablePointer<UInt8>.allocate(capacity: n)
    defer { sum.deallocate(); px.deallocate() }
    for s in 0..<sub {
        decode("\(dir)/f\(String(format: "%06d", k * sub + s)).jpg", into: px)
        for i in 0..<n { sum[i] &+= UInt16(px[i]) }
    }
    for row in 0..<h {
        let d = dst + row * dstStride, srow = sum + row * w * 4
        for i in 0..<(w * 4) { d[i] = UInt8((Int(srow[i]) + sub / 2) / sub) }
    }
}

let writer = try AVAssetWriter(outputURL: { try? FileManager.default.removeItem(at: out); return out }(), fileType: .mp4)
writer.shouldOptimizeForNetworkUse = true
let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
    AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 16_000_000, AVVideoMaxKeyFrameIntervalKey: 120,
                                      AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                      AVVideoExpectedSourceFrameRateKey: 60, AVVideoAllowFrameReorderingKey: true] as [String: Any],
])
vIn.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])

let asset = AVURLAsset(url: audioSource)
let aTrack = try await asset.loadTracks(withMediaType: .audio).first!
let aFormat = try await aTrack.load(.formatDescriptions).first!
let reader = try AVAssetReader(asset: asset)
let aOut = AVAssetReaderTrackOutput(track: aTrack, outputSettings: nil)
reader.add(aOut)
let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: aFormat)
aIn.expectsMediaDataInRealTime = false
writer.add(vIn); writer.add(aIn)
reader.startReading()
writer.startWriting()
writer.startSession(atSourceTime: .zero)

// Frames are blended 8 at a time in parallel, then appended in order
let batch = 8
var next = 0
let t0 = Date()
let group = DispatchGroup()
group.enter()
vIn.requestMediaDataWhenReady(on: DispatchQueue(label: "video")) {
    while vIn.isReadyForMoreMediaData {
        if next >= frames { vIn.markAsFinished(); group.leave(); return }
        let count = min(batch, frames - next)
        var buffers = [CVPixelBuffer?](repeating: nil, count: count)
        for j in 0..<count { CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffers[j]) }
        DispatchQueue.concurrentPerform(iterations: count) { j in
            let pb = buffers[j]!
            CVPixelBufferLockBaseAddress(pb, [])
            blend(next + j, into: CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self), stride: CVPixelBufferGetBytesPerRow(pb))
            CVPixelBufferUnlockBaseAddress(pb, [])
        }
        for j in 0..<count {
            while !vIn.isReadyForMoreMediaData { usleep(2000) }
            adaptor.append(buffers[j]!, withPresentationTime: CMTime(value: CMTimeValue(next + j), timescale: fps))
        }
        next += count
        if next % 480 == 0 { print("\(next)/\(frames) frames, \(Int(Date().timeIntervalSince(t0))) s"); fflush(stdout) }
    }
}
group.enter()
aIn.requestMediaDataWhenReady(on: DispatchQueue(label: "audio")) {
    while aIn.isReadyForMoreMediaData {
        guard let sample = aOut.copyNextSampleBuffer() else { aIn.markAsFinished(); group.leave(); return }
        aIn.append(sample)
    }
}
await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in group.notify(queue: .main) { c.resume() } }
await writer.finishWriting()
if writer.status != .completed { print("FAILED:", writer.error as Any); exit(1) }
print("wrote \(frames) frames:", out.lastPathComponent, Double(try FileManager.default.attributesOfItem(atPath: out.path)[.size] as! UInt64) / 1_000_000, "MB")
