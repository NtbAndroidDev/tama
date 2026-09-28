import SwiftUI

/// Settings › Droplets › Agents: which coding agents feed the notch.
@MainActor
public final class AgentsSettings: SettingsStore {
    public static let shared = AgentsSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "agentsClaude", "agentsCodex", "agentsCursor", "agentsShowInNotch", "agentsNotifyDone"
    ]

    /// Agents: which coding agents feed the notch.
    @AppStorage("agentsClaude") public var claude: Bool = true {
        didSet { AgentActivityService.shared.settingsChanged() }
    }
    @AppStorage("agentsCodex") public var codex: Bool = true {
        didSet { AgentActivityService.shared.settingsChanged() }
    }
    @AppStorage("agentsCursor") public var cursor: Bool = true {
        didSet { AgentActivityService.shared.settingsChanged() }
    }
    @AppStorage("agentsShowInNotch") public var showInNotch: Bool = true {
        didSet { AgentActivityService.shared.settingsChanged() }
    }
    @AppStorage("agentsNotifyDone") public var notifyDone: Bool = true

    private init() { super.init(keys: Self.keys) }
}
