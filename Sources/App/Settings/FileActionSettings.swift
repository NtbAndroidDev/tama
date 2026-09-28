import SwiftUI

/// Settings › Files: quick actions, conversion, Smart Export, tracked folders and cutouts.
@MainActor
public final class FileActionSettings: SettingsStore {
    public static let shared = FileActionSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "quickActionsEnabled", "quickActionTiles", "quickActionMailApp", "quickshareConfirm",
        "convertDestination", "afterConvertAction", "smartExportEnabled", "smartExportFolder",
        "smartExportCompressed", "smartExportConverted", "smartExportCutouts",
        "trackedFoldersEnabled", "trackedFolders", "trackedFoldersCompressionLevel",
        "cutoutBackground", "cutoutPadding", "cutoutCornerRadius", "cutoutShadow"
    ]

    @AppStorage("quickActionsEnabled") public var quickActionsEnabled: Bool = true {
        didSet { AppState.shared.islandFrameChanged() }
    }
    /// The tiles after Keep, comma-separated `QuickAction` raw values.
    @AppStorage("quickActionTiles") public var quickActionTilesStorage: String = QuickAction.storage(for: QuickAction.defaultTiles)
    @AppStorage("quickActionMailApp") public var quickActionMailApp: QuickActionMailApp = .systemDefault
    /// Quickshare asks before anything leaves the Mac.
    @AppStorage("quickshareConfirm") public var quickshareConfirm: Bool = true
    /// Converted files' folder; "" is Downloads.
    @AppStorage("convertDestination") public var convertDestination: String = ""
    @AppStorage("afterConvertAction") public var afterConvertAction: AfterConvertAction = .addToShelf
    /// Smart Export: processed files are saved into per-type folders.
    @AppStorage("smartExportEnabled") public var smartExportEnabled: Bool = false
    /// Base folder for Smart Export; "" is Downloads › Tama.
    @AppStorage("smartExportFolder") public var smartExportFolder: String = ""
    @AppStorage("smartExportCompressed") public var smartExportCompressed: Bool = true
    @AppStorage("smartExportConverted") public var smartExportConverted: Bool = true
    @AppStorage("smartExportCutouts") public var smartExportCutouts: Bool = true
    /// Tracked folders: new files in these folders are taken in, each folder
    /// doing what its own action says (`TrackedFolderAction`).
    @AppStorage("trackedFoldersEnabled") public var trackedFoldersEnabled: Bool = false {
        didSet { TrackedFolderService.shared.sync() }
    }
    /// Newline-separated "action:path" tokens; see `TrackedFolder`.
    @AppStorage("trackedFolders") public var trackedFoldersStorage: String = "" {
        didSet { TrackedFolderService.shared.sync() }
    }
    /// The level "Add and compress" uses, since there is nobody to ask.
    @AppStorage("trackedFoldersCompressionLevel") public var trackedFoldersCompressionLevel: CompressionLevel = .medium
    @AppStorage("cutoutBackground") public var cutoutBackground: CutoutBackground = .transparent
    /// Space around the subject, as a fraction of its size (0 keeps the whole frame).
    @AppStorage("cutoutPadding") public var cutoutPadding: Double = 0
    /// Corner radius of the backdrop, as a fraction of its shorter side.
    @AppStorage("cutoutCornerRadius") public var cutoutCornerRadius: Double = 0
    @AppStorage("cutoutShadow") public var cutoutShadow: Bool = false

    private init() { super.init(keys: Self.keys) }
}
