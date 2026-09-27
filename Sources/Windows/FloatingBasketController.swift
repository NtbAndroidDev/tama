import SwiftUI
import AppKit

/// A Basket's panel. It can take keyboard focus without activating Tama, so
/// the arrow keys, ⌘A, ⌫ and ⌘C reach the files the way they do in the Tray
/// while the app you were in stays frontmost. A Basket only takes the keys
/// when it is clicked — one left sitting on screen never swallows what is
/// being typed — and clicking any other app takes them straight back, since
/// that app's own window becomes key.
final class BasketPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// On mouse-up, not mouse-down: a file dragged out of the Basket leaves
    /// through a dragging session and never sends one, so taking the keys is
    /// left to clicks that stayed clicks. Dragging a file into the editor
    /// somebody is writing in must not take the keyboard away from it.
    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
        if event.type == .leftMouseUp, !isKeyWindow { makeKey() }
    }
}

/// Owns one floating panel per open Basket. `sync()` matches the panels to
/// `AppState.baskets` and `isBasketVisible`; Single Basket mode only ever
/// shows the first Basket.
@MainActor
public final class FloatingBasketController: NSObject {
    public static let shared = FloatingBasketController()

    private var panels: [UUID: BasketPanel] = [:]
    private var minimized: Set<UUID> = []

    private override init() {
        super.init()
    }

    public func setup() {
        sync()
    }

    /// Kept for callers that flip visibility directly.
    public func setVisible(_ visible: Bool) {
        sync()
    }

    static let fullSize = CGSize(width: DroppyShelfMetrics.basketWidth, height: DroppyShelfMetrics.basketHeight)
    static let minimizedSize = CGSize(width: 96, height: 38)

    /// Shows the Baskets that should be on screen and hides the rest.
    public func sync() {
        let state = AppState.shared
        let wanted: [Basket] = {
            guard state.isBasketVisible else { return [] }
            if state.basketMode == .single { return Array(state.baskets.prefix(1)) }
            return state.baskets.filter(\.isOpen)
        }()
        let wantedIDs = Set(wanted.map(\.id))
        for (id, panel) in panels where !wantedIDs.contains(id) {
            panel.orderOut(nil)
            // A Basket that's gone for good frees its panel.
            if !state.baskets.contains(where: { $0.id == id }) {
                panels[id] = nil
                minimized.remove(id)
            }
        }
        for basket in wanted {
            let panel = panels[basket.id] ?? makePanel(for: basket.id, index: state.baskets.firstIndex(of: basket) ?? 0)
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
    }

    private func makePanel(for id: UUID, index: Int) -> BasketPanel {
        let size = Self.fullSize
        let panel = BasketPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        let host = NSHostingView(rootView: FloatingBasketView(basketID: id))
        // Fixed-size panel: the frame is set here, so SwiftUI must not also push a
        // min/max content size onto the window. That feedback is what AppKit aborts
        // with an "Update Constraints in Window" throw.
        host.sizingOptions = []
        panel.contentView = host
        // Black glass surfaces: keep text light even when the system is in Light Mode.
        panel.appearance = NSAppearance(named: .darkAqua)
        if let screen = NSScreen.main {
            // Later Baskets cascade from the first.
            let step = CGFloat(index) * 28
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2 + step,
                                         y: screen.frame.midY - size.height / 2 - step))
        }
        panels[id] = panel
        CaptureExclusion.register(panel)
        return panel
    }

    public func bringToFront(_ id: UUID) {
        panels[id]?.orderFrontRegardless()
    }

    /// Puts a Basket beside the pointer, on the pointer's screen, so a shake
    /// mid-drag brings it within reach of the drop instead of wherever it was.
    public func moveNearPointer(_ id: UUID, offset: CGFloat = 0) {
        let panel = panels[id] ?? makePanel(for: id, index: 0)
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x + 40 + offset, y: mouse.y - size.height / 2 - offset)
        if origin.x + size.width > visible.maxX { origin.x = mouse.x - 40 - size.width - offset }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        panel.setFrameOrigin(origin)
    }

    public func updatePanelSize(_ id: UUID, isMinimized: Bool) {
        guard let panel = panels[id] else { return }
        if isMinimized { minimized.insert(id) } else { minimized.remove(id) }
        let target = isMinimized ? Self.minimizedSize : Self.fullSize
        var frame = panel.frame
        frame.origin.y -= target.height - frame.height
        frame.size = target
        panel.setFrame(frame, display: true, animate: true)
    }

    /// The pointer is over one of the Baskets (Auto-hide leaves them alone then).
    public var isPointerOverBasket: Bool {
        let mouse = NSEvent.mouseLocation
        return panels.values.contains { $0.isVisible && $0.frame.insetBy(dx: -12, dy: -12).contains(mouse) }
    }
}
