import AppKit
import ApplicationServices

/// What the user picked on the capture overlay, in CoreGraphics coordinates
/// (top-left origin on the primary display).
enum CaptureSelection {
    case rect(CGRect)
    case window(CGWindowID, CGRect)

    var rect: CGRect {
        switch self {
        case let .rect(r), let .window(_, r): r
        }
    }
}

/// A full-screen overlay of our own, one panel per display, for picking what
/// to capture: drag an area, click a window, or hover an accessibility element
/// and click it. Everything comes from the overlay's own mouse events — there
/// is no global monitoring. Esc or a right-click cancels.
@MainActor
final class CaptureSelectionController {
    static let shared = CaptureSelectionController()

    private var panels: [CaptureOverlayPanel] = []
    private var continuation: CheckedContinuation<CaptureSelection?, Never>?
    private(set) var mode: CaptureMode = .area

    /// The hovered window or element and the rubber band being dragged,
    /// all in CoreGraphics coordinates.
    private(set) var highlight: CGRect?
    private(set) var label: String?
    private(set) var dragRect: CGRect?
    private var dragStart: CGPoint?

    private var hoveredWindow: ScreenWindowList.Info?
    /// The hovered element and the ancestors scrolled up to; the last is shown.
    private var elementChain: [AXUIElement] = []
    private var lastHoverPoint: CGPoint?

    /// Window numbers of the overlay panels, always left out of captures.
    var overlayWindowIDs: [CGWindowID] { panels.map { CGWindowID($0.windowNumber) } }

    var isActive: Bool { continuation != nil }

    private init() {}

