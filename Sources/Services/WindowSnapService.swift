import AppKit
import ApplicationServices

/// Every Window Snap action: a layout on the window's current display, a move
/// to the next or previous display, or raising the window under the pointer.
/// Raw values are the preset IDs the console and the Ring have always used.
public enum SnapLayout: String, CaseIterable, Identifiable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case topLeft, topRight, bottomLeft, bottomRight
    case center, maximize
    case nextDisplay, previousDisplay, bringToFront

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .leftThird: "Left Third"
        case .centerThird: "Center Third"
        case .rightThird: "Right Third"
        case .leftTwoThirds: "Left Two Thirds"
        case .rightTwoThirds: "Right Two Thirds"
        case .topLeft: "Top Left Quarter"
        case .topRight: "Top Right Quarter"
        case .bottomLeft: "Bottom Left Quarter"
        case .bottomRight: "Bottom Right Quarter"
        case .center: "Center"
        case .maximize: "Maximize"
        case .nextDisplay: "Next Display"
        case .previousDisplay: "Previous Display"
        case .bringToFront: "Bring Window To Front"
        }
    }

    /// Short label under the console tile.
    public var detail: String {
        switch self {
        case .leftHalf: "50% Left"
        case .rightHalf: "50% Right"
        case .topHalf: "50% Top"
        case .bottomHalf: "50% Bottom"
        case .leftThird: "33% Left"
        case .centerThird: "33% Mid"
        case .rightThird: "33% Right"
        case .leftTwoThirds: "66% Left"
        case .rightTwoThirds: "66% Right"
        case .topLeft: "25% ↖"
        case .topRight: "25% ↗"
        case .bottomLeft: "25% ↙"
        case .bottomRight: "25% ↘"
        case .center: "70% Center"
        case .maximize: "100% Full"
        case .nextDisplay: "Move →"
        case .previousDisplay: "← Move"
        case .bringToFront: "Under pointer"
        }
    }

    public var icon: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.filled"
        case .rightHalf: "rectangle.righthalf.filled"
        case .topHalf: "rectangle.tophalf.filled"
        case .bottomHalf: "rectangle.bottomhalf.filled"
        case .leftThird, .rightThird: "rectangle.split.3x1"
        case .centerThird: "rectangle.split.3x1.fill"
        case .leftTwoThirds: "rectangle.leadinghalf.inset.filled"
        case .rightTwoThirds: "rectangle.trailinghalf.inset.filled"
        case .topLeft: "rectangle.inset.topleft.filled"
        case .topRight: "rectangle.inset.topright.filled"
        case .bottomLeft: "rectangle.inset.bottomleft.filled"
        case .bottomRight: "rectangle.inset.bottomright.filled"
        case .center: "rectangle.center.inset.filled"
        case .maximize: "arrow.up.left.and.arrow.down.right"
        case .nextDisplay: "rectangle.righthalf.inset.filled.arrow.right"
        case .previousDisplay: "rectangle.lefthalf.inset.filled.arrow.left"
        case .bringToFront: "macwindow.on.rectangle"
        }
    }

    /// Fractions of the visible screen: x, y (from the top), width, height.
    /// nil for the actions that aren't a layout.
    public var fraction: CGRect? {
        let third = 1.0 / 3
        switch self {
        case .leftHalf: return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: return CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf: return CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .leftThird: return CGRect(x: 0, y: 0, width: third, height: 1)
        case .centerThird: return CGRect(x: third, y: 0, width: third, height: 1)
        case .rightThird: return CGRect(x: 2 * third, y: 0, width: third, height: 1)
        case .leftTwoThirds: return CGRect(x: 0, y: 0, width: 2 * third, height: 1)
        case .rightTwoThirds: return CGRect(x: third, y: 0, width: 2 * third, height: 1)
        case .topLeft: return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .center: return CGRect(x: 0.15, y: 0.1, width: 0.7, height: 0.8)
        case .maximize: return CGRect(x: 0, y: 0, width: 1, height: 1)
        case .nextDisplay, .previousDisplay, .bringToFront: return nil
        }
    }

    public var shortcutAction: ShortcutAction {
        switch self {
        case .leftHalf: .snapLeftHalf
        case .rightHalf: .snapRightHalf
        case .topHalf: .snapTopHalf
        case .bottomHalf: .snapBottomHalf
        case .leftThird: .snapLeftThird
        case .centerThird: .snapCenterThird
        case .rightThird: .snapRightThird
        case .leftTwoThirds: .snapLeftTwoThirds
        case .rightTwoThirds: .snapRightTwoThirds
        case .topLeft: .snapTopLeft
        case .topRight: .snapTopRight
        case .bottomLeft: .snapBottomLeft
        case .bottomRight: .snapBottomRight
        case .center: .snapCenter
        case .maximize: .snapMaximize
        case .nextDisplay: .snapNextDisplay
        case .previousDisplay: .snapPreviousDisplay
        case .bringToFront: .snapBringToFront
        }
    }

    init?(shortcut: ShortcutAction) {
        guard let match = Self.allCases.first(where: { $0.shortcutAction == shortcut }) else { return nil }
        self = match
    }

    /// Settings groups, in the order they're listed.
    public static let groups: [(title: String, layouts: [SnapLayout])] = [
        ("Halves", [.leftHalf, .rightHalf, .topHalf, .bottomHalf]),
        ("Thirds", [.leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds]),
        ("Quarters", [.topLeft, .topRight, .bottomLeft, .bottomRight]),
        ("Window", [.center, .maximize, .bringToFront]),
        ("Displays", [.nextDisplay, .previousDisplay]),
    ]

    /// The frame this layout gives a window, in AX coordinates (top-left
    /// origin on the primary screen), on the visible area `area`.
    static func target(_ fraction: CGRect, in area: CGRect) -> CGRect {
        CGRect(x: area.minX + area.width * fraction.minX, y: area.minY + area.height * fraction.minY,
               width: area.width * fraction.width, height: area.height * fraction.height).integral
    }

    /// Where a window lands on another display: the same relative place and
    /// size, clamped so it fits.
    static func moved(_ frame: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return frame }
        let rx = (frame.minX - source.minX) / source.width
        let ry = (frame.minY - source.minY) / source.height
        let width = min(frame.width / source.width * destination.width, destination.width)
        let height = min(frame.height / source.height * destination.height, destination.height)
        var x = destination.minX + rx * destination.width
        var y = destination.minY + ry * destination.height
        x = min(max(x, destination.minX), destination.maxX - width)
        y = min(max(y, destination.minY), destination.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height).integral
    }
}

