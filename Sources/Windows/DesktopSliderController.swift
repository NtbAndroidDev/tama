import SwiftUI
import AppKit
import Combine

/// Settings › HUDs › Desktop volume / brightness slider: a small glass slider
/// that lives on the desktop, under every window, on all Spaces. Drag it by
/// its edge to move it; macOS remembers where it was left.
@MainActor
public final class DesktopSliderController {
    public static let shared = DesktopSliderController()

    public enum Kind: String {
        case volume, brightness
    }

    private var panels: [Kind: NSPanel] = [:]

    private init() {}

    public func sync() {
        let state = AppState.shared
        set(.volume, visible: state.desktopVolumeSlider)
        // Only with a display Tama can dim.
        set(.brightness, visible: state.desktopBrightnessSlider && BrightnessService.shared.canSetBrightness)
    }

    private func set(_ kind: Kind, visible: Bool) {
        if visible {
            let panel = panels[kind] ?? makePanel(kind)
            panels[kind] = panel
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if let panel = panels[kind] {
            panel.orderOut(nil)
            panels[kind] = nil
        }
    }

    private func makePanel(_ kind: Kind) -> NSPanel {
        let size = DroppyShelfMetrics.desktopSliderSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        // On the desktop: above its icons, below every ordinary window.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: DesktopSliderView(kind: kind))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        let autosave = "TamaDesktop\(kind.rawValue.capitalized)Slider"
        if !panel.setFrameUsingName(autosave), let screen = NSScreen.main {
            // First time: the lower right of the desktop, volume above brightness.
            let visible = screen.visibleFrame
            let lift: CGFloat = kind == .volume ? 72 : 20
            panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 24, y: visible.minY + lift))
        }
        panel.setFrameAutosaveName(autosave)
        CaptureExclusion.register(panel)
        return panel
    }
}

/// The slider itself: icon, track and percentage on dark glass.
private struct DesktopSliderView: View {
    let kind: DesktopSliderController.Kind
    @ObservedObject private var outputs = AudioOutputService.shared
    @ObservedObject private var state = AppState.shared
    @State private var brightness: Double = BrightnessService.shared.brightness ?? 0.5
    /// Made once rather than in `body`, where every redraw built and subscribed
    /// a fresh timer. Only the brightness slider needs one.
    private let ticks: AnyPublisher<Date, Never>

    init(kind: DesktopSliderController.Kind) {
        self.kind = kind
        ticks = kind == .brightness
            ? Timer.publish(every: 1, tolerance: 0.3, on: .main, in: .common).autoconnect().eraseToAnyPublisher()
            : Empty().eraseToAnyPublisher()
    }

    private var isVolume: Bool { kind == .volume }

    private var value: Binding<Double> {
        if isVolume {
            return Binding(get: { outputs.isMuted ? 0 : outputs.volume },
                           set: { outputs.setVolume($0) })
        }
        return Binding(get: { brightness }, set: { level in
            brightness = level
            BrightnessService.shared.setBrightness(level)
        })
    }

    private var icon: String {
        let hudKind: IslandHUD.Kind = isVolume ? .volume : .brightness
        return hudKind.iconName(for: value.wrappedValue, isMuted: isVolume && outputs.isMuted)
    }

    private var percent: Int { Int((value.wrappedValue * 100).rounded()) }

    private var iconImage: some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 20)
            .contentTransition(.symbolEffect(.replace))
    }

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            // Only the volume icon does something (mute); the brightness one
            // is a plain label rather than a button that ignores clicks.
            if isVolume {
                Button { outputs.setMuted(!outputs.isMuted) } label: { iconImage }
                    .buttonStyle(DroppyPressStyle(scale: 0.85))
                    .help(outputs.isMuted ? "Unmute" : "Mute")
                    .accessibilityLabel(outputs.isMuted ? "Unmute" : "Mute")
            } else {
                iconImage.accessibilityHidden(true)
            }
            Slider(value: value, in: 0...1)
                .controlSize(.small)
                .disabled(isVolume && !outputs.canSetVolume)
                .accessibilityLabel(isVolume ? "Volume" : "Brightness")
                .accessibilityValue("\(percent) percent")
            Text("\(percent)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
        .tint(state.accentColor.color)
        .onReceive(ticks) { _ in
            // Brightness has no change notification; follow the keys and Control Center.
            guard let now = BrightnessService.shared.brightness, abs(now - brightness) > 0.005 else { return }
            brightness = now
        }
    }
}
