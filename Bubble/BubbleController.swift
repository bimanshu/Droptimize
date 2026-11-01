import AppKit

/// Owns the bubble: its panel, where it sits, and the idle → menu → working → done/message
/// state machine. `BubbleHostView` forwards every event here; `BubbleModel` is what gets drawn.
@MainActor
final class BubbleController {
    let model = BubbleModel()
    private let history: HistoryStore
    private let pro: ProStore
    /// Opens the Pro window (the menu bar owns it).
    var onShowPro: (() -> Void)?

    private let panel = BubblePanel()
    private let host: BubbleHostView
    private let mover: PanelMover
    private let store = DockStore()
    private let inputs = InputPanel()
    private let memory = OptionMemory()

    /// The bubble's center in screen coordinates. Everything is positioned from this.
    private var center: CGPoint = .zero
    private var moveStartCenter: CGPoint = .zero

    private var jobTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var shrinkTask: Task<Void, Never>?
    private var lastResult: JobResult?
    /// What the running (or just finished) job does, for the card and History.
    private var runningAction: Action?
    private var runningOption: ActionOption?
    /// True while an unsupported drag is over the bubble and we're saying so.
    private var isRejectingDrag = false
    /// The message on show is about the free plan; clicking it opens the Pro window.
    private var isOfferingPro = false
    /// "Free: 3 of 5…" when the free plan cut a drop short, for the done card.
    private var limitNote: String?
    /// The drop came from another app (Photos, Mail, a browser), so results went to Downloads.
    private var receivedFromApp = false

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(history: HistoryStore, pro: ProStore) {
        self.history = history
        self.pro = pro
        host = BubbleHostView(model: model)
        mover = PanelMover(view: host)
        host.controller = self
        panel.contentView = host
        panel.setAccessibilityLabel("Droptimize")
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.placeOnScreen() }
        }
        placeOnScreen()
    }

    // MARK: Showing and hiding

    var isVisible: Bool { panel.isVisible }

    func show() {
        panel.orderFrontRegardless()
        UserDefaults.standard.set(false, forKey: Self.hiddenKey)
    }

    func hide() {
        panel.orderOut(nil)
        UserDefaults.standard.set(true, forKey: Self.hiddenKey)
    }

    func toggle() { isVisible ? hide() : show() }

    static var startsHidden: Bool { UserDefaults.standard.bool(forKey: hiddenKey) }
    private static let hiddenKey = "bubble.hidden"

    // MARK: Position

    /// Puts the bubble where it last rested on the display it was last on, or the main display.
    private func placeOnScreen() {
        let screen = store.lastDisplay.flatMap(Self.screen(withID:)) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let position = Self.id(of: screen).flatMap(store.position(forDisplay:)) ?? .default
        rest(at: position, on: screen, animated: false)
    }

    private func rest(at position: DockPosition, on screen: NSScreen, animated: Bool) {
        model.side = position.side
        let target = position.center(in: screen.visibleFrame)
        if animated && !reduceMotion {
            mover.animate(from: center, to: target) { [weak self] point in self?.setCenter(point) }
        } else {
            mover.stop()
            setCenter(target)
        }
    }

    private func setCenter(_ point: CGPoint) {
        center = point
        applyPanelFrame()
    }

    func moveBegan() {
        mover.stop()
        moveStartCenter = center
    }

    func move(by delta: CGVector) {
        setCenter(CGPoint(x: moveStartCenter.x + delta.dx, y: moveStartCenter.y + delta.dy))
    }

    /// Springs to the nearest edge of whichever display the bubble was let go on, and remembers it.
    func moveEnded() {
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? panel.screen ?? NSScreen.main
        guard let screen else { return }
        let position = DockPosition.nearest(to: center, in: screen.visibleFrame)
        if let id = Self.id(of: screen) { store.save(position, forDisplay: id) }
        rest(at: position, on: screen, animated: true)
    }

    // MARK: Panel size

    private var panelContent: PanelContent {
        switch model.phase {
        case .idle, .asking, .working: return .bubble
        case .menu: return .menu(segments: model.menu.segments.count, submenu: model.submenu.flatMap(menuGeometry.submenu(for:)))
        case .done, .message: return .accessory
        }
    }

    private var menuGeometry: MenuGeometry {
        MenuGeometry(side: model.side, optionCounts: model.menu.geometryOptionCounts)
    }

    /// Sizes the panel for the current state, keeping the bubble's center fixed on screen.
    /// Growing happens at once, so new segments are real drop targets straight away; shrinking
    /// waits until the fold-in animation is over.
    private func updatePanelFrame() {
        shrinkTask?.cancel()
        let wanted = BubbleLayout(side: model.side).panelFrame(for: panelContent, center: center)
        guard panel.frame.contains(wanted), panel.frame != wanted else {
            applyPanelFrame()
            return
        }
        shrinkTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Motion.collapseSettle * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.applyPanelFrame()
        }
    }

    private func applyPanelFrame() {
        let frame = BubbleLayout(side: model.side).panelFrame(for: panelContent, center: center)
        panel.disableScreenUpdatesUntilFlush()
        panel.setFrame(frame, display: false)
        host.bubbleCenter = CGPoint(x: center.x - frame.minX, y: center.y - frame.minY)
        panel.displayIfNeeded()
    }

    // MARK: Hover and click

    func hoverChanged(_ hovering: Bool) {
        model.isHovering = hovering
    }

    func region(at screenPoint: CGPoint) -> BubbleRegion {
        if hypot(screenPoint.x - center.x, screenPoint.y - center.y) <= Motion.bubbleDiameter / 2 + 6 {
            return .bubble
        }
        if case .done = model.phase,
           BubbleLayout(side: model.side).accessoryRect(center: center).contains(screenPoint) {
            return .result
        }
        return .elsewhere
    }

    func click(in region: BubbleRegion) {
        switch model.phase {
        case .asking:
            inputs.cancel()
        case .working:
            cancelJob()
        case .done where region != .elsewhere:
            revealResult()
        case .message:
            let opensPro = isOfferingPro
            returnToIdle()
            if opensPro { onShowPro?() }
        default:
            break
        }
    }

    // MARK: Dropping files on the bubble

    /// A drag came over the bubble, from Finder or any other app. Returns whether we can take any
    /// of what it carries.
    func dragEntered(_ items: DroppedItems) -> Bool {
        if case .working = model.phase { return false }     // one job at a time until the JobQueue (Phase 1)
        if inputs.isShowing { inputs.cancel() }               // a new drag wins over an unanswered question
        guard let menu = ActionMenu(kinds: items.kinds, lastColor: memory.lastColor) else {
            if items.hasItems {
                isRejectingDrag = true
                showMessage(JobError.unsupported.errorDescription ?? "", autoDismiss: false)
            }
            return false
        }
        // Out of free files today: say so at once rather than after the drop.
        guard pro.grant(1) > 0 else {
            isRejectingDrag = true
            offerPro()
            return false
        }
        dismissTask?.cancel()
        isRejectingDrag = false
        model.menu = menu
        model.target = nil
        model.submenu = nil
        model.phase = .menu
        updatePanelFrame()
        return true
    }

    /// The drag moved; highlight whatever is under the pointer, and show the options of the
    /// segment it's over (Compress sizes, Remove BG backgrounds).
    func dragMoved() -> NSDragOperation {
        guard model.isMenuOpen else { return [] }
        let mouse = NSEvent.mouseLocation
        let geometry = menuGeometry
        let target = geometry.target(at: CGVector(dx: mouse.x - center.x, dy: mouse.y - center.y),
                                     openSubmenu: model.submenu)
        let submenu = geometry.openSubmenu(after: target, current: model.submenu)
        if submenu != model.submenu {
            model.submenu = submenu
            updatePanelFrame()                                 // grows at once to hold the options
        }
        if target != model.target {
            model.target = target
            if target != nil {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        return target == nil ? [] : .copy
    }

    func dragExited() {
        endDrag()
    }

    /// The drag ended somewhere, dropped or not; fold anything it opened.
    func dragSessionEnded() {
        endDrag()
    }

    private func endDrag() {
        if isRejectingDrag && isOfferingPro {
            // Leave the free-plan message up a moment, so it can be clicked.
            isRejectingDrag = false
            scheduleDismiss(after: Motion.messageDuration)
        } else if model.isMenuOpen || isRejectingDrag {
            returnToIdle()
        }
    }

    func drop(_ items: DroppedItems) -> Bool {
        guard model.isMenuOpen, let target = model.target, let action = model.menu.action(for: target) else {
            returnToIdle()
            return false
        }
        guard items.count > 0 else {
            returnToIdle()
            return false
        }
        // The free plan runs what's left of today's files and says so on the card.
        let allowed = pro.grant(items.count)
        guard allowed > 0 else {
            offerPro()
            return false
        }
        limitNote = allowed < items.count ? "Free plan: \(allowed) of \(items.count). Pro does all" : nil
        if !reduceMotion {
            let mouse = NSEvent.mouseLocation
            addRipple(at: CGVector(dx: mouse.x - center.x, dy: mouse.y - center.y))
        }
        let option = model.menu.option(for: target)?.option
        receivedFromApp = !items.isReady
        if items.isReady {
            go(with: Array(items.files.prefix(allowed)), action: action, option: option)
            return true
        }
        // Another app is writing the files (Photos may fetch them from iCloud): spin meanwhile.
        // A click cancels, as with any job.
        dismissTask?.cancel()
        model.target = nil
        model.submenu = nil
        model.phase = .working(JobProgress(completed: 0, total: allowed, fraction: 0))
        updatePanelFrame()
        jobTask = Task { [weak self] in
            let files = (try? await items.files(limit: allowed)) ?? []
            guard let self, !Task.isCancelled else { return }
            guard !files.isEmpty else { return self.fail(JobError.notReceived) }
            self.go(with: files, action: action, option: option)
        }
        return true
    }

    private func go(with files: [URL], action: Action, option: ActionOption?) {
        if option == .custom {
            ask(for: action, files: files)
        } else {
            start(Job(files: files, action: action, option: option), runner: ImageJobRunner())
        }
    }

    /// Dropped on a Custom option: ask for the size or color beside the bubble, then run.
    private func ask(for action: Action, files: [URL]) {
        dismissTask?.cancel()
        model.target = nil
        model.submenu = nil
        model.phase = .asking
        updatePanelFrame()
        let anchor = BubbleLayout(side: model.side).accessoryRect(center: center)
        switch action {
        case .compress:
            let isVideo = files.contains { MediaKind(url: $0) == .video }
            let initial = memory.lastCustomSize ?? (isVideo ? VideoTuning.defaultCustomSize : nil)
            inputs.askForSize(initial: initial, beside: anchor, side: model.side) { [weak self] bytes in
                guard let self else { return }
                guard let bytes else { return self.returnToIdle() }
                self.memory.lastCustomSize = bytes
                self.start(Job(files: files, action: .compress, option: .maxBytes(bytes)), runner: ImageJobRunner())
            }
        case .removeBackground:
            inputs.askForColor(initial: memory.lastColor ?? .white, beside: anchor, side: model.side) { [weak self] color in
                guard let self else { return }
                guard let color else { return self.returnToIdle() }
                self.memory.lastColor = color
                self.start(Job(files: files, action: .removeBackground, option: .background(color)), runner: ImageJobRunner())
            }
        default:
            returnToIdle()
        }
    }

    // MARK: Jobs

    private func start(_ job: Job, runner: JobRunner) {
        jobTask?.cancel()
        runningAction = job.action
        runningOption = job.option
        dismissTask?.cancel()
        model.target = nil
        model.phase = .working(JobProgress(completed: 0, total: job.files.count, fraction: 0))
        updatePanelFrame()
        jobTask = Task { [weak self] in
            do {
                let result = try await runner.run(job) { progress in
                    guard let self, case .working = self.model.phase else { return }
                    self.model.phase = .working(progress)
                }
                guard !Task.isCancelled else { return }
                self?.finish(result)
            } catch is CancellationError {
                // Cancelled by a click; the bubble is already idle.
            } catch {
                self?.fail(error)
            }
        }
    }

    private func finish(_ result: JobResult) {
        jobTask = nil
        lastResult = result
        pro.record(result.outputs.count)
        let lastFree = pro.isLimited && pro.grant(1) == 0 ? "That was today's last free file" : nil
        history.record(result.items.map { item in
            HistoryEntry(action: runningAction?.title ?? "", detail: runningOption?.title,
                         input: item.input, output: item.output, inputBytes: item.inputBytes, outputBytes: item.outputBytes)
        })
        // Removing a background isn't about size, so the card says "Done" rather than a saving.
        let saving = runningAction == .removeBackground ? 0 : result.saving
        let info = DoneInfo(saving: saving, count: result.outputs.count, thumbnail: nil,
                            detail: limitNote ?? result.note ?? (receivedFromApp ? "Saved to Downloads" : nil) ?? lastFree)
        limitNote = nil
        receivedFromApp = false
        model.phase = .done(info)
        updatePanelFrame()
        scheduleDismiss(after: Motion.doneDuration)
        // Show the done state at once; the thumbnail follows a moment later.
        guard let first = result.outputs.first else { return }
        let scale = panel.backingScaleFactor
        Task { [weak self] in
            let thumbnail = await Thumbnails.make(for: first, side: Motion.thumbnailSide, scale: scale)
            guard let self, case .done(var current) = self.model.phase, current.id == info.id else { return }
            current.thumbnail = thumbnail.image
            self.model.phase = .done(current)
        }
    }

    private func fail(_ error: Error) {
        jobTask = nil
        showMessage((error as? LocalizedError)?.errorDescription ?? "Couldn't optimize this image.")
    }

    private func cancelJob() {
        jobTask?.cancel()
        jobTask = nil
        returnToIdle()
    }

    // MARK: Done and messages

    private func showMessage(_ text: String, autoDismiss: Bool = true) {
        isOfferingPro = false
        model.phase = .message(text)
        model.shakes += 1
        updatePanelFrame()
        if autoDismiss { scheduleDismiss(after: Motion.messageDuration) }
    }

    /// Returns to idle after `seconds`, but never while the pointer is resting on the bubble.
    private func scheduleDismiss(after seconds: Double) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            if self.model.isHovering {
                self.scheduleDismiss(after: Motion.hoverGrace)
            } else {
                self.returnToIdle()
            }
        }
    }

    /// Today's free files are used up: say so; a click opens the Pro window.
    private func offerPro() {
        showMessage("No free files left today. Click for Pro.", autoDismiss: !isRejectingDrag)
        isOfferingPro = true
    }

    private func returnToIdle() {
        dismissTask?.cancel()
        isRejectingDrag = false
        isOfferingPro = false
        model.target = nil
        model.submenu = nil
        model.phase = .idle
        updatePanelFrame()
    }

    private func revealResult() {
        guard let outputs = lastResult?.outputs else { return }
        NSWorkspace.shared.activateFileViewerSelecting(outputs)
        returnToIdle()
    }

    private func addRipple(at offset: CGVector) {
        let ripple = Ripple(offset: offset)
        model.ripples.append(ripple)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Motion.rippleDuration * 1_000_000_000))
            self?.model.ripples.removeAll { $0.id == ripple.id }
        }
    }

    // MARK: Dragging the result out

    /// One dragging item per output, starting from `point` in the host view.
    func dragOutItems(at point: CGPoint) -> [NSDraggingItem]? {
        guard case .done(let info) = model.phase, let outputs = lastResult?.outputs, !outputs.isEmpty else { return nil }
        let side = Motion.thumbnailSide
        return outputs.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let image = info.thumbnail ?? NSWorkspace.shared.icon(forFile: url.path)
            let offset = CGFloat(min(index, 3)) * 4
            item.setDraggingFrame(CGRect(x: point.x - side / 2 + offset, y: point.y - side / 2 - offset,
                                         width: side, height: side),
                                  contents: image)
            return item
        }
    }

    /// The result was dragged somewhere. If it landed, it's been handed off; tidy up.
    func dragOutEnded(operation: NSDragOperation) {
        if !operation.isEmpty { returnToIdle() }
    }

    // MARK: Displays

    /// A stable name for a display: vendor, model and serial number.
    private static func id(of screen: NSScreen) -> String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        let display = CGDirectDisplayID(number.uint32Value)
        return "\(CGDisplayVendorNumber(display))-\(CGDisplayModelNumber(display))-\(CGDisplaySerialNumber(display))"
    }

    private static func screen(withID id: String) -> NSScreen? {
        NSScreen.screens.first { Self.id(of: $0) == id }
    }
}
