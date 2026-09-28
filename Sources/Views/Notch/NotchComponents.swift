import SwiftUI
import AppKit

// MARK: - Notch palette
// The notch is pure black like the hardware around it; everything on it is
// white at a few fixed opacities, plus the music wave in the accent colour.

public enum NotchPalette {
    public static let fill = Color.black
    public static let pill = Color(red: 10 / 255, green: 10 / 255, blue: 12 / 255).opacity(0.92)
    public static let tile = Color.white.opacity(0.055)
    public static let tileHover = Color.white.opacity(0.17)
    public static let control = Color.white.opacity(0.10)
    public static let track = Color.white.opacity(0.24)
    public static let secondary = Color.white.opacity(0.55)
    public static let tertiary = Color.white.opacity(0.45)
    public static let dash = Color.white.opacity(0.26)
    public static let calendarRed = Color(red: 1.0, green: 0.27, blue: 0.23)
    public static let selection = Color(red: 0.04, green: 0.52, blue: 1.0)

    /// The music wave follows the accent: a lighter tint at the top of each
    /// bar to a deeper one at the bottom.
    @MainActor public static var waveColors: [Color] {
        let accent = NSColor(ThemeSettings.shared.accentColor.color).usingColorSpace(.sRGB) ?? .systemBlue
        let top = accent.blended(withFraction: 0.4, of: .white) ?? accent
        let bottom = accent.blended(withFraction: 0.35, of: .black) ?? accent
        return [Color(nsColor: top), Color(nsColor: accent), Color(nsColor: bottom)]
    }
}

// MARK: - Music wave

/// The little accent-coloured equalizer Tama shows beside the album art. Bars
/// breathe while music plays and glide down to rest when it pauses.
public struct WaveBars: View {
    public var isPlaying: Bool
    public var bars: Int
    public var height: CGFloat
    public var barWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isIslandLayerVisible) private var isLayerVisible
    /// Observed so the bars retint as soon as the accent changes.
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var mediaSettings = MediaSettings.shared

    public init(isPlaying: Bool, bars: Int = 5, height: CGFloat = 12, barWidth: CGFloat = 2.4) {
        self.isPlaying = isPlaying
        self.bars = bars
        self.height = height
        self.barWidth = barWidth
    }

    public var body: some View {
        // Core Animation runs the bars in the render server. Driving them from
        // SwiftUI re-rendered the whole island hosting view 30 times a second.
        WaveBarsLayer(bars: bars, height: height, barWidth: barWidth,
                      colors: colors.map { NSColor($0).cgColor },
                      mode: mode)
            .frame(width: CGFloat(bars) * barWidth + CGFloat(max(bars - 1, 0)) * barWidth * 0.85,
                   height: height)
    }

    /// Settings › HUDs › Visualizer: grey mono bars, or a ramp from the
    /// album art's colours (the accent while there is no art).
    private var colors: [Color] {
        switch mediaSettings.visualizerStyle {
        case .mono:
            return [Color.white.opacity(0.95), Color.white.opacity(0.75), Color.white.opacity(0.5)]
        case .gradient:
            guard let palette = ArtworkPalette.current(MediaService.shared.currentTrack) else { return NotchPalette.waveColors }
            return [palette.primary, palette.primary, palette.secondary]
        }
    }

    private var mode: WaveBarsView.Mode {
        guard isPlaying else { return .resting }
        // Reduce Motion holds the bars still at a raised, uneven "playing" pose.
        if reduceMotion { return .still }
        // A hidden island layer stays mounted; it mustn't keep animating.
        guard isLayerVisible else { return .resting }
        // Settings › HUDs › Live audio visualizer: bars follow the real output.
        return mediaSettings.liveAudioVisualizer ? .live : .playing
    }
}

private struct WaveBarsLayer: NSViewRepresentable {
    var bars: Int
    var height: CGFloat
    var barWidth: CGFloat
    var colors: [CGColor]
    var mode: WaveBarsView.Mode

