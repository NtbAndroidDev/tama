import SwiftUI
import AppKit

/// Lyrics or Playing Next, opened beside the player; the output picker has its own flag.
public enum PlayerPanel: Equatable, Sendable {
    case none, lyrics, upNext
}

/// The home page of the shelf: the full player — a big cover with its source
/// badge, the scrubber and one transport row — with Lyrics or Playing Next
/// opening as a column beside it and the audio output picker under it.
public struct PlayerPage: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var mediaSettings = MediaSettings.shared
    @ObservedObject private var media = MediaService.shared
    @ObservedObject private var outputs = AudioOutputService.shared
    @ObservedObject private var lyrics = LyricsService.shared
    @AppStorage(LyricsService.onlineKey) private var lyricsOnline = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    private var track: MediaTrack { media.currentTrack }
    /// The side column only exists for the full player; a solo player in
    /// the Home editor keeps to itself.
    private var showsSidePanel: Bool { state.showsFullPlayer && state.playerPanel != .none }
    private var source: MediaButtonSource {
        MediaButtonSource.of(bundleID: track.sourceBundleID.isEmpty ? (AppIcon.bundleID(forPlayer: track.sourceApp) ?? "") : track.sourceBundleID)
    }
    private var palette: ArtworkPalette { ArtworkPalette.current(track) ?? .fallback }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            playerColumn
                .frame(width: showsSidePanel ? DroppyShelfMetrics.playerWidth - DroppyShelfMetrics.horizontalPadding * 2 : nil)
                .frame(maxWidth: showsSidePanel ? nil : .infinity)
            if showsSidePanel {
                Rectangle()
                    .fill(DS.Palette.hairline)
                    .frame(width: 1, height: DroppyShelfMetrics.playerHeight - 20)
                    .padding(.top, 10)
                    .padding(.horizontal, (PlayerMetrics.sidePanelGap - 1) / 2)
                sidePanel
                    .frame(width: PlayerMetrics.sidePanelWidth, height: DroppyShelfMetrics.playerHeight)
                    .transition(DS.Motion.transition(reduceMotion, .opacity.combined(with: .move(edge: .trailing))))
            }
        }
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid), value: state.isOutputPickerOpen)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid), value: state.playerPanel)
        .onHover { state.isPointerOverMediaWidget = $0 }
        .onChange(of: "\(track.title)|\(track.artist)") { _, _ in refreshPanel(); autoExpandLyrics() }
        .onChange(of: track.sourceApp) { _, _ in refreshPanel() }
        .onChange(of: lyricsOnline) { _, _ in refreshPanel() }
        .onChange(of: lyrics.state) { _, _ in openLyricsIfFound() }
        .onChange(of: outputs.devices.count) { _, _ in resizeForOutputs() }
        .onAppear {
            refreshPanel()
            autoExpandLyrics()
        }
        .onDisappear { state.isPointerOverMediaWidget = false }
    }

    private var playerColumn: some View {
        VStack(spacing: 0) {
            header
            Group {
                if !track.hasTrack {
                    idleRow
                } else if track.needsBrowserJavaScript {
                    browserScrubHint
                } else {
                    PlayerScrubber(track: track, showsRemaining: mediaSettings.playerShowsRemaining)
                }
            }
            .frame(height: PlayerMetrics.scrubberHeight)
            .padding(.top, PlayerMetrics.scrubberGap)
            controls.padding(.top, PlayerMetrics.controlsGap)
            if state.isOutputPickerOpen {
                outputPicker
                    .transition(DS.Motion.transition(reduceMotion, .opacity.combined(with: .move(edge: .top))))
            }
        }
    }

    // MARK: Side panel

    @ViewBuilder
    private var sidePanel: some View {
        switch state.playerPanel {
        case .lyrics: LyricsCard(palette: palette)
        case .upNext: PlayingNextColumn()
        case .none: EmptyView()
        }
    }

    private func toggle(_ target: PlayerPanel) {
        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) {
            state.isOutputPickerOpen = false
            state.playerPanel = state.playerPanel == target ? .none : target
        }
        refreshPanel()
        DroppyAudio.playTick()
    }

    private func refreshPanel() {
        switch state.playerPanel {
        case .lyrics: LyricsService.shared.load(for: track)
        case .upNext: media.refreshUpNext()
        case .none: break
        }
    }

    /// Settings › Shelf › Auto-expand lyrics: look the song up, and open the
    /// card once lyrics are found (not for a miss).
    private func autoExpandLyrics() {
        guard mediaSettings.autoExpandLyrics, state.showsFullPlayer, track.hasTrack, lyricsOnline,
              state.playerPanel == .none, !state.isOutputPickerOpen else { return }
        LyricsService.shared.load(for: track)
        openLyricsIfFound()
    }

    private func openLyricsIfFound() {
        guard mediaSettings.autoExpandLyrics, state.showsFullPlayer, track.hasTrack,
              state.playerPanel == .none, !state.isOutputPickerOpen,
              case .loaded = lyrics.state else { return }
        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { state.playerPanel = .lyrics }
    }

    /// A speaker plugged in or removed while the picker is open changes its height.
    private func resizeForOutputs() {
        guard state.isOutputPickerOpen else { return }
        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { state.objectWillChange.send() }
        state.onIslandFrameChange?(state.isIslandExpanded)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: PlayerMetrics.headerSpacing) {
            Button {
                // Settings › HUDs › Live album artwork opens the cover large.
                if mediaSettings.liveAlbumArtwork, track.hasTrack {
                    ArtworkWindowController.shared.show()
                } else if track.hasTrack {
                    media.openSourceApp()
                } else {
                    media.launchDefaultMusicApp(andPlay: false)
                }
            } label: {
                AlbumArtView(image: track.artworkImage, size: PlayerMetrics.artwork, radius: PlayerMetrics.artworkRadius)
                    .overlay(alignment: .bottomTrailing) {
                        if let icon = AppIcon.image(bundleID: badgeBundleID) {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: PlayerMetrics.sourceBadge, height: PlayerMetrics.sourceBadge)
                                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                                .offset(x: 4, y: 4)
                        }
                    }
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .help(artworkHelp)
            .accessibilityLabel(artworkHelp)

            VStack(alignment: .leading, spacing: 3) {
                // The wave sits in the title's row so a long title truncates
                // before it instead of running underneath.
                HStack(alignment: .center, spacing: 8) {
                    Text(track.hasTrack ? track.title : "Not playing")
                        .font(.system(size: PlayerMetrics.titleSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .optionalHelp(track.hasTrack ? track.title : nil)
                    if let quality = qualityBadge {
                        AudioQualityBadge(text: quality)
                    }
                    Spacer(minLength: 0)
                    if track.hasTrack {
                        WaveBars(isPlaying: track.isPlaying, bars: 6, height: 12, barWidth: 2.2)
                            .fixedSize()
                    }
                }
                Text(track.hasTrack ? track.artist : "Play something in Music, Spotify or a browser")
                    .font(.system(size: PlayerMetrics.subtitleSize, weight: .medium))
                    .foregroundStyle(NotchPalette.secondary)
                    .lineLimit(1)
                    .optionalHelp(track.hasTrack ? track.artist : nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The playing app, or the default music app before anything plays.
    private var badgeBundleID: String? {
        guard track.hasTrack else { return mediaSettings.defaultMusicApp.bundleID }
        return track.sourceBundleID.isEmpty ? AppIcon.bundleID(forPlayer: track.sourceApp) : track.sourceBundleID
    }

    private var artworkHelp: String {
        if !track.hasTrack { return "Open \(mediaSettings.defaultMusicApp.shortTitle)" }
        if mediaSettings.liveAlbumArtwork { return "Show album art" }
        return track.sourceApp.isEmpty ? "Now Playing" : "Open \(track.sourceApp)"
    }

    /// Settings › Droplets › Apple Music › Audio quality badge.
    private var qualityBadge: String? {
        guard mediaSettings.audioQualityBadge, source == .appleMusic,
              state.droplets.first(where: { $0.id == "appleMusic" })?.isEnabled ?? true else { return nil }
        return track.audioQuality
    }

    // MARK: Idle

    /// Nothing plays: open the default music app (Settings › HUDs › Media Controls).
    private var idleRow: some View {
        HStack(spacing: 8) {
            Spacer()
            DroppyPillButton("Open \(mediaSettings.defaultMusicApp.shortTitle)", systemName: "arrow.up.forward.app", tone: .tonal,
                             help: "Launches \(mediaSettings.defaultMusicApp.title) when nothing is currently playing.") {
                media.launchDefaultMusicApp(andPlay: false)
            }
            Spacer()
        }
        .frame(height: 26)
    }

    /// Shown instead of the scrubber while the browser keeps the tab's
    /// position to itself; the menu path differs between Safari and Chromium.
    private var browserScrubHint: some View {
        let path = track.sourceBundleID == "com.apple.Safari"
            ? "Develop › Allow JavaScript from Apple Events"
            : "View › Developer › Allow JavaScript from Apple Events"
        return Label("To scrub, turn on \(track.sourceApp) › \(path)", systemImage: "info.circle")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.55))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .help("\(track.sourceApp) only shares the video's position and lets Tama seek once this option is on.")
    }

    // MARK: Controls

    /// One centred row: the source's left button, previous / play / next, its
    /// right button, then favourite, lyrics, Playing Next (Music) and the
    /// output — each only once, so a button chosen for a side isn't repeated.
    private var controls: some View {
        let slots = state.mediaButtons(for: source)
        let placed: Set<MediaWidgetButton> = [slots.left, slots.right]
        var extras: [MediaWidgetButton] = []
        if track.supportsLike { extras.append(.favorite) }
        extras.append(.lyrics)
        if source == .appleMusic { extras.append(.queue) }
        extras.append(.output)
        extras.removeAll { placed.contains($0) }
        return HStack(spacing: 5) {
            sideButton(slots.left)
            transportButton("backward.fill", size: PlayerMetrics.skipIcon, help: "Previous") { media.previousTrack() }
                .disabled(!track.hasTrack)
            transportButton(track.isPlaying ? "pause.fill" : "play.fill", size: PlayerMetrics.playIcon,
                            help: track.isPlaying ? "Pause" : (track.hasTrack ? "Play" : "Play \(mediaSettings.defaultMusicApp.shortTitle)")) {
                media.togglePlayPause()
            }
            transportButton("forward.fill", size: PlayerMetrics.skipIcon, help: "Next") { media.nextTrack() }
                .disabled(!track.hasTrack)
            sideButton(slots.right)
            ForEach(extras) { sideButton($0) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: PlayerMetrics.controlsHeight)
    }

    @ViewBuilder
    private func sideButton(_ button: MediaWidgetButton) -> some View {
        switch button {
        case .none:
            EmptyView()
        case .shuffle:
            PlayerSideButton(icon: "shuffle", isActive: track.shuffle == true, tint: palette.primary,
                             help: track.shuffle == true ? "Turn shuffle off" : "Shuffle") { media.toggleShuffle() }
                .disabled(!track.supportsShuffleRepeat)
        case .repeat:
            PlayerSideButton(icon: track.repeatMode == .one ? "repeat.1" : "repeat",
                             isActive: (track.repeatMode ?? .off) != .off, tint: palette.primary,
                             help: repeatHelp) { media.cycleRepeat() }
                .disabled(!track.supportsShuffleRepeat)
        case .favorite:
            PlayerSideButton(icon: track.isLiked ? "heart.fill" : "heart", isActive: track.isLiked, tint: palette.primary,
                             help: track.isLiked ? "Remove from favorites" : "Add to favorites") { media.toggleLike() }
                .disabled(!track.supportsLike)
        case .lyrics:
            PlayerSideButton(icon: "quote.bubble", isActive: state.playerPanel == .lyrics, tint: palette.primary,
                             help: lyricsOnline ? "Lyrics" : "Lyrics (looked up online once you allow it)") { toggle(.lyrics) }
                .disabled(!state.showsFullPlayer)
        case .queue:
            PlayerSideButton(icon: "list.bullet", isActive: state.playerPanel == .upNext, tint: palette.primary,
                             help: "Playing Next") { toggle(.upNext) }
                .disabled(!state.showsFullPlayer)
        case .output:
            PlayerSideButton(icon: currentOutputIcon, isActive: state.isOutputPickerOpen, tint: palette.primary,
                             help: "Choose audio output") {
                outputs.refresh()
                withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) {
                    state.playerPanel = .none
                    state.isOutputPickerOpen.toggle()
                }
                DroppyAudio.playTick()
            }
        }
    }

    private var repeatHelp: String {
        switch track.repeatMode ?? .off {
        case .off: "Repeat"
        case .all: source == .spotify ? "Turn repeat off" : "Repeat one"
        case .one: "Turn repeat off"
        }
    }

    private func transportButton(_ name: String, size: CGFloat, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: PlayerMetrics.transportFrame.width, height: PlayerMetrics.transportFrame.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.8))
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: Output picker

    private var currentOutputIcon: String {
        outputs.devices.first(where: { $0.id == outputs.currentDeviceID })?.iconName ?? "laptopcomputer"
    }

    private var outputPicker: some View {
        VStack(spacing: 9) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 64, height: 1.5)
                .padding(.vertical, 3)

            if outputs.devices.isEmpty {
                DroppyEmptyState(systemName: "speaker.slash", title: "No audio outputs available", compact: true)
            }
            ForEach(outputs.devices) { device in
                OutputRow(
                    device: device,
                    isCurrent: device.id == outputs.currentDeviceID,
                    volume: device.id == outputs.currentDeviceID ? outputs.volume : outputs.volume(for: device)
                ) {
                    outputs.select(device)
                    DroppyAudio.playTick()
                }
            }
        }
        .padding(.top, 8)
    }

}

