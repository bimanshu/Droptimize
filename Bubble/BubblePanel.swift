import AppKit

/// The borderless floating window the bubble lives in. Non-activating, so it never takes focus
/// from the app you're in; on every Space and over full-screen apps (CORE.md §4.1).
final class BubblePanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Motion.idlePanelSide, height: Motion.idlePanelSide),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false            // the views draw their own
        isMovable = false            // moved by hand in BubbleController, with edge snapping
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