/// Moves the focused window of the app the user was last working in (never
/// Tama itself) with the Accessibility API. Invoked only by explicit
/// actions — a console tile, the Ring or a recorded shortcut; there is no
/// drag watching.
@MainActor
public final class WindowSnapService {
    public static let shared = WindowSnapService()

    private var lastTargetPID: pid_t?
    private var observer: NSObjectProtocol?

    private init() {
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() {
            lastTargetPID = app.processIdentifier
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != getpid() else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { WindowSnapService.shared.lastTargetPID = pid }
        }
    }

    /// Call early so the service starts following app switches.
    public func start() {}

    public enum SnapError: LocalizedError {
        case notTrusted, noApp, noWindow, rejected, singleDisplay
        public var errorDescription: String? {
            switch self {
            case .notTrusted: return "Allow Tama in System Settings › Privacy & Security › \(PermissionService.accessibilityName)."
            case .noApp: return "Click the window you want to move first."
            case .noWindow: return "That app has no window to move."
            case .rejected: return "The window can't be resized."
            case .singleDisplay: return "Only one display is connected."
            }
        }
    }

    /// Fractions of the visible screen for a preset ID (kept for older callers).
    public static func layout(for id: String) -> CGRect {
        SnapLayout(rawValue: id)?.fraction ?? CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    /// Returns the app's name on success.
    @discardableResult
    public func snap(_ presetID: String) throws -> String {
        try snap(SnapLayout(rawValue: presetID) ?? .maximize, showPreview: false)
    }

    /// A shortcut or tile: snaps and reports failures in a banner. Shortcuts
    /// flash the target zone first when "Show snap preview" is on.
    public func perform(_ layout: SnapLayout, fromShortcut: Bool) {
        do {
            let showPreview = fromShortcut && CaptureSettings.shared.windowSnapShowPreview
            let app = try snap(layout, showPreview: showPreview)
            if !fromShortcut {
                AppState.shared.showNotification(appName: "Window Snap", title: "Window Positioned",
                                                 message: "\(app) → \(layout.title)")
            }
        } catch SnapError.notTrusted {
            AppState.shared.showNotification(appName: "Window Snap", title: "Couldn't snap",
                                             message: SnapError.notTrusted.localizedDescription,
                                             actionTitle: "Open Settings") {
                PermissionService.shared.openSettings(.accessibility)
            }
        } catch {
            AppState.shared.showNotification(appName: "Window Snap", title: "Couldn't snap", message: error.localizedDescription)
        }
    }

    @discardableResult
    public func snap(_ layout: SnapLayout, showPreview: Bool) throws -> String {
        guard AXIsProcessTrusted() else {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            throw SnapError.notTrusted
        }
        if layout == .bringToFront { return try bringWindowUnderPointerToFront() }

        guard let pid = lastTargetPID, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            throw SnapError.noApp
        }
        let axApp = AXUIElementCreateApplication(pid)
        guard let window = copyElement(axApp, kAXFocusedWindowAttribute) ?? copyElement(axApp, kAXMainWindowAttribute) else {
            throw SnapError.noWindow
        }

        let current = frame(of: window)
        let screens = Self.orderedScreens()
        let screen = Self.screen(containing: current, in: screens)
        let area = Self.axVisibleFrame(of: screen)

        let target: CGRect
        switch layout {
        case .nextDisplay, .previousDisplay:
            guard screens.count > 1, let index = screens.firstIndex(of: screen) else { throw SnapError.singleDisplay }
            let step = layout == .nextDisplay ? 1 : screens.count - 1
            let destination = screens[(index + step) % screens.count]
            target = SnapLayout.moved(current, from: area, to: Self.axVisibleFrame(of: destination))
        default:
            target = SnapLayout.target(layout.fraction ?? CGRect(x: 0, y: 0, width: 1, height: 1), in: area)
        }

        if showPreview { SnapPreviewOverlay.shared.flash(axFrame: target) }
        // Position, size, then position again: some apps clamp size to the screen
        // edge, and a move across displays must land before the resize.
        guard set(window, kAXPositionAttribute, target.origin),
              set(window, kAXSizeAttribute, target.size) else { throw SnapError.rejected }
        _ = set(window, kAXPositionAttribute, target.origin)
        app.activate()
        return app.localizedName ?? "Window"
    }

