import SwiftUI

/// Settings › HUDs › Media and Media Controls.
@MainActor
public final class MediaSettings: SettingsStore {
    public static let shared = MediaSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "nowPlayingEnabled", "mediaAutoHide", "mediaAutoHideDelay", "nowPlayingDisplay",
        NowPlayingSize.key, "notchTrackTitle", "visualizerStyle", "liveAudioVisualizer",
        "liveAlbumArtwork", "playerArtworkTint", "playerShowsRemaining", "defaultMusicApp",
        "trackSwipe", "trackSwipeReversed", "notchClickOpensMedia", "filterMediaSources",
        "blockedMediaSources", "hideIncognitoMedia", "autoExpandLyrics", "lyricsWindowPinned",
        "audioQualityBadge", "musicLeftButton", "musicRightButton", "spotifyLeftButton",
        "spotifyRightButton", "regularLeftButton", "regularRightButton"
    ]

    /// Now Playing master switch: off, music stays out of the resting island.
    @AppStorage("nowPlayingEnabled") public var nowPlayingEnabled: Bool = true {
        didSet { AppState.shared.islandFrameChanged() }
    }
    /// Auto-hide preview: the resting wings fade out once music has been
    /// paused for `mediaAutoHideDelay` seconds.
    @AppStorage("mediaAutoHide") public var mediaAutoHide: Bool = true {
        didSet { AppState.shared.syncMediaAutoHide() }
    }
    @AppStorage("mediaAutoHideDelay") public var mediaAutoHideDelay: Double = 5 {
        didSet { AppState.shared.syncMediaAutoHide() }
    }
    @AppStorage("nowPlayingDisplay") public var nowPlayingDisplay: NowPlayingDisplay = .underPointer {
        didSet { AppState.shared.islandFrameChanged() }
    }
    /// Settings › HUDs › Media › Now Playing Size: Regular or Smaller. The
    /// key is `NowPlayingSize.key`, which `PlayerMetrics` reads back.
    @AppStorage(NowPlayingSize.key) public var nowPlayingSize: NowPlayingSize = .regular {
        didSet { AppState.shared.islandFrameChanged() }
    }
    /// The track title and artist are written in the notch wings.
    @AppStorage("notchTrackTitle") public var notchTrackTitle: Bool = true {
        didSet { AppState.shared.islandFrameChanged() }
    }
    @AppStorage("visualizerStyle") public var visualizerStyle: VisualizerStyle = .gradient
    /// The bars follow the sound actually playing (a system audio tap).
    @AppStorage("liveAudioVisualizer") public var liveAudioVisualizer: Bool = false {
        didSet { LiveAudioLevels.shared.sync() }
    }
    /// Clicking the album art opens it large instead of the player's app.
    @AppStorage("liveAlbumArtwork") public var liveAlbumArtwork: Bool = false
    /// The open player washes the shelf with the album art's colours.
    @AppStorage("playerArtworkTint") public var playerArtworkTint: Bool = true
    /// The player's right-hand time shows what's left (off: the length).
    @AppStorage("playerShowsRemaining") public var playerShowsRemaining: Bool = true
    @AppStorage("defaultMusicApp") public var defaultMusicApp: DefaultMusicApp = .appleMusic
    /// Two-finger sideways swipe on the media widget or the wings skips tracks.
    @AppStorage("trackSwipe") public var trackSwipe: Bool = true
    @AppStorage("trackSwipeReversed") public var trackSwipeReversed: Bool = false
    /// A click on the notch opens the media widget while music plays.
    @AppStorage("notchClickOpensMedia") public var notchClickOpensMedia: Bool = false
    /// Filter media sources: apps listed in `blockedMediaSources` are ignored.
    @AppStorage("filterMediaSources") public var filterMediaSources: Bool = false
    /// Newline-separated bundle IDs; see `blockedMediaSourceIDs`.
    @AppStorage("blockedMediaSources") public var blockedMediaSourcesStorage: String = ""
    /// Private (incognito) browser windows are never picked up.
    @AppStorage("hideIncognitoMedia") public var hideIncognitoMedia: Bool = false
    /// The lyrics card opens beside the player on its own when a song has lyrics.
    @AppStorage("autoExpandLyrics") public var autoExpandLyrics: Bool = false
    /// The floating lyrics window stays above other windows.
    @AppStorage("lyricsWindowPinned") public var lyricsWindowPinned: Bool = true
    /// Apple Music droplet: a Lossless / Hi-Res badge beside the title.
    @AppStorage("audioQualityBadge") public var audioQualityBadge: Bool = true
    @AppStorage("musicLeftButton") public var musicLeftButton: MediaWidgetButton = .shuffle
    @AppStorage("musicRightButton") public var musicRightButton: MediaWidgetButton = .repeat
    @AppStorage("spotifyLeftButton") public var spotifyLeftButton: MediaWidgetButton = .shuffle
    @AppStorage("spotifyRightButton") public var spotifyRightButton: MediaWidgetButton = .repeat
    @AppStorage("regularLeftButton") public var regularLeftButton: MediaWidgetButton = .none
    @AppStorage("regularRightButton") public var regularRightButton: MediaWidgetButton = .none

    private init() { super.init(keys: Self.keys) }
}
