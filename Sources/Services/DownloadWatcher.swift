import AppKit

/// Shows a browser download in the notch while it's in progress, and offers to
/// put the finished file in the Tray. Browsers write to a partial file
/// (Chromium `.crdownload`, Safari `.download`, Firefox `.part`) and rename it
/// when done, so watching ~/Downloads for those is enough; no browser access needed.
@MainActor
public final class DownloadWatcher {
    public static let shared = DownloadWatcher()

    private static let partialExtensions: Set<String> = ["crdownload", "download", "part"]

    private var source: DispatchSourceFileSystemObject?
    private var poller: Timer?
    private var descriptor: Int32 = -1
    /// Partial file → when it was first seen.
    private var active: [URL: Date] = [:]
    private var lastScan = Date()

    private init() {}

    private var folder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    /// Starts or stops with the setting.
    public func apply(enabled: Bool) {
        enabled ? start() : stop()
    }

    private func start() {
        guard source == nil else { return }
        wantsWatching = true
        guard !isOpening else { return }
        isOpening = true
        // open() blocks until the user answers the Downloads-folder privacy
        // prompt, which froze the whole app at launch; open it off the main thread.
        let path = folder.path
        DispatchQueue.global(qos: .utility).async {
            let fd = open(path, O_EVTONLY)
            Task { @MainActor in DownloadWatcher.shared.attach(fd) }
        }
    }

    private var isOpening = false
    private var wantsWatching = false

    private func attach(_ fd: Int32) {
        isOpening = false
        guard fd >= 0 else { return }
        guard wantsWatching, source == nil else { close(fd); return }
        descriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { DownloadWatcher.shared.scan() } }
        source.setCancelHandler { [descriptor] in close(descriptor) }
        source.resume()
        self.source = source
        lastScan = Date()
        scan()
    }

    private func stop() {
        wantsWatching = false
        source?.cancel()
        source = nil
        poller?.invalidate()
        poller = nil
        active.removeAll()
        LiveActivityCenter.shared.end("download")
    }

    private func scan() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        let entries = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        let partials = entries.filter { Self.partialExtensions.contains($0.pathExtension.lowercased()) }

        for url in partials where active[url] == nil { active[url] = Date() }
        let finished = active.keys.filter { !partials.contains($0) }
        for url in finished { active[url] = nil }

        if !finished.isEmpty {
            // The finished file is whatever landed since the last scan and isn't partial.
            let since = lastScan.addingTimeInterval(-2)
            let landed = entries
                .filter { !Self.partialExtensions.contains($0.pathExtension.lowercased()) }
                .filter { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >= since }
                .max { Self.modified($0) < Self.modified($1) }
            if let landed { announce(landed) }
        }
        lastScan = Date()
        updateActivity()

        // Directory events only fire on create/rename; poll the size while a download runs.
        if active.isEmpty {
            poller?.invalidate()
            poller = nil
        } else if poller == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { _ in
                Task { @MainActor in DownloadWatcher.shared.scan() }
            }
            RunLoop.main.add(timer, forMode: .common)
            poller = timer
        }
    }

    private func updateActivity() {
        guard let (url, _) = active.max(by: { $0.value < $1.value }) else {
            LiveActivityCenter.shared.end("download")
            return
        }
        let bytes = Self.size(of: url)
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        let name = Self.displayName(url)
        let count = active.count
        LiveActivityCenter.shared.post(LiveActivity(
            id: "download",
            icon: "arrow.down.circle.fill",
            tint: DS.accent,
            trailing: .text(size.replacingOccurrences(of: " ", with: "")),
            priority: .ambient,
            label: count > 1 ? "Downloading \(count) files" : "Downloading \(name) · \(size)"
        ))
    }

    private func announce(_ url: URL) {
        let size = ByteCountFormatter.string(fromByteCount: Self.size(of: url), countStyle: .file)
        LiveActivityCenter.shared.post(LiveActivity(
            id: "downloadDone", icon: "checkmark.circle.fill", tint: DS.Palette.success,
            trailing: .none, priority: .urgent, label: "Downloaded \(url.lastPathComponent)",
            expiresAt: Date().addingTimeInterval(3)
        ))
        AppState.shared.showNotification(
            appName: "Downloads",
            title: url.lastPathComponent,
            message: "Downloaded · \(size)",
            actionTitle: "Add to Tray",
            action: { AppState.shared.addShelfItems([ShelfItem(url: url)], reveal: true) }
        )
    }

    private static func displayName(_ url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        return base.hasPrefix("Unconfirmed ") ? "a file" : base
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// Safari's `.download` is a bundle; count everything inside it.
    private static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true else { return Int64(values.fileSize ?? 0) }
        let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        var total: Int64 = 0
        while let item = items?.nextObject() as? URL {
            total += Int64((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
