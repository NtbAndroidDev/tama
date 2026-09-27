import SwiftUI
import AppKit

public struct MediaTrack: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval
    public var currentPosition: TimeInterval
    public var isPlaying: Bool
    public var sourceApp: String // Display name: "Music", "Spotify", "Google Chrome"…
    public var sourceBundleID: String
    /// Whether the source lets Tama set the playhead / favourite the track.
    public var supportsSeek: Bool
    public var supportsLike: Bool
    /// A browser tab whose position Tama can't read until the browser allows
    /// JavaScript from Apple Events.
    public var needsBrowserJavaScript: Bool
    public var isLiked: Bool
    public var volume: Double
    public var artworkData: Data?
    /// Shuffle and repeat, where the source reports them (Music, Spotify).
    public var shuffle: Bool?
    public var repeatMode: RepeatMode?
    /// "Lossless" / "Hi-Res Lossless" when Music says so; nil otherwise.
    public var audioQuality: String?
    
    public init(
        title: String = "",
        artist: String = "",
        album: String = "",
        duration: TimeInterval = 0,
        currentPosition: TimeInterval = 0,
        isPlaying: Bool = false,
        sourceApp: String = "",
        sourceBundleID: String = "",
        supportsSeek: Bool = false,
        supportsLike: Bool = false,
        needsBrowserJavaScript: Bool = false,
        isLiked: Bool = false,
        volume: Double = 1.0,
        artworkData: Data? = nil,
        shuffle: Bool? = nil,
        repeatMode: RepeatMode? = nil,
        audioQuality: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.currentPosition = currentPosition
        self.isPlaying = isPlaying
        self.sourceApp = sourceApp
        self.sourceBundleID = sourceBundleID
        self.supportsSeek = supportsSeek
        self.supportsLike = supportsLike
        self.needsBrowserJavaScript = needsBrowserJavaScript
        self.isLiked = isLiked
        self.volume = volume
        self.artworkData = artworkData
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.audioQuality = audioQuality
    }

    /// Shuffle and repeat can be set from Tama.
    public var supportsShuffleRepeat: Bool { shuffle != nil }

    /// Decoded album art, when the now-playing source supplied any.
    /// Cached: views re-read it on every playhead tick, and decoding the same
    /// cover twice a second in four places added up.
    @MainActor public var artworkImage: NSImage? {
        guard let artworkData, !artworkData.isEmpty else { return nil }
        if let cached = ArtworkCache.entry, cached.data.isSameArtwork(as: artworkData) { return cached.image }
        let image = NSImage(data: artworkData)
        ArtworkCache.entry = image.map { (artworkData, $0) }
        return image
    }

    public var hasTrack: Bool { !title.isEmpty }
    
    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentPosition / duration, 0), 1)
    }
    
    public var formattedPosition: String {
        formatTime(currentPosition)
    }
    
    public var formattedDuration: String {
        formatTime(duration)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

/// The last decoded cover; there is only ever one current track.
@MainActor private enum ArtworkCache {
    static var entry: (data: Data, image: NSImage)?
}

extension Data {
    /// Whether two covers hold the same bytes, answered by their storage first:
    /// the track is copied, not re-read, between renders, so this is almost
    /// always the same buffer and a full compare of a cover per render is waste.
    /// Small values may be stored inline, where the address says nothing.
    func isSameArtwork(as other: Data) -> Bool {
        guard count == other.count else { return false }
        if count > 64 {
            let a = withUnsafeBytes { $0.baseAddress }
            let b = other.withUnsafeBytes { $0.baseAddress }
            if a != nil, a == b { return true }
        }
        return self == other
    }
}
