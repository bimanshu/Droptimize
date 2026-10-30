import AppKit

/// Owns the bubble: its panel, where it sits, and the idle → menu → working → done/message
/// state machine. `BubbleHostView` forwards every event here; `BubbleModel` is what gets drawn.
@MainActor
final class BubbleController {
    let model = BubbleModel()
    /// The last ten outputs, newest first, for the menu bar's Recent list.
    private(set) var recents: [URL] = []

    private let panel = BubblePanel()
    private let host: BubbleHostView
    private let mover: PanelMover
    private let store = DockStore()

    /// The bubble's center in screen coordinates. Everything is positioned from this.
    private var center: CGPoint = .zero
    private var moveStartCenter: CGPoint = .zero

    private var jobTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var shrinkTask: Task<Void, Never>?
    private var lastResult: JobResult?
    /// True while an unsupported drag is over the bubble and we're saying so.
    private var isRejectingDrag = false

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init() {
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
        case .idle, .working: return .bubble
        case .menu: return .menu(segments: model.menu.segments.count)
        case .done, .message: return .accessory
        }
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
        case .working:
            cancelJob()
        case .done where region != .elsewhere:
            revealResult()
        case .message:
            returnToIdle()
        default:
            break
        }
    }

    // MARK: Dropping files on the bubble

    /// A drag carrying `urls` came over the bubble. Returns whether we can take any of them.
    func dragEntered(_ urls: [URL]) -> Bool {
        if case .working = model.phase { return false }     // one job at a time until the JobQueue (Phase 1)
        let kinds = Set(urls.compactMap(MediaKind.init(url:)))
        guard let menu = ActionMenu(kinds: kinds) else {
            if !urls.isEmpty {
                isRejectingDrag = true
                showMessage(JobError.unsupported.errorDescription ?? "", autoDismiss: false)
            }
            return false
        }
        dismissTask?.cancel()
        isRejectingDrag = false
        model.menu = menu
        model.target = nil
        model.phase = .menu
        updatePanelFrame()
        return true
    }

    /// The drag moved; highlight whatever is under the pointer.
    func dragMoved() -> NSDragOperation {
        guard model.isMenuOpen else { return [] }
        let mouse = NSEvent.mouseLocation
        let target = RadialLayout(count: model.menu.segments.count, side: model.side)
            .target(at: CGVector(dx: mouse.x - center.x, dy: mouse.y - center.y))
        if target != model.target {
            model.target = target
            if target != nil {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        return target == nil ? [] : .copy
    }

    func dragExited() {
        if model.isMenuOpen || isRejectingDrag { returnToIdle() }
    }

    /// The drag ended somewhere, dropped or not; fold anything it opened.
    func dragSessionEnded() {
        if model.isMenuOpen || isRejectingDrag { returnToIdle() }
    }

    func drop(_ urls: [URL]) -> Bool {
        guard model.isMenuOpen, let target = model.target, let action = model.menu.action(for: target) else {
            returnToIdle()
            return false
        }
        let files = urls.filter { MediaKind(url: $0) != nil }
        guard !files.isEmpty else {
            returnToIdle()
            return false
        }
        if !reduceMotion {
            let mouse = NSEvent.mouseLocation
            addRipple(at: CGVector(dx: mouse.x - center.x, dy: mouse.y - center.y))
        }
        // Phase 0: hold Option while dropping to try the error state.
        let failure: JobError? = NSEvent.modifierFlags.contains(.option) ? .alreadySmallest : nil
        start(Job(files: files, action: action), runner: FakeJobRunner(failure: failure))
        return true
    }

    // MARK: Jobs

    private func start(_ job: Job, runner: JobRunner) {
        jobTask?.cancel()
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
        recents = Array((result.outputs + recents.filter { !result.outputs.contains($0) }).prefix(10))
        let info = DoneInfo(saving: result.saving, count: result.outputs.count, thumbnail: nil)
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
        showMessage((error as? LocalizedError)?.errorDescription ?? "Something went wrong.")
    }

    private func cancelJob() {
        jobTask?.cancel()
        jobTask = nil
        returnToIdle()
    }

    // MARK: Done and messages

    private func showMessage(_ text: String, autoDismiss: Bool = true) {
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

    private func returnToIdle() {
        dismissTask?.cancel()
        isRejectingDrag = false
        model.target = nil
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
