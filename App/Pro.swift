import AppKit
import SwiftUI
import SystemConfiguration

/// Pro and the free plan's daily count (CORE.md §8.1), saved in UserDefaults. The key would
/// belong in the Keychain, but ad-hoc signed builds change identity with every update and the
/// Keychain would ask for access each time; move it there with Developer ID signing (Phase 3).
@MainActor
final class ProStore: ObservableObject {
    @Published private(set) var license: License?
    @Published private(set) var allowance: FreeAllowance
    @Published private(set) var isWorking = false
    /// The last thing that went wrong, for the Pro window.
    @Published var problem: String?

    let isSelling: Bool
    private let defaults: UserDefaults
    private let now: () -> Date
    private let session: URLSession
    private static let licenseDefaultsKey = "pro.license"
    private static let allowanceDefaultsKey = "pro.allowance"

    init(defaults: UserDefaults = .standard, selling: Bool = StoreConfig.isSelling,
         now: @escaping () -> Date = { Date() }, session: URLSession = .shared) {
        self.defaults = defaults
        isSelling = selling
        self.now = now
        self.session = session
        license = defaults.data(forKey: Self.licenseDefaultsKey).flatMap { try? JSONDecoder().decode(License.self, from: $0) }
        allowance = defaults.data(forKey: Self.allowanceDefaultsKey)
            .flatMap { try? JSONDecoder().decode(FreeAllowance.self, from: $0) } ?? FreeAllowance()
    }

    var isPro: Bool { license?.isPro(at: now()) ?? false }
    /// Counting files: only once Pro is on sale, and only without Pro.
    var isLimited: Bool { isSelling && !isPro }
    var remainingToday: Int { allowance.remaining(on: today) }
    private var today: String { FreeAllowance.day(of: now()) }

    /// How many of `files` may run now.
    func grant(_ files: Int) -> Int {
        isLimited ? allowance.grant(files, on: today) : files
    }

    /// Counts files that were made.
    func record(_ files: Int) {
        guard isLimited, files > 0 else { return }
        allowance.record(files, on: today)
        save()
    }

    // MARK: License

    func activate(_ typed: String) async {
        let key = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !isWorking else { return }
        isWorking = true
        problem = nil
        defer { isWorking = false }
        do {
            let data = try await send(.activate, ["license_key": key, "instance_name": Self.macName])
            switch LemonSqueezy.activation(data, key: key, at: now()) {
            case .success(let activated):
                license = activated
                save()
                if !activated.isActive { problem = "This key isn't active." }
            case .failure(let failure):
                // Someone else's product: give the activation straight back.
                if case .notDroptimize(let instance?) = failure {
                    _ = try? await send(.deactivate, ["license_key": key, "instance_id": instance])
                }
                problem = failure.message
            }
        } catch {
            problem = "Couldn't reach the license server. Check your connection and try again."
        }
    }

    /// Frees this Mac's activation so the key can be used on another one.
    func deactivate() async {
        guard let current = license, !isWorking else { return }
        isWorking = true
        problem = nil
        defer { isWorking = false }
        do {
            let data = try await send(.deactivate, ["license_key": current.key, "instance_id": current.instanceID])
            let answer = try? JSONDecoder().decode(LemonSqueezy.Response.self, from: data)
            if answer?.deactivated == true || answer?.error?.lowercased().contains("not found") == true {
                license = nil
                save()
            } else {
                problem = answer?.error ?? "Couldn't deactivate it. Try again later."
            }
        } catch {
            problem = "Couldn't reach the license server. Check your connection and try again."
        }
    }

    /// Asks the server whether the license still stands: when it's due, or now with `force`.
    /// Without a connection nothing changes (and Pro keeps working through the grace period).
    func check(force: Bool = false) async {
        guard let current = license, force || current.needsCheck(at: now()), !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        guard let data = try? await send(.validate, ["license_key": current.key, "instance_id": current.instanceID]),
              let updated = LemonSqueezy.validation(data, license: current, at: now()) else { return }
        license = updated
        save()
    }

    /// Forgets a license that's no longer active.
    func removeLicense() {
        license = nil
        problem = nil
        save()
    }

