import SwiftUI

/// Settings › HUDs, the Volume and Brightness sections: whether the notch shows that level,
/// how the readout looks, and whether Tama takes the keys from macOS. Every
/// change pops the HUD in the notch too, so the result is seen where it lives.
struct LevelHUDSettingsTab: View {
    let kind: IslandHUD.Kind

    @ObservedObject var state = AppState.shared
    @ObservedObject private var outputs = AudioOutputService.shared
    @ObservedObject private var mediaKeys = MediaKeyMonitor.shared
    @ObservedObject private var permissions = PermissionService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Brightness has no change notification; sampled while the page is open.
    @State private var confirmsAccessibilityReset = false
    @State private var brightness: Double = BrightnessService.shared.brightness ?? 0.7

    private var isVolume: Bool { kind == .volume }

    // MARK: Bindings for this kind's settings

    private var enabled: Binding<Bool> { isVolume ? $state.showVolumeHUD : $state.showBrightnessHUD }
    private var duration: Binding<Double> { isVolume ? $state.hudDuration : $state.brightnessHUDDuration }
    private var meter: Binding<HUDMeterStyle> { isVolume ? $state.hudMeterStyle : $state.brightnessHUDMeterStyle }
    private var showPercentage: Binding<Bool> { isVolume ? $state.hudShowPercentage : $state.brightnessHUDShowPercentage }
    private var hideLabel: Binding<Bool> { isVolume ? $state.hudHideLabel : $state.brightnessHUDHideLabel }
    private var animation: Binding<HUDAnimation> { isVolume ? $state.hudAnimation : $state.brightnessHUDAnimation }
    private var replaceSystem: Binding<Bool> { isVolume ? $state.replaceSystemVolumeHUD : $state.replaceSystemBrightnessHUD }
    private var scrollToChange: Binding<Bool> { isVolume ? $state.scrollToChangeVolume : $state.scrollToChangeBrightness }

    private var style: LevelHUDStyle { state.hudStyle(for: kind) }

    private var currentDevice: IslandHUD.Device? {
        outputs.devices.first { $0.id == outputs.currentDeviceID }
            .map { IslandHUD.Device(name: $0.name, symbol: AudioOutputService.deviceSymbol($0)) }
    }

    /// The live level, as the notch would show it now.
    private var sample: IslandHUD {
        isVolume
            ? IslandHUD(kind: .volume, value: outputs.volume, isMuted: outputs.isMuted, device: currentDevice)
            : IslandHUD(kind: .brightness, value: brightness)
    }

    private var isIntercepting: Bool { isVolume ? mediaKeys.interceptsVolume : mediaKeys.interceptsBrightness }

