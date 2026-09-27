import SwiftUI
import AppKit

/// The one Settings window: dark translucent glass with the sidebar on the
/// glass and a lighter content panel (see SettingsView).
@MainActor
public final class SettingsWindowController: NSObject {
    public static let shared = SettingsWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    public func showWindow() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Tama Settings"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.appearance = NSAppearance(named: .darkAqua)
            window.minSize = NSSize(width: 700, height: 520)
            window.center()
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: SettingsView())
            // The window sets its own frame and minSize, so SwiftUI must not also
            // push content-size extrema onto it — that feedback is what AppKit
            // aborts with an "Update Constraints in Window" throw.
            host.sizingOptions = []
            window.contentView = host
            window.setFrameAutosaveName("TamaSettings")
            self.window = window
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens Settings on a page.
    func showWindow(page: SettingsPage) {
        SettingsNavigator.shared.open(page)
        showWindow()
    }
}
