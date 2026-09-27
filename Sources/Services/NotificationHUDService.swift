import AppKit
import Combine

/// A notification macOS delivered to some app, as read from its store.
public struct MirroredNotification: Identifiable, Equatable, Sendable {
    public enum ReplyKind: Sendable { case messages, whatsapp, telegram, none }

    public let id: Int64
    public let bundleID: String
    public let title: String
    public let subtitle: String
    public let body: String
    public let date: Date
    /// The conversation it belongs to (Messages: the chat identifier).
    public let threadID: String?

    public var replyKind: ReplyKind {
        switch bundleID {
        case "com.apple.MobileSMS", "com.apple.iChat": .messages
        case "net.whatsapp.WhatsApp", "desktop.WhatsApp": .whatsapp
        case "ru.keepcoder.Telegram", "org.telegram.desktop": .telegram
        default: .none
        }
    }

    /// "Subtitle · body", like the reference's preview line.
    public var preview: String {
        [subtitle, body].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Parses a `record.data` plist from the usernoted store. Both the
    /// compact keys macOS writes (`titl`, `subt`, `body`, `thre`) and long
    /// ones are accepted; nil when there is nothing to show.
    static func parse(id: Int64, bundleID: String?, plist data: Data, deliveredAt: Double?) -> MirroredNotification? {
        guard let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let root = object as? [String: Any] else { return nil }
        let request = (root["req"] as? [String: Any]) ?? (root["request"] as? [String: Any]) ?? root
        func text(_ keys: String...) -> String {
            for key in keys {
                if let value = request[key] as? String, !value.isEmpty { return value }
            }
            return ""
        }
        let title = text("titl", "title")
        let subtitle = text("subt", "subtitle")
        let body = text("body", "message")
        guard !(title.isEmpty && subtitle.isEmpty && body.isEmpty) else { return nil }
        let app = bundleID ?? (root["app"] as? String) ?? ""
        let timestamp = deliveredAt ?? (root["date"] as? Double) ?? Date().timeIntervalSinceReferenceDate
        let thread = text("thre", "threadIdentifier")
        return MirroredNotification(id: id, bundleID: app, title: title, subtitle: subtitle, body: body,
                                    date: Date(timeIntervalSinceReferenceDate: timestamp),
                                    threadID: thread.isEmpty ? nil : thread)
    }
}

/// Notification HUD: mirrors the Mac's notifications into the notch. macOS
/// has no API for other apps' notifications, so this reads the notification
/// store usernoted keeps (SQLite), which needs Full Disk Access. It watches
/// the store's write-ahead log and only queries when it changes.
@MainActor
public final class NotificationHUDService: ObservableObject {
    public static let shared = NotificationHUDService()

    public enum Status: Equatable {
        case off
        /// "Checking the macOS notification store"
        case checking
        case needsFullDiskAccess
        case notFound
        case unsupported(String)
        case watching
    }

    @Published public private(set) var status: Status = .off
    /// Newest first, this session only (never written to disk).
    @Published public private(set) var recent: [MirroredNotification] = []
    /// A notification whose reply composer the console should open.
    @Published public var replyTargetID: Int64?

    private let queue = DispatchQueue(label: "app.tama.notification-store", qos: .utility)
    /// Only touched on `queue`.
    private nonisolated(unsafe) var reader: SQLiteReader?
    private nonisolated(unsafe) var lastRecordID: Int64 = 0
    private var walSource: DispatchSourceFileSystemObject?
    private var fallbackTimer: Timer?
    private var pendingQuery: DispatchWorkItem?
    private var waiting: [MirroredNotification] = []
    private var cancellables = Set<AnyCancellable>()
    private var storePath: String?

    private init() {}

    private var isEnabled: Bool {
        AppState.shared.droplets.first { $0.id == "notifications" }?.isEnabled ?? false
    }

    /// Starts or stops with the droplet's switch.
    public func sync() {
        if isEnabled { start() } else { stop() }
    }

