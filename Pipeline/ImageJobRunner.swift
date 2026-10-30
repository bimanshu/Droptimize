import Foundation
import UniformTypeIdentifiers

/// One image, optimized and saved.
struct FileOutcome {
    var output: URL
    var inputBytes: Int
    var outputBytes: Int
    /// A PNG of the result for the clipboard, when one was asked for.
    var picture: Data?
}

/// Turns one image into a new, smaller file next to it (CORE.md §6). Synchronous and CPU-bound:
/// call it off the main thread.
enum ImageOptimizer {
    static func process(_ input: URL, action: Action, wantsPicture: Bool) throws -> FileOutcome {
        if MediaKind(url: input) == .video { throw JobError.notYet("Video is coming soon.") }
        let decoded = try ImageDecoder.decode(input, scale: ImagePlan.scale(for: action))
        let plan = try ImagePlan.make(action: action, source: decoded.format, sourceExtension: input.pathExtension)
        let data = try encode(decoded.image, as: plan.encoding)

        let inputBytes = (try? input.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard SizeGuard.accepts(inputBytes: inputBytes, outputBytes: data.count) else { throw JobError.alreadySmallest }
        let output = try OutputWriter.write(data, for: input, fileExtension: plan.fileExtension, suffix: plan.suffix)

        let picture = wantsPicture && decoded.image.pixelCount <= EncoderTuning.clipboardImagePixelLimit
            ? try? ImageIOEncoder.encode(decoded.image, as: .png)
            : nil
        return FileOutcome(output: output, inputBytes: inputBytes, outputBytes: data.count, picture: picture)
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
        }
    }
}

/// Runs a drop through `ImageOptimizer`, several files at a time (CORE.md §5), and puts the
/// results on the clipboard.
struct ImageJobRunner: JobRunner {
    func run(_ job: Job, progress: @escaping @MainActor (JobProgress) -> Void) async throws -> JobResult {
        _ = try ImagePlan.scale(for: job.action)        // fail at once for actions that aren't built yet
        let action = job.action
        let total = job.files.count
        let wantsPicture = total == 1
        var outcomes: [(index: Int, outcome: FileOutcome)] = []
        var errors: [Error] = []

        await withTaskGroup(of: (Int, Result<FileOutcome, Error>).self) { group in
            func collect(_ finished: (Int, Result<FileOutcome, Error>)) async {
                switch finished.1 {
                case .success(let outcome): outcomes.append((finished.0, outcome))
                case .failure(let error): errors.append(error)
                }
                let done = outcomes.count + errors.count
                await progress(JobProgress(completed: done, total: total, fraction: Double(done) / Double(total)))
            }
            for (index, url) in job.files.enumerated() {
                if index >= Self.concurrency, let finished = await group.next() { await collect(finished) }
                group.addTask {
                    (index, Result<FileOutcome, Error> {
                        try Task.checkCancellation()
                        return try ImageOptimizer.process(url, action: action, wantsPicture: wantsPicture)
                    })
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
                         outputBytes: Int64(results.reduce(0) { $0 + $1.outputBytes }))
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
