import SwiftUI

/// Settings › Droplets › Notes.
@MainActor
public final class NotesSettings: SettingsStore {
    public static let shared = NotesSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "notesAppleSync", "notesShowToolbar", "notesGrowCanvas"
    ]

    @AppStorage("notesAppleSync") public var appleSync: Bool = false {
        didSet { if appleSync { NotesStore.shared.pullFromAppleNotes() } }
    }
    @AppStorage("notesShowToolbar") public var showToolbar: Bool = true
    @AppStorage("notesGrowCanvas") public var growCanvas: Bool = true

    private init() { super.init(keys: Self.keys) }
}
