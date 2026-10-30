import Foundation

/// Finds the best quality that still fits a file-size limit, for Compress's target sizes.
enum SizeSearch {
    /// The output at the highest quality in `qualities` whose size is at most `limit` bytes,
    /// found by bisection (file size grows with quality). Nil when even the lowest is too big.
    /// Encodes at most `steps + 2` times.
    static func bestFit(limit: Int, qualities: ClosedRange<Double>, steps: Int = EncoderTuning.searchSteps,
                        encode: (Double) throws -> Data) rethrows -> Data? {
        let highest = try encode(qualities.upperBound)
        if highest.count <= limit { return highest }
        var best = try encode(qualities.lowerBound)
        guard best.count <= limit else { return nil }
        var low = qualities.lowerBound
        var high = qualities.upperBound
        for _ in 0..<steps {
            let middle = (low + high) / 2
            let data = try encode(middle)
            if data.count <= limit {
                best = data
                low = middle
            } else {
                high = middle
            }
        }
        return best
    }

    /// The scales to try, largest first, when even the lowest quality is too big at full size.
    /// Stops before either side would drop under `minimumSide` pixels.
    static func scales(width: Int, height: Int, minimumSide: Int = EncoderTuning.minimumFitSide) -> [Double] {
        var scales: [Double] = [1]
        var scale = 1.0
        while true {
            scale *= EncoderTuning.fitScaleStep
            guard Double(min(width, height)) * scale >= Double(minimumSide) else { break }
            scales.append(scale)
        }
        return scales
    }
}