    /// Raises the topmost normal window under the pointer and activates its app.
    private func bringWindowUnderPointerToFront() throws -> String {
        let point = Self.axPoint(fromCocoa: NSEvent.mouseLocation)
        guard let info = ScreenWindowList.topWindow(at: point, excludingPID: getpid(), normalOnly: true),
              let app = NSRunningApplication(processIdentifier: info.pid) else { throw SnapError.noWindow }
        let axApp = AXUIElementCreateApplication(info.pid)
        var windows: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windows) == .success,
           let list = windows as? [AXUIElement] {
            // The AX window whose frame matches the one the window server reports.
            let match = list.min { a, b in
                Self.distance(frame(of: a), info.bounds) < Self.distance(frame(of: b), info.bounds)
            }
            if let match {
                AXUIElementPerformAction(match, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(match, kAXMainAttribute as CFString, kCFBooleanTrue)
            }
        }
        app.activate()
        if showsPreviewForFront { SnapPreviewOverlay.shared.flash(axFrame: info.bounds) }
        return app.localizedName ?? "Window"
    }

    private var showsPreviewForFront: Bool { CaptureSettings.shared.windowSnapShowPreview }

    private static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
    }

    // MARK: Screens

    /// Displays left to right (then top to bottom), the order next/previous walks.
    static func orderedScreens() -> [NSScreen] {
        NSScreen.screens.sorted { a, b in
            a.frame.minX != b.frame.minX ? a.frame.minX < b.frame.minX : a.frame.maxY > b.frame.maxY
        }
    }

    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// A Cocoa frame (bottom-left origin) in AX / CoreGraphics coordinates.
    static func axRect(fromCocoa r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func cocoaRect(fromAX r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func axPoint(fromCocoa p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: primaryHeight - p.y) }

    static func axVisibleFrame(of screen: NSScreen) -> CGRect { axRect(fromCocoa: screen.visibleFrame) }

    /// The display holding most of the window, else the one its centre is on.
    static func screen(containing axFrame: CGRect, in screens: [NSScreen]) -> NSScreen {
        let best = screens.max { a, b in
            area(axRect(fromCocoa: a.frame).intersection(axFrame)) < area(axRect(fromCocoa: b.frame).intersection(axFrame))
        }
        if let best, area(axRect(fromCocoa: best.frame).intersection(axFrame)) > 0 { return best }
        return NSScreen.main ?? screens.first ?? NSScreen.screens[0]
    }

    private static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }

    // MARK: AX helpers

    private func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func frame(of window: AXUIElement) -> CGRect {
        AXFrame.of(window) ?? .zero
    }

    private func set(_ window: AXUIElement, _ attribute: String, _ point: CGPoint) -> Bool {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(window, attribute as CFString, value) == .success
    }

    private func set(_ window: AXUIElement, _ attribute: String, _ size: CGSize) -> Bool {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(window, attribute as CFString, value) == .success
    }
}