// MARK: - Scrubber

/// The bar and its two times. Its own view, observing only the playhead, so
/// the twice-a-second tick redraws this row and not the whole player.
private struct PlayerScrubber: View {
    let track: MediaTrack
    let showsRemaining: Bool

    @ObservedObject private var playhead = MediaService.shared.playhead
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var media: MediaService { MediaService.shared }
    private var position: TimeInterval { playhead.position }
    private var progress: Double {
        if isScrubbing { return scrubValue }
        guard track.duration > 0 else { return 0 }
        return min(max(position / track.duration, 0), 1)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(track.duration <= 0 ? "--:--" : isScrubbing ? format(track.duration * scrubValue) : clock(position))
                .frame(minWidth: PlayerMetrics.timeMinWidth, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(NotchPalette.track)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: max(7, geo.size.width * progress))
                }
                .frame(height: isScrubbing ? PlayerMetrics.trackThicknessScrubbing : PlayerMetrics.trackThickness)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            isScrubbing = true
                            scrubValue = min(max(g.location.x / max(geo.size.width, 1), 0), 1)
                        }
                        .onEnded { _ in
                            // An unknown length would turn any drag into a seek to 0:00.
                            if track.duration > 0 { media.seek(to: track.duration * scrubValue) }
                            isScrubbing = false
                        }
                )
            }
            .frame(height: 12)
            // Only the bar is off-limits for a source that can't seek; the
            // length / remaining toggle beside it still works.
            .allowsHitTesting(track.supportsSeek)
            .animation(DS.Motion.respecting(reduceMotion, DS.Motion.hover), value: isScrubbing)
            // The drag is invisible to VoiceOver, so expose the bar as an adjustable control.
            .accessibilityElement()
            .accessibilityLabel("Playback position")
            .accessibilityValue(track.duration <= 0 ? "Unavailable" : "\(clock(position)) of \(track.formattedDuration)")
            .accessibilityAdjustableAction { direction in
                guard track.supportsSeek, track.duration > 0 else { return }
                let step: TimeInterval = direction == .increment ? 10 : direction == .decrement ? -10 : 0
                media.seek(to: min(max(media.livePosition() + step, 0), track.duration))
            }
            // Remaining ("-1:05") or the length ("2:32"); click to switch.
            Button {
                MediaSettings.shared.playerShowsRemaining.toggle()
                DroppyAudio.playTick()
            } label: {
                Text(trailingTime)
                    .frame(minWidth: PlayerMetrics.timeMinWidth, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.94))
            .help(showsRemaining ? "Show the song's length" : "Show the time remaining")
            .accessibilityLabel(showsRemaining ? "Time remaining" : "Song length")
            .accessibilityValue(trailingTime)
            .accessibilityHint(showsRemaining ? "Shows the song's length" : "Shows the time remaining")
        }
        .font(.system(size: PlayerMetrics.timeSize, weight: .medium).monospacedDigit())
        .foregroundStyle(DS.Palette.textSecondary)
    }

    private var trailingTime: String {
        guard track.duration > 0 else { return "--:--" }
        if !showsRemaining { return format(track.duration) }
        return "-" + format(max(track.duration - track.duration * progress, 0))
    }

    private func format(_ time: TimeInterval) -> String {
        let t = Int(max(time, 0).rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    /// Like `MediaTrack.formattedPosition`: truncated, not rounded.
    private func clock(_ time: TimeInterval) -> String {
        String(format: "%d:%02d", Int(time) / 60, Int(time) % 60)
    }
}

/// A round button beside the transport. On, it takes a soft disc in the
/// artwork's colour (the reference's green shuffle and repeat for Spotify).
private struct PlayerSideButton: View {
    let icon: String
    let isActive: Bool
    let tint: Color
    let help: String
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: PlayerMetrics.sideIcon, weight: .semibold))
                .foregroundStyle(isActive ? tint : .white.opacity(isHovered ? 1 : 0.78))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: PlayerMetrics.sideButton, height: PlayerMetrics.sideButton)
                .background(
                    Circle().fill(isActive ? tint.opacity(0.2) : (isHovered && isEnabled ? Color.white.opacity(0.1) : .clear))
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovered = isEnabled && $0 }
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// "Lossless" / "Hi-Res Lossless" beside the title (Apple Music).
struct AudioQualityBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "waveform")
                .font(.system(size: 7.5, weight: .bold))
            Text(text)
                .font(.system(size: 8.5, weight: .bold))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 5)
        .frame(height: PlayerMetrics.qualityBadgeHeight)
        .background(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8))
        .help("Playing in \(text)")
        .accessibilityLabel(text)
    }
}

