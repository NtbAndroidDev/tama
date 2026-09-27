import AppKit
import UniformTypeIdentifiers

/// Writes into an Obsidian vault directly on disk: Obsidian watches the folder,
/// so appended lines show up in the app without any plugin.
@MainActor
final class ObsidianService: ObservableObject {
    static let shared = ObsidianService()

    enum Target: String, CaseIterable, Codable, Sendable {
        case daily = "Daily"
        case inbox = "Inbox"
    }

    struct Entry: Identifiable, Codable, Hashable {
        var id = UUID()
        let date: Date
        let text: String
        let note: String
    }

    enum ObsidianError: LocalizedError {
        case noVault
        case empty

        var errorDescription: String? {
            switch self {
            case .noVault: return "Choose an Obsidian vault first."
            case .empty: return "Nothing to append."
            }
        }
    }

    private let defaults = UserDefaults.standard

    @Published var vaultPath: String? {
        didSet { defaults.set(vaultPath, forKey: "obsidianVaultPath") }
    }
    /// Empty means "use the vault's Daily Notes settings".
    @Published var dailyFolderOverride: String {
        didSet { defaults.set(dailyFolderOverride, forKey: "obsidianDailyFolder") }
    }
    @Published var dailyFormatOverride: String {
        didSet { defaults.set(dailyFormatOverride, forKey: "obsidianDailyFormat") }
    }
    @Published var inboxPath: String {
        didSet { defaults.set(inboxPath, forKey: "obsidianInboxPath") }
    }
    @Published var target: Target {
        didSet { defaults.set(target.rawValue, forKey: "obsidianTarget") }
    }
    @Published private(set) var recentEntries: [Entry] = []
    /// The vault's notes, most recently modified first (see `refreshNotes`).
    @Published private(set) var vaultNotes: [VaultNote] = []
    @Published private(set) var isRefreshingNotes = false

    private init() {
        dailyFolderOverride = defaults.string(forKey: "obsidianDailyFolder") ?? ""
        dailyFormatOverride = defaults.string(forKey: "obsidianDailyFormat") ?? ""
        inboxPath = defaults.string(forKey: "obsidianInboxPath") ?? "Inbox.md"
        target = Target(rawValue: defaults.string(forKey: "obsidianTarget") ?? "") ?? .daily
        if let data = defaults.data(forKey: "obsidianRecentEntries"),
           let entries = try? JSONDecoder().decode([Entry].self, from: data) {
            recentEntries = entries
        }
        vaultPath = defaults.string(forKey: "obsidianVaultPath") ?? Self.detectedVaults().first?.path
    }

    /// Re-reads the vault and its note targets after Reset to Defaults or
    /// Import Settings, which write UserDefaults behind these properties.
    func reloadFromDefaults() {
        dailyFolderOverride = defaults.string(forKey: "obsidianDailyFolder") ?? ""
        dailyFormatOverride = defaults.string(forKey: "obsidianDailyFormat") ?? ""
        inboxPath = defaults.string(forKey: "obsidianInboxPath") ?? "Inbox.md"
        target = Target(rawValue: defaults.string(forKey: "obsidianTarget") ?? "") ?? .daily
        vaultPath = defaults.string(forKey: "obsidianVaultPath") ?? Self.detectedVaults().first?.path
    }

    var vaultURL: URL? {
        guard let vaultPath, FileManager.default.fileExists(atPath: vaultPath) else { return nil }
        return URL(fileURLWithPath: vaultPath, isDirectory: true)
    }

    var vaultName: String? { vaultURL?.lastPathComponent }

    // MARK: - Vaults

    /// Vaults Obsidian itself knows about, most recently opened first.
    static func detectedVaults() -> [URL] {
        let config = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/obsidian/obsidian.json")
        guard let data = try? Data(contentsOf: config),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vaults = json["vaults"] as? [String: [String: Any]] else { return [] }
        return vaults.values
            .compactMap { info -> (URL, Double)? in
                guard let path = info["path"] as? String, FileManager.default.fileExists(atPath: path) else { return nil }
                return (URL(fileURLWithPath: path, isDirectory: true), info["ts"] as? Double ?? 0)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    func pickVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Vault"
        panel.message = "Choose the folder of your Obsidian vault"
        if let vaultURL { panel.directoryURL = vaultURL }
        // Keep the island open while the panel has focus, or the console unmounts.
        AppState.shared.setModal(true, owner: "obsidian.service")
        defer { AppState.shared.setModal(false, owner: "obsidian.service") }
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            vaultPath = url.path
        }
    }

