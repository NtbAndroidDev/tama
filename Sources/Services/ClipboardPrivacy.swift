import SwiftUI
import AppKit
import UniformTypeIdentifiers

public enum ClipboardPauseDuration: String, CaseIterable, Identifiable, Sendable {
    case fiveMinutes, oneHour, untilResumed

    public var id: Self { self }
    public var title: String {
        switch self {
        case .fiveMinutes: return "For 5 Minutes"
        case .oneHour: return "For 1 Hour"
        case .untilResumed: return "Until I Turn It Back On"
        }
    }
    var interval: TimeInterval? {
        switch self {
        case .fiveMinutes: return 5 * 60
        case .oneHour: return 60 * 60
        case .untilResumed: return nil
        }
    }
}

public enum ClipboardRetention: String, CaseIterable, Identifiable, Sendable {
    case forever, day, week, month

    public var id: Self { self }
    public var title: String {
        switch self {
        case .forever: return "Forever"
        case .day: return "1 Day"
        case .week: return "7 Days"
        case .month: return "30 Days"
        }
    }
    var maxAge: TimeInterval? {
        switch self {
        case .forever: return nil
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        }
    }
}

/// What the clipboard history is allowed to keep: pause, excluded apps,
/// the sensitive-content filter and how long / how much it retains.
@MainActor
public final class ClipboardPrivacy: ObservableObject {
    public static let shared = ClipboardPrivacy()

    /// Password managers and the keychain; most mark copies as concealed, but not all do.
    public static let defaultExcludedApps = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
    ]

    private static let pausedUntilKey = "clipboardPausedUntil"
    private static let excludedKey = "clipboardExcludedApps"

    /// `.distantFuture` means paused until the user resumes.
    @Published public private(set) var pausedUntil: Date?
    @Published public var excludedBundleIDs: [String] {
        didSet { UserDefaults.standard.set(excludedBundleIDs, forKey: Self.excludedKey) }
    }
    @AppStorage("clipboardFilterSensitive") public var filterSensitive: Bool = true
    /// Sensitive text that isn't skipped is kept, but drawn blurred until hovered.
    @AppStorage("clipboardBlurSensitive") public var blurSensitive: Bool = false
    @AppStorage("clipboardRetention") public var retention: ClipboardRetention = .forever {
        didSet { AppState.shared.applyClipboardRetention() }
    }
    @AppStorage("clipboardImageLimitMB") public var imageLimitMB: Int = 500 {
        didSet { AppState.shared.applyClipboardRetention() }
    }

    private var resumeTimer: Timer?
    private var retentionTimer: Timer?

    private init() {
        let defaults = UserDefaults.standard
        excludedBundleIDs = defaults.stringArray(forKey: Self.excludedKey) ?? Self.defaultExcludedApps
        let stamp = defaults.double(forKey: Self.pausedUntilKey)
        if stamp > 0 {
            let date = Date(timeIntervalSince1970: stamp)
            if date > Date() { pausedUntil = date } else { defaults.removeObject(forKey: Self.pausedUntilKey) }
        }
        scheduleResume()
    }

    // MARK: Pause

    public var isPaused: Bool {
        guard let pausedUntil else { return false }
        return pausedUntil > Date()
    }

    public var isPausedIndefinitely: Bool { pausedUntil == .distantFuture }

    public func pause(_ duration: ClipboardPauseDuration) {
        let until = duration.interval.map { Date().addingTimeInterval($0) } ?? .distantFuture
        pausedUntil = until
        UserDefaults.standard.set(until.timeIntervalSince1970, forKey: Self.pausedUntilKey)
        scheduleResume()
        DroppyAudio.playTick()
    }

    public func resume() {
        pausedUntil = nil
        UserDefaults.standard.removeObject(forKey: Self.pausedUntilKey)
        resumeTimer?.invalidate()
        resumeTimer = nil
    }

    /// "Paused until 3:45 PM" / "Paused" — for the shelf and Settings.
    public var pauseDescription: String {
        guard let pausedUntil, isPaused else { return "Recording" }
        if pausedUntil == .distantFuture { return "Paused until you resume" }
        return "Paused until \(pausedUntil.formatted(date: .omitted, time: .shortened))"
    }

    /// ClipboardService checks `isPaused` itself; the timer only flips the UI back.
    private func scheduleResume() {
        resumeTimer?.invalidate()
        resumeTimer = nil
        guard let pausedUntil, pausedUntil != .distantFuture else { return }
        let delay = pausedUntil.timeIntervalSinceNow
        guard delay > 0 else {
            resume()
            return
        }
        resumeTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.resume() }
        }
    }

    // MARK: Excluded apps

    public func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedBundleIDs.contains { $0.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    public func exclude(_ bundleID: String) {
        let clean = bundleID.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, !isExcluded(clean) else { return }
        excludedBundleIDs.append(clean)
    }

    public func include(_ bundleID: String) {
        excludedBundleIDs.removeAll { $0 == bundleID }
    }

    public func chooseAppToExclude() {
        let panel = NSOpenPanel()
        panel.title = "Choose an App to Exclude"
        panel.prompt = "Exclude"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier { exclude(id) }
        }
    }

    /// Regular apps running now that aren't excluded yet, for the quick-add menu.
    public var runningAppsToExclude: [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { (app.localizedName ?? $0, $0) } }
            .filter { !isExcluded($0.1) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    public static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: Retention

    /// Trims now, then every hour while Tama runs.
    func startRetention(for state: AppState) {
        retentionTimer?.invalidate()
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak state] _ in
            Task { @MainActor in state?.applyClipboardRetention() }
        }
        state.applyClipboardRetention()
    }
}

