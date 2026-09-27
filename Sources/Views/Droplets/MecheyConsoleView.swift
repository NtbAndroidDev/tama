import SwiftUI

// Mechey Console — switch sounds for every keystroke, presented inside the Droplets lane.

public struct MecheyConsoleView: View {
    @ObservedObject private var mechey = MecheyService.shared
    @AppStorage(MecheyService.Keys.isOn) private var isOn = false
    @AppStorage(MecheyService.Keys.pack) private var pack = MecheyPack.brown.rawValue
    @AppStorage(MecheyService.Keys.volume) private var volume = 0.6
    @AppStorage(MecheyService.Keys.muteWhilePlaying) private var muteWhilePlaying = false
    // Input Monitoring is granted in System Settings, so re-check while it's missing.
    private let permissionPoll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private let tint = Color(red: 0.62, green: 0.66, blue: 0.76)

    public init() {}

    private var statusText: String {
        if !isOn { return "OFF" }
        if !mechey.hasPermission { return "NEEDS ACCESS" }
        return mechey.isListening ? "LISTENING" : "STARTING"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            header

            Text("Plays a switch sound for each key you press. Mechey only notes what kind of key it was — never which key or what you type.")
                .font(DS.Typo.caption)
                .foregroundColor(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if isOn && !mechey.hasPermission { permissionCard }

            packPicker
            volumeRow
            keyPad

            Toggle(isOn: $muteWhilePlaying) {
                Text("Silent while music or video is playing")
                    .font(DS.Typo.caption)
                    .foregroundColor(DS.Palette.textSecondary)
            }
            .toggleStyle(.checkbox)
        }
        .onAppear {
            MecheyService.shared.start()
            mechey.refreshPermission()
        }
        .onReceive(permissionPoll) { _ in
            if !mechey.hasPermission { mechey.refreshPermission() }
        }
    }

    private var header: some View {
        HStack(spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "keyboard.fill").foregroundColor(tint).accessibilityHidden(true)
                Text("Keystroke sounds").font(DS.Typo.title)
                    .foregroundColor(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            Text(statusText)
                .font(DS.Typo.micro)
                .padding(.horizontal, DS.Space.sm)
                .padding(.vertical, DS.Space.xxs)
                .background(mechey.isListening ? DS.Palette.success.opacity(0.22) : DS.Palette.surface2)
                .foregroundColor(mechey.isListening ? DS.Palette.success : (isOn ? DS.Palette.warning : DS.Palette.textSecondary))
                .clipShape(Capsule())
                .accessibilityLabel("Status: \(statusText.lowercased())")
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel("Play keystroke sounds")
        }
    }

    private var permissionCard: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: "lock.shield.fill")
                .foregroundColor(DS.Palette.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text("Input Monitoring needed")
                    .font(DS.Typo.labelStrong)
                    .foregroundColor(DS.Palette.textPrimary)
                Text("Turn on Tama in Privacy & Security › Input Monitoring, then come back.")
                    .font(DS.Typo.caption)
                    .foregroundColor(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            DroppyPillButton("Grant", systemName: "lock.open", tone: .accent,
                             help: "Ask for Input Monitoring access") {
                mechey.requestPermission()
            }
        }
        .padding(DS.Space.md)
        .dsSurface(1, radius: DS.Radius.sm, borderColor: DS.Palette.warning.opacity(0.4))
    }

    private var packPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.xs) {
                ForEach(MecheyPack.allCases) { item in
                    DroppyChip(item.title, systemName: item.iconName, isSelected: pack == item.rawValue) {
                        pack = item.rawValue
                        // Let the new pack render before playing it.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            mechey.preview(.letter, down: true)
                        }
                    }
                }
            }
        }
    }

    private var volumeRow: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 10))
                .foregroundColor(DS.Palette.textTertiary)
                .accessibilityHidden(true)
            Slider(value: $volume, in: 0...1) { editing in
                if !editing { mechey.preview(.letter, down: true) }
            }
            .controlSize(.small)
            .tint(tint)
            .accessibilityLabel("Volume")
            .accessibilityValue("\(Int((volume * 100).rounded())) percent")
            Text("\(Int((volume * 100).rounded()))%")
                .font(DS.Typo.numeric)
                .monospacedDigit()
                .foregroundColor(DS.Palette.textSecondary)
                .frame(width: 36, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private var keyPad: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(mechey.isRendering ? "Building sounds…" : "Tap to preview")
                .font(DS.Typo.caption)
                .foregroundColor(DS.Palette.textSecondary)
            HStack(spacing: DS.Space.xs) {
                ForEach([MecheyKey.modifier, .letter, .space, .backspace, .enter], id: \.self) { key in
                    MecheyPreviewKey(title: key.title, wide: key == .space) { down in
                        mechey.preview(key, down: down)
                    }
                }
            }
        }
    }
}

/// A key cap that sounds on press and on release, like the real thing.
private struct MecheyPreviewKey: View {
    let title: String
    let wide: Bool
    let onKey: (Bool) -> Void
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(DS.Palette.textPrimary)
            .frame(maxWidth: wide ? .infinity : 52, minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
                    .fill(isPressed ? DS.Palette.surface3 : DS.Palette.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
                    .strokeBorder(DS.Palette.hairline, lineWidth: 1)
            )
            // A lip on the bottom edge that flattens when pressed.
            .offset(y: isPressed ? 1.5 : 0)
            .shadow(color: .black.opacity(isPressed ? 0.1 : 0.35), radius: 0, y: isPressed ? 0.5 : 2)
            .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: isPressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        onKey(true)
                    }
                    .onEnded { _ in
                        isPressed = false
                        onKey(false)
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Preview \(title)")
            .accessibilityAction { onKey(true); onKey(false) }
    }
}