    private func send(_ endpoint: LemonSqueezy.Endpoint, _ fields: [String: String]) async throws -> Data {
        let (data, response) = try await session.data(for: LemonSqueezy.request(endpoint, fields))
        // Busy or broken servers say nothing about the key.
        if let http = response as? HTTPURLResponse, http.statusCode == 429 || http.statusCode >= 500 {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func save() {
        if let license, let data = try? JSONEncoder().encode(license) {
            defaults.set(data, forKey: Self.licenseDefaultsKey)
        } else {
            defaults.removeObject(forKey: Self.licenseDefaultsKey)
        }
        if let data = try? JSONEncoder().encode(allowance) {
            defaults.set(data, forKey: Self.allowanceDefaultsKey)
        }
    }

    /// The name the activation shows under in the Lemon Squeezy dashboard.
    private static var macName: String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
    }
}

/// The Pro window, from the menu bar or by clicking the bubble when the free files run out.
/// A normal window: it activates the app, since you asked for it.
@MainActor
final class ProWindowController {
    private let store: ProStore
    private var window: NSWindow?

    init(store: ProStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: ProView(store: store))
            hosting.sizingOptions = [.preferredContentSize]
            let window = ClosableWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.title = "Droptimize Pro"
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        Task { await store.check(force: true) }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct ProView: View {
    @ObservedObject var store: ProStore
    @State private var typedKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                LogoMark(size: 40)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Droptimize Pro")
                        .font(.system(size: 20, weight: .semibold))
                    Text(status)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let license = store.license, store.isPro {
                owned(license)
            } else {
                if let license = store.license { ended(license) }
                offer
                keyEntry
            }

            if let problem = store.problem {
                Text(problem)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 34)
        .padding(.bottom, 24)
        .frame(width: 380)
    }

    private var status: String {
        if let license = store.license, store.isPro { return "Pro · \(license.plan.title). Thank you!" }
        if !store.isSelling { return "Pro goes on sale soon. Until then, everything is unlimited." }
        let left = store.remainingToday
        return "Free plan: \(left) of \(FreeAllowance.perDay) files left today."
    }

    // MARK: Without Pro

    private var offer: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                benefit("infinity", "Unlimited files, every day")
                benefit("photo.on.rectangle.angled", "Every action, for images and video")
                benefit("square.stack.3d.up", "Whole folders in one drop")
            }
            HStack(spacing: 10) {
                buy("\(StoreConfig.monthlyPrice) a month", detail: "Cancel any time", url: StoreConfig.monthlyCheckout,
                    prominent: false)
                buy("\(StoreConfig.lifetimePrice) once", detail: "Yours for life", url: StoreConfig.lifetimeCheckout,
                    prominent: true)
            }
            .disabled(!store.isSelling)
        }
    }

    private func benefit(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.system(size: 13))
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
        }
    }

    @ViewBuilder
    private func buy(_ title: String, detail: String, url: URL?, prominent: Bool) -> some View {
        let label = VStack(spacing: 1) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail).font(.system(size: 11)).opacity(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        if prominent {
            Button { open(url) } label: { label }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        } else {
            Button { open(url) } label: { label }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }

    private var keyEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Already bought it? Paste the license key from your email.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack {
                TextField("License key", text: $typedKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit(activate)
                if store.isWorking {
                    ProgressView().controlSize(.small)
                }
                Button("Activate", action: activate)
                    .disabled(typedKey.trimmingCharacters(in: .whitespaces).isEmpty || store.isWorking)
            }
            .disabled(!store.isSelling)
        }
    }

    private func ended(_ license: License) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your Pro license (\(license.maskedKey)) isn't active any more. Renew below, or check again if you just did.")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Check Again") { Task { await store.check(force: true) } }
                Button("Remove Key") { store.removeLicense() }
            }
            .disabled(store.isWorking)
        }
    }

    // MARK: With Pro

    private func owned(_ license: License) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Plan").foregroundStyle(.secondary)
                    Text(license.plan.title)
                }
                GridRow {
                    Text("Key").foregroundStyle(.secondary)
                    Text(license.maskedKey).font(.system(size: 12, design: .monospaced))
                }
                if let email = license.email {
                    GridRow {
                        Text("Email").foregroundStyle(.secondary)
                        Text(email)
                    }
                }
            }
            .font(.system(size: 12))
            HStack {
                if license.plan == .monthly {
                    Button("Manage Subscription") { open(StoreConfig.manageSubscription) }
                }
                Button("Deactivate on This Mac") { Task { await store.deactivate() } }
                    .disabled(store.isWorking)
                if store.isWorking {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private func activate() {
        let key = typedKey
        Task {
            await store.activate(key)
            if store.isPro { typedKey = "" }
        }
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