    /// Shows the overlay and waits for a pick; nil when cancelled.
    func select(mode: CaptureMode) async -> CaptureSelection? {
        if let continuation {
            continuation.resume(returning: nil)
            self.continuation = nil
        }
        self.mode = mode
        reset()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            present()
        }
    }

    // MARK: Presentation

    private func present() {
        tearDown()
        for screen in NSScreen.screens {
            let panel = CaptureOverlayPanel(screen: screen, controller: self)
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        // The overlay needs key focus for Esc; Tama is an agent app.
        NSApp.activate(ignoringOtherApps: true)
        let pointer = NSEvent.mouseLocation
        (panels.first { NSMouseInRect(pointer, $0.frame, false) } ?? panels.first)?.makeKey()
        hover(atCocoa: pointer)
    }

    private func tearDown() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }

    private func reset() {
        highlight = nil
        label = nil
        dragRect = nil
        dragStart = nil
        hoveredWindow = nil
        elementChain = []
        lastHoverPoint = nil
    }

    private func finish(_ selection: CaptureSelection?) {
        tearDown()
        let continuation = self.continuation
        self.continuation = nil
        reset()
        continuation?.resume(returning: selection)
    }

    func cancel() { finish(nil) }

    private func redraw() { panels.forEach { $0.contentView?.needsDisplay = true } }

    // MARK: Events (from the overlay's own views)

    func hover(atCocoa point: CGPoint) {
        guard dragRect == nil, mode == .window || mode == .element else { return }
        let p = WindowSnapService.axPoint(fromCocoa: point)
        if let last = lastHoverPoint, last.distance(to: p) < 1.5 { return }
        lastHoverPoint = p
        // Scrolled up to an ancestor: keep it while the pointer stays inside.
        if elementChain.count > 1, let highlight, highlight.contains(p) { return }

        guard let window = ScreenWindowList.topWindow(at: p, excludingPID: getpid(), normalOnly: mode == .window) else {
            hoveredWindow = nil
            elementChain = []
            highlight = nil
            label = nil
            redraw()
            return
        }
        hoveredWindow = window
        if mode == .element, AXIsProcessTrusted(), let element = Self.element(at: p, pid: window.pid) {
            elementChain = [element]
            showElement(element, in: window)
        } else {
            elementChain = []
            highlight = window.bounds
            label = mode == .element
                ? "\(window.ownerName) — allow \(PermissionService.accessibilityName) to pick elements"
                : [window.ownerName, window.title].filter { !$0.isEmpty }.joined(separator: " — ")
        }
        redraw()
    }

    func mouseDown(atCocoa point: CGPoint) {
        dragStart = WindowSnapService.axPoint(fromCocoa: point)
    }

    func mouseDragged(toCocoa point: CGPoint) {
        guard let start = dragStart else { return }
        let p = WindowSnapService.axPoint(fromCocoa: point)
        // Window and element modes still allow a drag, for anything the hover misses.
        guard dragRect != nil || start.distance(to: p) > 4 || mode == .area || mode == .ocr else { return }
        dragRect = CGRect(corner: start, p)
        label = "\(Int(dragRect!.width)) × \(Int(dragRect!.height))"
        redraw()
    }

    func mouseUp(atCocoa point: CGPoint) {
        defer { dragStart = nil }
        if let dragRect {
            if dragRect.width >= 4, dragRect.height >= 4 {
                finish(.rect(dragRect.integral))
            } else {
                self.dragRect = nil
                redraw()
            }
            return
        }
        switch mode {
        case .window:
            if let window = hoveredWindow { finish(.window(window.id, window.bounds)) }
        case .element:
            if let highlight { finish(.rect(highlight.integral)) }
        case .area, .ocr, .fullscreen:
            break
        }
    }

    /// Scroll up widens the element to its parent, scroll down narrows back.
    func scroll(deltaY: CGFloat) {
        guard mode == .element, let window = hoveredWindow, let current = elementChain.last else { return }
        if deltaY > 0 {
            guard let parent = Self.parent(of: current), Self.role(of: parent) != (kAXApplicationRole as String),
                  let frame = AXFrame.of(parent), frame.width > 1, frame.height > 1 else { return }
            elementChain.append(parent)
            showElement(parent, in: window)
        } else if deltaY < 0, elementChain.count > 1 {
            elementChain.removeLast()
            showElement(elementChain[elementChain.count - 1], in: window)
        }
        redraw()
    }

    private func showElement(_ element: AXUIElement, in window: ScreenWindowList.Info) {
        let frame = (AXFrame.of(element) ?? window.bounds).intersection(window.bounds)
        highlight = frame.isNull || frame.isEmpty ? window.bounds : frame
        let role = Self.string(element, kAXRoleDescriptionAttribute) ?? "Element"
        let title = Self.string(element, kAXTitleAttribute) ?? Self.string(element, kAXDescriptionAttribute) ?? ""
        let levels = elementChain.count > 1 ? "  ↑\(elementChain.count - 1)" : ""
        label = (title.isEmpty ? role.capitalized : "\(role.capitalized) · \(title.prefix(40))") + levels
    }

    // MARK: Accessibility

    /// The deepest element at `point` in the app that owns the window there.
    /// Asking the app (not the system-wide element) skips our own overlay,
    /// which is the frontmost window at every point.
    private static func element(at point: CGPoint, pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &element) == .success else { return nil }
        return element
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func role(of element: AXUIElement) -> String? { string(element, kAXRoleAttribute) }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    // MARK: Drawing

    /// A CoreGraphics rect in a view covering `screenFrame` (Cocoa coordinates).
    func viewRect(_ r: CGRect, screenFrame: CGRect) -> CGRect {
        let cocoa = WindowSnapService.cocoaRect(fromAX: r)
        return cocoa.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    }

    var hint: String {
        switch mode {
        case .area, .ocr: "Drag to select · Esc to cancel"
        case .window: "Click a window · drag for an area · Esc to cancel"
        case .element: "Click an element · scroll to widen · drag for an area · Esc to cancel"
        case .fullscreen: ""
        }
    }

    var shownRect: CGRect? { dragRect ?? highlight }
}

// MARK: - Overlay window

