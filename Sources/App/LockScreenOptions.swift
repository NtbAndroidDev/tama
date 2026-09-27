import AppKit

// Settings › Lock screen choices.

/// A sound played the moment the screen locks or unlocks. "Default" is the
/// system's own padlock sound (SecurityInterface); the rest are the sounds
/// in /System/Library/Sounds. Nothing is bundled with Tama.
public enum LockSound {
    public static let none = "none"
    public static let `default` = "default"

    /// Choices for the pickers: None, Default, then the system sounds.
    public static var choices: [String] {
        let dir = URL(fileURLWithPath: "/System/Library/Sounds")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasSuffix(".aiff") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted()
        return [none, `default`] + names
    }

    public static func title(_ id: String) -> String {
        switch id {
        case none: "None"
        case `default`: "Default"
        default: id
        }
    }

    /// The sound for a choice; `locking` picks the Default's lock or unlock half.
    @MainActor
    public static func sound(_ id: String, locking: Bool) -> NSSound? {
        switch id {
        case none:
            return nil
        case `default`:
            let base = "/System/Library/Frameworks/SecurityInterface.framework/Versions/A/Resources/"
            let path = base + (locking ? "lock.aif" : "unlock.aif")
            return NSSound(contentsOfFile: path, byReference: true) ?? NSSound(named: locking ? "Pop" : "Glass")
        default:
            return NSSound(named: id)
        }
    }

    @MainActor
    public static func play(_ id: String, locking: Bool) {
        guard let sound = sound(id, locking: locking) else { return }
        sound.stop()
        sound.play()
    }
}

/// How the lock-screen status widgets are laid out.
public enum LockWidgetStyle: String, CaseIterable, Identifiable, Sendable {
    /// Icon, value and detail in one line on the wallpaper (Tama's original).
    case inline
    /// Icon over value over detail, in columns.
    case vertical
    /// Each widget in its own rounded tile.
    case rounded

    public var id: Self { self }
    public var title: String {
        switch self {
        case .inline: "Inline"
        case .vertical: "Vertical"
        case .rounded: "Rounded"
        }
    }
}

/// Light or dark widgets.
public enum LockWidgetLook: String, CaseIterable, Identifiable, Sendable {
    case light, dark
    public var id: Self { self }
    public var title: String { self == .light ? "Light" : "Dark" }
}

/// What the rounded widgets (and the media HUD) are made of.
public enum LockSurfaceMaterial: String, CaseIterable, Identifiable, Sendable {
    /// Translucent dark, like before.
    case dark
    /// A frosted blur of the wallpaper.
    case regular
    /// Frosted, with a glass sheen and rim.
    case liquid

    public var id: Self { self }
    public var title: String {
        switch self {
        case .dark: "Dark"
        case .regular: "Regular"
        case .liquid: "Liquid"
        }
    }
}

/// Settings › Lock screen › Keep awake: minutes the display stays on while
/// locked; 0 is Off, -1 as long as it's locked.
public enum LockKeepAwake {
    public static let stops = [0, 1, 2, 5, 10, 15, 30, 60, -1]

    public static func title(_ minutes: Int) -> String {
        switch minutes {
        case 0: "Off"
        case -1: "Always"
        case 60: "1 hr"
        default: "\(minutes) min"
        }
    }

    public static func index(of minutes: Int) -> Int { stops.firstIndex(of: minutes) ?? 0 }
}
