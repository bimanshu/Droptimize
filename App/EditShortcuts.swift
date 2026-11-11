import AppKit

/// ⌘X, ⌘C, ⌘V, ⌘A, ⌘Z and ⇧⌘Z for text fields. A menu bar app (LSUIElement) has no Edit menu,
/// which is what normally routes these, so windows with text fields pass key equivalents here.
enum EditShortcuts {
    /// Sends the edit action for `event` up the window's responder chain; false if it isn't one or
    /// nothing there handles it.
    @MainActor
    static func perform(_ event: NSEvent, in window: NSWindow) -> Bool {
        guard let action = action(for: event) else { return false }
        return window.firstResponder?.tryToPerform(action, with: window) ?? false
    }

    static func action(for event: NSEvent) -> Selector? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags == .command { return plain[key] }
        if flags == [.command, .shift], key == "z" { return Selector(("redo:")) }
        return nil
    }

    private static let plain: [String: Selector] = [
        "x": #selector(NSText.cut(_:)),
        "c": #selector(NSText.copy(_:)),
        "v": #selector(NSText.paste(_:)),
        "a": #selector(NSText.selectAll(_:)),
        "z": Selector(("undo:")),
    ]
}
