import SwiftUI
import AppKit

// What Tama draws on the lock screen: a row of glanceable status under the
// system clock, and the player above the login field. Both sit on the user's
// wallpaper, so text is white with a soft shadow instead of on a card.

/// Battery, headphones, air quality, weather, the next sunrise or sunset and
/// the next event, each only when it has something to say.
struct LockScreenStatusRow: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var lockScreenSettings = LockScreenSettings.shared
    @ObservedObject private var monitor = SystemMonitorService.shared
    @ObservedObject private var weather = WeatherService.shared
    @ObservedObject private var headphones = HeadphoneBatteryService.shared
    /// Looked up once a minute, not on every battery tick that redraws the row.
    @State private var nextEvent: AgendaEntry?

    /// The panel's height for a widget style.
    static func height(for style: LockWidgetStyle) -> CGFloat {
        switch style {
        case .inline: 60
        case .vertical: 96
        case .rounded: 110
        }
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: lockScreenSettings.widgetStyle == .inline ? 30 : 16) {
                if lockScreenSettings.showsBattery, monitor.hasBattery {
                    LockScreenStatusItem(
                        symbol: monitor.isCharging ? "laptopcomputer.and.arrow.down" : "laptopcomputer",
                        value: "\(monitor.batteryLevel)%",
                        detail: monitor.isCharging ? "Charging" : nil
                    )
                }
                if lockScreenSettings.showsHeadphones, let buds = headphones.battery, let level = buds.level {
                    LockScreenStatusItem(
                        symbol: buds.name.localizedCaseInsensitiveContains("airpods") ? "airpods" : "headphones",
                        value: "\(level)%",
                        detail: buds.detail
                    )
                }
                if lockScreenSettings.showsWeather, let now = weather.snapshot {
                    if let aqi = now.aqi {
                        LockScreenStatusItem(symbol: "aqi.medium", value: "AQI \(aqi)", detail: now.aqiLabel)
                    }
                    LockScreenStatusItem(symbol: now.symbol, value: now.temperatureText, detail: now.summary)
                    if let sun = now.nextSunEvent(after: context.date) {
                        LockScreenStatusItem(
                            symbol: sun.isSunset ? "sunset.fill" : "sunrise.fill",
                            value: sun.date.formatted(date: .omitted, time: .shortened),
                            detail: nil
                        )
                    }
                }
                if lockScreenSettings.showsNextEvent, let event = nextEvent {
                    LockScreenStatusItem(symbol: "calendar", value: event.title, detail: when(event), valueMaxWidth: 260)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { monitor.subscribe() }
        .onDisappear { monitor.unsubscribe() }
        .task {
            while !Task.isCancelled {
                nextEvent = CalendarService.shared.nextEvent()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func when(_ event: AgendaEntry) -> String? {
        guard let start = event.start else { return nil }
        if Calendar.current.isDateInToday(start) { return start.formatted(date: .omitted, time: .shortened) }
        return start.formatted(.dateTime.day().month(.abbreviated))
    }
}

struct LockScreenStatusItem: View {
    let symbol: String
    let value: String
    let detail: String?
    var valueMaxWidth: CGFloat? = nil
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var lockScreenSettings = LockScreenSettings.shared

    init(symbol: String, value: String, detail: String?, valueMaxWidth: CGFloat? = nil) {
        self.symbol = symbol
        self.value = value
        self.detail = detail
        self.valueMaxWidth = valueMaxWidth
    }

    /// Light look: dark text (on light tiles); dark look: white text.
    private var ink: Color { lockScreenSettings.widgetLook == .light && lockScreenSettings.widgetStyle == .rounded ? .black : .white }

    var body: some View {
        switch lockScreenSettings.widgetStyle {
        case .inline: inline
        case .vertical: vertical.foregroundStyle(ink).shadow(color: .black.opacity(0.35), radius: 6, y: 1)
        case .rounded:
            vertical
                .foregroundStyle(ink)
                .frame(minWidth: 96)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(LockSurface(material: lockScreenSettings.widgetMaterial, look: lockScreenSettings.widgetLook,
                                        cornerRadius: 22))
                .accessibilityElement(children: .combine)
        }
    }

    /// Icon over value over detail.
    private var vertical: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .symbolRenderingMode(.hierarchical)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .frame(maxWidth: valueMaxWidth ?? 200)
                .fixedSize(horizontal: valueMaxWidth == nil, vertical: false)
            if let detail {
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .opacity(0.65)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var inline: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .symbolRenderingMode(.hierarchical)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .frame(maxWidth: valueMaxWidth, alignment: .leading)
                .fixedSize(horizontal: valueMaxWidth == nil, vertical: false)
            if let detail {
                Text(detail)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
        .accessibilityElement(children: .combine)
    }
}

/// Now Playing, above the login field: artwork, title, progress and the
/// transport. Only drawn while something is playing or paused.
struct LockScreenPlayer: View {
    static let size = CGSize(width: 440, height: 214)

    @ObservedObject private var media = MediaService.shared
    private var track: MediaTrack { media.currentTrack }

    var body: some View {
        Group {
            if track.hasTrack {
                card
            } else {
                Color.clear
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var card: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                AlbumArtView(image: track.artworkImage, size: 72, radius: 12)
                    .overlay(alignment: .bottomTrailing) {
                        let bundleID = track.sourceBundleID.isEmpty ? AppIcon.bundleID(forPlayer: track.sourceApp) : track.sourceBundleID
                        if let icon = AppIcon.image(bundleID: bundleID) {
                            Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                                .offset(x: 4, y: 4)
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(track.artist)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let position = media.livePosition(at: context.date)
                let duration = max(track.duration, 0)
                HStack(spacing: 10) {
                    Text(format(position))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.22))
                            Capsule().fill(.white)
                                .frame(width: duration > 0 ? geo.size.width * min(position / duration, 1) : 0)
                        }
                    }
                    .frame(height: 5)
                    Text("-" + format(max(duration - position, 0)))
                }
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .opacity(duration > 0 ? 1 : 0)
                .accessibilityElement()
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(format(position)) of \(format(duration))")
            }

            HStack {
                control(track.isLiked ? "star.fill" : "star", size: 16, help: track.isLiked ? "Unlike" : "Like") {
                    media.toggleLike()
                }
                .opacity(track.supportsLike ? 1 : 0)
                .disabled(!track.supportsLike)
                // Invisible when the player can't like; VoiceOver mustn't find it either.
                .accessibilityHidden(!track.supportsLike)
                Spacer()
                control("backward.fill", size: 22, help: "Previous") { media.previousTrack() }
                Spacer().frame(width: 26)
                control(track.isPlaying ? "pause.fill" : "play.fill", size: 30, help: track.isPlaying ? "Pause" : "Play") {
                    media.togglePlayPause()
                }
                Spacer().frame(width: 26)
                control("forward.fill", size: 22, help: "Next") { media.nextTrack() }
                Spacer()
                // Balances the star so the transport stays centred.
                Color.clear.frame(width: 30, height: 30)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        // Settings › Lock screen › Media HUD material.
        .background(LockSurface(material: LockScreenSettings.shared.mediaMaterial, look: .dark, cornerRadius: 28))
    }

    private func control(_ symbol: String, size: CGFloat, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: size + 14, height: size + 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.86))
        .help(help)
        .accessibilityLabel(help)
    }

    private func format(_ time: TimeInterval) -> String {
        let seconds = Int(time.rounded(.down))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// The fill behind a lock-screen card: translucent dark, a frosted blur of the
/// wallpaper, or frosted glass with a sheen and a light rim; light or dark.
struct LockSurface: View {
    let material: LockSurfaceMaterial
    let look: LockWidgetLook
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            switch material {
            case .dark:
                shape.fill(look == .light ? Color.white.opacity(0.55) : Color.black.opacity(0.38))
            case .regular:
                VisualEffectView(material: look == .light ? .popover : .hudWindow, blendingMode: .behindWindow)
                    .clipShape(shape)
                shape.fill(look == .light ? Color.white.opacity(0.35) : Color.black.opacity(0.12))
            case .liquid:
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(shape)
                shape.fill(look == .light ? Color.white.opacity(0.45) : Color.black.opacity(0.2))
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.03), .clear],
                                          startPoint: .top, endPoint: .bottom))
            }
        }
        .overlay(
            shape.strokeBorder(
                material == .liquid
                    ? AnyShapeStyle(LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.08)],
                                                   startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(Color.white.opacity(0.14)),
                lineWidth: material == .liquid ? 1 : 0.8)
        )
    }
}

