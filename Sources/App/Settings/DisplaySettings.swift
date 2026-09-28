import SwiftUI

/// Settings › HUDs › Display style and size: which screens carry the island, and its size.
@MainActor
public final class DisplaySettings: SettingsStore {
    public static let shared = DisplaySettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "displayTargetMode", "hideOnExternalDisplays", "showWhenIdle", "perDisplayVisibility",
        "hiddenDisplays", "hidePhysicalNotch", "islandHeightOffset", "islandWidthOffset",
        "notchHUDHeightOffset", "notchHUDWidthOffset", "mediaHUDVerticalOffset",
        "fullscreenBehavior", "hideInMissionControl"
    ]

    @AppStorage("displayTargetMode") public var displayTargetMode: DisplayTargetMode = .main
    @AppStorage("hideOnExternalDisplays") public var hideOnExternalDisplays: Bool = false {
        didSet { AppState.shared.surfaceRulesChanged() }
    }
    /// Off: an external display's resting island fades out while nothing is live.
    @AppStorage("showWhenIdle") public var showWhenIdle: Bool = true {
        didSet { AppState.shared.objectWillChange.send() }
    }
    /// On: only the external displays not listed in `hiddenDisplays` show the island.
    @AppStorage("perDisplayVisibility") public var perDisplayVisibility: Bool = false {
        didSet { AppState.shared.surfaceRulesChanged() }
    }
    /// Newline-separated `NSScreen.droppyDisplayKey`s; see `hiddenDisplayKeys`.
    @AppStorage("hiddenDisplays") public var hiddenDisplaysStorage: String = "" {
        didSet { AppState.shared.surfaceRulesChanged() }
    }
    /// A black bar across the top of a notched display, so the notch disappears into it.
    @AppStorage("hidePhysicalNotch") public var hidePhysicalNotch: Bool = false {
        didSet { NotchCoverController.shared.sync() }
    }
    @AppStorage("islandHeightOffset") public var islandHeightOffset: Double = 0 {
        didSet { AppState.shared.islandFrameChanged() }
    }
    @AppStorage("islandWidthOffset") public var islandWidthOffset: Double = 0 {
        didSet { AppState.shared.islandFrameChanged() }
    }
    @AppStorage("notchHUDHeightOffset") public var notchHUDHeightOffset: Double = 0 {
        didSet { AppState.shared.islandFrameChanged() }
    }
    @AppStorage("notchHUDWidthOffset") public var notchHUDWidthOffset: Double = 0 {
        didSet { AppState.shared.islandFrameChanged() }
    }
    /// Extra points between the top of the screen and the floating island pill.
    @AppStorage("mediaHUDVerticalOffset") public var mediaHUDVerticalOffset: Double = 0 {
        didSet { AppState.shared.islandFrameChanged() }
    }
    @AppStorage("fullscreenBehavior") public var fullscreenBehavior: FullscreenBehavior = .show {
        didSet { ScreenStateService.shared.sync() }
    }
    @AppStorage("hideInMissionControl") public var hideInMissionControl: Bool = true {
        didSet { ScreenStateService.shared.sync() }
    }

    private init() { super.init(keys: Self.keys) }
}
