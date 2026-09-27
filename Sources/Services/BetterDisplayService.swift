import AppKit

/// Settings › HUDs › BetterDisplay integration. BetterDisplay can dim external
/// monitors (over DDC or in software) and, when its HTTP server is switched on
/// (BetterDisplay › Settings › Integration), takes commands on
/// `127.0.0.1:55777`. When it answers, the brightness keys aimed at an
/// external display go through it and the notch HUD shows the level. Tama
/// never installs or starts BetterDisplay; without it the row offers a link.
@MainActor
public final class BetterDisplayService: ObservableObject {
    public static let shared = BetterDisplayService()

    public static let bundleID = "pro.betterdisplay.BetterDisplay"
    public static let downloadURL = URL(string: "https://github.com/waydabber/BetterDisplay")!
    private static let base = "http://127.0.0.1:55777"

    @Published public private(set) var isInstalled = false
    /// Its HTTP API answered the last check.
    @Published public private(set) var isReachable = false

    private var lastCheck: Date?
    /// Last level read or set per display name, so held keys step smoothly.
    private var levels: [String: (value: Double, at: Date)] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 2
        return URLSession(configuration: config)
    }()

    private init() {}

    /// Looks for the app and pings its API.
    public func refresh() {
        isInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) != nil
        lastCheck = Date()
        guard isInstalled, AppState.shared.useBetterDisplay, let url = URL(string: Self.base + "/") else {
            isReachable = false
            return
        }
        Task {
            // Any HTTP answer means the server is up, whatever it says to "/".
            let reachable = (try? await session.data(from: url))?.1 is HTTPURLResponse
            BetterDisplayService.shared.isReachable = reachable
        }
    }

    /// Whether brightness keys for this screen should go to BetterDisplay.
    public func routes(_ screen: NSScreen) -> Bool {
        if let lastCheck, Date().timeIntervalSince(lastCheck) > 30 { refresh() }
        return AppState.shared.useBetterDisplay && isReachable && !screen.isBuiltIn
    }

    /// Steps the display's brightness through BetterDisplay and shows the HUD.
    public func step(_ screen: NSScreen, by delta: Double, step: Double) {
        let name = screen.localizedName
        Task {
            let current: Double?
            // A level more than a few seconds old may have changed in BetterDisplay itself.
            if let cached = levels[name], Date().timeIntervalSince(cached.at) < 3 {
                current = cached.value
            } else {
                current = await brightness(named: name)
            }
            guard let current else {
                // It stopped answering: fall back to macOS from the next press.
                BetterDisplayService.shared.isReachable = false
                return
            }
            let target = MediaKeyMonitor.steppedVolume(current, by: delta, step: step)
            BetterDisplayService.shared.levels[name] = (target, Date())
            await set(target, named: name)
            if AppState.shared.showBrightnessHUD { AppState.shared.showHUD(.brightness, value: target) }
        }
    }

    private func brightness(named name: String) async -> Double? {
        guard let url = request("get", name: name, extra: "brightness") else { return nil }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let value = Double(text) else { return nil }
        return min(max(value, 0), 1)
    }

    private func set(_ value: Double, named name: String) async {
        guard let url = request("set", name: name, extra: "brightness=\(String(format: "%.4f", value))") else { return }
        _ = try? await session.data(from: url)
    }

    private func request(_ verb: String, name: String, extra: String) -> URL? {
        var components = URLComponents(string: "\(Self.base)/\(verb)")
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        components?.percentEncodedQuery = "name=\(name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name)&\(extra)"
        return components?.url
    }
}
