import AppKit
import Foundation

// What Thunderstorm's floating launcher can find besides files: System
// Settings panes, system commands, web searches and DuckDuckGo instant
// answers.

// MARK: - Matching

enum LauncherMatch {
    /// Every word of the query appears in the title or a keyword. Returns a
    /// score (higher is better), or nil for no match.
    static func score(_ query: String, title: String, keywords: [String] = []) -> Int? {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        let lowerTitle = title.lowercased()
        let haystack = ([lowerTitle] + keywords.map { $0.lowercased() }).joined(separator: " ")
        guard words.allSatisfy({ haystack.contains($0) }) else { return nil }
        let joined = words.joined(separator: " ")
        if lowerTitle == joined { return 400 }
        if lowerTitle.hasPrefix(joined) { return 300 }
        if lowerTitle.split(separator: " ").contains(where: { $0.hasPrefix(words[0]) }) { return 200 }
        if lowerTitle.contains(joined) { return 150 }
        return 100
    }
}

// MARK: - System Settings panes

/// A System Settings pane, opened through its `x-apple.systempreferences:` URL.
struct SystemSettingsPane: Identifiable, Sendable {
    let name: String
    let detail: String
    let symbol: String
    let paneID: String
    let keywords: [String]

    var id: String { paneID + name }
    var url: URL? { URL(string: "x-apple.systempreferences:\(paneID)") }

    init(_ name: String, _ detail: String, _ symbol: String, _ paneID: String, _ keywords: [String] = []) {
        self.name = name
        self.detail = detail
        self.symbol = symbol
        self.paneID = paneID
        self.keywords = keywords
    }

