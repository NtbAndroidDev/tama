import SwiftUI
import AppKit

/// The shared state of the guide window, so opening it on a topic works
/// whether or not the window already exists.
@MainActor
final class UserGuideModel: ObservableObject {
    @Published var query: String = ""
    @Published var selection: String = DroppyGuide.articles.first?.id ?? ""

    func select(_ article: GuideArticle) { selection = article.id }
}

/// Settings › About › User Guide, the menu bar and the notch's right-click
/// menu all open this one window.
@MainActor
public final class UserGuideWindowController: NSObject, NSWindowDelegate {
    public static let shared = UserGuideWindowController()

    private var window: NSWindow?
    private let model = UserGuideModel()

    private override init() { super.init() }

    /// Opens the guide, optionally on a topic (a `GuideArticle` id) and with
    /// the words that led there still in the search field, so they stay
    /// picked out in the article.
    func show(topic: String? = nil, query: String? = nil) {
        if let query { model.query = query }
        if let topic, DroppyGuide.article(topic) != nil {
            if query == nil { model.query = "" }
            model.selection = topic
        }
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Tama Guide"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.appearance = NSAppearance(named: .darkAqua)
            window.minSize = NSSize(width: 760, height: 480)
            window.isReleasedWhenClosed = false
            window.delegate = self
            let host = NSHostingView(rootView: UserGuideView(model: model))
            // The window sets its own frame and minSize, so SwiftUI must not also
            // push content-size extrema onto it — that feedback is what AppKit
            // aborts with an "Update Constraints in Window" throw.
            host.sizingOptions = []
            window.contentView = host
            window.setFrameAutosaveName("TamaUserGuide")
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens the guide on whatever a query finds, for a Settings search that
    /// came up empty.
    func search(_ query: String) {
        model.query = query
        if let first = DroppyGuide.articles.first(where: { $0.matches(query) }) {
            model.selection = first.id
        }
        show()
    }

    /// Esc closes it, like every other Tama panel.
    public func windowDidBecomeKey(_ notification: Notification) {
        window?.standardWindowButton(.closeButton)?.isEnabled = true
    }

    /// The shelf page you are looking at, so a Help button lands on the
    /// article that describes it rather than the front page.
    static func topic(for page: ShelfPage) -> String {
        switch page {
        case .home: "player"
        case .tray: "tray"
        case .widgets: "droplets"
        case .calendar: "calendar"
        }
    }
}
