import AppKit

/// Settings › HUDs › Hide physical notch: a black bar along the top of every
/// notched display, as tall as the menu bar, so the camera housing melts into
/// it. It sits just under the menu bar (whose items stay on top and clickable),
/// ignores the mouse, and stays out of fullscreen Spaces, where macOS already
/// hides the menu bar. A display switched off for the island gets no bar.
@MainActor
public final class NotchCoverController {
    public static let shared = NotchCoverController()

    private var covers: [CGDirectDisplayID: NSPanel] = [:]
    private var screenObserver: NSObjectProtocol?

    private init() {}

    public func start() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { NotchCoverController.shared.sync() }
        }
        sync()
    }

    public func sync() {
        let state = AppState.shared
        var wanted = Set<CGDirectDisplayID>()
        if state.hidePhysicalNotch {
            let fullscreen = ScreenStateService.shared.fullscreenDisplays
            for screen in NSScreen.screens {
                let inset = screen.safeAreaInsets.top
                guard inset > 0, let id = screen.displayID, state.allowsSurface(on: screen),
                      !fullscreen.contains(id) else { continue }
                wanted.insert(id)
                let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - inset,
                                   width: screen.frame.width, height: inset)
                let panel = covers[id] ?? Self.makeCover()
                covers[id] = panel
                if panel.frame != frame { panel.setFrame(frame, display: true) }
                if !panel.isVisible { panel.orderFrontRegardless() }
            }
        }
        for (id, panel) in covers where !wanted.contains(id) {
            panel.orderOut(nil)
            covers[id] = nil
        }
    }

    private static func makeCover() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // Under the menu bar, over every ordinary window.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        CaptureExclusion.register(panel)
        return panel
    }
}