    static let all: [SystemSettingsPane] = [
        .init("Wi-Fi", "Wireless network connection, known networks, and hotspots.", "wifi",
              "com.apple.wifi-settings-extension", ["wireless", "network", "hotspot", "internet"]),
        .init("Bluetooth", "Connect and manage Bluetooth devices.", "dot.radiowaves.left.and.right",
              "com.apple.BluetoothSettings", ["airpods", "headphones", "devices", "pair"]),
        .init("Network", "Ethernet, VPN, firewall and network services.", "network",
              "com.apple.Network-Settings.extension", ["ethernet", "firewall", "proxy", "dns"]),
        .init("VPN", "Add and connect VPN configurations.", "lock.shield",
              "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension", ["tunnel", "network"]),
        .init("Notifications", "Choose which apps can notify you and how.", "bell.badge",
              "com.apple.Notifications-Settings.extension", ["alerts", "banners", "badges"]),
        .init("Sound", "Output and input devices, alert sounds and volume.", "speaker.wave.2",
              "com.apple.Sound-Settings.extension", ["volume", "audio", "microphone", "speakers", "output", "input"]),
        .init("Focus", "Do Not Disturb and Focus modes.", "moon",
              "com.apple.Focus-Settings.extension", ["do not disturb", "dnd", "sleep", "work"]),
        .init("Screen Time", "App limits, downtime, and communication limits.", "hourglass",
              "com.apple.Screen-Time-Settings.extension", ["limits", "downtime", "usage", "parental"]),
        .init("General", "About, Software Update, Storage, AirDrop and more.", "gear",
              "com.apple.systempreferences.GeneralSettings", ["settings"]),
        .init("About", "This Mac's model, chip, memory and serial number.", "info.circle",
              "com.apple.SystemProfiler.AboutExtension", ["serial", "model", "system report", "version"]),
        .init("Software Update", "Update macOS.", "arrow.triangle.2.circlepath",
              "com.apple.Software-Update-Settings.extension", ["update", "upgrade", "macos"]),
        .init("Storage", "Disk space and storage recommendations.", "internaldrive",
              "com.apple.settings.Storage", ["disk", "space", "free up"]),
        .init("AirDrop & Handoff", "AirDrop visibility and Handoff between devices.", "airplayaudio",
              "com.apple.AirDrop-Handoff-Settings.extension", ["airdrop", "handoff", "airplay receiver"]),
        .init("Login Items & Extensions", "Apps that open at login and app extensions.", "person.badge.key",
              "com.apple.LoginItems-Settings.extension", ["startup", "login", "background items", "extensions"]),
        .init("Language & Region", "Preferred languages, region, calendar and number formats.", "globe",
              "com.apple.Localization-Settings.extension", ["language", "region", "locale", "format"]),
        .init("Date & Time", "Set the date, time and time zone.", "clock",
              "com.apple.Date-Time-Settings.extension", ["clock", "time zone", "24-hour"]),
        .init("Sharing", "File sharing, screen sharing, remote login and the computer's name.", "person.2",
              "com.apple.Sharing-Settings.extension", ["file sharing", "screen sharing", "ssh", "remote", "computer name"]),
        .init("Time Machine", "Back up with Time Machine.", "clock.arrow.circlepath",
              "com.apple.Time-Machine-Settings.extension", ["backup"]),
        .init("Transfer or Reset", "Erase this Mac or transfer to a new one.", "arrow.counterclockwise",
              "com.apple.Transfer-Reset-Settings.extension", ["erase", "reset", "migration"]),
        .init("Startup Disk", "Choose the disk your Mac starts up from.", "externaldrive",
              "com.apple.Startup-Disk-Settings.extension", ["boot"]),
        .init("Appearance", "Light and dark mode, accent and highlight colour.", "circle.lefthalf.filled",
              "com.apple.Appearance-Settings.extension", ["dark mode", "light mode", "accent", "theme"]),
        .init("Accessibility", "Vision, hearing, motor and speech features.", "accessibility",
              "com.apple.Accessibility-Settings.extension", ["voiceover", "zoom", "reduce motion", "contrast"]),
        .init("Control Center", "Menu bar and Control Center items.", "switch.2",
              "com.apple.ControlCenter-Settings.extension", ["menu bar", "clock", "battery percentage"]),
        .init("Siri", "Siri and Apple Intelligence.", "mic",
              "com.apple.Siri-Settings.extension", ["apple intelligence", "voice", "assistant", "hey siri"]),
        .init("Spotlight", "Search results and privacy for Spotlight.", "magnifyingglass",
              "com.apple.Spotlight-Settings.extension", ["search", "index"]),
        .init("Privacy & Security", "App permissions, FileVault and security settings.", "hand.raised",
              "com.apple.settings.PrivacySecurity.extension", ["privacy", "security", "permissions", "filevault", "accessibility access"]),
        .init("Desktop & Dock", "Dock, Stage Manager, windows and Mission Control.", "dock.rectangle",
              "com.apple.Desktop-Settings.extension", ["dock", "stage manager", "mission control", "hot corners", "widgets"]),
        .init("Displays", "Resolution, brightness, Night Shift and arrangement.", "display",
              "com.apple.Displays-Settings.extension", ["monitor", "resolution", "night shift", "brightness", "true tone"]),
        .init("Wallpaper", "Desktop pictures.", "photo",
              "com.apple.Wallpaper-Settings.extension", ["background", "desktop picture"]),
        .init("Screen Saver", "Screen savers.", "sparkles.tv",
              "com.apple.ScreenSaver-Settings.extension", ["screensaver"]),
        .init("Battery", "Battery health, Low Power Mode and energy options.", "battery.100",
              "com.apple.Battery-Settings.extension", ["energy", "power", "low power mode", "charging"]),
        .init("Lock Screen", "When the display turns off and a password is required.", "lock",
              "com.apple.Lock-Screen-Settings.extension", ["screen lock", "require password", "sleep display"]),
        .init("Touch ID & Password", "Fingerprints and your login password.", "touchid",
              "com.apple.Touch-ID-Settings.extension", ["fingerprint", "password", "touch id"]),
        .init("Users & Groups", "User accounts and guest access.", "person.2.circle",
              "com.apple.Users-Groups-Settings.extension", ["account", "guest", "admin"]),
        .init("Passwords", "Saved passwords and passkeys.", "key",
              "com.apple.Passwords-Settings.extension", ["keychain", "passkeys"]),
        .init("Internet Accounts", "Mail, contacts and calendar accounts.", "at",
              "com.apple.Internet-Accounts-Settings.extension", ["mail", "google", "exchange", "accounts"]),
        .init("Game Center", "Game Center profile and friends.", "gamecontroller",
              "com.apple.Game-Center-Settings.extension", ["games"]),
        .init("Game Controllers", "Connected game controllers and their buttons.", "gamecontroller.fill",
              "com.apple.Game-Controller-Settings.extension", ["controller", "gamepad", "joystick"]),
        .init("Wallet & Apple Pay", "Cards and Apple Pay.", "creditcard",
              "com.apple.WalletSettingsExtension", ["apple pay", "cards", "wallet"]),
        .init("Keyboard", "Key repeat, input sources, dictation and text replacements.", "keyboard",
              "com.apple.Keyboard-Settings.extension", ["input sources", "dictation", "key repeat", "backlight"]),
        .init("Keyboard Shortcuts", "App and system keyboard shortcuts, including Spotlight Shortcuts.", "command",
              "com.apple.Keyboard-Settings.extension", ["shortcuts", "hotkeys", "spotlight shortcuts", "mission control shortcuts"]),
        .init("Mouse", "Tracking speed, scrolling and secondary click.", "computermouse",
              "com.apple.Mouse-Settings.extension", ["scroll direction", "natural scrolling", "tracking"]),
        .init("Trackpad", "Gestures, tap to click and tracking speed.", "rectangle.and.hand.point.up.left",
              "com.apple.Trackpad-Settings.extension", ["gestures", "tap to click", "force click"]),
        .init("Printers & Scanners", "Add printers and scanners.", "printer",
              "com.apple.Print-Scanner-Settings.extension", ["print", "scanner"]),
        .init("Family", "Family Sharing members and settings.", "person.3",
              "com.apple.Family-Settings.extension", ["family sharing", "parental"]),
        .init("Apple Account", "Your Apple Account, iCloud and media purchases.", "person.crop.circle",
              "com.apple.systempreferences.AppleIDSettings", ["apple id", "icloud", "account"]),
    ]
}

