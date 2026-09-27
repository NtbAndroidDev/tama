import AppKit

/// The `tama://` URL scheme (registered in Info.plist), for launchers and
/// scripts such as the bundled Alfred workflow:
///
///     tama://add?target=shelf&path=/Users/me/a.pdf&path=/Users/me/b.png
///     tama://add?target=basket&path=…
///     tama://show?target=shelf|basket|clipboard|calendar|guide|tour|settings|<droplet id>
///     tama://settings?page=general|droplets|shortcuts|shelf|basket|clipboard|…
///     tama://settings?page=droplets&droplet=<droplet id>
///
/// `path` may repeat, or hold several paths separated by newlines or tabs.
@MainActor
enum URLSchemeHandler {
    static func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "tama",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let command = (components.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        let query = components.queryItems ?? []
        let target = query.first { $0.name == "target" }?.value?.lowercased() ?? "shelf"
        let state = AppState.shared
        switch command {
        case "add":
            let paths = query.filter { $0.name == "path" }
                .compactMap(\.value)
                .flatMap { $0.split(whereSeparator: { $0 == "\n" || $0 == "\t" }).map(String.init) }
                .map { ($0 as NSString).expandingTildeInPath }
                .filter { FileManager.default.fileExists(atPath: $0) }
            guard !paths.isEmpty else {
                state.showNotification(appName: "Tama", title: "Nothing to add",
                                       message: "The link didn't name any file that exists.", icon: "questionmark.folder")
                return
            }
            add(paths.map { ShelfItem(url: URL(fileURLWithPath: $0)) }, to: target)
        case "show", "open":
            switch target {
            case "basket": state.showBasket(nearPointer: false)
            case "clipboard": state.showClipboard()
            case "calendar", "tasks":
                state.open(.calendar)
                NotchWindowController.shared.focusPanel()
            case "guide", "help":
                UserGuideWindowController.shared.show()
            case "tour", "onboarding", "introduction":
                OnboardingWindowController.shared.show()
            case "settings", "preferences":
                openSettings(page: query.first { $0.name == "page" }?.value,
                             droplet: query.first { $0.name == "droplet" }?.value)
            case let id where state.droplets.contains { $0.id.lowercased() == id && $0.isEnabled }:
                // tama://show?target=pomodoro opens that widget's console.
                state.open(.widgets)
                state.activeDropletID = state.droplets.first { $0.id.lowercased() == id }?.id
                NotchWindowController.shared.focusPanel()
            default:
                state.open(.tray)
                NotchWindowController.shared.focusPanel()
            }
        case "settings", "preferences":
            openSettings(page: query.first { $0.name == "page" }?.value ?? target,
                         droplet: query.first { $0.name == "droplet" }?.value)
        default:
            state.showNotification(appName: "Tama", title: "Unknown link",
                                   message: "tama://\(command) isn't something Tama knows.", icon: "questionmark.circle")
        }
    }

    /// `tama://settings?page=droplets`, and `tama://show?target=settings`.
    /// An unknown page name just opens Settings where it was left.
    private static func openSettings(page: String?, droplet: String? = nil) {
        if let page, let match = SettingsPage.allCases.first(where: { $0.rawValue.lowercased() == page.lowercased() }) {
            SettingsWindowController.shared.showWindow(page: match)
        } else {
            SettingsWindowController.shared.showWindow()
        }
        // `&droplet=weather` opens that droplet's page in the store.
        if let droplet, let match = AppState.shared.droplets.first(where: { $0.id.lowercased() == droplet.lowercased() }) {
            SettingsNavigator.shared.page = .droplets
            SettingsNavigator.shared.openDropletID = match.id
        }
    }

    /// Shared by the URL scheme and the Finder Services.
    static func add(_ items: [ShelfItem], to target: String) {
        let state = AppState.shared
        if target == "basket" {
            let id = state.primaryBasketID ?? state.spawnBasket(nearPointer: false)
            state.addBasketItems(items, to: id)
            state.showBasket(nearPointer: false)
        } else {
            state.addShelfItems(items, reveal: true)
        }
        DroppyAudio.playDropSuccess()
    }
}
