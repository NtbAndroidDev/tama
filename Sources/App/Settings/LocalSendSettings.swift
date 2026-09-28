import SwiftUI

/// Settings › Droplets › LocalSend.
@MainActor
public final class LocalSendSettings: SettingsStore {
    public static let shared = LocalSendSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "localSendDeviceName", "localSendReceiveMode", "localSendVisible", "localSendEncrypted",
        "localSendPIN", "localSendSaveFolder", "localSendAddToShelf",
        "localSendQuickSaveFavorites"
    ]

    /// The name other devices see; empty = this Mac's name.
    @AppStorage("localSendDeviceName") public var deviceName: String = "" {
        didSet { LocalSendService.shared.settingsChanged() }
    }
    @AppStorage("localSendReceiveMode") public var receiveMode: LocalSendReceiveMode = .anyone
    /// Announce this Mac and answer other devices' scans.
    @AppStorage("localSendVisible") public var isVisible: Bool = true {
        didSet { LocalSendService.shared.settingsChanged() }
    }
    /// Encrypted (HTTPS): serve with the self-signed certificate; off = plain HTTP.
    @AppStorage("localSendEncrypted") public var isEncrypted: Bool = true {
        didSet { LocalSendService.shared.restart() }
    }
    /// A PIN senders must type before a transfer is offered; empty = none.
    @AppStorage("localSendPIN") public var pin: String = ""
    /// Where received files go; empty = Downloads.
    @AppStorage("localSendSaveFolder") public var saveFolder: String = ""
    @AppStorage("localSendAddToShelf") public var addToShelf: Bool = true
    /// Favorites' transfers are saved without asking.
    @AppStorage("localSendQuickSaveFavorites") public var quickSaveFavorites: Bool = false

    private init() { super.init(keys: Self.keys) }
}
