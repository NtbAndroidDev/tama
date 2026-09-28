import SwiftUI
import Combine

// Settings › HUDs › Media and Media Controls: what the stored media settings
// mean for the island, the player and the media keys.

extension AppState {
    // MARK: Auto-hide preview

    /// Follows play/pause: once music has been paused for the delay, the
    /// resting wings fold away; playing again brings them straight back.
    func observeMediaAutoHide() -> AnyCancellable {
        mediaService.$currentTrack
            .map { track in track.hasTrack && !track.isPlaying }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncMediaAutoHide() }
    }

    func syncMediaAutoHide() {
        mediaAutoHideWork?.cancel()
        mediaAutoHideWork = nil
        let track = mediaService.currentTrack
        guard MediaSettings.shared.mediaAutoHide, track.hasTrack, !track.isPlaying else {
            if isMediaAutoHidden { withAnimation(DS.Motion.fluid) { isMediaAutoHidden = false } }
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, MediaSettings.shared.mediaAutoHide, !self.mediaService.currentTrack.isPlaying else { return }
            withAnimation(DS.Motion.morphClose) { self.isMediaAutoHidden = true }
        }
        mediaAutoHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(MediaSettings.shared.mediaAutoHideDelay, 1), execute: work)
    }

    // MARK: Wings

    /// Notch track title: the song is written beside the art while music owns
    /// the island (no urgent live activity in front of it).
    ///
    /// Only where there is room. A physical notch is a fixed black cut-out, so
    /// the resting surface has to hug it; writing the song there stretched a
    /// black bar across the menu bar. On a notched screen the title lives in
    /// the open player instead, and here it is only the floating pill's.
    public func showsTrackTitleInWings(on displayID: CGDirectDisplayID?) -> Bool {
        Self.showsTrackTitle(enabled: MediaSettings.shared.notchTrackTitle,
                             hasNotch: notchHeight(on: displayID) > 0,
                             hasTrack: mediaService.currentTrack.hasTrack,
                             showsMedia: showsMedia(on: displayID),
                             activitiesFirst: HUDSettings.shared.compactHUDPriority == .activitiesFirst
                                 && LiveActivityCenter.shared.top(.urgent) != nil)
    }

    /// The rule on its own, so it can be checked without a screen.
    nonisolated static func showsTrackTitle(enabled: Bool, hasNotch: Bool, hasTrack: Bool,
                                            showsMedia: Bool, activitiesFirst: Bool) -> Bool {
        guard enabled, hasTrack, showsMedia, !activitiesFirst else { return false }
        return !hasNotch
    }

    // MARK: Sources

    /// Settings › HUDs › Filter media sources: apps switched off.
    public var blockedMediaSourceIDs: Set<String> {
        get { Set(MediaSettings.shared.blockedMediaSourcesStorage.split(separator: "\n").map(String.init)) }
        set { MediaSettings.shared.blockedMediaSourcesStorage = newValue.sorted().joined(separator: "\n") }
    }

    /// Whether Tama may show and control media from this app.
    public func allowsMediaSource(_ bundleID: String) -> Bool {
        guard MediaSettings.shared.filterMediaSources, !bundleID.isEmpty else { return true }
        return !blockedMediaSourceIDs.contains(bundleID)
    }

    // MARK: Playback buttons

    /// The buttons either side of the transport for a source.
    public func mediaButtons(for source: MediaButtonSource) -> (left: MediaWidgetButton, right: MediaWidgetButton) {
        switch source {
        case .appleMusic: (MediaSettings.shared.musicLeftButton, MediaSettings.shared.musicRightButton)
        case .spotify: (MediaSettings.shared.spotifyLeftButton, MediaSettings.shared.spotifyRightButton)
        case .regular: (MediaSettings.shared.regularLeftButton, MediaSettings.shared.regularRightButton)
        }
    }

    public func setMediaButton(_ button: MediaWidgetButton, for source: MediaButtonSource, left: Bool) {
        switch (source, left) {
        case (.appleMusic, true): MediaSettings.shared.musicLeftButton = button
        case (.appleMusic, false): MediaSettings.shared.musicRightButton = button
        case (.spotify, true): MediaSettings.shared.spotifyLeftButton = button
        case (.spotify, false): MediaSettings.shared.spotifyRightButton = button
        case (.regular, true): MediaSettings.shared.regularLeftButton = button
        case (.regular, false): MediaSettings.shared.regularRightButton = button
        }
    }

    /// Reset and Import write the keys directly, past the didSets.
    func applyMediaSettings() {
        syncMediaAutoHide()
        LiveAudioLevels.shared.sync()
        WeatherService.shared.locationSettingsChanged()
        WeatherService.shared.intervalChanged()
    }
}
