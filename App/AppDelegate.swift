import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var bubble: BubbleController?
    private var menuBar: MenuBar?
    private var hotKey: HotKey?
    private var licenseTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside the app; keep the bubble and menu bar out of their way.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        let history = HistoryStore()
        let pro = ProStore()
        let bubble = BubbleController(history: history, pro: pro)
        self.bubble = bubble
        let menuBar = MenuBar(bubble: bubble, history: history, pro: pro)
        self.menuBar = menuBar
        bubble.onShowPro = { [weak menuBar] in menuBar?.showPro() }
        // A Pro license is checked now and then (CORE.md Rule 4's one exception).
        Task { await pro.check() }
        licenseTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak pro] _ in
            Task { @MainActor in await pro?.check() }
        }
        hotKey = HotKey(keyCode: MenuBar.toggleKeyCode, modifiers: MenuBar.toggleCarbonModifiers) { [weak bubble] in
            bubble?.toggle()
        }
        if !BubbleController.startsHidden { bubble.show() }
    }
}
