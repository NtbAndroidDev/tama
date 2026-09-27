import AppKit

/// Settings › General › Automation › Tracked folders: watches folders the
/// user picked and takes in each new file that lands in one. A file counts as
/// new once it has stopped growing, so half-written downloads and exports
/// aren't grabbed early; partial-download files are skipped altogether.
///
/// Each folder carries its own action (`TrackedFolderAction`): the Shelf, a
/// Basket, or the Shelf with the file compressed where it lands. Arrivals are
/// gathered per action, so a folder full of files is one batch, not one job
/// each.
@MainActor
public final class TrackedFolderService {
    public static let shared = TrackedFolderService()

    private static let partialExtensions: Set<String> = ["crdownload", "download", "part", "tmp", "partial"]

    private final class Watch {
        let folder: URL
        /// What this folder does with an arrival, kept in step with settings.
        var action: TrackedFolderAction = .tray
        var source: DispatchSourceFileSystemObject?
        /// Names already there (or already added), so only arrivals count.
        var known: Set<String> = []
        /// Arrivals waiting to settle: name → size last time.
        var pending: [String: Int64] = [:]
        init(folder: URL) { self.folder = folder }
    }

    private var watches: [String: Watch] = [:]
    private var settleTimer: Timer?

    private init() {}

    public var folders: [TrackedFolder] {
        TrackedFolder.decode(AppState.shared.trackedFoldersStorage)
    }

    public func add(_ folder: URL, action: TrackedFolderAction = .tray) {
        var list = folders
        guard !list.contains(where: { $0.path == folder.path }) else { return }
        list.append(TrackedFolder(path: folder.path, action: action))
        AppState.shared.trackedFoldersStorage = TrackedFolder.encode(list)
    }

    public func remove(_ folder: TrackedFolder) {
        AppState.shared.trackedFoldersStorage =
            TrackedFolder.encode(folders.filter { $0.path != folder.path })
    }

    /// Changing the action takes effect on the next arrival; files already
    /// taken in are left alone.
    public func setAction(_ action: TrackedFolderAction, for folder: TrackedFolder) {
        var list = folders
        guard let index = list.firstIndex(where: { $0.path == folder.path }),
              list[index].action != action else { return }
        list[index].action = action
        AppState.shared.trackedFoldersStorage = TrackedFolder.encode(list)
    }

    /// Starts and stops watches to match the settings, and carries an action
    /// the user changed onto the watch that is already running.
    public func sync() {
        let state = AppState.shared
        let wanted = state.trackedFoldersEnabled ? folders : []
        let byPath = Dictionary(wanted.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        for (path, watch) in watches {
            guard let folder = byPath[path] else {
                watch.source?.cancel()
                watches[path] = nil
                continue
            }
            watch.action = folder.action
        }
        for folder in wanted where watches[folder.path] == nil {
            start(folder)
        }
        if watches.isEmpty {
            settleTimer?.invalidate()
            settleTimer = nil
        }
    }

    private func start(_ folder: TrackedFolder) {
        let watch = Watch(folder: folder.url)
        watch.action = folder.action
        watches[folder.path] = watch
        // open() can block on a privacy prompt (Desktop, Documents,
        // Downloads), so it happens off the main thread.
        let path = folder.path
        DispatchQueue.global(qos: .utility).async {
            let fd = open(path, O_EVTONLY)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            Task { @MainActor in TrackedFolderService.shared.attach(fd, names: names, to: path) }
        }
    }

    private func attach(_ fd: Int32, names: [String], to path: String) {
        guard let watch = watches[path], watch.source == nil else {
            if fd >= 0 { close(fd) }
            return
        }
        guard fd >= 0 else {
            watches[path] = nil
            AppState.shared.showNotification(appName: "Tracked folders", title: "Can't watch folder",
                                             message: "\(URL(fileURLWithPath: path).lastPathComponent) couldn't be opened.",
                                             icon: "exclamationmark.triangle.fill")
            return
        }
        watch.known = Set(names)
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { TrackedFolderService.shared.scan(path) }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watch.source = source
    }

    private func scan(_ path: String) {
        guard let watch = watches[path] else { return }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        let current = Set(names)
        for name in current.subtracting(watch.known) where watch.pending[name] == nil {
            guard !name.hasPrefix("."),
                  !Self.partialExtensions.contains((name as NSString).pathExtension.lowercased()) else { continue }
            watch.pending[name] = -1
        }
        // Names that went away can come back as new later.
        watch.known.formIntersection(current)
        watch.pending = watch.pending.filter { current.contains($0.key) }
        if !watch.pending.isEmpty { startSettling() }
    }

    private func startSettling() {
        guard settleTimer == nil else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in TrackedFolderService.shared.settle() }
        }
        RunLoop.main.add(timer, forMode: .common)
        settleTimer = timer
    }

    /// Takes in arrivals whose size held still since the last tick, each folder
    /// doing what its own action says.
    private func settle() {
        var anyPending = false
        var ready: [TrackedFolderAction: [URL]] = [:]
        for watch in watches.values {
            for (name, lastSize) in watch.pending {
                let url = watch.folder.appendingPathComponent(name)
                let size = ShelfItem.size(of: url)
                if size == lastSize, FileManager.default.fileExists(atPath: url.path) {
                    watch.pending[name] = nil
                    watch.known.insert(name)
                    ready[watch.action, default: []].append(url)
                } else {
                    watch.pending[name] = size
                    anyPending = true
                }
            }
        }
        for (action, urls) in ready { take(urls, action: action) }
        if !ready.isEmpty { DroppyAudio.playDropSuccess() }
        if !anyPending {
            settleTimer?.invalidate()
            settleTimer = nil
        }
    }

    /// One batch of arrivals from folders that share an action.
    private func take(_ urls: [URL], action: TrackedFolderAction) {
        let state = AppState.shared
        let items = urls.map { ShelfItem(url: $0) }
        switch action {
        case .tray:
            state.addShelfItems(items)
        case .basket:
            // Opening it is the point: a file routed to a Basket that isn't on
            // screen would land somewhere nobody can see.
            state.showBasket(nearPointer: false)
            guard let basket = state.baskets.last else {
                state.addShelfItems(items)
                return
            }
            state.addBasketItems(items, to: basket.id)
        case .compress:
            // Held first, so the compressed file takes the original's place on
            // the Shelf rather than appearing beside it.
            let held = state.addShelfItems(items)
            let targets = held.filter { FileCompressor.canCompress($0.url) }
            guard !targets.isEmpty else { return }
            CompressActions.compress(targets, level: state.trackedFoldersCompressionLevel)
        }
    }
}
