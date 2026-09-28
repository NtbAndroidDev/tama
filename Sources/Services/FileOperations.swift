import AppKit
import UniformTypeIdentifiers

/// What the Shelf and Basket context menus do to files on disk: copy, move,
/// save, rename, gather into a folder, open with another app. Each action
/// reports what went wrong in the notch instead of failing silently, and
/// updates the held items so their tiles follow the files.
@MainActor
public enum FileOperations {
    private static var state: AppState { AppState.shared }

    public static var downloadsFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    /// Finder-style "name 2.ext" when the name is taken. Nonisolated: the
    /// copy and move work below picks names off the main thread.
    nonisolated static func uniqueDestination(for source: URL, in folder: URL, name: String? = nil) -> URL {
        let file = name ?? source.lastPathComponent
        let base = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        return UniqueFileNamer.url(in: folder, base: base, ext: ext) { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: Copy

    /// Copy: the files themselves on the clipboard, ready to paste in Finder.
    public static func copyToPasteboard(_ items: [ShelfItem]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(items.map { $0.url as NSURL })
        DroppyAudio.playCopySuccess()
    }

    public static func copyPaths(_ items: [ShelfItem]) {
        ClipboardService.shared.copyToPasteboard(text: items.map(\.url.path).joined(separator: "\n"))
        DroppyAudio.playCopySuccess()
    }

    // MARK: Move to…

    /// Asks for a folder. The Shelf stays open behind the panel.
    static func chooseFolder(prompt: String, message: String? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = message ?? ""
        state.setModal(true, owner: "fileOps.chooseFolder")
        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()
        state.setModal(false, owner: "fileOps.chooseFolder")
        return response == .OK ? panel.url : nil
    }

    public static func moveWithPicker(_ items: [ShelfItem]) {
        guard !items.isEmpty,
              let folder = chooseFolder(prompt: "Move Here", message: "Choose a destination to move the selected files.")
        else { return }
        move(items, to: folder)
    }

    /// Moves the files into the folder; their tiles follow them. Across disks
    /// FileManager copies and removes, like Finder.
    public static func move(_ items: [ShelfItem], to folder: URL) {
        // Across disks a move is a full copy, so the file work runs off the
        // main thread; tiles and the banner update back on main.
        let ids = Set(items.map(\.id))
        state.heldItemsInFileWork.formUnion(ids)
        Task.detached(priority: .userInitiated) {
            var failed: [String] = []
            var done: [(id: UUID, destination: URL)] = []
            for item in items {
                if item.url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL { continue }
                let destination = uniqueDestination(for: item.url, in: folder)
                do {
                    try FileManager.default.moveItem(at: item.url, to: destination)
                    done.append((item.id, destination))
                } catch {
                    failed.append(item.name)
                }
            }
            let results = done
            let failures = failed
            await MainActor.run {
                finishMove(results, failed: failures, folder: folder)
                state.heldItemsInFileWork.subtract(ids)
            }
        }
    }

    private static func finishMove(_ done: [(id: UUID, destination: URL)], failed: [String], folder: URL) {
        for (id, destination) in done {
            state.updateHeldItems(ids: [id]) { $0 = $0.moved(to: destination) }
        }
        let moved = done.count
        if failed.isEmpty {
            DroppyAudio.playDropSuccess()
            state.showNotification(appName: "Tama", title: "Moved",
                                   message: "\(moved) file\(moved == 1 ? "" : "s") → \(folder.lastPathComponent)",
                                   icon: "folder.fill",
                                   actionTitle: "Show", action: { NSWorkspace.shared.open(folder) })
        } else {
            state.showNotification(appName: "Tama", title: "Move Failed",
                                   message: "Some items could not be moved: \(failed.prefix(3).joined(separator: ", "))",
                                   icon: "exclamationmark.triangle.fill")
        }
    }

    // MARK: Save

    /// Save to Downloads: a copy, so the held file stays put.
    public static func saveCopies(_ items: [ShelfItem], to folder: URL = downloadsFolder) {
        // Copying a large file blocks for as long as it takes: off main.
        Task.detached(priority: .userInitiated) {
            var saved: [URL] = []
            var failed = 0
            for item in items {
                let destination = uniqueDestination(for: item.url, in: folder)
                do {
                    try FileManager.default.copyItem(at: item.url, to: destination)
                    saved.append(destination)
                } catch {
                    failed += 1
                }
            }
            let results = saved
            let failures = failed
            await MainActor.run { finishSave(results, failed: failures, folder: folder) }
        }
    }

    private static func finishSave(_ saved: [URL], failed: Int, folder: URL) {
        guard !saved.isEmpty else {
            state.showNotification(appName: "Tama", title: "Save failed",
                                   message: "Nothing could be copied to \(folder.lastPathComponent).",
                                   icon: "exclamationmark.triangle.fill")
            return
        }
        DroppyAudio.playDropSuccess()
        let urls = saved
        state.showNotification(
            appName: "Tama",
            title: "Saved to \(folder.lastPathComponent)",
            message: (saved.count == 1 ? saved[0].lastPathComponent : "\(saved.count) files") + (failed > 0 ? " · \(failed) failed" : ""),
            icon: "arrow.down.circle.fill",
            actionTitle: "Show in Finder",
            action: { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        )
    }

    // MARK: Rename

    public static func renameWithPrompt(_ item: ShelfItem) {
        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.informativeText = "Renames the file on disk too."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = item.url.lastPathComponent
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        state.setModal(true, owner: "fileOps.rename")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        // Select the name without its extension, like Finder.
        DispatchQueue.main.async {
            let base = (item.url.lastPathComponent as NSString).deletingPathExtension
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: (base as NSString).length)
        }
        let response = alert.runModal()
        state.setModal(false, owner: "fileOps.rename")
        guard response == .alertFirstButtonReturn else { return }
        rename(item, to: field.stringValue)
    }

    public static func rename(_ item: ShelfItem, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !name.isEmpty, name != item.url.lastPathComponent else { return }
        let destination = item.url.deletingLastPathComponent().appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            state.showNotification(appName: "Tama", title: "Rename failed",
                                   message: "\(name) already exists there.", icon: "exclamationmark.triangle.fill")
            return
        }
        do {
            try FileManager.default.moveItem(at: item.url, to: destination)
            state.updateHeldItems(ids: [item.id]) { $0 = $0.moved(to: destination) }
            DroppyAudio.playTick()
        } catch {
            state.showNotification(appName: "Tama", title: "Rename failed",
                                   message: error.localizedDescription, icon: "exclamationmark.triangle.fill")
        }
    }

    // MARK: Create Folder

    /// Gathers the items into a new folder that takes their place. Files
    /// Tama made itself move in; the user's own files are copied, so
    /// nothing is taken out of its original folder.
    public static func createFolder(from items: [ShelfItem]) {
        guard let first = items.first else { return }
        let container = AppState.trayStorageDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = container.appendingPathComponent(items.count == 1 ? first.url.deletingPathExtension().lastPathComponent : "New Folder",
                                                      isDirectory: true)
        let storage = AppState.trayStorageDirectory.resolvingSymlinksInPath().path
        // The user's own files are copied, which can take a while: the file
        // work runs off main, the Shelf is updated back on it.
        let ids = Set(items.map(\.id))
        state.heldItemsInFileWork.formUnion(ids)
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                let message = error.localizedDescription
                await MainActor.run {
                    state.heldItemsInFileWork.subtract(ids)
                    state.showNotification(appName: "Tama", title: "Create Folder Failed",
                                           message: message, icon: "exclamationmark.triangle.fill")
                }
                return
            }
            var failed = 0
            for item in items {
                let destination = uniqueDestination(for: item.url, in: folder)
                do {
                    if item.url.resolvingSymlinksInPath().path.hasPrefix(storage) {
                        try fm.moveItem(at: item.url, to: destination)
                    } else {
                        try fm.copyItem(at: item.url, to: destination)
                    }
                } catch {
                    failed += 1
                }
            }
            if failed >= items.count { try? fm.removeItem(at: container) }
            let failures = failed
            await MainActor.run {
                finishCreateFolder(items, folder: folder, failed: failures)
                state.heldItemsInFileWork.subtract(ids)
            }
        }
    }

    private static func finishCreateFolder(_ items: [ShelfItem], folder: URL, failed: Int) {
        guard let first = items.first else { return }
        guard failed < items.count else {
            state.showNotification(appName: "Tama", title: "Create Folder Failed",
                                   message: "None of the files could be added to the folder.",
                                   icon: "exclamationmark.triangle.fill")
            return
        }
        let folderItem = ShelfItem(url: folder)
        // The folder lives in Tray storage: if its tile had nowhere to go it
        // would be swept as an orphan at the next launch, with the files in it.
        let firstIsHeld = state.shelfItems.contains { $0.id == first.id }
            || state.baskets.contains { $0.items.contains { $0.id == first.id } }
        if firstIsHeld {
            state.replaceHeldItem(first.id, with: [folderItem])
        } else {
            state.addShelfItems([folderItem])
        }
        let rest = Set(items.dropFirst().map(\.id))
        if !rest.isEmpty {
            state.shelfItems.removeAll { rest.contains($0.id) }
            for index in state.baskets.indices { state.baskets[index].items.removeAll { rest.contains($0.id) } }
        }
        DroppyAudio.playDropSuccess()
        if failed > 0 {
            state.showNotification(appName: "Tama", title: "Folder Created with Issues",
                                   message: "\(failed) of \(items.count) files couldn't be added.",
                                   icon: "exclamationmark.triangle.fill")
        } else {
            state.showNotification(appName: "Tama", title: "Folder Created",
                                   message: "\(items.count) file\(items.count == 1 ? "" : "s") in \(folder.lastPathComponent)",
                                   icon: "folder.fill.badge.plus")
        }
    }

    // MARK: Open With

    /// Apps that can open every one of the files, the default first.
    public static func applications(for items: [ShelfItem]) -> [URL] {
        guard let first = items.first else { return [] }
        var apps = NSWorkspace.shared.urlsForApplications(toOpen: first.url)
        for item in items.dropFirst() {
            let other = Set(NSWorkspace.shared.urlsForApplications(toOpen: item.url).map(\.standardizedFileURL))
            apps = apps.filter { other.contains($0.standardizedFileURL) }
        }
        var seen = Set<String>()
        return apps.filter { seen.insert(appName($0)).inserted }
    }

    static func appName(_ url: URL) -> String {
        FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    public static func open(_ items: [ShelfItem], with app: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(items.map(\.url), withApplicationAt: app, configuration: config) { _, error in
            guard let error else { return }
            let message = error.localizedDescription
            Task { @MainActor in
                AppState.shared.showNotification(appName: "Tama", title: "Couldn't open",
                                                 message: message, icon: "exclamationmark.triangle.fill")
            }
        }
    }

    public static func openWithPicker(_ items: [ShelfItem]) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Open"
        state.setModal(true, owner: "fileOps.openWith")
        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()
        state.setModal(false, owner: "fileOps.openWith")
        guard response == .OK, let app = panel.url else { return }
        open(items, with: app)
    }

    // MARK: Text

    /// Extract Text: OCR every image and PDF, joined, onto the clipboard.
    public static func extractText(_ items: [ShelfItem]) {
        let urls = items.map(\.url).filter(OCRService.canRead)
        guard !urls.isEmpty else { return }
        Task { @MainActor in
            var texts: [String] = []
            for url in urls {
                if let result = try? await OCRService.recognize(url: url), !result.text.isEmpty {
                    texts.append(result.text)
                }
            }
            let text = texts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                state.showNotification(appName: "OCR", title: "No text found", message: "Nothing readable in \(urls.count == 1 ? urls[0].lastPathComponent : "these files").")
                return
            }
            ClipboardService.shared.copyToPasteboard(text: text)
            DroppyAudio.playCopySuccess()
            state.showNotification(appName: "OCR", title: "Text copied", message: "\(text.count) characters")
        }
    }
}

