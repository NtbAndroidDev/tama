import SwiftUI
import AppKit

public struct VisualEffectView: NSViewRepresentable {
    public let material: NSVisualEffectView.Material
    public let blendingMode: NSVisualEffectView.BlendingMode
    public let state: NSVisualEffectView.State

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

public struct LiquidGlassTheme: Sendable {
    public static let royalBlue = Color(red: 21/255, green: 58/255, blue: 164/255)
    public static let electricBlue = Color(red: 31/255, green: 92/255, blue: 201/255)
    public static let deepInk = Color(red: 10/255, green: 14/255, blue: 22/255)
    public static let cardSurface = Color(red: 26/255, green: 32/255, blue: 44/255, opacity: 0.85)
    public static let cardSurfaceRaised = Color(red: 35/255, green: 42/255, blue: 58/255, opacity: 0.92)
    public static let subtleBorder = Color.white.opacity(0.12)
    public static let highlightGlow = Color(red: 52/255, green: 120/255, blue: 246/255, opacity: 0.25)
    public static let emberOrange = Color(red: 245/255, green: 130/255, blue: 32/255)
    public static let emeraldGreen = Color(red: 48/255, green: 209/255, blue: 88/255)
    
    @MainActor
    public static var dynamicAccent: Color {
        ThemeSettings.shared.accentColor.color
    }
    
    @MainActor
    public static var dynamicGlow: Color {
        ThemeSettings.shared.accentColor.color.opacity(0.35 * ThemeSettings.shared.borderGlowIntensity)
    }
}

@MainActor
public final class DroppyAudio {
    public static func playTick() {
        if GeneralSettings.shared.soundEffects {
            NSSound(named: "Tink")?.play()
        }
        if GeneralSettings.shared.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }
    
    public static func playDropSuccess() {
        if GeneralSettings.shared.soundEffects {
            NSSound(named: "Pop")?.play()
        }
        if GeneralSettings.shared.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
        }
    }
    
    public static func playCopySuccess() {
        if GeneralSettings.shared.soundEffects {
            NSSound(named: "Purr")?.play()
        }
        if GeneralSettings.shared.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
        }
    }
    
    public static func playDelete() {
        if GeneralSettings.shared.soundEffects {
            NSSound(named: "Basso")?.play()
        }
        if GeneralSettings.shared.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
        }
    }
    
    public static func playSnip() {
        if GeneralSettings.shared.soundEffects {
            NSSound(named: "Hero")?.play()
        }
        if GeneralSettings.shared.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }
}

/// Shape with inverted fillet ears on top left & right for hardware notch blending.
/// At `earRadius == 0` it degenerates into the resting pill, so the two states are
/// the same path with different numbers — which is what lets them interpolate.
public struct NotchWithEarsShape: Shape {
    public var cornerRadius: CGFloat
    public var earRadius: CGFloat

    public init(cornerRadius: CGFloat = 20, earRadius: CGFloat = 12) {
        self.cornerRadius = cornerRadius
        self.earRadius = earRadius
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cornerRadius, earRadius) }
        set {
            cornerRadius = newValue.first
            earRadius = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let ear = max(0, min(earRadius, w / 4))
        let left = ear
        let right = w - ear
        // Continuous (squircle-like) corners reach ~1.3x the nominal radius,
        // like the hardware notch and the Dynamic Island; plain arcs look pinched.
        let r = max(0, min(cornerRadius, h / 1.3, (right - left) / 2.6))
        let reach = r * 1.3

        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        // Top-left ear: a concave fillet flowing out of the bezel.
        if ear > 0 {
            path.addCurve(
                to: CGPoint(x: left, y: ear),
                control1: CGPoint(x: ear * 0.62, y: 0),
                control2: CGPoint(x: left, y: ear * 0.38)
            )
        }
        path.addLine(to: CGPoint(x: left, y: h - reach))
        path.addCurve(
            to: CGPoint(x: left + reach, y: h),
            control1: CGPoint(x: left, y: h - reach * 0.28),
            control2: CGPoint(x: left + reach * 0.28, y: h)
        )
        path.addLine(to: CGPoint(x: right - reach, y: h))
        path.addCurve(
            to: CGPoint(x: right, y: h - reach),
            control1: CGPoint(x: right - reach * 0.28, y: h),
            control2: CGPoint(x: right, y: h - reach * 0.28)
        )
        path.addLine(to: CGPoint(x: right, y: ear))
        if ear > 0 {
            path.addCurve(
                to: CGPoint(x: w, y: 0),
                control1: CGPoint(x: right, y: ear * 0.38),
                control2: CGPoint(x: w - ear * 0.62, y: 0)
            )
        } else {
            path.addLine(to: CGPoint(x: w, y: 0))
        }
        path.closeSubpath()
        return path
    }
}

