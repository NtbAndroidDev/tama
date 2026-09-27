import Foundation

/// Turns the agents' own records into `AgentSession` updates. Pure, so the
/// formats are covered by tests.
enum AgentParsers {
    // MARK: Claude Code hooks

    /// Applies one Claude Code hook event (the JSON Claude pipes to a hook
    /// command). Returns false for events that end the session.
    @discardableResult
    static func applyClaude(_ event: [String: Any], to session: inout AgentSession) -> Bool {
        let name = event["hook_event_name"] as? String ?? ""
        if let cwd = event["cwd"] as? String, !cwd.isEmpty { session.project = (cwd as NSString).lastPathComponent }
        if let transcript = event["transcript_path"] as? String, !transcript.isEmpty { session.transcriptPath = transcript }
        switch name {
        case "SessionStart":
            session.activity = .idle
        case "UserPromptSubmit":
            if let prompt = event["prompt"] as? String { session.task = oneLine(prompt) }
            session.activity = .thinking
            session.assistantText = ""
        case "PreToolUse":
            let tool = event["tool_name"] as? String ?? "Tool"
            let input = event["tool_input"] as? [String: Any] ?? [:]
            session.activity = .tool(name: tool, detail: detail(forTool: tool, input: input))
        case "PostToolUse", "SubagentStop", "PreCompact":
            session.activity = .thinking
        case "Notification":
            let message = event["message"] as? String ?? ""
            session.activity = .waiting(oneLine(message))
        case "Stop":
            session.activity = .finished
        case "SessionEnd":
            return false
        default:
            break
        }
        session.updatedAt = Date()
        return true
    }

    /// What a tool call is about, short: the command, a file name, a pattern.
    static func detail(forTool tool: String, input: [String: Any]) -> String {
        func string(_ key: String) -> String? {
            (input[key] as? String).map(oneLine).flatMap { $0.isEmpty ? nil : $0 }
        }
        switch tool {
        case "Bash":
            return string("command") ?? string("description") ?? ""
        case "Edit", "MultiEdit", "Write", "Read", "NotebookEdit":
            return (string("file_path") ?? string("notebook_path")).map { ($0 as NSString).lastPathComponent } ?? ""
        case "Grep", "Glob":
            return string("pattern") ?? ""
        case "WebFetch":
            return string("url").flatMap { URL(string: $0)?.host } ?? ""
        case "WebSearch":
            return string("query") ?? ""
        case "Task", "Agent":
            return string("description") ?? ""
        default:
            return string("command") ?? string("description") ?? ""
        }
    }

    /// The newest assistant text in a Claude transcript (JSONL), reading
    /// only the file's tail.
    static func lastClaudeReply(transcriptAt path: String, tailBytes: Int = 96 * 1024) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        for line in lines.reversed() {
            guard line.contains("\"assistant\""),
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["type"] as? String == "assistant",
                  let message = object["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { continue }
            let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return nil
    }

    // MARK: Codex

    /// Applies one line of a Codex rollout log (~/.codex/sessions/…/rollout-*.jsonl).
    static func applyCodex(line: Substring, to session: inout AgentSession) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return }
        let payload = object["payload"] as? [String: Any] ?? object
        let outer = object["type"] as? String ?? ""
        let type = payload["type"] as? String ?? ""
        var changed = true
        switch (outer, type) {
        case ("session_meta", _):
            if let cwd = payload["cwd"] as? String { session.project = (cwd as NSString).lastPathComponent }
            if let id = payload["id"] as? String, session.sessionID.isEmpty { session.sessionID = id }
            changed = false
        case (_, "task_started"):
            session.activity = .thinking
        case (_, "task_complete"):
            session.activity = .finished
            if let last = payload["last_agent_message"] as? String, !last.isEmpty { session.assistantText = last }
        case (_, "turn_aborted"):
            session.activity = .failed("Stopped")
        case (_, "user_message"):
            if let message = payload["message"] as? String, !isCodexBoilerplate(message) {
                session.task = oneLine(message)
                session.activity = .thinking
            }
        case (_, "agent_message"):
            if let message = payload["message"] as? String { session.assistantText = message }
        case (_, "exec_command_begin"):
            let command = (payload["command"] as? [String]).map(codexCommand) ?? ""
            session.activity = .tool(name: "exec_command", detail: command)
        case (_, "exec_command_end"), (_, "function_call_output"), (_, "reasoning"), (_, "agent_reasoning"),
             (_, "custom_tool_call_output"):
            if session.activity != .finished { session.activity = .thinking }
        case (_, "function_call"), (_, "custom_tool_call"):
            let name = payload["name"] as? String ?? "tool"
            var detail = ""
            if let arguments = payload["arguments"] as? String,
               let parsed = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any] {
                if let command = parsed["command"] as? [String] {
                    detail = codexCommand(command)
                } else if let command = parsed["cmd"] as? String ?? parsed["command"] as? String {
                    detail = oneLine(command)
                }
            }
            session.activity = .tool(name: name, detail: detail)
        case (_, "message"):
            let role = payload["role"] as? String
            let content = payload["content"] as? [[String: Any]] ?? []
            let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if role == "assistant", !text.isEmpty {
                session.assistantText = text
            } else if role == "user", !text.isEmpty, !isCodexBoilerplate(text) {
                session.task = oneLine(text)
            } else {
                changed = false
            }
        default:
            changed = false
        }
        if changed { session.updatedAt = Date() }
    }

    /// ["bash", "-lc", "npm test"] → "npm test".
    static func codexCommand(_ parts: [String]) -> String {
        if parts.count >= 3, ["bash", "zsh", "sh", "/bin/bash", "/bin/zsh", "/bin/sh"].contains(parts[0]),
           parts[1].hasPrefix("-") {
            return oneLine(parts[2])
        }
        return oneLine(parts.joined(separator: " "))
    }

    private static func isCodexBoilerplate(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("<environment_context>") || trimmed.hasPrefix("<user_instructions>")
            || trimmed.hasPrefix("# AGENTS.md") || trimmed.hasPrefix("<INSTRUCTIONS>")
    }

    static func oneLine(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count > 240 ? String(flat.prefix(240)) + "…" : flat
    }
}

