import SwiftUI
import Combine

// The Tray (and the Basket, a window onto it): adding, trimming, pruning,
// removing and archiving held files.

extension AppState {
    // MARK: - Shelf Management
    /// Adds files to the Tray. `reveal` opens the shelf on the Tray page; it's
    /// only for drops on the island — a console or the Basket adding its result
    /// must stay where it is.
    /// Returns the items as held: files from the temporary folder have moved
    /// into Tama's own storage, so callers must use these URLs, not their own.
    @discardableResult
    public func addShelfItems(_ items: [ShelfItem], reveal: Bool = false) -> [ShelfItem] {
        // The same file listed twice in one drop is only held once.
        var seen = Set<URL>()
        let unique = items.filter { seen.insert($0.url.standardizedFileURL).inserted }
        var items = keepingTemporaryFiles(unique)
        // Settings › Shelf › Two Stacks: new files land in the stack on show.
        if trayTwoStacks {
            items = items.map { var item = $0; item.stack = activeTrayStack; return item }
        }
        // The same file dropped twice moves to the front instead of doubling up,
        // keeping its pin and tags.
        let incoming = Set(items.map(\.url.standardizedFileURL))
        let previous = Dictionary(shelfItems.map { ($0.url.standardizedFileURL, $0) }, uniquingKeysWith: { a, _ in a })
        items = items.map { item in
            guard let old = previous[item.url.standardizedFileURL] else { return item }
            var merged = item
            merged.isPinned = old.isPinned
            merged.tags = old.tags
            return merged
        }
        withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.fluid)) {
            shelfItems.removeAll { incoming.contains($0.url.standardizedFileURL) }
            shelfItems.insert(contentsOf: items, at: 0)
        }
        if hapticFeedback, !items.isEmpty {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        trimTray(reason: "Tray is full")
        measureFolderSizes(of: items)
        if reveal {
            open(.tray)
        } else if showFileTrayHUD, !isIslandExpanded, !items.isEmpty {
            // Settings › HUDs › File tray: the drop landed without opening the
            // shelf, so say so in the notch for a moment.
            LiveActivityCenter.shared.post(LiveActivity(
                id: "fileTray", icon: "tray.full.fill", tint: .white,
                trailing: .text("\(shelfItems.count)"), priority: .urgent,
                label: "\(items.count) file\(items.count == 1 ? "" : "s") added to the Tray",
                expiresAt: Date().addingTimeInterval(2)
            ))
        }
        return items
    }

    /// Moves dropped and generated files out of the temporary folder, and
    /// says so when one can't be kept (it stays, but may vanish later).
    func keepingTemporaryFiles(_ items: [ShelfItem]) -> [ShelfItem] {
        var failed: [String] = []
        let kept = items.map { item -> ShelfItem in
            let result = Self.keepingTemporaryFile(item)
            if result.url == item.url, Self.isTemporary(item.url) { failed.append(item.name) }
            return result
        }
        if !failed.isEmpty {
            showNotification(
                appName: "Tama Shelf",
                title: "Could not persist file",
                message: failed.count == 1 ? "\(failed[0]) stays in a temporary folder macOS may empty."
                    : "\(failed.count) files stay in a temporary folder macOS may empty.",
                icon: "exclamationmark.triangle.fill"
            )
        }
        return kept
    }

    /// Adds up dropped folders off the main thread (`ShelfItem.init` leaves a
    /// folder at 0 so a drop never waits on a walk of it) and patches the
    /// totals into wherever the items are held by then.
    func measureFolderSizes(of items: [ShelfItem]) {
        let pending = items.filter { $0.isDirectory && $0.fileSize == 0 }.map { ($0.id, $0.url) }
        guard !pending.isEmpty else { return }
        Task.detached(priority: .utility) {
            let sizes = pending.map { ($0.0, ShelfItem.size(of: $0.1)) }.filter { $0.1 > 0 }
            guard !sizes.isEmpty else { return }
            await MainActor.run {
                let state = AppState.shared
                for (id, size) in sizes {
                    state.updateHeldItems(ids: [id]) { if $0.isDirectory { $0.fileSize = size } }
                }
            }
        }
    }

    static func isTemporary(_ url: URL) -> Bool {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().path
        return url.resolvingSymlinksInPath().path.hasPrefix(temp)
    }

    // MARK: Auto-cleanup

    /// Settings › Shelf › Auto-cleanup: unpinned files past their time leave.
    func pruneExpiredShelfItems(now: Date = Date()) {
        guard let interval = trayExpiry.interval else { return }
        let expired = shelfItems.filter { item in
            guard let end = item.expiryDate(after: interval) else { return false }
            return end <= now
        }
        guard !expired.isEmpty else { return }
        let ids = Set(expired.map(\.id))
        withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.fluid)) {
            shelfItems.removeAll { ids.contains($0.id) }
        }
        showNotification(
            appName: "Tama Shelf",
            title: "Expired",
            message: expired.count == 1 ? "\(expired[0].name) left the Shelf"
                : "\(expired.count) files left the Shelf after \(trayExpiry.title)",
            icon: "clock.badge.xmark"
        )
    }

    // MARK: Pin, stacks and tags

    public func togglePin(_ ids: Set<UUID>) {
        let pin = !allPinned(ids)
        updateHeldItems(ids: ids) { $0.isPinned = pin }
        DroppyAudio.playTick()
    }

    public func allPinned(_ ids: Set<UUID>) -> Bool {
        let items = heldItems(ids)
        return !items.isEmpty && items.allSatisfy(\.isPinned)
    }

    public func moveToStack(_ ids: Set<UUID>, stack: Int) {
        updateHeldItems(ids: ids) { $0.stack = stack }
        DroppyAudio.playTick()
    }

    /// Adds the tag to every item, or takes it off when they all have it.
    public func toggleTag(_ tag: String, on ids: Set<UUID>) {
        let items = heldItems(ids)
        let remove = !items.isEmpty && items.allSatisfy { $0.tags.contains(tag) }
        updateHeldItems(ids: ids) { item in
            if remove {
                item.tags.removeAll { $0 == tag }
            } else if !item.tags.contains(tag) {
                item.tags.append(tag)
            }
        }
        if remove, trayTagFilter == tag, !shelfItems.contains(where: { $0.tags.contains(tag) }) {
            trayTagFilter = nil
        }
        DroppyAudio.playTick()
    }

    /// Tags in use on the Shelf, in pinboard order.
    public var shelfTagsInUse: [Pinboard] {
        let used = Set(shelfItems.flatMap(\.tags))
        return pinboards.filter { used.contains($0.name) }
    }

    /// Drops the oldest files past the Tray capacity, e.g. when the setting
    /// shrinks. Snips and conversions may exist nowhere else, so say what
    /// went and offer it back — with room to hold it: `undoCapacity` (the
    /// setting before it was lowered), or just enough for every file.
    func trimTray(reason: String, undoCapacity: Int? = nil) {
        let capacity = max(trayCapacity, 1)
        guard shelfItems.count > capacity else { return }
        let snapshot = shelfItems
        // Pinned files never make room; the oldest unpinned ones go.
        let unpinned = shelfItems.filter { !$0.isPinned }
        let removed = Set(unpinned.suffix(min(shelfItems.count - capacity, unpinned.count)).map(\.id))
        guard !removed.isEmpty else { return }
        withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.fluid)) {
            shelfItems.removeAll { removed.contains($0.id) }
        }
        let roomFor = max(undoCapacity ?? 0, snapshot.count)
        showNotification(
            appName: "Tray",
            title: reason,
            message: "Removed the oldest \(removed.count) file\(removed.count == 1 ? "" : "s")",
            actionTitle: undoCapacity == nil ? "Keep All" : "Undo",
            action: {
                let state = AppState.shared
                if state.trayCapacity < roomFor { state.trayCapacity = roomFor }
                state.restoreShelfItems(snapshot, removed: removed)
            }
        )
    }

    /// A drop that held nothing Tama can keep (a promise it couldn't read,
    /// an empty selection) says so instead of looking ignored.
    func notifyNothingAdded() {
        showNotification(
            appName: "Tray",
            title: "Couldn't add that",
            message: "The drop had no file, image or text to hold."
        )
    }

    /// Files deleted, or moved away, on disk since they were added leave the Tray
    /// instead of lingering as dead tiles.
    public func pruneMissingShelfItems() {
        let fm = FileManager.default
        let busy = heldItemsInFileWork
        let missing = Set(shelfItems.filter { !busy.contains($0.id) && !fm.fileExists(atPath: $0.url.path) }.map(\.id))
        if !missing.isEmpty {
            withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.fluid)) {
                shelfItems.removeAll { missing.contains($0.id) }
            }
        }
        // The Baskets' own files too.
        for index in baskets.indices {
            let gone = baskets[index].items.filter { !busy.contains($0.id) && !fm.fileExists(atPath: $0.url.path) }
            guard !gone.isEmpty else { continue }
            let ids = Set(gone.map(\.id))
            withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.fluid)) {
                baskets[index].items.removeAll { ids.contains($0.id) }
            }
        }
    }
    
    /// Where Tama keeps files it made itself (snips, conversions, archives,
    /// dropped images and text), so they outlive the temporary folder, which
    /// macOS empties after a few days or a restart.
    static var trayStorageDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("Tray", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func keepingTemporaryFile(_ item: ShelfItem) -> ShelfItem {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().path
        let path = item.url.resolvingSymlinksInPath().path
        guard path.hasPrefix(temp) else { return item }
        let folder = trayStorageDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = folder.appendingPathComponent(item.url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: item.url, to: destination)
        } catch {
            return item
        }
        var kept = item
        kept.url = destination
        return kept
    }

    /// Deletes kept files the Tray no longer lists.
    func pruneTrayStorage() {
        let fm = FileManager.default
        let root = Self.trayStorageDirectory.resolvingSymlinksInPath()
        let held = shelfItems + baskets.flatMap(\.items)
        let listed = Set(held.map { $0.url.resolvingSymlinksInPath().deletingLastPathComponent().path })
        // Which folders are orphans is decided here, against this moment's
        // Tray; only the deleting (possibly large snips and recordings) runs
        // off the main thread. A folder a drop creates after this isn't in
        // the list, so it can't be swept by mistake.
        let folders = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let orphans = folders.filter { !listed.contains($0.resolvingSymlinksInPath().path) }
        guard !orphans.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            for folder in orphans { try? FileManager.default.removeItem(at: folder) }
        }
    }

    public func clearAllShelfItems() {
        shelfItems.removeAll()
        DroppyAudio.playDelete()
    }
    
    public func clearShelf() {
        clearAllShelfItems()
    }
    

    public func removeShelfItems(ids: Set<UUID>) {
        shelfItems.removeAll(where: { ids.contains($0.id) })
        DroppyAudio.playDelete()
    }
    
    public func compressShelfItems(ids: Set<UUID>) {
        createArchive(of: shelfItems.filter { ids.contains($0.id) }, into: .shelf)
    }

    /// Create ZIP: one archive of the items, added to the surface they came from.
    public func createArchive(of itemsToCompress: [ShelfItem], into surface: HeldSurface) {
        guard !itemsToCompress.isEmpty else { return }
        let sources = itemsToCompress.map(\.url)
        let archiveName = sources.count == 1
            ? sources[0].deletingPathExtension().lastPathComponent + ".zip"
            : "Archive \(Int(Date().timeIntervalSince1970)).zip"
        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("Tama Archives", isDirectory: true)
        let archiveURL = workDir.appendingPathComponent(archiveName)
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            try? fm.createDirectory(at: workDir, withIntermediateDirectories: true)
            try? fm.removeItem(at: archiveURL)

            // ditto takes one source: a single item keeps its own name inside the
            // zip; several are gathered (APFS clones, so it's cheap) in a folder.
            var source = sources[0]
            var staging: URL?
            if sources.count > 1 {
                let folder = workDir.appendingPathComponent(UUID().uuidString)
                    .appendingPathComponent(archiveName.replacingOccurrences(of: ".zip", with: ""))
                try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
                var used = Set<String>()
                for url in sources {
                    var name = url.lastPathComponent
                    var n = 2
                    while used.contains(name) {
                        name = "\(url.deletingPathExtension().lastPathComponent) \(n).\(url.pathExtension)"
                        n += 1
                    }
                    used.insert(name)
                    try? fm.copyItem(at: url, to: folder.appendingPathComponent(name))
                }
                source = folder
                staging = folder.deletingLastPathComponent()
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            var isDirectory: ObjCBool = false
            fm.fileExists(atPath: source.path, isDirectory: &isDirectory)
            // --keepParent keeps a folder's own name at the top of the zip; for a
            // lone file it would add the file's parent folder instead.
            process.arguments = ["-c", "-k", "--sequesterRsrc"] + (isDirectory.boolValue ? ["--keepParent"] : [])
                + [source.path, archiveURL.path]
            var succeeded = false
            if (try? process.run()) != nil {
                process.waitUntilExit()
                succeeded = process.terminationStatus == 0 && fm.fileExists(atPath: archiveURL.path)
            }
            if let staging { try? fm.removeItem(at: staging) }
            
            DispatchQueue.main.async {
                guard succeeded else {
                    self.showNotification(appName: "Tama Shelf", title: "ZIP creation failed", message: archiveName,
                                          icon: "exclamationmark.triangle.fill")
                    return
                }
                // Through addItems, so the archive leaves the temporary
                // folder and the Tray capacity still holds.
                let archiveItem = self.addItems([ShelfItem(url: archiveURL)], to: surface).first ?? ShelfItem(url: archiveURL)
                DroppyAudio.playDropSuccess()
                self.showNotification(
                    appName: "Tama Shelf",
                    title: "Archive Created",
                    message: "\(itemsToCompress.count) file\(itemsToCompress.count == 1 ? "" : "s") → \(archiveName) (\(archiveItem.formattedSize))"
                )
            }
        }
    }
}
