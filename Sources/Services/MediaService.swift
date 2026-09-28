import SwiftUI
import Combine
import AppKit
import IOKit.pwr_mgt
import ImageIO
import ApplicationServices

final class MediaRemoteBridge: @unchecked Sendable {
    static let shared = MediaRemoteBridge()

    private typealias MRMediaRemoteGetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias MRMediaRemoteSendCommandFunction = @convention(c) (Int, AnyObject?) -> Bool
    private typealias MRMediaRemoteRegisterFunction = @convention(c) (DispatchQueue) -> Void
    private typealias MRMediaRemoteSetElapsedTimeFunction = @convention(c) (Double) -> Void
    private typealias MRMediaRemoteGetNowPlayingApplicationPIDFunction = @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void

    private var getInfoFn: MRMediaRemoteGetNowPlayingInfoFunction?
    private var sendCommandFn: MRMediaRemoteSendCommandFunction?
    private var setElapsedFn: MRMediaRemoteSetElapsedTimeFunction?
    private var getPIDFn: MRMediaRemoteGetNowPlayingApplicationPIDFunction?

    init() {
        if let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")) {
            if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString) {
                getInfoFn = unsafeBitCast(ptr, to: MRMediaRemoteGetNowPlayingInfoFunction.self)
            }
            if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) {
                sendCommandFn = unsafeBitCast(ptr, to: MRMediaRemoteSendCommandFunction.self)
            }
            if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSetElapsedTime" as CFString) {
                setElapsedFn = unsafeBitCast(ptr, to: MRMediaRemoteSetElapsedTimeFunction.self)
            }
            if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationPID" as CFString) {
                getPIDFn = unsafeBitCast(ptr, to: MRMediaRemoteGetNowPlayingApplicationPIDFunction.self)
            }
            if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString) {
                let regFn = unsafeBitCast(ptr, to: MRMediaRemoteRegisterFunction.self)
                regFn(DispatchQueue.main)
            }
        }
    }

    /// Since macOS 15.4 this returns an empty dictionary for apps without
    /// Apple's private entitlement; Tama then falls back to the sources below.
    /// Falls back to MediaRemoteAdapterProcess, which asks from inside
    /// /usr/bin/perl, when the direct call comes back empty.
    func getNowPlaying(completion: @escaping ([String: Any]?) -> Void) {
        let adapted: () -> [String: Any]? = {
            let adapter = MediaRemoteAdapterProcess.shared
            let info = adapter.latest
            return adapter.isLive && !info.isEmpty ? info : nil
        }
        guard let getInfoFn = getInfoFn else {
            completion(adapted())
            return
        }
        getInfoFn(DispatchQueue.main) { [getPIDFn] info in
            let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
            guard !title.isEmpty else { return completion(adapted()) }
            // The direct answer doesn't name its app; the adapter's does. Look
            // the owner up so Music and Spotify still get their scripted path.
            guard let getPIDFn, info[MediaRemoteAdapterProcess.bundleIDKey] == nil else { return completion(info) }
            getPIDFn(DispatchQueue.main) { pid in
                var owned = info
                if pid > 0, let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier {
                    owned[MediaRemoteAdapterProcess.bundleIDKey] = bundleID
                }
                completion(owned)
            }
        }
    }

    func sendCommand(_ command: Int) {
        let names = [0: "play", 1: "pause", 2: "toggle", 4: "next", 5: "previous"]
        if let name = names[command], MediaRemoteAdapterProcess.shared.send(name) { return }
        _ = sendCommandFn?(command, nil)
    }

    func setElapsedTime(_ time: Double) {
        if MediaRemoteAdapterProcess.shared.send("seek \(time)") { return }
        setElapsedFn?(time)
    }
}

/// Where the current track comes from; decides how Tama controls it.
private enum MediaSource: Equatable {
    case none
    case mediaRemote
    case music
    case spotify
    /// A browser tab playing audio, identified by its URL so a paused tab can
    /// be followed until it closes.
    case browser(bundleID: String, url: String)
}

@MainActor
public final class MediaService: ObservableObject {
    public static let shared = MediaService()

    @Published public var currentTrack: MediaTrack {
        didSet {
            if currentTrack.currentPosition != oldValue.currentPosition || currentTrack.isPlaying != oldValue.isPlaying {
                positionStamp = Date()
                playhead.set(currentTrack.currentPosition, at: positionStamp)
            }
            if currentTrack.isPlaying != oldValue.isPlaying || (currentTrack.duration > 0) != (oldValue.duration > 0) {
                updatePlayheadTimer()
            }
        }
    }
    /// When `currentPosition` was last set, so views can extrapolate between ticks.
    private var positionStamp = Date()
    /// The ticking playhead, apart from `currentTrack` so the open player's
    /// scrubber can move without every view of the track re-rendering with it.
    public let playhead = PlayheadModel()

    /// Tracks after the current one, where the player shares them (Apple Music).
    @Published public private(set) var upNext: [QueuedTrack] = []
    @Published public private(set) var upNextStatus: UpNextStatus = .idle
    /// Small covers for the Playing Next column, by persistent ID.
    @Published public private(set) var upNextArtwork: [String: NSImage] = [:]
    private var upNextArtworkRequests: Set<String> = []
    private var upNextRequest = 0

    private var source: MediaSource = .none
    private var isPolling = false
    private var artworkCache: [String: Data] = [:]
    private var artworkRequests: Set<String> = []
    /// Artwork key of the track on screen, so a late download for the previous
    /// track can't land on the new one.
    private var currentArtworkKey: String?
    /// Display names by bundle ID: a Launch Services lookup on every poll adds up.
    private var appNames: [String: String?] = [:]
    /// With the adapter live and nothing found, the AppleScript probe waits for a
    /// player to launch or quit (or the backstop below) instead of every tick.
    private var scriptProbeDue = true
    private var lastScriptProbe = Date.distantPast
    private var appWatchers: [NSObjectProtocol] = []

    public var isPlaying: Bool { currentTrack.isPlaying }
    public var trackTitle: String { currentTrack.title }
    public var artist: String { currentTrack.artist }
    public var album: String { currentTrack.album }

