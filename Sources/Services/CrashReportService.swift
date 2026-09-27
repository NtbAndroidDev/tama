import Foundation
import AppKit

/// Tama after a crash: macOS writes an `.ips` report into
/// `~/Library/Logs/DiagnosticReports`, and this reads the newest one that
/// belongs to Tama, turns it into something a person can read, and offers
/// to put it on the clipboard.
///
/// Nothing is uploaded — there is no server to upload to, and there is no
/// analytics in Tama. The report is yours to paste wherever you report the
/// bug, so it is sanitised first: the home folder, the account name and the
/// identifiers macOS uses to recognise this Mac are taken out.
@MainActor
public final class CrashReportService: ObservableObject {
    public static let shared = CrashReportService()

    /// The file name of the last report the person was shown, so the same
    /// crash isn't raised again on every launch.
    static let seenKey = "lastSeenCrashReport"
    /// Settings › About › Troubleshooting.
    static let promptKey = "crashReportPrompt"

    /// The report waiting to be shown, if any.
    @Published public private(set) var pending: CrashReport?

    private init() {}

    private static var reportsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    /// Called at launch. Finds an unseen report from the last week and, when
    /// the prompt is on, puts the panel up once the notch has settled.
    public func checkForRecentCrash() {
        guard let report = latestReport(), report.fileName != UserDefaults.standard.string(forKey: Self.seenKey) else { return }
        pending = report
        DroppyLog.error("Crash", "Found an unseen crash report: \(report.fileName)")
        guard UserDefaults.standard.object(forKey: Self.promptKey) as? Bool ?? true else {
            // The prompt is off, so the report is left in Settings › About.
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard self?.pending != nil else { return }
            CrashReportWindowController.shared.show()
        }
    }

    /// Stops this report coming back. The report itself is left on disk.
    public func dismissPending() {
        if let pending { UserDefaults.standard.set(pending.fileName, forKey: Self.seenKey) }
        pending = nil
    }

    /// The newest Tama report from the last seven days, read and sanitised.
    /// Nothing is written and nothing is deleted.
    public func latestReport() -> CrashReport? {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: Self.reportsFolder.path) else { return nil }
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        let candidates = names
            .filter { $0.hasPrefix("Tama-") && $0.hasSuffix(".ips") }
            .map { Self.reportsFolder.appendingPathComponent($0) }
            .compactMap { url -> (URL, Date)? in
                guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      date > cutoff else { return nil }
                return (url, date)
            }
            .sorted { $0.1 > $1.1 }
        guard let newest = candidates.first else { return nil }
        return CrashReport(url: newest.0, date: newest.1)
    }

    /// Puts the report on the clipboard, and says so in the notch.
    public func copyToPasteboard(_ report: CrashReport) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(report.text, forType: .string)
        AppState.shared.showNotification(appName: "Tama", title: "Crash Report Copied",
                                         message: "Paste it wherever you report the bug.",
                                         icon: "doc.on.clipboard")
        DroppyAudio.playCopySuccess()
    }
}

/// One `.ips` file, read into something legible.
public struct CrashReport: Identifiable, Sendable {
    public let url: URL
    public let date: Date
    /// The summary shown in the panel and copied to the clipboard.
    public let text: String
    /// The single line the panel leads with ("EXC_BREAKPOINT (SIGTRAP)").
    public let headline: String

    public var id: String { url.lastPathComponent }
    public var fileName: String { url.lastPathComponent }

    init(url: URL, date: Date) {
        self.url = url
        self.date = date
        let parsed = CrashReport.summarise(url)
        self.text = parsed.text
        self.headline = parsed.headline
    }

    /// An `.ips` file is a JSON header line followed by a JSON body. When it
    /// parses, the summary is built from the fields worth reading; when it
    /// doesn't — a format change, a truncated file — the raw text is
    /// sanitised and trimmed instead, which is still better than nothing.
    private static func summarise(_ url: URL) -> (text: String, headline: String) {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return ("The crash report could not be read.", "Unreadable report")
        }
        guard let split = raw.firstIndex(of: "\n"),
              let headerData = String(raw[raw.startIndex..<split]).data(using: .utf8),
              let bodyData = String(raw[raw.index(after: split)...]).data(using: .utf8),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        else {
            return (sanitise(String(raw.prefix(8_000))), "Crash report")
        }

