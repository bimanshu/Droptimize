import SwiftUI

/// Draws the bubble and everything around it on a fixed square canvas centered on the bubble.
/// Purely visual: events are handled by `BubbleHostView`.
struct BubbleView: View {
    @ObservedObject var model: BubbleModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            catchArea
            RadialMenu(menu: model.menu, side: model.side, isOpen: model.isMenuOpen, target: model.target,
                       submenu: model.submenu)
            accessory
            ForEach(model.ripples) { RippleView(ripple: $0) }
            progressRing
            bubble
        }
        .frame(width: BubbleLayout.canvasSide, height: BubbleLayout.canvasSide)
    }

    // MARK: Bubble

    private var bubble: some View {
        ZStack {
            Circle().fill(.regularMaterial)
            Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            glyph
                .id(glyphKey)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
        }
        .frame(width: Motion.bubbleDiameter, height: Motion.bubbleDiameter)
        .shadow(color: .black.opacity(0.25), radius: Motion.bubbleShadowRadius, y: 2)
        .scaleEffect(bubbleScale)
        .opacity(bubbleOpacity)
        .modifier(Shake(travel: reduceMotion ? 0 : Motion.shakeTravel, shakes: CGFloat(model.shakes)))
        .animation(Motion.spring.animation, value: bubbleScale)
        .animation(Motion.spring.animation, value: bubbleOpacity)
        .animation(Motion.spring.animation, value: glyphKey)
        .animation(.easeOut(duration: Motion.shakeDuration), value: model.shakes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Droptimize")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Drop images or videos here to optimize them.")
    }

    @ViewBuilder private var glyph: some View {
        switch model.phase {
        case .idle:
            LogoMark()
                .foregroundStyle(.secondary)
        case .menu:
            if let title = model.target.flatMap(model.menu.title(for:)) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 4)
            } else {
                LogoMark()
                    .foregroundStyle(Color.accentColor)
            }
        case .asking:
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.accentColor)
        case .working(let progress):
            if model.isHovering {
                Image(systemName: "xmark")       // a click cancels
                    .font(.system(size: 13, weight: .bold))
            } else if progress.total > 1 {
                Text("\(progress.completed)/\(progress.total)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                LogoMark()
                    .foregroundStyle(.tertiary)
            }
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.accentColor)
        case .message:
            Image(systemName: "exclamationmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }

    /// Changes whenever the glyph should swap with a transition.
    private var glyphKey: String {
        switch model.phase {
        case .idle: return "idle"
        case .menu: return "menu-\(model.target.flatMap(model.menu.title(for:)) ?? "none")"
        case .asking: return "asking"
        case .working(let progress): return model.isHovering ? "cancel" : (progress.total > 1 ? "count" : "working")
        case .done: return "done"
        case .message: return "message"
        }
    }

    private var bubbleScale: CGFloat {
        if reduceMotion { return 1 }
        if model.isMenuOpen { return Motion.bubbleAwakeScale }
        return model.isHovering ? Motion.bubbleHoverScale : 1
    }

    private var bubbleOpacity: Double {
        model.phase == .idle && !model.isHovering ? Motion.bubbleIdleOpacity : 1
    }

    private var accessibilityValue: String {
        switch model.phase {
        case .idle: return ""
        case .menu:
            guard let target = model.target else { return "" }
            return model.menu.option(for: target)?.accessibilityLabel ?? model.menu.action(for: target)?.accessibilityLabel ?? ""
        case .asking: return "Waiting for your choice"
        case .working(let progress): return "Working, \(Int(progress.fraction * 100)) percent"
        case .done(let info): return "Done, \(info.savingText.replacingOccurrences(of: "\u{2212}", with: "")) smaller"
        case .message(let text): return text
        }
    }

    // MARK: Around the bubble

    /// Nearly invisible disc behind the open menu so the gaps between segments (and out to the
    /// options) still catch the drag.
    private var catchArea: some View {
        let submenu = model.submenu.flatMap {
            MenuGeometry(side: model.side, optionCounts: model.menu.geometryOptionCounts).submenu(for: $0)
        }
        let diameter = BubbleLayout.catchDiameter(segments: model.menu.segments.count, submenu: submenu)
        return Circle()
            .fill(Color.black.opacity(model.isMenuOpen ? Motion.hitCatchOpacity : 0))
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }

    /// Fills as work is done (each finished file, or frames of a video); spins until there's something to show.
    @ViewBuilder private var progressRing: some View {
        if case .working(let progress) = model.phase {
            Group {
                if progress.fraction > 0 {
                    Circle()
                        .trim(from: 0, to: progress.fraction)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: Motion.progressLineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(Motion.hoverSpring.animation, value: progress.fraction)
                } else {
                    SpinnerRing(spins: !reduceMotion)
                }
            }
            .frame(width: Motion.progressRingDiameter, height: Motion.progressRingDiameter)
            .transition(.opacity)
            .accessibilityHidden(true)
        }
    }

    /// The result card or a message, beside the bubble on the side facing into the screen.
    private var accessory: some View {
        let layout = BubbleLayout(side: model.side)
        return ZStack {
            switch model.phase {
            case .done(let info):
                ResultCard(info: info).transition(accessoryTransition)
            case .message(let text):
                MessagePill(text: text).transition(accessoryTransition)
            default:
                EmptyView()
            }
        }
        .frame(width: Motion.accessoryMaxWidth, height: Motion.accessoryHeight,
               alignment: model.side == .right ? .trailing : .leading)
        .offset(x: layout.accessoryOffset.dx, y: -layout.accessoryOffset.dy)
        .animation(reduceMotion ? .easeOut(duration: Motion.reducedMotionFade) : Motion.spring.animation,
                   value: accessoryKey)
    }

    private var accessoryKey: String {
        switch model.phase {
        case .done(let info): return "done-\(info.id)"
        case .message(let text): return "message-\(text)"
        default: return "none"
        }
    }

    private var accessoryTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let anchor: UnitPoint = model.side == .right ? .trailing : .leading
        return .scale(scale: 0.6, anchor: anchor).combined(with: .opacity)
    }
}

