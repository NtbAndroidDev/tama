import AppKit
import Combine

/// One note: rich text (RTF) plus a plain-text copy for titles, previews,
/// search and capture.
public struct DroppyNote: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var rtf: Data
    public var text: String
    public var created = Date()
    public var modified = Date()
    public var isPinned = false
    /// The Apple Notes note it syncs with, and that note's modification date
    /// when it was last read or written.
    public var appleNoteID: String?
    public var appleModified: Date?

    public var lines: [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public var title: String { lines.first.map(Self.stripMarker) ?? "New Note" }
    public var preview: String { lines.dropFirst().first.map(Self.stripMarker) ?? "No additional text" }
    public var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private static func stripMarker(_ line: String) -> String {
        if line.hasPrefix("• ") { return String(line.dropFirst(2)) }
        return line
    }
}

/// Every note, saved to Application Support › Tama › notes.json, with an
/// optional two-way sync to a "Tama" folder in Apple Notes (AppleScript):
/// edits are pushed a moment after typing stops, and the folder is read back
/// whenever Notes opens.
@MainActor
public final class NotesStore: ObservableObject {
    public static let shared = NotesStore()

    public enum SyncStatus: Equatable, Sendable {
        case idle, syncing
        case unreachable(String)
        case scriptFailed(String)
    }

    @Published public private(set) var notes: [DroppyNote] = []
    @Published public private(set) var syncStatus: SyncStatus = .idle
    /// Set by the home card to open a note in the console.
    @Published public var requestedNoteID: UUID?

    private var saveWork: DispatchWorkItem?
    private var pushWork: [UUID: DispatchWorkItem] = [:]

    static var fileURL: URL { AppState.supportDirectory.appendingPathComponent("notes.json") }

    private init() {
        load()
    }

