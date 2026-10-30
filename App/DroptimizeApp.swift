import AppKit

/// Droptimize is a menu bar app (LSUIElement): no Dock icon, no main window, just the bubble.
@main
@MainActor
enum DroptimizeApp {
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}
