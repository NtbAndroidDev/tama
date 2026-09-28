import SwiftUI

/// Settings › General and Accessibility: how the island behaves and where Tama shows itself.
@MainActor
public final class GeneralSettings: SettingsStore {
    public static let shared = GeneralSettings()

    /// Grace period before the island closes itself once the pointer leaves.
    /// Long enough to overshoot an edge and come back, or to reach a control
    /// that sits just outside the island; below roughly a third of a second
    /// the shelf is gone before a deliberate move can land.
    nonisolated public static let defaultAutoHideDelay: Double = 0.4

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "islandStyle", "expandOnHover", "hapticFeedback", "soundEffects", "autoHideDelay",
        "hoverOpenDelay", "islandMotionStyle", "showInMenuBar", "showInDock", "diagnosticLogging",
        "showTooltips", "showWhatsNew", "sidebarHiddenDroplets", "rightClickToHide",
        "rightClickToReveal", "holdToReveal", "holdToRevealModifier", "hideFromScreenshots"
    ]

    @AppStorage("islandStyle") public var islandStyle: IslandStyle = .notchAttached
    /// Off by default, like the reference; existing installs are switched off
    /// once by `migrateSettings()`.
    @AppStorage("expandOnHover") public var expandOnHover: Bool = false
    @AppStorage("hapticFeedback") public var hapticFeedback: Bool = true
    @AppStorage("soundEffects") public var soundEffects: Bool = true
    @AppStorage("autoHideDelay") public var autoHideDelay: Double = GeneralSettings.defaultAutoHideDelay
    /// How long the pointer rests on the notch before hover opens it.
    @AppStorage("hoverOpenDelay") public var hoverOpenDelay: Double = 0.25
    @AppStorage("islandMotionStyle") public var islandMotionStyle: IslandMotionStyle = .dynamicIsland
    @AppStorage("showInMenuBar") public var showInMenuBar: Bool = true
    @AppStorage("showInDock") public var showInDock: Bool = false
    /// Write detailed logs for troubleshooting (DroppyLog).
    @AppStorage("diagnosticLogging") public var diagnosticLogging: Bool = false
    /// Show the hover help (tooltips) on Tama's own buttons.
    @AppStorage("showTooltips") public var showTooltips: Bool = true {
        didSet { DroppyDiagnostics.applyTooltipPreference(showTooltips) }
    }
    /// Show What's New after an update.
    @AppStorage("showWhatsNew") public var showWhatsNew: Bool = true
    /// Droplets left out of the Settings sidebar's "Enabled Droplets" list (comma-separated ids).
    @AppStorage("sidebarHiddenDroplets") public var sidebarHiddenDroplets: String = ""
    /// Adds "Hide Notch/Island" to the island's right-click menu.
    @AppStorage("rightClickToHide") public var rightClickToHide: Bool = false
    /// A right-click where the hidden island sits brings it back.
    @AppStorage("rightClickToReveal") public var rightClickToReveal: Bool = true
    /// The resting island stays hidden until the modifiers below are held.
    @AppStorage("holdToReveal") public var holdToReveal: Bool = false {
        didSet { IslandVisibilityService.shared.sync() }
    }
    @AppStorage("holdToRevealModifier") public var holdToRevealModifier: ShortcutModifier = .controlOption
    /// Tama's panels are left out of screenshots and screen sharing.
    @AppStorage("hideFromScreenshots") public var hideFromScreenshots: Bool = false {
        didSet { CaptureExclusion.apply() }
    }

    private init() { super.init(keys: Self.keys) }
}
