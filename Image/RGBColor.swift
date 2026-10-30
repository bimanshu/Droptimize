import Foundation

/// An sRGB color, as typed in a hex field.
struct RGBColor: Hashable, Codable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    static let white = RGBColor(red: 255, green: 255, blue: 255)
    static let black = RGBColor(red: 0, green: 0, blue: 0)

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Reads `#1A2B3C`, `1a2b3c` or the short `#abc`. Nil for anything else.
    init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: UInt8(truncatingIfNeeded: value >> 16),
                  green: UInt8(truncatingIfNeeded: value >> 8),
                  blue: UInt8(truncatingIfNeeded: value))
    }

    /// `#1A2B3C`.
    var hex: String {
        "#" + [red, green, blue].map { byte in
            let digits = String(byte, radix: 16, uppercase: true)
            return digits.count == 1 ? "0" + digits : digits
        }.joined()
    }

    /// A readable name for the common ones, else the hex value.
    var name: String {
        switch self {
        case .white: return "White"
        case .black: return "Black"
        default: return hex
        }
    }
}

/// File sizes in decimal units, as Finder shows them (1 KB = 1000 bytes).
enum ByteCount {
    /// "500 KB", "1 MB", "1.5 MB".
    static func describe(_ bytes: Int) -> String {
        bytes >= 1_000_000 ? "\(number(Double(bytes) / 1_000_000)) MB" : "\(number(Double(bytes) / 1000)) KB"
    }

    /// "500K", "1M", "1.5M", for the small option bubbles.
    static func short(_ bytes: Int) -> String {
        bytes >= 1_000_000 ? "\(number(Double(bytes) / 1_000_000))M" : "\(number(Double(bytes) / 1000))K"
    }

    /// "-500kb", "-1mb", "-1.5mb", for file names.
    static func suffix(_ bytes: Int) -> String {
        "-" + short(bytes).lowercased() + "b"
    }

    /// Up to one decimal place, without a trailing ".0".
    private static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}
