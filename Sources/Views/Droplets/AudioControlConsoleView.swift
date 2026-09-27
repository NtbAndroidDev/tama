import SwiftUI

// Audio Control Console — per-app volume, presented inside the Droplets lane.

public struct AudioControlConsoleView: View {
    @ObservedObject private var audio = AppAudioService.shared
    @ObservedObject private var output = AudioOutputService.shared

    private let tint = Color(red: 0.36, green: 0.60, blue: 0.98)

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            header
            masterRow

            if !AppAudioService.isSupported {
                DroppyEmptyState(
                    systemName: "slider.vertical.3",
                    title: "Needs macOS 14.2 or later",
                    subtitle: "Per-app volume uses Core Audio process taps, which arrived in macOS Sonoma 14.2. The system volume above still works."
                )
            } else {
                if let error = audio.captureError { errorCard(error) }
                if audio.apps.isEmpty {
                    DroppyEmptyState(
                        systemName: "speaker.slash",
                        title: "Nothing is playing",
                        subtitle: "Apps show up here as soon as they make a sound."
                    )
                } else {
                    // One row per app that is making sound: more than a handful
                    // outgrows the fixed console height, so the list scrolls.
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: DS.Space.xs) {
                            ForEach(audio.apps) { app in
                                AppVolumeRow(app: app, tint: tint)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { AppAudioService.shared.start() }
    }

    private var header: some View {
        HStack(spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "slider.vertical.3").foregroundColor(tint).accessibilityHidden(true)
                Text("Per-app volume").font(DS.Typo.title)
                    .foregroundColor(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            if AppAudioService.isSupported {
                DroppyPillButton("Reset all", systemName: "arrow.counterclockwise",
                                 help: "Set every app back to full volume and unmute them") {
                    audio.resetAll()
                    DroppyAudio.playTick()
                }
                .disabled(audio.gains.isEmpty && audio.muted.isEmpty && audio.captureError == nil)
            }
        }
    }

    private var masterRow: some View {
        HStack(spacing: DS.Space.sm) {
            DroppyIconButton(
                output.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                size: 24, tone: .tonal, isActive: output.isMuted,
                help: output.isMuted ? "Unmute" : "Mute"
            ) {
                output.setMuted(!output.isMuted)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("System · \(output.devices.first(where: { $0.id == output.currentDeviceID })?.name ?? "Output")")
                    .font(DS.Typo.caption)
                    .foregroundColor(DS.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Slider(value: Binding(get: { output.volume }, set: { output.setVolume($0) }), in: 0...1)
                    .controlSize(.small)
                    .tint(tint)
                    .disabled(!output.canSetVolume)
                    .accessibilityLabel("System volume")
                    .accessibilityValue(output.canSetVolume ? "\(Int((output.volume * 100).rounded())) percent" : "Fixed")
            }
            Text(output.canSetVolume ? "\(Int((output.volume * 100).rounded()))%" : "Fixed")
                .font(DS.Typo.numeric)
                .monospacedDigit()
                .foregroundColor(DS.Palette.textSecondary)
                .frame(width: 40, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .padding(DS.Space.sm)
        .dsSurface(1, radius: DS.Radius.sm)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(DS.Palette.warning)
                .accessibilityHidden(true)
            Text(message)
                .font(DS.Typo.caption)
                .foregroundColor(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            VStack(spacing: DS.Space.xs) {
                // App audio sits in the same System Settings pane as Screen Recording.
                DroppyPillButton("Settings", systemName: "gear", help: "Open Screen & System Audio Recording in System Settings") {
                    PermissionService.shared.openSettings(.screenRecording)
                }
                DroppyPillButton("Try again", systemName: "arrow.clockwise", tone: .accent,
                                 help: "Ask for app audio access again") {
                    audio.retryCapture()
                }
            }
        }
        .padding(DS.Space.md)
        .dsSurface(1, radius: DS.Radius.sm, borderColor: DS.Palette.warning.opacity(0.4))
    }
}

private struct AppVolumeRow: View {
    @ObservedObject private var audio = AppAudioService.shared
    let app: AppAudioEntry
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isMuted: Bool { audio.isMuted(app.id) }

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                Circle()
                    .fill(app.isPlaying ? DS.Palette.success : DS.Palette.textTertiary)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().strokeBorder(DS.Palette.ink, lineWidth: 1.2))
                    // The dot pulses with the app's level, unless Reduce Motion is on.
                    .scaleEffect(app.isPlaying && !reduceMotion ? 1 + CGFloat(audio.levels[app.id] ?? 0) * 0.5 : 1)
                    .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: audio.levels[app.id] ?? 0)
                    .offset(x: 2, y: 2)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(DS.Typo.label)
                    .foregroundColor(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .help(app.name)
                Slider(
                    value: Binding(get: { audio.gain(for: app.id) }, set: { audio.setGain($0, for: app.id) }),
                    in: 0...1.5
                )
                .controlSize(.mini)
                .tint(audio.gain(for: app.id) > 1 ? DS.Palette.warning : tint)
                .disabled(isMuted)
                .accessibilityLabel("\(app.name) volume")
                .accessibilityValue(isMuted ? "Muted" : "\(Int((audio.gain(for: app.id) * 100).rounded())) percent")
            }

            Text(isMuted ? "Muted" : "\(Int((audio.gain(for: app.id) * 100).rounded()))%")
                .font(DS.Typo.numeric)
                .monospacedDigit()
                .foregroundColor(isMuted ? DS.Palette.danger : DS.Palette.textSecondary)
                .frame(width: 44, alignment: .trailing)
                .accessibilityHidden(true)

            DroppyIconButton(
                isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                size: 22, tone: .plain, isActive: isMuted,
                help: isMuted ? "Unmute \(app.name)" : "Mute \(app.name)"
            ) {
                audio.toggleMute(app.id)
            }
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xs)
        .dsSurface(app.isPlaying ? 1 : 0, radius: DS.Radius.sm, border: false)
    }
}
