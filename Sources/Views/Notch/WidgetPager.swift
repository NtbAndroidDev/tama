import SwiftUI
import AppKit

/// The widget row, a page of icons at a time. A horizontal ScrollView won't do
/// here: on macOS it ignores a mouse wheel and vertical trackpad scrolls, and
/// can't be dragged, so most of the Droplets were out of reach. Pages flip on
/// any scroll, a drag, or the dots underneath.
struct WidgetPager: View {
    let droplets: [DropletModel]
    let badge: (DropletModel) -> String?
    let open: (DropletModel) -> Void

    /// Only checked when a scroll flips the page, so not observed: the parent
    /// hands in `droplets`, and observing redrew the pager on any AppState write.
    private var state: AppState { AppState.shared }
    @State private var page = 0
    @State private var dragOffset: CGFloat = 0
    /// A drag ends with a mouse-up over an icon; that must not open it.
    @State private var isSwiping = false
    @State private var scroll = WidgetPagerScrollMonitor()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let perPage = 5

    private var pages: [[DropletModel]] {
        stride(from: 0, to: droplets.count, by: Self.perPage).map {
            Array(droplets[$0..<min($0 + Self.perPage, droplets.count)])
        }
    }

    private var pageCount: Int { max(pages.count, 1) }

    var body: some View {
        VStack(spacing: DS.Space.sm) {
            GeometryReader { proxy in
                let width = proxy.size.width
                HStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { _, items in
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(items) { droplet in
                                WidgetIcon(droplet: droplet, badge: badge(droplet)) {
                                    guard !isSwiping else { return }
                                    open(droplet)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            // Keep a short last page on the same grid as the others.
                            ForEach(items.count..<Self.perPage, id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                            }
                        }
                        .frame(width: width, alignment: .top)
                    }
                }
                .offset(x: -CGFloat(page) * width + dragOffset)
                .frame(width: width, alignment: .leading)
                .clipped()
                .contentShape(Rectangle())
                .simultaneousGesture(swipe(width: width))
            }
            .padding(.top, DS.Space.md)

            if pageCount > 1 { dots }
        }
        .background { if pageCount > 1 { arrowShortcuts } }
        .onAppear {
            clampPage()
            scroll.start { step in flip(by: step) }
        }
        .onDisappear { scroll.stop() }
        .onChange(of: droplets.count) { _, _ in clampPage() }
    }

    private var dots: some View {
        // Each dot keeps its 6pt look but takes a 20pt click; the negative
        // spacing and padding keep the row's rhythm and height as before.
        HStack(spacing: -1) {
            ForEach(0..<pageCount, id: \.self) { index in
                PageDot(index: index, count: pageCount, isCurrent: index == page) { go(to: index) }
            }
        }
        .padding(.vertical, -4)
        .padding(.bottom, 4)
    }

    /// ← and → flip pages, the same hidden-button way ShelfView binds ⌘1…⌘4.
    /// Only mounted with the icon row, which has no text field to take arrows from.
    private var arrowShortcuts: some View {
        Group {
            Button("") { flip(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { flip(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func swipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                isSwiping = true
                var offset = value.translation.width
                // Rubber-band past the first and last page.
                if (page == 0 && offset > 0) || (page == pageCount - 1 && offset < 0) { offset /= 3 }
                dragOffset = offset
            }
            .onEnded { value in
                let predicted = value.predictedEndTranslation.width
                let step = predicted < -width / 4 ? 1 : (predicted > width / 4 ? -1 : 0)
                withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) {
                    dragOffset = 0
                    page = min(max(page + step, 0), pageCount - 1)
                }
                if step != 0 { DroppyAudio.playTick() }
                DispatchQueue.main.async { isSwiping = false }
            }
    }

    private func flip(by step: Int) {
        guard state.isIslandExpanded, state.shelfPage == .widgets, state.activeDropletID == nil else { return }
        go(to: page + step)
    }

    private func go(to index: Int) {
        let target = min(max(index, 0), pageCount - 1)
        guard target != page else { return }
        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { page = target }
        DroppyAudio.playTick()
    }

    private func clampPage() {
        page = min(page, pageCount - 1)
    }
}

/// One page dot: a real button, so it can be clicked, hovered and read out.
private struct PageDot: View {
    let index: Int
    let count: Int
    let isCurrent: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.white.opacity(isCurrent ? 0.9 : (isHovered ? 0.55 : 0.28)))
                .frame(width: 6, height: 6)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(DroppyPressStyle(scale: 0.8))
        .onHover { isHovered = $0 }
        .animation(DS.Motion.hover, value: isHovered)
        .help("Page \(index + 1)")
        .accessibilityLabel("Page \(index + 1)")
        .accessibilityValue("\(index + 1) of \(count)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Turns scroll events over the notch panel into page flips: one per wheel
/// notch, one per trackpad gesture (its momentum tail is ignored).
@MainActor
final class WidgetPagerScrollMonitor {
    private var monitor: Any?
    private var accumulated: CGFloat = 0
    private var gestureFlipped = false
    private var lastWheelFlip = Date.distantPast

    func start(onStep: @escaping @MainActor (Int) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // The shelf stays mounted after it closes; only the open Widgets
            // row may take scrolls (the resting notch uses them for volume).
            let state = AppState.shared
            guard let self, event.window === NotchWindowController.shared.panel,
                  state.isIslandExpanded, state.shelfPage == .widgets, state.activeDropletID == nil else { return event }
            return self.handle(event, onStep: onStep) ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent, onStep: @MainActor (Int) -> Void) -> Bool {
        guard event.momentumPhase.isEmpty else { return true }
        // Scrolling right, or down, moves on to the next page.
        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        let delta = abs(dx) > abs(dy) ? -dx : -dy

        guard event.hasPreciseScrollingDeltas else {
            // A mouse wheel: one notch, one page, with a short pause so a
            // fast spin doesn't race to the end.
            guard delta != 0, Date().timeIntervalSince(lastWheelFlip) > 0.25 else { return true }
            lastWheelFlip = Date()
            onStep(delta > 0 ? 1 : -1)
            return true
        }

        if event.phase.contains(.began) {
            accumulated = 0
            gestureFlipped = false
        }
        accumulated += delta
        if !gestureFlipped, abs(accumulated) > 36 {
            gestureFlipped = true
            onStep(accumulated > 0 ? 1 : -1)
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            accumulated = 0
            gestureFlipped = false
        }
        return true
    }
}