/// The island outline. Both placement modes interpolate their own path, so the
/// container can spring between resting and expanded without a visual cut.
public struct DynamicIslandShape: Shape {
    public var style: IslandStyle
    public var cornerRadius: CGFloat
    public var earRadius: CGFloat

    public init(
        style: IslandStyle = .notchAttached,
        cornerRadius: CGFloat = 20,
        earRadius: CGFloat = 0
    ) {
        self.style = style
        self.cornerRadius = cornerRadius
        self.earRadius = earRadius
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cornerRadius, earRadius) }
        set {
            cornerRadius = newValue.first
            earRadius = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        if style == .notchAttached {
            return NotchWithEarsShape(cornerRadius: cornerRadius, earRadius: earRadius).path(in: rect)
        }
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
    }
}

public struct LiquidGlassBackgroundModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var showBorder: Bool
    public var isHovered: Bool
    public var isNotchAttached: Bool
    public var earRadius: CGFloat
    /// Points at the top that stay solid black under Dynamic Glass: the
    /// hardware notch's height, so the resting notch still reads as hardware.
    public var solidTop: CGFloat
    /// The island is resting (for Theming › Outline › Show in resting state).
    public var isResting: Bool
    /// Observed so the border and glow retint as soon as the accent or glow
    /// intensity changes in Settings.
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var themeSettings = ThemeSettings.shared

    public init(
        cornerRadius: CGFloat = 20,
        showBorder: Bool = true,
        isHovered: Bool = false,
        isNotchAttached: Bool = false,
        earRadius: CGFloat = 0,
        solidTop: CGFloat = 0,
        isResting: Bool = false
    ) {
        self.cornerRadius = cornerRadius
        self.showBorder = showBorder
        self.isHovered = isHovered
        self.isNotchAttached = isNotchAttached
        self.earRadius = earRadius
        self.solidTop = solidTop
        self.isResting = isResting
    }

    private var shape: DynamicIslandShape {
        DynamicIslandShape(
            style: isNotchAttached ? .notchAttached : .floatingPill,
            cornerRadius: cornerRadius,
            earRadius: earRadius
        )
    }

    /// Settings › Theming, per display class. A notch-attached shape can't be
    /// Liquid Glass (it has to meet the black bezel).
    private var surface: IslandSurfaceStyle {
        if isNotchAttached {
            return themeSettings.notchedSurfaceStyle == .liquidGlass ? .dynamicGlass : themeSettings.notchedSurfaceStyle
        }
        return themeSettings.notchlessSurfaceStyle
    }

    private var tint: Color? { themeSettings.windowTintColor }

    private var showsOutline: Bool {
        themeSettings.subtleOutline && (!isResting || themeSettings.outlineInRestingState)
    }

    public func body(content: Content) -> some View {
        content
            .background(IslandSurfaceFill(surface: surface, solidTop: solidTop, tint: tint,
                                          glow: isHovered && !isNotchAttached ? LiquidGlassTheme.dynamicGlow : nil))
            .clipShape(shape)
            .overlay(
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                isNotchAttached ? Color.clear : (isHovered ? LiquidGlassTheme.dynamicAccent.opacity(0.65 * themeSettings.borderGlowIntensity) : Color.white.opacity(0.20)),
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: showBorder ? 1 : 0
                    )
            )
            .overlay(rim)
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowOffset)
    }

    /// Dynamic Glass's light rim along the glassy bottom edge, and the
    /// optional subtle outline. Both fade out at the very top, which meets the
    /// bezel or the menu bar.
    private var rim: some View {
        GeometryReader { geo in
            let h = max(geo.size.height, 1)
            let clearTop = min(0.9, max(solidTop, 2) / h)
            ZStack {
                if surface == .dynamicGlass && !isResting && solidTop < h - 1 {
                    shape.stroke(
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: min(0.95, clearTop + 0.25)),
                            .init(color: .white.opacity(0.22), location: 1),
                        ], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                }
                if showsOutline {
                    shape.stroke(
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.16), location: clearTop),
                            .init(color: .white.opacity(0.16), location: 1),
                        ], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    // A notch-attached island has no border (its top is the bezel), so its
    // glow is a soft accent halo below it, only while hovered.
    private var shadowColor: Color {
        let glow = themeSettings.borderGlowIntensity
        if isNotchAttached {
            return isHovered && glow > 0 ? LiquidGlassTheme.dynamicAccent.opacity(min(0.4 * glow, 0.6)) : .clear
        }
        return isHovered ? LiquidGlassTheme.dynamicAccent.opacity(0.25 * glow) : Color.black.opacity(0.48)
    }

    private var shadowRadius: CGFloat {
        if isNotchAttached { return isHovered ? 20 : 0 }
        return isHovered ? 16 : 10
    }

    private var shadowOffset: CGFloat {
        if isNotchAttached { return isHovered ? 8 : 0 }
        return isHovered ? 6 : 4
    }
}