// MARK: - System commands

/// Mac-wide commands. The destructive ones ask for a second Return first.
enum SystemCommand: String, CaseIterable, Identifiable, Sendable {
    case lockScreen, sleep, restart, shutDown, logOut, ejectAll, quitAll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lockScreen: "Lock Screen"
        case .sleep: "Sleep"
        case .restart: "Restart"
        case .shutDown: "Shut Down"
        case .logOut: "Log Out"
        case .ejectAll: "Eject All Disks"
        case .quitAll: "Quit All Apps"
        }
    }

    var detail: String {
        switch self {
        case .lockScreen: "Lock this Mac"
        case .sleep: "Put your Mac to sleep"
        case .restart: "Restart your Mac"
        case .shutDown: "Shut down your Mac"
        case .logOut: "Log out of your macOS account"
        case .ejectAll: "Eject every disk and network drive"
        case .quitAll: "Quit every running app except Finder and Tama"
        }
    }

    var symbol: String {
        switch self {
        case .lockScreen: "lock.fill"
        case .sleep: "moon.zzz.fill"
        case .restart: "arrow.clockwise.circle.fill"
        case .shutDown: "power.circle.fill"
        case .logOut: "rectangle.portrait.and.arrow.right"
        case .ejectAll: "eject.fill"
        case .quitAll: "xmark.app.fill"
        }
    }

    var keywords: [String] {
        switch self {
        case .lockScreen: ["lock", "screen", "away"]
        case .sleep: ["sleep", "suspend", "rest"]
        case .restart: ["reboot", "restart"]
        case .shutDown: ["shutdown", "power off", "turn off"]
        case .logOut: ["logout", "sign out", "log off"]
        case .ejectAll: ["eject", "unmount", "disks", "drives", "usb"]
        case .quitAll: ["quit", "close all", "kill", "apps"]
        }
    }

    /// The confirmation prompt; nil when the command runs at once.
    var confirmation: String? {
        switch self {
        case .lockScreen, .sleep: nil
        case .restart: "Press Return to restart"
        case .shutDown: "Press Return to shut down"
        case .logOut: "Press Return to log out"
        case .ejectAll: "Press Return to eject"
        case .quitAll: "Press Return to quit every app"
        }
    }

    /// Runs the command; the result is a line to show, or nil for silence.
    @MainActor
    func perform() async -> String? {
        switch self {
        case .lockScreen:
            return Self.lockScreen() ? nil : "Couldn't lock the screen."
        case .sleep:
            return Self.run("/usr/bin/pmset", ["sleepnow"]) ? nil : "Couldn't put the Mac to sleep."
        case .restart:
            return await Self.systemEvents("restart")
        case .shutDown:
            return await Self.systemEvents("shut down")
        case .logOut:
            return await Self.systemEvents("log out")
        case .ejectAll:
            return await Self.ejectAll()
        case .quitAll:
            return Self.quitAll()
        }
    }

    /// `SACLockScreenImmediate` from the login framework is what the Apple
    /// menu's Lock Screen uses; it's private, so it's looked up at run time and
    /// a display-sleep (which locks when a password is required) is the fallback.
    @MainActor
    private static func lockScreen() -> Bool {
        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        if let handle = dlopen(path, RTLD_LAZY) {
            defer { dlclose(handle) }
            if let symbol = dlsym(handle, "SACLockScreenImmediate") {
                typealias Lock = @convention(c) () -> Int32
                _ = unsafeBitCast(symbol, to: Lock.self)()
                return true
            }
        }
        return run("/usr/bin/pmset", ["displaysleepnow"])
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    /// Restart, shut down and log out go through System Events, which asks
    /// every app to quit (and lets them save) like the Apple menu does.
    private static func systemEvents(_ verb: String) async -> String? {
        let source = "tell application \"System Events\" to \(verb)"
        let failed = await Task.detached { () -> Bool in
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            return error != nil
        }.value
        return failed ? "System Events didn't \(verb). Allow Tama under Privacy & Security › Automation." : nil
    }

    private static func ejectAll() async -> String? {
        let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsLocalKey, .volumeIsRootFileSystemKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        let targets = volumes.filter { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.volumeIsRootFileSystem != true else { return false }
            return values.volumeIsEjectable == true || values.volumeIsRemovable == true || values.volumeIsLocal == false
        }
        guard !targets.isEmpty else { return "No disks to eject." }
        let failures = await Task.detached { () -> Int in
            var failed = 0
            for url in targets {
                do { try NSWorkspace.shared.unmountAndEjectDevice(at: url) } catch { failed += 1 }
            }
            return failed
        }.value
        let ejected = targets.count - failures
        if failures == 0 { return ejected == 1 ? "Ejected 1 disk." : "Ejected \(ejected) disks." }
        return "Ejected \(ejected) of \(targets.count); some disks are in use."
    }

    @MainActor
    private static func quitAll() -> String? {
        let keep: Set<String> = ["com.apple.finder", Bundle.main.bundleIdentifier ?? ""]
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !keep.contains($0.bundleIdentifier ?? "") && $0 != NSRunningApplication.current
        }
        apps.forEach { $0.terminate() }
        return apps.isEmpty ? "No apps to quit." : "Asked \(apps.count) app\(apps.count == 1 ? "" : "s") to quit."
    }
}