    // MARK: - Vault settings

    private func vaultConfig(_ name: String) -> [String: Any] {
        guard let vaultURL,
              let data = try? Data(contentsOf: vaultURL.appendingPathComponent(".obsidian/\(name)")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    var dailyFolder: String {
        if !dailyFolderOverride.isEmpty { return dailyFolderOverride }
        return vaultConfig("daily-notes.json")["folder"] as? String ?? ""
    }

    var dailyFormat: String {
        if !dailyFormatOverride.isEmpty { return dailyFormatOverride }
        let format = vaultConfig("daily-notes.json")["format"] as? String ?? ""
        return format.isEmpty ? "YYYY-MM-DD" : format
    }

    /// Vault-relative path of a note, always ending in `.md`.
    func notePath(for target: Target, date: Date = Date()) -> String {
        switch target {
        case .daily:
            let name = Self.formatter(fromMoment: dailyFormat, for: date).string(from: date)
            return Self.join(dailyFolder, name + ".md")
        case .inbox:
            let path = inboxPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let clean = path.isEmpty ? "Inbox" : path
            return clean.lowercased().hasSuffix(".md") ? clean : clean + ".md"
        }
    }

    // MARK: - Appending

    func append(_ text: String, asTask: Bool = false, to target: Target? = nil) throws {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw ObsidianError.empty }
        guard let vaultURL else { throw ObsidianError.noVault }
        let target = target ?? self.target
        let path = notePath(for: target)
        let noteURL = vaultURL.appendingPathComponent(path)

        let time = Self.timeFormatter.string(from: Date())
        let lines = body.components(separatedBy: .newlines)
        let head = asTask ? "- [ ] \(lines[0])" : "- \(time) \(lines[0])"
        // Continuation lines are indented so Obsidian keeps them inside the bullet.
        let entry = ([head] + lines.dropFirst().map { "    " + $0 }).joined(separator: "\n")
        try Self.appendLine(entry, to: noteURL)

        recentEntries.insert(Entry(date: Date(), text: body, note: path), at: 0)
        recentEntries = Array(recentEntries.prefix(5))
        if let data = try? JSONEncoder().encode(recentEntries) {
            defaults.set(data, forKey: "obsidianRecentEntries")
        }
    }

    /// Copies a file into the vault's attachment folder and appends an embed for it.
    func attach(_ fileURL: URL, to target: Target? = nil) throws {
        guard let vaultURL else { throw ObsidianError.noVault }
        let target = target ?? self.target
        let folder = attachmentFolder(forNote: notePath(for: target), in: vaultURL)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = Self.uniqueURL(for: fileURL.lastPathComponent, in: folder)
        try FileManager.default.copyItem(at: fileURL, to: destination)
        try append("![[\(destination.lastPathComponent)]]", to: target)
    }

    func attach(imageData: Data, to target: Target? = nil) throws {
        let stamp = Self.stampFormatter.string(from: Date())
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("Pasted image \(stamp).png")
        try imageData.write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        try attach(temp, to: target)
    }

    /// Mirrors Obsidian's "Default location for new attachments": "/" is the vault
    /// root, "./x" is relative to the note, anything else is vault-relative.
    private func attachmentFolder(forNote notePath: String, in vault: URL) -> URL {
        let setting = (vaultConfig("app.json")["attachmentFolderPath"] as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if setting.isEmpty { return vault.appendingPathComponent("attachments", isDirectory: true) }
        if setting == "/" { return vault }
        if setting.hasPrefix("./") {
            let noteFolder = (notePath as NSString).deletingLastPathComponent
            return vault.appendingPathComponent(Self.join(noteFolder, String(setting.dropFirst(2))), isDirectory: true)
        }
        return vault.appendingPathComponent(setting, isDirectory: true)
    }

    // MARK: - Clipping sources

    /// Appends whatever is on the system clipboard: files and images are
    /// copied into the vault, text goes in as an entry.
    func appendClipboard(asTask: Bool = false) throws -> String {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            for url in urls { try attach(url) }
            return urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
        }
        if let string = pasteboard.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try append(string, asTask: asTask)
            return "Clipboard text"
        }
        if let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try attach(imageData: png)
            return "Clipboard image"
        }
        throw ObsidianError.empty
    }

    // MARK: - Opening

    func openNote(_ target: Target? = nil) {
        guard let vaultName else { return }
        let path = notePath(for: target ?? self.target)
        let file = (path as NSString).deletingPathExtension
        let string = "obsidian://open?vault=\(Self.encode(vaultName))&file=\(Self.encode(file))"
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

    // MARK: - Helpers

    private static func appendLine(_ entry: String, to noteURL: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: noteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard fm.fileExists(atPath: noteURL.path) else {
            try (entry + "\n").write(to: noteURL, atomically: true, encoding: .utf8)
            return
        }
        let handle = try FileHandle(forUpdating: noteURL)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        var prefix = ""
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            if handle.readData(ofLength: 1) != Data("\n".utf8) { prefix = "\n" }
            try handle.seekToEnd()
        }
        try handle.write(contentsOf: Data((prefix + entry + "\n").utf8))
    }

    private static func uniqueURL(for name: String, in folder: URL) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = "\(base) \(index)"
            candidate = folder.appendingPathComponent(ext.isEmpty ? numbered : "\(numbered).\(ext)")
            index += 1
        }
        return candidate
    }

    private static func join(_ folder: String, _ name: String) -> String {
        let trimmed = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return trimmed.isEmpty ? name : "\(trimmed)/\(name)"
    }

    /// Obsidian's URI handler wants every reserved character escaped, "/" included.
    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmmss"
        return f
    }()

    /// Translates the Moment.js tokens Obsidian uses for note names into a
    /// DateFormatter pattern. `[text]` is Moment's literal escape. DateFormatter
    /// has no ordinal day, so `Do` becomes `date`'s "1st", "22nd"… as a literal.
    static func formatter(fromMoment moment: String, for date: Date) -> DateFormatter {
        let map: [(String, String)] = [
            ("YYYY", "yyyy"), ("YY", "yy"), ("MMMM", "MMMM"), ("MMM", "MMM"), ("MM", "MM"), ("M", "M"),
            ("DDDD", "DDD"), ("DD", "dd"), ("D", "d"), ("dddd", "EEEE"), ("ddd", "EEE"),
            ("ww", "ww"), ("w", "w"), ("gggg", "YYYY"), ("GGGG", "YYYY"), ("HH", "HH"), ("H", "H"),
            ("hh", "hh"), ("h", "h"), ("mm", "mm"), ("m", "m"), ("ss", "ss"), ("A", "a"), ("a", "a"), ("Q", "Q"),
        ]
        var pattern = ""
        var literal = ""
        func flushLiteral() {
            guard !literal.isEmpty else { return }
            pattern += "'" + literal.replacingOccurrences(of: "'", with: "''") + "'"
            literal = ""
        }
        var rest = Substring(moment)
        outer: while let first = rest.first {
            if first == "[", let close = rest.firstIndex(of: "]") {
                literal += rest[rest.index(after: rest.startIndex)..<close]
                rest = rest[rest.index(after: close)...]
                continue
            }
            if rest.hasPrefix("Do") {
                literal += ordinalDay(of: date)
                rest = rest.dropFirst(2)
                continue
            }
            for (token, replacement) in map where rest.hasPrefix(token) {
                flushLiteral()
                pattern += replacement
                rest = rest.dropFirst(token.count)
                continue outer
            }
            literal.append(first)
            rest = rest.dropFirst()
        }
        flushLiteral()
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        return f
    }

    /// Moment's `Do` in English: 1st, 2nd, 3rd, 4th, 11th–13th, 21st…
    static func ordinalDay(of date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let day = calendar.component(.day, from: date)
        let suffix: String
        switch (day % 10, day % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(day)\(suffix)"
    }
}

