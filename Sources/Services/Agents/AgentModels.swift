import SwiftUI

/// A coding agent Tama can follow.
public enum AgentKind: String, CaseIterable, Identifiable, Sendable {
    case claude, codex, cursor

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }

    /// Our own glyphs (SF Symbols), not the vendors' marks.
    public var symbol: String {
        switch self {
        case .claude: "asterisk"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .cursor: "cursorarrow.rays"
        }
    }

    public var tint: Color {
        switch self {
        case .claude: Color(red: 0.87, green: 0.52, blue: 0.38)
        case .codex: Color(red: 0.55, green: 0.80, blue: 0.95)
        case .cursor: Color(red: 0.80, green: 0.80, blue: 0.86)
        }
    }
}

/// What an agent is doing right now.
public enum AgentActivity: Equatable, Sendable {
    case idle
    /// "Working on your task"
    case thinking
    /// A tool call: "Running a command" (Bash), editing a file, searching…
    case tool(name: String, detail: String)
    /// It stopped to ask you something (permission, input).
    case waiting(String)
    case finished
    case failed(String)

    public var isWorking: Bool {
        switch self {
        case .thinking, .tool: true
        default: false
        }
    }

    /// One line for the card: "Running npm test", "Editing Layout.swift".
    public var line: String {
        switch self {
        case .idle: "Idle"
        case .thinking: "Working on your task"
        case let .tool(name, detail):
            switch name {
            case "Bash", "shell", "exec", "local_shell", "exec_command":
                detail.isEmpty ? "Running a command" : "Running \(detail)"
            case "BashOutput": "Waiting on shell"
            case "KillShell", "KillBash": "Stopping a shell"
            case "Edit", "MultiEdit", "Write", "NotebookEdit", "apply_patch":
                detail.isEmpty ? "Editing files" : "Editing \(detail)"
            case "Read": detail.isEmpty ? "Reading files" : "Reading \(detail)"
            case "Grep", "Glob": detail.isEmpty ? "Searching" : "Searching \(detail)"
            case "WebFetch", "WebSearch": detail.isEmpty ? "Browsing the web" : "Looking up \(detail)"
            case "Task", "Agent": detail.isEmpty ? "Running a subagent" : detail
            case "write_stdin": "Writing to terminal"
            default: detail.isEmpty ? name : "\(name) \(detail)"
            }
        case let .waiting(message): message.isEmpty ? "Waiting for you" : message
        case .finished: "Background task completed"
        case let .failed(message): message.isEmpty ? "Background task failed" : message
        }
    }
}

public struct AgentSession: Identifiable, Equatable, Sendable {
    public var kind: AgentKind
    public var sessionID: String
    public var project: String = ""
    /// The last thing you asked it.
    public var task: String = ""
    public var activity: AgentActivity = .idle
    /// Its latest reply text.
    public var assistantText: String = ""
    public var updatedAt = Date()
    /// Where Claude keeps the conversation, for its latest reply.
    public var transcriptPath: String?

    public var id: String { "\(kind.rawValue):\(sessionID)" }

    public init(kind: AgentKind, sessionID: String) {
        self.kind = kind
        self.sessionID = sessionID
    }
}