/// A speaker in the output picker. The current one carries its volume as a
/// soft fill behind the row and a white check.
private struct OutputRow: View {
    let device: AudioOutputDevice
    let isCurrent: Bool
    let volume: Double
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: device.iconName)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 24)
                Text(device.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                ZStack {
                    Circle().fill(isCurrent ? Color.white : Color.white.opacity(0.13))
                    if isCurrent {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.black)
                            .transition(DS.Motion.transition(reduceMotion, .scale.combined(with: .opacity)))
                    }
                }
                .frame(width: 19, height: 19)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 29)
            .background(
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Color.white.opacity(isHovered ? 0.12 : 0.08)
                        if isCurrent {
                            Color.white.opacity(0.18).frame(width: geo.size.width * volume)
                        }
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .onHover { isHovered = $0 }
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: isCurrent)
        .help(device.name)
        .accessibilityLabel(device.name)
        .accessibilityValue(isCurrent ? "Current output, volume \(Int((volume * 100).rounded())) percent" : "")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// The open player's wash of album-art colour, behind the whole shelf
/// (Settings › HUDs › Artwork tint). Fades out with no art or a paused song.
struct ArtworkTintBackground: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var mediaSettings = MediaSettings.shared
    @ObservedObject private var media = MediaService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = mediaSettings.playerArtworkTint && state.shelfPage == .home && state.showsFullPlayer
            ? ArtworkPalette.current(media.currentTrack) : nil
        ZStack {
            if let palette {
                LinearGradient(colors: [palette.primary.opacity(0.28), palette.secondary.opacity(0.34), .clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .transition(.opacity)
            }
        }
        .animation(DS.Motion.respecting(reduceMotion, .easeInOut(duration: 0.6)), value: palette)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Lyrics

/// The lyrics card beside the player: a "Lyrics" header with the pop-out
/// button, then the lines around the playhead, on the artwork's colours.
struct LyricsCard: View {
    let palette: ArtworkPalette
    @ObservedObject private var lyrics = LyricsService.shared

    private static let padding: CGFloat = 10
    private static let header: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.primary)
                Text("Lyrics")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                if let foundBy = lyrics.foundBy {
                    Text(foundBy)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(NotchPalette.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                NotchCircleButton("arrow.up.left.and.arrow.down.right", size: 20, iconSize: 8.5, filled: true,
                                  help: LyricsWindowController.shared.isVisible ? "Bring floating lyrics to front" : "Pop out lyrics") {
                    LyricsWindowController.shared.bringToFront()
                }
            }
            .frame(height: Self.header)
            LyricsPanel(height: DroppyShelfMetrics.playerHeight - Self.header - Self.padding * 2 - 4)
        }
        .padding(Self.padding)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [palette.primary.opacity(0.16), palette.secondary.opacity(0.24)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.04)))
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}