    func makeNSView(context: Context) -> WaveBarsView { WaveBarsView() }

    func updateNSView(_ view: WaveBarsView, context: Context) {
        view.configure(bars: bars, height: height, barWidth: barWidth, colors: colors, mode: mode)
    }
}

final class WaveBarsView: NSView {
    enum Mode: Equatable { case resting, still, playing, live }

    private static let phases: [Double] = [0.12, 0.43, 0.70, 0.08, 0.54, 0.30, 0.62]
    /// One full breath of a bar, in seconds.
    private static let period: CFTimeInterval = 0.9
    private static let restLevel: CGFloat = 0.26

    private var barLayers: [CAGradientLayer] = []
    private var barHeight: CGFloat = 0
    private var barWidth: CGFloat = 0
    private var mode: Mode?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Purely decorative: clicks belong to the island around it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(bars: Int, height: CGFloat, barWidth: CGFloat, colors: [CGColor], mode: Mode) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let geometryChanged = bars != barLayers.count || height != barHeight || barWidth != self.barWidth
        if bars != barLayers.count {
            barLayers.forEach { $0.removeFromSuperlayer() }
            barLayers = (0..<bars).map { _ in
                let bar = CAGradientLayer()
                bar.cornerCurve = .circular
                layer?.addSublayer(bar)
                return bar
            }
        }
        barHeight = height
        self.barWidth = barWidth
        for bar in barLayers where bar.colors as? [CGColor] != colors { bar.colors = colors }

        if geometryChanged {
            layoutBars()
        }
        if geometryChanged || mode != self.mode {
            // Glide between poses, except on first show or a size change.
            let animated = self.mode != nil && !geometryChanged
            self.mode = mode
            applyMode(animated: animated)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutBars()
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        barLayers.forEach { $0.contentsScale = scale }
    }