/// The paint behind the island for one surface style. Also used by the
/// Theming preview cards, so they show exactly what the island will draw.
public struct IslandSurfaceFill: View {
    public var surface: IslandSurfaceStyle
    /// Height that stays solid black at the top (Dynamic Glass).
    public var solidTop: CGFloat
    /// Theming › Window tint, washed over the glass.
    public var tint: Color?
    /// Hover glow for the floating pill.
    public var glow: Color?

    public init(surface: IslandSurfaceStyle, solidTop: CGFloat = 0, tint: Color? = nil, glow: Color? = nil) {
        self.surface = surface
        self.solidTop = solidTop
        self.tint = tint
        self.glow = glow
    }

    public var body: some View {
        switch surface {
        case .black:
            ZStack {
                Color.black
                if let glow {
                    LinearGradient(colors: [glow, Color.clear], startPoint: .top, endPoint: .center)
                }
            }
        case .dynamicGlass:
            GeometryReader { geo in
                let h = max(geo.size.height, 1)
                if solidTop >= h - 1 {
                    // Nothing hangs below the notch (resting, level HUD):
                    // pure black, so it reads as the hardware.
                    Color.black
                } else {
                    // Solid under the notch (or the top 45%), then fading to
                    // glass over the lower part, so the bottom edge reads as glass.
                    let solid = min(0.92, max(solidTop / h, 0.45))
                    ZStack {
                        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                        if let tint { tint.opacity(0.14) }
                        LinearGradient(stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: solid),
                            .init(color: .black.opacity(0.55), location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                        if let glow {
                            LinearGradient(colors: [glow, Color.clear], startPoint: .top, endPoint: .center)
                        }
                    }
                }
            }
        case .liquidGlass:
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.35)
                (tint ?? Color.white).opacity(tint == nil ? 0.04 : 0.16)
                LinearGradient(
                    colors: [Color.white.opacity(0.16), Color.white.opacity(0.03), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                if let glow {
                    LinearGradient(colors: [glow, Color.clear], startPoint: .top, endPoint: .center)
                }
            }
        }
    }
}

public extension View {
    func liquidGlass(
        cornerRadius: CGFloat = 20,
        showBorder: Bool = true,
        isHovered: Bool = false,
        isNotchAttached: Bool = false,
        earRadius: CGFloat = 0,
        solidTop: CGFloat = 0,
        isResting: Bool = false
    ) -> some View {
        self.modifier(LiquidGlassBackgroundModifier(
            cornerRadius: cornerRadius,
            showBorder: showBorder,
            isHovered: isHovered,
            isNotchAttached: isNotchAttached,
            earRadius: earRadius,
            solidTop: solidTop,
            isResting: isResting
        ))
    }
}
