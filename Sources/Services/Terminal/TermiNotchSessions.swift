import AppKit
import Combine
import Darwin

/// The app "Open in Terminal" hands the current folder to.
public enum TerminalApp: String, CaseIterable, Identifiable, Sendable {
    case terminal, iterm, ghostty, warp

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .terminal: "Terminal"
        case .iterm: "iTerm"
        case .ghostty: "Ghostty"
        case .warp: "Warp"
        }
    }

    public var bundleIDs: [String] {
        switch self {
        case .terminal: ["com.apple.Terminal"]
        case .iterm: ["com.googlecode.iterm2"]
        case .ghostty: ["com.mitchellh.ghostty"]
        case .warp: ["dev.warp.Warp-Stable", "dev.warp.Warp"]
        }
    }

    @MainActor public var appURL: URL? {
        bundleIDs.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    @MainActor public var isInstalled: Bool { appURL != nil }
}

/// One tab: a login shell on its own pty and the screen it draws into.
@MainActor
public final class TerminalSession: ObservableObject, Identifiable {
    public let id = UUID()
    public let screen: TerminalScreen
    /// Bumped after each batch of output; views redraw on it.
    @Published public private(set) var revision = 0
    @Published public private(set) var hasExited = false
    @Published public private(set) var title = "zsh"
    private var process: PTYProcess?
    private let pending = PendingOutput()
    /// Which shell an exit belongs to: a restart must not be ended by the old one.
    private var generation = 0

    init(directory: String, columns: Int, rows: Int) {
        screen = TerminalScreen(columns: columns, rows: rows)
        start(in: directory)
    }

    private func start(in directory: String) {
        let shell = TermiNotchSessions.loginShell
        let name = (shell as NSString).lastPathComponent
        let environment = TermiNotchSessions.environment(for: name)
        let sessionID = id
        let pending = self.pending
        generation += 1
        let current = generation
        do {
            process = try PTYProcess(
                executable: shell, arguments: ["-" + name], environment: environment,
                directory: FileManager.default.fileExists(atPath: directory) ? directory : NSHomeDirectory(),
                columns: screen.columns, rows: screen.rowCount,
                onData: { data in
                    // Output comes in bursts; redraw at most once a frame.
                    guard pending.append(data) else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
                        MainActor.assumeIsolated { TermiNotchSessions.shared.session(sessionID)?.drain() }
                    }
                },
                onExit: { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        MainActor.assumeIsolated { TermiNotchSessions.shared.session(sessionID)?.processEnded(current) }
                    }
                })
            title = name
            hasExited = false
        } catch {
            screen.feed("\r\n\u{1b}[31m\(error.localizedDescription)\u{1b}[0m\r\n")
            hasExited = true
            revision += 1
        }
    }

    private func drain() {
        let data = pending.take()
        guard !data.isEmpty else { return }
        screen.feed(data)
        let replies = screen.takeResponses()
        if !replies.isEmpty { process?.write(replies) }
        refreshTitle()
        revision += 1
    }

    private func processEnded(_ ended: Int) {
        guard ended == generation else { return }
        drain()
        TermiNotchSessions.shared.remember(directory: directory)
        process = nil
        hasExited = true
        screen.feed("\r\n\u{1b}[2m[Process completed — press Return or ↻ to start a new shell]\u{1b}[0m\r\n")
        revision += 1
    }

    private func refreshTitle() {
        let next = process?.foregroundCommand ?? ((directory as NSString).lastPathComponent)
        if next != title { title = next.isEmpty ? "/" : next }
    }

    /// The shell's working directory right now, or the last one known.
    public var directory: String {
        if let current = process?.currentDirectory { return current }
        return screen.reportedDirectory ?? TermiNotchSessions.shared.rememberedDirectory
    }

    /// A program other than the shell is running in the foreground.
    public var isBusy: Bool { process?.foregroundCommand != nil }

    public func send(_ data: Data) {
        guard let process, !hasExited else {
            // Return on a finished tab starts a new shell there.
            if data == Data([0x0d]) { restart() }
            return
        }
        process.write(data)
    }

    public func send(_ text: String) { send(Data(text.utf8)) }

    /// Pasted text, wrapped for shells that asked for bracketed paste.
    public func paste(_ text: String) {
        let clean = text.replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r")
        send(screen.bracketedPaste ? "\u{1b}[200~" + clean + "\u{1b}[201~" : clean)
    }

    public func interrupt() { send(Data([0x03])) }

    public func resize(columns: Int, rows: Int) {
        guard columns != screen.columns || rows != screen.rowCount else { return }
        screen.resize(columns: columns, rows: rows)
        process?.resize(columns: screen.columns, rows: screen.rowCount)
        revision += 1
    }

    public func clear() {
        screen.clearAll()
        // Ctrl-L asks the shell to redraw its prompt on the clean screen.
        if !isBusy { send(Data([0x0c])) }
        revision += 1
    }

    /// A new shell in the same folder, on a clean screen.
    public func restart() {
        let folder = directory
        TermiNotchSessions.shared.remember(directory: folder)
        process?.terminate()
        process = nil
        screen.reset()
        screen.clearAll()
        start(in: folder)
        revision += 1
    }

    func terminate() {
        TermiNotchSessions.shared.remember(directory: directory)
        process?.terminate()
        process = nil
    }
}

