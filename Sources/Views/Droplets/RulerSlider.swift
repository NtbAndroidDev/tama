import SwiftUI
import AppKit

/// The reference's duration picker: a horizontal ruler of one-minute ticks
/// with a label every five, dragged (or scrolled) under a fixed centre caret.
/// Shared by Pomodoro, High Alert and the Timer.
struct RulerSlider: View {
    @Binding var minutes: Int
    var range: ClosedRange<Int>
    var tint: Color = RulerMetrics.orange
    var isEnabled: Bool = true

    /// The fractional value while a drag or fling is in flight.
    @State private var liveValue: Double?
    @State private var dragStart: Double?
    /// Bumped per scroll event, so the ruler settles once scrolling stops.
    @State private var scrollGeneration = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var value: Double { liveValue ?? Double(minutes) }

    var body: some View {
        GeometryReader { geo in
            RulerTicks(value: value, range: range, tint: tint)
            .overlay { HorizontalScrollCatcher { delta in scroll(by: delta) } }
            .contentShape(Rectangle())
            .gesture(drag, including: isEnabled ? .all : .none)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: RulerMetrics.height)
        .opacity(isEnabled ? 1 : 0.45)
        // Changed elsewhere (Settings, the Focus/Break switch): follow it.
        .onChange(of: minutes) { _, new in
            if dragStart == nil, let live = liveValue, abs(live - Double(new)) >= 1 { liveValue = nil }
        }
        .accessibilityElement()
        .accessibilityLabel("Duration")
        .accessibilityValue("\(minutes) minutes")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: set(minutes + 1)
            case .decrement: set(minutes - 1)
            @unknown default: break
            }
        }
    }

    // MARK: Input

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { gesture in
                let start = dragStart ?? Double(minutes)
                if dragStart == nil { dragStart = start }
                let next = clamp(start - Double(gesture.translation.width / RulerMetrics.tickSpacing))
                if Int(next.rounded()) != Int(value.rounded()) { DroppyAudio.playTick() }
                liveValue = next
            }
            .onEnded { gesture in
                let start = dragStart ?? Double(minutes)
                dragStart = nil
                // A fling keeps going a little, like a scroll view.
                let predicted = clamp(start - Double(gesture.predictedEndTranslation.width / RulerMetrics.tickSpacing))
                let target = Int(predicted.rounded())
                if reduceMotion {
                    liveValue = nil
                    set(target)
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { liveValue = Double(target) }
                    set(target)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if dragStart == nil { liveValue = nil }
                    }
                }
            }
    }

    private func scroll(by delta: CGFloat) {
        guard isEnabled else { return }
        let next = clamp(value - Double(delta / RulerMetrics.tickSpacing))
        liveValue = next
        let rounded = Int(next.rounded())
        if rounded != minutes {
            set(rounded)
            DroppyAudio.playTick()
        }
        scrollGeneration += 1
        let generation = scrollGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard generation == scrollGeneration, dragStart == nil else { return }
            withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.snap)) { liveValue = nil }
        }
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, Double(range.lowerBound)), Double(range.upperBound))
    }

    private func set(_ value: Int) {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        if clamped != minutes { minutes = clamped }
    }
}


/// The ruler itself, animatable so a fling glides to its minute.
private struct RulerTicks: View, Animatable {
    var value: Double
    let range: ClosedRange<Int>
    let tint: Color

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
    }


    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let spacing = RulerMetrics.tickSpacing
        let mid = size.width / 2
        let half = Int(mid / spacing) + 2
        let base = Int(value.rounded(.down))
        let fraction = value - Double(base)
        let tickTop = RulerMetrics.labelHeight + 4
        let tickHeight = RulerMetrics.tickHeight

        for step in -half...half {
            let minute = base + step
            guard range.contains(minute) else { continue }
            let x = mid + (CGFloat(step) - CGFloat(fraction)) * spacing
            guard x > -spacing, x < size.width + spacing else { continue }
            // Ticks fade towards the edges, like the reference's.
            let distance = abs(x - mid) / mid
            let fade = max(0.12, 1 - distance * 0.85)
            let isCentre = abs(x - mid) < spacing / 2
            let rect = CGRect(x: x - 1, y: tickTop, width: 2, height: tickHeight)
            let color = isCentre ? Color.white : tint.opacity(fade * (minute.isMultiple(of: 5) ? 1 : 0.7))
            context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))

            if minute.isMultiple(of: 5) {
                let label = context.resolve(
                    Text("\(minute)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(isCentre ? .white : tint.opacity(fade))
                )
                context.draw(label, at: CGPoint(x: x, y: RulerMetrics.labelHeight / 2), anchor: .center)
            }
        }

        // The caret under the centre tick.
        var caret = Path()
        let caretTop = tickTop + tickHeight + 3
        caret.move(to: CGPoint(x: mid, y: caretTop))
        caret.addLine(to: CGPoint(x: mid + 5, y: caretTop + 7))
        caret.addLine(to: CGPoint(x: mid - 5, y: caretTop + 7))
        caret.closeSubpath()
        context.fill(caret, with: .color(tint))
    }
}