    /// Pinned first, then the most recently edited.
    public var ordered: [DroppyNote] {
        notes.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.modified > b.modified
        }
    }

    public func note(_ id: UUID) -> DroppyNote? { notes.first { $0.id == id } }

    /// The note Scratchpad-style capture reads (Obsidian's Note button).
    public var latest: DroppyNote? { notes.max { $0.modified < $1.modified } }

    // MARK: Loading & saving

    private func load() {
        if let data = try? Data(contentsOf: Self.fileURL) {
            if let decoded = try? JSONDecoder().decode([DroppyNote].self, from: data) {
                notes = decoded
            } else {
                // Unreadable: keep it aside instead of overwriting it.
                let backup = Self.fileURL.deletingLastPathComponent()
                    .appendingPathComponent("notes.corrupt-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.moveItem(at: Self.fileURL, to: backup)
            }
            return
        }
        // First run with Notes: the old single scratchpad becomes a note.
        let legacy = UserDefaults.standard.string(forKey: "scratchpadText") ?? ""
        if !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes = [Self.make(from: NSAttributedString(string: legacy, attributes: RichText.bodyAttributes))]
            save()
        }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Encodes and writes a snapshot on `diskQueue`: rich-text notes make a
    /// sizeable JSON file, and an atomic write of it on main hitched typing.
    private func save() {
        saveWork?.cancel()
        saveWork = nil
        let snapshot = notes
        let url = Self.fileURL
        Self.diskQueue.async { Self.write(snapshot, to: url) }
    }

    /// Called on quit: synchronous, through the same serial queue, so a
    /// write already in flight lands first and this one can't be lost.
    public func flush() {
        if saveWork != nil {
            saveWork?.cancel()
            saveWork = nil
            let snapshot = notes
            let url = Self.fileURL
            Self.diskQueue.sync { Self.write(snapshot, to: url) }
        } else {
            Self.diskQueue.sync {}
        }
    }

    /// Serial, so saves close together land in the order they were made.
    private nonisolated static let diskQueue = DispatchQueue(label: "app.tama.notes", qos: .utility)

    private nonisolated static func write(_ notes: [DroppyNote], to url: URL) {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Editing

    private static func make(from attributed: NSAttributedString) -> DroppyNote {
        DroppyNote(rtf: RichText.rtf(attributed), text: attributed.string)
    }

    @discardableResult
    public func create(_ text: String = "") -> UUID {
        let note = Self.make(from: NSAttributedString(string: text, attributes: RichText.bodyAttributes))
        notes.append(note)
        scheduleSave()
        if !text.isEmpty { schedulePush(note.id) }
        return note.id
    }

    public func update(_ id: UUID, with attributed: NSAttributedString) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let text = attributed.string
        guard text != notes[index].text || RichText.rtf(attributed) != notes[index].rtf else { return }
        notes[index].rtf = RichText.rtf(attributed)
        notes[index].text = text
        notes[index].modified = Date()
        scheduleSave()
        schedulePush(id)
    }

    /// Leaving the editor: an untouched new note isn't kept.
    public func discardIfEmpty(_ id: UUID) {
        guard let note = note(id), note.isEmpty, note.appleNoteID == nil else { return }
        notes.removeAll { $0.id == id }
        scheduleSave()
    }

    public func togglePin(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isPinned.toggle()
        scheduleSave()
    }

    public func copy(_ id: UUID) {
        guard let note = note(id) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(note.rtf, forType: .rtf)
        pasteboard.setString(note.text, forType: .string)
        DroppyAudio.playCopySuccess()
    }

    /// Deletes behind an Undo banner; the Apple Notes copy goes too.
    public func delete(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let removed = notes.remove(at: index)
        pushWork[id]?.cancel()
        pushWork[id] = nil
        scheduleSave()
        // Apple Notes keeps its own "Recently Deleted" for 30 days.
        if NotesSettings.shared.appleSync, let appleID = removed.appleNoteID { deleteFromAppleNotes(appleID) }
        AppState.shared.showNotification(appName: "Notes", title: "Note deleted", message: removed.title,
                                         icon: "trash.fill", actionTitle: "Undo") {
            let store = NotesStore.shared
            var restored = removed
            restored.appleNoteID = nil
            store.notes.append(restored)
            store.scheduleSave()
            store.schedulePush(restored.id)
        }
    }

    /// Empties a note's text, keeping the note; the banner offers it back.
    public func clear(_ id: UUID) {
        guard let note = note(id), !note.isEmpty else { return }
        let before = note
        update(id, with: NSAttributedString(string: "", attributes: RichText.bodyAttributes))
        AppState.shared.showNotification(appName: "Notes", title: "Note cleared",
                                         message: "\(before.text.count) characters removed", actionTitle: "Undo") {
            let store = NotesStore.shared
            // Only restore over an empty note, never over something typed since.
            guard let current = store.note(id), current.isEmpty,
                  let index = store.notes.firstIndex(where: { $0.id == id }) else { return }
            store.notes[index].rtf = before.rtf
            store.notes[index].text = before.text
            store.notes[index].modified = Date()
            store.scheduleSave()
            store.schedulePush(id)
        }
    }

    /// Finder › Services › Add to Tama Notes: onto the latest note.
    public func append(_ text: String) {
        guard let latest else {
            create(text)
            return
        }
        let attributed = NSMutableAttributedString(attributedString: RichText.attributed(from: latest.rtf))
        let separator = latest.text.isEmpty ? "" : (latest.text.hasSuffix("\n") ? "\n" : "\n\n")
        attributed.append(NSAttributedString(string: separator + text, attributes: RichText.bodyAttributes))
        update(latest.id, with: attributed)
    }

    // MARK: Apple Notes

    private func schedulePush(_ id: UUID) {
        guard NotesSettings.shared.appleSync else { return }
        pushWork[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pushWork[id] = nil
            self?.push(id)
        }
        pushWork[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func push(_ id: UUID) {
        guard let note = note(id), !note.isEmpty else { return }
        let html = RichText.html(from: RichText.attributed(from: note.rtf))
        let existing = note.appleNoteID ?? ""
        syncStatus = .syncing
        Task.detached(priority: .utility) {
            let result = AppleNotesScript.run(AppleNotesScript.push, arguments: [existing, html])
            await MainActor.run { NotesStore.shared.finishPush(id, result: result) }
        }
    }

    private func finishPush(_ id: UUID, result: AppleNotesScript.Result) {
        switch result {
        case let .success(output):
            let parts = output.components(separatedBy: AppleNotesScript.unit)
            if let index = notes.firstIndex(where: { $0.id == id }), let appleID = parts.first, !appleID.isEmpty {
                notes[index].appleNoteID = appleID
                if parts.count > 1, let delta = Double(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
                    notes[index].appleModified = Date().addingTimeInterval(delta)
                }
                scheduleSave()
            }
            syncStatus = .idle
        case let .failure(status):
            syncStatus = status
        }
    }

    private func deleteFromAppleNotes(_ appleID: String) {
        Task.detached(priority: .utility) {
            _ = AppleNotesScript.run(AppleNotesScript.delete, arguments: [appleID])
        }
    }

    /// Reads the Tama folder back: changes made in Apple Notes win when
    /// they're newer, notes made there are imported, and ours that were never
    /// pushed go up.
    public func pullFromAppleNotes() {
        guard NotesSettings.shared.appleSync, syncStatus != .syncing else { return }
        syncStatus = .syncing
        Task.detached(priority: .utility) {
            let result = AppleNotesScript.run(AppleNotesScript.pull, arguments: [])
            await MainActor.run { NotesStore.shared.merge(result) }
        }
    }

    private func merge(_ result: AppleNotesScript.Result) {
        guard case let .success(output) = result else {
            if case let .failure(status) = result { syncStatus = status }
            return
        }
        var seen = Set<String>()
        for record in output.components(separatedBy: AppleNotesScript.record) where !record.isEmpty {
            let fields = record.components(separatedBy: AppleNotesScript.unit)
            guard fields.count >= 3 else { continue }
            let appleID = fields[0]
            let modified = Date().addingTimeInterval(Double(fields[1].trimmingCharacters(in: .whitespaces)) ?? 0)
            let html = fields[2...].joined(separator: AppleNotesScript.unit)
            seen.insert(appleID)
            if let index = notes.firstIndex(where: { $0.appleNoteID == appleID }) {
                let known = notes[index].appleModified ?? .distantPast
                // Ours has unsent edits: they're pushed next and win.
                guard modified.timeIntervalSince(known) > 2, pushWork[notes[index].id] == nil else { continue }
                let attributed = RichText.attributed(fromHTML: html)
                notes[index].rtf = RichText.rtf(attributed)
                notes[index].text = attributed.string
                notes[index].modified = modified
                notes[index].appleModified = modified
            } else {
                let attributed = RichText.attributed(fromHTML: html)
                var note = Self.make(from: attributed)
                note.appleNoteID = appleID
                note.appleModified = modified
                note.modified = modified
                note.created = modified
                notes.append(note)
            }
        }
        // Deleted in Apple Notes: ours stays, and goes up again on its next edit.
        for index in notes.indices where notes[index].appleNoteID.map({ !seen.contains($0) }) ?? false {
            notes[index].appleNoteID = nil
            notes[index].appleModified = nil
        }
        scheduleSave()
        syncStatus = .idle
        for note in notes where note.appleNoteID == nil && !note.isEmpty { schedulePush(note.id) }
    }
}

// MARK: - AppleScript

/// The scripts that talk to Notes, run with `osascript` off the main thread.
/// Values travel as arguments, never spliced into the script.
enum AppleNotesScript {
    enum Result: Sendable {
        case success(String)
        case failure(NotesStore.SyncStatus)
    }

    static let unit = "\u{1F}"
    static let record = "\u{1E}"

    private static let folder = """
        set acct to default account
        if not (exists folder "Tama" of acct) then make new folder at acct with properties {name:"Tama"}
        set theFolder to folder "Tama" of acct
        """

    static let push = """
        on run argv
            set noteID to item 1 of argv
            set theBody to item 2 of argv
            tell application "Notes"
                \(folder)
                set theNote to missing value
                if noteID is not "" then
                    try
                        set theNote to note id noteID
                        set body of theNote to theBody
                    on error
                        set theNote to missing value
                    end try
                end if
                if theNote is missing value then set theNote to make new note at theFolder with properties {body:theBody}
                set delta to (modification date of theNote) - (current date)
                return (id of theNote) & (ASCII character 31) & (delta as text)
            end tell
        end run
        """

    static let pull = """
        on run argv
            set out to ""
            tell application "Notes"
                \(folder)
                repeat with theNote in notes of theFolder
                    set delta to (modification date of theNote) - (current date)
                    set out to out & (id of theNote) & (ASCII character 31) & (delta as text) & (ASCII character 31) & (body of theNote) & (ASCII character 30)
                end repeat
            end tell
            return out
        end run
        """

    static let delete = """
        on run argv
            tell application "Notes"
                try
                    delete note id (item 1 of argv)
                end try
            end tell
        end run
        """

    nonisolated static func run(_ script: String, arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script] + arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            return .failure(.unreachable(error.localizedDescription))
        }
        // Both pipes are drained at once: reading stdout to the end first
        // would deadlock if osascript filled the stderr pipe buffer meanwhile.
        let errorBox = PipeDataBox()
        let errorHandle = errors.fileHandleForReading
        let drained = DispatchGroup()
        drained.enter()
        DispatchQueue.global(qos: .utility).async {
            errorBox.data = errorHandle.readDataToEndOfFile()
            drained.leave()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        drained.wait()
        let errorData = errorBox.data
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // -1743: not allowed to send Apple Events; -600/-609: Notes not running / connection lost.
            if message.contains("-1743") || message.contains("-600") || message.contains("-609") || message.contains("-1728") {
                return .failure(.unreachable(message))
            }
            return .failure(.scriptFailed(message))
        }
        var text = String(data: data, encoding: .utf8) ?? ""
        if text.hasSuffix("\n") { text.removeLast() }
        return .success(text)
    }
}

/// Carries stderr's bytes back from the thread that drains it; written once
/// before `DispatchGroup.leave`, read after `wait`, so never concurrently.
private final class PipeDataBox: @unchecked Sendable {
    var data = Data()
}
