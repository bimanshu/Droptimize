import AppKit
import SwiftUI

/// The history the app keeps, saved to Application Support after every change.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var log: HistoryLog
    private let url: URL?

    init(url: URL? = HistoryFile.defaultURL) {
        self.url = url
        log = url.map(HistoryFile.load(from:)) ?? HistoryLog()
    }

    func record(_ entries: [HistoryEntry]) {
        guard !entries.isEmpty else { return }
        log.record(entries)
        save()
    }

    func remove(_ id: UUID) {
        log.remove(id)
        save()
    }

    func clear() {
        log.clear()
        save()
    }

    private func save() {
        guard let url else { return }
        try? HistoryFile.save(log, to: url)
    }
}

/// The History window, opened from the menu bar. A normal window: unlike the bubble, it
/// activates the app, because you asked to look at it.
@MainActor
final class HistoryWindowController {
    private let store: HistoryStore
    private var window: NSWindow?

    init(store: HistoryStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let window = ClosableWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 560),
                                        styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                                        backing: .buffered, defer: false)
            window.title = "History"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 420, height: 300)
            window.contentView = NSHostingView(rootView: HistoryView(store: store))
            window.center()
            window.setFrameAutosaveName("History")
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// ⌘W closes it (a menu bar app has no File menu to do that).
final class ClosableWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Views

private struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.log.entries.isEmpty {
                ContentUnavailableView("Nothing yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Drop an image on the bubble. Everything you make shows up here."))
            } else {
                List(store.log.entries) { entry in
                    HistoryRow(entry: entry, onRemove: { store.remove(entry.id) })
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 420, minHeight: 300)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("History").font(.system(size: 20, weight: .semibold))
                Text(summary).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Clear History…") { confirmingClear = true }
                .disabled(store.log.entries.isEmpty)
                .confirmationDialog("Clear the history?", isPresented: $confirmingClear) {
                    Button("Clear History", role: .destructive) { store.clear() }
                } message: {
                    Text("This only forgets the list. The files themselves stay where they are.")
                }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 12)
    }

    private var summary: String {
        let count = store.log.entries.count
        guard count > 0 else { return "Kept on this Mac only." }
        let files = count == 1 ? "1 file" : "\(count) files"
        let saved = store.log.savedBytes
        return saved > 0 ? "\(files) · saved \(ByteCount.describe(saved)) in total" : files
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let onRemove: () -> Void
    @State private var thumbnail: NSImage?

    private var exists: Bool { FileManager.default.fileExists(atPath: entry.output.path) }

    var body: some View {
        HStack(spacing: 12) {
            preview
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.output.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(exists ? "\(entry.summary) · \(entry.date.formatted(.relative(presentation: .named)))"
                            : "Moved or deleted")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.changeText)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(entry.outputBytes < entry.inputBytes ? Color.green : Color.secondary)
                Text("\(ByteCount.describe(entry.inputBytes)) → \(ByteCount.describe(entry.outputBytes))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([entry.output])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
            .accessibilityLabel("Show in Finder")
            .disabled(!exists)
        }
        .padding(.vertical, 4)
        .opacity(exists ? 1 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if exists { NSWorkspace.shared.activateFileViewerSelecting([entry.output]) }
        }
        .onDrag { NSItemProvider(contentsOf: entry.output) ?? NSItemProvider() }
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.output]) }.disabled(!exists)
            Button("Open") { NSWorkspace.shared.open(entry.output) }.disabled(!exists)
            Button("Copy") { Clipboard.put([entry.output], picture: nil) }.disabled(!exists)
            Button("Show Original in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.input]) }
            Divider()
            Button("Remove from History", action: onRemove)
        }
        .task(id: entry.id) {
            guard exists else { return }
            thumbnail = await Thumbnails.make(for: entry.output, side: 40, scale: NSScreen.main?.backingScaleFactor ?? 2).image
        }
        .accessibilityElement(children: .combine)
    }

    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Group {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
            } else {
                shape.fill(Color.primary.opacity(0.08))
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(shape)
    }
}
