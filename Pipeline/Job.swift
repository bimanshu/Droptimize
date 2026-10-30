import Foundation

/// One drop: some files and what to do with them. A batch shares one action (CORE.md §4.2).
struct Job: Identifiable {
    let id = UUID()
    var files: [URL]
    var action: Action
}

struct JobProgress: Equatable {
    var completed: Int
    var total: Int
    /// 0...1 across the whole batch.
    var fraction: Double
}

/// What a finished job hands back.
struct JobResult {
    var outputs: [URL]
    var inputBytes: Int64
    var outputBytes: Int64

    /// How much smaller the outputs are, 0...1.
    var saving: Double {
        inputBytes > 0 ? max(0, 1 - Double(outputBytes) / Double(inputBytes)) : 0
    }
}

/// The short lines the bubble shows when something doesn't work (CORE.md §4.3).
enum JobError: LocalizedError, Equatable {
    case alreadySmallest
    case noSubject
    case unsupported
    case unreadable
    case cantSave
    /// An action or format that isn't built yet; the message says which.
    case notYet(String)

    var errorDescription: String? {
        switch self {
        case .alreadySmallest: return "Already as small as it gets."
        case .noSubject: return "Couldn't find a clear subject."
        case .unsupported: return "Can't open this file type yet."
        case .unreadable: return "Couldn't open this image."
        case .cantSave: return "Couldn't save the result."
        case .notYet(let message): return message
        }
    }
}

/// Runs a job off the main thread (Rule 5).
protocol JobRunner {
    /// Runs `job`, reporting progress on the main actor. Throws `CancellationError` when cancelled.
    func run(_ job: Job, progress: @escaping @MainActor (JobProgress) -> Void) async throws -> JobResult
}