    public func start() {
        guard status == .off || status == .needsFullDiskAccess || status == .notFound else { return }
        status = .checking
        if cancellables.isEmpty {
            AppState.shared.$activeNotification
                .map { $0?.id }
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { _ in
                    MainActor.assumeIsolated { NotificationHUDService.shared.bannerChanged() }
                }
                .store(in: &cancellables)
            // Granting Full Disk Access happens in System Settings; look again on return.
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
                .receive(on: DispatchQueue.main)
                .sink { _ in
                    MainActor.assumeIsolated {
                        let service = NotificationHUDService.shared
                        if service.status == .needsFullDiskAccess, service.isEnabled { service.start() }
                    }
                }
                .store(in: &cancellables)
        }
        let candidates = Self.storeCandidates
        queue.async { [weak self] in
            guard let self else { return }
            var outcome: Status = .notFound
            var opened: (SQLiteReader, String)?
            for path in candidates {
                do {
                    let reader = try SQLiteReader(path: path)
                    let record = reader.columns(of: "record")
                    let app = reader.columns(of: "app")
                    guard record.isSuperset(of: ["rec_id", "app_id", "data"]), app.isSuperset(of: ["app_id", "identifier"]) else {
                        outcome = .unsupported("The notification store's layout isn't one Tama knows (\(record.sorted().joined(separator: ", "))).")
                        continue
                    }
                    opened = (reader, path)
                    break
                } catch SQLiteReader.OpenError.notPermitted {
                    outcome = .needsFullDiskAccess
                } catch SQLiteReader.OpenError.missing {
                    continue
                } catch {
                    outcome = .unsupported("\(error)")
                }
            }
            if let (reader, _) = opened {
                self.reader = reader
                self.lastRecordID = (try? reader.query("SELECT MAX(rec_id) FROM record").first?.first?.int) ?? 0
            }
            let path = opened?.1
            let result = opened == nil ? outcome : .watching
            DispatchQueue.main.async {
                MainActor.assumeIsolated { NotificationHUDService.shared.didOpen(result, path: path) }
            }
        }
    }

    private func didOpen(_ result: Status, path: String?) {
        guard isEnabled else { return stop() }
        status = result
        storePath = path
        guard result == .watching, let path else { return }
        watch(path)
    }

    public func stop() {
        walSource?.cancel()
        walSource = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        pendingQuery?.cancel()
        pendingQuery = nil
        waiting.removeAll()
        status = .off
        queue.async { [weak self] in self?.reader = nil }
    }

