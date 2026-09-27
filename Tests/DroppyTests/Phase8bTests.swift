import Foundation
import Testing
@testable import Droppy

/// TermiNotch's screen model: the escape sequences shells and CLIs use.
@Suite struct TerminalScreenTests {
    private func text(_ screen: TerminalScreen, row: Int) -> String {
        TerminalScreen.text(of: screen.grid[row])
    }

    @Test func printsAndWrapsLines() {
        let screen = TerminalScreen(columns: 5, rows: 3)
        screen.feed("hello world\r\nok")
        // Four lines on a three-row screen: "hello" scrolled off the top.
        #expect(TerminalScreen.text(of: screen.scrollback[0]) == "hello")
        #expect(text(screen, row: 0) == " worl")
        #expect(text(screen, row: 1) == "d")
        #expect(text(screen, row: 2) == "ok")
        #expect(screen.scrollback.count == 1)
        #expect(screen.plainText.hasSuffix("ok"))
    }

    @Test func colorsAndReset() {
        let screen = TerminalScreen(columns: 20, rows: 2)
        screen.feed("\u{1b}[1;32m$\u{1b}[0m ls \u{1b}[38;5;200mx\u{1b}[38;2;1;2;3my")
        let row = screen.grid[0]
        #expect(row[0].style.foreground == .ansi(2))
        #expect(row[0].style.bold)
        #expect(row[1].style == TerminalStyle())
        #expect(row[5].style.foreground == .palette(200))
        #expect(row[6].style.foreground == .rgb(1, 2, 3))
    }

    @Test func cursorMovementAndErase() {
        let screen = TerminalScreen(columns: 10, rows: 3)
        screen.feed("abcdef\u{1b}[3D\u{1b}[K")
        #expect(text(screen, row: 0) == "abc")
        screen.feed("\u{1b}[2;4HX")
        #expect(text(screen, row: 1) == "   X")
        screen.feed("\u{1b}[2J")
        #expect(text(screen, row: 0).isEmpty && text(screen, row: 1).isEmpty)
        screen.feed("\u{1b}[H12345\u{1b}[1G\u{1b}[2P")
        #expect(text(screen, row: 0) == "345")
    }

    @Test func carriageReturnOverwritesProgress() {
        let screen = TerminalScreen(columns: 20, rows: 2)
        screen.feed("10%\r55%\r100%")
        #expect(text(screen, row: 0) == "100%")
    }

    @Test func alternateScreenRestoresMain() {
        let screen = TerminalScreen(columns: 10, rows: 3)
        screen.feed("prompt$ ")
        screen.feed("\u{1b}[?1049h\u{1b}[Hvim here")
        #expect(screen.isAlternateScreen)
        #expect(text(screen, row: 0) == "vim here")
        screen.feed("\u{1b}[?1049l")
        #expect(!screen.isAlternateScreen)
        #expect(text(screen, row: 0) == "prompt$")
        #expect(screen.cursorX == 8)
    }

    @Test func answersCursorPositionReport() {
        let screen = TerminalScreen(columns: 10, rows: 5)
        screen.feed("\u{1b}[3;4H\u{1b}[6n")
        #expect(String(decoding: screen.takeResponses(), as: UTF8.self) == "\u{1b}[3;4R")
        #expect(screen.takeResponses().isEmpty)
    }

    @Test func utf8SplitAcrossChunks() {
        let screen = TerminalScreen(columns: 10, rows: 1)
        let bytes = Array("é✓".utf8)
        screen.feed(Data(bytes.prefix(1)))
        screen.feed(Data(bytes.dropFirst()))
        #expect(text(screen, row: 0) == "é✓")
    }

    @Test func oscTitleAndDirectory() {
        let screen = TerminalScreen(columns: 10, rows: 1)
        screen.feed("\u{1b}]0;build\u{07}\u{1b}]7;file://mac/Users/me/Code\u{1b}\\")
        #expect(screen.title == "build")
        #expect(screen.reportedDirectory == "/Users/me/Code")
        #expect(text(screen, row: 0).isEmpty)
    }

    @Test func resizeKeepsCursorLine() {
        let screen = TerminalScreen(columns: 10, rows: 4)
        screen.feed("a\r\nb\r\nc\r\nd")
        screen.resize(columns: 6, rows: 2)
        #expect(screen.rowCount == 2 && screen.columns == 6)
        #expect(text(screen, row: 1) == "d")
        #expect(screen.scrollback.count == 2)
    }