/// Adds Tama's hooks to Claude Code's settings (~/.claude/settings.json),
/// only when the user asks, after showing what changes. Each hook appends
/// the event Claude sends (JSON on stdin) as one line to a file Tama
/// watches; it never blocks Claude and never answers for you.
enum ClaudeHooks {
    static let marker = "tama-agent-hook"
    static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification",
                         "Stop", "SubagentStop", "SessionEnd"]
    /// Tool events take a matcher; the rest don't.
    static let matcherEvents: Set<String> = ["PreToolUse", "PostToolUse"]

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    static var eventsURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Tama/Agents/claude-events.jsonl")
    }

    /// The shell command each hook runs. `tr` folds the event onto one line
    /// (JSON strings never hold raw newlines); `|| true` keeps Claude going
    /// even if the write fails.
    static var command: String {
        let file = eventsURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "$HOME")
        let folder = (file as NSString).deletingLastPathComponent
        return "mkdir -p \"\(folder)\" && { tr -d '\\n'; echo; } >> \"\(file)\" || true # \(marker)"
    }

    static func isOurs(_ hook: Any) -> Bool {
        ((hook as? [String: Any])?["command"] as? String)?.contains(marker) ?? false
    }

    /// `settings` with Tama's hooks added (replacing older copies of them);
    /// everything else, the user's own hooks included, is left as it was.
    static func adding(to settings: [String: Any]) -> [String: Any] {
        var settings = removing(from: settings)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        let hook: [String: Any] = ["type": "command", "command": command, "timeout": 5]
        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            var group: [String: Any] = ["hooks": [hook]]
            if matcherEvents.contains(event) { group["matcher"] = "*" }
            groups.append(group)
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        return settings
    }

    /// `settings` without Tama's hooks; groups and events left empty go too.
    static func removing(from settings: [String: Any]) -> [String: Any] {
        var settings = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept: [[String: Any]] = groups.compactMap { group in
                guard let list = group["hooks"] as? [Any] else { return group }
                let remaining = list.filter { !isOurs($0) }
                if remaining.isEmpty, !list.isEmpty { return nil }
                var copy = group
                copy["hooks"] = remaining
                return copy
            }
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        if hooks.isEmpty { settings.removeValue(forKey: "hooks") } else { settings["hooks"] = hooks }
        return settings
    }

    static func isInstalled(in settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            (value as? [[String: Any]])?.contains { ($0["hooks"] as? [Any])?.contains(where: isOurs) ?? false } ?? false
        }
    }

    static func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        guard !data.isEmpty else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return object
    }

    static func json(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Writes `settings`, keeping a copy of the previous file beside it.
    static func write(_ settings: [String: Any]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: settingsURL.path) {
            let backup = settingsURL.deletingLastPathComponent().appendingPathComponent("settings.json.tama-backup")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: settingsURL, to: backup)
        }
        try Data(json(settings).utf8).write(to: settingsURL, options: .atomic)
    }
}
