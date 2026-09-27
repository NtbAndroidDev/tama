import SwiftUI
import Combine

// Clips, tray files, notes, pinboards and droplet switches survive a relaunch.

extension AppState {
    // MARK: - Persistence
    // Clips, tray files, notes and droplet switches survive a relaunch.

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Tama", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func restorePersistedState() {
        let defaults = UserDefaults.standard
        let dir = Self.supportDirectory
        // LocalSend's favorite devices (UserDefaults "localSendFavorites").
        LocalSendService.shared.restoreFavorites()

        let clipboardURL = dir.appendingPathComponent("clipboard.json")
        if let data = try? Data(contentsOf: clipboardURL) {
            if let items = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
                clipboardItems = items
            } else {
                // Unreadable (older or newer format): set it aside rather than
                // letting the next copy overwrite the whole history.
                let backup = dir.appendingPathComponent("clipboard.corrupt-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.moveItem(at: clipboardURL, to: backup)
            }
        }
        // Shelf files with their bookkeeping (added, pinned, stack, tags);
        // older builds kept only the paths, under "trayFiles".
        if let data = defaults.data(forKey: "trayItems"),
           let records = try? JSONDecoder().decode([HeldFileRecord].self, from: data) {
            shelfItems = records.compactMap(\.item)
        } else if let paths = defaults.stringArray(forKey: "trayFiles") {
            shelfItems = paths
                .filter { FileManager.default.fileExists(atPath: $0) }
                .map { ShelfItem(url: URL(fileURLWithPath: $0)) }
        }
        if let data = defaults.data(forKey: "baskets"),
           let records = try? JSONDecoder().decode([BasketRecord].self, from: data) {
            baskets = records.map(\.basket)
        }
        // Folders restored from records without a saved total.
        measureFolderSizes(of: shelfItems + baskets.flatMap(\.items))
        pruneTrayStorage()
        if let saved = defaults.stringArray(forKey: "homeWidgets"), !saved.isEmpty {
            homeWidgets = Array(saved.prefix(HomeWidget.limit))
        }
        // Both lists are kept so a droplet that ships switched off (Mechey)
        // remembers being turned on.
        let disabled = Set(defaults.stringArray(forKey: "disabledDroplets") ?? [])
        let enabled = Set(defaults.stringArray(forKey: "enabledDroplets") ?? [])
        for index in droplets.indices {
            if disabled.contains(droplets[index].id) { droplets[index].isEnabled = false }
            if enabled.contains(droplets[index].id) { droplets[index].isEnabled = true }
        }
        // Settings › Shelf › Widget icons (and rearrange mode) reorder them.
        applyStoredDropletOrder(defaults.stringArray(forKey: "dropletOrder") ?? [])

        $clipboardItems
            .dropFirst()
            .debounce(for: .seconds(0.8), scheduler: RunLoop.main)
            .sink { items in
                // Encoded and written off the main thread: a long history with
                // OCR text behind it is a few hundred kilobytes of JSON, and
                // copying repeatedly used to run that — and an atomic file
                // write — between two frames of the shelf. The quit path
                // (`flushPersistence`) still writes synchronously.
                let file = dir.appendingPathComponent("clipboard.json")
                // One serial queue, so two changes close together can't land
                // out of order and leave an older history on disk.
                Self.diskQueue.async {
                    guard let data = try? JSONEncoder().encode(items) else { return }
                    try? data.write(to: file, options: .atomic)
                }
            }
            .store(in: &persistence)
        $shelfItems
            .dropFirst()
            // Debounced like the Baskets are: dropping twenty files, or
            // dragging a tile from one stack to the other, changed the Tray
            // once per file and re-encoded the whole list each time.
            .debounce(for: .seconds(0.3), scheduler: RunLoop.main)
            .map { $0.map(HeldFileRecord.init) }
            .sink { records in
                defaults.set(records.map(\.path), forKey: "trayFiles")
                if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: "trayItems") }
            }
            .store(in: &persistence)
        $baskets
            .dropFirst()
            .debounce(for: .seconds(0.3), scheduler: RunLoop.main)
            .sink { baskets in
                if let data = try? JSONEncoder().encode(baskets.map(BasketRecord.init)) {
                    defaults.set(data, forKey: "baskets")
                }
            }
            .store(in: &persistence)
        $homeWidgets
            .dropFirst()
            .removeDuplicates()
            .sink { defaults.set($0, forKey: "homeWidgets") }
            .store(in: &persistence)
        $droplets
            .dropFirst()
            .map { $0.filter { !$0.isEnabled }.map(\.id) }
            .removeDuplicates()
            .sink { defaults.set($0, forKey: "disabledDroplets") }
            .store(in: &persistence)
        $droplets
            .dropFirst()
            .map { $0.filter(\.isEnabled).map(\.id) }
            .removeDuplicates()
            .sink { defaults.set($0, forKey: "enabledDroplets") }
            .store(in: &persistence)
        $droplets
            .dropFirst()
            .map { $0.map(\.id) }
            .removeDuplicates()
            .sink { defaults.set($0, forKey: "dropletOrder") }
            .store(in: &persistence)
    }
    
    /// Serialises the background writes so they land in the order they were made.
    static let diskQueue = DispatchQueue(label: "com.tama.persistence", qos: .utility)

    /// Writes what the debounced sinks may not have saved yet. Called on quit.
    public func flushPersistence() {
        // A hard reset has just wiped all of this on purpose.
        guard !Self.isHardResetting else { return }
        let defaults = UserDefaults.standard
        // Through the same queue as the debounced writes, and waited on, so a
        // write still in flight can't land after this one and undo it.
        let clipboardFile = Self.supportDirectory.appendingPathComponent("clipboard.json")
        let clips = clipboardItems
        Self.diskQueue.sync {
            guard let data = try? JSONEncoder().encode(clips) else { return }
            try? data.write(to: clipboardFile, options: .atomic)
        }
        // Notes keep their own file (NotesStore).
        NotesStore.shared.flush()
        // LocalSend favorites are written as they change; save once more.
        LocalSendService.shared.saveFavorites()
        defaults.set(shelfItems.map(\.url.path), forKey: "trayFiles")
        if let data = try? JSONEncoder().encode(shelfItems.map(HeldFileRecord.init)) {
            defaults.set(data, forKey: "trayItems")
        }
        if let data = try? JSONEncoder().encode(baskets.map(BasketRecord.init)) {
            defaults.set(data, forKey: "baskets")
        }
        defaults.set(homeWidgets, forKey: "homeWidgets")
        defaults.set(droplets.map(\.id), forKey: "dropletOrder")
    }
}