    @Test func applicationCursorMode() {
        let screen = TerminalScreen(columns: 10, rows: 1)
        screen.feed("\u{1b}[?1h\u{1b}[?2004h")
        #expect(screen.applicationCursorKeys)
        #expect(screen.bracketedPaste)
    }
}

@Suite struct AgentParserTests {
    @Test func claudeLifecycle() {
        var session = AgentSession(kind: .claude, sessionID: "s1")
        AgentParsers.applyClaude(["hook_event_name": "UserPromptSubmit", "prompt": "Fix the\nbuild", "cwd": "/Users/me/droppy"], to: &session)
        #expect(session.task == "Fix the build")
        #expect(session.project == "droppy")
        #expect(session.activity == .thinking)
        AgentParsers.applyClaude(["hook_event_name": "PreToolUse", "tool_name": "Bash",
                                  "tool_input": ["command": "swift build", "description": "Build"]], to: &session)
        #expect(session.activity == .tool(name: "Bash", detail: "swift build"))
        #expect(session.activity.line == "Running swift build")
        AgentParsers.applyClaude(["hook_event_name": "PreToolUse", "tool_name": "Edit",
                                  "tool_input": ["file_path": "/a/b/Layout.swift"]], to: &session)
        #expect(session.activity.line == "Editing Layout.swift")
        AgentParsers.applyClaude(["hook_event_name": "Stop"], to: &session)
        #expect(session.activity == .finished)
        #expect(!AgentParsers.applyClaude(["hook_event_name": "SessionEnd"], to: &session))
    }

