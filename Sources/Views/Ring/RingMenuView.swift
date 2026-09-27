import SwiftUI

/// Bubbles around a dismiss button, with the pointed-at wedge lit up.
struct RingMenuView: View {
    @ObservedObject var model: RingMenuModel
    @ObservedObject private var state = AppState.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let radius: CGFloat = 100
    private let bubble: CGFloat = 54
    private let hub: CGFloat = 66

    private var count: Int { max(model.actions.count, 1) }
    private var step: Angle { .degrees(360 / Double(count)) }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.82))
                .overlay(Circle().strokeBorder(DS.Palette.hairline, lineWidth: 1))
                .frame(width: radius * 2 + bubble + 16, height: radius * 2 + bubble + 16)
                .dsShadow(.high)

            if let selected = model.selected {
                RingWedge(center: step * Double(selected), width: step, inner: hub / 2 + 6,
                          outer: radius + bubble / 2 + 8)
                    .fill(DS.accent.opacity(0.28))
                    .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: selected)
            }

            ForEach(Array(model.actions.enumerated()), id: \.element) { index, action in
                bubbleView(action, index: index)
                    .offset(offset(for: index))
                    .scaleEffect(model.isPresented || reduceMotion ? 1 : 0.4)
                    .opacity(model.isPresented ? 1 : 0)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.12)
                            : .spring(response: 0.32, dampingFraction: 0.68).delay(Double(index) * 0.018),
                        value: model.isPresented
                    )
            }

            hubView
                .scaleEffect(model.isPresented || reduceMotion ? 1 : 0.6)
                .opacity(model.isPresented ? 1 : 0)
                .animation(reduceMotion ? .easeOut(duration: 0.12) : DS.Motion.snap, value: model.isPresented)
        }
        .frame(width: RingWindowController.size, height: RingWindowController.size)
        .scaleEffect(model.isPresented || reduceMotion ? 1 : 0.85)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.72), value: model.isPresented)
    }

    /// Offsets collapse to the center while hidden, so the bubbles burst outward.
    private func offset(for index: Int) -> CGSize {
        let distance = model.isPresented || reduceMotion ? radius : 0
        let angle = (step * Double(index)).radians
        return CGSize(width: sin(angle) * distance, height: -cos(angle) * distance)
    }

    private func bubbleView(_ action: RingAction, index: Int) -> some View {
        let isSelected = model.selected == index
        return ZStack {
            Circle().fill(isSelected ? DS.accent : NotchPalette.control)
            Circle().strokeBorder(isSelected ? DS.accentHairline : DS.Palette.hairline, lineWidth: 1)
            Image(systemName: action.systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: bubble, height: bubble)
        .overlay(alignment: .topTrailing) {
            Text("\(index + 1)")
                .font(DS.Typo.numericSmall)
                .foregroundStyle(DS.Palette.textSecondary)
                .frame(width: 15, height: 15)
                .background(Circle().fill(Color.black.opacity(0.7)))
                .offset(x: 2, y: -2)
        }
        .scaleEffect(isSelected && !reduceMotion ? 1.12 : 1)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.hover), value: isSelected)
        // One element per bubble: the glyph and the number badge are its parts.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(index + 1). \(action.currentTitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var hubView: some View {
        ZStack {
            Circle().fill(DS.Palette.ink)
            Circle().strokeBorder(DS.Palette.hairlineStrong, lineWidth: 1)
            if let selected = model.selected, model.actions.indices.contains(selected) {
                Text(model.actions[selected].currentTitle)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, DS.Space.sm)
            } else {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.Palette.textSecondary)
            }
        }
        .frame(width: hub, height: hub)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.selected.flatMap { model.actions.indices.contains($0) ? model.actions[$0].currentTitle : nil } ?? "Close")
    }
}

/// An annular slice centered on `center` (0 = 12 o'clock, clockwise).
private struct RingWedge: Shape {
    var center: Angle
    var width: Angle
    var inner: CGFloat
    var outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let mid = CGPoint(x: rect.midX, y: rect.midY)
        // Path angles run from 3 o'clock; shift so 0 means straight up.
        let start = center - width / 2 - .degrees(90)
        let end = center + width / 2 - .degrees(90)
        var path = Path()
        path.addArc(center: mid, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: mid, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}
