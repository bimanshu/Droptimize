import CryptoKit
import XCTest
@testable import Droptimize

// macOS only (CryptoKit, codesign, ditto); runs in CI and Xcode, not in scripts/check-linux.sh.
final class UpdaterMacTests: XCTestCase {
    private var folder: URL!
    private let key = Curve25519.Signing.PrivateKey()
    private var publicKey: String { key.publicKey.rawRepresentation.base64EncodedString() }

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("UpdaterMacTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func sign(_ data: Data) throws -> String {
        try key.signature(for: data).base64EncodedString()
    }

    func testOnlyUpdatesSignedWithOurKeyPass() throws {
        let zip = Data("the app".utf8)
        let signature = try sign(zip)
        XCTAssertTrue(UpdateInstaller.isSigned(zip, signature: signature, publicKey: publicKey))
        XCTAssertFalse(UpdateInstaller.isSigned(Data("the app!".utf8), signature: signature, publicKey: publicKey),
                       "changed after signing")
        let stranger = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        XCTAssertFalse(UpdateInstaller.isSigned(zip, signature: signature, publicKey: stranger), "someone else's key")
        XCTAssertFalse(UpdateInstaller.isSigned(zip, signature: "not base64!", publicKey: publicKey))
        XCTAssertFalse(UpdateInstaller.isSigned(zip, signature: "", publicKey: publicKey))
        XCTAssertFalse(UpdateInstaller.isSigned(zip, signature: signature), "the app's own key didn't make it")
        XCTAssertNoThrow(try Curve25519.Signing.PublicKey(rawRepresentation: XCTUnwrap(Data(base64Encoded: Update.publicKey))),
                         "the built-in key is a real Ed25519 key")
    }

    // MARK: Unpacking

    @discardableResult
    private func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// A tiny ad-hoc signed app, zipped like CI zips Droptimize. `damage` changes a sealed file
    /// after signing.
    private func makeZip(bundleID: String = "com.droptimize.app", build: Int = 57, damage: Bool = false) throws -> URL {
        let output = folder.appendingPathComponent("build-\(UUID().uuidString)")
        let app = output.appendingPathComponent("Droptimize.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: contents.appendingPathComponent("MacOS/Droptimize").path)
        let info: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleVersion": String(build),
                                   "CFBundleExecutable": "Droptimize", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try Data("hello".utf8).write(to: contents.appendingPathComponent("Resources/note.txt"))
        XCTAssertEqual(try run("/usr/bin/codesign", ["--force", "--sign", "-", app.path]), 0)
        if damage { try Data("changed".utf8).write(to: contents.appendingPathComponent("Resources/note.txt")) }
        let zip = output.appendingPathComponent("Droptimize.zip")
        XCTAssertEqual(try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path]), 0)
        return zip
    }

    private func feed(for zip: URL, build: Int = 57, signature: String? = nil) throws -> UpdateFeed {
        UpdateFeed(version: "1.0.0", build: build, url: URL(string: "https://example.com/Droptimize-\(build).zip")!,
                   signature: try signature ?? sign(Data(contentsOf: zip)), notes: "", minimumSystemVersion: "14.0")
    }

    private func unpack(_ zip: URL, _ feed: UpdateFeed) throws -> URL {
        let work = folder.appendingPathComponent("work-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        return try UpdateInstaller.unpack(zip, feed: feed, into: work, bundleID: "com.droptimize.app", publicKey: publicKey)
    }

    private func assertFails(_ expected: UpdateInstaller.Failure, _ zip: URL, _ feed: UpdateFeed,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try unpack(zip, feed), file: file, line: line) { error in
            XCTAssertEqual(error as? UpdateInstaller.Failure, expected, file: file, line: line)
        }
    }

    func testUnpacksASignedUpdate() throws {
        let zip = try makeZip()
        let app = try unpack(zip, feed(for: zip))
        XCTAssertEqual(app.lastPathComponent, "Droptimize.app")
        XCTAssertTrue(UpdateInstaller.hasValidCodeSignature(app))
    }

    func testRefusesAnythingElse() throws {
        let zip = try makeZip()
        assertFails(.badSignature, zip, try feed(for: zip, signature: sign(Data("another zip".utf8))))
        assertFails(.wrongApp, zip, try feed(for: zip, build: 58))

        let otherApp = try makeZip(bundleID: "com.example.other")
        assertFails(.wrongApp, otherApp, try feed(for: otherApp))

        let damaged = try makeZip(damage: true)
        assertFails(.damaged, damaged, try feed(for: damaged))

        let notAZip = folder.appendingPathComponent("page.zip")
        try Data("<html>Not Found</html>".utf8).write(to: notAZip)
        assertFails(.damaged, notAZip, try feed(for: notAZip))
    }

    func testStagesBesideTheRunningApp() throws {
        let zip = try makeZip()
        let app = try unpack(zip, feed(for: zip))
        let installed = folder.appendingPathComponent("Applications/Droptimize.app")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        XCTAssertNil(UpdateInstaller.placeProblem(for: installed))

        let staged = try UpdateInstaller.stage(app, beside: installed)
        XCTAssertEqual(staged.path, installed.path + ".new")
        XCTAssertTrue(UpdateInstaller.hasValidCodeSignature(staged), "copied with its signature intact")
        XCTAssertEqual(UpdateInstaller.placeProblem(for: URL(fileURLWithPath: "/System/Applications/Calculator.app")),
                       .readOnly)
    }
}
