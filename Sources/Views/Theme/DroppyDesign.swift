import SwiftUI
import AppKit

// MARK: - Tama Design System
// Single source of truth for spacing, radius, type, color, elevation and motion.
// Everything in the UI layer reads from here instead of hard-coding values.

public enum DS {

    // MARK: Spacing (4pt base grid)
    public enum Space {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 6
        public static let md: CGFloat = 10
        public static let lg: CGFloat = 14
        public static let xl: CGFloat = 20
        public static let xxl: CGFloat = 28
    }

    // MARK: Corner radii
    public enum Radius {
        public static let xs: CGFloat = 6
        public static let sm: CGFloat = 9
        public static let md: CGFloat = 13
        public static let lg: CGFloat = 18
        public static let xl: CGFloat = 24
        public static let card: CGFloat = 16
    }

    // MARK: Type ramp
    public enum Typo {
        public static let title = Font.system(size: 13, weight: .semibold)
        public static let headline = Font.system(size: 12, weight: .semibold)
        public static let body = Font.system(size: 12, weight: .regular)
        public static let label = Font.system(size: 11, weight: .medium)
        public static let labelStrong = Font.system(size: 11, weight: .semibold)
        public static let caption = Font.system(size: 10, weight: .medium)
        public static let micro = Font.system(size: 9, weight: .semibold)
        public static let numeric = Font.system(size: 11, weight: .semibold, design: .rounded)
        public static let numericSmall = Font.system(size: 9, weight: .bold, design: .rounded)
        public static let mono = Font.system(size: 10, weight: .medium, design: .monospaced)
    }

    // MARK: Color ramp — cool neutral glass over a near-black island
    public enum Palette {
        public static let ink = Color(red: 0.039, green: 0.051, blue: 0.078)

        /// Barely-there wash used inside dashed drop zones.
        public static let surfaceGhost = Color.white.opacity(0.035)
        public static let surface1 = Color.white.opacity(0.055)
        public static let surface2 = Color.white.opacity(0.085)
        public static let surface3 = Color.white.opacity(0.130)
        public static let surfaceSunken = Color.black.opacity(0.28)

        public static let hairline = Color.white.opacity(0.10)
        /// Unfilled part of a meter, scrubber or progress bar.
        public static let track = Color.white.opacity(0.12)
        public static let hairlineStrong = Color.white.opacity(0.20)

        public static let textPrimary = Color.white.opacity(0.94)
        public static let textSecondary = Color.white.opacity(0.60)
        public static let textTertiary = Color.white.opacity(0.38)

        public static let success = Color(red: 0.19, green: 0.82, blue: 0.45)
        public static let warning = Color(red: 0.98, green: 0.65, blue: 0.19)
        public static let danger = Color(red: 0.96, green: 0.33, blue: 0.36)
        public static let info = Color(red: 0.31, green: 0.62, blue: 0.99)
    }

    // MARK: Accent (user-configurable, resolved at draw time)
    @MainActor public static var accent: Color { ThemeSettings.shared.accentColor.color }
    @MainActor public static var accentSoft: Color { ThemeSettings.shared.accentColor.color.opacity(0.18) }
    @MainActor public static var accentHairline: Color { ThemeSettings.shared.accentColor.color.opacity(0.45) }
    @MainActor public static var glow: Color {
        ThemeSettings.shared.accentColor.color.opacity(0.32 * ThemeSettings.shared.borderGlowIntensity)
    }

    // MARK: Motion
    public enum Motion {
        /// Short, decisive — presses, chips, toggles.
        public static let snap = Animation.spring(response: 0.26, dampingFraction: 0.86)
        /// Default for layout changes inside the stack.
        public static let fluid = Animation.spring(response: 0.38, dampingFraction: 0.80)
        /// Container growth / card disclosure.
        public static let disclose = Animation.spring(response: 0.42, dampingFraction: 0.86)
        /// Hover elevation.
        public static let hover = Animation.spring(response: 0.20, dampingFraction: 0.85)

        // MARK: Island morph
        // Tuned frame-by-frame against Alcove at 60 fps. The shape and the content
        // inside it ride the *same* spring: content is already there, small and
        // blurred, while the shape grows, and lands sharp as the shape settles.
        // Both are springs, so an interrupted open/close retargets smoothly.

        // Every island spring follows Settings › Dynamic Island › Motion.
        private static func spring(_ response: Double, _ damping: Double) -> Animation {
            .spring(response: response, dampingFraction: damping)
        }
        private static var style: IslandMotionStyle { .current }

