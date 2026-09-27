import AppKit
import Carbon.HIToolbox
import SwiftUI

/// What the ring view draws: the actions, the one the pointer points at, and
/// whether it is popping in or out.
@MainActor
final class RingMenuModel: ObservableObject {
    @Published var actions: [RingAction] = []
    @Published var selected: Int?
    @Published var isPresented = false
}

/// Takes key focus (for 1–8, Return and Esc) without activating Tama, so
/// Window Snap and Color Dropper still act on the app underneath.
final class RingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The radial menu at the pointer. Opened by the Ring shortcut: tap it and click
/// or press a number, or hold it, point in a direction and let go.
@MainActor
public final class RingWindowController: NSObject {
    public static let shared = RingWindowController()

    static let size: CGFloat = 300
    /// Pointer closer to the center than this selects nothing (the dismiss button).
    static let deadZone: CGFloat = 34

    let model = RingMenuModel()
    private var panel: RingPanel?
    private var monitors: [Any] = []
    private var hotKeyDownAt: Date?
    private var closeWork: DispatchWorkItem?

    public var isVisible: Bool { panel?.isVisible == true && model.isPresented }

    private override init() {
        super.init()
    }

    // MARK: Shortcut

    public func hotKeyPressed() {
        if isVisible {
            close()
            return
        }
        hotKeyDownAt = Date()
        show()
    }

    /// Releasing after a real hold fires whatever the pointer is aiming at; a
    /// quick tap leaves the ring open for a click or a number key.
    public func hotKeyReleased() {
        defer { hotKeyDownAt = nil }
        guard isVisible, let down = hotKeyDownAt, Date().timeIntervalSince(down) > 0.25,
              let index = model.selected else { return }
        fire(index)
    }

    // MARK: Show / close

    public func show() {
        let actions = RingActionStore.shared.actions
        guard !actions.isEmpty else { return }
        closeWork?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        var frame = NSRect(x: mouse.x - Self.size / 2, y: mouse.y - Self.size / 2, width: Self.size, height: Self.size)
        if let visible = screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        panel.setFrame(frame, display: false)

        model.actions = actions
        model.selected = nil
        model.isPresented = false
        panel.orderFrontRegardless()
        panel.makeKey()
        installMonitors()
        updateSelection()
        // Next runloop pass, so the view first renders collapsed and then springs out.
        DispatchQueue.main.async { [weak self] in self?.model.isPresented = true }
        DroppyAudio.playTick()
    }

    public func close() {
        removeMonitors()
        hotKeyDownAt = nil
        model.isPresented = false
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.model.isPresented else { return }
                self.panel?.orderOut(nil)
            }
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    func fire(_ index: Int) {
        guard model.actions.indices.contains(index) else { return }
        let action = model.actions[index]
        close()
        DroppyAudio.playTick()
        // After the ring is gone, so a snip or the color sampler doesn't catch it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            MainActor.assumeIsolated { action.perform() }
        }
    }

    private func makePanel() -> RingPanel {
        let panel = RingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: RingMenuView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }

    // MARK: Pointer & keys

    private func updateSelection() {
        guard let panel else { return }
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - center.x
        let dy = mouse.y - center.y
        let count = model.actions.count
        guard count > 0, hypot(dx, dy) > Self.deadZone else {
            if model.selected != nil { model.selected = nil }
            return
        }
        // Clockwise from 12 o'clock, matching how the view lays the bubbles out.
        var angle = atan2(dx, dy)
        if angle < 0 { angle += 2 * .pi }
        let step = 2 * .pi / CGFloat(count)
        let index = Int((angle / step).rounded()) % count
        if model.selected != index { model.selected = index }
    }

    private func installMonitors() {
        removeMonitors()
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { _ in
            MainActor.assumeIsolated { RingWindowController.shared.updateSelection() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            self?.updateSelection()
            return event
        }) { monitors.append(m) }

        // Clicks anywhere else close the ring.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { _ in
            MainActor.assumeIsolated { RingWindowController.shared.close() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            guard let self, self.isVisible else { return event }
            guard event.window === self.panel else {
                self.close()
                return event
            }
            self.updateSelection()
            if let index = self.model.selected { self.fire(index) } else { self.close() }
            return nil
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, self.isVisible, event.window === self.panel else { return event }
            return self.handleKey(event) ? nil : event
        }) { monitors.append(m) }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let count = model.actions.count
        switch Int(event.keyCode) {
        case kVK_Escape:
            close()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let index = model.selected { fire(index) } else { close() }
        case kVK_RightArrow, kVK_DownArrow:
            model.selected = ((model.selected ?? -1) + 1) % count
        case kVK_LeftArrow, kVK_UpArrow:
            model.selected = ((model.selected ?? count) - 1 + count) % count
        default:
            guard let digit = event.charactersIgnoringModifiers.flatMap(Int.init), (1...count).contains(digit) else {
                return false
            }
            fire(digit - 1)
        }
        return true
    }
}
