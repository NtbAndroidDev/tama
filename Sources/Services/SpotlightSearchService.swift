import AppKit
import Foundation

/// One Spotlight hit, ready to draw.
public struct SearchResult: Identifiable, Equatable {
    public enum Group: Int, CaseIterable, Comparable {
        case applications, folders, documents, images, other

        public var title: String {
            switch self {
            case .applications: return "Applications"
            case .folders: return "Folders"
            case .documents: return "Documents"
            case .images: return "Images"
            case .other: return "Other"
            }
        }

        public static func < (lhs: Group, rhs: Group) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let parentPath: String
    public let group: Group
    public let lastUsed: Date?
}

/// Searches the Mac with Spotlight (NSMetadataQuery). Understands a few filter
/// tokens: `kind:pdf|image|app|folder|movie|audio|text` and `ext:swift`.
@MainActor
public final class SpotlightSearchService: ObservableObject {
    public static let shared = SpotlightSearchService()

    @Published public private(set) var sections: [(group: SearchResult.Group, items: [SearchResult])] = []
    @Published public private(set) var isSearching = false
    /// The query produced by the last finished search, so the view can tell
    /// "no matches" from "not searched yet".
    @Published public private(set) var lastQuery = ""
    public var results: [SearchResult] { sections.flatMap(\.items) }

    public static let wholeMacKey = "thunderstormWholeMac"
    public var searchesWholeMac: Bool {
        get { UserDefaults.standard.bool(forKey: Self.wholeMacKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.wholeMacKey)
            objectWillChange.send()
            if !pendingText.isEmpty { run(pendingText) }
        }
    }

    private static let limit = 60
    /// Spotlight sorts by last use; only this many are ranked, so a one-letter
    /// query doesn't walk tens of thousands of items.
    private static let scanLimit = 500

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var debounce: DispatchWorkItem?
    private var pendingText = ""

    init() {}

    /// Debounced so each keystroke doesn't restart a Spotlight query.
    public func search(_ text: String) {
        pendingText = text
        debounce?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            stop()
            sections = []
            lastQuery = ""
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.run(text) }
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    public func stop() {
        query?.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        query = nil
        isSearching = false
    }

    // MARK: Query

    private struct Parsed {
        var terms: [String] = []
        var contentTypes: [String] = []
        var extensions: [String] = []
    }

    private static let kinds: [String: [String]] = [
        "pdf": ["com.adobe.pdf"],
        "image": ["public.image"], "images": ["public.image"],
        "app": ["com.apple.application"], "apps": ["com.apple.application"], "application": ["com.apple.application"],
        "folder": ["public.folder"],
        "movie": ["public.movie"], "video": ["public.movie"],
        "audio": ["public.audio"], "music": ["public.audio"],
        "text": ["public.text"], "doc": ["public.text", "com.adobe.pdf", "public.composite-content"],
    ]

    private static func parse(_ text: String) -> Parsed {
        var parsed = Parsed()
        for token in text.split(whereSeparator: \.isWhitespace).map(String.init) {
            let lower = token.lowercased()
            if lower.hasPrefix("kind:"), let types = kinds[String(lower.dropFirst(5))] {
                parsed.contentTypes += types
            } else if lower.hasPrefix("ext:"), lower.count > 4 {
                parsed.extensions.append(String(lower.dropFirst(4)).trimmingCharacters(in: CharacterSet(charactersIn: ".")))
            } else {
                parsed.terms.append(token)
            }
        }
        return parsed
    }