/// Volume and brightness on the lock screen (Settings › Lock screen ›
/// Volume slider / Brightness slider).
struct LockScreenControls: View {
    static let size = CGSize(width: 440, height: 54)

    @ObservedObject private var state = AppState.shared
    @ObservedObject private var lockScreenSettings = LockScreenSettings.shared
    @ObservedObject private var outputs = AudioOutputService.shared
    @State private var brightness: Double = BrightnessService.shared.brightness ?? 0.5

    var body: some View {
        HStack(spacing: 18) {
            if lockScreenSettings.volumeSlider {
                slider(icon: IslandHUD.Kind.volume.iconName(for: outputs.isMuted ? 0 : outputs.volume, isMuted: outputs.isMuted),
                       label: "Volume",
                       value: Binding(get: { outputs.isMuted ? 0 : outputs.volume }, set: { outputs.setVolume($0) }))
                    .disabled(!outputs.canSetVolume)
            }
            if lockScreenSettings.brightnessSlider {
                slider(icon: IslandHUD.Kind.brightness.iconName(for: brightness, isMuted: false),
                       label: "Brightness",
                       value: Binding(get: { brightness }, set: { level in
                           brightness = level
                           BrightnessService.shared.setBrightness(level)
                       }))
                    .disabled(!BrightnessService.shared.canSetBrightness)
            }
        }
        .foregroundStyle(.white)
        .tint(.white)
        .padding(.horizontal, 18)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(LockSurface(material: lockScreenSettings.mediaMaterial, look: .dark, cornerRadius: Self.size.height / 2))
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            // Brightness has no change notification; follow the keys.
            guard let now = BrightnessService.shared.brightness, abs(now - brightness) > 0.005 else { return }
            brightness = now
        }
    }

    private func slider(icon: String, label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 20)
                .accessibilityHidden(true)
            Slider(value: value, in: 0...1)
                .controlSize(.small)
                .accessibilityLabel(label)
        }
    }
}