        /// Opening: grows out of the notch with a soft overshoot and settles;
        /// content follows on its own clock (see IslandLayer).
        private static var morphOpenBase: Animation {
            switch style {
            case .dynamicIsland: return spring(0.44, 0.74)
            case .snappy: return spring(0.3, 0.86)
            case .gentle: return spring(0.56, 0.8)
            case .minimal: return .easeOut(duration: 0.2)
            }
        }
        /// Closing: quicker, tucking back into the bezel with a small give.
        private static var morphCloseBase: Animation {
            switch style {
            case .dynamicIsland: return spring(0.36, 0.85)
            case .snappy: return spring(0.24, 0.95)
            case .gentle: return spring(0.46, 0.9)
            case .minimal: return .easeOut(duration: 0.16)
            }
        }

        // The island's outline, axis by axis, like the Dynamic Island: opening
        // stretches sideways first and drops down after with a soft bounce;
        // closing lifts first and draws in its sides after.
        private static var islandWidthOpenBase: Animation {
            switch style {
            case .dynamicIsland: return spring(0.38, 0.74)
            case .snappy: return spring(0.28, 0.86)
            case .gentle: return spring(0.5, 0.8)
            case .minimal: return .easeOut(duration: 0.2)
            }
        }
        private static var islandHeightOpenBase: Animation {
            switch style {
            case .dynamicIsland: return spring(0.5, 0.72)
            case .snappy: return spring(0.32, 0.86)
            case .gentle: return spring(0.62, 0.78)
            case .minimal: return .easeOut(duration: 0.2)
            }
        }
        private static var islandHeightCloseBase: Animation {
            switch style {
            case .dynamicIsland: return spring(0.3, 0.86)
            case .snappy: return spring(0.22, 0.95)
            case .gentle: return spring(0.4, 0.9)
            case .minimal: return .easeOut(duration: 0.16)
            }
        }
        private static var islandWidthCloseBase: Animation {
            switch style {
            case .dynamicIsland: return spring(0.42, 0.82)
            case .snappy: return spring(0.26, 0.95)
            case .gentle: return spring(0.5, 0.88)
            case .minimal: return .easeOut(duration: 0.16)
            }
        }
        /// Content arriving in the island, a beat after the shape starts.
        private static var islandContentInBase: Animation {
            switch style {
            case .dynamicIsland: return spring(0.34, 0.86).delay(0.07)
            case .snappy: return spring(0.24, 0.92).delay(0.03)
            case .gentle: return spring(0.44, 0.88).delay(0.1)
            case .minimal: return .easeOut(duration: 0.15)
            }
        }
        /// Content leaving, before the shape has shrunk around it.
        private static var islandContentOutBase: Animation {
            style == .gentle ? .easeOut(duration: 0.18) : .easeOut(duration: 0.13)
        }

        // Settings › Shelf › Animation speed retimes every island spring above
        // without changing its style (Turtle … Falcon).
        private static var tempo: Double { ShelfAnimationSpeed.current.multiplier }
        public static var morphOpen: Animation { morphOpenBase.speed(tempo) }
        public static var morphClose: Animation { morphCloseBase.speed(tempo) }
        public static var islandWidthOpen: Animation { islandWidthOpenBase.speed(tempo) }
        public static var islandHeightOpen: Animation { islandHeightOpenBase.speed(tempo) }
        public static var islandHeightClose: Animation { islandHeightCloseBase.speed(tempo) }
        public static var islandWidthClose: Animation { islandWidthCloseBase.speed(tempo) }
        public static var islandContentIn: Animation { islandContentInBase.speed(tempo) }
        public static var islandContentOut: Animation { islandContentOutBase.speed(tempo) }

        // MARK: Reduce Motion
        // Views read `accessibilityReduceMotion` from the environment and pass it
        // in; code without an environment (services, AppKit) reads the system flag.

        /// The system's Reduce Motion setting, for code that has no SwiftUI environment.
        @MainActor public static var reduceMotion: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        /// `animation`, or nil (no animation) when Reduce Motion is on.
        public static func respecting(_ reduce: Bool, _ animation: Animation) -> Animation? {
            reduce ? nil : animation
        }
        /// `transition`, or a plain cross-fade when Reduce Motion is on.
        public static func transition(_ reduce: Bool, _ transition: AnyTransition) -> AnyTransition {
            reduce ? .opacity : transition
        }
    }

    // MARK: Elevation
    public struct Shadow: Sendable {
        public let color: Color
        public let radius: CGFloat
        public let y: CGFloat

