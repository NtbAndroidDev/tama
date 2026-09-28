import SwiftUI

/// Settings › Clipboard.
@MainActor
public final class ClipboardSettings: SettingsStore {
    public static let shared = ClipboardSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "clipboardHistoryLimit", "clipboardEnabled", "clipboardInMenuBar", "clipboardInShelfMenu",
        "clipboardLayout", "clipboardTypeFilters", "clipboardClearOnQuit",
        "clipboardRejectDuplicates", "clipboardTagsEnabled", "clipboardFavoritesBar",
        "clipboardCopyFavorite", "clipboardAutoFocusSearch", "clipboardPasteIntoApp"
    ]

    @AppStorage("clipboardHistoryLimit") public var historyLimit: Int = 50 {
        didSet { AppState.shared.trimClipboardHistory(undoLimit: oldValue) }
    }
    /// The Clipboard manager master switch. Off, nothing is recorded and the
    /// shortcut only points at Settings.
    @AppStorage("clipboardEnabled") public var isEnabled: Bool = true {
        didSet { AppState.shared.applyClipboardEnabled() }
    }
    /// Where "Open Clipboard" appears: the menu bar item's menu and the
    /// notch's right-click menu.
    @AppStorage("clipboardInMenuBar") public var inMenuBar: Bool = true
    @AppStorage("clipboardInShelfMenu") public var inShelfMenu: Bool = true
    @AppStorage("clipboardLayout") public var layout: ClipboardLayout = .alpha {
        didSet { if layout != oldValue, AppState.shared.isClipboardVisible { AppState.shared.isClipboardVisible = false } }
    }
    /// The type-filter rail (All, Favorites, Text, Images…).
    @AppStorage("clipboardTypeFilters") public var typeFilters: Bool = true
    /// Unstarred, unfiled clips are dropped when Tama quits.
    @AppStorage("clipboardClearOnQuit") public var clearOnQuit: Bool = false
    /// A copy repeating a clip already in history is ignored outright
    /// (off: the existing clip moves back to the front).
    @AppStorage("clipboardRejectDuplicates") public var rejectDuplicates: Bool = false
    /// Clipboard actions: tags on clips, a "Copy + Favorite" action, and
    /// the search field focused whenever the clipboard opens.
    @AppStorage("clipboardTagsEnabled") public var tagsEnabled: Bool = true
    /// Settings › Clipboard › Favorites bar: starred clips get a strip of
    /// chips above the cards, one click away wherever the search is.
    @AppStorage("clipboardFavoritesBar") public var favoritesBar: Bool = true
    @AppStorage("clipboardCopyFavorite") public var copyFavorite: Bool = false
    @AppStorage("clipboardAutoFocusSearch") public var autoFocusSearch: Bool = false
    /// Paste into the app underneath (⌘V is posted); off, a pick is only copied.
    @AppStorage("clipboardPasteIntoApp") public var pasteIntoApp: Bool = true

    private init() { super.init(keys: Self.keys) }
}