/// Output waiting for the main thread; appended from the pty's queue.
private final class PendingOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var scheduled = false

    /// True when the caller should schedule a drain.
    func append(_ chunk: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        data.append(chunk)
        guard !scheduled else { return false }
        scheduled = true
        return true
    }

    func take() -> Data {
        lock.lock()
        defer { lock.unlock() }
        scheduled = false
        let out = data
        data = Data()
        return out
    }
}

/// TermiNotch's tabs. Shells start when the droplet is first opened and keep
/// running while the shelf is closed; the folder you `cd` to is remembered
/// across restarts and relaunches.
@MainActor
public final class TermiNotchSessions: ObservableObject {
    public static let shared = TermiNotchSessions()

    public static let directoryKey = "termiNotchDirectory"

    @Published public private(set) var sessions: [TerminalSession] = []
    @Published public var activeID: UUID?
    /// The last size a view measured, used for new tabs.
    private var size = (columns: 80, rows: 16)

    private init() {}

    public var active: TerminalSession? {
        sessions.first { $0.id == activeID } ?? sessions.first
    }

    func session(_ id: UUID) -> TerminalSession? { sessions.first { $0.id == id } }

    /// The first tab, started on demand.
    @discardableResult
    public func ensureSession() -> TerminalSession {
        if let active { return active }
        return newTab()
    }

    @discardableResult
    public func newTab() -> TerminalSession {
        let folder = active?.directory ?? rememberedDirectory
        let session = TerminalSession(directory: folder, columns: size.columns, rows: size.rows)
        sessions.append(session)
        activeID = session.id
        return session
    }

    public func close(_ session: TerminalSession) {
        session.terminate()
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions.remove(at: index)
        if activeID == session.id {
            activeID = sessions.isEmpty ? nil : sessions[min(index, sessions.count - 1)].id
        }
    }

    public func select(_ session: TerminalSession) { activeID = session.id }

    public func resizeAll(columns: Int, rows: Int) {
        size = (columns, rows)
        sessions.forEach { $0.resize(columns: columns, rows: rows) }
    }

    public func terminateAll() {
        sessions.forEach { $0.terminate() }
        sessions.removeAll()
        activeID = nil
    }

    // MARK: Folder memory

    var rememberedDirectory: String {
        let saved = UserDefaults.standard.string(forKey: Self.directoryKey) ?? NSHomeDirectory()
        return FileManager.default.fileExists(atPath: saved) ? saved : NSHomeDirectory()
    }

    func remember(directory: String) {
        guard FileManager.default.fileExists(atPath: directory) else { return }
        UserDefaults.standard.set(directory, forKey: Self.directoryKey)
    }

    // MARK: Open in Terminal