    /// Layers keep their animations while the view is out of a window, but
    /// re-adding them keeps the phase in step with the other wave bars.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, mode == .playing || mode == .live { applyMode(animated: false) }
        // Off screen, a live bar stops asking for the system tap.
        if window == nil, mode == .live { LiveAudioLevels.shared.unsubscribe(self) }
    }

    /// Live mode: one tick of real levels, or the simulated breath while the
    /// tap has nothing (no permission, digital silence).
    func applyLiveLevels() {
        guard mode == .live, window != nil else { return }
        let levels = LiveAudioLevels.shared
        guard levels.isReceiving, !levels.didFail else {
            if barLayers.first?.animation(forKey: "wave") == nil { breathe() }
            return
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(1.0 / 20)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        let rest = barHeight * Self.restLevel
        for (index, bar) in barLayers.enumerated() {
            bar.removeAnimation(forKey: "wave")
            bar.removeAnimation(forKey: "settle")
            let level = levels.level(bar: index, of: barLayers.count)
            bar.bounds.size.height = rest + (barHeight - rest) * level
        }
        CATransaction.commit()
    }

    /// The simulated animation: every bar breathes on its own phase.
    private func breathe() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let rest = barHeight * Self.restLevel
        let now = CACurrentMediaTime()
        for (index, bar) in barLayers.enumerated() {
            let phase = Self.phases[index % Self.phases.count]
            bar.removeAnimation(forKey: "settle")
            bar.bounds.size.height = rest
            let breath = CABasicAnimation(keyPath: "bounds.size.height")
            breath.fromValue = rest
            breath.toValue = barHeight
            breath.duration = Self.period / 2
            breath.autoreverses = true
            breath.repeatCount = .infinity
            breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            let cycle = (now / Self.period + phase).truncatingRemainder(dividingBy: 1)
            breath.timeOffset = cycle * Self.period
            breath.isRemovedOnCompletion = false
            bar.add(breath, forKey: "wave")
        }
    }

    private func layoutBars() {
        let spacing = barWidth * 0.85
        for (index, bar) in barLayers.enumerated() {
            bar.cornerRadius = barWidth / 2
            bar.bounds.size.width = barWidth
            bar.position = CGPoint(x: CGFloat(index) * (barWidth + spacing) + barWidth / 2, y: bounds.midY)
        }
    }

    private func applyMode(animated: Bool) {
        if mode == .live {
            LiveAudioLevels.shared.subscribe(self)
            breathe()
            applyLiveLevels()
            return
        }
        LiveAudioLevels.shared.unsubscribe(self)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let rest = barHeight * Self.restLevel
        let now = CACurrentMediaTime()
        for (index, bar) in barLayers.enumerated() {
            let phase = Self.phases[index % Self.phases.count]
            let shown = bar.presentation()?.bounds.size.height ?? bar.bounds.size.height
            bar.removeAnimation(forKey: "wave")
            bar.removeAnimation(forKey: "settle")
            switch mode {
            case .playing, .live:
                // Rest to full and back, eased: close enough to a sine. The
                // offset starts each bar at its own point in the breath.
                bar.bounds.size.height = rest
                let breath = CABasicAnimation(keyPath: "bounds.size.height")
                breath.fromValue = rest
                breath.toValue = barHeight
                breath.duration = Self.period / 2
                breath.autoreverses = true
                breath.repeatCount = .infinity
                breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                let cycle = (now / Self.period + phase).truncatingRemainder(dividingBy: 1)
                breath.timeOffset = cycle * Self.period
                breath.isRemovedOnCompletion = false
                bar.add(breath, forKey: "wave")
            case .still, .resting, nil:
                let target = mode == .still ? barHeight * (0.4 + 0.5 * CGFloat(phase) / 0.7) : rest
                bar.bounds.size.height = target
                guard animated, abs(shown - target) > 0.5 else { continue }
                let settle = CASpringAnimation(perceptualDuration: 0.46, bounce: 0.3)
                settle.keyPath = "bounds.size.height"
                settle.fromValue = shown
                settle.toValue = target
                settle.duration = settle.settlingDuration
                bar.add(settle, forKey: "settle")
            }
        }
    }
}

/// False inside an island layer that is mounted but faded out (the shelf
/// while the notch rests, the resting wings under the shelf).
private struct IslandLayerVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var isIslandLayerVisible: Bool {
        get { self[IslandLayerVisibleKey.self] }
        set { self[IslandLayerVisibleKey.self] = newValue }
    }
}

// MARK: - Album art

public struct AlbumArtView: View {
    public var image: NSImage?
    public var size: CGFloat
    public var radius: CGFloat

    public init(image: NSImage?, size: CGFloat, radius: CGFloat) {
        self.image = image
        self.size = size
        self.radius = radius
    }

    public var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color(white: 0.22), Color(white: 0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.38, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        // Artwork is decoration: the title beside it (or the caller's own
        // label) says what is playing, and VoiceOver would only read "image".
        .accessibilityHidden(true)
    }
}

// MARK: - App icons

public enum AppIcon {
    @MainActor private static var cache: [String: NSImage] = [:]

    /// Icon for a bundle identifier, cached; nil when the app is not installed.
    @MainActor
    public static func image(bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let hit = cache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }

