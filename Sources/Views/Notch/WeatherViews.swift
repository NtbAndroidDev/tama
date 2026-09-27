import SwiftUI

/// The weather card: "Local ➤" (or the fixed place), a thin large
/// temperature, the sky and today's range, then the next four hours.
/// Settings › Droplets › Weather picks its look: colorful, dark or grey
/// liquid glass. Location prompts, errors and loading take the card's place.
struct WeatherGlassCard: View {
    /// The Home card is compact; the droplet console draws it larger.
    var isLarge = false

    @ObservedObject private var weather = WeatherService.shared
    @ObservedObject private var state = AppState.shared

    private var radius: CGFloat { isLarge ? 26 : 22 }

    var body: some View {
        Group {
            if weather.isDenied {
                prompt("Allow Location to see the weather here, or pick a city in Settings.", button: "Open Settings…") {
                    weather.openLocationSettings()
                }
            } else if let now = weather.snapshot {
                conditions(now)
            } else if let error = weather.lastError {
                prompt(error, button: "Try again") { weather.refresh(force: true) }
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading weather")
            }
        }
        .padding(isLarge ? 16 : 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WeatherCardBackground(style: state.weatherStyle, snapshot: weather.snapshot, radius: radius))
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private func conditions(_ now: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(weather.placeTitle)
                            .font(.system(size: isLarge ? 15 : 13, weight: .bold))
                            .lineLimit(1)
                        if weather.isLocal {
                            Image(systemName: "location.fill")
                                .font(.system(size: isLarge ? 10 : 8.5, weight: .bold))
                        }
                    }
                    Text(now.bareTemperatureText)
                        .font(.system(size: isLarge ? 60 : 44, weight: .thin))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.top, -2)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: now.symbol)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: isLarge ? 22 : 17))
                    Text(now.summary)
                        .font(.system(size: isLarge ? 13.5 : 12, weight: .semibold))
                        .lineLimit(1)
                    if let range = now.rangeText {
                        Text(range)
                            .font(.system(size: isLarge ? 12.5 : 11, weight: .semibold).monospacedDigit())
                            .lineLimit(1)
                    }
                    extras(now)
                }
                .multilineTextAlignment(.trailing)
            }
            Spacer(minLength: 2)
            if !now.hourly.isEmpty {
                HStack(spacing: 0) {
                    ForEach(now.hourly) { hour in
                        VStack(spacing: isLarge ? 5 : 3) {
                            Text(hour.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted))))
                                .font(.system(size: isLarge ? 11 : 9.5, weight: .semibold).monospacedDigit())
                                .opacity(0.75)
                            Image(systemName: hour.symbol)
                                .symbolRenderingMode(.hierarchical)
                                .font(.system(size: isLarge ? 15 : 12))
                                .frame(height: isLarge ? 18 : 14)
                            Text(hour.temperatureText)
                                .font(.system(size: isLarge ? 12 : 10.5, weight: .bold).monospacedDigit())
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(weather.placeTitle), \(now.temperatureText), \(now.summary)\(now.rangeText.map { ", \($0)" } ?? "")")
    }

    /// Settings › Weather › AQI and Sunrise & sunset.
    @ViewBuilder
    private func extras(_ now: WeatherSnapshot) -> some View {
        let aqi = state.weatherShowsAQI ? now.aqi : nil
        let sun = state.weatherShowsSun ? now.nextSunEvent() : nil
        if aqi != nil || sun != nil {
            HStack(spacing: 6) {
                if let aqi {
                    Text("AQI \(aqi)")
                        .help(now.aqiLabel.map { "Air quality: \($0)" } ?? "Air quality")
                }
                if let sun {
                    Label(sun.date.formatted(date: .omitted, time: .shortened),
                          systemImage: sun.isSunset ? "sunset.fill" : "sunrise.fill")
                        .labelStyle(.titleAndIcon)
                        .help(sun.isSunset ? "Sunset" : "Sunrise")
                }
            }
            .font(.system(size: isLarge ? 11 : 9.5, weight: .semibold).monospacedDigit())
            .opacity(0.8)
            .lineLimit(1)
        }
    }

    private func prompt(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(weather.placeTitle, systemImage: weather.isLocal ? "location.fill" : "mappin")
                .font(.system(size: 12, weight: .bold))
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .opacity(0.75)
                .lineLimit(4)
            Spacer(minLength: 0)
            DroppyPillButton(button, tone: .tonal, action: action)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The card's surface for each Weather style.
private struct WeatherCardBackground: View {
    let style: WeatherStyle
    let snapshot: WeatherSnapshot?
    let radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            switch style {
            case .liquidGlass:
                // Grey macOS glass: a cool grey sheet with a lighter top edge.
                shape.fill(.ultraThinMaterial)
                shape.fill(LinearGradient(colors: [Color(red: 0.60, green: 0.64, blue: 0.72).opacity(0.92),
                                                   Color(red: 0.47, green: 0.51, blue: 0.59).opacity(0.92)],
                                          startPoint: .top, endPoint: .bottom))
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
            case .dark:
                shape.fill(Color.white.opacity(0.07))
                shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            case .colorful:
                shape.fill(LinearGradient(colors: sky, startPoint: .top, endPoint: .bottom))
                shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            }
        }
    }

    /// A sky for the conditions, day or night.
    private var sky: [Color] {
        guard let snapshot else { return [Color(red: 0.25, green: 0.52, blue: 0.92), Color(red: 0.38, green: 0.68, blue: 0.98)] }
        if !snapshot.isDay {
            return [Color(red: 0.06, green: 0.09, blue: 0.24), Color(red: 0.18, green: 0.22, blue: 0.45)]
        }
        switch snapshot.code {
        case 0, 1: return [Color(red: 0.18, green: 0.50, blue: 0.95), Color(red: 0.42, green: 0.72, blue: 1.0)]
        case 2, 3, 45, 48: return [Color(red: 0.40, green: 0.48, blue: 0.60), Color(red: 0.58, green: 0.65, blue: 0.75)]
        case 51...67, 80...82: return [Color(red: 0.24, green: 0.32, blue: 0.45), Color(red: 0.38, green: 0.47, blue: 0.60)]
        case 71...77, 85, 86: return [Color(red: 0.52, green: 0.62, blue: 0.76), Color(red: 0.74, green: 0.81, blue: 0.90)]
        case 95...99: return [Color(red: 0.20, green: 0.16, blue: 0.34), Color(red: 0.36, green: 0.30, blue: 0.52)]
        default: return [Color(red: 0.25, green: 0.52, blue: 0.92), Color(red: 0.38, green: 0.68, blue: 0.98)]
        }
    }
}