// MARK: - Web search

enum WebSearchEngine: String, CaseIterable, Identifiable, Sendable {
    case google, duckDuckGo, wikipedia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .google: "Google Search"
        case .duckDuckGo: "DuckDuckGo"
        case .wikipedia: "Wikipedia"
        }
    }

    var symbol: String {
        switch self {
        case .google: "magnifyingglass.circle.fill"
        case .duckDuckGo: "shield.lefthalf.filled"
        case .wikipedia: "book.closed.fill"
        }
    }

    func url(for query: String) -> URL? {
        var components: URLComponents
        switch self {
        case .google: components = URLComponents(string: "https://www.google.com/search")!
        case .duckDuckGo: components = URLComponents(string: "https://duckduckgo.com/")!
        case .wikipedia: components = URLComponents(string: "https://en.wikipedia.org/w/index.php")!
        }
        components.queryItems = [URLQueryItem(name: self == .wikipedia ? "search" : "q", value: query)]
        return components.url
    }
}

// MARK: - Instant answers

/// One answer from DuckDuckGo's free, keyless Instant Answer API.
struct InstantAnswer: Equatable, Sendable {
    var heading: String
    var text: String
    var source: String
    var url: URL?
}

enum InstantAnswerService {
    /// nil when DuckDuckGo has nothing for the query (most queries); throws on network errors.
    static func lookUp(_ query: String) async throws -> InstantAnswer? {
        var components = URLComponents(string: "https://api.duckduckgo.com/")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1"),
            URLQueryItem(name: "t", value: "tama"),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Tama", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return parse(data)
    }

    static func parse(_ data: Data) -> InstantAnswer? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func string(_ key: String) -> String { (json[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        let heading = string("Heading")
        if !string("Answer").isEmpty {
            return InstantAnswer(heading: heading.isEmpty ? "Answer" : heading, text: string("Answer"),
                                 source: "DuckDuckGo", url: nil)
        }
        if !string("AbstractText").isEmpty {
            return InstantAnswer(heading: heading, text: string("AbstractText"),
                                 source: string("AbstractSource").isEmpty ? "DuckDuckGo" : string("AbstractSource"),
                                 url: URL(string: string("AbstractURL")))
        }
        if !string("Definition").isEmpty {
            return InstantAnswer(heading: heading.isEmpty ? "Definition" : heading, text: string("Definition"),
                                 source: string("DefinitionSource"), url: URL(string: string("DefinitionURL")))
        }
        return nil
    }
}
