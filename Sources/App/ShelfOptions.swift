import SwiftUI
import AppKit

// Settings › Shelf: the choices that shape the open shelf and how it behaves.
// The stored values are @AppStorage properties in AppState's class body.

/// The Shelf's size preset (Settings › Shelf › The Shelf).
public enum ShelfSize: String, CaseIterable, Identifiable, Sendable {
    case regular
    case enlarged

    public var id: String { rawValue }

    /// How much the open shelf and everything on it is scaled.
    public var scale: CGFloat {
        switch self {
        case .regular: 1
        case .enlarged: DroppyShelfMetrics.enlargedScale
        }
    }
}

/// Where the page buttons sit while the shelf is open.
public enum ShelfNavigationStyle: String, CaseIterable, Identifiable, Sendable {
    /// Tabs inside the notch wings, at the top of the shelf.
    case regularButtons
    /// One glass capsule floating under the shelf (the reference's default).
    case floatingBar

    public var id: String { rawValue }
}

/// Settings › Shelf › Animation speed: a multiplier over the chosen motion
/// style, so the style keeps its character and only its tempo changes.
public enum ShelfAnimationSpeed: String, CaseIterable, Identifiable, Sendable {
    case turtle, human, cheetah, falcon

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .turtle: "Turtle"
        case .human: "Human"
        case .cheetah: "Cheetah"
        case .falcon: "Falcon"
        }
    }

    public var icon: String {
        switch self {
        case .turtle: "tortoise.fill"
        case .human: "figure.walk"
        case .cheetah: "hare.fill"
        case .falcon: "bird.fill"
        }
    }

    /// Passed to `Animation.speed(_:)`: above 1 plays faster.
    public var multiplier: Double {
        switch self {
        case .turtle: 0.6
        case .human: 1
        case .cheetah: 1.45
        case .falcon: 2.1
        }
    }

    /// Read straight from UserDefaults so DS.Motion can use it without AppState.
    static var current: ShelfAnimationSpeed {
        UserDefaults.standard.string(forKey: "animationSpeed").flatMap(ShelfAnimationSpeed.init(rawValue:)) ?? .human
    }
}

// MARK: - Favorites

/// Settings › Shelf › Favorites › Floating button size.
public enum FloatingButtonSize: String, CaseIterable, Identifiable, Sendable {
    case small, regular, large

    public static let key = "floatingButtonSize"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .small: "Small"
        case .regular: "Regular"
        case .large: "Large"
        }
    }

    public var icon: String {
        switch self {
        case .small: "circle"
        case .regular: "circle.circle"
        case .large: "circle.circle.fill"
        }
    }

    /// Diameter of the round glass buttons under the shelf.
    public var diameter: CGFloat {
        switch self {
        case .small: 26
        case .regular: 30
        case .large: 36
        }
    }

    /// What `DroppyShelfMetrics.floatingButton` reads, so the SwiftUI layout
    /// and `AppState`'s lane-pill geometry always agree.
    static var stored: FloatingButtonSize {
        FloatingButtonSize(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .regular
    }
}

/// Settings › Shelf › Favorites › Floating button style: how each round
/// button under the shelf is painted.
public enum FloatingButtonStyle: String, CaseIterable, Identifiable, Sendable {
    /// Grey glass with the widget's own colour on the symbol.
    case glass
    /// The widget's colour fills the circle; the symbol takes the icon colour.
    case colored
    /// Grey glass, every symbol white.
    case monochrome

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .glass: "Glass"
        case .colored: "Colored"
        case .monochrome: "Monochrome"
        }
    }

    public var icon: String {
        switch self {
        case .glass: "circle.dotted"
        case .colored: "paintpalette.fill"
        case .monochrome: "circle.lefthalf.filled"
        }
    }
}

/// One of up to four buttons beside the floating navigation bar: a widget
/// (Droplet), an app, or a Shortcut from the Shortcuts app. Stored in
/// `shelfFavorites` as "kind:value" tokens separated by newlines.
public struct ShelfFavorite: Hashable, Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case droplet, app, shortcut
    }

    public var kind: Kind
    /// A droplet id, an app bundle's path, or a Shortcut's name.
    public var value: String

    public var id: String { token }
    public var token: String { "\(kind.rawValue):\(value)" }

    public static let limit = 4

    public init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value
    }

    public init?(token: String) {
        guard let colon = token.firstIndex(of: ":"),
              let kind = Kind(rawValue: String(token[..<colon])) else { return nil }
        let value = String(token[token.index(after: colon)...])
        guard !value.isEmpty else { return nil }
        self.init(kind: kind, value: value)
    }

    static func decode(_ stored: String) -> [ShelfFavorite] {
        Array(stored.split(separator: "\n").compactMap { ShelfFavorite(token: String($0)) }.prefix(limit))
    }

    static func encode(_ favorites: [ShelfFavorite]) -> String {
        favorites.prefix(limit).map(\.token).joined(separator: "\n")
    }

    /// The widget's own colour, for Floating button style › Colored. Apps and
    /// Shortcuts keep their real icon, so they have none.
    @MainActor public var tint: Color? {
        kind == .droplet ? DropletPalette.tint(for: value) : nil
    }

    @MainActor public var title: String {
        switch kind {
        case .droplet: return AppState.shared.droplets.first { $0.id == value }?.name ?? "Widget"
        case .app: return FileManager.default.displayName(atPath: value).replacingOccurrences(of: ".app", with: "")
        case .shortcut: return value
        }
    }

    /// Opens the widget on the shelf, launches the app, or runs the Shortcut.
    @MainActor public func run() {
        let state = AppState.shared
        DroppyAudio.playTick()
        switch kind {
        case .droplet:
            guard state.droplets.contains(where: { $0.id == value && $0.isEnabled }) else {
                state.showNotification(appName: "Favorites", title: "\(title) is turned off",
                                       message: "Turn it on in Settings › Shelf › Widget settings.")
                return
            }
            state.open(.widgets)
            withAnimation(DS.Motion.fluid) { state.activeDropletID = value }
        case .app:
            let url = URL(fileURLWithPath: value)
            guard FileManager.default.fileExists(atPath: value) else {
                state.showNotification(appName: "Favorites", title: "App not found", message: url.lastPathComponent)
                return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            state.setIslandExpanded(false)
        case .shortcut:
            ShortcutsLibrary.run(value)
            state.setIslandExpanded(false)
        }
    }
}

