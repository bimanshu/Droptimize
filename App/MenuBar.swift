import AppKit
import Carbon.HIToolbox

/// The menu bar icon: show or hide the bubble, recent results, settings, quit (CORE.md §4.4).
@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    /// Show/hide shortcut: ⌃⌥⌘D. (⌥⌘D is taken by the system's Dock hiding.)
    static let toggleKeyCode = UInt32(kVK_ANSI_D)
    static let toggleCarbonModifiers = UInt32(controlKey | optionKey | cmdKey)
    private static let toggleMenuModifiers: NSEvent.ModifierFlags = [.control, .option, .command]

    private let bubble: BubbleController
    private let history: HistoryStore
    private let historyWindow: HistoryWindowController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let toggleItem = NSMenuItem()
    private let recentMenu = NSMenu(title: "Recent")

    init(bubble: BubbleController, history: HistoryStore) {
        self.bubble = bubble
        self.history = history
        self.historyWindow = HistoryWindowController(store: history)
        super.init()

        statusItem.button?.image = Logo.menuBarImage()

        let menu = NSMenu()
        menu.delegate = self

        toggleItem.action = #selector(toggleBubble)
        toggleItem.target = self
        toggleItem.keyEquivalent = "d"
        toggleItem.keyEquivalentModifierMask = Self.toggleMenuModifiers
        menu.addItem(toggleItem)

        let historyItem = NSMenuItem(title: "History…", action: #selector(showHistory), keyEquivalent: "y")
        historyItem.target = self
        menu.addItem(historyItem)

        let recentItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        menu.addItem(.separator())
        // Settings arrive with Phase 1; an item without an action shows disabled.
        menu.addItem(NSMenuItem(title: "Settings…", action: nil, keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Droptimize", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        toggleItem.title = bubble.isVisible ? "Hide Bubble" : "Show Bubble"

        recentMenu.removeAllItems()
        let recents = history.log.recentOutputs()
        if recents.isEmpty {
            recentMenu.addItem(NSMenuItem(title: "No recent files", action: nil, keyEquivalent: ""))
        }
        for url in recents {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(revealRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            recentMenu.addItem(item)
        }
    }

    @objc private func showHistory() {
        historyWindow.show()
    }

    @objc private func toggleBubble() {
        bubble.toggle()
    }

    @objc private func revealRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
