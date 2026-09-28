import AppKit
import SwiftUI

/// Settings › Accessibility: hiding the resting island and bringing it back.
///
/// - **Right-click to reveal**: while hidden, a right-click on the spot where
///   the island rests (top centre of its screen) shows it again. The panel lets
///   every click through while hidden, so the click is heard by event monitors:
///   a global one for clicks bound for other apps (mouse events need no
///   permission) and a local one for clicks on Tama's own windows.
/// - **Hold to reveal**: while the island is hidden, holding the chosen
///   modifiers shows it until they're released. `NSEvent.modifierFlags` is
///   polled only while hidden, because watching key events globally would need
///   Input Monitoring.
@MainActor
public final class IslandVisibilityService {
    public static let shared = IslandVisibilityService()

    private var globalRightClick: Any?
    private var localRightClick: Any?
    private var holdTimer: Timer?

    private init() {}

    /// Starts or stops the monitors to match the settings and the hidden state.
    public func sync() {
        let state = AppState.shared
        let hidden = state.isIslandHidden || GeneralSettings.shared.holdToReveal

        if hidden, globalRightClick == nil {
            globalRightClick = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { _ in
                let point = NSEvent.mouseLocation
                Task { @MainActor in IslandVisibilityService.shared.handleRightClick(at: point) }
            }
            localRightClick = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
                IslandVisibilityService.shared.handleRightClick(at: NSEvent.mouseLocation)
                return event
            }
        } else if !hidden {
            if let globalRightClick { NSEvent.removeMonitor(globalRightClick) }
            if let localRightClick { NSEvent.removeMonitor(localRightClick) }
            globalRightClick = nil
            localRightClick = nil
        }

        if hidden, GeneralSettings.shared.holdToReveal, holdTimer == nil {
            let timer = Timer(timeInterval: 0.08, repeats: true) { _ in
                MainActor.assumeIsolated { IslandVisibilityService.shared.pollModifiers() }
            }
            RunLoop.main.add(timer, forMode: .common)
            holdTimer = timer
        } else if !(hidden && GeneralSettings.shared.holdToReveal) {
            holdTimer?.invalidate()
            holdTimer = nil
            if state.isHoldRevealing { state.isHoldRevealing = false }
        }
    }

    /// Hides the resting island (the right-click menu's "Hide Notch/Island").
    public func hide() {
        AppState.shared.isIslandHidden = true
        DroppyAudio.playTick()
    }

    public func reveal() {
        let state = AppState.shared
        guard state.isIslandHidden else { return }
        withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.morphOpen)) {
            state.isIslandHidden = false
        }
        DroppyAudio.playTick()
    }

    private func handleRightClick(at point: NSPoint) {
        let state = AppState.shared
        guard state.isIslandHidden, GeneralSettings.shared.rightClickToReveal,
              let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }),
              screen == state.getTargetScreen() || DisplaySettings.shared.displayTargetMode == .all
        else { return }
        // Where the resting island sits, with some slack: it's invisible, so
        // the click can't be expected to land on its exact outline.
        let size = state.islandCompactSize
        let frame = screen.frame
        let height = max(size.height, 24) + state.islandTopOffset + 16
        let width = max(size.width, 200) + 40
        let region = NSRect(x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height)
        guard region.contains(point) else { return }
        reveal()
    }

    private func pollModifiers() {
        let state = AppState.shared
        let wanted = GeneralSettings.shared.holdToRevealModifier.eventFlags
        let held = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]) == wanted
        if state.isHoldRevealing != held {
            withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, held ? DS.Motion.morphOpen : DS.Motion.morphClose)) {
                state.isHoldRevealing = held
            }
            NotchWindowController.shared.syncCanvas()
        }
    }
}

/// Settings › Accessibility › Hide from screenshots. Every panel that draws
/// Tama on screen registers here, and `sharingType = .none` keeps it out of
/// screenshots and screen sharing while the setting is on. macOS honours this
/// for its own screenshot tools and most recorders; ScreenCaptureKit apps on
/// recent macOS may still capture the window, which no public API prevents.
@MainActor
public enum CaptureExclusion {
    private final class WeakWindow {
        weak var window: NSWindow?
        init(_ window: NSWindow) { self.window = window }
    }

    private static var windows: [WeakWindow] = []

    public static func register(_ window: NSWindow) {
        windows.removeAll { $0.window == nil || $0.window === window }
        windows.append(WeakWindow(window))
        apply(to: window)
    }

    public static func apply() {
        windows.removeAll { $0.window == nil }
        windows.compactMap(\.window).forEach(apply(to:))
    }

    private static func apply(to window: NSWindow) {
        let hidden = UserDefaults.standard.bool(forKey: "hideFromScreenshots")
        window.sharingType = hidden ? .none : .readOnly
    }
}

extension ShortcutModifier {
    /// The same keys as `NSEvent` flags, for comparing against what's held.
    var eventFlags: NSEvent.ModifierFlags {
        switch self {
        case .controlOption: [.control, .option]
        case .optionCommand: [.option, .command]
        case .commandShift: [.command, .shift]
        }
    }
}