// MARK: - Vault notes

/// A Markdown note in the vault, for the droplet's note list.
struct VaultNote: Identifiable, Hashable, Sendable {
    var id: String { path }
    /// Relative to the vault.
    let path: String
    let title: String
    let preview: String
    let modified: Date
}

extension ObsidianService {
    /// A vault is set but its folder is gone or can't be read (moved, an
    /// unplugged drive, access revoked).
    var isVaultUnavailable: Bool {
        guard let vaultPath, !vaultPath.isEmpty else { return false }
        return !FileManager.default.isReadableFile(atPath: vaultPath)
    }

    /// Reads the vault's notes off the main thread: every .md outside
    /// `.obsidian` and `.trash`, newest first, capped at 200.
    func refreshNotes() {
        guard let vaultURL, !isRefreshingNotes else { return }
        isRefreshingNotes = true
        Task.detached(priority: .userInitiated) {
            let notes = Self.scanNotes(in: vaultURL)
            await MainActor.run {
                let service = ObsidianService.shared
                service.vaultNotes = notes
                service.isRefreshingNotes = false
            }
        }
    }

    nonisolated private static func scanNotes(in vault: URL) -> [VaultNote] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: vault, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [(URL, Date)] = []
        for case let url as URL in walker {
            if url.lastPathComponent == ".trash" || url.lastPathComponent == ".obsidian" {
                walker.skipDescendants()
                continue
            }
            guard url.pathExtension.lowercased() == "md",
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            found.append((url, values.contentModificationDate ?? .distantPast))
        }
        let base = vault.standardizedFileURL.path
        return found.sorted { $0.1 > $1.1 }.prefix(200).map { url, date in
            var relative = url.standardizedFileURL.path
            if relative.hasPrefix(base) { relative = String(relative.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            return VaultNote(path: relative, title: url.deletingPathExtension().lastPathComponent,
                             preview: preview(of: url), modified: date)
        }
    }

    /// The first line of body text: past front matter, headings' #s stripped.
    nonisolated private static func preview(of url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "No additional text" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 4096)) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        var inFrontMatter = false
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if index == 0, line == "---" { inFrontMatter = true; continue }
            if inFrontMatter { if line == "---" { inFrontMatter = false }; continue }
            let stripped = line.trimmingCharacters(in: CharacterSet(charactersIn: "#>-*[] ")).trimmingCharacters(in: .whitespaces)
            if !stripped.isEmpty { return stripped }
        }
        return "No additional text"
    }

    func url(for note: VaultNote) -> URL? {
        vaultURL?.appendingPathComponent(note.path)
    }

    func readNote(_ note: VaultNote) -> String {
        guard let url = url(for: note) else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func saveNote(_ note: VaultNote, text: String) throws {
        guard let url = url(for: note) else { throw ObsidianError.noVault }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// A new, empty note in the vault's root (or the inbox note's folder).
    func createNote() throws -> VaultNote {
        guard let vaultURL else { throw ObsidianError.noVault }
        let folderPath = (inboxPath as NSString).deletingLastPathComponent
        let folder = folderPath.isEmpty ? vaultURL : vaultURL.appendingPathComponent(folderPath, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = Self.uniqueURL(for: "Untitled.md", in: folder)
        try "".write(to: url, atomically: true, encoding: .utf8)
        let relative = folderPath.isEmpty ? url.lastPathComponent : "\(folderPath)/\(url.lastPathComponent)"
        let note = VaultNote(path: relative, title: url.deletingPathExtension().lastPathComponent,
                             preview: "No additional text", modified: Date())
        vaultNotes.insert(note, at: 0)
        return note
    }

    /// Open this note in Obsidian.
    func open(_ note: VaultNote) {
        guard let vaultName else { return }
        let file = (note.path as NSString).deletingPathExtension
        let string = "obsidian://open?vault=\(Self.encode(vaultName))&file=\(Self.encode(file))"
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

    /// Open this vault in Obsidian.
    func openVault() {
        guard let vaultName, let url = URL(string: "obsidian://open?vault=\(Self.encode(vaultName))") else { return }
        NSWorkspace.shared.open(url)
    }
}
