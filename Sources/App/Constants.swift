import SwiftUI
import AppKit

public enum IslandStyle: String, CaseIterable, Identifiable, Sendable {
    case notchAttached = "Notch Attached"
    case floatingPill = "Floating Dynamic Island"
    
    public var id: String { rawValue }
}

public enum DroppyAccentColor: String, CaseIterable, Identifiable, Sendable {
    case electricBlue = "Electric Blue"
    case royalBlue = "Royal Sapphire"
    case neonPurple = "Neon Purple"
    case cyberMint = "Cyber Mint"
    case sunsetAmber = "Sunset Amber"
    case roseQuartz = "Rose Quartz"
    // The reference's named presets.
    case cyan = "Cyan"
    case ember = "Ember"
    case graphite = "Graphite"
    case midnight = "Midnight"
    case mint = "Mint"
    case ocean = "Ocean"
    case twilight = "Twilight"
    /// The hex in `accentCustomHex` (Settings › Theming, last swatch of the tape).
    case custom = "Custom"

    public var id: String { rawValue }

    /// UserDefaults key of the custom accent's hex ("#RRGGBB").
    public static let customHexKey = "accentCustomHex"

    public var color: Color {
        switch self {
        case .electricBlue: return Color(red: 31/255, green: 92/255, blue: 201/255)
        case .royalBlue: return Color(red: 21/255, green: 58/255, blue: 164/255)
        case .neonPurple: return Color(red: 165/255, green: 75/255, blue: 245/255)
        case .cyberMint: return Color(red: 45/255, green: 215/255, blue: 130/255)
        case .sunsetAmber: return Color(red: 245/255, green: 130/255, blue: 32/255)
        case .roseQuartz: return Color(red: 255/255, green: 75/255, blue: 115/255)
        case .cyan: return Color(red: 50/255, green: 190/255, blue: 230/255)
        case .ember: return Color(red: 230/255, green: 88/255, blue: 60/255)
        case .graphite: return Color(red: 142/255, green: 146/255, blue: 156/255)
        case .midnight: return Color(red: 70/255, green: 82/255, blue: 190/255)
        case .mint: return Color(red: 90/255, green: 220/255, blue: 190/255)
        case .ocean: return Color(red: 20/255, green: 130/255, blue: 200/255)
        case .twilight: return Color(red: 150/255, green: 100/255, blue: 220/255)
        case .custom:
            let hex = UserDefaults.standard.string(forKey: Self.customHexKey) ?? ""
            return Color(hex: hex) ?? DroppyAccentColor.electricBlue.color
        }
    }
}

// MARK: - Colours from hex

public extension Color {
    /// "#RRGGBB" or "RRGGBB"; nil for anything else.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    /// "#RRGGBB" in sRGB, for storing a picked colour.
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Tape palette

/// The swatches of Settings › Theming's colour tapes. A stored tape value is
/// "" (Tama's default), one of these ids, or a custom "#RRGGBB".
public enum TapePalette {
    public static let swatches: [(id: String, name: String, hex: String)] = [
        ("rose", "Rose", "#FF4B73"), ("red", "Red", "#F0453A"), ("ember", "Ember", "#E6583C"),
        ("orange", "Orange", "#F58220"), ("amber", "Amber", "#F5B82E"), ("yellow", "Yellow", "#F2D43D"),
        ("lime", "Lime", "#A4DA3E"), ("green", "Green", "#34C759"), ("mint", "Mint", "#5ADCBE"),
        ("teal", "Teal", "#30B0C7"), ("cyan", "Cyan", "#32BEE6"), ("sky", "Sky", "#5AA9F5"),
        ("blue", "Blue", "#1F5CC9"), ("indigo", "Indigo", "#5856D6"), ("violet", "Violet", "#8E5CF0"),
        ("purple", "Purple", "#A54BF5"), ("pink", "Pink", "#F25CB8"), ("graphite", "Graphite", "#8E929C"),
    ]

    /// nil for "" (default) or anything unreadable.
    public static func color(for value: String) -> Color? {
        if value.hasPrefix("#") { return Color(hex: value) }
        return swatches.first { $0.id == value }.flatMap { Color(hex: $0.hex) }
    }
}

// MARK: - Surface

/// How the island and the shelf are painted, chosen per display class in
/// Settings › Theming. The notch-attached shape offers Dynamic Glass and
/// Black; the floating pill on notchless screens adds Liquid Glass.
public enum IslandSurfaceStyle: String, CaseIterable, Identifiable, Sendable {
    /// Black under the bezel, fading into glass along the bottom edge, with a hairline rim.
    case dynamicGlass
    /// Solid black.
    case black
    /// Tinted glass all over.
    case liquidGlass

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dynamicGlass: "Dynamic Glass"
        case .black: "Black"
        case .liquidGlass: "Liquid Glass"
        }
    }

    public func subtitle(notched: Bool) -> String {
        switch self {
        case .dynamicGlass: "Black fading into Liquid Glass"
        case .black: notched ? "Matches the physical notch" : "Classic solid black"
        case .liquidGlass: "Tinted Liquid Glass"
        }
    }

    public static let notchedChoices: [IslandSurfaceStyle] = [.dynamicGlass, .black]
    public static let notchlessChoices: [IslandSurfaceStyle] = [.dynamicGlass, .black, .liquidGlass]
}

public enum LiveActivityMode: String, CaseIterable, Identifiable, Sendable {
    case mediaAndFocus = "Now Playing & Focus"
    case systemTelemetry = "Hardware Telemetry"
    case pomodoroCountdown = "Pomodoro Timer"
    
    public var id: String { rawValue }
}

