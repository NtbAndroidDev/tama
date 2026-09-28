import AppKit

extension AppState {
    /// The drop tiles as configured: Keep, then up to three chosen tiles.
    /// Quick Actions off leaves only Keep, so a drop simply lands.
    public var quickActions: [QuickAction] {
        guard FileActionSettings.shared.quickActionsEnabled else { return [.keep] }
        return [.keep] + QuickAction.tiles(from: FileActionSettings.shared.quickActionTilesStorage)
    }

    public var quickActionTiles: [QuickAction] {
        get { QuickAction.tiles(from: FileActionSettings.shared.quickActionTilesStorage) }
        set { FileActionSettings.shared.quickActionTilesStorage = QuickAction.storage(for: newValue) }
    }
}

/// Runs a Quick Action on dropped or held files. The same code serves the
/// notch's drop tiles, the Basket's and the context menus.
@MainActor
public enum QuickActionRunner {
    /// Where a drop landed: Keep puts the files there.
    public enum Origin {
        case island(openTray: Bool)
        case basket(UUID, bucket: Int)
    }

    public static func perform(_ action: QuickAction, items: [ShelfItem], from origin: Origin) {
        guard !items.isEmpty else { return }
        let state = AppState.shared
        switch action {
        case .keep:
            switch origin {
            case .island(let openTray):
                state.addShelfItems(items, reveal: openTray)
            case .basket(let id, let bucket):
                state.addBasketItems(items, to: id, bucket: bucket)
            }
            DroppyAudio.playDropSuccess()
        case .share:
            // The Tray moves dropped images and text out of the temporary
            // folder, so share what it now holds.
            state.pendingShare = state.addShelfItems(items, reveal: true)
        case .convert:
            state.pendingConvert = state.addShelfItems(items, reveal: true)
        case .zip:
            // One archive, kept on the surface the drag landed on.
            switch origin {
            case .island(let openTray):
                state.createArchive(of: items, into: .shelf)
                if openTray { state.open(.tray) }
            case .basket(let id, _):
                state.createArchive(of: items, into: .basket(id))
            }
        case .airDrop, .quickshare, .iCloud, .mail, .messages, .localSend:
            send(action, urls: items.map(\.url))
        }
    }

    /// The sharing tiles, for any files (context menus call this directly).
    public static func send(_ action: QuickAction, urls: [URL]) {
        let urls = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        switch action {
        case .airDrop: TrayActions.airDrop(urls)
        case .quickshare: QuickshareService.shared.upload(urls)
        case .iCloud: saveToICloudDrive(urls)
        case .mail: mail(urls)
        case .messages: message(urls)
        case .localSend: LocalSendService.shared.stage(urls)
        case .zip: AppState.shared.createArchive(of: urls.map { ShelfItem(url: $0) }, into: .shelf)
        case .keep, .share, .convert: break
        }
    }

    // MARK: Mail and Messages

    /// Settings › Quick Action mail app: the system's compose-email service,
    /// or the files handed to Mail or Outlook, which open a new message with
    /// them attached.
    static func mail(_ urls: [URL]) {
        let state = AppState.shared
        let choice = FileActionSettings.shared.quickActionMailApp
        if let bundleID = choice.bundleID {
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                state.showNotification(appName: "Mail", title: "\(choice.title) isn't installed",
                                       message: "Pick another mail app in Settings › General › Quick Actions.",
                                       icon: "envelope.badge.fill")
                return
            }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: config) { _, error in
                guard let error else { return }
                let message = error.localizedDescription
                Task { @MainActor in
                    AppState.shared.showNotification(appName: "Mail", title: "Couldn't start an email",
                                                     message: message, icon: "exclamationmark.triangle.fill")
                }
            }
            DroppyAudio.playTick()
            return
        }
        guard let service = NSSharingService(named: .composeEmail), service.canPerform(withItems: urls) else {
            state.showNotification(appName: "Mail", title: "No mail account",
                                   message: "Set up an account in Mail, or pick Outlook in Settings.", icon: "envelope.badge.fill")
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
        DroppyAudio.playTick()
    }

    static func message(_ urls: [URL]) {
        guard let service = NSSharingService(named: .composeMessage), service.canPerform(withItems: urls) else {
            AppState.shared.showNotification(appName: "Messages", title: "Can't share with Messages",
                                             message: "Sign in to Messages to send files.", icon: "message.fill")
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
        DroppyAudio.playTick()
    }

    // MARK: iCloud Drive

    static var iCloudDriveFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    /// Copies the files into iCloud Drive › Tama and shows them in Finder,
    /// where Share › Copy Link makes a link. macOS offers no public API to
    /// create an iCloud link directly.
    static func saveToICloudDrive(_ urls: [URL]) {
        let state = AppState.shared
        let fm = FileManager.default
        guard fm.fileExists(atPath: iCloudDriveFolder.path) else {
            state.showNotification(appName: "iCloud Drive", title: "iCloud Drive Unavailable",
                                   message: "Turn on iCloud Drive in System Settings › Apple Account › iCloud.",
                                   icon: "icloud.slash.fill")
            return
        }
        let folder = iCloudDriveFolder.appendingPathComponent("Tama", isDirectory: true)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            let denied = (error as NSError).code == NSFileWriteNoPermissionError
            state.showNotification(appName: "iCloud Drive",
                                   title: denied ? "Permission Required" : "Could Not Prepare iCloud Drive Folder",
                                   message: denied ? "Allow Tama to use iCloud Drive in System Settings › Privacy & Security › Files and Folders."
                                       : error.localizedDescription,
                                   icon: "exclamationmark.icloud.fill")
            return
        }
        // The copies can be large (and iCloud Drive slow to take them): the
        // copying runs off the main thread, Finder and the banner after it.
        Task.detached(priority: .userInitiated) {
            var copies: [URL] = []
            for url in urls {
                let destination = FileOperations.uniqueDestination(for: url, in: folder)
                if (try? FileManager.default.copyItem(at: url, to: destination)) != nil { copies.append(destination) }
            }
            let done = copies
            await MainActor.run { finishICloudCopy(urls, copies: done) }
        }
    }

    private static func finishICloudCopy(_ urls: [URL], copies: [URL]) {
        let state = AppState.shared
        guard !copies.isEmpty else {
            state.showNotification(appName: "iCloud Drive", title: "Upload failed",
                                   message: "The files couldn't be copied to iCloud Drive.", icon: "exclamationmark.icloud.fill")
            return
        }
        DroppyAudio.playDropSuccess()
        NSWorkspace.shared.activateFileViewerSelecting(copies)
        let shown = copies
        // Say so when only some of them made it, rather than reporting the
        // smaller number as if that were everything that was asked for.
        let failed = urls.count - copies.count
        let copied = "\(copies.count) file\(copies.count == 1 ? "" : "s") in Tama"
        state.showNotification(
            appName: "iCloud Drive",
            title: failed > 0 ? "Some files couldn't be copied" : "Saved to iCloud Drive",
            message: failed > 0
                ? "\(copied); \(failed) couldn't be copied. Share › Copy Link in Finder to share the rest."
                : "\(copied) — Share › Copy Link in Finder to share.",
            icon: failed > 0 ? "exclamationmark.icloud.fill" : "icloud.and.arrow.up.fill",
            actionTitle: "Show",
            action: { NSWorkspace.shared.activateFileViewerSelecting(shown) }
        )
    }
}