        public static let none = Shadow(color: .clear, radius: 0, y: 0)
        public static let low = Shadow(color: Color.black.opacity(0.24), radius: 5, y: 2)
        public static let mid = Shadow(color: Color.black.opacity(0.32), radius: 12, y: 5)
        public static let high = Shadow(color: Color.black.opacity(0.42), radius: 22, y: 10)
    }
}

// MARK: - Reusable surface

public extension View {
    /// Standard raised panel used by every card in the stack.
    func dsSurface(
        _ level: Int = 1,
        radius: CGFloat = DS.Radius.card,
        border: Bool = true,
        borderColor: Color? = nil,
        shadow: DS.Shadow = .none
    ) -> some View {
        let fill: Color = {
            switch level {
            case 0: return DS.Palette.surfaceSunken
            case 2: return DS.Palette.surface2
            case 3: return DS.Palette.surface3
            default: return DS.Palette.surface1
            }
        }()
        return self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(borderColor ?? DS.Palette.hairline, lineWidth: border ? 1 : 0)
            )
            .shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
    }

    func dsShadow(_ shadow: DS.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
    }
}

// MARK: - Press feedback

/// Plain button that dips slightly while held, so every tap is felt.
/// Falls back to a dim instead of a scale when Reduce Motion is on.
public struct DroppyPressStyle: ButtonStyle {
    public var scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    public init(scale: CGFloat = 0.92) { self.scale = scale }

    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && isEnabled
        configuration.label
            .scaleEffect(pressed && !reduceMotion ? scale : 1)
            .opacity(pressed ? 0.78 : (isEnabled ? 1 : 0.4))
            .animation(DS.Motion.snap, value: pressed)
    }
}

// MARK: - Icon button

public enum DroppyButtonTone {
    case plain      // transparent until hovered
    case tonal      // subtle filled chip
    case accent     // accent filled
    case destructive
}

public struct DroppyIconButton: View {
    public let systemName: String
    public var size: CGFloat
    public var tone: DroppyButtonTone
    public var isActive: Bool
    public var help: String?
    public let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    public init(
        _ systemName: String,
        size: CGFloat = 24,
        tone: DroppyButtonTone = .plain,
        isActive: Bool = false,
        help: String? = nil,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.size = size
        self.tone = tone
        self.isActive = isActive
        self.help = help
        self.action = action
    }

    private var foreground: Color {
        if isActive { return tone == .accent ? .white : DS.accent }
        switch tone {
        case .destructive: return DS.Palette.danger
        case .accent: return .white
        default: return isHovered ? DS.Palette.textPrimary : DS.Palette.textSecondary
        }
    }

    private var background: Color {
        if isActive { return tone == .accent ? DS.accent : DS.accentSoft }
        switch tone {
        case .accent: return DS.accent
        case .tonal: return isHovered ? DS.Palette.surface3 : DS.Palette.surface2
        case .destructive: return isHovered ? DS.Palette.danger.opacity(0.18) : DS.Palette.surface1
        case .plain: return isHovered ? DS.Palette.surface2 : Color.clear
        }
    }

    /// "arrow.up.doc.fill" → "arrow up doc", so VoiceOver never reads raw symbol ids.
    static func spokenName(_ symbol: String) -> String {
        symbol.split(separator: ".")
            .filter { !["fill", "circle", "square", "rectangle"].contains($0) }
            .joined(separator: " ")
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(Circle().fill(background))
                .overlay(
                    Circle().strokeBorder(
                        isActive ? DS.accentHairline : Color.clear,
                        lineWidth: 1
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(DroppyPressStyle())
        .scaleEffect(isHovered && isEnabled && !reduceMotion ? 1.06 : 1.0)
        .animation(DS.Motion.hover, value: isHovered)
        .onHover { isHovered = isEnabled && $0 }
        .accessibilityLabel(help ?? Self.spokenName(systemName))
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .modifier(OptionalHelp(text: help))
    }
}

public extension View {
    /// Tooltip that is skipped entirely when there is no text (`.help("")` renders an empty one).
    func optionalHelp(_ text: String?) -> some View {
        modifier(OptionalHelp(text: text))
    }
}

/// `.help("")` still renders an empty tooltip, so only attach it when there is text.
private struct OptionalHelp: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text, !text.isEmpty {
            content.help(text)
        } else {
            content
        }
    }
}

// MARK: - Pill button (icon + label)

