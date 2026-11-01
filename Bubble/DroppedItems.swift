import AppKit
import UniformTypeIdentifiers

/// What a drag carries, so images and videos can come from any app (CORE.md §4.2):
/// - **files** Finder (or anything else) already has on disk;
/// - **promised files** an app writes once you drop: Photos, Mail and Messages attachments,
///   Safari and most browsers' images;
/// - **picture data**, when that's all an app offers.
/// Read straight from the drag; `files(limit:)` turns it into files on disk. Promised and pasted
/// files land in a `ReceivedFiles` folder, so their results go to Downloads.
@MainActor
struct DroppedItems {
    private(set) var files: [URL] = []
    private(set) var promises: [NSFilePromiseReceiver] = []
    private(set) var pictures: [Picture] = []
    /// What the drag holds that Droptimize can work on, for choosing the menu.
    private(set) var kinds: Set<MediaKind> = []
    /// True when the drag holds something, even if nothing Droptimize can use.
    private(set) var hasItems = false

    struct Picture {
        var data: Data
        var type: UTType
        var name: String
    }

    /// The pasteboard types the bubble listens for.
    static var draggedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
            + pictureTypes.map { NSPasteboard.PasteboardType($0.identifier) }
    }

    /// Picture data, best first: the encoded original beats a browser's re-rendered TIFF.
    private static let pictureTypes: [UTType] = [.png, .jpeg, .heic, .webP, .gif, .tiff]
        + [UTType("public.avif")].compactMap { $0 }

    /// Reads the drag. `withData` also reads picture data, which is only needed at the drop.
    init(_ pasteboard: NSPasteboard, withData: Bool) {
        let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self],
                                              options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !fileURLs.isEmpty {
            hasItems = true
            files = fileURLs.filter { MediaKind(url: $0) != nil }
            kinds = Set(files.compactMap(MediaKind.init(url:)))
            return
        }

        let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil)
            as? [NSFilePromiseReceiver] ?? []
        if !receivers.isEmpty {
            hasItems = true
            promises = receivers.filter { !Self.kinds(of: $0).isEmpty }
            kinds = Set(promises.flatMap(Self.kinds(of:)))
            return
        }

        for item in pasteboard.pasteboardItems ?? [] {
            guard let type = Self.pictureTypes.first(where: { item.types.contains(NSPasteboard.PasteboardType($0.identifier)) })
            else { continue }
            hasItems = true
            kinds.insert(.image)
            guard withData, let data = item.data(forType: NSPasteboard.PasteboardType(type.identifier)) else {
                pictures.append(Picture(data: Data(), type: type, name: ""))   // counted; read at the drop
                continue
            }
            pictures.append(Picture(data: data, type: type, name: Self.name(for: item)))
        }
    }

    /// How many things the drop would make.
    var count: Int { files.count + promises.count + pictures.count }

    /// True when everything is already a file on disk (no waiting).
    var isReady: Bool { promises.isEmpty && pictures.isEmpty }

    /// The first `limit` items as files on disk. Promised files can take a moment (Photos may
    /// fetch from iCloud); gives up on any that don't arrive within `ReceivedFiles` patience.
    func files(limit: Int) async throws -> [URL] {
        if isReady { return Array(files.prefix(limit)) }
        let folder = try ReceivedFiles.newFolder()
        if !promises.isEmpty {
            let received = await Self.receive(Array(promises.prefix(limit)), into: folder)
            return received.filter { MediaKind(url: $0) != nil }
        }
        var written: [URL] = []
        for picture in pictures.prefix(limit) where !picture.data.isEmpty {
            let ext = picture.type.preferredFilenameExtension ?? "png"
            var url = folder.appendingPathComponent(picture.name).appendingPathExtension(ext)
            var number = 2
            while FileManager.default.fileExists(atPath: url.path) {
                url = folder.appendingPathComponent("\(picture.name) \(number)").appendingPathExtension(ext)
                number += 1
            }
            try picture.data.write(to: url, options: .withoutOverwriting)
            written.append(url)
        }
        return written
    }

    // MARK: Promises

    /// Seconds to wait for promised files before going on with what arrived.             (tune)
    static let promisePatience: Double = 90

    private static func kinds(of receiver: NSFilePromiseReceiver) -> [MediaKind] {
        receiver.fileTypes.compactMap { identifier in
            guard let type = UTType(identifier) else { return nil }
            if type.conforms(to: .svg) { return nil }
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
            return nil
        }
    }

    private static func receive(_ receivers: [NSFilePromiseReceiver], into folder: URL) async -> [URL] {
        let expected = receivers.reduce(0) { $0 + max(1, $1.fileTypes.count) }
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return await withCheckedContinuation { (continuation: CheckedContinuation<[URL], Never>) in
            let collector = Collector(expected: expected, continuation: continuation)
            for receiver in receivers {
                receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: queue) { url, error in
                    collector.add(error == nil ? url : nil)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + promisePatience) { collector.finish() }
        }
    }

    /// Gathers promised files as they arrive (on any thread) and answers once, when all are in or
    /// time is up.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        private var remaining: Int
        private var continuation: CheckedContinuation<[URL], Never>?

        init(expected: Int, continuation: CheckedContinuation<[URL], Never>) {
            remaining = expected
            self.continuation = continuation
        }

        func add(_ url: URL?) {
            lock.lock()
            if let url { urls.append(url) }
            remaining -= 1
            let done = remaining <= 0
            lock.unlock()
            if done { finish() }
        }

        func finish() {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            let urls = self.urls
            lock.unlock()
            continuation?.resume(returning: urls)
        }
    }

    // MARK: Pictures

    /// A browser usually says where the picture came from: use its file name.
    private static func name(for item: NSPasteboardItem) -> String {
        let stem = item.string(forType: .URL).flatMap(URL.init(string:))?.deletingPathExtension().lastPathComponent ?? ""
        let cleaned = stem.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Image" : String(cleaned.prefix(80))
    }
}
