import AppKit
import SwiftUI

/// Everything the Ring can hold. Raw values are persisted; don't rename them.
public enum RingAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case openShelf, tray, clipboard, snipToTray, toggleBasket, highAlert, pomodoro
    case snapLeft, snapRight, snapMaximize, colorDropper, search, playPause, settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .openShelf: return "Open Shelf"
        case .tray: return "Tray"
        case .clipboard: return "Clipboard"
        case .snipToTray: return "Snip to Tray"
        case .toggleBasket: return "Basket"
        case .highAlert: return "High Alert"
        case .pomodoro: return "Pomodoro"
        case .snapLeft: return "Snap Left"
        case .snapRight: return "Snap Right"
        case .snapMaximize: return "Maximize"
        case .colorDropper: return "Color Dropper"
        case .search: return "Search"
        case .playPause: return "Play / Pause"
        case .settings: return "Settings"
        }
    }

    /// State-aware, so the ring shows what the click will do.
    @MainActor public var currentTitle: String {
        switch self {
        case .highAlert: return SleepBlockerService.shared.isAwakeActive ? "Stay Awake Off" : "High Alert"
        case .pomodoro: return AppState.shared.isPomodoroActive ? "Pause Focus" : "Start Focus"
        case .toggleBasket: return AppState.shared.isBasketVisible ? "Hide Basket" : "Show Basket"
        default: return title
        }
    }

    public var systemImage: String {
        switch self {
        case .openShelf: return "rectangle.topthird.inset.filled"
        case .tray: return "tray.fill"
        case .clipboard: return "list.clipboard.fill"
        case .snipToTray: return "camera.viewfinder"
        case .toggleBasket: return "basket.fill"
        case .highAlert: return "cup.and.saucer.fill"
        case .pomodoro: return "timer"
        case .snapLeft: return "rectangle.lefthalf.filled"
        case .snapRight: return "rectangle.righthalf.filled"
        case .snapMaximize: return "arrow.up.left.and.arrow.down.right"
        case .colorDropper: return "eyedropper.halffull"
        case .search: return "bolt.fill"
        case .playPause: return "playpause.fill"
        case .settings: return "gearshape.fill"
        }
    }

    @MainActor public func perform() {
        let state = AppState.shared
        switch self {
        case .openShelf:
            state.open(.home)
            NotchWindowController.shared.focusPanel()
        case .tray:
            state.open(.tray)
            NotchWindowController.shared.focusPanel()
        case .clipboard:
            state.showClipboard()
        case .snipToTray:
            TrayActions.snipToTray()
        case .toggleBasket:
            state.isBasketVisible.toggle()
        case .highAlert:
            SleepBlockerService.shared.toggleIndefinite()
        case .pomodoro:
            if state.isPomodoroActive { state.pausePomodoro() } else { state.startPomodoro() }
        case .snapLeft: Self.snap("leftHalf", "Left Half")
        case .snapRight: Self.snap("rightHalf", "Right Half")
        case .snapMaximize: Self.snap("maximize", "Maximize")
        case .colorDropper:
            Self.sampleColor()
        case .search:
            guard state.droplets.contains(where: { $0.id == "thunderstorm" && $0.isEnabled }) else {
                state.showNotification(appName: "Thunderstorm", title: "Search is turned off",
                                       message: "Turn on the Thunderstorm Droplet in Settings.")
                return
            }
            state.open(.widgets)
            state.activeDropletID = "thunderstorm"
            NotchWindowController.shared.focusPanel()
        case .playPause:
            MediaService.shared.togglePlayPause()
        case .settings:
            SettingsWindowController.shared.showWindow()
        }
    }

    @MainActor private static func snap(_ preset: String, _ title: String) {
        do {
            let app = try WindowSnapService.shared.snap(preset)
            AppState.shared.showNotification(appName: "Window Snap", title: "Window Positioned", message: "\(app) → \(title)")
        } catch {
            AppState.shared.showNotification(appName: "Window Snap", title: "Couldn't snap", message: error.localizedDescription)
        }
    }

    /// Same result as the Color Dropper console: hex on the clipboard, in
    /// Tama's history and at the front of the recent swatches.
    @MainActor private static func sampleColor() {
        NSColorSampler().show { picked in
            guard let hex = picked?.sRGBHex else { return }
            DispatchQueue.main.async {
                var swatches = UserDefaults.standard.stringArray(forKey: "colorSwatches") ?? []
                swatches.removeAll { $0 == hex }
                swatches.insert(hex, at: 0)
                UserDefaults.standard.set(Array(swatches.prefix(8)), forKey: "colorSwatches")
                ClipboardService.shared.copyToPasteboard(text: hex)
                ClipboardService.shared.onNewItem?(ClipboardItem(content: hex, type: .color))
                DroppyAudio.playCopySuccess()
                AppState.shared.showNotification(appName: "Color Dropper", title: "Hex Copied", message: "\(hex) copied to clipboard")
            }
        }
    }
}

/// The user's ring, in order. At most `maxCount`, persisted as JSON.
@MainActor
public final class RingActionStore: ObservableObject {
    public static let shared = RingActionStore()
    public static let maxCount = 8
    public static let minCount = 2
    private static let key = "ringActions"

    public static let defaults: [RingAction] = [
        .openShelf, .tray, .clipboard, .snipToTray, .search, .playPause, .snapLeft, .snapRight,
    ]

    @Published public var actions: [RingAction] {
        didSet {
            guard actions != oldValue else { return }
            if let data = try? JSONEncoder().encode(actions.map(\.rawValue)) {
                UserDefaults.standard.set(data, forKey: Self.key)
            }
        }
    }

    private init() {
        actions = Self.stored() ?? Self.defaults
    }

    /// The stored ring, or nil when there is none to read.
    private static func stored() -> [RingAction]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        // Decoded as strings so an action dropped in a later version doesn't discard the rest.
        let saved = ((try? JSONDecoder().decode([String].self, from: data)) ?? []).compactMap(RingAction.init(rawValue:))
        guard saved.count >= minCount else { return nil }
        return Array(saved.prefix(maxCount))
    }

    /// Re-reads the ring after Reset to Defaults or Import Settings.
    public func reloadFromDefaults() {
        actions = Self.stored() ?? Self.defaults
    }

    public func add(_ action: RingAction) {
        guard actions.count < Self.maxCount, !actions.contains(action) else { return }
        actions.append(action)
    }

    public func remove(_ action: RingAction) {
        guard actions.count > Self.minCount else { return }
        actions.removeAll { $0 == action }
    }

    public func move(_ action: RingAction, by offset: Int) {
        guard let index = actions.firstIndex(of: action) else { return }
        let target = index + offset
        guard actions.indices.contains(target) else { return }
        actions.swapAt(index, target)
    }

    public func reset() { actions = Self.defaults }
}
