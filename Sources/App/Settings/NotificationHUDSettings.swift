import SwiftUI

/// Settings › Droplets › Notification HUD: mirrored notifications in the notch.
@MainActor
public final class NotificationHUDSettings: SettingsStore {
    public static let shared = NotificationHUDSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "notificationHUDDuration", "notificationHUDBlockedApps", "notificationHUDBurst",
        "notificationHUDPreview", "notificationHUDQuickReply", "notificationHUDHideAfterReply",
        "notificationHUDShowFilters"
    ]

    /// Notification HUD: seconds a mirrored notification stays up.
    @AppStorage("notificationHUDDuration") public var duration: Double = 5
    /// Bundle IDs whose notifications are not mirrored, one per line.
    @AppStorage("notificationHUDBlockedApps") public var blockedApps: String = ""
    @AppStorage("notificationHUDBurst") public var burst: Bool = true
    @AppStorage("notificationHUDPreview") public var preview: Bool = true
    @AppStorage("notificationHUDQuickReply") public var quickReply: Bool = true
    @AppStorage("notificationHUDHideAfterReply") public var hideAfterReply: Bool = true
    @AppStorage("notificationHUDShowFilters") public var showFilters: Bool = false

    private init() { super.init(keys: Self.keys) }
}
