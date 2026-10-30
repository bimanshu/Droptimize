import SwiftUI

/// The segments that fan out around the bubble while a drag is over it (CORE.md §4.2).
struct RadialMenu: View {
    let menu: ActionMenu
    let side: DockSide
    let isOpen: Bool
    let target: MenuTarget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let ring = RadialLayout(count: menu.segments.count, side: side)
        ZStack {
            ForEach(menu.segments.indices, id: \.self) { index in
                let highlighted = target == .segment(index)
                let offset = ring.offset(of: index)
                // With Reduce Motion the segments fade in place instead of scaling and fanning out.
                let placed = isOpen || reduceMotion
                SegmentView(action: menu.segments[index], highlighted: highlighted)
                    .scaleEffect(scale(open: isOpen, highlighted: highlighted))
                    .offset(x: placed ? offset.dx : 0, y: placed ? -offset.dy : 0)
                    .opacity(isOpen ? 1 : 0)
                    .animation(openAnimation(index: index), value: isOpen)
                    .animation(Motion.hoverSpring.animation, value: highlighted)
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
