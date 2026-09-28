import SwiftUI
import AppKit
import ApplicationServices
import Combine

/// Panel that can take keyboard focus without activating Tama, so the app
/// you were in stays frontmost and receives the paste.
final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows the clipboard in the layout picked in Settings › Clipboard: Alpha
/// docks the card strip at the bottom of the screen and slides it in and
/// out; Legacy is a list window with a preview pane, centred on the screen.
@MainActor
public final class ClipboardWindowController: NSObject {
    public static let shared = ClipboardWindowController()

    private var panel: ClipboardPanel?
    private var legacyPanel: ClipboardPanel?
    /// The panel on screen now (or last), for the click-away check.
    private var activePanel: ClipboardPanel?
    private var cancellables = Set<AnyCancellable>()
    private var clickMonitor: Any?
    private var hideWork: DispatchWorkItem?

    public static let height: CGFloat = 206
    /// The shelf slides on DS.Motion.fluid (see ClipboardShelfView), which
    /// has cleared the panel by now; the panel waits this long to go.
    static var slideOutDelay: TimeInterval { DS.Motion.reduceMotion ? 0 : 0.4 }

    private override init() {
        super.init()
    }

    public func setup() {
        let panel = ClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: Self.height),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false

        // The view is only built while the panel shows (see `mount`): kept
        // mounted behind an ordered-out panel, every clip re-rendered on each
        // AppState change — hover, media, the pointer crossing screens.
        panel.contentView = NSView(frame: panel.contentLayoutRect)
        // Black glass surfaces: keep text light even when the system is in Light Mode.
        panel.appearance = NSAppearance(named: .darkAqua)
        self.panel = panel
        CaptureExclusion.register(panel)
        legacyPanel = makeLegacyPanel()

        AppState.shared.$isClipboardVisible
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in self?.setVisible(visible) }
            .store(in: &cancellables)
    }

    /// The Legacy layout's window: dark, rounded, centred where the pointer is.
    private func makeLegacyPanel() -> ClipboardPanel {
        let size = ClipboardWindowController.legacySize
        let panel = ClipboardPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSView(frame: NSRect(origin: .zero, size: size))
        panel.appearance = NSAppearance(named: .darkAqua)
        CaptureExclusion.register(panel)
        return panel
    }

    static let legacySize = NSSize(width: 760, height: 480)

    private func setVisible(_ visible: Bool) {
        hideWork?.cancel()
        if visible {
            let isLegacy = ClipboardSettings.shared.layout == .legacy
            // A layout switch while open: the other window goes at once.
            let other = isLegacy ? panel : legacyPanel
            other?.orderOut(nil)
            unmount(other)
            guard let target = isLegacy ? legacyPanel : panel else { return }
            activePanel = target
            if isLegacy { positionLegacy(target) } else { position(target) }
            mount(target, legacy: isLegacy)
            target.orderFrontRegardless()
            target.makeKey()
            startClickMonitor()
        } else {
            stopClickMonitor()
            // Legacy goes at once; Alpha waits for its slide-out. Both views
            // stay mounted until then so their own hide handling has run.
            legacyPanel?.orderOut(nil)
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.panel?.orderOut(nil)
                self.unmount(self.panel)
                self.unmount(self.legacyPanel)
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.slideOutDelay, execute: work)
        }
    }

    /// Builds the panel's view as it comes on screen. The views start hidden
    /// and slide in on their next pass (see their `hasAppeared`).
    private func mount(_ panel: ClipboardPanel, legacy: Bool) {
        guard let container = panel.contentView, container.subviews.isEmpty else { return }
        let host: NSView
        if legacy {
            let view = NSHostingView(rootView: LegacyClipboardView())
            view.sizingOptions = []
            view.safeAreaRegions = []
            host = view
        } else {
            let view = NSHostingView(rootView: ClipboardShelfView())
            view.sizingOptions = []
            view.safeAreaRegions = []
            host = view
        }
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
    }

    private func unmount(_ panel: ClipboardPanel?) {
        guard let panel, !panel.isVisible else { return }
        panel.contentView?.subviews.forEach { $0.removeFromSuperview() }
    }

    /// The system Accessibility prompt is shown once per launch, not on every paste.
    private var didPromptForAccessibility = false

    /// Hides at once and hands focus back, then pastes into the app underneath.
    /// Images and files go on the pasteboard as themselves, not as their names.
    public func pasteAndClose(_ item: ClipboardItem, plainText: Bool = false) {
        paste([item], plainText: plainText)
    }

    /// Pastes one clip or several (joined; see `ClipboardMultiPaste`). With
    /// Settings › Clipboard › Paste into previous app off, they're only copied.
    public func paste(_ items: [ClipboardItem], plainText: Bool = false) {
        guard !items.isEmpty else { return }
        // Read before hiding: closing the clipboard clears the paste mode.
        let pastesIntoApp = ClipboardSettings.shared.pasteIntoApp || AppState.shared.isClipboardPasteMode
        guard ClipboardService.shared.copyToPasteboard(items: items, plainText: plainText) else {
            AppState.shared.showNotification(appName: "Clipboard", title: "Can't paste this clip",
                                             message: "Its image or file is no longer on this Mac.")
            return
        }
        DroppyAudio.playCopySuccess()
        AppState.shared.isClipboardVisible = false
        hideWork?.cancel()
        panel?.orderOut(nil)
        legacyPanel?.orderOut(nil)
        let what = items.count == 1 ? items[0].displayTitle : "\(items.count) items"
        guard pastesIntoApp else {
            AppState.shared.showNotification(appName: "Clipboard", title: "Copied to Clipboard", message: what,
                                             icon: "doc.on.clipboard.fill", duration: 1.8)
            return
        }
        // Posting ⌘V needs Accessibility access; without it the clip is still copied.
        guard AXIsProcessTrusted() else {
            if !didPromptForAccessibility {
                didPromptForAccessibility = true
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            }
            AppState.shared.showNotification(
                appName: "Clipboard",
                title: "Copied — press ⌘V to paste",
                message: "Allow Tama under Privacy & Security › \(PermissionService.accessibilityName) to paste automatically.",
                actionTitle: "Open Settings",
                action: { PermissionService.shared.openSettings(.accessibility) }
            )
            return
        }
        AppState.shared.showNotification(appName: "Clipboard", title: "Copied to Clipboard & Pasting",
                                         message: plainText ? "\(what) · plain text" : what,
                                         icon: "doc.on.clipboard.fill", duration: 1.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? AppState.shared.getTargetScreen()
            ?? NSScreen.main
        // Visible frame: sit above the Dock rather than under it.
        guard let frame = screen?.visibleFrame else { return }
        let width = min(frame.width - 80, 1000)
        panel.setFrame(
            NSRect(x: frame.midX - width / 2, y: frame.minY, width: width, height: Self.height),
            display: true
        )
    }

    private func positionLegacy(_ panel: NSPanel) {
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? AppState.shared.getTargetScreen()
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = Self.legacySize
        // A little above the middle, where a spotlight-style window sits.
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2 + frame.height * 0.08,
                              width: size.width, height: size.height), display: true)
    }

    /// Clicking anywhere else puts the clipboard away.
    private func startClickMonitor() {
        stopClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            Task { @MainActor in
                guard let panel = ClipboardWindowController.shared.activePanel,
                      !NSMouseInRect(NSEvent.mouseLocation, panel.frame, false) else { return }
                AppState.shared.isClipboardVisible = false
            }
        }
    }

    private func stopClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }
}
