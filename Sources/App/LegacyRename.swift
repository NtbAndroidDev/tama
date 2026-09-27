import Foundation

/// The app was called Droppy before it was called Tama.
///
/// Two things macOS keys by name changed with it: the bundle identifier, which
/// is the domain `UserDefaults` writes to, and the Application Support folder.
/// Without this, the first launch after the rename would look like a fresh
/// install — no settings, no Tray, no clipboard history, no pinboards.
///
/// Runs once, from `DroppyApp.init()`, before anything reads a stored value.
enum LegacyRename {
    private static let oldBundleID = "app.getdroppy.macos"
    private static let oldFolder = "Droppy"
    private static let newFolder = "Tama"
    private static let doneKey = "migratedFromDroppy"

    /// The only things under the old folder this app ever wrote. The folder is
    /// shared with the commercial Droppy, which keeps `BrowserMediaBridge` and
    /// `Extensions` there, so everything else is left strictly alone.
    private static let owned = ["clipboard.json", "notes.json",
                                "Tray", "Clipboard", "Lyrics", "TermiNotch", "Agents"]

    static let run: Void = {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        copySupportFiles()
        copyDefaults(into: defaults)
        defaults.set(true, forKey: doneKey)
    }()

    /// `~/Library/Application Support/Droppy/…` → `.../Tama/…`, copied rather
    /// than moved: the other Droppy is still installed and still reading from
    /// that folder. The old copy is left for the user to delete.
    private static func copySupportFiles() {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let old = base.appendingPathComponent(oldFolder, isDirectory: true)
        let new = base.appendingPathComponent(newFolder, isDirectory: true)
        guard fm.fileExists(atPath: old.path) else { return }
        try? fm.createDirectory(at: new, withIntermediateDirectories: true)
        for name in owned {
            let source = old.appendingPathComponent(name)
            let destination = new.appendingPathComponent(name)
            guard fm.fileExists(atPath: source.path), !fm.fileExists(atPath: destination.path) else { continue }
            try? fm.copyItem(at: source, to: destination)
        }
    }

    /// AppKit keys a saved window frame by the window's autosave name, and
    /// those names carried the app's name with them: "NSWindow Frame
    /// DroppySettings" is now "NSWindow Frame TamaSettings". Without this the
    /// Settings, Calendar and Guide windows forget where they were.
    private static func carriedOver(_ key: String) -> String {
        let prefix = "NSWindow Frame " + oldFolder
        guard key.hasPrefix(prefix) else { return key }
        return "NSWindow Frame " + newFolder + key.dropFirst(prefix.count)
    }

    /// The old identifier's preferences, key by key. A key already set under
    /// the new identifier wins, so this can never overwrite a fresh choice.
    private static func copyDefaults(into defaults: UserDefaults) {
        guard let old = defaults.persistentDomain(forName: oldBundleID) else { return }
        for (key, value) in old {
            let key = carriedOver(key)
            guard defaults.object(forKey: key) == nil else { continue }
            defaults.set(value, forKey: key)
        }
    }
}