/// Previous, current and next lines around the playhead; the current one is
/// bright and kept centred. Tapping a synced line seeks there.
struct LyricsPanel: View {
    let height: CGFloat

    @ObservedObject private var lyrics = LyricsService.shared
    @ObservedObject private var media = MediaService.shared
    @AppStorage(LyricsService.onlineKey) private var lyricsOnline = false

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }

    @ViewBuilder
    private var content: some View {
        switch lyrics.state {
        case .idle:
            message("Play a song to see lyrics", "Synced lyrics appear here when a song is active.")
        case .disabled:
            VStack(spacing: 6) {
                Text("Lyrics are looked up online")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.white)
                Text("Sends the song's title, artist, album and length to LRCLIB (lrclib.net). Nothing else leaves your Mac.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(NotchPalette.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                pillButton("Fetch lyrics online") { lyricsOnline = true }
            }
            .padding(.horizontal, 6)
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading lyrics…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NotchPalette.secondary)
            }
        case .instrumental:
            message("♪ Instrumental", "This track has no words.")
        case .notFound:
            message("No lyrics for this song", "LRCLIB doesn't have lyrics for it yet.")
        case .offline:
            message("No internet connection", "Connect to Wi-Fi, Ethernet, or Personal Hotspot to continue.")
        case .failed:
            VStack(spacing: 8) {
                message("Synced lyrics aren't available right now.", nil)
                pillButton("Try again") { LyricsService.shared.load(for: media.currentTrack, force: true) }
            }
        case let .loaded(result):
            if result.isSynced {
                TimelineView(.animation(minimumInterval: 0.2, paused: !media.currentTrack.isPlaying)) { context in
                    // A hair early, so the highlight lands as the line starts rather than after.
                    let position = media.livePosition(at: context.date) + 0.15
                    LyricsScroller(lyrics: result, current: result.lineIndex(at: position),
                                   canSeek: media.currentTrack.supportsSeek, height: height)
                }
            } else {
                LyricsScroller(lyrics: result, current: nil, canSeek: false, height: height)
                    .overlay(alignment: .bottom) {
                        Text("This track doesn’t have timed lyrics.")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(NotchPalette.tertiary)
                    }
            }
        }
    }

    private func message(_ title: String, _ subtitle: String?) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchPalette.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 6)
    }

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        LyricsPillButton(title: title, action: action)
    }
}

