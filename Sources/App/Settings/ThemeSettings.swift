import SwiftUI

/// Settings › Theming: accent, surfaces, outline and window tint.
@MainActor
public final class ThemeSettings: SettingsStore {
    public static let shared = ThemeSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "accentColor", "borderGlowIntensity", "notchEarFilletRadius", "notchedSurfaceStyle",
        "notchlessSurfaceStyle", "subtleOutline", "outlineInRestingState",
        "solidSettingsBackground", "windowTint"
    ]

    @AppStorage("accentColor") public var accentColor: DroppyAccentColor = .electricBlue
    @AppStorage("borderGlowIntensity") public var borderGlowIntensity: Double = 0.8
    @AppStorage("notchEarFilletRadius") public var notchEarFilletRadius: Double = 12.0
    /// Surface of the notch-attached island and shelf on screens with a notch.
    @AppStorage("notchedSurfaceStyle") public var notchedSurfaceStyle: IslandSurfaceStyle = .dynamicGlass
    /// Surface of the floating island and shelf on screens without one.
    @AppStorage("notchlessSurfaceStyle") public var notchlessSurfaceStyle: IslandSurfaceStyle = .dynamicGlass
    /// A hairline around the surface, so black stays visible on dark wallpapers.
    @AppStorage("subtleOutline") public var subtleOutline: Bool = false
    /// The outline is drawn on the resting island too, not just when it opens.
    @AppStorage("outlineInRestingState") public var outlineInRestingState: Bool = false
    /// Settings › Theming › Settings window: paint this window opaque instead
    /// of translucent glass.
    @AppStorage("solidSettingsBackground") public var solidSettingsBackground: Bool = false
    /// Tint washed over Settings and the glass surfaces: "" (default), a
    /// `TapePalette` id, or "#RRGGBB".
    @AppStorage("windowTint") public var windowTint: String = ""

    /// Window tint, resolved.
    public var windowTintColor: Color? { TapePalette.color(for: windowTint) }

    private init() { super.init(keys: Self.keys) }
}