/// The Weather droplet's console: the large card, then where the weather is
/// for, when it was fetched, and a way into its settings.
struct WeatherConsoleView: View {
    @ObservedObject private var weather = WeatherService.shared
    @ObservedObject private var state = AppState.shared

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            WeatherGlassCard(isLarge: true)
                .frame(width: 300, height: 190)
            VStack(alignment: .leading, spacing: 10) {
                DroppyKeyValue(key: "Location", value: state.weatherLocationMode == .automatic ? "Automatic" : weather.placeTitle)
                DroppyKeyValue(key: "Refreshes", value: "Every \(refreshText)")
                if let now = weather.snapshot, let aqi = now.aqi, state.weatherShowsAQI {
                    DroppyKeyValue(key: "Air quality", value: now.aqiLabel.map { "\(aqi) · \($0)" } ?? "\(aqi)")
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    DroppyPillButton(weather.isLoading ? "Refreshing…" : "Refresh", systemName: "arrow.clockwise", tone: .tonal) {
                        weather.refresh(force: true)
                        DroppyAudio.playTick()
                    }
                    .disabled(weather.isLoading)
                    DroppyPillButton("Settings…", systemName: "gearshape", tone: .tonal) {
                        SettingsWindowController.shared.showWindow()
                        SettingsNavigator.shared.open(.droplets)
                        SettingsNavigator.shared.openDropletID = "weather"
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 190, alignment: .topLeading)
        }
        .padding(.top, 4)
        .onAppear { weather.start(for: "console") }
        .onDisappear { weather.stop(for: "console") }
    }

    private var refreshText: String {
        let minutes = state.weatherRefreshMinutes
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes) min"
    }
}
