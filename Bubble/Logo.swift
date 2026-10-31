import AppKit
import SwiftUI

/// Droptimize's mark: a bubble, smaller, smaller (the owner's pick, 2026-10-31). One geometry on a
/// 24-unit grid, like an SF Symbol, drawn by the bubble (`LogoMark`), the menu bar
/// (`menuBarImage`) and the app icon (`scripts/app-icon.svg` repeats the numbers; regenerate its PNGs
/// with `scripts/make-app-icon.js`).
enum Logo {
    struct Disc {
        var x: CGFloat
        var y: CGFloat
        var radius: CGFloat

        /// Its bounding box at `unit` points per grid unit, y down.
        func rect(_ unit: CGFloat) -> CGRect {
            CGRect(x: (x - radius) * unit, y: (y - radius) * unit, width: radius * 2 * unit, height: radius * 2 * unit)
        }
    }

    static let grid: CGFloat = 24
    static let stroke: CGFloat = 2
    /// Outlined: the original, then smaller.
    static let rings = [Disc(x: 12, y: 12, radius: 9.5), Disc(x: 9.6, y: 14.4, radius: 5.6)]
    /// Solid: the result.
    static let dot = Disc(x: 7.9, y: 16.1, radius: 2.6)

    /// A template image, so the menu bar tints it for light and dark.
    static func menuBarImage(size: CGFloat = Motion.menuBarLogoSize) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let unit = rect.width / grid
            NSColor.black.set()
            for ring in rings {
                let path = NSBezierPath(ovalIn: ring.rect(unit))
                path.lineWidth = stroke * unit
                path.stroke()
            }
            NSBezierPath(ovalIn: dot.rect(unit)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Droptimize"
        return image
    }
}

/// The mark in SwiftUI, in the current foreground style.
struct LogoMark: View {
    var size: CGFloat = Motion.logoSize

    var body: some View {
        let unit = size / Logo.grid
        ZStack(alignment: .topLeading) {
            ForEach(Logo.rings.indices, id: \.self) { index in
                disc(Circle().stroke(lineWidth: Logo.stroke * unit), Logo.rings[index], unit)
            }
            disc(Circle(), Logo.dot, unit)
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func disc(_ shape: some View, _ disc: Logo.Disc, _ unit: CGFloat) -> some View {
        let rect = disc.rect(unit)
        return shape
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }
}
