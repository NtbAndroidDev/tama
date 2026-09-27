import SwiftUI

// MARK: - Lock screen

/// Settings › Lock screen, in the reference's order: the master switch with
/// animation and sound tiles and the two sound pickers, then Features (media
/// HUD, volume and brightness sliders, screensaver, keep awake), then Widgets.
struct LockScreenSettingsPage: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject private var weather = WeatherService.shared
    @ObservedObject private var calendar = CalendarService.shared
    private let sounds = LockSound.choices

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Lock screen") {
                SettingsGroup {
                    SettingsRow("Lock screen", icon: "lock.fill",
                                help: "Enable or disable all lock screen features. Nothing Tama draws covers the password field.",
                                anchor: "lock.enable") {
                        Toggle("Lock screen", isOn: $state.lockScreenEnabled).labelsHidden().toggleStyle(.switch)
                    }
                    ToggleTiles([
                        ToggleTile("Lock/unlock animation", icon: "lock.fill", isOn: $state.lockScreenAnimation),
                        ToggleTile("Lock & unlock sound", icon: "speaker.wave.2.fill", isOn: $state.lockScreenSounds),
                    ], anchor: "lock.animation")
                    .disabled(!state.lockScreenEnabled)
                    .opacity(state.lockScreenEnabled ? 1 : 0.5)
                    // Everything under the master switch is inert while it's off.
                    Group {
                        soundRow("Lock sound", help: "Plays the moment the screen locks.", selection: $state.lockScreenLockSound,
                                 locking: true, anchor: "lock.sound")
                        SettingsDivider()
                        soundRow("Unlock sound", help: "Plays the moment the screen unlocks.", selection: $state.lockScreenUnlockSound,
                                 locking: false, anchor: nil)
                    }
                    .disabled(!state.lockScreenEnabled)
                }
            }

            Group {
                SettingsSection("Features") {
                    SettingsGroup {
                        SettingsToggleRow("Lock screen media HUD", icon: "play.rectangle.fill",
                                          help: "Show Now Playing controls on the lock screen. Only drawn while something is playing or paused.",
                                          anchor: "lock.player", isOn: $state.lockScreenShowsPlayer)
                        SettingsDivider()
                        Group {
                            SettingsRow("Media HUD material",
                                        subtitle: state.lockScreenShowsPlayer ? nil : "Turn on the lock screen media HUD to choose its material.",
                                        anchor: "lock.mediaMaterial")
                            ChoiceTiles(LockSurfaceMaterial.allCases.map { .init($0, $0.title) },
                                        selection: $state.lockScreenMediaMaterial)
                        }
                        .disabled(!state.lockScreenShowsPlayer)
                        .opacity(state.lockScreenShowsPlayer ? 1 : 0.5)
                        SettingsDivider()
                        SettingsToggleRow("Volume slider", icon: "speaker.wave.2.fill",
                                          help: "A volume slider on the lock screen, above the media HUD.",
                                          anchor: "lock.volume", isOn: $state.lockScreenVolumeSlider)
                        SettingsDivider()
                        SettingsToggleRow("Brightness slider", icon: "sun.max",
                                          help: "A display brightness slider on the lock screen.",
                                          anchor: "lock.brightness", isOn: $state.lockScreenBrightnessSlider)
                        SettingsDivider()
                        SettingsToggleRow("Keep visible during screensaver", icon: "moon.stars",
                                          help: "Keep the widgets and media HUD above the screen saver. Off, they step aside while it runs.",
                                          anchor: "lock.screensaver", isOn: $state.lockScreenDuringScreensaver)
                        SettingsDivider()
                        SettingsSlider("Keep awake",
                                       value: Binding(get: { Double(LockKeepAwake.index(of: state.lockScreenKeepAwake)) },
                                                      set: { state.lockScreenKeepAwake = LockKeepAwake.stops[Int($0.rounded())] }),
                                       in: 0...Double(LockKeepAwake.stops.count - 1), step: 1, defaultValue: 0,
                                       help: "Keeps the display on for this long after locking, so the lock screen stays visible. Released as soon as you unlock.",
                                       anchor: "lock.keepAwake") { LockKeepAwake.title(LockKeepAwake.stops[Int($0.rounded())]) }
                    }
                }

                SettingsSection("Widgets") {
                    SettingsGroup {
                        SettingsToggleRow("Status widgets row", icon: "square.grid.2x2.fill",
                                          help: "Show centered widgets under the lock screen clock.",
                                          anchor: "lock.status", isOn: $state.lockScreenShowsStatusRow)
                        preview.padding(12)
                        Group {
                            SettingsRow("Widget style", help: "Vertical or rounded layout.", anchor: "lock.widgetStyle")
                            ChoiceTiles(LockWidgetStyle.allCases.map { .init($0, $0.title) },
                                        selection: $state.lockScreenWidgetStyle)
                            SettingsDivider()
                            SettingsRow("Widget look", help: "Light or dark widgets. Light shows dark text on light rounded tiles.",
                                        anchor: "lock.widgetLook")
                            ChoiceTiles([.init(LockWidgetLook.light, "Light", icon: "sun.max"),
                                         .init(LockWidgetLook.dark, "Dark", icon: "moon")],
                                        selection: $state.lockScreenWidgetLook)
                            SettingsDivider()
                            SettingsRow("Widget material", help: "Regular or liquid (rounded style).", anchor: "lock.widgetMaterial")
                            ChoiceTiles(LockSurfaceMaterial.allCases.map { .init($0, $0.title) },
                                        selection: $state.lockScreenWidgetMaterial)
                            SettingsDivider()
                            SettingsToggleRow("Mac battery", subtitle: "Show Mac battery percentage widget.", isOn: $state.lockScreenShowsBattery)
                            SettingsDivider()
                            SettingsToggleRow("Headphone battery", isOn: $state.lockScreenShowsHeadphones)
                            SettingsDivider()
                            SettingsToggleRow("Next event", isOn: $state.lockScreenShowsNextEvent)
                            if state.lockScreenShowsNextEvent && !calendar.hasEventAccess {
                                warning("Needs Calendar access to show your next event.") {
                                    Button("Allow…") { PermissionService.shared.request(.calendars) }
                                }
                            }
                            SettingsDivider()
                            SettingsToggleRow("Weather, air quality and sunset", isOn: $state.lockScreenShowsWeather)
                            if state.lockScreenShowsWeather { weatherStatus }
                        }
                        .disabled(!state.lockScreenShowsStatusRow)
                        .opacity(state.lockScreenShowsStatusRow ? 1 : 0.5)
                    }
                }
            }
            .disabled(!state.lockScreenEnabled)
            .opacity(state.lockScreenEnabled ? 1 : 0.5)
        }
    }

    /// A sound picker with ▶ to hear it.
    private func soundRow(_ title: String, help: String, selection: Binding<String>, locking: Bool, anchor: String?) -> some View {
        SettingsRow(title, help: help, anchor: anchor) {
            Button { LockSound.play(selection.wrappedValue, locking: locking) } label: {
                Image(systemName: "play.circle.fill").font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(selection.wrappedValue == LockSound.none)
            .help("Preview")
            .accessibilityLabel("Preview \(title.lowercased())")
            Picker(title, selection: selection) {
                ForEach(sounds, id: \.self) { id in
                    Label(LockSound.title(id), systemImage: id == LockSound.none ? "speaker.slash" : "speaker.wave.2")
                        .tag(id)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .disabled(!state.lockScreenSounds)
        // Dimmed once, whether the master switch or the sound tile is off.
        .opacity(state.lockScreenEnabled && state.lockScreenSounds ? 1 : 0.5)
    }

    /// The row as it will look, on a dark stand-in for the wallpaper.
    ///
    /// `scaleEffect` doesn't shrink the layout, so the 1100 pt row has to be
    /// measured and scaled inside a reader. Otherwise the card claims 1100 pt
    /// and the whole Widgets group overflows the page.
    private var preview: some View {
        let height = LockScreenStatusRow.height(for: state.lockScreenWidgetStyle)
        return GeometryReader { geo in
            let scale = min(geo.size.width / 1100, 0.52)
            LockScreenStatusRow()
                .frame(width: 1100, height: height)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
            .frame(height: height * 0.62)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [Color(red: 0.32, green: 0.4, blue: 0.55), Color(red: 0.08, green: 0.1, blue: 0.16)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(state.lockScreenEnabled && state.lockScreenShowsStatusRow ? 1 : 0.4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of the lock screen status row")
    }

    @ViewBuilder
    private var weatherStatus: some View {
        if weather.isDenied {
            warning("Tama isn't allowed to use Location, so it can't look up the weather.") {
                Button("Open Settings…") { weather.openLocationSettings() }
            }
        } else if let error = weather.lastError {
            warning(error) {
                Button("Try Again") { weather.refresh(force: true) }
            }
        } else if let now = weather.snapshot {
            SettingsNote("Now: \(now.temperatureText), \(now.summary)\(now.aqi.map { " · AQI \($0)" } ?? "")")
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Finding the weather where you are…").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.bottom, 10)
        }
        SettingsNote("From Open-Meteo. Only a location rounded to about a kilometre is sent, every 30 minutes.")
    }

    private func warning<Action: View>(_ text: String, @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(DS.Palette.warning)
            Spacer()
            action().controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.bottom, 10)
    }
}
