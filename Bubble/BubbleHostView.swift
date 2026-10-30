import AppKit
import SwiftUI

/// Which part of the bubble a press started on.
enum BubbleRegion {
    case bubble
    /// The result card in the done state.
    case result
    case elsewhere
}

/// The panel's content view. Every event is handled here in AppKit (drops, hover, moving the
/// bubble, dragging the result out) and passed to `BubbleController`; the SwiftUI canvas
/// inside only draws.
final class BubbleHostView: NSView, NSDraggingSource {
    weak var controller: BubbleController?

    /// Where the bubble's center sits in this view. The canvas stays centered on it.
    var bubbleCenter: CGPoint = .zero {
        didSet { layoutCanvas() }
    }

    private let canvas: NSHostingView<BubbleView>
    private var trackingArea: NSTrackingArea?
    private var press: Press?

    private struct Press {
        enum Mode { case pending, moving, draggingOut }
        let event: NSEvent
        let startMouse: CGPoint      // screen coordinates
        let region: BubbleRegion
        var mode: Mode = .pending
    }

    init(model: BubbleModel) {
        canvas = NSHostingView(rootView: BubbleView(model: model))
        super.init(frame: NSRect(x: 0, y: 0, width: Motion.idlePanelSide, height: Motion.idlePanelSide))
        canvas.sizingOptions = []    // the canvas has a fixed size; don't let it resize the panel
        addSubview(canvas)
        canvas.unregisterDraggedTypes()
        registerForDraggedTypes([.fileURL])
        layoutCanvas()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func layoutCanvas() {
        let side = BubbleLayout.canvasSide
        canvas.frame = CGRect(x: bubbleCenter.x - side / 2, y: bubbleCenter.y - side / 2, width: side, height: side)
    }

    // MARK: Hit testing and hover

    /// Keep every event in AppKit; the SwiftUI canvas only draws.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { controller?.hoverChanged(true) }
    override func mouseExited(with event: NSEvent) { controller?.hoverChanged(false) }

    // MARK: Click, move, drag out

    override func mouseDown(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        press = Press(event: event, startMouse: mouse, region: controller?.region(at: mouse) ?? .elsewhere)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var press, let controller else { return }
        let mouse = NSEvent.mouseLocation
        let delta = CGVector(dx: mouse.x - press.startMouse.x, dy: mouse.y - press.startMouse.y)
        switch press.mode {
        case .pending:
            guard hypot(delta.dx, delta.dy) >= Motion.dragThreshold else { return }
            let start = convert(press.event.locationInWindow, from: nil)
            if press.region == .result, let items = controller.dragOutItems(at: start) {
                press.mode = .draggingOut
                self.press = press
                beginDraggingSession(with: items, event: press.event, source: self)
                return
            }
            press.mode = .moving
            controller.moveBegan()
            controller.move(by: delta)
        case .moving:
            controller.move(by: delta)
        case .draggingOut:
            break
        }
        self.press = press
    }

    override func mouseUp(with event: NSEvent) {
        guard let press else { return }
        self.press = nil
        switch press.mode {
        case .pending: controller?.click(in: press.region)
        case .moving: controller?.moveEnded()
        case .draggingOut: break
        }
    }

    // MARK: NSDraggingSource (the result card)

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Copy only, so Finder never moves the file, and never onto ourselves.
        context == .outsideApplication ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        press = nil
        controller?.dragOutEnded(operation: operation)
    }

    // MARK: NSDraggingDestination (files dropped on the bubble)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let controller, !isOwnDrag(sender) else { return [] }
        return controller.dragEntered(fileURLs(in: sender)) ? controller.dragMoved() : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let controller, !isOwnDrag(sender) else { return [] }
        return controller.dragMoved()
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        controller?.dragExited()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let controller, !isOwnDrag(sender) else { return false }
        return controller.drop(fileURLs(in: sender))
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        controller?.dragSessionEnded()
    }

    private func isOwnDrag(_ info: NSDraggingInfo) -> Bool {
        (info.draggingSource as? NSView) === self
    }

    private func fileURLs(in info: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }
}
