import SwiftUI

/// Settings › Shelf › Tray: what the Tray holds and how files leave it.
@MainActor
public final class TraySettings: SettingsStore {
    public static let shared = TraySettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "trayExpiry", "trayTwoStacks", "trayCapacity", "removeOnDragOut", "protectOriginals",
        "autoCopyOCRText"
    ]

    /// Auto-cleanup: unpinned Shelf files leave after this long.
    @AppStorage("trayExpiry") public var expiry: TrayExpiry = .never
    /// Two Stacks: the Tray holds two separate stacks of files.
    @AppStorage("trayTwoStacks") public var twoStacks: Bool = false {
        didSet { if !twoStacks { AppState.shared.activeTrayStack = 0 } }
    }
    /// Most files the Tray holds; the oldest go first.
    @AppStorage("trayCapacity") public var capacity: Int = 50 {
        didSet { AppState.shared.trimTray(reason: "Tray capacity lowered", undoCapacity: oldValue) }
    }
    /// Take a file off the Tray once it's been dragged out into another app.
    @AppStorage("removeOnDragOut") public var removeOnDragOut: Bool = false
    /// Drags out of the Tray and Basket only ever copy: Finder can't move the
    /// user's original out of its folder. Off allows a move (Finder's default
    /// on the same volume), and a moved file then leaves the Tray.
    @AppStorage("protectOriginals") public var protectOriginals: Bool = true
    /// Text read by OCR (the OCR droplet, a Tray preview) goes straight to the clipboard.
    @AppStorage("autoCopyOCRText") public var autoCopyOCRText: Bool = false

    private init() { super.init(keys: Self.keys) }
}
