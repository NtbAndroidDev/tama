import AppKit
import Combine

/// Agents droplet: follows Claude Code (through optional hooks), Codex
/// (its session logs) and Cursor (its local state database, best effort),
/// and shows the one at work in the notch.
@MainActor
public final class AgentActivityService: ObservableObject {
    public static let shared = AgentActivityService()

    /// Newest first.
    @Published public private(set) var sessions: [AgentSession] = []
    @Published public private(set) var claudeHooksInstalled = false
    @Published public private(set) var codexAvailable = false
    @Published public private(set) var cursorAvailable = false
    @Published public private(set) var lastError: String?

    private var running = false
    private var claudeSource: DispatchSourceFileSystemObject?
    private var claudeOffset: UInt64 = 0
    /// Bumped when the watch restarts, so a read begun before it can't move
    /// the offset it reset.
    private var claudeGeneration = 0
    private var claudeBusy = false
    private var claudePending = false
    private var pollTimer: Timer?
    private var codexFile: URL?
    private var codexOffset: UInt64 = 0
    private var codexSession: AgentSession?
    private var codexBusy = false
    private var cursorStamp: Date?
    private var cursorBusy = false
    private let background = DispatchQueue(label: "app.tama.agents", qos: .utility)

    private init() {}

    private var isEnabled: Bool {
        AppState.shared.droplets.first { $0.id == "agents" }?.isEnabled ?? false
    }

    public func sync() {
        if isEnabled { start() } else { stop() }
    }

    public func start() {
        refreshHookStatus()
        guard !running else { return }
        running = true
        watchClaude()
        // The timer itself is `syncPolling`'s to own: switching the Droplet on
        // while the screen is off must not start it polling into the dark.
        syncPolling()
    }

    public func stop() {
        running = false
        claudeSource?.cancel()
        claudeSource = nil
        pollTimer?.invalidate()
        pollTimer = nil
        sessions.removeAll()
        LiveActivityCenter.shared.end("agents")
    }

    /// Holds the two-second poll while the screen is off. Its only output is a
    /// Live Activity in the notch, which nobody can see then — and it is the
    /// busiest thing Tama does at rest, reading each agent's log and Cursor's
    /// database every tick. Unlike `stop()` this keeps the sessions it has
    /// found, so the notch comes back showing what it showed before.
    public func syncPolling() {
        guard running else { return }
        if PowerStateService.shared.isDormant {
            pollTimer?.invalidate()
            pollTimer = nil
        } else if pollTimer == nil {
            let timer = Timer(timeInterval: 2, repeats: true) { _ in
                MainActor.assumeIsolated { AgentActivityService.shared.poll() }
            }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
            poll()
        }
    }

    // MARK: Claude Code

    public func refreshHookStatus() {
        claudeHooksInstalled = (try? ClaudeHooks.readSettings()).map(ClaudeHooks.isInstalled) ?? false
    }

