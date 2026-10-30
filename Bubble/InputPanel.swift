import AppKit
import SwiftUI

/// The small panel that asks for a custom size or color after a drop on a Custom option (you
/// can't type mid-drag). It takes the keyboard without activating Droptimize, so the app you
/// were in stays in front (Rule 1). Return confirms, Esc cancels.
@MainActor
final class InputPanel {
    private var panel: KeyPanel?
    private var onCancel: (() -> Void)?

    var isShowing: Bool { panel != nil }

    /// Asks for a file size, filled in with `initial` bytes. Calls back with nil when cancelled.
    func askForSize(initial: Int?, beside anchor: CGRect, side: DockSide, completion: @escaping (Int?) -> Void) {
        let view = SizeInputView(initial: initial ?? 500_000,
                                 onDone: { [weak self] bytes in self?.finish { completion(bytes) } },
                                 onCancel: { [weak self] in self?.cancel() })
        present(view, beside: anchor, side: side) { completion(nil) }
    }

    /// Asks for a background color, starting from `initial`. Calls back with nil when cancelled.
    func askForColor(initial: RGBColor, beside anchor: CGRect, side: DockSide, completion: @escaping (RGBColor?) -> Void) {
        let view = ColorInputView(initial: initial,
                                  onDone: { [weak self] color in self?.finish { completion(color) } },
                                  onCancel: { [weak self] in self?.cancel() },
                                  sample: { [weak self] picked in self?.sampleScreenColor(then: picked) })
        present(view, beside: anchor, side: side) { completion(nil) }
    }

    func cancel() {
        let onCancel = self.onCancel
        close()
        onCancel?()
    }

    private func finish(_ deliver: () -> Void) {
        close()
        deliver()
    }

    private func close() {
        onCancel = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// Shows `content` beside the bubble, on the side facing into the screen.
    private func present<Content: View>(_ content: Content, beside anchor: CGRect, side: DockSide,
                                        onCancel: @escaping () -> Void) {
        close()
        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize
        let x = side == .right ? anchor.maxX - size.width : anchor.minX
        let panel = KeyPanel(contentRect: CGRect(x: x, y: anchor.midY - size.height / 2, width: size.width, height: size.height),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                // the view draws its own
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        self.onCancel = onCancel
    }

    /// The system loupe for picking any color on screen. Focus comes back to the panel afterwards.
    private func sampleScreenColor(then picked: @escaping @MainActor (RGBColor) -> Void) {
        NSColorSampler().show { [weak self] color in
            MainActor.assumeIsolated {
                if let color = color?.usingColorSpace(.sRGB) {
                    picked(RGBColor(red: Self.byte(color.redComponent), green: Self.byte(color.greenComponent),
                                    blue: Self.byte(color.blueComponent)))
                }
                self?.panel?.makeKeyAndOrderFront(nil)
            }
        }
    }

    private static func byte(_ component: CGFloat) -> UInt8 {
        UInt8((min(max(component, 0), 1) * 255).rounded())
    }
}

/// A borderless panel that can take the keyboard. Handles ⌘X/C/V/A/Z itself, since a menu bar
/// app has no Edit menu to route them.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let action = Self.editActions[event.charactersIgnoringModifiers ?? ""],
           NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private static let editActions: [String: Selector] = [
        "x": #selector(NSText.cut(_:)),
        "c": #selector(NSText.copy(_:)),
        "v": #selector(NSText.paste(_:)),
        "a": #selector(NSText.selectAll(_:)),
        "z": Selector(("undo:")),
    ]
}

// MARK: - Views

/// Shared look for the input panels: material card with a hairline and shadow.
private struct InputCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12, weight: .semibold))
            content
        }
        .padding(14)
        .frame(width: 236, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .padding(16)                           // room for the shadow inside the transparent window
    }
}

private struct SizeInputView: View {
    enum Unit: Int { case kb = 1000, mb = 1_000_000 }

    let onDone: @MainActor (Int) -> Void
    let onCancel: @MainActor () -> Void
    @State private var amount: String
    @State private var unit: Unit
    @FocusState private var focused: Bool

    init(initial: Int, onDone: @escaping @MainActor (Int) -> Void, onCancel: @escaping @MainActor () -> Void) {
        self.onDone = onDone
        self.onCancel = onCancel
        let inMB = initial >= 1_000_000
        let value = Double(initial) / Double(inMB ? Unit.mb.rawValue : Unit.kb.rawValue)
        _amount = State(initialValue: value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value))
        _unit = State(initialValue: inMB ? .mb : .kb)
    }

    private var bytes: Int? {
        guard let value = Double(amount.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        let bytes = Int(value * Double(unit.rawValue))
        return EncoderTuning.customSizeRange.contains(bytes) ? bytes : nil
    }

    var body: some View {
        InputCard(title: "Compress to under") {
            HStack(spacing: 8) {
                TextField("500", text: $amount)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .focused($focused)
                    .onSubmit(done)
                Picker("Unit", selection: $unit) {
                    Text("KB").tag(Unit.kb)
                    Text("MB").tag(Unit.mb)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 100)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Compress", action: done).keyboardShortcut(.defaultAction).disabled(bytes == nil)
            }
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func done() {
        if let bytes { onDone(bytes) }
    }
}

private struct ColorInputView: View {
    /// Quick picks: white, black, two neutrals and a few common accents.
    static let presets = ["#FFFFFF", "#000000", "#F2F2F7", "#1C1C1E", "#FF3B30", "#FF9500", "#34C759", "#0A84FF"]
        .compactMap(RGBColor.init(hex:))

    let onDone: @MainActor (RGBColor) -> Void
    let onCancel: @MainActor () -> Void
    let sample: @MainActor (@escaping @MainActor (RGBColor) -> Void) -> Void
    @State private var hex: String
    @FocusState private var focused: Bool

    init(initial: RGBColor, onDone: @escaping @MainActor (RGBColor) -> Void, onCancel: @escaping @MainActor () -> Void,
         sample: @escaping @MainActor (@escaping @MainActor (RGBColor) -> Void) -> Void) {
        self.onDone = onDone
        self.onCancel = onCancel
        self.sample = sample
        _hex = State(initialValue: initial.hex)
    }

    private var color: RGBColor? { RGBColor(hex: hex) }

    var body: some View {
        InputCard(title: "Background color") {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(rgb: color ?? .white))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                    .frame(width: 28, height: 28)
                TextField("#FFFFFF", text: $hex)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 100)
                    .focused($focused)
                    .onSubmit(done)
                    .accessibilityLabel("Hex color")
                Button {
                    sample { hex = $0.hex }
                } label: {
                    Image(systemName: "eyedropper")
                }
                .help("Pick a color from the screen")
                .accessibilityLabel("Pick a color from the screen")
            }
            HStack(spacing: 6) {
                ForEach(Self.presets, id: \.self) { preset in
                    Button { hex = preset.hex } label: {
                        Circle()
                            .fill(Color(rgb: preset))
                            .overlay(Circle().strokeBorder(preset == color ? Color.accentColor : Color.primary.opacity(0.2),
                                                           lineWidth: preset == color ? 2 : 0.5))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.name)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Remove BG", action: done).keyboardShortcut(.defaultAction).disabled(color == nil)
            }
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func done() {
        if let color { onDone(color) }
    }
}

extension Color {
    init(rgb color: RGBColor) {
        self.init(.sRGB, red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255)
    }
}
