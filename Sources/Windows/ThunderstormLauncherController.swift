import SwiftUI
import AppKit
import Combine

/// Thunderstorm's floating launcher window: a borderless panel that takes
/// the keyboard without activating Tama (like Spotlight), centred near the
/// top of the screen under the pointer. It grows with its results and goes
/// away on Esc, after an action, or when another window takes the keyboard.
@MainActor
final class ThunderstormLauncherController: NSObject, NSWindowDelegate {
    static let shared = ThunderstormLauncherController()

    let model = ThunderstormLauncherModel()
    private var panel: LauncherPanel?
    private var keyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private override init() { super.init() }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard AppState.shared.droplets.contains(where: { $0.id == "thunderstorm" && $0.isEnabled }) else { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        // The island's own Thunderstorm console would fight for the keys.
        if AppState.shared.isIslandExpanded, AppState.shared.activeDropletID == "thunderstorm" {
            AppState.shared.setIslandExpanded(false)
        }
        model.reset()
        position(panel, height: ToolWindowMetrics.launcherBarHeight)
        panel.orderFrontRegardless()
        panel.makeKey()
        model.opened()
        startKeyMonitor()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        stopKeyMonitor()
        model.closed()
        panel.orderOut(nil)
    }

    private func makePanel() -> LauncherPanel {
        let panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: ToolWindowMetrics.launcherWidth, height: ToolWindowMetrics.launcherBarHeight),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.delegate = self
        let host = NSHostingView(rootView: ThunderstormLauncherView(model: model))
        host.sizingOptions = []
        host.safeAreaRegions = []
        let container = NSView(frame: panel.contentLayoutRect)
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        panel.contentView = container
        panel.appearance = NSAppearance(named: .darkAqua)
        CaptureExclusion.register(panel)

        // Grow and shrink with the results, keeping the bar where it is.
        model.$sections
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resize() }
            .store(in: &cancellables)
        return panel
    }

    private var desiredHeight: CGFloat {
        let sections = model.sections
        guard !sections.isEmpty else { return ToolWindowMetrics.launcherBarHeight }
        let rows = CGFloat(sections.reduce(0) { $0 + $1.items.count })
        let content = rows * (ToolWindowMetrics.launcherRowHeight + 2) + CGFloat(sections.count) * 26 + 12
        return min(ToolWindowMetrics.launcherBarHeight + content, ToolWindowMetrics.launcherMaxHeight)
    }

    private func resize() {
        guard let panel, panel.isVisible else { return }
        var frame = panel.frame
        let height = desiredHeight
        guard abs(frame.height - height) > 0.5 else { return }
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }

    private func position(_ panel: NSPanel, height: CGFloat) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let width = min(ToolWindowMetrics.launcherWidth, visible.width - 40)
        let top = visible.maxY - visible.height * 0.2
        panel.setFrame(NSRect(x: visible.midX - width / 2, y: top - height, width: width, height: height), display: true)
    }

    // MARK: Keys

    /// Arrows, Return, Esc and ⌘-keys, before the text field sees them; only
    /// for this panel, and only while it's up.
    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            return self.model.handleKey(event) ? nil : event
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: NSWindowDelegate

    /// Another app (or a click elsewhere) took the keyboard. Quick Look keeps
    /// the launcher up; it's still our own window.
    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible else { return }
            if let key = NSApp.keyWindow, key !== self.panel, key.className.contains("QLPreviewPanel") { return }
            if NSApp.keyWindow === self.panel { return }
            self.hide()
        }
    }
}

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
