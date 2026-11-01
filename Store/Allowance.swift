import Foundation

/// The free plan (owner's decision, 2026-11-01; CORE.md §8.1): `perDay` files a day, counting every
/// file that comes out of any action (images and video alike), reset at local midnight. Pro is
/// unlimited. Portable, so it's tested on Linux too.
struct FreeAllowance: Codable, Equatable {
    static let perDay = 3

    /// The day `used` counts, as "2026-11-01" in the user's calendar.
    var day: String
    var used: Int

    init(day: String = "", used: Int = 0) {
        self.day = day
        self.used = used
    }

    static func day(of date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func remaining(on day: String) -> Int {
        day == self.day ? max(0, Self.perDay - used) : Self.perDay
    }

    /// How many of `files` may run now.
    func grant(_ files: Int, on day: String) -> Int {
        min(max(files, 0), remaining(on: day))
    }

    /// Counts `files` that were made on `day`.
    mutating func record(_ files: Int, on day: String) {
        if day != self.day {
            self.day = day
            used = 0
        }
        used += max(files, 0)
    }
}
