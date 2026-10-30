import Foundation

/// Phase 0 stand-in for the real pipeline: pretends to work for about a second, then hands
/// back the original files with a made-up saving. It never writes or changes anything.
/// Replace with the image pipeline in Phase 1 (CORE.md §6).
struct FakeJobRunner: JobRunner {
    var duration: Double = 1
    /// For trying the error state: fail with this instead of finishing.
    var failure: JobError?

    func run(_ job: Job, progress: @escaping @MainActor (JobProgress) -> Void) async throws -> JobResult {
        let total = job.files.count
        let ticks = 30
        for tick in 1...ticks {
            try await Task.sleep(nanoseconds: UInt64(duration / Double(ticks) * 1_000_000_000))
            let fraction = Double(tick) / Double(ticks)
            await progress(JobProgress(completed: Int(fraction * Double(total)), total: total, fraction: fraction))
        }
        if let failure { throw failure }
        let inputBytes = job.files.reduce(Int64(0)) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        let saving = Double.random(in: 0.4...0.75)
        return JobResult(outputs: job.files, inputBytes: inputBytes,
                         outputBytes: Int64(Double(inputBytes) * (1 - saving)))
    }
}
