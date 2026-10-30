import SwiftUI

/// The segments that fan out around the bubble while a drag is over it (CORE.md §4.2), and
/// the smaller option bubbles that fan out beyond a hovered segment.
struct RadialMenu: View {
    let menu: ActionMenu
    let side: DockSide
    let isOpen: Bool
    let target: MenuTarget?
    /// The segment whose options are showing.
    let submenu: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let geometry = MenuGeometry(side: side, optionCounts: menu.geometryOptionCounts)
        ZStack {
            ForEach(menu.segments.indices, id: \.self) { index in
                // A segment stays lit while one of its options is hovered.
                let highlighted = target?.segment == index
                let offset = geometry.ring.offset(of: index)
                // With Reduce Motion the segments fade in place instead of scaling and fanning out.
                let placed = isOpen || reduceMotion
                SegmentView(action: menu.segments[index], highlighted: highlighted)
                    .scaleEffect(scale(open: isOpen, highlighted: highlighted))
                    .offset(x: placed ? offset.dx : 0, y: placed ? -offset.dy : 0)
                    .opacity(isOpen ? 1 : 0)
                    .animation(openAnimation(index: index), value: isOpen)
                    .animation(Motion.hoverSpring.animation, value: highlighted)
            }
            // Every segment's options are always here, hidden at their segment until it's hovered,
            // so they can spring out of it and back into it.
            ForEach(menu.segments.indices, id: \.self) { segment in
                if let layout = geometry.submenu(for: segment) {
                    let parent = geometry.ring.offset(of: segment)
                    let shown = isOpen && submenu == segment
                    ForEach(0..<layout.count, id: \.self) { index in
                        let offset = layout.offset(of: index)
                        let placed = shown || reduceMotion
                        OptionBubble(option: menu.options[segment][index],
                                     highlighted: target == .option(segment: segment, index: index))
                            .scaleEffect(reduceMotion || shown ? 1 : 0.3)
                            .offset(x: placed ? offset.dx : parent.dx, y: -(placed ? offset.dy : parent.dy))
                            .opacity(shown ? 1 : 0)
                            .animation(optionAnimation(index: index, shown: shown), value: shown)
                            .accessibilityHidden(!shown)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(!isOpen)
    }

    private func scale(open: Bool, highlighted: Bool) -> CGFloat {
        if reduceMotion { return 1 }
        guard open else { return 0.4 }
        return highlighted ? Motion.segmentHoverScale : 1
    }

    /// Fans out in order with a short stagger; folds back in all at once.
    private func openAnimation(index: Int) -> Animation {
        if reduceMotion { return .easeOut(duration: Motion.reducedMotionFade) }
        return isOpen ? Motion.spring.animation.delay(Double(index) * Motion.fanStagger) : Motion.spring.animation
    }

    private func optionAnimation(index: Int, shown: Bool) -> Animation {
        if reduceMotion { return .easeOut(duration: Motion.reducedMotionFade) }
        return shown ? Motion.spring.animation.delay(Double(index) * Motion.optionStagger) : Motion.hoverSpring.animation
    }
}

/// One option bubble: a size ("500K"), a symbol, or a color swatch.
private struct OptionBubble: View {
    let option: MenuOption
    let highlighted: Bool

    var body: some View {
        content
            .frame(width: Motion.optionDiameter, height: Motion.optionDiameter)
            .background {
                if fillsWithAccent {
                    Circle().fill(Color.accentColor)
                } else {
                    Circle().fill(.regularMaterial)
                }
            }
            .overlay(Circle().strokeBorder(highlighted ? Color.accentColor : Color.primary.opacity(0.12),
                                           lineWidth: highlighted ? 2 : 0.5))
            .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
            .scaleEffect(highlighted ? Motion.optionHoverScale : 1)
            .animation(Motion.hoverSpring.animation, value: highlighted)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(option.accessibilityLabel)
            .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    @ViewBuilder private var content: some View {
        switch option.label {
        case .text(let text):
            Text(text)
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(fillsWithAccent ? Color.white : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 2)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(fillsWithAccent ? Color.white : Color.primary)
        case .swatch(let color):
            Circle()
                .fill(Color(rgb: color))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                .padding(6)
        }
    }

    /// Sizes and symbols fill with the accent color when hovered; swatches keep showing their color
    /// and get an accent ring instead.
    private var fillsWithAccent: Bool {
        if case .swatch = option.label { return false }
        return highlighted
    }
}

private struct SegmentView: View {
    let action: Action
    let highlighted: Bool

    var body: some View {
        Image(systemName: action.symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(highlighted ? Color.white : Color.primary)
            .frame(width: Motion.segmentDiameter, height: Motion.segmentDiameter)
            .background {
                if highlighted {
                    Circle().fill(Color.accentColor)
                } else {
                    Circle().fill(.regularMaterial)
                }
            }
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(action.accessibilityLabel)
            .accessibilityAddTraits(highlighted ? .isSelected : [])
    }
}