    @Test func claudeTranscriptReply() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("droppy-transcript-\(UUID()).jsonl")
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"hi"}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"First"}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash"},{"type":"text","text":"Latest reply"}]}}"#,
        ]
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(AgentParsers.lastClaudeReply(transcriptAt: url.path) == "Latest reply")
    }

    @Test func codexRollout() {
        var session = AgentSession(kind: .codex, sessionID: "")
        let lines = [
            #"{"type":"session_meta","payload":{"id":"abc","cwd":"/Users/me/app"}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>x</environment_context>"}]}}"#,
            #"{"type":"event_msg","payload":{"type":"user_message","message":"Add tests"}}"#,
            #"{"type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{\"command\":[\"bash\",\"-lc\",\"npm test\"]}"}}"#,
        ]
        for line in lines { AgentParsers.applyCodex(line: Substring(line), to: &session) }
        #expect(session.sessionID == "abc")
        #expect(session.project == "app")
        #expect(session.task == "Add tests")
        #expect(session.activity.line == "Running npm test")
        AgentParsers.applyCodex(line: #"{"type":"event_msg","payload":{"type":"agent_message","message":"Done: 4 tests"}}"#, to: &session)
        AgentParsers.applyCodex(line: #"{"type":"event_msg","payload":{"type":"task_complete"}}"#, to: &session)
        #expect(session.assistantText == "Done: 4 tests")
        #expect(session.activity == .finished)
    }

    @Test func hooksMergeKeepsUserHooksAndIsIdempotent() {
        let user: [String: Any] = [
            "model": "opus",
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]],
        ]
        let once = ClaudeHooks.adding(to: user)
        let twice = ClaudeHooks.adding(to: once)
        #expect(ClaudeHooks.isInstalled(in: twice))
        #expect(twice["model"] as? String == "opus")
        let stop = (twice["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]] ?? []
        #expect(stop.count == 2) // the user's group and one of ours, not two
        let pre = (twice["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]] ?? []
        #expect(pre.first?["matcher"] as? String == "*")
        let removed = ClaudeHooks.removing(from: twice)
        #expect(!ClaudeHooks.isInstalled(in: removed))
        let hooks = removed["hooks"] as? [String: Any] ?? [:]
        #expect(Array(hooks.keys) == ["Stop"])
        #expect(ClaudeHooks.command.contains(ClaudeHooks.marker))
    }
}

@Suite struct NotificationHUDTests {
    @Test func parsesUsernotedRecord() throws {
        let plist: [String: Any] = [
            "app": "com.apple.ScriptEditor2",
            "req": ["titl": "Test", "subt": "Testing Droppy", "body": "Test message", "thre": "iMessage;-;+15551234567"],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let note = try #require(MirroredNotification.parse(id: 7, bundleID: nil, plist: data, deliveredAt: 700_000_000))
        #expect(note.bundleID == "com.apple.ScriptEditor2")
        #expect(note.title == "Test")
        #expect(note.preview == "Testing Droppy · Test message")
        #expect(note.date == Date(timeIntervalSinceReferenceDate: 700_000_000))
        #expect(note.replyKind == .none)
        let empty = try PropertyListSerialization.data(fromPropertyList: ["req": [:] as [String: Any]], format: .binary, options: 0)
        #expect(MirroredNotification.parse(id: 8, bundleID: "x", plist: empty, deliveredAt: nil) == nil)
    }

    @Test func messagesThreadTargets() {
        #expect(QuickReplyService.target(fromThread: "iMessage;-;+15551234567") == .chat("iMessage;-;+15551234567"))
        #expect(QuickReplyService.target(fromThread: "+1 (555) 123-4567") == .handle("+1 (555) 123-4567"))
        #expect(QuickReplyService.target(fromThread: "me@example.com") == .handle("me@example.com"))
        #expect(QuickReplyService.target(fromThread: "com.apple.something") == nil)
        #expect(QuickReplyService.target(fromThread: nil) == nil)
    }
}

@Suite struct MeetingDetectionTests {
    @Test func audioProcessOwners() {
        let running: Set<String> = ["com.apple.FaceTime"]
        #expect(MeetingApp.owner(ofAudioProcess: "us.zoom.xos", running: running)?.id == "zoom")
        #expect(MeetingApp.owner(ofAudioProcess: "com.microsoft.teams2.helper", running: running)?.id == "teams")
        #expect(MeetingApp.owner(ofAudioProcess: "com.apple.avconferenced", running: running)?.id == "facetime")
        #expect(MeetingApp.owner(ofAudioProcess: "com.apple.avconferenced", running: [])?.id == nil)
        #expect(MeetingApp.owner(ofAudioProcess: "net.whatsapp.WhatsApp", running: running)?.id == "whatsapp")
        #expect(MeetingApp.owner(ofAudioProcess: "com.google.Chrome.helper", running: running)?.id == "meet")
        #expect(MeetingApp.owner(ofAudioProcess: "com.apple.VoiceMemos", running: running) == nil)
    }
}

/// A real pty: the shell sees a terminal, and Ctrl-C reaches the program.
@Suite struct PTYProcessTests {
    private final class Collector: @unchecked Sendable {
        let lock = NSLock()
        var data = Data()
        var exited = false
        func append(_ chunk: Data) { lock.lock(); data.append(chunk); lock.unlock() }
        var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
    }

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { usleep(20_000) }
    }

    @Test func runsOnATerminalAndInterrupts() throws {
        let collector = Collector()
        let process = try PTYProcess(
            executable: "/bin/sh", arguments: ["sh"], environment: ["TERM": "xterm-256color", "PATH": "/usr/bin:/bin"],
            directory: "/tmp", columns: 80, rows: 24,
            onData: { collector.append($0) },
            onExit: { _ in collector.lock.lock(); collector.exited = true; collector.lock.unlock() })
        process.write(Data("test -t 0 && echo TTY-OK; pwd\n".utf8))
        waitUntil { collector.text.contains("TTY-OK") && collector.text.contains("tmp") }
        #expect(collector.text.contains("TTY-OK"))
        process.write(Data("sleep 30 && echo NOT-INTERRUPTED\n".utf8))
        usleep(300_000)
        process.write(Data([0x03]))
        process.write(Data("echo AFTER-CTRL-C\n".utf8))
        // A line break before the word: the output line, not the echo of what
        // was typed ("\r\n" is one Character in Swift).
        waitUntil { collector.text.contains("\r\nAFTER-CTRL-C") }
        #expect(collector.text.contains("\r\nAFTER-CTRL-C"))
        #expect(!collector.text.contains("\r\nNOT-INTERRUPTED"))
        process.write(Data("exit\n".utf8))
        waitUntil { collector.lock.lock(); defer { collector.lock.unlock() }; return collector.exited }
        #expect(collector.exited)
    }
}