    /// Shows exactly what will be added to ~/.claude/settings.json and
    /// writes it only on confirmation (keeping a backup).
    public func installClaudeHooks() {
        let current: [String: Any]
        do {
            current = try ClaudeHooks.readSettings()
        } catch {
            lastError = "~/.claude/settings.json isn't valid JSON, so Tama won't touch it. Fix it and try again."
            return
        }
        let updated = ClaudeHooks.adding(to: current)
        let added = ClaudeHooks.adding(to: [:])
        let alert = NSAlert()
        alert.messageText = "Add Tama's hooks to Claude Code?"
        alert.informativeText = """
        Tama will add these hooks to ~/.claude/settings.json (your other settings and hooks stay as they are; \
        the old file is kept as settings.json.tama-backup). Each hook only appends the event Claude reports \
        — prompt, tool and command, status — to \(ClaudeHooks.eventsURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")), \
        which Tama reads. They never block or answer Claude. New Claude sessions pick them up.
        """
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 520, height: 220)
        if let text = scroll.documentView as? NSTextView {
            text.string = ClaudeHooks.json(added)
            text.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
            text.isEditable = false
        }
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Install Hooks")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.createDirectory(at: ClaudeHooks.eventsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ClaudeHooks.write(updated)
            lastError = nil
            AppState.shared.showNotification(appName: "Agents", title: "Claude Code hooks installed",
                                             message: "Start a new Claude session to see it in the notch.", icon: "sparkles")
        } catch {
            lastError = "Couldn't write ~/.claude/settings.json: \(error.localizedDescription)"
        }
        refreshHookStatus()
        watchClaude()
    }

    public func removeClaudeHooks() {
        guard let current = try? ClaudeHooks.readSettings() else { return }
        do {
            try ClaudeHooks.write(ClaudeHooks.removing(from: current))
            lastError = nil
        } catch {
            lastError = "Couldn't write ~/.claude/settings.json: \(error.localizedDescription)"
        }
        refreshHookStatus()
    }

    private func watchClaude() {
        claudeSource?.cancel()
        claudeSource = nil
        guard running, AppState.shared.agentsClaude else { return }
        let url = ClaudeHooks.eventsURL
        let fm = FileManager.default
        // Nothing to follow until the hooks are in (or have written before).
        guard claudeHooksInstalled || fm.fileExists(atPath: url.path) else { return }
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        // Old events are history, not news.
        claudeOffset = (try? fm.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        claudeGeneration += 1
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename],
                                                               queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated {
                let service = AgentActivityService.shared
                if let events = service.claudeSource?.data, events.contains(.delete) || events.contains(.rename) {
                    service.watchClaude()
                } else {
                    service.readClaudeEvents()
                }
            }
        }
        source.setCancelHandler { close(fd) }
        claudeSource = source
        source.resume()
    }

    /// Reads what the hooks appended on the background queue (the file I/O),
    /// then applies it here; a burst of events while a read is out folds into
    /// one more read.
    private func readClaudeEvents() {
        guard !claudeBusy else {
            claudePending = true
            return
        }
        claudeBusy = true
        let offset = claudeOffset
        let generation = claudeGeneration
        background.async {
            let chunk = Self.readClaudeChunk(from: offset)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    AgentActivityService.shared.applyClaude(chunk, generation: generation)
                }
            }
        }
    }

    private struct ClaudeChunk: Sendable {
        var lines: [Data] = []
        /// Where the next read starts; nil leaves the offset as it was.
        var nextOffset: UInt64?
    }

    nonisolated private static func readClaudeChunk(from start: UInt64) -> ClaudeChunk {
        let url = ClaudeHooks.eventsURL
        guard let handle = try? FileHandle(forReadingFrom: url) else { return ClaudeChunk() }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        var offset = start
        if size < offset { offset = 0 }
        var chunk = ClaudeChunk(nextOffset: offset)
        try? handle.seek(toOffset: offset)
        if let data = try? handle.readToEnd(), !data.isEmpty,
           // Only whole lines; a half-written one waits for the next event.
           let lastNewline = data.lastIndex(of: 0x0a) {
            let complete = data[data.startIndex...lastNewline]
            chunk.nextOffset = offset + UInt64(complete.count)
            chunk.lines = complete.split(separator: 0x0a).map { Data($0) }
        }
        // Keep the file small; Tama only ever needs the newest events.
        if size > 2_000_000, let writer = try? FileHandle(forWritingTo: url) {
            try? writer.truncate(atOffset: 0)
            try? writer.close()
            chunk.nextOffset = 0
        }
        return chunk
    }

    private func applyClaude(_ chunk: ClaudeChunk, generation: Int) {
        claudeBusy = false
        defer {
            if claudePending {
                claudePending = false
                readClaudeEvents()
            }
        }
        guard running, generation == claudeGeneration else { return }
        if let next = chunk.nextOffset { claudeOffset = next }
        for line in chunk.lines {
            guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            let sessionID = event["session_id"] as? String ?? "claude"
            var session = sessions.first { $0.kind == .claude && $0.sessionID == sessionID }
                ?? AgentSession(kind: .claude, sessionID: sessionID)
            let wasWorking = session.activity.isWorking
            guard AgentParsers.applyClaude(event, to: &session) else {
                sessions.removeAll { $0.id == session.id }
                continue
            }
            let name = event["hook_event_name"] as? String
            if name == "Stop" || name == "PostToolUse" || name == "SubagentStop", let path = session.transcriptPath {
                fetchClaudeReply(for: session.id, transcript: path)
            }
            upsert(session, wasWorking: wasWorking)
        }
    }

    private func fetchClaudeReply(for id: String, transcript: String) {
        background.async {
            let reply = AgentParsers.lastClaudeReply(transcriptAt: transcript)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let service = AgentActivityService.shared
                    guard let reply, let index = service.sessions.firstIndex(where: { $0.id == id }) else { return }
                    service.sessions[index].assistantText = reply
                }
            }
        }
    }

    // MARK: Polling (Codex, Cursor, staleness)

    private func poll() {
        guard running else { return }
        if AppState.shared.agentsCodex { pollCodex() } else { removeSessions(of: .codex) }
        if AppState.shared.agentsCursor { pollCursor() } else { removeSessions(of: .cursor) }
        if !AppState.shared.agentsClaude { removeSessions(of: .claude) }
        // A session that went quiet: finished ones fade after a while, and a
        // "working" one with no news for five minutes has probably crashed.
        let now = Date()
        var changed = false
        for index in sessions.indices.reversed() {
            let age = now.timeIntervalSince(sessions[index].updatedAt)
            if sessions[index].activity.isWorking, age > 300 {
                sessions[index].activity = .idle
                changed = true
            } else if !sessions[index].activity.isWorking, age > 1800 {
                sessions.remove(at: index)
                changed = true
            }
        }
        if changed { publishActivity() }
    }

    /// Every write to `sessions` republishes it, and this runs every two seconds.
    private func removeSessions(of kind: AgentKind) {
        guard sessions.contains(where: { $0.kind == kind }) else { return }
        sessions.removeAll { $0.kind == kind }
    }

    nonisolated private static var codexRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    /// The newest rollout log from today or yesterday (Codex writes one per
    /// session under sessions/YYYY/MM/DD).
    nonisolated private static func newestCodexLog() -> (URL, Date)? {
        let fm = FileManager.default
        let calendar = Calendar(identifier: .gregorian)
        var best: (URL, Date)?
        for dayOffset in [0, -1] {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: Date()) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            let folder = codexRoot.appendingPathComponent(String(format: "%04d/%02d/%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0))
            guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if best == nil || date > best!.1 { best = (file, date) }
            }
        }
        return best
    }

    /// The directory walk and log read run on the background queue; only the
    /// parsed lines come back to the main actor.
    private func pollCodex() {
        guard !codexBusy else { return }
        codexBusy = true
        let knownFile = codexFile
        let offset = codexOffset
        background.async {
            let read = Self.readCodex(knownFile: knownFile, offset: offset)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { AgentActivityService.shared.applyCodex(read) }
            }
        }
    }

    private struct CodexRead: Sendable {
        var available = false
        var file: URL?
        var modified = Date.distantPast
        /// Only a log touched in the last ten minutes is a live session.
        var isLive = false
        /// Where this read started (the tail, for a log seen for the first
        /// time) and where the next one picks up.
        var start: UInt64 = 0
        var end: UInt64 = 0
        var lines: [String] = []
    }

    nonisolated private static func readCodex(knownFile: URL?, offset: UInt64) -> CodexRead {
        var read = CodexRead()
        read.available = FileManager.default.fileExists(atPath: codexRoot.path)
        guard read.available, let (file, modified) = newestCodexLog() else { return read }
        read.file = file
        read.modified = modified
        read.isLive = Date().timeIntervalSince(modified) < 600
        guard read.isLive else { return read }
        var start = offset
        if knownFile != file {
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? UInt64) ?? 0
            // Pick up the story so far from the log's tail.
            start = size > 256 * 1024 ? size - 256 * 1024 : 0
        }
        read.start = start
        read.end = start
        guard let handle = try? FileHandle(forReadingFrom: file) else { return read }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        guard size > start else { return read }
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), let lastNewline = data.lastIndex(of: 0x0a) else { return read }
        let complete = data[data.startIndex...lastNewline]
        read.end = start + UInt64(complete.count)
        read.lines = String(decoding: complete, as: UTF8.self).split(separator: "\n").map(String.init)
        return read
    }

    private func applyCodex(_ read: CodexRead) {
        codexBusy = false
        guard running, AppState.shared.agentsCodex else { return }
        if codexAvailable != read.available { codexAvailable = read.available }
        guard read.available, let file = read.file else { return }
        guard read.isLive else {
            if codexSession != nil {
                removeSessions(of: .codex)
                codexSession = nil
                codexFile = nil
                publishActivity()
            }
            return
        }
        if codexFile != file {
            codexFile = file
            codexOffset = read.start
            codexSession = AgentSession(kind: .codex, sessionID: file.deletingPathExtension().lastPathComponent)
        }
        guard var session = codexSession, read.end > read.start else { return }
        let skipFirst = read.start > 0 && sessions.first(where: { $0.kind == .codex }) == nil
        codexOffset = read.end
        let wasWorking = sessions.first { $0.id == session.id }?.activity.isWorking ?? false
        var lines = read.lines
        // Starting mid-file, the first line is probably cut.
        if skipFirst, !lines.isEmpty { lines.removeFirst() }
        for line in lines { AgentParsers.applyCodex(line: Substring(line), to: &session) }
        session.updatedAt = read.modified
        codexSession = session
        upsert(session, wasWorking: wasWorking)
    }

    private static let cursorBundleID = "com.todesktop.230313mzl4w4u92"

    private static var cursorDatabase: String {
        NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    }

    /// Cursor keeps its chats ("composers") in a SQLite key-value table; the
    /// newest one's name and status is what we can honestly read. Only while
    /// Cursor runs, and only when its database changed.
    private func pollCursor() {
        let path = Self.cursorDatabase
        let available = FileManager.default.fileExists(atPath: path)
        if cursorAvailable != available { cursorAvailable = available }
        let isRunning = available && NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == Self.cursorBundleID }
        guard available, isRunning else {
            if sessions.contains(where: { $0.kind == .cursor }) {
                sessions.removeAll { $0.kind == .cursor }
                publishActivity()
            }
            return
        }
        let wal = FileManager.default.fileExists(atPath: path + "-wal") ? path + "-wal" : path
        let stamp = (try? FileManager.default.attributesOfItem(atPath: wal)[.modificationDate] as? Date) ?? nil
        guard stamp != cursorStamp, !cursorBusy else { return }
        cursorStamp = stamp
        cursorBusy = true
        background.async {
            var result: (id: String, name: String, status: String, updated: Double)?
            if let reader = try? SQLiteReader(path: path) {
                let rows = (try? reader.query("""
                    SELECT json_extract(value, '$.composerId'), json_extract(value, '$.name'),
                           json_extract(value, '$.status'), json_extract(value, '$.lastUpdatedAt')
                    FROM cursorDiskKV WHERE key LIKE 'composerData:%' AND json_valid(value)
                    ORDER BY json_extract(value, '$.lastUpdatedAt') DESC LIMIT 1
                    """)) ?? []
                if let row = rows.first, row.count >= 4 {
                    result = (row[0].string ?? "cursor", row[1].string ?? "", row[2].string ?? "", row[3].double ?? 0)
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { AgentActivityService.shared.applyCursor(result) }
            }
        }
    }

    private func applyCursor(_ result: (id: String, name: String, status: String, updated: Double)?) {
        cursorBusy = false
        guard let result else { return }
        let updated = Date(timeIntervalSince1970: result.updated / 1000)
        guard Date().timeIntervalSince(updated) < 600 else { return }
        var session = sessions.first { $0.kind == .cursor && $0.sessionID == result.id }
            ?? AgentSession(kind: .cursor, sessionID: result.id)
        let wasWorking = session.activity.isWorking
        session.task = result.name
        session.activity = result.status == "generating" ? .thinking : (wasWorking ? .finished : session.activity)
        session.updatedAt = updated
        sessions.removeAll { $0.kind == .cursor && $0.sessionID != result.id }
        upsert(session, wasWorking: wasWorking)
    }

    // MARK: Publishing

    private func upsert(_ session: AgentSession, wasWorking: Bool) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        sessions.sort { $0.updatedAt > $1.updatedAt }
        if wasWorking, !session.activity.isWorking {
            announce(session)
        }
        publishActivity()
    }

    /// "Background task completed" (or failed, or waiting on you).
    private func announce(_ session: AgentSession) {
        guard AppState.shared.agentsNotifyDone else { return }
        let title: String
        switch session.activity {
        case .finished: title = "\(session.kind.name) finished"
        case .failed: title = "\(session.kind.name) stopped"
        case .waiting: title = "\(session.kind.name) needs you"
        default: return
        }
        let message = session.assistantText.isEmpty ? (session.task.isEmpty ? session.activity.line : session.task)
            : AgentParsers.oneLine(session.assistantText)
        AppState.shared.showNotification(appName: session.project.isEmpty ? "Agents" : session.project, title: title,
                                         message: message, icon: session.kind.symbol, duration: 5)
    }

    /// The glyph and spinner in the resting notch while an agent works.
    private func publishActivity() {
        guard AppState.shared.agentsShowInNotch, let working = sessions.first(where: { $0.activity.isWorking }) else {
            LiveActivityCenter.shared.end("agents")
            return
        }
        LiveActivityCenter.shared.post(LiveActivity(
            id: "agents", icon: working.kind.symbol, tint: working.kind.tint, trailing: .spinner,
            priority: .ambient, label: "\(working.kind.name): \(working.activity.line)"
        ))
    }

    /// Settings changes (which agents, show in notch).
    public func settingsChanged() {
        guard running else { return }
        watchClaude()
        poll()
        publishActivity()
    }
}