        let exception = body["exception"] as? [String: Any]
        let type = exception?["type"] as? String ?? "Unknown"
        let signal = exception?["signal"] as? String
        let headline = signal.map { "\(type) (\($0))" } ?? type

        // Only what came out of the report is sanitised. Tama's own labels
        // are left alone: an account named "Mac" or "admin" would otherwise
        // rewrite the headings and leave a report nobody can read.
        func value(_ any: Any?) -> String { sanitise((any as? String) ?? "?") }

        var lines: [String] = []
        lines.append("Tama crash report")
        lines.append("Version: \(value(header["app_version"])) (\(value(header["build_version"])))")
        lines.append("macOS: \(value(header["os_version"]))")
        lines.append("Mac: \(value(body["modelCode"])) · \(value(body["cpuType"]))")
        lines.append("When: \(value(header["timestamp"]))")
        lines.append("Exception: \(headline)")
        if let codes = exception?["codes"] as? String { lines.append("Codes: \(sanitise(codes))") }
        if let termination = body["termination"] as? [String: Any],
           let indicator = termination["indicator"] as? String {
            lines.append("Termination: \(sanitise(indicator))")
        }
        if let uptime = body["uptime"] as? Int { lines.append("Uptime: \(uptime)s") }

        // An uncaught Objective-C exception carries the only backtrace that
        // names anything, so it is worth more than the raw frames.
        if let backtraces = body["asiBacktraces"] as? [String], let first = backtraces.first {
            lines.append("")
            lines.append("Uncaught exception:")
            lines.append(contentsOf: first.components(separatedBy: "\n").prefix(24).map { sanitise($0) })
        }

        if let threads = body["threads"] as? [[String: Any]],
           let faulting = body["faultingThread"] as? Int, faulting < threads.count {
            let images = (body["usedImages"] as? [[String: Any]]) ?? []
            lines.append("")
            lines.append("Crashed thread \(faulting):")
            let frames = (threads[faulting]["frames"] as? [[String: Any]]) ?? []
            for (index, frame) in frames.prefix(28).enumerated() {
                let imageIndex = frame["imageIndex"] as? Int ?? -1
                let image = (imageIndex >= 0 && imageIndex < images.count)
                    ? sanitise(images[imageIndex]["name"] as? String ?? "?") : "?"
                let offset = frame["imageOffset"] as? Int ?? 0
                if let symbol = frame["symbol"] as? String {
                    let location = frame["symbolLocation"] as? Int ?? 0
                    lines.append(String(format: "%2d  %-32@ %@ + %d", index, image as NSString,
                                        sanitise(symbol), location))
                } else {
                    lines.append(String(format: "%2d  %-32@ +%d", index, image as NSString, offset))
                }
            }
        }

        return (lines.joined(separator: "\n"), headline)
    }

    /// Takes out what identifies this Mac and this account: the home folder,
    /// the account name, and the UUIDs macOS uses to recognise the machine.
    ///
    /// The account name is only replaced where it stands as a whole word.
    /// A short one — "mac", "dev", "admin" — is a substring of half the
    /// report otherwise, and "macOS 27.0" turning into "<user>OS 27.0" would
    /// make the report useless to whoever reads it.
    /// `home` and `accounts` are arguments so a test can hand it an account
    /// named after something the report itself says.
    static func sanitise(_ text: String,
                         home: String = FileManager.default.homeDirectoryForCurrentUser.path,
                         accounts: [String] = [NSUserName(), NSFullUserName()]) -> String {
        var output = text
        output = output.replacingOccurrences(of: home, with: "~")
        // Any other account's home directory, for a report that names one.
        output = output.replacingOccurrences(of: "/Users/[^/\"\\s]+", with: "/Users/<user>",
                                             options: .regularExpression)
        for name in accounts where name.count > 2 {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b"
            output = output.replacingOccurrences(of: pattern, with: "<user>",
                                                 options: [.regularExpression, .caseInsensitive])
        }
        // Serial-shaped identifiers: crashReporterKey, sleepWakeUUID, bootSessionUUID.
        for key in ["crashReporterKey", "sleepWakeUUID", "bootSessionUUID", "incident", "logWritingSignature"] {
            output = output.replacingOccurrences(
                of: "\"\(key)\" : \"[^\"]*\"", with: "\"\(key)\" : \"<removed>\"",
                options: .regularExpression)
        }
        return output
    }
}