    /// One serial queue for every AppleScript: NSAppleScript isn't thread-safe.
    nonisolated private static let scriptQueue = DispatchQueue(label: "app.tama.media.scripts", qos: .userInitiated)

    private init() {
        self.currentTrack = MediaTrack()
        // Push updates from the adapter: a new song or play/pause shows at once
        // instead of on the next poll.
        MediaRemoteAdapterProcess.shared.onUpdate = { [weak self] in
            Task { @MainActor in self?.fetchLiveSystemMedia() }
        }
        MediaRemoteAdapterProcess.shared.start()
        startLiveSystemPolling()
    }

    /// The playhead right now: the last known position plus the time since,
    /// capped so a stalled poll can't run the lyrics ahead of the song.
    public func livePosition(at date: Date = Date()) -> TimeInterval {
        let base = playhead.position
        guard currentTrack.isPlaying else { return base }
        let ahead = min(max(date.timeIntervalSince(playhead.stamp), 0), 2)
        return currentTrack.duration > 0 ? min(base + ahead, currentTrack.duration) : base + ahead
    }

    // MARK: - Up Next

    /// Reloads the queue for the current source. Only Apple Music exposes its
    /// playlist to AppleScript; everything else gets an honest "unavailable".
    public func refreshUpNext() {
        upNextRequest += 1
        let request = upNextRequest
        switch source {
        case .music:
            break
        case .spotify:
            upNext = []
            upNextStatus = .unavailable("Up Next isn't available for Spotify — it doesn't share its queue with other apps.")
            return
        case .browser:
            upNext = []
            upNextStatus = .unavailable("Up Next isn't available for browser playback.")
            return
        case .mediaRemote, .none:
            upNext = []
            upNextStatus = currentTrack.hasTrack
                ? .unavailable("Up Next is only available for Apple Music.")
                : .unavailable("Play something in Music to see what's next.")
            return
        }
        if upNext.isEmpty { upNextStatus = .loading }
        Task { [weak self] in
            let result = await Self.musicUpNext()
            guard let self, request == self.upNextRequest else { return }
            if let result {
                self.upNext = result.tracks
                self.upNextStatus = .loaded(playlist: result.playlist, shuffled: result.shuffled)
                self.loadUpNextArtwork(result.tracks)
            } else {
                self.upNext = []
                self.upNextStatus = .unavailable("Music didn't share its current playlist.")
            }
        }
    }

