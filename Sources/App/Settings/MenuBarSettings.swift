import SwiftUI

/// Settings › Droplets › Menu Bar Manager.
@MainActor
public final class MenuBarSettings: SettingsStore {
    public static let shared = MenuBarSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "menuBarAlwaysHidden", "menuBarAutoRehide", "menuBarRehideDelay",
        "menuBarRehideOnAppSwitch", "menuBarToggleIcon", "menuBarIconTemplate",
        "menuBarShowDividers"
    ]

    @AppStorage("menuBarAlwaysHidden") public var alwaysHidden: Bool = false {
        didSet { MenuBarManagerService.shared.sync() }
    }
    @AppStorage("menuBarAutoRehide") public var autoRehide: Bool = true
    /// Seconds before revealed items fold away again.
    @AppStorage("menuBarRehideDelay") public var rehideDelay: Double = 10
    @AppStorage("menuBarRehideOnAppSwitch") public var rehideOnAppSwitch: Bool = false
    @AppStorage("menuBarToggleIcon") public var toggleIcon: MenuBarToggleIcon = .chevron {
        didSet { MenuBarManagerService.shared.sync() }
    }
    @AppStorage("menuBarIconTemplate") public var iconTemplate: Bool = true {
        didSet { MenuBarManagerService.shared.sync() }
    }
    /// Thin dividers mark the sections while they're shown.
    @AppStorage("menuBarShowDividers") public var showDividers: Bool = true {
        didSet { MenuBarManagerService.shared.sync() }
    }

    private init() { super.init(keys: Self.keys) }
}