    /// Opens the active tab's folder in the app picked in Settings (Terminal
    /// when that one isn't installed). Opening a folder *with* the app starts
    /// a shell there, so no Automation permission is needed; Warp takes its
    /// own URL.
    public func openInTerminalApp() {
        let folder = active?.directory ?? rememberedDirectory
        remember(directory: folder)
        var app = AppState.shared.termiNotchTerminalApp
        if !app.isInstalled {
            AppState.shared.showNotification(appName: "TermiNotch", title: "\(app.title) isn't installed",
                                             message: "Opening Terminal instead. Pick another app in the TermiNotch settings.",
                                             icon: "apple.terminal")
            app = .terminal
        }
        if app == .warp {
            var components = URLComponents()
            components.scheme = "warp"
            components.host = "action"
            components.path = "/new_window"
            components.queryItems = [URLQueryItem(name: "path", value: folder)]
            if let url = components.url { NSWorkspace.shared.open(url) }
        } else if let appURL = app.appURL {
            NSWorkspace.shared.open([URL(fileURLWithPath: folder, isDirectory: true)], withApplicationAt: appURL,
                                    configuration: NSWorkspace.OpenConfiguration())
        }
        AppState.shared.setIslandExpanded(false)
    }

    // MARK: Shell setup

    static var loginShell: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(decoding: Data(bytes: shell, count: strlen(shell)), as: UTF8.self)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/bin/zsh"
    }

    static func environment(for shellName: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "Tama"
        if environment["LANG"] == nil { environment["LANG"] = "en_US.UTF-8" }
        environment["SHELL"] = loginShell
        environment.removeValue(forKey: "__CFBundleIdentifier")
        environment.removeValue(forKey: "XPC_SERVICE_NAME")
        // zsh: Tama's prompt (user@host ~ / green $) after the user's own
        // startup files, unless Settings turns it off.
        if shellName == "zsh", AppState.shared.termiNotchDroppyPrompt, let dotdir = zshDotDirectory() {
            if let user = environment["ZDOTDIR"] { environment["DROPPY_USER_ZDOTDIR"] = user }
            environment["ZDOTDIR"] = dotdir
        }
        return environment
    }

    /// Startup files that source the user's own (.zshenv, .zprofile, .zshrc,
    /// .zlogin from their ZDOTDIR or home) and then set the prompt.
    private static func zshDotDirectory() -> String? {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = support.appendingPathComponent("Tama/TermiNotch/zsh", isDirectory: true)
        do { try fm.createDirectory(at: folder, withIntermediateDirectories: true) } catch { return nil }
        func chain(_ file: String) -> String {
            """
            # Written by Tama's TermiNotch: runs your own \(file), then hands back.
            __tama_zdotdir="$ZDOTDIR"
            ZDOTDIR="${DROPPY_USER_ZDOTDIR:-$HOME}"
            [[ -r "$ZDOTDIR/\(file)" ]] && source "$ZDOTDIR/\(file)"
            DROPPY_USER_ZDOTDIR="$ZDOTDIR"
            ZDOTDIR="$__tama_zdotdir"

            """
        }
        let files: [String: String] = [
            ".zshenv": chain(".zshenv"),
            ".zprofile": chain(".zprofile"),
            ".zshrc": chain(".zshrc") + """
            # /etc/zshrc put history next to these files; keep it in yours.
            [[ "$HISTFILE" == "$__tama_zdotdir"/* ]] && HISTFILE="$DROPPY_USER_ZDOTDIR/.zsh_history"
            PROMPT=$'%F{blue}%n@%m%f %F{blue}%~%f\\n%F{green}$%f '
            RPROMPT=''

            """,
            ".zlogin": chain(".zlogin") + """
            ZDOTDIR="$DROPPY_USER_ZDOTDIR"
            unset __tama_zdotdir DROPPY_USER_ZDOTDIR

            """,
        ]
        for (name, contents) in files {
            let url = folder.appendingPathComponent(name)
            if (try? String(contentsOf: url, encoding: .utf8)) != contents {
                try? contents.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        return folder.path
    }
}