// MARK: - Retention

extension AppState {
    /// Drops history clips older than the retention window, then evicts the
    /// oldest unstarred image clips while stored images exceed the size cap.
    /// Starred and pinboard clips are never touched.
    public func applyClipboardRetention() {
        let privacy = ClipboardPrivacy.shared
        let isHistory: (ClipboardItem) -> Bool = { !$0.isPinned && $0.board == nil }
        var removed: [ClipboardItem] = []

        if let maxAge = privacy.retention.maxAge {
            let cutoff = Date().addingTimeInterval(-maxAge)
            removed = clipboardItems.filter { isHistory($0) && $0.copiedAt < cutoff }
            if !removed.isEmpty {
                let ids = Set(removed.map(\.id))
                clipboardItems.removeAll { ids.contains($0.id) }
            }
        }
        deleteImageFiles(of: removed)

        let images = clipboardItems.filter { $0.type == .image }
        let limit = Int64(max(privacy.imageLimitMB, 1)) * 1_000_000
        Task { [weak self] in
            let filenames = Set(images.map(\.content))
            let sizes = await Task.detached(priority: .utility) { () -> [String: Int64] in
                var result: [String: Int64] = [:]
                for name in filenames {
                    let size = (try? ClipboardImageStore.url(for: name).resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    result[name] = Int64(size)
                }
                return result
            }.value
            guard let self else { return }
            var total = sizes.values.reduce(0, +)
            guard total > limit else { return }
            // Oldest first; files shared by two clips are only counted once.
            var evicted: [ClipboardItem] = []
            var freed = Set<String>()
            for item in self.clipboardItems.filter({ $0.type == .image && isHistory($0) }).sorted(by: { $0.copiedAt < $1.copiedAt }) {
                guard total > limit else { break }
                evicted.append(item)
                if freed.insert(item.content).inserted { total -= sizes[item.content] ?? 0 }
            }
            guard !evicted.isEmpty else { return }
            let ids = Set(evicted.map(\.id))
            self.clipboardItems.removeAll { ids.contains($0.id) }
            self.deleteImageFiles(of: evicted)
        }
    }

    /// Unlike the count trim these clips aren't coming back, so their files go now.
    private func deleteImageFiles(of items: [ClipboardItem]) {
        let still = Set(clipboardItems.filter { $0.type == .image }.map(\.content))
        let files = Set(items.filter { $0.type == .image }.map(\.content)).subtracting(still)
        guard !files.isEmpty else { return }
        Task.detached(priority: .background) {
            for name in files { try? FileManager.default.removeItem(at: ClipboardImageStore.url(for: name)) }
        }
    }

    /// Bytes used by stored clipboard images, for Settings.
    public nonisolated static func clipboardImageStorageBytes() async -> Int64 {
        await Task.detached(priority: .utility) {
            let files = (try? FileManager.default.contentsOfDirectory(at: ClipboardImageStore.directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            return files.reduce(Int64(0)) { sum, url in
                sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
        }.value
    }
}