/// An element's frame from its AX position and size (top-left origin).
enum AXFrame {
    static func of(_ element: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let position = value, CFGetTypeID(position) == AXValueGetTypeID(),
              AXValueGetValue(position as! AXValue, .cgPoint, &origin) else { return nil }
        value = nil
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let sized = value, CFGetTypeID(sized) == AXValueGetTypeID(),
              AXValueGetValue(sized as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }
}

/// The window server's list of on-screen windows, front to back.
enum ScreenWindowList {
    struct Info {
        let id: CGWindowID
        let pid: pid_t
        /// CoreGraphics coordinates (top-left origin on the primary screen).
        let bounds: CGRect
        let layer: Int
        let ownerName: String
        let title: String
    }

    static func windows() -> [Info] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0.01, bounds.width > 2, bounds.height > 2 else { return nil }
            return Info(id: id, pid: pid, bounds: bounds,
                        layer: entry[kCGWindowLayer as String] as? Int ?? 0,
                        ownerName: entry[kCGWindowOwnerName as String] as? String ?? "",
                        title: entry[kCGWindowName as String] as? String ?? "")
        }
    }

    /// The frontmost window under `point` that isn't `excludingPID`'s.
    /// `normalOnly` keeps to ordinary app windows (layer 0).
    static func topWindow(at point: CGPoint, excludingPID: pid_t, normalOnly: Bool) -> Info? {
        windows().first { info in
            info.pid != excludingPID && info.bounds.contains(point)
                && (normalOnly ? info.layer == 0 : info.layer < Int(CGWindowLevelForKey(.screenSaverWindow)))
                && info.ownerName != "Window Server"
        }
    }
}

// MARK: - Snap preview

/// A translucent blue zone flashed where the window is about to land, shown
/// when a snap comes from a keyboard shortcut.
@MainActor
final class SnapPreviewOverlay {
    static let shared = SnapPreviewOverlay()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func flash(axFrame: CGRect) {
        let frame = WindowSnapService.cocoaRect(fromAX: axFrame)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        hideWork?.cancel()
        panel.setFrame(frame.insetBy(dx: -4, dy: -4), display: true)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.orderFrontRegardless()
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
        }
        let work = DispatchWorkItem { [weak self] in
            guard let panel = self?.panel else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = reduceMotion ? 0 : 0.25; panel.animator().alphaValue = 0 }) {
                Task { @MainActor in panel.orderOut(nil) }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.22).cgColor
        view.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.85).cgColor
        view.layer?.borderWidth = 2
        view.layer?.cornerRadius = 12
        panel.contentView = view
        CaptureExclusion.register(panel)
        return panel
    }
}
