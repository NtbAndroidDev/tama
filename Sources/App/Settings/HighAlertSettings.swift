import SwiftUI

/// Settings › Droplets › High Alert: what it keeps awake, and the ruler's last length.
@MainActor
public final class HighAlertSettings: SettingsStore {
    public static let shared = HighAlertSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "highAlertMode", "highAlertMinutes"
    ]

    /// High Alert: what it keeps awake, and the ruler's last length.
    @AppStorage("highAlertMode") public var mode: HighAlertMode = .display
    @AppStorage("highAlertMinutes") public var minutes: Int = 60

    private init() { super.init(keys: Self.keys) }
}
