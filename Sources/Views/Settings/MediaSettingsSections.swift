import SwiftUI
import AppKit

/// Settings › HUDs › Media and Media Controls, laid out like the reference:
/// Now Playing, Auto-hide preview, Now Playing display, Notch track title,
/// the Visualizer cards, Live audio visualizer and Live album artwork; then
/// the default music app, track swipe, notch click, playback buttons and the
/// source filters.
struct HUDsMediaSections: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject private var hudSettings = HUDSettings.shared
    @ObservedObject private var mediaSettings = MediaSettings.shared
    @ObservedObject private var liveLevels = LiveAudioLevels.shared
    @State private var buttonSource: MediaButtonSource = .appleMusic

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            media
            mediaControls
        }
    }

    // MARK: Media

    private var media: some View {
        SettingsSection("Media") {
            SettingsGroup {
                SettingsToggleRow("Now Playing",
                                  help: "Enable now-playing controls and metadata in the resting notch: the cover, the bars and, if you like, the title. Off, music stays out of the notch; the player on the shelf still works.",
                                  anchor: "huds.nowPlaying", isOn: $mediaSettings.nowPlayingEnabled)
                SettingsDivider()
                SettingsToggleRow("Auto-hide preview",
                                  help: "Fade out the mini player after a delay: once the music has been paused that long, the resting wings fold away. Playing again brings them back.",
                                  anchor: "huds.autoHide", isOn: $mediaSettings.mediaAutoHide)
                    .settingsDisabled(!mediaSettings.nowPlayingEnabled)
                if mediaSettings.mediaAutoHide {
                    SettingsDivider()
                    SettingsSlider("Hide after", value: $mediaSettings.mediaAutoHideDelay, in: 2...30, step: 1, defaultValue: 5,
                                   help: "How long music stays paused before the wings fold away.") { String(format: "%.0f s", $0) }
                        .settingsDisabled(!mediaSettings.nowPlayingEnabled)
                }
                SettingsDivider()
                SettingsRow("Now Playing size",
                            subtitle: "Regular or a smaller player on the shelf.",
                            help: "Smaller draws the whole player — cover, scrubber and transport — at 86 %, so the shelf takes less room while music plays.",
                            anchor: "huds.nowPlayingSize")
                ChoiceTiles(NowPlayingSize.allCases.map { .init($0, $0.title, icon: $0.icon) },
                            selection: $mediaSettings.nowPlayingSize)
                SettingsDivider()
                // Both only shape the music in the resting notch, which Now
                // Playing turns off as a whole (`showsMedia(on:)`).
                Group {
                    SettingsRow("Now Playing display",
                                subtitle: mediaSettings.nowPlayingEnabled ? nil : "Needs Now Playing.",
                                help: "Where the music shows when Tama is on more than one display. Under pointer: the island on the display you're using. MacBook: only the built-in display's notch (any display with the lid closed).",
                                anchor: "huds.nowPlayingDisplay")
                    ChoiceTiles([
                        .init(NowPlayingDisplay.underPointer, "Under pointer", icon: "cursorarrow.rays"),
                        .init(NowPlayingDisplay.macBook, "MacBook", icon: "laptopcomputer"),
                    ], selection: $mediaSettings.nowPlayingDisplay)
                    SettingsDivider()
                    SettingsToggleRow("Notch track title",
                                      subtitle: mediaSettings.nowPlayingEnabled
                                        ? "Only where there's room. A physical notch keeps its own width, so the song shows in the player there."
                                        : "Needs Now Playing.",
                                      help: "Write the song's title beside the cover on the floating island. A display with a physical notch keeps the hardware's outline while resting, so the title waits for the open player there.",
                                      anchor: "huds.trackTitle", isOn: $mediaSettings.notchTrackTitle)
                }
                .settingsDisabled(!mediaSettings.nowPlayingEnabled)
                SettingsDivider()
                SettingsRow("Visualizer", help: "Pick the Now Playing spectrum style: grey mono bars, or a two-tone ramp from the album art's colors (your highlight color when there's no art).",
                            anchor: "huds.visualizer")
                PreviewCardPicker([
                    PreviewCardOption(VisualizerStyle.mono, "Mono bars", subtitle: "Mono spectrum bars"),
                    PreviewCardOption(VisualizerStyle.gradient, "Gradient bars", subtitle: "Two-tone album art ramp"),
                ], selection: $mediaSettings.visualizerStyle, thumbnailHeight: 70) { style in
                    VisualizerThumbnail(style: style)
                }
                .padding(.top, -8)
                SettingsDivider()
                SettingsToggleRow("Live audio visualizer",
                                  help: "Bounce the bars to what's actually playing. Tama listens to the Mac's sound output to size them (macOS asks once for permission to record system audio); nothing is recorded or kept. Without the permission the bars keep their usual animation.",
                                  anchor: "huds.liveVisualizer", isOn: $mediaSettings.liveAudioVisualizer)
                if mediaSettings.liveAudioVisualizer && liveLevels.didFail {
                    HStack(alignment: .firstTextBaseline) {
                        SettingsNote("macOS didn't let Tama listen to the sound output (it needs macOS 14.2 and the System Audio Recording permission), so the bars are animated instead.",
                                     icon: "exclamationmark.triangle.fill", tint: DS.Palette.warning)
                        Button("Open Settings…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                        .padding(.trailing, 14)
                    }
                }
                SettingsDivider()
                SettingsToggleRow("Live album artwork",
                                  help: "Click the cover in the player to see it large, drifting slowly while the song plays; close it with ✕ or Esc. macOS doesn't share Music's animated covers with other apps, so the motion is Tama's. Off, clicking the cover opens the playing app.",
                                  anchor: "huds.liveArtwork", isOn: $mediaSettings.liveAlbumArtwork)
                SettingsDivider()
                SettingsToggleRow("Artwork tint",
                                  help: "Use gradient-based visuals: the open player washes the shelf in the album art's colors.",
                                  anchor: "huds.artworkTint", isOn: $mediaSettings.playerArtworkTint)
            }
        }
    }

    // MARK: Media Controls

    private var mediaControls: some View {
        SettingsSection("Media controls") {
            SettingsGroup {
                SettingsRow("Default music app",
                            help: "Choose which app Media HUD opens by default. Used when the player opens without an active source app: it offers to open it, and Play launches it and starts playing.",
                            anchor: "huds.defaultMusicApp")
                ChoiceTiles([
                    .init(DefaultMusicApp.appleMusic, "Apple Music", icon: "applelogo"),
                    .init(DefaultMusicApp.spotify, "Spotify", icon: "waveform.circle.fill"),
                ], selection: $mediaSettings.defaultMusicApp)
                SettingsDivider()
                SettingsRow("Track swipe",
                            help: "Two-finger swipe inside the Media widget to skip tracks — on the player, the media card, or the music in the resting notch. Scrolling up and down there still changes the volume.",
                            anchor: "huds.trackSwipe")
                ChoiceTiles([
                    .init(true, "On", icon: "hand.draw"),
                    .init(false, "Off", icon: "hand.raised.slash"),
                ], selection: $mediaSettings.trackSwipe)
                SettingsDivider()
                Group {
                    SettingsRow("Track swipe direction",
                                subtitle: mediaSettings.trackSwipe ? nil : "Needs Track swipe.",
                                help: "Flip the track-skip swipe. Standard: fingers moving left play the next song. Reversed: fingers moving right do.",
                                anchor: "huds.trackSwipeDirection")
                    ChoiceTiles([
                        .init(false, "Standard", icon: "arrow.left.and.right"),
                        .init(true, "Reversed", icon: "arrow.left.arrow.right"),
                    ], selection: $mediaSettings.trackSwipeReversed)
                }
                .settingsDisabled(!mediaSettings.trackSwipe)
                SettingsDivider()
                SettingsRow("On notch click",
                            help: "Open media on notch click: while music plays, a click on the notch opens the player. Default opens the page picked in Shelf › Pages.",
                            anchor: "huds.notchClick")
                ChoiceTiles([
                    .init(true, "Media widget", icon: "music.note"),
                    .init(false, "Default", icon: "house"),
                ], selection: $mediaSettings.notchClickOpensMedia)
                SettingsDivider()
                playbackButtons
                SettingsDivider()
                SettingsToggleRow("Filter media sources",
                                  help: "Choose which apps Tama shows and controls. An app you switch off is ignored, as if it weren't playing.",
                                  anchor: "huds.filterSources", isOn: $mediaSettings.filterMediaSources)
                if mediaSettings.filterMediaSources { sourceList }
                SettingsDivider()
                SettingsToggleRow("Hide Incognito media",
                                  help: "Hide media from private browsing windows. Chrome, Brave, Edge, Vivaldi, Opera and Chromium say which windows are incognito. Safari doesn't tell other apps which windows are private, so its private tabs can't be told apart.",
                                  anchor: "huds.hideIncognito", isOn: $mediaSettings.hideIncognitoMedia)
                SettingsDivider()
                SettingsToggleRow("Always use built-in speakers",
                                  subtitle: "A headset that connects doesn't take the sound with it.",
                                  help: "macOS hands the sound to headphones or a speaker the moment they connect. With this on, Tama hands it straight back to this Mac's own speakers. Picking an output by hand, here or in the player, still works.",
                                  anchor: "huds.builtInSpeakers", isOn: $hudSettings.alwaysUseBuiltInSpeakers)
            }
        }
    }

    /// "Choose which playback buttons appear for Regular Now Playing, Spotify,
    /// and Apple Music."
    private var playbackButtons: some View {
        let buttons = state.mediaButtons(for: buttonSource)
        return VStack(spacing: 0) {
            SettingsRow("Playback buttons",
                        help: "Choose which playback buttons appear for Regular Now Playing, Spotify, and Apple Music, either side of previous / play / next. Lyrics, Playing Next, favorite and the output still show after them unless you place them here.",
                        anchor: "huds.playbackButtons")
            ChoiceTiles([
                .init(MediaButtonSource.regular, "Regular", icon: "play.circle"),
                .init(MediaButtonSource.spotify, "Spotify", icon: "waveform.circle.fill"),
                .init(MediaButtonSource.appleMusic, "Apple Music", icon: "applelogo"),
            ], selection: $buttonSource)
            MediaButtonPickers(source: buttonSource)
            if buttons.left == .none && buttons.right == .none {
                SettingsNote("No playback buttons selected.")
            }
        }
    }

    private static let knownSources: [(id: String, name: String)] = [
        ("com.apple.Music", "Music"), ("com.spotify.client", "Spotify"), ("com.apple.Safari", "Safari"),
        ("com.google.Chrome", "Google Chrome"), ("com.brave.Browser", "Brave"), ("com.microsoft.edgemac", "Microsoft Edge"),
        ("company.thebrowser.Browser", "Arc"), ("com.vivaldi.Vivaldi", "Vivaldi"), ("com.operasoftware.Opera", "Opera"),
        ("org.chromium.Chromium", "Chromium"), ("com.apple.podcasts", "Podcasts"), ("com.apple.TV", "TV"),
        ("com.colliderli.iina", "IINA"), ("org.videolan.vlc", "VLC"),
    ]

    /// Installed players and browsers, plus whatever is playing now.
    private var sources: [(id: String, name: String)] {
        var list = Self.knownSources.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil }
        let track = MediaService.shared.currentTrack
        if !track.sourceBundleID.isEmpty, !list.contains(where: { $0.id == track.sourceBundleID }) {
            list.append((track.sourceBundleID, track.sourceApp))
        }
        for id in state.blockedMediaSourceIDs where !list.contains(where: { $0.id == id }) {
            list.append((id, id))
        }
        return list
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(sources, id: \.id) { source in
                Toggle(isOn: Binding(
                    get: { !state.blockedMediaSourceIDs.contains(source.id) },
                    set: { allowed in
                        var blocked = state.blockedMediaSourceIDs
                        if allowed { blocked.remove(source.id) } else { blocked.insert(source.id) }
                        state.blockedMediaSourceIDs = blocked
                    }
                )) {
                    HStack(spacing: 7) {
                        if let icon = AppIcon.image(bundleID: source.id) {
                            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                        }
                        Text(source.name).font(SettingsStyle.rowTitle)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Left and right button pickers for one source (used here and on the
/// Apple Music droplet's page).
struct MediaButtonPickers: View {
    let source: MediaButtonSource
    @ObservedObject private var state = AppState.shared

    var body: some View {
        let buttons = state.mediaButtons(for: source)
        HStack(spacing: 16) {
            picker("Left button", selection: buttons.left, left: true)
            picker("Right button", selection: buttons.right, left: false)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func picker(_ title: String, selection: MediaWidgetButton, left: Bool) -> some View {
        Picker(title, selection: Binding(get: { selection },
                                         set: { state.setMediaButton($0, for: source, left: left) })) {
            ForEach(source.options) { option in
                Label(option.title, systemImage: option.icon).tag(option)
            }
        }
        .fixedSize()
    }
}

/// A row of bars for the Visualizer cards: grey, or a pink-to-violet ramp
/// standing in for "album art colours".
private struct VisualizerThumbnail: View {
    let style: VisualizerStyle
    private let heights: [CGFloat] = [0.35, 0.55, 0.4, 0.8, 0.5, 0.95, 0.6, 0.45, 0.7]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .fill(fill(index))
                    .frame(width: 4, height: 26 * heights[index])
            }
        }
        .frame(height: 26, alignment: .bottom)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private func fill(_ index: Int) -> LinearGradient {
        switch style {
        case .mono:
            return LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.5)], startPoint: .top, endPoint: .bottom)
        case .gradient:
            let t = Double(index) / Double(heights.count - 1)
            let top = Color(hue: 0.93 - 0.12 * t, saturation: 0.75, brightness: 1)
            return LinearGradient(colors: [top, top.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: - Droplet pages

/// The settings rows a droplet's detail page carries, as Form sections:
/// Apple Music (Audio quality badge, Media widget) and Weather.
struct DropletSettingsSections: View {
    let id: String

    var body: some View {
        switch id {
        case "appleMusic": AppleMusicDropletSettings()
        case "weather": WeatherDropletSettings()
        case "termiNotch": TermiNotchDropletSettings()
        case "meetings": MeetingsDropletSettings()
        case "notifications": NotificationHUDDropletSettings()
        case "agents": AgentsDropletSettings()
        case "notchface": NotchfaceDropletSettings()
        case "snipper": ElementCaptureDropletSettings()
        case "ocr": OCRDropletSettings()
        case "windowSnapper": WindowSnapDropletSettings()
        case "liquidMouse": LiquidMouseDropletSettings()
        case "voiceTranscribe": VoiceTranscribeDropletSettings()
        case "thunderstorm": ThunderstormDropletSettings()
        case "menuBar": MenuBarManagerDropletSettings()
        case "localSend": LocalSendDropletSettings()
        case "pomodoro": ShelfOptionsLink(name: "Pomodoro", anchor: "shelf.pomodoro")
        case "caffeine": ShelfOptionsLink(name: "High Alert", anchor: "shelf.highAlert.mode")
        case "scratchpad": ShelfOptionsLink(name: "Notes", anchor: "shelf.notes.sync")
        default: EmptyView()
        }
    }
}

/// A droplet whose options live on the Shelf page: say so and go there,
/// rather than leave the detail page ending in nothing.
private struct ShelfOptionsLink: View {
    let name: String
    let anchor: String

    var body: some View {
        Section {
            LabeledContent {
                Button("Show in Shelf") {
                    if let entry = SettingsSearchIndex.entries.first(where: { $0.anchor == anchor }) {
                        SettingsNavigator.shared.reveal(entry)
                    }
                }
            } label: {
                Text("\(name) options are under Settings › Shelf › \(name).")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AppleMusicDropletSettings: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var mediaSettings = MediaSettings.shared

    var body: some View {
        Section {
            Toggle(isOn: $mediaSettings.audioQualityBadge) {
                HStack(spacing: 6) {
                    Text("Audio quality badge")
                    InfoButton("Show Lossless or Hi-Res Lossless beside the title when Music says the song is. Music only describes files it has (downloaded or in your library); for other streams the badge stays hidden rather than guess.")
                }
            }
            .settingsAnchor("droplet.appleMusic.quality")
        }
        Section {
            MediaButtonPickers(source: .appleMusic)
                .padding(.horizontal, -14)
                .settingsAnchor("droplet.appleMusic.buttons")
            let buttons = state.mediaButtons(for: .appleMusic)
            if buttons.left == .none && buttons.right == .none {
                Text("No playback buttons selected.").font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Media widget")
        } footer: {
            Text("Choose which playback buttons appear either side of previous / play / next while Music plays. Spotify and other players have their own in HUDs › Media controls.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct WeatherDropletSettings: View {
    @ObservedObject private var weatherSettings = WeatherSettings.shared
    @ObservedObject private var weather = WeatherService.shared
    @State private var query = ""
    @State private var results: [WeatherPlace] = []
    @State private var searchError: String?
    @State private var isSearching = false
    @State private var search: Task<Void, Never>?

    var body: some View {
        Section {
            Picker(selection: $weatherSettings.style) {
                Text("Colorful").tag(WeatherStyle.colorful)
                Text("Dark").tag(WeatherStyle.dark)
                Text("Liquid Glass").tag(WeatherStyle.liquidGlass)
            } label: {
                HStack(spacing: 6) {
                    Text("Weather style")
                    InfoButton("Choose a colorful, dark, or native macOS liquid glass look for the weather card.")
                }
            }
            .pickerStyle(.segmented)
            .settingsAnchor("droplet.weather.style")
        } header: {
            Text("Weather")
        }
        Section {
            Picker(selection: $weatherSettings.locationMode) {
                Text("Automatic location").tag(WeatherLocationMode.automatic)
                Text("Selected location").tag(WeatherLocationMode.fixed)
            } label: {
                HStack(spacing: 6) {
                    Text("Weather location")
                    InfoButton("Automatic uses this Mac's location (Location Services), rounded to about a kilometre before it's sent. Selected location shows the fixed place you pick below and never asks for your location.")
                }
            }
            .settingsAnchor("droplet.weather.location")
            if weatherSettings.locationMode == .fixed {
                LabeledContent("Showing") {
                    Text(weatherSettings.placeName.isEmpty ? "No place picked yet" : weatherSettings.placeName)
                        .foregroundStyle(weatherSettings.placeName.isEmpty ? .secondary : .primary)
                }
            } else if weather.isDenied {
                HStack {
                    Text("Allow automatic location lookup in System Settings, or pick a place.")
                        .font(.caption).foregroundStyle(DS.Palette.warning)
                    Spacer()
                    Button("Open Settings…") { weather.openLocationSettings() }.controlSize(.small)
                }
            }
            HStack {
                TextField("Search for a city", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(runSearch)
                    .onChange(of: query) { _, _ in scheduleSearch() }
                if isSearching { ProgressView().controlSize(.small) }
            }
            if let searchError {
                Text(searchError).font(.caption).foregroundStyle(DS.Palette.warning)
            }
            ForEach(results) { place in
                Button {
                    weather.choose(place)
                    query = ""
                    results = []
                    DroppyAudio.playTick()
                } label: {
                    HStack {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(place.name)
                            if !place.detail.isEmpty {
                                Text(place.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } footer: {
            Text("City search uses Open-Meteo's free geocoding; only what you type is sent.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Picker(selection: $weatherSettings.refreshMinutes) {
                Text("15 minutes").tag(15)
                Text("30 minutes").tag(30)
                Text("1 hour").tag(60)
                Text("2 hours").tag(120)
            } label: {
                HStack(spacing: 6) {
                    Text("Weather refresh interval")
                    InfoButton("How often weather data refreshes while a weather card, the droplet or the lock screen is showing.")
                }
            }
            .settingsAnchor("droplet.weather.refresh")
            Toggle(isOn: $weatherSettings.showsAQI) {
                HStack(spacing: 6) {
                    Text("Air quality")
                    InfoButton("Show AQI and air quality category.")
                }
            }
            .settingsAnchor("droplet.weather.aqi")
            Toggle(isOn: $weatherSettings.showsSun) {
                HStack(spacing: 6) {
                    Text("Sunrise & sunset")
                    InfoButton("Show sunrise and sunset times.")
                }
            }
            .settingsAnchor("droplet.weather.sun")
        }
        .onChange(of: weatherSettings.showsAQI) { _, _ in weather.refresh(force: true) }
    }

    /// Searches a moment after typing stops.
    private func scheduleSearch() {
        search?.cancel()
        searchError = nil
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else {
            results = []
            return
        }
        search = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await perform()
        }
    }

    private func runSearch() {
        search?.cancel()
        search = Task { await perform() }
    }

    private func perform() async {
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await WeatherService.searchPlaces(query)
            guard !Task.isCancelled else { return }
            results = found
            searchError = found.isEmpty ? "No places match “\(query)”." : nil
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            searchError = "Couldn't load locations. Try again."
        }
    }
}