/// The white call-to-action pill in the lyrics panel; softens a touch on hover.
private struct LyricsPillButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(Capsule().fill(Color.white.opacity(isHovered ? 0.86 : 1)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .onHover { isHovered = $0 }
        .animation(DS.Motion.hover, value: isHovered)
    }
}

private struct LyricsScroller: View {
    let lyrics: Lyrics
    let current: Int?
    let canSeek: Bool
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 5) {
                    // Room above the first and below the last line so either can sit in the middle.
                    Color.clear.frame(height: max(height / 2 - 12, 0))
                    ForEach(lyrics.lines) { line in
                        LyricRow(
                            line: line,
                            isCurrent: line.id == current,
                            isPast: current.map { line.id < $0 } ?? false,
                            isSynced: lyrics.isSynced,
                            canSeek: canSeek
                        )
                        .id(line.id)
                    }
                    Color.clear.frame(height: max(height / 2 - 12, 0))
                }
                .padding(.horizontal, 4)
            }
            .onAppear { proxy.scrollTo(current ?? 0, anchor: .center) }
            .onChange(of: current) { _, index in
                guard let index else { return }
                withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.disclose)) { proxy.scrollTo(index, anchor: .center) }
            }
        }
        .mask(
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.28),
                        .init(color: .black, location: 0.72), .init(color: .clear, location: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

private struct LyricRow: View {
    let line: LyricLine
    let isCurrent: Bool
    let isPast: Bool
    let isSynced: Bool
    let canSeek: Bool

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tappable: Bool { canSeek && line.time != nil }

    var body: some View {
        Text(line.text.isEmpty ? "♪" : line.text)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white.opacity(opacity))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: .infinity)
            .scaleEffect(isCurrent || !isSynced ? 1 : 0.88)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 && tappable }
            .onTapGesture(perform: seek)
            .animation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid), value: isCurrent)
            .animation(DS.Motion.respecting(reduceMotion, DS.Motion.hover), value: isHovered)
            .optionalHelp(tappable ? "Play from here" : nil)
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
            .accessibilityActions {
                if tappable { Button("Play from here", action: seek) }
            }
    }

    private func seek() {
        guard tappable, let time = line.time else { return }
        MediaService.shared.seek(to: time)
        DroppyAudio.playTick()
    }

    private var opacity: Double {
        if isCurrent || !isSynced { return isSynced ? 1 : 0.85 }
        if isHovered { return 0.75 }
        return isPast ? 0.3 : 0.45
    }
}