public enum DisplayTargetMode: String, CaseIterable, Identifiable, Sendable {
    case main = "Main Display (macOS Primary)"
    case builtIn = "Built-in Display (MacBook)"
    case external = "External Monitor"
    case active = "Follow Active Window / Mouse"
    case all = "All Displays"

    /// Modes where the live island moves to the screen under the pointer.
    public var followsPointer: Bool { self == .active || self == .all }
    
    public var id: String { rawValue }
}

// MARK: - Level HUD

/// How the volume / brightness meter is filled.
public enum HUDMeterStyle: String, CaseIterable, Identifiable, Sendable {
    case white = "White"
    case accent = "Accent"
    /// Green when quiet, through amber, to red when loud — with a glow.
    case decibel = "Decibel"
    /// A colour picked on the Theming tape; its hex is stored per HUD kind.
    case custom = "Custom"

    public var id: String { rawValue }

    /// The styles offered as picture tiles on the HUD pages (Custom comes from Theming).
    public static let tileChoices: [HUDMeterStyle] = [.white, .accent, .decibel]

    /// The fill for a level; `accent` is the user's accent, resolved by the caller,
    /// and `custom` the picked colour for `.custom`.
    public func color(for value: Double, accent: Color, custom: Color? = nil) -> Color {
        switch self {
        case .white: return .white
        case .accent: return accent
        case .custom: return custom ?? accent
        case .decibel:
            // Like a VU meter: green through most of the range, amber near
            // the top, red only at the very end.
            let v = min(max(value, 0), 1)
            let hue: Double
            if v <= 0.7 {
                hue = 0.30
            } else if v <= 0.88 {
                hue = 0.30 - (v - 0.7) / 0.18 * 0.22   // green → amber
            } else {
                hue = 0.08 - (v - 0.88) / 0.12 * 0.08  // amber → red
            }
            return Color(hue: hue, saturation: 0.7, brightness: 1)
        }
    }
}

/// How quickly the meter follows a new level.
public enum HUDAnimation: String, CaseIterable, Identifiable, Sendable {
    case smooth = "Smooth"
    case fast = "Fast"
    case instant = "Instant"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .smooth: return "tortoise.fill"
        case .fast: return "hare.fill"
        case .instant: return "bolt.fill"
        }
    }

    public var animation: Animation? {
        switch self {
        case .smooth: return .spring(response: 0.42, dampingFraction: 0.86)
        case .fast: return .easeOut(duration: 0.12)
        case .instant: return nil
        }
    }
}

/// What leads the volume HUD: the speaker symbol, or the output device.
public enum HUDLeading: String, CaseIterable, Identifiable, Sendable {
    case symbol = "Show symbol"
    case device = "Show device"

    public var id: String { rawValue }
}

/// How the island moves when it opens and closes.
public enum IslandMotionStyle: String, CaseIterable, Identifiable, Sendable {
    case dynamicIsland = "Dynamic Island"
    case snappy = "Snappy"
    case gentle = "Gentle"
    case minimal = "Minimal"

    public var id: String { rawValue }

    public var summary: String {
        switch self {
        case .dynamicIsland: return "Stretches sideways, drops with a soft bounce; content follows a beat later."
        case .snappy: return "Quick and firm, barely any bounce."
        case .gentle: return "Slower and softer, a relaxed float."
        case .minimal: return "A short fade and resize, no bounce."
        }
    }

    static var current: IslandMotionStyle {
        UserDefaults.standard.string(forKey: "islandMotionStyle").flatMap(IslandMotionStyle.init(rawValue:)) ?? .dynamicIsland
    }
}

/// The page the shelf shows each time it opens.
public enum DefaultShelfPage: String, CaseIterable, Identifiable, Sendable {
    case home, tray, widgets, calendar, lastUsed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lastUsed: return "Last used page"
        default: return page?.title ?? ""
        }
    }

    /// nil keeps whatever page was open last.
    public var page: ShelfPage? {
        switch self {
        case .home: return .home
        case .tray: return .tray
        case .widgets: return .widgets
        case .calendar: return .calendar
        case .lastUsed: return nil
        }
    }
}


// MARK: - Island

/// The island's state machine (spec §16.6). Hovering and a nearby file drag are
/// not modes of their own: they only nudge the resting geometry.
public enum IslandMode: Equatable, Sendable {
    case resting
    case hud
    case notification
    case dropTarget
    case shelf

    /// The big shape: the shelf or the drop tiles.
    public var isOpen: Bool { self == .shelf || self == .dropTarget }

    /// Higher cases win: a drag over the notch beats everything, a banner
    /// beats a volume HUD.
    static func resolve(isDragHovering: Bool, isExpanded: Bool, hasNotification: Bool, hasHUD: Bool) -> IslandMode {
        if isDragHovering { return .dropTarget }
        if isExpanded { return .shelf }
        if hasNotification { return .notification }
        if hasHUD { return .hud }
        return .resting
    }
}

/// Everything about the island's outline, animated as one value.
public struct IslandGeometry: Equatable, Sendable {
    public var size: CGSize
    public var cornerRadius: CGFloat
    public var earRadius: CGFloat
}

// MARK: - Shelf

/// What the open shelf is showing. Like Tama, the shelf shows one page at a
/// time and a floating lane pill underneath it switches between them.
public enum ShelfPage: String, CaseIterable, Identifiable, Sendable {
    case home
    case tray
    case widgets
    case calendar

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: return "Now Playing"
        case .tray: return "Tray"
        case .widgets: return "Widgets"
        case .calendar: return "Tasks & Calendar"
        }
    }

    public var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .tray: return "tray.fill"
        case .widgets: return "square.grid.2x2.fill"
        case .calendar: return "calendar.badge.clock"
        }
    }
}

