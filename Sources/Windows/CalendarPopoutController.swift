import SwiftUI
import AppKit

/// Tasks & Calendar popped out of the shelf into a floating window of its
/// own, optionally kept above other windows (Settings › Shelf › Tasks &
/// Calendar, or the pin in its header).
@MainActor
public final class CalendarPopoutController: NSObject, NSWindowDelegate {
    public static let shared = CalendarPopoutController()

    private var panel: NSPanel?
    public private(set) var isOpen = false

    private override init() { super.init() }

    public func toggle() { isOpen ? close() : open() }

    public func open() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        applyLevel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        isOpen = true
        // The shelf's copy of the page gives way to the window.
        if AppState.shared.shelfPage == .calendar { AppState.shared.setIslandExpanded(false) }
    }

    /// Bring floating calendar to front.
    public func bringToFront() {
        guard let panel, isOpen else { return open() }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    public func close() {
        panel?.orderOut(nil)
        isOpen = false
    }

    /// Keep calendar window on top.
    public func applyLevel() {
        panel?.level = CalendarSettings.shared.popoutOnTop ? .floating : .normal
    }

    public func windowWillClose(_ notification: Notification) {
        isOpen = false
    }

    private func makePanel() -> NSPanel {
        let size = DroppyShelfMetrics.calendarPopoutSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Tasks & Calendar"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = NSColor(white: 0.06, alpha: 0.97)
        panel.minSize = NSSize(width: 460, height: 220)
        panel.delegate = self
        let host = NSHostingView(rootView: CalendarPopoutView())
        // The panel carries its own minSize and autosaved frame.
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrameAutosaveName("TamaCalendarPopout")
        if panel.frame.origin == .zero, let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - size.width - 24,
                                         y: screen.visibleFrame.maxY - size.height - 24))
        }
        CaptureExclusion.register(panel)
        return panel
    }
}

/// The page in the window, with room for the traffic lights.
private struct CalendarPopoutView: View {
    var body: some View {
        CalendarPage(isPopout: true)
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
    }
}
