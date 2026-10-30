import Foundation
import UniformTypeIdentifiers

/// One image, optimized and saved.
struct FileOutcome {
    var input: URL
    var output: URL
    var inputBytes: Int
    var outputBytes: Int
    /// A PNG of the result for the clipboard, when one was asked for.
    var picture: Data?
    /// Worth telling the user, such as "Resized to 1600 × 1200 to fit".
    var note: String?
}

/// Turns one image into a new file next to it (CORE.md §6). Synchronous and CPU-bound: call it
/// off the main thread.
enum ImageOptimizer {
    static func process(_ input: URL, action: Action, option: ActionOption? = nil, wantsPicture: Bool) throws -> FileOutcome {
        let inputBytes = (try? input.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0

        switch (action, option) {
        case (.compress, .maxBytes(let limit)?):
            return try compress(input, inputBytes: inputBytes, toFit: limit, wantsPicture: wantsPicture)
        case (.removeBackground, _):
            var background: RGBColor?
            if case .background(let color) = option { background = color }
            return try removeBackground(input, inputBytes: inputBytes, background: background, wantsPicture: wantsPicture)
        default:
            let decoded = try ImageDecoder.decode(input, scale: ImagePlan.scale(for: action))
            let plan = try ImagePlan.make(action: action, option: option, source: decoded.format,
                                          sourceExtension: input.pathExtension)
            var image = decoded.image
            var note: String?
            if plan.encoding == .jpeg, !image.isOpaque {
                // JPEG can't hold transparency (CORE.md §6.2).
                image = Compositor.cutOut(image, mask: [Float](repeating: 1, count: image.pixelCount), background: .white)
                note = "Transparency filled with white"
            }
            let data = try encode(image, as: plan.encoding)
            // A conversion into another format is what was asked for, even when it comes out bigger
            // (WebP → PNG often does). Everything else never hands back a bigger file (Rule 3).
            let isFormatChange = action == .convert && plan.suffix == nil
            if !isFormatChange {
                guard SizeGuard.accepts(inputBytes: inputBytes, outputBytes: data.count) else { throw JobError.alreadySmallest }
            }
            return try save(data, showing: image, for: input, plan: plan, inputBytes: inputBytes,
                            wantsPicture: wantsPicture, note: note)
        }
    }

    static func encode(_ image: RGBAImage, as encoding: ImagePlan.Encoding) throws -> Data {
        switch encoding {
        case .webp:
            let lossy = try WebPEncoder.encode(image, quality: EncoderTuning.webpQuality)
            // Graphics often come out smaller lossless; keep whichever is smaller.
            guard image.looksLikeGraphic else { return lossy }
            let lossless = try WebPEncoder.encode(image, quality: nil)
            return lossless.count < lossy.count ? lossless : lossy
        case .png:
            return try PNGEncoder.encode(image)
        case .jpeg:
            return try ImageIOEncoder.encode(image, as: .jpeg, quality: EncoderTuning.jpegQuality)
        case .heic:
            return try ImageIOEncoder.encode(image, as: .heic, quality: EncoderTuning.heicQuality)
        case .avif:
            return try AVIFEncoder.encode(image, quality: EncoderTuning.avifQuality)
        }
    }

    /// The best-looking output of at most `limit` bytes, or nil if none fits at this size.
    static func encode(_ image: RGBAImage, as encoding: ImagePlan.Encoding, fitting limit: Int) throws -> Data? {
        switch encoding {
        case .png:
            // Lossless has no quality to turn down; only shrinking helps.
            let data = try PNGEncoder.encode(image)
            return data.count <= limit ? data : nil
        case .jpeg:
            return try SizeSearch.bestFit(limit: limit, qualities: EncoderTuning.jpegQualities) {
                try ImageIOEncoder.encode(image, as: .jpeg, quality: $0)
            }
        case .heic:
            return try SizeSearch.bestFit(limit: limit, qualities: EncoderTuning.heicQualities) {
                try ImageIOEncoder.encode(image, as: .heic, quality: $0)
            }
        case .webp:
            if image.looksLikeGraphic {
                let lossless = try WebPEncoder.encode(image, quality: nil)
                if lossless.count <= limit { return lossless }
            }
            return try SizeSearch.bestFit(limit: limit, qualities: EncoderTuning.webpQualities) {
                try WebPEncoder.encode(image, quality: Float($0))
            }
        case .avif:
            // Search at a faster speed (each step is an encode), then re-encode the winner at the
            // normal speed, which usually comes out smaller still. Keep whichever fits.
            guard let fast = try SizeSearch.bestFitAndQuality(limit: limit, qualities: EncoderTuning.avifQualities, encode: {
                try AVIFEncoder.encode(image, quality: Int($0.rounded()), speed: EncoderTuning.avifSearchSpeed)
            }) else { return nil }
            let final = try AVIFEncoder.encode(image, quality: Int(fast.quality.rounded()))
            return final.count <= limit ? final : fast.data
        }
    }

    /// Compress to at most `limit` bytes, same format: the best quality that fits, and smaller
    /// dimensions only when even the lowest quality is too big.
    private static func compress(_ input: URL, inputBytes: Int, toFit limit: Int, wantsPicture: Bool) throws -> FileOutcome {
        guard inputBytes > limit else { throw JobError.alreadyUnder(limit) }
        let decoded = try ImageDecoder.decode(input)
        let plan = try ImagePlan.make(action: .compress, option: .maxBytes(limit), source: decoded.format,
                                      sourceExtension: input.pathExtension)
        for scale in SizeSearch.scales(width: decoded.image.width, height: decoded.image.height) {
            try Task.checkCancellation()
            let image = try scale < 1 ? ImageDecoder.decode(input, scale: scale).image : decoded.image
            if let data = try encode(image, as: plan.encoding, fitting: limit) {
                let note = scale < 1 ? "Resized to \(image.width) × \(image.height) to fit" : nil
                return try save(data, showing: image, for: input, plan: plan, inputBytes: inputBytes,
                                wantsPicture: wantsPicture, note: note)
            }
        }
        throw JobError.cantFit(limit)
    }

    /// Cuts out the subject (CORE.md §6.5) and keeps it transparent or puts a color behind it.
    /// Always a PNG. Not an optimization, so the size guard doesn't apply: a cut-out PNG can be
    /// bigger than the JPEG it came from.
    private static func removeBackground(_ input: URL, inputBytes: Int, background: RGBColor?,
                                         wantsPicture: Bool) throws -> FileOutcome {
        let decoded = try ImageDecoder.decode(input)
        let mask = try SubjectMask.make(for: decoded.image)
        let cut = Compositor.cutOut(decoded.image, mask: mask, background: background)
        let plan = try ImagePlan.make(action: .removeBackground, option: .background(background),
                                      source: decoded.format, sourceExtension: input.pathExtension)
        return try save(PNGEncoder.encode(cut), showing: cut, for: input, plan: plan, inputBytes: inputBytes,
                        wantsPicture: wantsPicture,
                        note: background.map { "Background: \($0.name)" } ?? "Background removed")
    }

    private static func save(_ data: Data, showing image: RGBAImage, for input: URL, plan: ImagePlan,
                             inputBytes: Int, wantsPicture: Bool, note: String? = nil) throws -> FileOutcome {
        let output = try OutputWriter.write(data, for: input, fileExtension: plan.fileExtension, suffix: plan.suffix)
        let picture = wantsPicture && image.pixelCount <= EncoderTuning.clipboardImagePixelLimit
            ? try? ImageIOEncoder.encode(image, as: .png)
            : nil
        return FileOutcome(input: input, output: output, inputBytes: inputBytes, outputBytes: data.count,
                           picture: picture, note: note)
    }
}

/// Runs a drop through `ImageOptimizer` (several images at a time) or `VideoOptimizer` (one video at
/// a time, CORE.md §5), and puts the results on the clipboard.
struct ImageJobRunner: JobRunner {
    func run(_ job: Job, progress: @escaping @MainActor (JobProgress) -> Void) async throws -> JobResult {
        let action = job.action
        let option = job.option
        let total = job.files.count
        let wantsPicture = total == 1
        var outcomes: [(index: Int, outcome: FileOutcome)] = []
        var errors: [Error] = []
        let hasVideo = job.files.contains { MediaKind(url: $0) == .video }
        let concurrency = hasVideo ? 1 : Self.concurrency
        // Videos report progress within the file; images only as each one finishes.
        let reporter = ProgressReporter(total: total, report: progress)

        await withTaskGroup(of: (Int, Result<FileOutcome, Error>).self) { group in
            func collect(_ finished: (Int, Result<FileOutcome, Error>)) async {
                switch finished.1 {
                case .success(let outcome): outcomes.append((finished.0, outcome))
                case .failure(let error): errors.append(error)
                }
                let done = outcomes.count + errors.count
                reporter.finished(count: done)
                await progress(JobProgress(completed: done, total: total, fraction: Double(done) / Double(total)))
            }
            for (index, url) in job.files.enumerated() {
                if index >= concurrency, let finished = await group.next() { await collect(finished) }
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        if MediaKind(url: url) == .video {
                            let outcome = try await VideoOptimizer.process(url, action: action, option: option,
                                                                           progress: reporter.within)
                            return (index, .success(outcome))
                        }
                        return (index, .success(try ImageOptimizer.process(url, action: action, option: option,
                                                                           wantsPicture: wantsPicture)))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            for await finished in group { await collect(finished) }
        }
        try Task.checkCancellation()

        let results = outcomes.sorted { $0.index < $1.index }.map(\.outcome)
        guard !results.isEmpty else {
            // Report a real problem before "already as small as it gets".
            throw errors.first { ($0 as? JobError) != .alreadySmallest } ?? errors.first ?? JobError.unreadable
        }
        let outputs = results.map(\.output)
        let picture = results.first?.picture
        await MainActor.run { Clipboard.put(outputs, picture: picture) }
        return JobResult(outputs: outputs,
                         inputBytes: Int64(results.reduce(0) { $0 + $1.inputBytes }),
                         outputBytes: Int64(results.reduce(0) { $0 + $1.outputBytes }),
                         note: results.count == 1 ? results[0].note : nil,
                         items: results.map { JobResult.Item(input: $0.input, output: $0.output,
                                                            inputBytes: $0.inputBytes, outputBytes: $0.outputBytes) })
    }

    /// Turns progress within the current file into batch progress on the main actor, about once
    /// per percent rather than once per video frame.
    private final class ProgressReporter: @unchecked Sendable {
        private let lock = NSLock()
        private let total: Int
        private let report: Unchecked<@MainActor (JobProgress) -> Void>
        private var completed = 0
        private var lastFraction = -1.0

        init(total: Int, report: @escaping @MainActor (JobProgress) -> Void) {
            self.total = total
            self.report = Unchecked(report)
        }

        func finished(count: Int) {
            lock.lock(); defer { lock.unlock() }
            completed = count
        }

        /// 0…1 through the file being worked on.
        var within: @Sendable (Double) -> Void {
            { [self] part in
                lock.lock()
                let fraction = (Double(completed) + min(max(part, 0), 1)) / Double(max(total, 1))
                guard fraction - lastFraction >= 0.01 else { lock.unlock(); return }
                lastFraction = fraction
                let progress = JobProgress(completed: completed, total: total, fraction: fraction)
                lock.unlock()
                let report = self.report
                Task { @MainActor in report.value(progress) }
            }
        }
    }

    /// Images at once: the performance cores, at most four (each one can hold a few hundred MB).  (tune)
    static let concurrency: Int = {
        var cores: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.physicalcpu", &cores, &size, nil, 0) == 0, cores > 0 {
            return min(Int(cores), 4)
        }
        return max(1, min(ProcessInfo.processInfo.activeProcessorCount / 2, 4))
    }()
}
