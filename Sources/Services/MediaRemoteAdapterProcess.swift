import Foundation

/// Runs `/usr/bin/perl` with DroppyMediaRemoteAdapter loaded (see
/// Adapters/MediaRemoteAdapter): since macOS 15.4 MediaRemote only answers
/// Apple's own processes, and perl is one of them. It streams Now Playing as
/// JSON lines and takes transport commands on stdin, so browsers get position,
/// seeking and artwork without "Allow JavaScript from Apple Events".
final class MediaRemoteAdapterProcess: @unchecked Sendable {
    static let shared = MediaRemoteAdapterProcess()

    /// Now Playing in MediaRemote's own dictionary keys, so MediaService reads
    /// it like a direct answer. Empty while nothing plays.
    var latest: [String: Any] { lock.withLock { _latest } }
    /// Whether the adapter has answered at all; until then the old sources run.
    var isLive: Bool { lock.withLock { _isLive } }
    /// Called on the main queue after every update.
    var onUpdate: (() -> Void)?

    static let bundleIDKey = "tamaBundleID"

    private let lock = NSLock()
    private var _latest: [String: Any] = [:]
    private var _isLive = false
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var restarts = 0
    private var isStopped = false
    private var artwork: Data?

    private init() {}

    private static let script = """
    use DynaLoader;
    my $h = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
    my $s = DynaLoader::dl_find_symbol($h, "droppy_mediaremote_stream") or die "missing entry point";
    DynaLoader::dl_install_xsub("main::droppy_mediaremote_stream", $s);
    main::droppy_mediaremote_stream();
    """

    /// Next to the executable when run from `.build`, in Frameworks inside the app.
    private static var libraryURL: URL? {
        let name = "libTamaMediaRemoteAdapter.dylib"
        var candidates: [URL] = []
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(exe.appendingPathComponent(name))
            candidates.append(exe.deletingLastPathComponent().appendingPathComponent("Frameworks").appendingPathComponent(name))
        }
        if let resources = Bundle.main.resourceURL { candidates.append(resources.appendingPathComponent(name)) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func start() {
        lock.lock(); defer { lock.unlock() }
        guard process == nil, !isStopped, let library = Self.libraryURL,
              FileManager.default.isExecutableFile(atPath: "/usr/bin/perl") else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = ["-e", Self.script, library.path]
        let stdout = Pipe(), stdin = Pipe()
        task.standardOutput = stdout
        task.standardInput = stdin
        task.standardError = FileHandle.nullDevice

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.consume(data)
        }
        task.terminationHandler = { [weak self] _ in self?.didTerminate() }

        do {
            try task.run()
        } catch {
            return
        }
        process = task
        input = stdin.fileHandleForWriting
    }

    func stop() {
        lock.lock()
        let task = process
        process = nil
        isStopped = true
        lock.unlock()
        // Closing stdin makes the adapter exit on its own.
        try? input?.close()
        task?.terminate()
    }

    /// `play`, `pause`, `toggle`, `next`, `previous`, `seek <seconds>`, `refresh`.
    /// Returns false when the adapter isn't there to take it.
    @discardableResult
    func send(_ command: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard _isLive, let input, process?.isRunning == true,
              let data = (command + "\n").data(using: .utf8) else { return false }
        do {
            try input.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Reading

    private func consume(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            lines.append(buffer.subdata(in: buffer.startIndex..<newline))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        lock.unlock()

        var changed = false
        for line in lines {
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if object["error"] != nil { continue }
            if object["ready"] != nil {
                lock.lock(); _isLive = true; restarts = 0; lock.unlock()
                continue
            }
            let info = translate(object)
            lock.lock(); _latest = info; lock.unlock()
            changed = true
        }
        if changed {
            DispatchQueue.main.async { [weak self] in self?.onUpdate?() }
        }
    }

    /// Back to MediaRemote's keys, so MediaService's existing path reads it.
    private func translate(_ object: [String: Any]) -> [String: Any] {
        guard object["empty"] == nil, let title = object["title"] as? String else {
            artwork = nil
            return [:]
        }
        var info: [String: Any] = ["kMRMediaRemoteNowPlayingInfoTitle": title]
        info["kMRMediaRemoteNowPlayingInfoArtist"] = object["artist"] as? String
        info["kMRMediaRemoteNowPlayingInfoAlbum"] = object["album"] as? String
        info["kMRMediaRemoteNowPlayingInfoDuration"] = (object["duration"] as? NSNumber)?.doubleValue
        info["kMRMediaRemoteNowPlayingInfoElapsedTime"] = (object["elapsed"] as? NSNumber)?.doubleValue
        // The rate can stay 1 while paused in some players; the playing flag is the truth.
        let playing = (object["playing"] as? NSNumber)?.boolValue ?? false
        let rate = (object["rate"] as? NSNumber)?.doubleValue ?? (playing ? 1 : 0)
        info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = playing ? max(rate, 0.01) : 0.0
        if let stamp = (object["timestamp"] as? NSNumber)?.doubleValue {
            info["kMRMediaRemoteNowPlayingInfoTimestamp"] = Date(timeIntervalSince1970: stamp)
        }
        info[Self.bundleIDKey] = object["bundleID"] as? String
        // Artwork is only sent when it changes; keep the last one for this track.
        if let encoded = object["artwork"] as? String, let data = Data(base64Encoded: encoded) {
            artwork = data
        } else if object["artworkID"] == nil {
            artwork = nil
        }
        info["kMRMediaRemoteNowPlayingInfoArtworkData"] = artwork
        return info
    }

    private func didTerminate() {
        lock.lock()
        process = nil
        input = nil
        _isLive = false
        _latest = [:]
        buffer.removeAll()
        restarts += 1
        let attempt = restarts
        let stopped = isStopped
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.onUpdate?() }
        // A crash or a macOS update that closes the door: retry a few times with
        // backoff, then leave it to the AppleScript sources.
        guard !stopped, attempt <= 5 else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + Double(attempt * attempt)) { [weak self] in
            self?.start()
        }
    }
}
