import SwiftUI

/// Settings › Droplets › Notchface.
@MainActor
public final class NotchfaceSettings: SettingsStore {
    public static let shared = NotchfaceSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "notchfaceCamera", "notchfaceMirror"
    ]

    /// Notchface: the camera to preview (unique ID; empty = the system default).
    @AppStorage("notchfaceCamera") public var camera: String = ""
    @AppStorage("notchfaceMirror") public var mirror: Bool = true

    private init() { super.init(keys: Self.keys) }
}