// MARK: - Pieces

/// The done state: thumbnail and saving. Drag it into any app, or click to reveal in Finder.
private struct ResultCard: View {
    let info: DoneInfo

    var body: some View {
        HStack(spacing: 8) {
            thumbnail
            VStack(alignment: .leading, spacing: 1) {
                Text(info.savingText)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                Text(info.detail ?? (info.count > 1 ? "\(info.count) files" : "Drag to use"))
                    .lineLimit(1)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 6)
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Result, \(info.savingText.replacingOccurrences(of: "\u{2212}", with: "")) smaller")
        .accessibilityHint("Drag into any app, or click to show it in Finder.")
    }

    @ViewBuilder private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if let image = info.thumbnail {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: Motion.thumbnailSide, height: Motion.thumbnailSide)
                .clipShape(shape)
        } else {
            shape.fill(Color.primary.opacity(0.08))
                .frame(width: Motion.thumbnailSide, height: Motion.thumbnailSide)
        }
    }
}

/// One short line, such as "Already as small as it gets."
private struct MessagePill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }
}

/// An arc going round the bubble while work has no measurable progress. Still with Reduce Motion.
private struct SpinnerRing: View {
    let spins: Bool

    var body: some View {
        TimelineView(.animation(paused: !spins)) { context in
            let turn = spins
                ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Motion.spinnerPeriod) / Motion.spinnerPeriod
                : 0
            Circle()
                .trim(from: 0, to: Motion.spinnerArc)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: Motion.progressLineWidth, lineCap: .round))
                .rotationEffect(.degrees(turn * 360 - 90))
        }
    }
}

/// A ring that ripples out from where files were dropped.
private struct RippleView: View {
    let ripple: Ripple
    @State private var expanded = false

    var body: some View {
        Circle()
            .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 2)
            .frame(width: Motion.rippleDiameter, height: Motion.rippleDiameter)
            .scaleEffect(expanded ? 4 : 0.5)
            .opacity(expanded ? 0 : 1)
            .offset(x: ripple.offset.dx, y: -ripple.offset.dy)
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(.easeOut(duration: Motion.rippleDuration)) { expanded = true }
            }
    }
}

/// A short horizontal shake, once per increment of `shakes`.
private struct Shake: GeometryEffect {
    var travel: CGFloat
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(shakes * .pi * 6), y: 0))
    }
}