enum RulerMetrics {
    static let orange = Color(red: 1.0, green: 0.62, blue: 0.24)
    static let height: CGFloat = 50
    static let labelHeight: CGFloat = 14
    static let tickHeight: CGFloat = 20
    static let tickSpacing: CGFloat = 9.5
}

/// "45:00", or "1:30:00" past the hour.
func rulerClock(_ seconds: Int) -> String {
    let s = max(seconds, 0)
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
}

// MARK: - Timer controls

/// The orange "Start Timer" capsule.
struct RulerStartButton: View {
    var title = "Start timer"
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(RulerMetrics.orange)
                .lineLimit(1)
                .padding(.horizontal, 18)
                .frame(height: 36)
                .background(Capsule().fill(RulerMetrics.orange.opacity(isHovered ? 0.34 : 0.24)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .onHover { isHovered = isEnabled && $0 }
        .animation(DS.Motion.hover, value: isHovered)
    }
}

/// A round control beside it: grey, or orange-tinted for pause/stop.
struct RulerRoundButton: View {
    let systemName: String
    var orange = false
    var title: String?
    let help: String
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    init(_ systemName: String, orange: Bool = false, title: String? = nil, help: String, action: @escaping () -> Void) {
        self.systemName = systemName
        self.orange = orange
        self.title = title
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .bold))
                    .accessibilityHidden(true)
                if let title {
                    Text(title).font(DS.Typo.headline).lineLimit(1)
                }
            }
            .foregroundStyle(orange ? RulerMetrics.orange : Color.white.opacity(0.85))
            .padding(.horizontal, title == nil ? 0 : 12)
            .frame(minWidth: 36, minHeight: 36)
            .background(Capsule().fill(orange ? RulerMetrics.orange.opacity(isHovered ? 0.34 : 0.24)
                                              : Color.white.opacity(isHovered ? 0.2 : 0.13)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .onHover { isHovered = isEnabled && $0 }
        .animation(DS.Motion.hover, value: isHovered)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The big orange time on the right, with an optional caption before it.
struct RulerClock: View {
    let text: String
    var caption: String?

    init(seconds: Int, caption: String? = nil) {
        self.text = rulerClock(seconds)
        self.caption = caption
    }

    init(text: String, caption: String? = nil) {
        self.text = text
        self.caption = caption
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
            if let caption {
                Text(caption)
                    .font(DS.Typo.title)
                    .foregroundStyle(RulerMetrics.orange.opacity(0.9))
                    .lineLimit(1)
            }
            Text(text)
                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(RulerMetrics.orange)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Scroll

/// Two-finger horizontal scrolls (and a plain wheel) over the ruler.
private struct HorizontalScrollCatcher: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onScroll = onScroll
    }

    final class CatcherView: NSView {
        var onScroll: ((CGFloat) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Only scrolls: clicks and drags go to the SwiftUI gesture under it.
            guard let event = NSApp.currentEvent, event.type == .scrollWheel else { return nil }
            return super.hitTest(point)
        }

        override func scrollWheel(with event: NSEvent) {
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            let delta = abs(dx) >= abs(dy) ? dx : -dy
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 9
            onScroll?(delta * scale)
        }
    }
}