// MARK: - Playing Next

/// The tracks after the current one in Music's playlist, as a column beside
/// the player with their covers; tap one to play it.
struct PlayingNextColumn: View {
    @ObservedObject private var media = MediaService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headerText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchPalette.secondary)
                .lineLimit(1)
                .frame(height: 14)
                .help(headerText)
            content
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    private var headerText: String {
        guard case let .loaded(playlist, shuffled) = media.upNextStatus else { return "Playing Next" }
        let name = playlist.isEmpty ? "Playing Next" : "Playing Next · \(playlist)"
        return shuffled ? name + " · Shuffle is on, so the order may differ" : name
    }

    @ViewBuilder
    private var content: some View {
        switch media.upNextStatus {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Asking Music what's next…")
            }
            .modifier(UpNextMessage())
        case let .unavailable(reason):
            Label(reason, systemImage: "info.circle")
                .modifier(UpNextMessage())
        case .loaded:
            if media.upNext.isEmpty {
                Text("Playing Next is empty")
                    .modifier(UpNextMessage())
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(media.upNext) { item in
                            QueueRow(item: item, artwork: media.upNextArtwork[item.persistentID]) { media.play(item) }
                        }
                    }
                }
                .mask(
                    LinearGradient(stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                )
            }
        }
    }
}

private struct UpNextMessage: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(DS.Palette.textSecondary)
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct QueueRow: View {
    let item: QueuedTrack
    let artwork: NSImage?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AlbumArtView(image: artwork, size: PlayerMetrics.queueArtwork, radius: 6)
                    .overlay {
                        if isHovered {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.45))
                                Image(systemName: "play.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(item.artist)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchPalette.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 6)
            .frame(height: PlayerMetrics.queueRowHeight)
            .background(Color.white.opacity(isHovered ? 0.08 : 0))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .onHover { isHovered = $0 }
        .help("Play \(item.title)")
        .accessibilityLabel(item.artist.isEmpty ? item.title : "\(item.title), \(item.artist)")
        .accessibilityHint("Plays this track")
    }
}
