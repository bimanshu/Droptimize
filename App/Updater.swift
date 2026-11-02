import AppKit
import SwiftUI

/// The built-in updater (no Sparkle until there's a Developer ID; HANDOFF.md). Checks the stable
/// feed 30 s after launch and then daily, and offers a newer build in a small window that doesn't
/// take focus from the app you're in (Rule 1). Install & Relaunch downloads the signed zip, checks
/// it (`UpdateInstaller`), quits, and a small script swaps the app and reopens it.
@MainActor
final class Updater: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case checkFailed
        case needsSystem(UpdateFeed)
        case available(UpdateFeed)
        case downloading(UpdateFeed, Double)
        case installing(UpdateFeed)
    }

    @Published private(set) var phase: Phase = .idle
    /// Why the last install didn't happen, shown with the offer.
    @Published private(set) var problem: String?

    /// "0.1.0" and 42: this copy.
    let currentVersion: String
    let currentBuild: Int
    private let defaults: UserDefaults
    private let session = URLSession(configuration: .ephemeral)
    private var timer: Timer?
    private var installing: Task<Void, Never>?
    private lazy var window = UpdateWindowController(updater: self)

    private static let lastCheckedKey = "update.lastChecked"
    private static let skippedBuildKey = "update.skippedBuild"
    /// Set just before quitting to install, to tell at the next launch whether it worked.
    private static let installingBuildKey = "update.installingBuild"

    /// Debug builds (run from Xcode) only check when asked.
    static var checksAutomatically: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        currentBuild = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap { Int($0) } ?? 0
    }

    /// The version on offer, for the menu.
    var availableVersion: String? {
        switch phase {
        case .available(let feed), .downloading(let feed, _), .installing(let feed): return feed.version
        default: return nil
        }
    }

    private var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    /// Starts the background checks (CORE.md Rule 4: one small JSON file from GitHub).
    func start() {
        let failedInstall = noteLastInstall()
        guard Self.checksAutomatically else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Update.firstCheckDelay * 1_000_000_000))
            await self?.checkIfDue(force: failedInstall)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkIfDue() }
        }
    }

    /// Menu bar → Check for Updates…: shows the window (activating the app: you asked) and checks.
    func checkNow() {
        window.show(activating: true)
        guard !isBusy else { return }
        Task { await check(userAsked: true) }
    }

    func install() {
        guard case .available(let feed) = phase, installing == nil else { return }
        let app = Bundle.main.bundleURL
        if let place = UpdateInstaller.placeProblem(for: app) {
            problem = place.message
            return
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "com.droptimize.app"
        problem = nil
        phase = .downloading(feed, 0)
        installing = Task { [weak self] in
            var leftovers: [URL] = []
            do {
                let work = try UpdateInstaller.makeWorkFolder(build: feed.build)
                leftovers.append(work)
                let zip = try await UpdateInstaller.download(feed.url, into: work) { fraction in
                    Task { @MainActor in self?.downloaded(fraction, of: feed) }
                }
                try Task.checkCancellation()
                self?.phase = .installing(feed)
                let staged = try await Task.detached(priority: .userInitiated) {
                    let newApp = try UpdateInstaller.unpack(zip, feed: feed, into: work, bundleID: bundleID)
                    return try UpdateInstaller.stage(newApp, beside: app)
                }.value
                leftovers.append(staged)
                try UpdateInstaller.startSwap(target: app, staged: staged, work: work)
                self?.defaults.set(feed.build, forKey: Self.installingBuildKey)
                NSApp.terminate(nil)
            } catch {
                for leftover in leftovers { try? FileManager.default.removeItem(at: leftover) }
                guard let self else { return }
                self.installing = nil
                self.phase = .available(feed)
                if !(error is CancellationError) {
                    self.problem = (error as? UpdateInstaller.Failure)?.message ?? UpdateInstaller.Failure.couldNotInstall.message
                }
            }
        }
    }

    func cancelDownload() {
        installing?.cancel()
    }

    /// Later: the window closes; the menu still offers it, and the next daily check shows it again.
    func later() {
        window.close()
    }

    /// Skip This Version: not offered again until a newer one comes out (asking still shows it).
    func skip() {
        guard case .available(let feed) = phase else { return }
        defaults.set(feed.build, forKey: Self.skippedBuildKey)
        phase = .idle
        problem = nil
        window.close()
    }

    func dismiss() {
        if !isBusy, availableVersion == nil { phase = .idle }
        window.close()
    }

    // MARK: Checking

    private func checkIfDue(force: Bool = false) async {
        let last = defaults.object(forKey: Self.lastCheckedKey) as? Date
        guard force || Update.isDue(lastChecked: last, at: Date()) else { return }
        await check(userAsked: false)
    }

    /// Asked: every outcome shows in the window. On its own: only a newer build does, so a
    /// background check never disturbs what the window shows.
    private func check(userAsked: Bool) async {
        guard !isBusy else { return }
        if userAsked { phase = .checking }
        let answer = await fetchFeed()
        if case .unreachable = answer {
            if userAsked { phase = .checkFailed }
            return
        }
        defaults.set(Date(), forKey: Self.lastCheckedKey)
        guard case .feed(let feed) = answer else {
            if userAsked { phase = .upToDate }
            return
        }
        let skipped = userAsked ? nil : defaults.object(forKey: Self.skippedBuildKey) as? Int
        switch Update.offer(feed, currentBuild: currentBuild, system: ProcessInfo.processInfo.operatingSystemVersion,
                            skippedBuild: skipped) {
        case .available:
            phase = .available(feed)
            if !userAsked, !window.isVisible { window.show(activating: false) }
        case .needsSystem:
            if userAsked { phase = .needsSystem(feed) }
        case .upToDate, .skipped:
            if userAsked { phase = .upToDate }
        }
    }

    private enum Answer {
        case feed(UpdateFeed)
        /// No stable release yet (404).
        case noRelease
        /// Offline, or an answer we can't use.
        case unreachable
    }

    private func fetchFeed() async -> Answer {
        let request = URLRequest(url: Update.feedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        guard let (data, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode
        else { return .unreachable }
        if status == 404 { return .noRelease }
        guard status == 200, let feed = UpdateFeed.decode(data) else { return .unreachable }
        return .feed(feed)
    }

    private func downloaded(_ fraction: Double, of feed: UpdateFeed) {
        if case .downloading(feed, _) = phase { phase = .downloading(feed, fraction) }
    }

    /// Whether the install started before the last quit failed (the build didn't change). Says so
    /// with the next offer.
    private func noteLastInstall() -> Bool {
        guard let expected = defaults.object(forKey: Self.installingBuildKey) as? Int else { return false }
        defaults.removeObject(forKey: Self.installingBuildKey)
        guard currentBuild < expected else { return false }
        problem = "The last update didn't install, so you still have \(currentVersion) (build \(currentBuild)). Try again."
        return true
    }
}

/// The update window: a small panel that shows without taking focus when an update turns up on
/// its own, and like a normal window when you ask.
@MainActor
final class UpdateWindowController {
    private unowned let updater: Updater
    private var panel: NSPanel?

    init(updater: Updater) {
        self.updater = updater
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(activating: Bool) {
        if panel == nil {
            let panel = UpdatePanel(contentRect: CGRect(x: 0, y: 0, width: 440, height: 200),
                                    styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
            let hosting = NSHostingController(rootView: UpdateView(updater: updater))
            hosting.sizingOptions = [.preferredContentSize]
            panel.contentViewController = hosting
            panel.title = "Droptimize Update"
            panel.titlebarAppearsTransparent = true
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.collectionBehavior = [.moveToActiveSpace]
            panel.isReleasedWhenClosed = false
            panel.center()
            self.panel = panel
        }
        if activating {
            NSApp.activate()
            panel?.makeKeyAndOrderFront(nil)
        } else {
            panel?.orderFrontRegardless()
        }
    }

    func close() {
        panel?.close()
    }
}

/// Takes clicks and the keyboard without activating the app; ⌘W closes it.
private final class UpdatePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private struct UpdateView: View {
    @ObservedObject var updater: Updater

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22)
        .padding(.top, 30)
        .padding(.bottom, 20)
        .frame(width: 440)
    }

    private var current: String {
        "\(updater.currentVersion) (build \(updater.currentBuild))"
    }

    @ViewBuilder
    private var content: some View {
        switch updater.phase {
        case .idle, .checking:
            title("Checking for updates…")
            ProgressView().controlSize(.small)
        case .upToDate:
            title("You're up to date")
            line("Droptimize \(current) is the newest version.")
            buttons { Button("OK", action: updater.dismiss).keyboardShortcut(.defaultAction) }
        case .checkFailed:
            title("Couldn't check for updates")
            line("Check your internet connection and try again.")
            buttons {
                Button("OK", action: updater.dismiss).keyboardShortcut(.cancelAction)
                Button("Try Again", action: updater.checkNow).keyboardShortcut(.defaultAction)
            }
        case .needsSystem(let feed):
            title("Droptimize \(feed.version) needs a newer macOS")
            line("It runs on macOS \(feed.minimumSystemVersion) or later. You have macOS \(ProcessInfo.processInfo.operatingSystemVersionString).")
            buttons { Button("OK", action: updater.dismiss).keyboardShortcut(.defaultAction) }
        case .available(let feed):
            title("Droptimize \(feed.version) is available")
            line("You have \(current). It installs in a few seconds and reopens by itself.")
            notes(feed.notes)
            if let problem = updater.problem {
                Text(problem)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Skip This Version", action: updater.skip)
                Spacer()
                Button("Later", action: updater.later).keyboardShortcut(.cancelAction)
                Button("Install & Relaunch", action: updater.install).keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        case .downloading(let feed, let fraction):
            title("Downloading Droptimize \(feed.version)…")
            ProgressView(value: fraction)
            buttons { Button("Cancel", action: updater.cancelDownload).keyboardShortcut(.cancelAction) }
        case .installing(let feed):
            title("Installing Droptimize \(feed.version)…")
            ProgressView().progressViewStyle(.linear)
            line("Droptimize will quit and reopen in a moment.")
        }
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 15, weight: .semibold))
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func notes(_ text: String) -> some View {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ScrollView {
                Text(text)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 160)
            .fixedSize(horizontal: false, vertical: true)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
        }
    }

    private func buttons<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Spacer()
            content()
        }
        .padding(.top, 4)
    }
}
