import SwiftUI

/// Settings › Droplets › TermiNotch.
@MainActor
public final class TermiNotchSettings: SettingsStore {
    public static let shared = TermiNotchSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "termiNotchTerminalApp", "termiNotchDroppyPrompt", "termiNotchQuickBar",
        "termiNotchFontSize"
    ]

    /// TermiNotch › Open in Terminal: the app that gets the current folder.
    @AppStorage("termiNotchTerminalApp") public var terminalApp: TerminalApp = .terminal
    /// TermiNotch › zsh gets the `user@host ~` / green `$` prompt after your own startup files.
    @AppStorage("termiNotchDroppyPrompt") public var droppyPrompt: Bool = true
    /// TermiNotch › Show TermiNotch bar: open as the one-line quick command bar.
    @AppStorage("termiNotchQuickBar") public var quickBar: Bool = false
    @AppStorage("termiNotchFontSize") public var fontSize: Double = 12

    private init() { super.init(keys: Self.keys) }
}