final class CaptureOverlayPanel: NSPanel {
    init(screen: NSScreen, controller: CaptureSelectionController) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        setFrame(screen.frame, display: false)
        contentView = CaptureOverlayView(controller: controller, screenFrame: screen.frame)
    }

    override var canBecomeKey: Bool { true }
}

private final class CaptureOverlayView: NSView {
    private weak var controller: CaptureSelectionController?
    private let screenFrame: CGRect
    private var trackingArea: NSTrackingArea?

    init(controller: CaptureSelectionController, screenFrame: CGRect) {
        self.controller = controller
        self.screenFrame = screenFrame
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        MainActor.assumeIsolated { controller?.hover(atCocoa: NSEvent.mouseLocation) }
    }

    override func mouseDown(with event: NSEvent) {
        MainActor.assumeIsolated { controller?.mouseDown(atCocoa: NSEvent.mouseLocation) }
    }

    override func mouseDragged(with event: NSEvent) {
        MainActor.assumeIsolated { controller?.mouseDragged(toCocoa: NSEvent.mouseLocation) }
    }

    override func mouseUp(with event: NSEvent) {
        MainActor.assumeIsolated { controller?.mouseUp(atCocoa: NSEvent.mouseLocation) }
    }

    override func rightMouseDown(with event: NSEvent) {
        MainActor.assumeIsolated { controller?.cancel() }
    }

    override func scrollWheel(with event: NSEvent) {
        // One step per notch or trackpad swipe, not per pixel.
        guard event.phase == [] || event.phase == .began else { return }
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.5 else { return }
        MainActor.assumeIsolated { controller?.scroll(deltaY: event.isDirectionInvertedFromDevice ? -delta : delta) }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            MainActor.assumeIsolated { controller?.cancel() }
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        MainActor.assumeIsolated { drawOverlay() }
    }

    @MainActor private func drawOverlay() {
        guard let controller else { return }
        let dim = NSBezierPath(rect: bounds)
        let accent = NSColor.controlAccentColor
        if let shown = controller.shownRect {
            let r = controller.viewRect(shown, screenFrame: screenFrame)
            dim.append(NSBezierPath(rect: r).reversed)
            NSColor.black.withAlphaComponent(0.28).setFill()
            dim.fill()
            accent.withAlphaComponent(0.12).setFill()
            NSBezierPath(rect: r).fill()
            let outline = NSBezierPath(roundedRect: r.insetBy(dx: -1, dy: -1), xRadius: 3, yRadius: 3)
            outline.lineWidth = 2
            accent.setStroke()
            outline.stroke()
            if bounds.intersects(r), let label = controller.label, !label.isEmpty {
                drawPill(label, near: r)
            }
        } else {
            NSColor.black.withAlphaComponent(0.18).setFill()
            dim.fill()
        }
        // The hint sits on the display under the pointer.
        if NSMouseInRect(NSEvent.mouseLocation, screenFrame, false), !controller.hint.isEmpty {
            drawPill(controller.hint, at: CGPoint(x: bounds.midX, y: bounds.minY + 60), centered: true)
        }
    }

    private func drawPill(_ text: String, near r: CGRect) {
        // Above the rect when there's room, else inside its top edge.
        let y = r.maxY + 30 < bounds.maxY ? r.maxY + 8 : r.maxY - 30
        drawPill(text, at: CGPoint(x: max(r.minX, 8), y: y), centered: false)
    }

    private func drawPill(_ text: String, at point: CGPoint, centered: Bool) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let width = size.width + 20
        var x = centered ? point.x - width / 2 : point.x
        x = min(max(x, 8), bounds.maxX - width - 8)
        let pill = CGRect(x: x, y: point.y, width: width, height: 22)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 11, yRadius: 11).fill()
        (text as NSString).draw(at: CGPoint(x: pill.minX + 10, y: pill.minY + (22 - size.height) / 2), withAttributes: attributes)
    }
}
