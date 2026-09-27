import SwiftUI
import AppKit
import Combine

/// A borderless panel can't become key by default, so the HUD's Esc, Tab and
/// Space shortcuts never reached it.
private final class LiveActivityPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
public final class LiveActivityWindowController: NSObject {
    public static let shared = LiveActivityWindowController()
    
    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    
    private override init() {
        super.init()
    }
    
    public func setup() {
        let contentRect = NSRect(x: 0, y: 0, width: 480, height: 320)
        let panel = LiveActivityPanel(
            contentRect: contentRect,
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
        
        // The view is only built while the panel shows (see setVisible): kept
        // mounted behind an ordered-out panel it re-rendered on every media,
        // stats and settings change.
        // Black glass surfaces: keep text light even when the system is in Light Mode.
        panel.appearance = NSAppearance(named: .darkAqua)
        
        if let screen = NSScreen.main {
            let x = screen.frame.midX - 240
            let y = screen.frame.midY - 100
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        self.panel = panel
        CaptureExclusion.register(panel)

        // Listen to AppState
        AppState.shared.$isLiveActivityPresented
            .receive(on: RunLoop.main)
            .sink { [weak self] isPresented in
                self?.setVisible(isPresented)
            }
            .store(in: &cancellables)
    }
    
    public func toggle() {
        AppState.shared.isLiveActivityPresented.toggle()
    }
    
    private var isMonitoring = false

    public func setVisible(_ visible: Bool) {
        if visible {
            if let screen = NSScreen.main, let panel = self.panel {
                let x = screen.frame.midX - 240
                let y = screen.frame.midY - 100
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }
            if panel?.contentView == nil {
                let host = NSHostingView(rootView: LockScreenLiveActivityView())
                // Fixed-size panel; see FloatingBasketController for why.
                host.sizingOptions = []
                panel?.contentView = host
            }
            panel?.orderFrontRegardless()
            // Non-activating: takes the keyboard without bringing Tama forward.
            panel?.makeKey()
            // Subscribing takes a fresh CPU baseline instead of averaging over the idle gap.
            if !isMonitoring { SystemMonitorService.shared.subscribe() }
            isMonitoring = true
        } else {
            panel?.orderOut(nil)
            panel?.contentView = nil
            if isMonitoring { SystemMonitorService.shared.unsubscribe() }
            isMonitoring = false
        }
    }
}
