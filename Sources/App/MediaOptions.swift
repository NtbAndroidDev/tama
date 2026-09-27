import SwiftUI

// Choices on Settings › HUDs › Media / Media Controls, the player and the
// weather card. The stored settings live in the AppState class body; these
// are their value types.

/// Settings › HUDs › Visualizer: how the music bars are coloured.
public enum VisualizerStyle: String, CaseIterable, Identifiable, Sendable {
    /// White bars fading to grey.
    case mono
    /// A two-tone ramp taken from the album art (the accent without art).
    case gradient
    public var id: String { rawValue }
}

/// Settings › HUDs › Now Playing display: which island shows the music.
public enum NowPlayingDisplay: String, CaseIterable, Identifiable, Sendable {
    /// The live island, wherever the pointer has taken it.
    case underPointer
    /// Only the MacBook's own display (any display when there is none).
    case macBook
    public var id: String { rawValue }
}

/// Settings › HUDs › Default music app: opened and played when nothing plays.
public enum DefaultMusicApp: String, CaseIterable, Identifiable, Sendable {
    case appleMusic, spotify
    public var id: String { rawValue }

    public var bundleID: String { self == .appleMusic ? "com.apple.Music" : "com.spotify.client" }
    /// The name AppleScript knows the app by.
    public var scriptName: String { self == .appleMusic ? "Music" : "Spotify" }
    public var title: String { self == .appleMusic ? "Apple Music" : "Spotify" }
    public var shortTitle: String { self == .appleMusic ? "Music" : "Spotify" }
}

/// Settings › HUDs › Media keys › Playback keys: who answers play/pause,
/// next and previous.
public enum PlaybackKeysMode: String, CaseIterable, Identifiable, Sendable {
    /// macOS routes them, as without Tama.
    case system
    /// Tama sends them to the source its player shows.
    case nowPlaying
    /// Tama always sends them to the default music app.
    case defaultApp
    public var id: String { rawValue }
}

/// A button the full player can put either side of the transport
/// (Settings › Droplets › Apple Music › Media widget, and HUDs › Media Controls).
public enum MediaWidgetButton: String, CaseIterable, Identifiable, Sendable {
    case none, shuffle, `repeat`, favorite, lyrics, queue, output
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: "None"
        case .shuffle: "Shuffle"
        case .repeat: "Repeat"
        case .favorite: "Favorite"
        case .lyrics: "Lyrics"
        case .queue: "Playing Next"
        case .output: "Output"
        }
    }

    public var icon: String {
        switch self {
        case .none: "circle.slash"
        case .shuffle: "shuffle"
        case .repeat: "repeat"
        case .favorite: "heart"
        case .lyrics: "quote.bubble"
        case .queue: "list.bullet"
        case .output: "airpodspro"
        }
    }
}

/// Whose playback buttons are being chosen: each source has its own pair.
public enum MediaButtonSource: String, CaseIterable, Identifiable, Sendable {
    /// Browsers and any other app: no shuffle, repeat or favourite.
    case regular
    case spotify
    case appleMusic
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .regular: "Regular"
        case .spotify: "Spotify"
        case .appleMusic: "Apple Music"
        }
    }

    /// The buttons this source can actually act on.
    public var options: [MediaWidgetButton] {
        switch self {
        case .regular: [.none, .lyrics, .output]
        case .spotify: [.none, .shuffle, .repeat, .lyrics, .output]
        case .appleMusic: MediaWidgetButton.allCases
        }
    }

    public static func of(bundleID: String) -> MediaButtonSource {
        switch bundleID {
        case "com.apple.Music": .appleMusic
        case "com.spotify.client": .spotify
        default: .regular
        }
    }
}

/// Repeat as Music and Spotify report it; Spotify only knows off and all.
public enum RepeatMode: String, Sendable, Equatable {
    case off, all, one
}

/// Settings › Droplets › Weather › Weather style.
public enum WeatherStyle: String, CaseIterable, Identifiable, Sendable {
    /// A sky gradient that follows the conditions.
    case colorful
    /// Near-black, like the rest of the shelf.
    case dark
    /// Grey macOS liquid glass (the reference default).
    case liquidGlass
    public var id: String { rawValue }
}

/// Settings › Droplets › Weather › Weather location.
public enum WeatherLocationMode: String, CaseIterable, Identifiable, Sendable {
    /// This Mac's location, from Location Services.
    case automatic
    /// A place picked with the city search.
    case fixed
    public var id: String { rawValue }
}
