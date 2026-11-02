import CryptoKit
import Foundation
import Security

/// Downloads, checks and installs an update (`App/Updater.swift` drives it; the feed and the rules
/// are in `Store/UpdateFeed.swift`). The app is ad-hoc signed, so its code signature only shows
/// the files weren't damaged, not who built them: the Ed25519 signature over the zip, made in CI
/// with a key only GitHub holds (`scripts/sign-update.swift`), is what makes an update trustworthy.
enum UpdateInstaller {
    enum Failure: Error, Equatable {
        case download
        case badSignature
        /// Not a zip, no app inside, or its code signature is broken.
        case damaged
        /// Another app, or another build than the feed promised.
        case wrongApp
        case place(Update.PlaceProblem)
        case couldNotInstall

        var message: String {
            switch self {
            case .download: return "Couldn't download the update. Check your connection and try again."
            case .badSignature: return "The download isn't signed by Droptimize, so it wasn't installed."
            case .damaged: return "The download was damaged, so it wasn't installed. Try again."
            case .wrongApp: return "The download wasn't the expected version of Droptimize, so it wasn't installed."
            case .place(let problem): return problem.message
            case .couldNotInstall: return "Couldn't install the update here. Try again, or reinstall Droptimize."
            }
        }
    }

    /// Whether `signature` (base64) is `publicKey`'s (base64) Ed25519 signature of `data`.
    static func isSigned(_ data: Data, signature: String, publicKey: String = Update.publicKey) -> Bool {
        guard let keyData = Data(base64Encoded: publicKey), let signatureData = Data(base64Encoded: signature),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else { return false }
        return key.isValidSignature(signatureData, for: data)
    }

    /// Whether the app at `app` can be swapped for a new one where it is.
    static func placeProblem(for app: URL) -> Update.PlaceProblem? {
        let folder = app.deletingLastPathComponent()
        let readOnly = (try? folder.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        let files = FileManager.default
        return Update.placeProblem(appPath: app.path,
                                   folderIsWritable: files.isWritableFile(atPath: folder.path)
                                       && files.isWritableFile(atPath: app.path),
                                   volumeIsReadOnly: readOnly)
    }

    /// A fresh folder for one update's download.
    static func makeWorkFolder(build: Int) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Droptimize-update-\(build)")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Downloads `url` into `folder`, reporting progress from 0 to 1. Cancelling the task stops it.
    static func download(_ url: URL, into folder: URL,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let watcher = ProgressWatcher(report: progress)
        let (location, response): (URL, URLResponse)
        do {
            (location, response) = try await session.download(from: url, delegate: watcher)
        } catch {
            try Task.checkCancellation()
            throw Failure.download
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.download }
        let zip = folder.appendingPathComponent("Droptimize.zip")
        try? FileManager.default.removeItem(at: zip)
        try FileManager.default.moveItem(at: location, to: zip)
        return zip
    }

    /// Checks the downloaded zip against `feed` and unpacks it: the new app, ready to stage.
    /// Slow-ish (reads and unzips a few MB), so call it off the main thread.
    static func unpack(_ zip: URL, feed: UpdateFeed, into folder: URL, bundleID: String,
                       publicKey: String = Update.publicKey) throws -> URL {
        guard let data = try? Data(contentsOf: zip) else { throw Failure.damaged }
        guard isSigned(data, signature: feed.signature, publicKey: publicKey) else { throw Failure.badSignature }

        let unzipped = folder.appendingPathComponent("unzipped")
        try? FileManager.default.removeItem(at: unzipped)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unzipped.path]) else { throw Failure.damaged }
        let apps = (try? FileManager.default.contentsOfDirectory(at: unzipped, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "app" } ?? []
        guard apps.count == 1, let app = apps.first else { throw Failure.damaged }

        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        guard info?["CFBundleIdentifier"] as? String == bundleID,
              info?["CFBundleVersion"] as? String == String(feed.build)
        else { throw Failure.wrongApp }
        guard hasValidCodeSignature(app) else { throw Failure.damaged }
        return app
    }

    /// Copies the new app in beside the running one (`Droptimize.app.new`), so the swap after
    /// quitting is two renames on the same disk.
    static func stage(_ newApp: URL, beside current: URL) throws -> URL {
        let staged = current.deletingLastPathComponent().appendingPathComponent(current.lastPathComponent + ".new")
        try? FileManager.default.removeItem(at: staged)
        guard run("/usr/bin/ditto", [newApp.path, staged.path]) else {
            try? FileManager.default.removeItem(at: staged)
            throw Failure.couldNotInstall
        }
        return staged
    }

    /// Starts `Update.swapScript`, which outlives the app: it waits for process `pid` to quit,
    /// swaps `staged` in for `target`, opens it and removes `work`. Quit right after.
    static func startSwap(target: URL, staged: URL, work: URL,
                          pid: Int32 = ProcessInfo.processInfo.processIdentifier) throws {
        let script = work.appendingPathComponent("swap.sh")
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("Droptimize-update.log")
        do {
            try Data(Update.swapScript.utf8).write(to: script)
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script.path, String(pid), target.path, staged.path, work.path]
            process.standardInput = FileHandle.nullDevice
            let output = try FileHandle(forWritingTo: log)
            process.standardOutput = output
            process.standardError = output
            try process.run()
        } catch {
            throw Failure.couldNotInstall
        }
    }

    /// Whether `app`'s code signature is intact (ad-hoc signed: proves the files weren't damaged).
    static func hasValidCodeSignature(_ app: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        return SecStaticCodeCheckValidityWithErrors(code, flags, nil, nil) == errSecSuccess
    }

    /// Runs a tool and waits; whether it succeeded.
    private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

/// Reports a download's progress: `URLSession` hands over the task as it's created.
private final class ProgressWatcher: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let report: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?

    init(report: @escaping @Sendable (Double) -> Void) {
        self.report = report
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [report] progress, _ in
            report(progress.fractionCompleted)
        }
    }
}
