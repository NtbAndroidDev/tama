import AppKit
import OSLog
import UniformTypeIdentifiers

/// Tama's log. Everything goes to the unified log (subsystem
/// app.tama.macos); with Settings › About › Diagnostic logging on, lines
/// are also written to ~/Library/Logs/Tama/Tama.log (capped at 2 MB, one
/// older file kept) so "Export logs…" can hand them over.
enum DroppyLog {
    private static let subsystem = "app.tama.macos"
    private static let writer = LogFileWriter()

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Tama", isDirectory: true)
    }
    static var file: URL { folder.appendingPathComponent("Tama.log") }

    /// Detailed logging is on (read straight from defaults, from any thread).
    static var isVerbose: Bool { UserDefaults.standard.bool(forKey: "diagnosticLogging") }

    static func info(_ category: String, _ message: String) {
        Logger(subsystem: subsystem, category: category).info("\(message, privacy: .public)")
        if isVerbose { writer.append("INFO", category, message) }
    }

    static func error(_ category: String, _ message: String) {
        Logger(subsystem: subsystem, category: category).error("\(message, privacy: .public)")
        if isVerbose { writer.append("ERROR", category, message) }
    }

    /// Detail only worth keeping while diagnostic logging is on.
    static func debug(_ category: String, _ message: @autoclosure () -> String) {
        guard isVerbose else { return }
        let text = message()
        Logger(subsystem: subsystem, category: category).debug("\(text, privacy: .public)")
        writer.append("DEBUG", category, text)
    }

    /// A text report: version, macOS, displays, settings that aren't private,
    /// then the log file(s). Returned as one string for the save panel.
    @MainActor
    static func report() -> String {
        let info = Bundle.main.infoDictionary
        var lines: [String] = []
        lines.append("Tama diagnostic report — \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Version: \(info?["CFBundleShortVersionString"] as? String ?? "dev") (\(info?["CFBundleVersion"] as? String ?? "-"))")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Model: \(LocalSendService.modelName)")
        lines.append("Displays: \(NSScreen.screens.map { "\(Int($0.frame.width))×\(Int($0.frame.height))\($0.safeAreaInsets.top > 0 ? " (notch)" : "")" }.joined(separator: ", "))")
        lines.append("Droplets on: \(AppState.shared.droplets.filter(\.isEnabled).map(\.id).joined(separator: ", "))")
        lines.append("Permissions: \(PermissionService.Kind.allCases.map { "\($0.rawValue)=\(PermissionService.shared.status($0))" }.joined(separator: ", "))")
        lines.append("")
        lines.append("Settings (PIN and folder paths left out):")
        let private_: Set<String> = ["localSendPIN", "localSendSaveFolder", "smartExportFolder", "snipperFolderPath",
                                     "trackedFolders", "weatherPlaceLatitude", "weatherPlaceLongitude", "weatherPlaceName"]
        let defaults = UserDefaults.standard
        for key in AppState.settingsKeys.sorted() where !private_.contains(key) {
            guard let value = defaults.object(forKey: key) else { continue }
            lines.append("  \(key) = \(String(describing: value).prefix(200))")
        }
        lines.append("")
        writer.flush()
        let older = folder.appendingPathComponent("Tama.1.log")
        for url in [older, file] {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            lines.append("===== \(url.lastPathComponent) =====")
            lines.append(text)
        }
        if !isVerbose && !FileManager.default.fileExists(atPath: file.path) {
            lines.append("(Diagnostic logging is off, so there's no log file. Turn it on, reproduce the problem, then export again.)")
        }
        return lines.joined(separator: "\n")
    }

    /// "Export logs…": saves the report where the user picks.
    @MainActor
    static func export() {
        let panel = NSSavePanel()
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd HH-mm"
        panel.nameFieldStringValue = "Tama Logs \(stamp.string(from: Date())).txt"
        panel.allowedContentTypes = [.plainText]
        AppState.shared.setModal(true, owner: "tamaLog.export")
        defer { AppState.shared.setModal(false, owner: "tamaLog.export") }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try report().write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    /// Deletes the log files.
    static func clear() {
        writer.clear()
    }
}

/// Appends lines off the main thread, rotating at 2 MB.
private final class LogFileWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.tama.log", qos: .utility)
    private let limit = 2 * 1024 * 1024
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func append(_ level: String, _ category: String, _ message: String) {
        let line = "\(formatter.string(from: Date())) [\(level)] \(category): \(message)\n"
        queue.async {
            let fm = FileManager.default
            let file = DroppyLog.file
            try? fm.createDirectory(at: DroppyLog.folder, withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: file.path))?[.size] as? Int, size > self.limit {
                let older = DroppyLog.folder.appendingPathComponent("Tama.1.log")
                try? fm.removeItem(at: older)
                try? fm.moveItem(at: file, to: older)
            }
            if !fm.fileExists(atPath: file.path) { fm.createFile(atPath: file.path, contents: nil) }
            guard let handle = try? FileHandle(forWritingTo: file) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }

    func flush() { queue.sync {} }

    func clear() {
        queue.async {
            try? FileManager.default.removeItem(at: DroppyLog.file)
            try? FileManager.default.removeItem(at: DroppyLog.folder.appendingPathComponent("Tama.1.log"))
        }
    }
}

/// Small app-wide preferences that act through AppKit defaults.
enum DroppyDiagnostics {
    /// Settings › Accessibility › Show tooltips. AppKit reads
    /// NSInitialToolTipDelay for every tooltip, so a very long delay turns
    /// all of Tama's hover help off; removing it restores the system delay.
    static func applyTooltipPreference(_ show: Bool) {
        if show {
            UserDefaults.standard.removeObject(forKey: "NSInitialToolTipDelay")
        } else {
            UserDefaults.standard.set(86_400_000, forKey: "NSInitialToolTipDelay")
        }
    }
}