// MARK: - Smart Export

/// Settings › General › Automation › Smart Export: processed files are saved
/// into a folder per kind, under one base folder.
@MainActor
enum SmartExport {
    static var baseFolder: URL {
        let custom = FileActionSettings.shared.smartExportFolder
        if !custom.isEmpty { return URL(fileURLWithPath: custom, isDirectory: true) }
        return FileOperations.downloadsFolder.appendingPathComponent("Tama", isDirectory: true)
    }

    /// The folder for this kind, created on demand, or nil when Smart Export
    /// (or this kind) is off.
    static func folder(for kind: SmartExportKind) -> URL? {
        guard FileActionSettings.shared.smartExportEnabled else { return nil }
        let on: Bool
        switch kind {
        case .compressed: on = FileActionSettings.shared.smartExportCompressed
        case .converted: on = FileActionSettings.shared.smartExportConverted
        case .cutouts: on = FileActionSettings.shared.smartExportCutouts
        }
        guard on else { return nil }
        let folder = baseFolder.appendingPathComponent(kind.folderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        } catch {
            return nil
        }
    }

    /// Moves a finished file (from the temporary folder) into its Smart
    /// Export folder; returns where it is now.
    static func route(_ url: URL, kind: SmartExportKind) -> URL {
        guard let folder = folder(for: kind) else { return url }
        let destination = FileOperations.uniqueDestination(for: url, in: folder)
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        } catch {
            return url
        }
    }
}
