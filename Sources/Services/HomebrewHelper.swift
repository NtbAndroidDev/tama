import AppKit

/// Finds the command-line tools some file actions use, and installs them with
/// Homebrew: FFmpeg (video target size), Ghostscript (deep PDF compression),
/// cwebp (WebP) and LibreOffice (Office → PDF). Installing runs `brew
/// install` in the background with its progress in the notch; without
/// Homebrew, Tama points at brew.sh.
@MainActor
public final class HomebrewHelper: ObservableObject {
    public static let shared = HomebrewHelper()

    public enum Tool: String, CaseIterable, Identifiable, Sendable {
        case ffmpeg, ghostscript, webp, libreoffice

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .ffmpeg: "FFmpeg"
            case .ghostscript: "Ghostscript"
            case .webp: "WebP tools"
            case .libreoffice: "LibreOffice"
            }
        }

        public var purpose: String {
            switch self {
            case .ffmpeg: "Compress videos to an exact size"
            case .ghostscript: "Deep PDF compression"
            case .webp: "Convert images to WebP"
            case .libreoffice: "Convert Word, Excel and PowerPoint files to PDF"
            }
        }

        /// What `brew install` gets.
        var formula: [String] {
            switch self {
            case .ffmpeg: ["ffmpeg"]
            case .ghostscript: ["ghostscript"]
            case .webp: ["webp"]
            case .libreoffice: ["--cask", "libreoffice"]
            }
        }

        var candidates: [String] {
            switch self {
            case .ffmpeg: ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
            case .ghostscript: ["/opt/homebrew/bin/gs", "/usr/local/bin/gs"]
            case .webp: ["/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp"]
            case .libreoffice: ["/Applications/LibreOffice.app/Contents/MacOS/soffice"]
            }
        }
    }

    /// Tools being installed right now.
    @Published public private(set) var installing: Set<Tool> = []
    /// Bumped after an install so views re-check what's there.
    @Published public private(set) var revision = 0

    private init() {}

    nonisolated static var brewURL: URL? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    nonisolated static func path(of tool: Tool) -> URL? {
        tool.candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    public func isInstalled(_ tool: Tool) -> Bool {
        _ = revision
        return Self.path(of: tool) != nil
    }

    /// Installs a tool, or explains how to get Homebrew first.
    public func install(_ tool: Tool) {
        guard !installing.contains(tool) else { return }
        guard let brew = Self.brewURL else {
            promptForHomebrew(tool)
            return
        }
        installing.insert(tool)
        let arguments = ["install"] + tool.formula
        JobCenter.shared.run(
            title: "Installing \(tool.title) via Homebrew",
            appName: "Homebrew",
            failureTitle: "Install failed",
            operation: { _ in
                try FileConverter.run(brew, arguments, environment: HomebrewHelper.brewEnvironment)
            },
            onSuccess: { _ in
                HomebrewHelper.shared.revision += 1
                return JobCenter.Banner(title: "\(tool.title) installed", message: tool.purpose)
            },
            onFinish: { _ in
                HomebrewHelper.shared.installing.remove(tool)
                HomebrewHelper.shared.revision += 1
            }
        )
        AppState.shared.showNotification(appName: "Homebrew", title: "Installing \(tool.title)",
                                         message: "Downloading and installing… this can take a few minutes.",
                                         icon: "shippingbox.fill")
    }

    /// Homebrew needs its own bin folder on PATH and no auto-update prompt.
    nonisolated static var brewEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["NONINTERACTIVE"] = "1"
        return env
    }

    /// Homebrew Required: open brew.sh, then come back and install.
    public func promptForHomebrew(_ tool: Tool) {
        let alert = NSAlert()
        alert.messageText = "Homebrew Required"
        alert.informativeText = "\(tool.title) is installed with Homebrew, the macOS package manager. Visit brew.sh to install Homebrew, then click “Install \(tool.title)” again."
        alert.addButton(withTitle: "Visit brew.sh")
        alert.addButton(withTitle: "Cancel")
        let state = AppState.shared
        state.setModal(true, owner: "homebrew.brewMissing")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        state.setModal(false, owner: "homebrew.brewMissing")
        if response == .alertFirstButtonReturn, let url = URL(string: "https://brew.sh") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Asks before installing a tool an action needs; true when it's there.
    public func require(_ tool: Tool, for action: String) -> Bool {
        if isInstalled(tool) { return true }
        let alert = NSAlert()
        alert.messageText = "\(action) needs \(tool.title)"
        alert.informativeText = Self.brewURL == nil
            ? "Homebrew isn't installed. Visit brew.sh to install it, then install \(tool.title)."
            : "Homebrew detected. Install \(tool.title) now? It runs `brew install \(tool.formula.joined(separator: " "))` in the background."
        alert.addButton(withTitle: Self.brewURL == nil ? "Visit brew.sh" : "Install \(tool.title)")
        alert.addButton(withTitle: "Cancel")
        let state = AppState.shared
        state.setModal(true, owner: "homebrew.require")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        state.setModal(false, owner: "homebrew.require")
        if response == .alertFirstButtonReturn {
            if Self.brewURL == nil {
                if let url = URL(string: "https://brew.sh") { NSWorkspace.shared.open(url) }
            } else {
                install(tool)
            }
        }
        return false
    }
}