    var body: some View {
        SettingsSection(isVolume ? "Volume" : "Brightness", anchor: isVolume ? "huds.volume" : "huds.brightness") {
            SettingsGroup {
                header
                SettingsDivider()
                Group {
                    preview.padding(12)
                    SettingsDivider()
                    SettingsSlider("Duration", value: duration, in: 0.5...4, step: 0.5, defaultValue: 1.5) {
                        String(format: "%.1f s", $0)
                    }
                    SettingsDivider()
                    SettingsRow("Meter", help: "White, your highlight color, or Decibel (green to red as it gets louder). A custom color is picked in Theming.")
                    tileRow(HUDMeterStyle.tileChoices, selection: meter, title: \.rawValue) { option in
                        Group {
                            if option == .decibel {
                                // Decibel is about change, so its tile plays it.
                                DecibelDemoMeter(kind: kind)
                            } else {
                                HUDMeter(hud: IslandHUD(kind: kind, value: 0.72), width: 70, style: option, showPercentage: false)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .padding([.horizontal, .bottom], 14)
                    if meter.wrappedValue == .custom {
                        SettingsNote("Using the custom color from Theming › \(isVolume ? "Volume" : "Brightness") slider color.")
                    }
                    SettingsDivider()
                    SettingsToggleRow("Show percentage", isOn: showPercentage)
                    SettingsDivider()
                    SettingsToggleRow("Hide label", isOn: hideLabel)
                    SettingsDivider()
                    SettingsRow("Animation")
                    tileRow(HUDAnimation.allCases, selection: animation, title: \.rawValue) { option in
                        Image(systemName: option.iconName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(option == animation.wrappedValue ? state.accentColor.color : .secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .padding([.horizontal, .bottom], 14)
                    if isVolume {
                        SettingsDivider()
                        SettingsRow("Leading icon")
                        tileRow(HUDLeading.allCases, selection: $state.hudLeading, title: \.rawValue) { option in
                            Image(systemName: option == .symbol ? "speaker.wave.2.fill" : (currentDevice?.symbol ?? "airpodspro"))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .padding([.horizontal, .bottom], 14)
                    }
                }
                .settingsDisabled(!enabled.wrappedValue)
            }

            SettingsGroup {
                SettingsToggleRow(isVolume ? "Hide the macOS volume HUD" : "Hide the macOS brightness HUD",
                                  subtitle: enabled.wrappedValue ? nil : "Needs \(isVolume ? "Volume" : "Brightness") HUD above.",
                                  help: footer, isOn: replaceSystem)
                    .settingsDisabled(!enabled.wrappedValue)
                if enabled.wrappedValue && replaceSystem.wrappedValue && !isIntercepting {
                    accessibilityWarning
                }
                SettingsDivider()
                SettingsToggleRow(isVolume ? "Scroll on the notch to change the volume" : "⌥-scroll on the notch to change the brightness",
                                  isOn: scrollToChange)
            }
        }
        .onChange(of: style) { _, _ in previewInNotch() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard !isVolume, let now = BrightnessService.shared.brightness else { return }
            if abs(now - brightness) > 0.005 { brightness = now }
        }
    }

    /// Allowed yet not intercepting means a stale grant (a rebuild changed
    /// the code signature): asking again does nothing, only a reset helps.
    private var accessibilityWarning: some View {
        let isStale = permissions.status(.accessibility) == .granted
        return HStack(alignment: .firstTextBaseline) {
            Label(isStale
                  ? "\(PermissionService.accessibilityName) is on but isn't taking effect, usually after an update. Reset clears it so macOS asks again."
                  : "Needs \(PermissionService.accessibilityName) access. Until it's allowed, macOS shows its HUD too.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(DS.Palette.warning)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if isStale {
                Button("Reset…") {
                    // The tap is only retried on a poll; a fresh grant may just
                    // not have been picked up yet, so retry before wiping it.
                    mediaKeys.syncInterception()
                    if !isIntercepting { confirmsAccessibilityReset = true }
                }
                    .controlSize(.small)
                    .help("Clear Tama's \(PermissionService.accessibilityName) grant and ask again")
                    .confirmationDialog(
                        "Reset \(PermissionService.accessibilityName) for Tama?",
                        isPresented: $confirmsAccessibilityReset
                    ) {
                        Button("Reset and Ask Again", role: .destructive) {
                            permissions.reset(.accessibility, thenRequest: true)
                        }
                    } message: {
                        Text("Paste, Window Snap and media keys stop working until you allow Tama again.")
                    }
            } else {
                Button("Allow…") { permissions.request(.accessibility) }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var footer: String {
        if isVolume {
            return "With the macOS HUD hidden, Tama handles the volume keys itself: the same steps as macOS, ⌥⇧ for finer ones, and the feedback sound if it's on in Sound settings. Outputs without a software volume, like HDMI displays, keep the macOS HUD. In All Displays the level shows only on the screen you're using; in the open shelf it shows along the bottom."
        }
        return "With the macOS HUD hidden, Tama handles the brightness keys itself: the same steps as macOS, ⌥⇧ for finer ones. It dims the built-in display; external displays keep the macOS HUD. Keyboards whose brightness keys macOS handles in hardware can't be taken over."
    }

    // MARK: Parts

    /// Icon, title and the master switch, like the top row of a system pane.
    private var header: some View {
        SettingsRow(isVolume ? "Volume HUD" : "Brightness HUD",
                    subtitle: isVolume ? "Replace system OSD" : "Replace brightness OSD",
                    icon: isVolume ? "speaker.wave.2.fill" : "sun.max.fill") {
            Toggle(isVolume ? "Volume HUD" : "Brightness HUD", isOn: enabled).labelsHidden().toggleStyle(.switch)
        }
    }

    /// The HUD as the notch will draw it, around a stand-in for the notch.
    private var preview: some View {
        HStack(spacing: 8) {
            HUDLabel(hud: sample, maxLabelWidth: 110, style: style)
            Spacer(minLength: 0)
            Capsule().fill(Color.white.opacity(0.06)).frame(width: 90, height: 20)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            HUDMeter(hud: sample, width: style.showPercentage ? 64 : 92)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(reduceMotion ? nil : style.animation.animation, value: sample.value)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isVolume ? "Volume HUD preview" : "Brightness HUD preview")
    }

    private func previewInNotch() {
        guard enabled.wrappedValue else { return }
        if isVolume {
            AudioOutputService.shared.presentHUD()
        } else {
            state.showHUD(.brightness, value: brightness)
        }
    }

    /// Picture tiles with a caption, the chosen one ringed in the accent.
    private func tileRow<Option: Hashable, Tile: View>(
        _ options: [Option],
        selection: Binding<Option>,
        title: KeyPath<Option, String>,
        @ViewBuilder tile: @escaping (Option) -> Tile
    ) -> some View {
        HStack(spacing: 10) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection.wrappedValue == option
                Button {
                    selection.wrappedValue = option
                } label: {
                    VStack(spacing: 6) {
                        tile(option)
                            .frame(height: 44)
                            .padding(3)
                            .overlay(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .strokeBorder(isSelected ? state.accentColor.color : Color.primary.opacity(0.1), lineWidth: isSelected ? 2.5 : 1)
                            )
                        Text(option[keyPath: title])
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option[keyPath: title])
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

/// The Decibel tile's meter, rising and falling like a level meter so its
/// colour can be seen running from green through amber to red. Still under
/// Reduce Motion.
private struct DecibelDemoMeter: View {
    let kind: IslandHUD.Kind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let level = reduceMotion ? 0.72 : Self.level(at: context.date.timeIntervalSinceReferenceDate)
            HUDMeter(hud: IslandHUD(kind: kind, value: level), width: 70, style: .decibel, showPercentage: false)
        }
        .accessibilityHidden(true)
    }

    /// Two slow waves and a quicker one, so it wanders like music rather
    /// than ticking like a metronome; spans roughly 15–95 %.
    static func level(at t: TimeInterval) -> Double {
        let value = 0.55 + 0.28 * sin(t * 1.1) + 0.12 * sin(t * 2.9 + 1.3)
        return min(max(value, 0.12), 0.97)
    }
}
