import XCTest
@testable import Droptimize

// Portable: also runs on Linux via scripts/check-linux.sh.
final class HistoryTests: XCTestCase {
    private func entry(_ name: String, in bytes: Int = 1000, out: Int = 400, action: String = "Compress") -> HistoryEntry {
        HistoryEntry(action: action, input: URL(fileURLWithPath: "/w/\(name).png"),
                     output: URL(fileURLWithPath: "/w/\(name)-min.png"), inputBytes: bytes, outputBytes: out)
    }

    func testNewestDropsGoOnTopInDropOrder() {
        var log = HistoryLog()
        log.record([entry("a"), entry("b")])
        log.record([entry("c"), entry("d")])
        XCTAssertEqual(log.entries.map(\.input.lastPathComponent), ["c.png", "d.png", "a.png", "b.png"])
    }

    func testKeepsAtMostTheLimit() {
        var log = HistoryLog()
        for i in 0..<(HistoryLog.limit + 20) { log.record([entry("f\(i)")]) }
        XCTAssertEqual(log.entries.count, HistoryLog.limit)
        XCTAssertEqual(log.entries.first?.input.lastPathComponent, "f\(HistoryLog.limit + 19).png", "drops the oldest")
    }

    func testRemoveAndClear() {
        var log = HistoryLog()
        let a = entry("a"), b = entry("b")
        log.record([a, b])
        log.remove(a.id)
        XCTAssertEqual(log.entries, [b])
        log.clear()
        XCTAssertTrue(log.entries.isEmpty)
    }

    func testRecentOutputsAreUniqueAndCapped() {
        var log = HistoryLog()
        for i in 0..<15 { log.record([entry("f\(i)")]) }
        log.record([entry("f3")])
        let recent = log.recentOutputs()
        XCTAssertEqual(recent.count, 10)
        XCTAssertEqual(recent.first?.lastPathComponent, "f3-min.png")
        XCTAssertEqual(Set(recent).count, recent.count)
    }

    func testSavedBytesIgnoresFilesThatGrew() {
        var log = HistoryLog()
        log.record([entry("a", in: 1000, out: 400), entry("b", in: 500, out: 900, action: "Convert")])
        XCTAssertEqual(log.savedBytes, 600)
    }

    func testChangeAndSummaryText() {
        XCTAssertEqual(entry("a", in: 1000, out: 160).changeText, "\u{2212}84%")
        XCTAssertEqual(entry("a", in: 1000, out: 1120).changeText, "+12%")
        XCTAssertEqual(entry("a", in: 1000, out: 1000).changeText, "±0%")
        var withDetail = entry("a")
        withDetail.detail = "Under 500 KB"
        XCTAssertEqual(withDetail.summary, "Compress · Under 500 KB")
        XCTAssertEqual(entry("a").summary, "Compress")
    }

    func testOptionTitlesForHistory() {
        XCTAssertEqual(ActionOption.maxBytes(500_000).title, "Under 500 KB")
        XCTAssertEqual(ActionOption.format(.jpeg).title, "To JPG")
        XCTAssertEqual(ActionOption.background(nil).title, "No background")
        XCTAssertEqual(ActionOption.background(.white).title, "White")
        XCTAssertNil(ActionOption.custom.title)
    }

    func testSavesAndLoads() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryTests-\(UUID().uuidString)/Droptimize/history.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        var log = HistoryLog()
        log.record([entry("a"), entry("b")])
        try HistoryFile.save(log, to: url)
        let loaded = HistoryFile.load(from: url)
        XCTAssertEqual(loaded.entries.map(\.id), log.entries.map(\.id))
        XCTAssertEqual(loaded.entries.map(\.output), log.entries.map(\.output))
        XCTAssertEqual(loaded.entries[0].date.timeIntervalSince1970, log.entries[0].date.timeIntervalSince1970, accuracy: 1)
    }

    func testMissingOrBrokenFilesGiveAnEmptyHistory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertTrue(HistoryFile.load(from: folder.appendingPathComponent("none.json")).entries.isEmpty)
        let broken = folder.appendingPathComponent("broken.json")
        try Data("not json".utf8).write(to: broken)
        XCTAssertTrue(HistoryFile.load(from: broken).entries.isEmpty)
    }
}