    private static func predicate(for parsed: Parsed) -> NSPredicate? {
        var parts: [NSPredicate] = []
        for term in parsed.terms {
            // Wildcards and quotes would break out of the pattern.
            let safe = term.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "\"", with: "")
            guard !safe.isEmpty else { continue }
            let name = NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemDisplayNameKey, "*\(safe)*")
            // File contents only for longer words: "*a*" over every document is slow and noisy.
            if safe.count >= 3 {
                let content = NSPredicate(format: "%K LIKE[cd] %@", "kMDItemTextContent", "*\(safe)*")
                parts.append(NSCompoundPredicate(orPredicateWithSubpredicates: [name, content]))
            } else {
                parts.append(name)
            }
        }
        if !parsed.contentTypes.isEmpty {
            parts.append(NSCompoundPredicate(orPredicateWithSubpredicates: parsed.contentTypes.map {
                NSPredicate(format: "%K == %@", "kMDItemContentTypeTree", $0)
            }))
        }
        if !parsed.extensions.isEmpty {
            parts.append(NSCompoundPredicate(orPredicateWithSubpredicates: parsed.extensions.map {
                NSPredicate(format: "%K LIKE[c] %@", NSMetadataItemFSNameKey, "*.\($0)")
            }))
        }
        guard !parts.isEmpty else { return nil }
        return NSCompoundPredicate(andPredicateWithSubpredicates: parts)
    }

    private func run(_ text: String) {
        stop()
        let parsed = Self.parse(text)
        guard let predicate = Self.predicate(for: parsed) else {
            sections = []
            lastQuery = text
            return
        }
        let query = NSMetadataQuery()
        query.predicate = predicate
        query.searchScopes = searchesWholeMac
            ? [NSMetadataQueryLocalComputerScope]
            : [NSMetadataQueryUserHomeScope, "/Applications", "/System/Applications"]
        query.sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]
        query.operationQueue = .main
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryGatheringProgress, .NSMetadataQueryDidFinishGathering] {
            observers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] note in
                let finished = note.name == .NSMetadataQueryDidFinishGathering
                MainActor.assumeIsolated { self?.collect(finished: finished, terms: parsed.terms, text: text) }
            })
        }
        self.query = query
        isSearching = true
        if !query.start() { isSearching = false }
    }

    private func collect(finished: Bool, terms: [String], text: String) {
        guard let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var hits: [(result: SearchResult, score: Int)] = []
        let count = min(query.resultCount, Self.scanLimit)
        for index in 0..<count {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !Self.isNoise(path, home: home) else { continue }
            let url = URL(fileURLWithPath: path)
            let name = item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String ?? url.lastPathComponent
            let tree = item.value(forAttribute: "kMDItemContentTypeTree") as? [String] ?? []
            let group = Self.group(for: tree)
            let parent = url.deletingLastPathComponent().path
            let result = SearchResult(
                url: url,
                name: name,
                parentPath: parent.hasPrefix(home) ? "~" + String(parent.dropFirst(home.count)) : parent,
                group: group,
                lastUsed: item.value(forAttribute: "kMDItemLastUsedDate") as? Date
            )
            hits.append((result, Self.score(name: name, group: group, terms: terms)))
        }

        // Stable: equal scores keep Spotlight's last-used order.
        let ranked = hits.enumerated()
            .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .prefix(Self.limit)
            .map(\.element.result)
        sections = SearchResult.Group.allCases.compactMap { group in
            let items = ranked.filter { $0.group == group }
            return items.isEmpty ? nil : (group, items)
        }
        if finished {
            lastQuery = text
            isSearching = false
            query.stop()
        }
    }

    /// Apps first, then names that match the words over content-only matches.
    private static func score(name: String, group: SearchResult.Group, terms: [String]) -> Int {
        var score = group == .applications ? 1000 : 0
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        for term in terms {
            let t = term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            if folded == t { score += 300 } else if folded.hasPrefix(t) { score += 200 } else if folded.contains(t) { score += 100 }
        }
        return score
    }

    private static func group(for tree: [String]) -> SearchResult.Group {
        let types = Set(tree)
        if types.contains("com.apple.application") || types.contains("com.apple.application-bundle") { return .applications }
        if types.contains("public.folder") { return .folders }
        if types.contains("public.image") { return .images }
        if !types.isDisjoint(with: ["public.text", "com.adobe.pdf", "public.composite-content",
                                    "public.presentation", "public.spreadsheet", "public.content"]) {
            return .documents
        }
        return .other
    }

    /// Caches, app internals and dotfiles bury the results people look for.
    private static func isNoise(_ path: String, home: String) -> Bool {
        if path.contains("/.") || path.contains(".app/Contents/") { return true }
        if path.hasPrefix(home + "/Library/") { return true }
        return false
    }
}
