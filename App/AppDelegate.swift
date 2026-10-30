import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var bubble: BubbleController?
    private var menuBar: MenuBar?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside the app; keep the bubble and menu bar out of their way.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        let history = HistoryStore()
        let bubble = BubbleController(history: history)
        self.bubble = bubble
        menuBar = MenuBar(bubble: bubble, history: history)
        hotKey = HotKey(keyCode: MenuBar.toggleKeyCode, modifiers: MenuBar.toggleCarbonModifiers) { [weak bubble] in
            bubble?.toggle()
        }
        if !BubbleController.startsHidden { bubble.show() }
    }
}
