import Foundation

/// The built-in updater's feed: one small JSON file that CI publishes with every stable release
/// (`.github/workflows/build.yml`, written by `scripts/sign-update.swift`). Reading it and deciding
/// what to offer is portable; downloading, checking the signature and swapping the app are in
/// `App/UpdateInstaller.swift`, the window in `App/Updater.swift`.
struct UpdateFeed: Codable, Equatable {
    /// What people see: "1.0.1".
    var version: String
    /// What's compared: the build number (`CFBundleVersion`, CI's run number).
    var build: Int
    /// The zipped app.
    var url: URL
    /// Base64 Ed25519 signature of the zip's bytes, made with the private key behind `Update.publicKey`.
    var signature: String
    /// What's new, plain text.
    var notes: String
    /// "14.0".
    var minimumSystemVersion: String

    /// Reads a feed, or nil when it isn't one we can use (only https downloads).
    static func decode(_ data: Data) -> UpdateFeed? {
        guard let feed = try? JSONDecoder().decode(UpdateFeed.self, from: data),
              feed.build > 0, feed.url.scheme == "https", !feed.signature.isEmpty
        else { return nil }
        return feed
    }

    /// Whether a Mac on `system` can run it.
    func runs(on system: OperatingSystemVersion) -> Bool {
        guard let minimum = Update.systemVersion(minimumSystemVersion) else { return false }
        return (system.majorVersion, system.minorVersion, system.patchVersion)
            >= (minimum.majorVersion, minimum.minorVersion, minimum.patchVersion)
    }
}

/// When to check, what to offer, and where the app can replace itself.
enum Update {
    /// Published by CI with each stable release; GitHub serves it. The check sends nothing about
    /// the user or their files (CORE.md Rule 4).
    static let feedURL = URL(string: "https://github.com/bimanshu/Droptimize/releases/download/stable/update.json")!
    /// The Ed25519 public key (base64 of its 32 raw bytes) that every update must be signed with.
    /// Its private half is the `UPDATE_SIGNING_KEY` secret in GitHub, never in the repository.
    static let publicKey = "tw8LgxBR8XARghweG/2B23Vo+7RHSNhz26GQFfICGOM="

    /// After launch, so starting up stays quick.  (tune)
    static let firstCheckDelay: TimeInterval = 30
    /// Then about once a day.  (tune)
    static let checkInterval: TimeInterval = 24 * 3600

    static func isDue(lastChecked: Date?, at now: Date) -> Bool {
        guard let lastChecked else { return true }
        // A clock set back makes the last check look like it's in the future: check anyway.
        let elapsed = now.timeIntervalSince(lastChecked)
        return elapsed >= checkInterval || elapsed < 0
    }

    enum Offer: Equatable {
        case upToDate
        /// Newer, and this Mac can run it.
        case available
        /// Newer, but the person chose Skip This Version.
        case skipped
        /// Newer, but needs a later macOS.
        case needsSystem(String)
    }

    /// What `feed` means for this copy of the app.
    static func offer(_ feed: UpdateFeed, currentBuild: Int, system: OperatingSystemVersion,
                      skippedBuild: Int?) -> Offer {
        guard feed.build > currentBuild else { return .upToDate }
        guard feed.runs(on: system) else { return .needsSystem(feed.minimumSystemVersion) }
        if let skippedBuild, feed.build <= skippedBuild { return .skipped }
        return .available
    }

    /// "14", "14.2" or "14.2.1"; nil otherwise.
    static func systemVersion(_ text: String) -> OperatingSystemVersion? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(parts.count), parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        let numbers = parts.compactMap { $0 } + [0, 0]
        return OperatingSystemVersion(majorVersion: numbers[0], minorVersion: numbers[1], patchVersion: numbers[2])
    }

    /// Why the app can't replace itself where it is, if it can't.
    enum PlaceProblem: Equatable {
        /// Opened straight from a download: macOS runs it from a hidden read-only copy.
        case translocated
        /// A disk image, or a folder this user can't write to.
        case readOnly

        var message: String {
            switch self {
            case .translocated, .readOnly:
                return "Droptimize can't update itself from where it is. Quit it, drag it into your Applications folder, open it from there and try again."
            }
        }
    }

    /// Whether the app at `appPath` can be swapped for a new one (portable: the caller supplies
    /// what the file system says).
    static func placeProblem(appPath: String, folderIsWritable: Bool, volumeIsReadOnly: Bool) -> PlaceProblem? {
        if appPath.contains("/AppTranslocation/") { return .translocated }
        if volumeIsReadOnly || !folderIsWritable { return .readOnly }
        return nil
    }

    /// Run by `/bin/sh` after the app quits: waits for it to exit (`$1`, its process ID), swaps the
    /// new copy (`$3`, staged beside it) in for the old one (`$2`), opens it, and removes the
    /// download folder (`$4`). If anything fails, the old copy stays and is reopened. Like
    /// `scripts/install.sh`, but the new copy was already checked by the app.
    /// `DROPTIMIZE_NO_OPEN=1` skips opening it (tests).
    static let swapScript = #"""
    pid="$1"; target="$2"; new="$3"; work="$4"
    tries=0
    while kill -0 "$pid" 2>/dev/null; do
      tries=$((tries + 1))
      if [ "$tries" -gt 150 ]; then
        echo "Droptimize didn't quit; update abandoned." >&2
        rm -rf "$new" "$work"
        exit 1
      fi
      sleep 0.2
    done
    old="$target.old"
    rm -rf "$old"
    if mv "$target" "$old"; then
      if mv "$new" "$target"; then
        rm -rf "$old"
      else
        echo "Couldn't move the new copy in; the old one stays." >&2
        mv "$old" "$target"
      fi
    else
      echo "Couldn't move the old copy aside; it stays." >&2
    fi
    rm -rf "$new" "$work"
    xattr -dr com.apple.quarantine "$target" 2>/dev/null
    if [ -z "$DROPTIMIZE_NO_OPEN" ]; then open "$target"; fi
    exit 0
    """#
}