public struct DroppyPillButton: View {
    public let title: String
    public var systemName: String?
    public var tone: DroppyButtonTone
    public var help: String?
    public let action: () -> Void

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    public init(
        _ title: String,
        systemName: String? = nil,
        tone: DroppyButtonTone = .tonal,
        help: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemName = systemName
        self.tone = tone
        self.help = help
        self.action = action
    }

    private var foreground: Color {
        switch tone {
        case .accent: return .white
        case .destructive: return DS.Palette.danger
        default: return isHovered ? DS.Palette.textPrimary : DS.Palette.textSecondary
        }
    }

    private var background: Color {
        switch tone {
        case .accent: return isHovered ? DS.accent.opacity(0.92) : DS.accent
        case .destructive: return isHovered ? DS.Palette.danger.opacity(0.16) : DS.Palette.surface1
        case .tonal: return isHovered ? DS.Palette.surface3 : DS.Palette.surface2
        case .plain: return isHovered ? DS.Palette.surface2 : .clear
        }
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xs) {
                if let systemName {
                    Image(systemName: systemName).font(.system(size: 10, weight: .semibold))
                }
                Text(title).font(DS.Typo.caption)
            }
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, DS.Space.md)
            .frame(height: 24)
            .background(Capsule().fill(background))
            .contentShape(Capsule())
        }
        .buttonStyle(DroppyPressStyle(scale: 0.95))
        .animation(DS.Motion.hover, value: isHovered)
        .onHover { isHovered = isEnabled && $0 }
        .modifier(OptionalHelp(text: help))
    }
}

// MARK: - Segmented chips

public struct DroppyChip: View {
    public let title: String
    public var systemName: String?
    public var isSelected: Bool
    public var badge: String?
    public var help: String?
    public let action: () -> Void

    @State private var isHovered = false

    public init(
        _ title: String,
        systemName: String? = nil,
        isSelected: Bool = false,
        badge: String? = nil,
        help: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemName = systemName
        self.isSelected = isSelected
        self.badge = badge
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xs) {
                if let systemName {
                    Image(systemName: systemName).font(.system(size: 9, weight: .semibold))
                }
                Text(title).font(isSelected ? DS.Typo.labelStrong : DS.Typo.label)
                if let badge {
                    Text(badge)
                        .font(DS.Typo.numericSmall)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(isSelected ? Color.white.opacity(0.25) : DS.accentSoft))
                }
            }
            .foregroundStyle(isSelected ? Color.white : (isHovered ? DS.Palette.textPrimary : DS.Palette.textSecondary))
            .padding(.horizontal, DS.Space.md)
            .frame(height: 22)
            .background(
                Capsule().fill(isSelected ? DS.accent : (isHovered ? DS.Palette.surface2 : Color.clear))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(DroppyPressStyle(scale: 0.95))
        .animation(DS.Motion.snap, value: isSelected)
        .animation(DS.Motion.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .modifier(OptionalHelp(text: help))
    }
}

// MARK: - Empty state

public struct DroppyEmptyState: View {
    public let systemName: String
    public let title: String
    public var subtitle: String?
    public var compact: Bool

    public init(systemName: String, title: String, subtitle: String? = nil, compact: Bool = false) {
        self.systemName = systemName
        self.title = title
        self.subtitle = subtitle
        self.compact = compact
    }

    public var body: some View {
        VStack(spacing: compact ? DS.Space.xs : DS.Space.sm) {
            Image(systemName: systemName)
                .font(.system(size: compact ? 18 : 24, weight: .light))
                .foregroundStyle(DS.Palette.textTertiary)
            Text(title)
                .font(DS.Typo.label)
                .foregroundStyle(DS.Palette.textSecondary)
            if let subtitle, !compact {
                Text(subtitle)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? DS.Space.md : DS.Space.lg)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Meter

public struct DroppyMeter: View {
    public let value: Double      // 0...1
    public var tint: Color
    public var height: CGFloat

    public init(value: Double, tint: Color, height: CGFloat = 4) {
        self.value = value
        self.tint = tint
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DS.Palette.track)
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int((min(max(value, 0), 1) * 100).rounded())) percent")
    }
}

// MARK: - Section label

public struct DroppyKeyValue: View {
    public let key: String
    public let value: String
    public var tint: Color?

    public init(key: String, value: String, tint: Color? = nil) {
        self.key = key
        self.value = value
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: DS.Space.sm) {
            Text(key).font(DS.Typo.caption).foregroundStyle(DS.Palette.textTertiary)
            Spacer(minLength: DS.Space.sm)
            Text(value).font(DS.Typo.numeric).foregroundStyle(tint ?? DS.Palette.textPrimary)
        }
    }
}
