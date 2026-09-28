import SwiftUI

/// Settings › Droplets › Thunderstorm launcher.
@MainActor
public final class ThunderstormSettings: SettingsStore {
    public static let shared = ThunderstormSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "thunderstormWebSearch", "thunderstormInlineAnswers", "thunderstormSystemCommands"
    ]

    /// Google / DuckDuckGo / Wikipedia rows under the results.
    @AppStorage("thunderstormWebSearch") public var webSearch: Bool = true
    /// Ask DuckDuckGo's Instant Answer API as you type (sends the query to DuckDuckGo).
    @AppStorage("thunderstormInlineAnswers") public var inlineAnswers: Bool = false
    /// Lock, Sleep, Restart, Eject… rows.
    @AppStorage("thunderstormSystemCommands") public var systemCommands: Bool = true

    private init() { super.init(keys: Self.keys) }
}
