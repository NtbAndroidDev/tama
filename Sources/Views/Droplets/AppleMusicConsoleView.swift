import SwiftUI

/// The Apple Music droplet's console: Music's own transport, shuffle, repeat
/// and favourite with the audio quality badge — or, when Music isn't the one
/// playing, a way to open it and start playing.
struct AppleMusicConsoleView: View {
    @ObservedObject private var media = MediaService.shared
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var mediaSettings = MediaSettings.shared

    private var track: MediaTrack { media.currentTrack }
    private var isMusic: Bool { track.hasTrack && track.sourceBundleID == "com.apple.Music" }

    var body: some View {
        if isMusic {
            nowPlaying
        } else {
            VStack(spacing: DS.Space.md) {
                DroppyEmptyState(systemName: "music.note", title: "Music isn't playing",
                                 subtitle: track.hasTrack ? "\(track.sourceApp) is playing right now." : "Open Music and pick something to play.")
                HStack(spacing: DS.Space.sm) {
                    DroppyPillButton("Open Music", systemName: "arrow.up.forward.app", tone: .tonal) {
                        openMusic(play: false)
                    }
                    DroppyPillButton("Play", systemName: "play.fill", tone: .accent, help: "Open Music and start playing") {
                        openMusic(play: true)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Space.sm)
        }
    }

    private var nowPlaying: some View {
        HStack(alignment: .center, spacing: 18) {
            AlbumArtView(image: track.artworkImage, size: 120, radius: 18)
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HStack(spacing: DS.Space.sm) {
                    Text(track.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                        .help(track.title)
                    if mediaSettings.audioQualityBadge, let quality = track.audioQuality {
                        AudioQualityBadge(text: quality)
                    }
                }
                let byline = [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " — ")
                Text(byline)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                    .help(byline)
                HStack(spacing: DS.Space.md) {
                    DroppyIconButton("shuffle", size: 32, tone: .tonal, isActive: track.shuffle == true,
                                     help: track.shuffle == true ? "Turn shuffle off" : "Shuffle") { media.toggleShuffle() }
                    DroppyIconButton("backward.fill", size: 32, tone: .tonal, help: "Previous") { media.previousTrack() }
                    DroppyIconButton(track.isPlaying ? "pause.fill" : "play.fill", size: 40, tone: .accent,
                                     help: track.isPlaying ? "Pause" : "Play") { media.togglePlayPause() }
                    DroppyIconButton("forward.fill", size: 32, tone: .tonal, help: "Next") { media.nextTrack() }
                    DroppyIconButton(track.repeatMode == .one ? "repeat.1" : "repeat", size: 32, tone: .tonal,
                                     isActive: (track.repeatMode ?? .off) != .off, help: repeatHelp) { media.cycleRepeat() }
                    DroppyIconButton(track.isLiked ? "heart.fill" : "heart", size: 32, tone: .tonal, isActive: track.isLiked,
                                     help: track.isLiked ? "Remove from favorites" : "Add to favorites") { media.toggleLike() }
                }
                .padding(.top, DS.Space.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, DS.Space.sm)
    }

    /// Names the current mode and what a click does, not just "Repeat".
    private var repeatHelp: String {
        switch track.repeatMode ?? .off {
        case .off: return "Repeat is off (click to repeat all)"
        case .all: return "Repeating all (click to repeat one)"
        case .one: return "Repeating one song (click to turn repeat off)"
        }
    }

    private func openMusic(play: Bool) {
        media.launch(.appleMusic, andPlay: play)
    }
}