    /// Jumps to a queued Apple Music track, found by persistent ID in case the
    /// playlist moved since it was listed.
    public func play(_ queued: QueuedTrack) {
        guard source == .music else { return }
        let id = Self.literal(queued.persistentID)
        runScript("""
        tell application "Music"
            try
                play (first track of current playlist whose persistent ID is \(id))
            on error
                play track \(queued.index) of current playlist
            end try
        end tell
        """)
        DroppyAudio.playTick()
        refreshSoon()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.refreshUpNext() }
    }

    /// Fetches the covers one track at a time on the script queue, shrunk to
    /// thumbnails; the cache is trimmed so a long session can't grow it forever.
    private func loadUpNextArtwork(_ tracks: [QueuedTrack]) {
        let missing = tracks.map(\.persistentID).filter { upNextArtwork[$0] == nil && !upNextArtworkRequests.contains($0) }
        guard !missing.isEmpty else { return }
        upNextArtworkRequests.formUnion(missing)
        if upNextArtwork.count > 60 { upNextArtwork.removeAll() }
        Task { [weak self] in
            for id in missing {
                let data = await Self.musicArtwork(persistentID: id)
                var thumb: CGImage?
                if let data { thumb = await Self.thumbnail(data, pixels: 144) }
                guard let self else { return }
                self.upNextArtworkRequests.remove(id)
                if let thumb {
                    self.upNextArtwork[id] = NSImage(cgImage: thumb, size: NSSize(width: 72, height: 72))
                }
            }
        }
    }

    /// Decodes straight to a small image off the main thread; drawing the
    /// full-size cover into a thumbnail on main stalled the shelf per row.
    nonisolated private static func thumbnail(_ data: Data, pixels: Int) async -> CGImage? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let options = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixels,
                ] as CFDictionary
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: CGImageSourceCreateThumbnailAtIndex(source, 0, options))
            }
        }
    }

    nonisolated private static func musicArtwork(persistentID: String) async -> Data? {
        let script = "tell application \"Music\" to get raw data of artwork 1 of (first track of current playlist whose persistent ID is \(literal(persistentID)))"
        return await withCheckedContinuation { cont in
            scriptQueue.async {
                var err: NSDictionary?
                let desc = NSAppleScript(source: script)?.executeAndReturnError(&err)
                cont.resume(returning: err == nil ? desc?.data : nil)
            }
        }
    }

    nonisolated private static func musicUpNext() async -> (playlist: String, shuffled: Bool, tracks: [QueuedTrack])? {
        let script = """
        tell application "Music"
            if player state is stopped then return ""
            set sep to "|||"
            set pl to current playlist
            set idx to index of current track
            set total to count of tracks of pl
            set out to (name of pl) & sep & (shuffle enabled as string) & linefeed
            set lastIdx to idx + 8
            if lastIdx > total then set lastIdx to total
            repeat with i from (idx + 1) to lastIdx
                set t to track i of pl
                set out to out & (i as string) & sep & (persistent ID of t) & sep & (name of t) & sep & (artist of t) & sep & ((duration of t) as string) & linefeed
            end repeat
            return out
        end tell
        """
        return await withCheckedContinuation { cont in
            scriptQueue.async {
                guard let out = runLines(script), !out.isEmpty else { cont.resume(returning: nil); return }
                var lines = out.components(separatedBy: CharacterSet.newlines).filter { !$0.isEmpty }
                guard !lines.isEmpty else { cont.resume(returning: nil); return }
                let head = lines.removeFirst().components(separatedBy: "|||")
                let tracks: [QueuedTrack] = lines.compactMap { line in
                    let p = line.components(separatedBy: "|||")
                    guard p.count >= 5, let index = Int(p[0]) else { return nil }
                    return QueuedTrack(index: index, persistentID: p[1], title: p[2], artist: p[3], duration: number(p[4]))
                }
                cont.resume(returning: (head.first ?? "", head.count > 1 && head[1] == "true", tracks))
            }
        }
    }

    // MARK: - Controls

    public func togglePlayPause() {
        switch source {
        case .mediaRemote: MediaRemoteBridge.shared.sendCommand(2) // kMRTogglePlayPause
        case .music: runControlScript(app: "Music", command: "playpause")
        case .spotify: runControlScript(app: "Spotify", command: "playpause")
        case let .browser(bundleID, url):
            runBrowserMediaJS(bundleID: bundleID, url: url, body: "if(m.paused){m.play()}else{m.pause()};return 'ok';") {
                MediaKeys.post(.playPause)
            }
        case .none:
            // Nothing to resume: Settings › HUDs › Default music app opens and plays.
            if !currentTrack.hasTrack, launchDefaultMusicApp(andPlay: true) { return }
            MediaKeys.post(.playPause)
        }
        // Optimistic, so the button flips at once; the next poll confirms it.
        if currentTrack.hasTrack { currentTrack.isPlaying.toggle() }
        DroppyAudio.playTick()
        refreshSoon()
    }

    public func nextTrack() {
        switch source {
        case .mediaRemote: MediaRemoteBridge.shared.sendCommand(4) // kMRNextTrack
        case .music: runControlScript(app: "Music", command: "next track")
        case .spotify: runControlScript(app: "Spotify", command: "next track")
        case .browser, .none: MediaKeys.post(.next)
        }
        DroppyAudio.playTick()
        refreshSoon()
    }

    public func previousTrack() {
        switch source {
        case .mediaRemote: MediaRemoteBridge.shared.sendCommand(5) // kMRPreviousTrack
        case .music: runControlScript(app: "Music", command: "previous track")
        case .spotify: runControlScript(app: "Spotify", command: "previous track")
        case .browser, .none: MediaKeys.post(.previous)
        }
        DroppyAudio.playTick()
        refreshSoon()
    }

    public func seek(to position: TimeInterval) {
        guard currentTrack.supportsSeek else { return }
        let clamped = min(max(position, 0), currentTrack.duration)
        currentTrack.currentPosition = clamped
        switch source {
        case .mediaRemote:
            MediaRemoteBridge.shared.setElapsedTime(clamped)
        case .music:
            runScript(#"tell application "Music" to set player position to \#(clamped)"#)
        case .spotify:
            runScript(#"tell application "Spotify" to set player position to \#(clamped)"#)
        case let .browser(bundleID, url):
            runBrowserMediaJS(bundleID: bundleID, url: url, body: "m.currentTime=\(clamped);return 'ok';")
        case .none:
            break
        }
    }

    /// Apple Music only: its scripting dictionary exposes the favourite flag.
    public func toggleLike() {
        guard currentTrack.supportsLike, source == .music else { return }
        let newValue = !currentTrack.isLiked
        currentTrack.isLiked = newValue
        runScript("""
        tell application "Music"
            try
                set favorited of current track to \(newValue)
            on error
                set loved of current track to \(newValue)
            end try
        end tell
        """)
        DroppyAudio.playTick()
    }

    /// Music and Spotify: flips shuffle.
    public func toggleShuffle() {
        guard let shuffle = currentTrack.shuffle else { return }
        currentTrack.shuffle = !shuffle
        switch source {
        case .music: runScript(#"tell application "Music" to set shuffle enabled to \#(!shuffle)"#)
        case .spotify: runScript(#"tell application "Spotify" to set shuffling to \#(!shuffle)"#)
        default: return
        }
        DroppyAudio.playTick()
        refreshSoon()
    }

    /// Music: off → all → one → off. Spotify's dictionary only has on and off.
    public func cycleRepeat() {
        guard let mode = currentTrack.repeatMode else { return }
        switch source {
        case .music:
            let next: RepeatMode = mode == .off ? .all : mode == .all ? .one : .off
            currentTrack.repeatMode = next
            runScript(#"tell application "Music" to set song repeat to \#(next.rawValue)"#)
        case .spotify:
            let on = mode == .off
            currentTrack.repeatMode = on ? .all : .off
            runScript(#"tell application "Spotify" to set repeating to \#(on)"#)
        default:
            return
        }
        DroppyAudio.playTick()
        refreshSoon()
    }

    // MARK: Default music app

    /// Opens Settings › HUDs › Default music app (without stealing focus) and,
    /// if asked, starts it playing once it has launched. False when it isn't installed.
    @discardableResult
    public func launchDefaultMusicApp(andPlay play: Bool) -> Bool {
        launch(MediaSettings.shared.defaultMusicApp, andPlay: play)
    }

    /// Opens Music or Spotify and, if asked, plays once it answers.
    @discardableResult
    public func launch(_ app: DefaultMusicApp, andPlay play: Bool) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else { return false }
        let wasRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == app.bundleID }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = !play
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
        guard play else { return true }
        // A cold launch needs a moment before it answers Apple Events.
        let delay: TimeInterval = wasRunning ? 0 : 1.6
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.runScript(#"tell application "\#(app.scriptName)" to play"#)
            self?.refreshSoon()
        }
        DroppyAudio.playTick()
        return true
    }

    // MARK: Media keys

    /// Settings › HUDs › Media keys › Playback keys. True when Tama acted
    /// on the key; false leaves it to macOS (a browser tab, which only the
    /// system route reaches, or the setting is off).
    func handlePlaybackKey(_ key: MediaKeys.Key) -> Bool {
        switch HUDSettings.shared.playbackKeysMode {
        case .system:
            return false
        case .nowPlaying:
            switch source {
            case .music, .spotify, .mediaRemote:
                perform(key)
                return true
            case .none:
                guard key == .playPause else { return false }
                return launchDefaultMusicApp(andPlay: true)
            case .browser:
                return false
            }
        case .defaultApp:
            let app = MediaSettings.shared.defaultMusicApp
            let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == app.bundleID }
            guard running else {
                return key == .playPause ? launchDefaultMusicApp(andPlay: true) : false
            }
            let command: String
            switch key {
            case .playPause: command = "playpause"
            case .next: command = "next track"
            case .previous: command = "previous track"
            }
            runControlScript(app: app.scriptName, command: command)
            refreshSoon()
            return true
        }
    }

    private func perform(_ key: MediaKeys.Key) {
        switch key {
        case .playPause: togglePlayPause()
        case .next: nextTrack()
        case .previous: previousTrack()
        }
    }

    public func setVolume(_ volume: Double) {
        currentTrack.volume = min(max(volume, 0), 1.0)
        let volInt = Int(currentTrack.volume * 100)
        switch source {
        case .music: runScript(#"tell application "Music" to set sound volume to \#(volInt)"#)
        case .spotify: runScript(#"tell application "Spotify" to set sound volume to \#(volInt)"#)
        default: AudioOutputService.shared.setVolume(currentTrack.volume)
        }
    }

    /// Brings the player's app to the front.
    public func openSourceApp() {
        var bundleID = currentTrack.sourceBundleID
        if bundleID.isEmpty, let guess = AppIcon.bundleID(forPlayer: currentTrack.sourceApp) { bundleID = guess }
        guard !bundleID.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func runControlScript(app: String, command: String) {
        runScript(#"tell application "\#(app)" to \#(command)"#)
    }

    private func runScript(_ source: String) {
        Self.scriptQueue.async {
            var err: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&err)
        }
    }

    /// Runs `body` against the tab's main media element; `fallback` runs when
    /// the tab is gone or the browser refuses JavaScript from Apple Events.
    private func runBrowserMediaJS(
        bundleID: String,
        url: String,
        body: String,
        fallback: (@MainActor @Sendable () -> Void)? = nil
    ) {
        guard let browser = Browser.all.first(where: { $0.bundleID == bundleID }) else {
            fallback?()
            return
        }
        let script = Self.tabScript(browser, url: url, js: Self.mediaJS(body))
        Self.scriptQueue.async {
            guard Self.runLines(script) != "ok", let fallback else { return }
            Task { @MainActor in fallback() }
        }
    }

    /// One round of polling right now, outside the timer's schedule. Used when
    /// the Mac wakes: the shelf would otherwise show the track that was playing
    /// when the screen went off until the next tick came round.
    public func refreshNow() {
        scriptProbeDue = true
        fetchLiveSystemMedia()
    }

    private func refreshSoon() {
        scriptProbeDue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.fetchLiveSystemMedia()
        }
    }

    // MARK: - Polling

    private var pollTimer: Timer?
    private var pollInterval: TimeInterval = 0
    private var playheadTimer: Timer?
    private var expansionWatch: AnyCancellable?

    private func startLiveSystemPolling() {
        // Every line of this reaches AppState.shared — the expansion watch
        // directly, the first fetch through the media-source filter — and this
        // runs inside AppState.init, because AppState holds `MediaService.shared`
        // in a stored property. Touching AppState.shared before its own
        // one-time initialiser returns deadlocks it (dispatch_once waiting on
        // itself), so the whole start-up is handed to the next turn of the
        // main loop, by which time both singletons exist.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.expansionWatch = AppState.shared.$isIslandExpanded
                .removeDuplicates()
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.updatePlayheadTimer() }
            self.watchPlayerApps()
            self.fetchLiveSystemMedia()
            self.schedulePoll()
        }
    }

    /// A player or browser opening or quitting is when the AppleScript sources
    /// can change without the adapter hearing of it, so probe then.
    private func watchPlayerApps() {
        let players: Set<String> = Set(["com.apple.Music", "com.spotify.client"] + Browser.all.map(\.bundleID))
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            appWatchers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let id = app?.bundleIdentifier, players.contains(id) else { return }
                MainActor.assumeIsolated {
                    self?.scriptProbeDue = true
                    // A cold launch needs a moment before it answers Apple Events.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.fetchLiveSystemMedia() }
                }
            })
        }
    }

    /// The adapter pushes every change, so with it running polling is only a
    /// backstop. Apple Events push nothing, so a scripted source still needs a
    /// steady poll when the adapter is down.
    private func schedulePoll() {
        let interval: TimeInterval
        if MediaRemoteAdapterProcess.shared.isLive {
            interval = source == .none || source == .mediaRemote ? 10 : 5
        } else {
            // Idle, nothing to follow: a player launching triggers a probe of its
            // own (watchPlayerApps), so a slow poll only catches in-app starts.
            interval = source == .none ? 5 : 1.5
        }
        guard interval != pollInterval || pollTimer == nil else { return }
        pollInterval = interval
        pollTimer?.invalidate()
        // Common modes: keep polling while a menu is open or a drag is in flight.
        let poll = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                // Screen off: nobody sees the player; PowerStateService asks
                // for a round the moment it comes back.
                guard !PowerStateService.shared.isDormant else { return }
                self?.fetchLiveSystemMedia()
            }
        }
        // Tolerance lets macOS batch these wake-ups with others while idle.
        poll.tolerance = interval * 0.2
        RunLoop.main.add(poll, forMode: .common)
        pollTimer = poll
    }

    /// Advances the playhead between polls so the open shelf's scrubber moves
    /// smoothly. Nothing else shows the position, so a resting notch doesn't
    /// re-render twice a second for it.
    private func updatePlayheadTimer() {
        let needed = currentTrack.isPlaying && currentTrack.duration > 0 && AppState.shared.isIslandExpanded
        guard needed != (playheadTimer != nil) else { return }
        if needed {
            // Catch up on the time that passed while nobody was watching.
            currentTrack.currentPosition = extrapolatedPosition()
            let playhead = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.currentTrack.isPlaying else { return }
                    let position = self.extrapolatedPosition()
                    // Home's media card still reads the track itself; the full
                    // player's scrubber reads only the playhead.
                    let state = AppState.shared
                    if state.shelfPage == .home, !state.showsFullPlayer {
                        self.currentTrack.currentPosition = position
                    } else {
                        self.playhead.set(position, at: Date())
                    }
                }
            }
            playhead.tolerance = 0.1
            RunLoop.main.add(playhead, forMode: .common)
            playheadTimer = playhead
        } else {
            playheadTimer?.invalidate()
            playheadTimer = nil
        }
    }

    /// The last known position plus the time since, uncapped.
    private func extrapolatedPosition() -> TimeInterval {
        let base = currentTrack.currentPosition
        guard currentTrack.isPlaying else { return base }
        let now = base + max(Date().timeIntervalSince(positionStamp), 0)
        return currentTrack.duration > 0 ? min(now, currentTrack.duration) : now
    }

    /// Publishes a polled track only when something on screen would change:
    /// every poll re-rendered all of the notch, the shelf and the HUD.
    private func publish(_ track: MediaTrack) {
        var comparable = track
        comparable.currentPosition = currentTrack.currentPosition
        if comparable == currentTrack, abs(track.currentPosition - extrapolatedPosition()) < 1.5 { return }
        currentTrack = track
    }

    private func fetchLiveSystemMedia() {
        guard !isPolling else { return }
        isPolling = true

        // 1. The system-wide Now Playing, where macOS still allows it.
        MediaRemoteBridge.shared.getNowPlaying { [weak self] info in
            Task { @MainActor in
                guard let self else { return }
                // Music and Spotify still go through AppleScript, which adds
                // Favourite and their own artwork.
                let owner = info?[MediaRemoteAdapterProcess.bundleIDKey] as? String
                let scripted = owner == "com.apple.Music" || owner == "com.spotify.client"
                // Settings › HUDs › Filter media sources: a switched-off app is skipped.
                let allowed = owner.map { AppState.shared.allowsMediaSource($0) } ?? true
                if !scripted, allowed, let info, let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String, !title.isEmpty {
                    self.applyMediaRemote(info, title: title)
                    self.isPolling = false
                    self.schedulePoll()
                    return
                }
                // 2. Music / Spotify, 3. a browser tab that is playing audio.
                let previous = self.source
                // The adapter would have pushed anything playing, so with it live
                // and nothing followed, the Apple Events round is only a backstop.
                let adapterLive = MediaRemoteAdapterProcess.shared.isLive
                if adapterLive, info == nil, previous == .none, !self.scriptProbeDue,
                   Date().timeIntervalSince(self.lastScriptProbe) < 60 {
                    self.isPolling = false
                    self.schedulePoll()
                    return
                }
                self.lastScriptProbe = Date()
                let snapshot = await Self.probeScriptableSources(following: previous)
                self.apply(snapshot)
                self.scriptProbeDue = self.source != .none || !adapterLive
                self.isPolling = false
                self.schedulePoll()
            }
        }
    }

    private func applyMediaRemote(_ info: [String: Any], title: String) {
        let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
        var elapsed = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0
        if rate > 0, let stamp = info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date {
            elapsed += Date().timeIntervalSince(stamp) * rate
        }
        source = .mediaRemote
        currentArtworkKey = nil
        // Keep the old artwork only for the same song; a new one without art
        // must not inherit the previous cover.
        let keptArtwork = title == currentTrack.title ? currentTrack.artworkData : nil
        let bundleID = info[MediaRemoteAdapterProcess.bundleIDKey] as? String ?? ""
        let appName = appName(for: bundleID)
        let duration = max(info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0, 0)
        publish(MediaTrack(
            title: title,
            artist: info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "",
            album: info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? "",
            duration: duration,
            currentPosition: min(max(elapsed, 0), duration > 0 ? duration : .greatestFiniteMagnitude),
            isPlaying: rate > 0,
            sourceApp: appName ?? "Now Playing",
            sourceBundleID: bundleID,
            supportsSeek: duration > 0,
            isLiked: false,
            volume: currentTrack.volume,
            artworkData: info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data ?? keptArtwork
        ))
    }

    private func appName(for bundleID: String) -> String? {
        if let cached = appNames[bundleID] { return cached }
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
        appNames[bundleID] = name
        return name
    }

    // MARK: - Scriptable sources

    private struct Snapshot: Sendable {
        var source: MediaSource = .none
        var title = ""
        var artist = ""
        var album = ""
        var duration: Double = 0
        var position: Double = 0
        var isPlaying = false
        var isLiked = false
        var appName = ""
        var bundleID = ""
        var artworkKey: String?
        var artworkURL: URL?
        var needsBrowserJS = false
        var shuffle: Bool?
        var repeatMode: RepeatMode?
        var audioQuality: String?
    }

    private func apply(_ snap: Snapshot) {
        guard snap.source != .none, !snap.title.isEmpty else {
            source = .none
            currentArtworkKey = nil
            if currentTrack.hasTrack { currentTrack = MediaTrack(volume: currentTrack.volume) }
            return
        }
        let sameTrack = snap.title == currentTrack.title && snap.source == source
        source = snap.source
        currentArtworkKey = snap.artworkKey
        var artwork = snap.artworkKey.flatMap { artworkCache[$0] }
        if artwork == nil, sameTrack { artwork = currentTrack.artworkData }

        publish(MediaTrack(
            title: snap.title,
            artist: snap.artist,
            album: snap.album,
            duration: snap.duration,
            currentPosition: snap.position,
            isPlaying: snap.isPlaying,
            sourceApp: snap.appName,
            sourceBundleID: snap.bundleID,
            supportsSeek: snap.duration > 0,
            supportsLike: snap.source == .music,
            needsBrowserJavaScript: snap.needsBrowserJS,
            isLiked: snap.isLiked,
            volume: currentTrack.volume,
            artworkData: artwork,
            shuffle: snap.shuffle,
            repeatMode: snap.repeatMode,
            audioQuality: snap.audioQuality
        ))

        if artwork == nil, let key = snap.artworkKey { loadArtwork(key: key, url: snap.artworkURL) }
    }

    private func loadArtwork(key: String, url: URL?) {
        guard !artworkRequests.contains(key) else { return }
        artworkRequests.insert(key)
        let isMusic = source == .music
        Task { [weak self] in
            var data: Data?
            if let url {
                data = try? await URLSession.shared.data(from: url).0
            } else if isMusic {
                data = await Self.musicArtwork()
            }
            guard let self else { return }
            self.artworkRequests.remove(key)
            guard let data, !data.isEmpty else { return }
            self.artworkCache[key] = data
            if self.artworkCache.count > 40 { self.artworkCache.removeAll() }
            if self.currentTrack.hasTrack, self.currentTrack.artworkData == nil, self.currentArtworkKey == key {
                self.currentTrack.artworkData = data
            }
        }
    }

    nonisolated private static func musicArtwork() async -> Data? {
        await withCheckedContinuation { cont in
            scriptQueue.async {
                var err: NSDictionary?
                let desc = NSAppleScript(source: #"tell application "Music" to get raw data of artwork 1 of current track"#)?
                    .executeAndReturnError(&err)
                cont.resume(returning: err == nil ? desc?.data : nil)
            }
        }
    }

    nonisolated private static func probeScriptableSources(following previous: MediaSource) async -> Snapshot {
        let (running, hidePrivate) = await MainActor.run {
            let state = AppState.shared
            // Filter media sources: switched-off apps are treated as not running.
            let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
                .filter { state.allowsMediaSource($0) }
            return (running, MediaSettings.shared.hideIncognitoMedia)
        }
        let audible = audibleBundleIDs()
        return await withCheckedContinuation { cont in
            scriptQueue.async {
                var best: Snapshot?
                // A player that is actually playing wins; a paused one is kept as a fallback.
                if running.contains("com.apple.Music"), let snap = probeMusic() {
                    if snap.isPlaying { cont.resume(returning: snap); return }
                    best = snap
                }
                if running.contains("com.spotify.client"), let snap = probeSpotify() {
                    if snap.isPlaying { cont.resume(returning: snap); return }
                    best = best ?? snap
                }
                for browser in Browser.all where running.contains(browser.bundleID) {
                    let followed: String? = {
                        if case let .browser(id, url) = previous, id == browser.bundleID { return url }
                        return nil
                    }()
                    let isAudible = audible.contains(browser.bundleID)
                    guard isAudible || followed != nil else { continue }
                    if let snap = probeBrowser(browser, isAudible: isAudible, followedURL: followed, hidePrivate: hidePrivate) {
                        if snap.isPlaying { cont.resume(returning: snap); return }
                        best = best ?? snap
                    }
                }
                cont.resume(returning: best ?? Snapshot())
            }
        }
    }

    /// Compiled once, for the fixed probe scripts that run on every poll.
    /// Only ever touched on `scriptQueue`, like every NSAppleScript here.
    nonisolated(unsafe) private static var compiledScripts: [String: NSAppleScript] = [:]

    /// `reuse` keeps the compiled script for next time: only for sources that
    /// don't vary per call, so the cache stays a handful of entries.
    nonisolated private static func runLines(_ source: String, reuse: Bool = false) -> String? {
        dispatchPrecondition(condition: .onQueue(scriptQueue))
        var err: NSDictionary?
        let script: NSAppleScript?
        if reuse, let compiled = compiledScripts[source] {
            script = compiled
        } else if reuse, let fresh = NSAppleScript(source: source), fresh.compileAndReturnError(nil) {
            compiledScripts[source] = fresh
            script = fresh
        } else {
            script = NSAppleScript(source: source)
        }
        let desc = script?.executeAndReturnError(&err)
        guard err == nil else { return nil }
        return desc?.stringValue
    }

    nonisolated private static func probeMusic() -> Snapshot? {
        let script = """
        tell application "Music"
            if player state is stopped then return ""
            set sep to "|||"
            set fav to false
            try
                set fav to favorited of current track
            on error
                try
                    set fav to loved of current track
                end try
            end try
            set shuf to "false"
            try
                set shuf to (shuffle enabled as string)
            end try
            set rep to "off"
            try
                set rep to (song repeat as string)
            end try
            set sr to "0"
            set br to "0"
            set kd to ""
            try
                set sr to ((sample rate of current track) as string)
            end try
            try
                set br to ((bit rate of current track) as string)
            end try
            try
                set kd to (kind of current track) as string
            end try
            return (player state as string) & sep & name of current track & sep & artist of current track & sep & album of current track & sep & (player position as string) & sep & (duration of current track as string) & sep & (fav as string) & sep & shuf & sep & rep & sep & sr & sep & br & sep & kd
        end tell
        """
        guard let out = runLines(script, reuse: true), !out.isEmpty else { return nil }
        let p = out.components(separatedBy: "|||")
        guard p.count >= 7 else { return nil }
        var snap = Snapshot(source: .music, title: p[1], artist: p[2], album: p[3],
                            duration: number(p[5]), position: number(p[4]),
                            isPlaying: p[0].lowercased() == "playing", isLiked: p[6] == "true",
                            appName: "Music", bundleID: "com.apple.Music")
        snap.artworkKey = "music:\(p[1])|\(p[2])|\(p[3])"
        if p.count >= 12 {
            snap.shuffle = p[7] == "true"
            snap.repeatMode = RepeatMode(rawValue: p[8].lowercased()) ?? .off
            snap.audioQuality = audioQuality(sampleRate: number(p[9]), bitRate: number(p[10]), kind: p[11])
        }
        return snap
    }

    nonisolated private static func probeSpotify() -> Snapshot? {
        let script = """
        tell application "Spotify"
            if player state is stopped then return ""
            set sep to "|||"
            set shuf to "false"
            set rep to "false"
            try
                set shuf to (shuffling as string)
                set rep to (repeating as string)
            end try
            return (player state as string) & sep & name of current track & sep & artist of current track & sep & album of current track & sep & (player position as string) & sep & ((duration of current track) / 1000 as string) & sep & (artwork url of current track) & sep & shuf & sep & rep
        end tell
        """
        guard let out = runLines(script, reuse: true), !out.isEmpty else { return nil }
        let p = out.components(separatedBy: "|||")
        guard p.count >= 7 else { return nil }
        var snap = Snapshot(source: .spotify, title: p[1], artist: p[2], album: p[3],
                            duration: number(p[5]), position: number(p[4]),
                            isPlaying: p[0].lowercased() == "playing",
                            appName: "Spotify", bundleID: "com.spotify.client")
        if p.count >= 9 {
            snap.shuffle = p[7] == "true"
            snap.repeatMode = p[8] == "true" ? .all : .off
        }
        if let url = URL(string: p[6]), url.scheme?.hasPrefix("http") == true {
            snap.artworkKey = p[6]
            snap.artworkURL = url
        }
        return snap
    }

    /// AppleScript numbers can come back with a decimal comma in some locales.
    nonisolated private static func number(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    /// Lossless or Hi-Res from what Music's dictionary shares about the file:
    /// its kind ("Apple Lossless audio file"), bit rate and sample rate.
    /// Streams Music doesn't describe get no badge rather than a guess.
    nonisolated private static func audioQuality(sampleRate: Double, bitRate: Double, kind: String) -> String? {
        let kind = kind.lowercased()
        let lossless = kind.contains("lossless") || kind.contains("alac") || kind.contains("aiff")
            || kind.contains("wav") || kind.contains("flac") || bitRate >= 700
        guard lossless else { return nil }
        return sampleRate > 48_000 ? "Hi-Res Lossless" : "Lossless"
    }

    // MARK: Browsers

    private struct Browser: Sendable {
        let bundleID: String
        let name: String
        let isSafari: Bool

        static let all: [Browser] = [
            Browser(bundleID: "com.apple.Safari", name: "Safari", isSafari: true),
            Browser(bundleID: "com.google.Chrome", name: "Google Chrome", isSafari: false),
            Browser(bundleID: "com.brave.Browser", name: "Brave", isSafari: false),
            Browser(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge", isSafari: false),
            Browser(bundleID: "company.thebrowser.Browser", name: "Arc", isSafari: false),
            Browser(bundleID: "com.vivaldi.Vivaldi", name: "Vivaldi", isSafari: false),
            Browser(bundleID: "com.operasoftware.Opera", name: "Opera", isSafari: false),
            Browser(bundleID: "org.chromium.Chromium", name: "Chromium", isSafari: false),
        ]
    }

    /// Sites whose tab title names what is playing.
    nonisolated private static let mediaSites = [
        "youtube.com/watch", "youtube.com/shorts", "music.youtube.com", "youtu.be/",
        "soundcloud.com/", "open.spotify.com", "music.apple.com", "twitch.tv/",
        "zingmp3.vn", "nhaccuatui.com", "tiktok.com/", "vimeo.com/", "netflix.com/watch",
        "deezer.com", "tidal.com", "bandcamp.com", "mixcloud.com",
    ]

    /// Lists tabs as "active<TAB>title<TAB>url" lines.
    nonisolated private static func probeBrowser(_ browser: Browser, isAudible: Bool, followedURL: String?,
                                                 hidePrivate: Bool) -> Snapshot? {
        let activeOf = browser.isSafari ? "current tab of w" : "active tab of w"
        let titleOf = browser.isSafari ? "name of t" : "title of t"
        // Hide Incognito media: Chromium browsers report a window's mode.
        // Safari doesn't tell AppleScript which windows are private.
        let privateCheck = hidePrivate && !browser.isSafari ? """
                    try
                        if (mode of w as string) is "incognito" then set isPrivate to true
                    end try
        """ : ""
        let script = """
        set sep to ASCII character 9
        set out to ""
        tell application id "\(browser.bundleID)"
            repeat with w in windows
                try
                    set isPrivate to false
        \(privateCheck)
                    if not isPrivate then
                        set activeURL to URL of (\(activeOf))
                        set isFront to (index of w is 1)
                        repeat with t in tabs of w
                            set u to URL of t
                            set flag to "0"
                            if u is activeURL then set flag to "1"
                            if isFront and flag is "1" then set flag to "2"
                            set out to out & flag & sep & (\(titleOf)) & sep & u & linefeed
                        end repeat
                    end if
                end try
            end repeat
        end tell
        return out
        """
        guard let out = runLines(script, reuse: true) else { return nil }
        let tabs: [(rank: Int, title: String, url: String)] = out.split(separator: "\n").compactMap { line in
            let p = line.components(separatedBy: "\t")
            guard p.count >= 3 else { return nil }
            return (Int(p[0]) ?? 0, p[1], p[2...].joined(separator: "\t"))
        }
        guard !tabs.isEmpty else { return nil }

        let chosen: (rank: Int, title: String, url: String)?
        if let followedURL, let same = tabs.first(where: { $0.url == followedURL }), !isAudible || isMediaURL(same.url) {
            chosen = same
        } else if isAudible {
            let media = tabs.filter { isMediaURL($0.url) }.sorted { $0.rank > $1.rank }
            // No known media site: the front tab is the best guess at what's making sound.
            chosen = media.first ?? tabs.max { $0.rank < $1.rank }
        } else {
            chosen = nil
        }
        guard let tab = chosen else { return nil }

        let parsed = parseTitle(tab.title, url: tab.url)
        var snap = Snapshot(source: .browser(bundleID: browser.bundleID, url: tab.url),
                            title: parsed.title, artist: parsed.artist.isEmpty ? browser.name : parsed.artist,
                            isPlaying: isAudible, appName: browser.name, bundleID: browser.bundleID)
        if let out = runLines(tabScript(browser, url: tab.url, js: mediaJS("return m.currentTime+'|'+m.duration+'|'+m.paused;"))) {
            let p = out.components(separatedBy: "|")
            if p.count == 3 {
                let duration = number(p[1])
                if duration.isFinite, duration > 0 {
                    snap.duration = duration
                    snap.position = min(max(number(p[0]), 0), duration)
                }
                snap.isPlaying = p[2] != "true"
            } else if out.hasPrefix("ERR:"), out != "ERR:notab", isMediaURL(tab.url) {
                snap.needsBrowserJS = true
            }
        }
        if let id = youTubeID(tab.url) {
            snap.artworkKey = "yt:\(id)"
            snap.artworkURL = URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
        }
        return snap
    }

    /// Wraps `body` so it runs with `m` bound to the page's playing media
    /// element, or its longest one. Single quotes only: it's embedded in AppleScript.
    nonisolated private static func mediaJS(_ body: String) -> String {
        "(function(){var a=Array.from(document.querySelectorAll('video,audio'));"
            + "var m=a.find(function(e){return !e.paused})||a.sort(function(x,y){return (y.duration||0)-(x.duration||0)})[0];"
            + "if(!m)return '';\(body)})()"
    }

    /// Runs `js` in the tab showing `url`. Returns its result as text, or
    /// "ERR:<number>" when the browser refuses (JavaScript from Apple Events off).
    nonisolated private static func tabScript(_ browser: Browser, url: String, js: String) -> String {
        let run = browser.isSafari ? "do JavaScript \(literal(js)) in t" : "execute t javascript \(literal(js))"
        return """
        tell application id "\(browser.bundleID)"
            repeat with w in windows
                repeat with t in tabs of w
                    if URL of t is \(literal(url)) then
                        try
                            set r to \(run)
                            if r is missing value then return ""
                            return r as string
                        on error number n
                            return "ERR:" & n
                        end try
                    end if
                end repeat
            end repeat
        end tell
        return "ERR:notab"
        """
    }

    nonisolated private static func literal(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    nonisolated private static func isMediaURL(_ url: String) -> Bool {
        let lower = url.lowercased()
        return mediaSites.contains { lower.contains($0) }
    }

    /// Strips site suffixes and unread counts, splitting "Song • Artist" and "X by Y".
    nonisolated private static func parseTitle(_ raw: String, url: String) -> (title: String, artist: String) {
        var title = raw.trimmingCharacters(in: .whitespaces)
        if let range = title.range(of: #"^\(\d+\+?\)\s*"#, options: .regularExpression) {
            title.removeSubrange(range)
        }
        let suffixes = [" - YouTube Music", " - YouTube", " | Spotify", " - Spotify", " | Listen online for free on SoundCloud",
                        " | SoundCloud", " - Twitch", " | TikTok", " on Vimeo", " | Netflix", " - Apple Music", " | Zing MP3"]
        for suffix in suffixes where title.hasSuffix(suffix) {
            title = String(title.dropLast(suffix.count))
        }
        var artist = ""
        if url.contains("soundcloud.com"), title.hasPrefix("Stream ") {
            title = String(title.dropFirst("Stream ".count))
            if let r = title.range(of: " by ", options: .backwards) {
                artist = String(title[r.upperBound...])
                title = String(title[..<r.lowerBound])
            }
        } else if let r = title.range(of: " • ") {
            artist = String(title[r.upperBound...])
            title = String(title[..<r.lowerBound])
        } else if url.contains("youtube.com") || url.contains("youtu.be") {
            artist = "YouTube"
        }
        return (title.isEmpty ? raw : title, artist)
    }

    nonisolated private static func youTubeID(_ url: String) -> String? {
        guard let comps = URLComponents(string: url), let host = comps.host else { return nil }
        if host.contains("youtu.be") { return comps.path.split(separator: "/").first.map(String.init) }
        guard host.contains("youtube.com") else { return nil }
        if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value { return v }
        let parts = comps.path.split(separator: "/")
        if parts.count >= 2, parts[0] == "shorts" { return String(parts[1]) }
        return nil
    }

    /// Bundle IDs of apps holding a "playing audio" power assertion — Chromium
    /// browsers and WebKit (Safari) take one while a page makes sound.
    nonisolated private static func audibleBundleIDs() -> Set<String> {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byPID = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        var result = Set<String>()
        for (pid, assertions) in byPID {
            let isAudio = assertions.contains { assertion in
                let name = (assertion[kIOPMAssertionNameKey] as? String ?? "").lowercased()
                return name.contains("playing audio") || name.contains("media playback") || name.contains("audio playback")
            }
            guard isAudio,
                  let app = NSRunningApplication(processIdentifier: pid_t(pid.int32Value)),
                  var bundleID = app.bundleIdentifier else { continue }
            if bundleID.hasPrefix("com.apple.WebKit") { bundleID = "com.apple.Safari" }
            // Chromium helpers carry the browser's ID plus a suffix (e.g. ".helper").
            if let browser = Browser.all.first(where: { bundleID.hasPrefix($0.bundleID) }) { bundleID = browser.bundleID }
            result.insert(bundleID)
        }
        return result
    }
}

// MARK: - Playhead

/// Where the playhead is, published on its own: the open player's scrubber
/// and time labels observe this, so its twice-a-second tick doesn't rebuild
/// the rest of the player.
@MainActor
public final class PlayheadModel: ObservableObject {
    @Published public private(set) var position: TimeInterval = 0
    /// When `position` was taken, for extrapolating between ticks.
    public private(set) var stamp = Date()

    func set(_ position: TimeInterval, at stamp: Date) {
        self.stamp = stamp
        if position != self.position { self.position = position }
    }
}

// MARK: - Media keys

/// Posts the hardware play/next/previous keys, which macOS routes to whichever
/// app owns Now Playing (a YouTube tab, Podcasts…). Needs Accessibility access.
@MainActor
enum MediaKeys {
    enum Key: Int32 {
        case playPause = 16 // NX_KEYTYPE_PLAY
        case next = 17      // NX_KEYTYPE_NEXT
        case previous = 18  // NX_KEYTYPE_PREVIOUS
    }

    private static var didPrompt = false
    /// `eventSourceUserData` of the keys Tama posts itself.
    nonisolated static let postedMarker: Int64 = 0x44_52_4F_50

    static func post(_ key: Key) {
        guard AXIsProcessTrusted() else {
            if !didPrompt {
                didPrompt = true
                // The value of kAXTrustedCheckOptionPrompt, spelled out: the global isn't concurrency-safe.
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
            AppState.shared.showNotification(
                appName: "Tama",
                title: "Accessibility needed",
                message: "Allow Tama in System Settings › Privacy & Security › Accessibility to control browser playback."
            )
            return
        }
        for isDown in [true, false] {
            let state: Int = isDown ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: (Int(key.rawValue) << 16) | (state << 8),
                data2: -1
            )
            // Marked, so Tama's own media-key tap lets it through to macOS.
            let cgEvent = event?.cgEvent
            cgEvent?.setIntegerValueField(.eventSourceUserData, value: postedMarker)
            cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Up Next

public struct QueuedTrack: Identifiable, Equatable, Sendable {
    /// Position in Music's current playlist.
    public let index: Int
    public let persistentID: String
    public let title: String
    public let artist: String
    public let duration: TimeInterval

    public var id: String { "\(index)-\(persistentID)" }
}

public enum UpNextStatus: Equatable, Sendable {
    case idle
    case loading
    case loaded(playlist: String, shuffled: Bool)
    case unavailable(String)
}
