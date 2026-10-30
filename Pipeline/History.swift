import Foundation

/// One file Droptimize made. Kept on this Mac only (Rule 4).
struct HistoryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var date: Date
    /// "Compress", "Convert", …
    var action: String
    /// The option bubble, if any: "Under 500 KB", "To JPG", "White".
    var detail: String?
    var input: URL
    var output: URL
    var inputBytes: Int
    var outputBytes: Int

    init(id: UUID = UUID(), date: Date = Date(), action: String, detail: String? = nil,
         input: URL, output: URL, inputBytes: Int, outputBytes: Int) {
        self.id = id
        self.date = date
        self.action = action
        self.detail = detail
        self.input = input
        self.output = output
        self.inputBytes = inputBytes
        self.outputBytes = outputBytes
    }

    /// "−84%", or "+12%" when it came out bigger (a conversion or Remove BG).
    var changeText: String {
        guard inputBytes > 0 else { return "" }
        let percent = Int((Double(outputBytes - inputBytes) / Double(inputBytes) * 100).rounded())
        return percent < 0 ? "\u{2212}\(-percent)%" : percent == 0 ? "±0%" : "+\(percent)%"
    }

    /// "Compress · Under 500 KB".
    var summary: String { [action, detail].compactMap { $0 }.joined(separator: " · ") }
}

/// Everything Droptimize made, newest first, up to `limit` entries.
struct HistoryLog: Codable, Equatable {
    static let limit = 500

    private(set) var entries: [HistoryEntry] = []

    /// Adds one drop's results. They go on top, in the order they were dropped.
    mutating func record(_ new: [HistoryEntry]) {
        entries = Array((new + entries).prefix(Self.limit))
    }

    mutating func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    mutating func clear() {
        entries.removeAll()
    }

    /// The latest outputs, for the menu bar's Recent list.
    func recentOutputs(_ count: Int = 10) -> [URL] {
        var recent: [URL] = []
        for entry in entries where !recent.contains(entry.output) {
            recent.append(entry.output)
            if recent.count == count { break }
        }
        return recent
    }

    /// Bytes saved across everything that came out smaller.
    var savedBytes: Int {
        entries.reduce(0) { $0 + max(0, $1.inputBytes - $1.outputBytes) }
    }
}

/// Reads and writes the history file in Application Support.
enum HistoryFile {
    static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Droptimize", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    /// The saved history, or an empty one if there's none yet or it can't be read.
    static func load(from url: URL) -> HistoryLog {
        guard let data = try? Data(contentsOf: url) else { return HistoryLog() }
        return (try? decoder.decode(HistoryLog.self, from: data)) ?? HistoryLog()
    }

    static func save(_ log: HistoryLog, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(log).write(to: url, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension ActionOption {
    /// How the option reads in History: "Under 500 KB", "To JPG", "No background", "White".
    var title: String? {
        switch self {
        case .maxBytes(let bytes): return "Under \(ByteCount.describe(bytes))"
        case .format(let format): return "To \(format.displayName)"
        case .background(nil): return "No background"
        case .background(let color?): return color.name
        case .custom: return nil
        }
    }
}