    /// Bundle identifier for the player names MediaService reports. Exact
    /// names only: a substring match turned "YouTube Music" into Apple Music.
    public static func bundleID(forPlayer name: String) -> String? {
        playerBundleIDs[name.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    private static let playerBundleIDs: [String: String] = [
        "spotify": "com.spotify.client",
        "music": "com.apple.Music",
        "apple music": "com.apple.Music",
        "safari": "com.apple.Safari",
        "google chrome": "com.google.Chrome",
        "chrome": "com.google.Chrome",
        "chromium": "org.chromium.Chromium",
        "brave browser": "com.brave.Browser",
        "brave": "com.brave.Browser",
        "microsoft edge": "com.microsoft.edgemac",
        "edge": "com.microsoft.edgemac",
        "arc": "company.thebrowser.Browser",
        "vivaldi": "com.vivaldi.Vivaldi",
        "opera": "com.operasoftware.Opera"
    ]
}

// MARK: - File icons

/// Finder's icon for a file, cached by path. `NSWorkspace.icon(forFile:)`
/// crosses into LaunchServices and hands back a fresh `NSImage` every call,
/// and the rails that draw these — the Tray, a Basket, the folder browser —
/// ask again on every redraw: a hover, a keystroke in a search field, a drag
/// in flight. Keyed by path rather than by type, so a custom icon somebody set
/// in Finder stays on the one file that has it.
public enum FileIcon {
    @MainActor private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 600
        return cache
    }()

    @MainActor
    public static func image(for path: String) -> NSImage {
        let key = path as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(icon, forKey: key)
        return icon
    }

    @MainActor
    public static func image(for url: URL) -> NSImage { image(for: url.path) }
}

// MARK: - Buttons

/// Round, borderless control used across the shelf: transport, tray actions, headers.
public struct NotchCircleButton: View {
    let systemName: String
    let size: CGFloat
    let iconSize: CGFloat
    let isActive: Bool
    let filled: Bool
    let help: String?
    let action: () -> Void

    @State private var isHovered = false

    public init(
        _ systemName: String,
        size: CGFloat = 30,
        iconSize: CGFloat = 12,
        isActive: Bool = false,
        filled: Bool = true,
        help: String? = nil,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.size = size
        self.iconSize = iconSize
        self.isActive = isActive
        self.filled = filled
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white.opacity(isActive || isHovered ? 1 : 0.8))
                .frame(width: size, height: size)
                .background(
                    Circle().fill(
                        isActive ? Color.white.opacity(0.18)
                            : (filled ? (isHovered ? Color.white.opacity(0.16) : NotchPalette.control)
                               : (isHovered ? Color.white.opacity(0.10) : .clear))
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovered = $0 }
        // A label of its own, not just the tooltip: `.help` is a hint, and it
        // is suppressed entirely by Settings › Accessibility › Show tooltips.
        .accessibilityLabel(help ?? DroppyIconButton.spokenName(systemName))
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .modifier(OptionalHelp(text: help))
    }
}

/// Tooltip and VoiceOver label from the same text, only when there is one;
/// `.help("")` would leave an empty tooltip.
private struct OptionalHelp: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text, !text.isEmpty {
            content.help(text).accessibilityLabel(text)
        } else {
            content
        }
    }
}

/// Tama's springy press: shrink fast, bounce back. With Reduce Motion the
/// press only dims. A disabled button is dimmed too, unless the call site
/// draws its own disabled look (`dimsWhenDisabled: false`).
public struct PressableStyle: ButtonStyle {
    public var scale: CGFloat = 0.84
    public var dimsWhenDisabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    public init(scale: CGFloat = 0.84, dimsWhenDisabled: Bool = true) {
        self.scale = scale
        self.dimsWhenDisabled = dimsWhenDisabled
    }

    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && isEnabled
        configuration.label
            .scaleEffect(pressed && !reduceMotion ? scale : 1)
            .opacity(!isEnabled && dimsWhenDisabled ? 0.4 : (pressed && reduceMotion ? 0.78 : 1))
            .animation(
                reduceMotion ? nil
                    : pressed
                    ? .spring(response: 0.12, dampingFraction: 0.9)
                    : .spring(response: 0.38, dampingFraction: 0.5),
                value: pressed
            )
    }
}

// MARK: - Edge fades

public extension View {
    /// Fades the leading and trailing edges of a horizontal rail into the black shelf.
    func horizontalEdgeFade(_ width: CGFloat = 22) -> some View {
        mask(
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: width)
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: width)
            }
        )
    }
}