    /// Where usernoted keeps the store: the group container on Sequoia and
    /// later, the per-user cache folder before that.
    static var storeCandidates: [String] {
        var paths = [NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/db"]
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if confstr(_CS_DARWIN_USER_DIR, &buffer, buffer.count) > 0 {
            let dir = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            paths.append((dir as NSString).appendingPathComponent("com.apple.notificationcenter/db2/db"))
        }
        return paths
    }

    // MARK: Watching

    private func watch(_ path: String) {
        walSource?.cancel()
        let wal = path + "-wal"
        let target = FileManager.default.fileExists(atPath: wal) ? wal : path
        let fd = open(target, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename],
                                                                   queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    let service = NotificationHUDService.shared
                    if let events = service.walSource?.data, events.contains(.delete) || events.contains(.rename) {
                        // A checkpoint replaced the file: watch the new one.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            MainActor.assumeIsolated {
                                if let path = service.storePath, service.status == .watching { service.watch(path) }
                            }
                        }
                    }
                    service.scheduleQuery()
                }
            }
            source.setCancelHandler { close(fd) }
            walSource = source
            source.resume()
        }
        // A slow safety net in case an event is missed (the WAL is swapped out).
        fallbackTimer?.invalidate()
        let timer = Timer(timeInterval: 10, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard !PowerStateService.shared.isDormant else { return }
                NotificationHUDService.shared.scheduleQuery()
            }
        }
        timer.tolerance = 3
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
    }

    private func scheduleQuery() {
        guard pendingQuery == nil else { return }
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                NotificationHUDService.shared.pendingQuery = nil
                NotificationHUDService.shared.queryNew()
            }
        }
        pendingQuery = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func queryNew() {
        queue.async { [weak self] in
            guard let self, let reader = self.reader else { return }
            let rows = (try? reader.query("""
                SELECT r.rec_id, a.identifier, r.data, r.delivered_date
                FROM record r LEFT JOIN app a ON a.app_id = r.app_id
                WHERE r.rec_id > ? ORDER BY r.rec_id LIMIT 50
                """, [.integer(self.lastRecordID)])) ?? []
            var found: [MirroredNotification] = []
            for row in rows where row.count >= 4 {
                guard let id = row[0].int else { continue }
                self.lastRecordID = max(self.lastRecordID, id)
                guard let data = row[2].data,
                      let note = MirroredNotification.parse(id: id, bundleID: row[1].string, plist: data,
                                                            deliveredAt: row[3].double) else { continue }
                found.append(note)
            }
            guard !found.isEmpty else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { NotificationHUDService.shared.receive(found) }
            }
        }
    }

    // MARK: Showing

    var blockedApps: Set<String> {
        Set(AppState.shared.notificationHUDBlockedApps.split(separator: "\n").map(String.init))
    }

    private func receive(_ notifications: [MirroredNotification]) {
        let own = Bundle.main.bundleIdentifier
        let fresh = notifications.filter {
            $0.bundleID != own && !blockedApps.contains($0.bundleID)
                // A backlog after sleep isn't news.
                && Date().timeIntervalSince($0.date) < 90
        }
        guard !fresh.isEmpty else { return }
        recent.insert(contentsOf: fresh.reversed(), at: 0)
        if recent.count > 50 { recent.removeLast(recent.count - 50) }
        waiting.append(contentsOf: fresh)
        presentNext()
    }

    /// Waits for Tama's own banners and the one on screen; a burst of three
    /// or more folds into one summary when Burst notifications is on.
    private func presentNext() {
        let state = AppState.shared
        guard !waiting.isEmpty, state.activeNotification == nil else { return }
        let duration = max(state.notificationHUDDuration, 2)
        if state.notificationHUDBurst, waiting.count >= 3 {
            let burst = waiting
            waiting.removeAll()
            let apps = Set(burst.map(\.bundleID))
            let appName = apps.count == 1 ? Self.appName(for: burst[0].bundleID) : "Notifications"
            let notification = DroppyNotification(
                appName: appName, title: "\(burst.count) new notifications",
                message: burst.prefix(3).map { $0.title.isEmpty ? $0.body : $0.title }.joined(separator: " · "),
                sourceBundleID: apps.count == 1 ? burst[0].bundleID : nil, isMirrored: true)
            show(notification, duration: duration)
            return
        }
        let next = waiting.removeFirst()
        let preview = state.notificationHUDPreview
        let notification = DroppyNotification(
            appName: Self.appName(for: next.bundleID),
            title: preview ? next.title : Self.appName(for: next.bundleID),
            message: preview ? next.preview : "New notification",
            actionTitle: state.notificationHUDQuickReply && next.replyKind != .none ? "Reply" : nil,
            action: { NotificationHUDService.shared.beginReply(next.id) },
            sourceBundleID: next.bundleID, isMirrored: true)
        // Shorter while more are waiting, so a queue drains.
        show(notification, duration: waiting.isEmpty ? duration : min(duration, 2.5))
    }

    private func show(_ notification: DroppyNotification, duration: TimeInterval) {
        AppState.shared.present(notification, duration: duration)
    }

    private func bannerChanged() {
        guard AppState.shared.activeNotification == nil, !waiting.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            MainActor.assumeIsolated { NotificationHUDService.shared.presentNext() }
        }
    }

    public func clearRecent() {
        recent.removeAll()
    }

    public func remove(_ id: Int64) {
        recent.removeAll { $0.id == id }
    }

    /// Opens the Notifications console with the reply composer for this one.
    func beginReply(_ id: Int64) {
        replyTargetID = id
        let state = AppState.shared
        state.open(.widgets)
        state.activeDropletID = "notifications"
        NotchWindowController.shared.focusPanel()
    }

    // MARK: Apps

    static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    public func setBlocked(_ bundleID: String, _ blocked: Bool) {
        var apps = blockedApps
        if blocked { apps.insert(bundleID) } else { apps.remove(bundleID) }
        AppState.shared.notificationHUDBlockedApps = apps.sorted().joined(separator: "\n")
    }

    public func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