/// The user's Shortcuts (Shortcuts.app), through the `shortcuts` command-line tool.
@MainActor
public final class ShortcutsLibrary: ObservableObject {
    public static let shared = ShortcutsLibrary()

    @Published public private(set) var names: [String] = []
    @Published public private(set) var isLoading = false
    nonisolated private static let tool = "/usr/bin/shortcuts"

    private init() {}

    public static var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: tool) }

    /// Lists the Shortcuts off the main thread.
    public func refresh() {
        guard Self.isAvailable, !isLoading else { return }
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let output = Self.capture([ "list" ])
            let names = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            await MainActor.run {
                ShortcutsLibrary.shared.names = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                ShortcutsLibrary.shared.isLoading = false
            }
        }
    }

    /// Runs a Shortcut by name without waiting for it.
    static func run(_ name: String) {
        guard isAvailable else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["run", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            AppState.shared.showNotification(appName: "Favorites", title: "Couldn't run \u{201C}\(name)\u{201D}",
                                             message: error.localizedDescription)
        }
    }

    nonisolated private static func capture(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Contextual buttons

/// A round glass button a page puts beside the navigation bar while it's on
/// screen: ✕ to close a timer, ↗ / ↻ for TermiNotch. Pages register theirs
/// with `.shelfAccessories(…)`; only those matching the page (and open
/// Droplet) on screen are drawn.
public struct ShelfAccessory: Identifiable {
    public let id: String
    public var icon: String
    public var help: String
    public var page: ShelfPage
    /// The Droplet console it belongs to; nil for the page itself.
    public var dropletID: String?
    public var action: @MainActor () -> Void

    public init(id: String, icon: String, help: String, page: ShelfPage, dropletID: String? = nil,
                action: @escaping @MainActor () -> Void) {
        self.id = id
        self.icon = icon
        self.help = help
        self.page = page
        self.dropletID = dropletID
        self.action = action
    }
}

@MainActor
public final class ShelfAccessoryCenter: ObservableObject {
    public static let shared = ShelfAccessoryCenter()

    @Published public private(set) var byOwner: [String: [ShelfAccessory]] = [:]

    private init() {}

    public func set(_ accessories: [ShelfAccessory], for owner: String) {
        byOwner[owner] = accessories.isEmpty ? nil : accessories
        // The navigation bar's width (and so the panel's hit rect) changed.
        AppState.shared.objectWillChange.send()
        AppState.shared.onIslandFrameChange?(AppState.shared.isIslandExpanded)
    }

    public func clear(_ owner: String) {
        guard byOwner[owner] != nil else { return }
        set([], for: owner)
    }

    /// The buttons for what the shelf shows right now.
    public var visible: [ShelfAccessory] {
        let state = AppState.shared
        return byOwner.keys.sorted().flatMap { byOwner[$0] ?? [] }
            .filter { $0.page == state.shelfPage && $0.dropletID == (state.shelfPage == .widgets ? state.activeDropletID : nil) }
    }
}

private struct ShelfAccessoriesModifier: ViewModifier {
    let owner: String
    let accessories: [ShelfAccessory]

    func body(content: Content) -> some View {
        content
            .onAppear { ShelfAccessoryCenter.shared.set(accessories, for: owner) }
            .onDisappear { ShelfAccessoryCenter.shared.clear(owner) }
            .onChange(of: accessories.map(\.id)) { _, _ in ShelfAccessoryCenter.shared.set(accessories, for: owner) }
    }
}

extension View {
    /// Puts round buttons beside the navigation bar under the shelf while this
    /// view is on screen. `owner` must be unique per registering view.
    public func shelfAccessories(_ owner: String, _ accessories: [ShelfAccessory]) -> some View {
        modifier(ShelfAccessoriesModifier(owner: owner, accessories: accessories))
    }
}
