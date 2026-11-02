import XCTest
@testable import Droptimize

// Portable: also run on Linux by scripts/check-linux.sh.
final class UpdateTests: XCTestCase {
    // What scripts/sign-update.swift writes (its `feed` command).
    private let published = """
    {
      "build" : 57,
      "minimumSystemVersion" : "14.0",
      "notes" : "Faster GIFs.\\nFixes the first launch.",
      "signature" : "zNHcgnAVhsswymWnkN8wD5gPE27+EtXSXve6D5Ked3P6Qs/Ajuo5u4wVowulfDM2JguNH7ZyJ7FflicGmMs/BQ==",
      "url" : "https://github.com/bimanshu/Droptimize/releases/download/stable/Droptimize-57.zip",
      "version" : "1.0.0"
    }
    """

    private func feed(build: Int = 57, minimum: String = "14.0") -> UpdateFeed {
        UpdateFeed(version: "1.0.0", build: build, url: URL(string: "https://example.com/Droptimize.zip")!,
                   signature: "c2ln", notes: "", minimumSystemVersion: minimum)
    }

    private let sonoma = OperatingSystemVersion(majorVersion: 14, minorVersion: 6, patchVersion: 1)

    func testReadsTheFeedCIPublishes() throws {
        let feed = try XCTUnwrap(UpdateFeed.decode(Data(published.utf8)))
        XCTAssertEqual(feed.version, "1.0.0")
        XCTAssertEqual(feed.build, 57)
        XCTAssertEqual(feed.url.lastPathComponent, "Droptimize-57.zip")
        XCTAssertEqual(feed.notes, "Faster GIFs.\nFixes the first launch.")
        XCTAssertEqual(feed.minimumSystemVersion, "14.0")

        // The same fields the script writes; scripts/sign-update.swift's self-test checks its side.
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(feed)) as? [String: Any])
        XCTAssertEqual(Set(encoded.keys), ["version", "build", "url", "signature", "notes", "minimumSystemVersion"])
    }

    func testRefusesFeedsItCantUse() {
        let plainHTTP = published.replacingOccurrences(of: "https://github.com", with: "http://github.com")
        XCTAssertNil(UpdateFeed.decode(Data(plainHTTP.utf8)), "downloads only over https")
        XCTAssertNil(UpdateFeed.decode(Data(published.replacingOccurrences(of: "57,", with: "0,").utf8)))
        XCTAssertNil(UpdateFeed.decode(Data(#"{"version": "1.0.0", "build": 57}"#.utf8)), "fields missing")
        XCTAssertNil(UpdateFeed.decode(Data("<html>Not Found</html>".utf8)))
        let unsigned = published.replacingOccurrences(of: #""signature" : "zNHc"#, with: #""signature" : "", "x" : "zNHc"#)
        XCTAssertNil(UpdateFeed.decode(Data(unsigned.utf8)))
    }

    func testOffersOnlyNewerBuildsThisMacCanRun() {
        XCTAssertEqual(Update.offer(feed(build: 57), currentBuild: 42, system: sonoma, skippedBuild: nil), .available)
        XCTAssertEqual(Update.offer(feed(build: 42), currentBuild: 42, system: sonoma, skippedBuild: nil), .upToDate)
        XCTAssertEqual(Update.offer(feed(build: 40), currentBuild: 42, system: sonoma, skippedBuild: nil), .upToDate,
                       "a preview build newer than the last stable one is never offered an older one")
        XCTAssertEqual(Update.offer(feed(build: 57, minimum: "15.0"), currentBuild: 42, system: sonoma, skippedBuild: nil),
                       .needsSystem("15.0"))
        XCTAssertEqual(Update.offer(feed(build: 57), currentBuild: 42, system: sonoma, skippedBuild: 57), .skipped)
        XCTAssertEqual(Update.offer(feed(build: 60), currentBuild: 42, system: sonoma, skippedBuild: 57), .available,
                       "skipping one version doesn't skip the next")
    }

    func testSystemVersions() throws {
        let full = try XCTUnwrap(Update.systemVersion("14.2.1"))
        XCTAssertEqual([full.majorVersion, full.minorVersion, full.patchVersion], [14, 2, 1])
        let major = try XCTUnwrap(Update.systemVersion("15"))
        XCTAssertEqual([major.majorVersion, major.minorVersion, major.patchVersion], [15, 0, 0])
        for bad in ["", "14.", "14.x", "1.2.3.4", "-1", "fourteen"] {
            XCTAssertNil(Update.systemVersion(bad), bad)
        }
        XCTAssertTrue(feed(minimum: "14.6.1").runs(on: sonoma))
        XCTAssertFalse(feed(minimum: "14.7").runs(on: sonoma))
        XCTAssertTrue(feed(minimum: "13.0").runs(on: sonoma))
        XCTAssertFalse(feed(minimum: "garbage").runs(on: sonoma), "an unreadable minimum is never offered")
    }

    func testChecksAboutOnceADay() {
        let last = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(Update.isDue(lastChecked: nil, at: last), "never checked")
        XCTAssertFalse(Update.isDue(lastChecked: last, at: last.addingTimeInterval(23 * 3600)))
        XCTAssertTrue(Update.isDue(lastChecked: last, at: last.addingTimeInterval(24 * 3600)))
        XCTAssertTrue(Update.isDue(lastChecked: last, at: last.addingTimeInterval(-3600)), "the clock went back")
        XCTAssertEqual(Update.feedURL.absoluteString,
                       "https://github.com/bimanshu/Droptimize/releases/download/stable/update.json")
        XCTAssertEqual(Data(base64Encoded: Update.publicKey)?.count, 32, "a raw Ed25519 public key")
    }

    func testReplacesItselfOnlyWhereItCan() {
        XCTAssertNil(Update.placeProblem(appPath: "/Applications/Droptimize.app", folderIsWritable: true, volumeIsReadOnly: false))
        XCTAssertEqual(Update.placeProblem(appPath: "/private/var/folders/x/T/AppTranslocation/1A2B/d/Droptimize.app",
                                           folderIsWritable: false, volumeIsReadOnly: true), .translocated)
        XCTAssertEqual(Update.placeProblem(appPath: "/Volumes/Droptimize/Droptimize.app", folderIsWritable: false,
                                           volumeIsReadOnly: true), .readOnly, "still on the disk image")
        XCTAssertEqual(Update.placeProblem(appPath: "/Applications/Droptimize.app", folderIsWritable: false,
                                           volumeIsReadOnly: false), .readOnly, "an Applications folder this user can't change")
        XCTAssertTrue(Update.PlaceProblem.translocated.message.contains("Applications folder"))
    }

    // MARK: The swap script

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("UpdateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    /// A stand-in app: a folder holding one file that says which copy it is.
    private func makeApp(at url: URL, saying text: String) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url.appendingPathComponent("which"))
    }

    private func which(_ app: URL) -> String? {
        (try? Data(contentsOf: app.appendingPathComponent("which"))).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Starts a process that ends after `seconds` (0: already ended), for the script to wait on.
    private func process(lasting seconds: Double) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", seconds > 0 ? "sleep \(seconds)" : "true"]
        try process.run()
        if seconds == 0 { process.waitUntilExit() }
        return process
    }

    /// Runs `Update.swapScript` like `UpdateInstaller.startSwap`, but waits for it.
    @discardableResult
    private func swap(pid: Int32, target: URL, new: URL, work: URL) throws -> Int32 {
        let script = work.deletingLastPathComponent().appendingPathComponent("swap-\(UUID().uuidString).sh")
        try Data(Update.swapScript.utf8).write(to: script)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(pid), target.path, new.path, work.path]
        var environment = ProcessInfo.processInfo.environment
        environment["DROPTIMIZE_NO_OPEN"] = "1"
        process.environment = environment
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    func testSwapScriptReplacesTheAppOnceItQuits() throws {
        let folder = try makeFolder()
        let target = folder.appendingPathComponent("Droptimize.app")
        let new = folder.appendingPathComponent("Droptimize.app.new")
        let work = folder.appendingPathComponent("download")
        try makeApp(at: target, saying: "old")
        try makeApp(at: new, saying: "new")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let running = try process(lasting: 0.6)
        XCTAssertEqual(try swap(pid: running.processIdentifier, target: target, new: new, work: work), 0)
        XCTAssertFalse(running.isRunning, "it waited for the app to quit")
        XCTAssertEqual(which(target), "new")
        for leftover in [new, work, folder.appendingPathComponent("Droptimize.app.old")] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path), leftover.lastPathComponent)
        }
    }

    func testSwapScriptKeepsTheOldAppWhenTheNewOneIsMissing() throws {
        let folder = try makeFolder()
        let target = folder.appendingPathComponent("Droptimize.app")
        let work = folder.appendingPathComponent("download")
        try makeApp(at: target, saying: "old")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let ended = try process(lasting: 0)
        try swap(pid: ended.processIdentifier, target: target,
                 new: folder.appendingPathComponent("Droptimize.app.new"), work: work)
        XCTAssertEqual(which(target), "old", "never left without an app")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Droptimize.app.old").path))
    }
}
