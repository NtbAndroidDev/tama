import SwiftUI
import AppKit

// Choices on Settings › HUDs. The stored settings themselves live in the
// AppState class body; these are their value types.

/// Settings › HUDs › Collapsed HUD scope: with All Displays, whether a level
/// HUD shows only on the screen being used or on every screen's island.
public enum HUDScope: String, CaseIterable, Identifiable, Sendable {
    case underPointer, allDisplays
    public var id: String { rawValue }
}

/// Settings › HUDs › In fullscreen: what the island does on a screen showing
/// a fullscreen app or video.
public enum FullscreenBehavior: String, CaseIterable, Identifiable, Sendable {
    case show, hideMedia, hideAll
    public var id: String { rawValue }
}

/// Which of music and an urgent live activity takes the resting wings.
public enum CompactHUDPriority: String, CaseIterable, Identifiable, Sendable {
    case activitiesFirst, mediaFirst
    public var id: String { rawValue }
}

/// Settings › Shelf › Tray & screenshots: where the card a fresh screenshot
/// leaves goes. Closest Corner follows the pointer, so the card never lands
/// on top of the thing that was just captured.
public enum CapturePreviewPlacement: String, CaseIterable, Identifiable, Sendable {
    case bottomRight
    case closestCorner

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .bottomRight: "Bottom right"
        case .closestCorner: "Closest corner"
        }
    }

    public var icon: String {
        switch self {
        case .bottomRight: "rectangle.inset.bottomright.filled"
        case .closestCorner: "cursorarrow.rays"
        }
    }
}

/// Settings › HUDs › Media key target: which display the brightness keys dim.
public enum MediaKeyTarget: String, CaseIterable, Identifiable, Sendable {
    /// The display the pointer is on, when Tama can dim it.
    case underPointer
    /// Always the MacBook's own panel.
    case mainMacBook
    public var id: String { rawValue }
}

extension NSScreen {
    /// A key for this display that survives reboots and reconnects (display
    /// IDs don't): vendor, model and serial, with the name as a tiebreaker.
    var droppyDisplayKey: String {
        guard let id = displayID else { return localizedName }
        return "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }
}

extension AppState {
    /// Settings › HUDs › Per-display visibility: external displays switched off.
    public var hiddenDisplayKeys: Set<String> {
        get { Set(hiddenDisplaysStorage.split(separator: "\n").map(String.init)) }
        set { hiddenDisplaysStorage = newValue.sorted().joined(separator: "\n") }
    }

    /// Whether a screen may carry the island at all (Hide on external
    /// displays, Per-display visibility). The built-in panel always may.
    public func allowsSurface(on screen: NSScreen) -> Bool {
        if screen.isBuiltIn { return true }
        if hideOnExternalDisplays { return false }
        if perDisplayVisibility, hiddenDisplayKeys.contains(screen.droppyDisplayKey) { return false }
        return true
    }

    /// Screens that may carry the island. Empty only when every screen is
    /// switched off, and then the island is simply hidden wherever it is.
    public var surfaceScreens: [NSScreen] {
        NSScreen.screens.filter(allowsSurface(on:))
    }

    /// The resting island and level HUDs are hidden on this screen right now:
    /// the screen is switched off, it shows a fullscreen app with "Hide all",
    /// or Mission Control is up. An open shelf, the drop tiles and banners
    /// still show — they answer something the user just did.
    public func isSurfaceSuppressed(on displayID: CGDirectDisplayID?) -> Bool {
        guard let screen = screen(for: displayID) else { return false }
        if !allowsSurface(on: screen) { return true }
        let screens = ScreenStateService.shared
        if hideInMissionControl, screens.isMissionControlActive { return true }
        if fullscreenBehavior == .hideAll, let id = screen.displayID, screens.fullscreenDisplays.contains(id) { return true }
        return false
    }

    /// Whether music shows in the resting island on this screen: Now Playing
    /// is on, Auto-hide preview hasn't folded it, Now Playing display allows
    /// this island, and In fullscreen › Hide media doesn't leave it out.
    public func showsMedia(on displayID: CGDirectDisplayID?) -> Bool {
        guard nowPlayingEnabled, !isMediaAutoHidden else { return false }
        switch nowPlayingDisplay {
        case .underPointer:
            // All Displays' look-alikes on the other screens stay quiet.
            if displayID != nil { return false }
        case .macBook:
            let screens = NSScreen.screens
            if screens.contains(where: \.isBuiltIn), screen(for: displayID)?.isBuiltIn == false { return false }
        }
        guard fullscreenBehavior == .hideMedia,
              let id = screen(for: displayID)?.displayID else { return true }
        return !ScreenStateService.shared.fullscreenDisplays.contains(id)
    }

    /// Show when idle off: an external display's resting island fades out
    /// while nothing is live on it, and comes back on hover or a file drag.
    public func isIdleHidden(on displayID: CGDirectDisplayID?) -> Bool {
        guard !showWhenIdle, let screen = screen(for: displayID), !screen.isBuiltIn,
              islandMode(on: displayID) == .resting, !hasMiniActivity(on: displayID) else { return false }
        if displayID == nil, isIslandHovered || isDragNear { return false }
        return true
    }
}

extension AppState {
    /// A rule about which screens carry the island changed: move the live
    /// island off a screen that may no longer have it, and redraw.
    func surfaceRulesChanged() {
        objectWillChange.send()
        NotchWindowController.shared.surfaceRulesChanged()
        NotchCoverController.shared.sync()
    }

    /// Reset and Import write the keys directly, past the didSets: run what
    /// the HUD settings switch on or off.
    func applyHUDSettings() {
        ScreenStateService.shared.sync()
        surfaceRulesChanged()
        CapsLockService.shared.sync()
        RecordingIndicatorService.shared.sync()
        FocusModeService.shared.sync()
        ConnectivityService.shared.sync()
        DesktopSliderController.shared.sync()
        BrightnessService.shared.syncAutoWatch()
        BetterDisplayService.shared.refresh()
        MediaKeyMonitor.shared.syncInterception()
    }
}
