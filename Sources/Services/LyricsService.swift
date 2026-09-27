import Foundation
import CryptoKit
import Combine

public struct LyricLine: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    /// Seconds into the song; nil for unsynced (plain) lyrics.
    public let time: TimeInterval?
    public let text: String
}

public struct Lyrics: Codable, Equatable, Sendable {
    public var lines: [LyricLine]
    public var isSynced: Bool

    /// Index of the line being sung at `position`, nil before the first one.
    public func lineIndex(at position: TimeInterval) -> Int? {
        guard isSynced else { return nil }
        var low = 0, high = lines.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if (lines[mid].time ?? 0) <= position {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    /// Parses LRC: one or more `[mm:ss.xx]` stamps before each line's text.
    /// Metadata tags (`[ar:…]`) are skipped; `[offset:±ms]` is honoured.
    public static func parseLRC(_ text: String) -> Lyrics? {
        let stamp = /\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]/
        var offset: TimeInterval = 0
        var timed: [(TimeInterval, String)] = []
        for raw in text.components(separatedBy: .newlines) {
            var line = Substring(raw.trimmingCharacters(in: .whitespaces))
            if let match = line.wholeMatch(of: /\[offset:\s*([+-]?\d+)\]/), let ms = Double(match.1) {
                // Positive offsets make lyrics appear sooner.
                offset = -ms / 1000
                continue
            }
            var times: [TimeInterval] = []
            while let match = line.prefixMatch(of: stamp) {
                let minutes = Double(match.1) ?? 0
                let seconds = Double(match.2.replacingOccurrences(of: ":", with: ".")) ?? 0
                times.append(minutes * 60 + seconds)
                line = line[match.range.upperBound...]
            }
            guard !times.isEmpty else { continue }
            let words = line.trimmingCharacters(in: .whitespaces)
            for t in times { timed.append((t, words)) }
        }
        guard !timed.isEmpty else { return nil }
        let lines = timed
            .sorted { $0.0 < $1.0 }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: max($0.element.0 + offset, 0), text: $0.element.1) }
        return Lyrics(lines: lines, isSynced: true)
    }

    public static func plain(_ text: String) -> Lyrics? {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.contains(where: { !$0.isEmpty }) else { return nil }
        return Lyrics(lines: lines.enumerated().map { LyricLine(id: $0.offset, time: nil, text: $0.element) }, isSynced: false)
    }
}

public enum LyricsState: Equatable, Sendable {
    case idle
    /// Online lookup is off; the panel explains what turning it on sends.
    case disabled
    case loading
    case loaded(Lyrics)
    case instrumental
    case notFound
    case failed
    /// No internet and nothing cached: "No Internet Connection".
    case offline
}

/// Synced lyrics from LRCLIB (lrclib.net), a free, open lyrics database.
/// Online lookups are opt-in; results and misses are cached on disk.
@MainActor
public final class LyricsService: ObservableObject {
    public static let shared = LyricsService()
    public static let onlineKey = "fetchLyricsOnline"

    @Published public private(set) var state: LyricsState = .idle
    /// How LRCLIB matched the song: "Found by artist" or "Found by title".
    @Published public private(set) var foundBy: String?
    private var currentKey: String?
    private var memory: [String: CacheEntry] = [:]
    private var task: Task<Void, Never>?

    nonisolated private static let userAgent = "Tama/1.0 (macOS)"
    nonisolated private static let missLifetime: TimeInterval = 86_400

    private struct CacheEntry: Codable, Sendable {
        var lyrics: Lyrics?
        var instrumental: Bool
        var fetchedAt: Date
        /// Optional so caches written before it existed still decode.
        var foundBy: String?

        var isStaleMiss: Bool {
            lyrics == nil && !instrumental && Date().timeIntervalSince(fetchedAt) > LyricsService.missLifetime
        }
    }

    private var connectivitySink: AnyCancellable?

    private init() {
        // Back online after an offline miss: look the song up again.
        connectivitySink = ConnectivityService.shared.$isOnline
            .removeDuplicates()
            .filter { $0 }
            .sink { _ in
                Task { @MainActor in
                    let service = LyricsService.shared
                    guard service.state == .offline || service.state == .failed else { return }
                    service.load(for: MediaService.shared.currentTrack, force: true)
                }
            }
    }

    public var isOnlineEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.onlineKey)
    }

    /// Loads lyrics for `track` unless they're already showing. `force` retries after a failure.
    public func load(for track: MediaTrack, force: Bool = false) {
        guard track.hasTrack else {
            reset(to: .idle)
            return
        }
        guard isOnlineEnabled else {
            reset(to: .disabled)
            return
        }
        let query = Query(track: track)
        let key = query.key
        if key == currentKey, !force, state != .disabled, state != .idle { return }
        task?.cancel()
        currentKey = key

        if let entry = memory[key], !entry.isStaleMiss {
            apply(entry)
            return
        }
        state = .loading
        task = Task { [weak self] in
            if let entry = await Self.readDisk(key), !entry.isStaleMiss {
                self?.finish(key: key, entry: entry, persist: false)
                return
            }
            guard ConnectivityService.shared.isOnline else {
                if let self, self.currentKey == key { self.state = .offline }
                return
            }
            do {
                let entry = try await Self.fetch(query)
                self?.finish(key: key, entry: entry, persist: true)
            } catch {
                guard !Task.isCancelled, let self, self.currentKey == key else { return }
                // Network trouble isn't a miss: don't cache it, let Retry try again.
                self.state = ConnectivityService.shared.isOnline ? .failed : .offline
            }
        }
    }

    private func reset(to newState: LyricsState) {
        task?.cancel()
        currentKey = nil
        state = newState
        foundBy = nil
    }

    private func finish(key: String, entry: CacheEntry, persist: Bool) {
        memory[key] = entry
        if memory.count > 60 { memory.removeAll() }
        if persist { Task.detached(priority: .utility) { Self.writeDisk(entry, key: key) } }
        guard currentKey == key else { return }
        apply(entry)
    }

    private func apply(_ entry: CacheEntry) {
        foundBy = entry.lyrics == nil ? nil : entry.foundBy
        if let lyrics = entry.lyrics {
            state = .loaded(lyrics)
        } else {
            state = entry.instrumental ? .instrumental : .notFound
        }
    }

    // MARK: Query

    private struct Query: Sendable {
        var title: String
        var artist: String
        var album: String
        var duration: Int

        /// Browser tabs report "Artist - Song (Official Video)" as the title and
        /// the site as the artist; tidy that into something LRCLIB can match.
        init(track: MediaTrack) {
            var title = track.title
            var artist = track.artist
            let placeholderArtist = artist.isEmpty || artist == "YouTube" || artist == track.sourceApp
            title = title.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*\b(official|lyrics?|video|audio|visuali[sz]er|mv|hd|4k)\b[^\)\]]*[\)\]]"#,
                                               with: "", options: [.regularExpression, .caseInsensitive])
            if placeholderArtist, let dash = title.range(of: " - ") {
                artist = String(title[..<dash.lowerBound])
                title = String(title[dash.upperBound...])
            } else if placeholderArtist {
                artist = ""
            }
            self.title = title.trimmingCharacters(in: .whitespaces)
            self.artist = artist.trimmingCharacters(in: .whitespaces)
            self.album = track.album.trimmingCharacters(in: .whitespaces)
            self.duration = Int(track.duration.rounded())
        }

        var key: String {
            let raw = [title, artist, album].map { $0.lowercased() }.joined(separator: "|") + "|\(duration)"
            return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    private struct Record: Decodable, Sendable {
        var duration: Double?
        var instrumental: Bool?
        var plainLyrics: String?
        var syncedLyrics: String?
    }

    // MARK: Network

    nonisolated private static func fetch(_ query: Query) async throws -> CacheEntry {
        // The exact lookup needs every field; without an album or a length go straight to search.
        if !query.album.isEmpty, query.duration > 0, !query.artist.isEmpty {
            var comps = URLComponents(string: "https://lrclib.net/api/get")!
            comps.queryItems = [
                URLQueryItem(name: "track_name", value: query.title),
                URLQueryItem(name: "artist_name", value: query.artist),
                URLQueryItem(name: "album_name", value: query.album),
                URLQueryItem(name: "duration", value: String(query.duration)),
            ]
            if let (data, status) = try await request(comps.url!), status == 200,
               let record = try? JSONDecoder().decode(Record.self, from: data),
               var entry = entry(from: record) {
                entry.foundBy = "Found by artist"
                return entry
            }
        }

        var comps = URLComponents(string: "https://lrclib.net/api/search")!
        comps.queryItems = [URLQueryItem(name: "q", value: [query.title, query.artist].filter { !$0.isEmpty }.joined(separator: " "))]
        guard let (data, status) = try await request(comps.url!), status == 200 else {
            return CacheEntry(lyrics: nil, instrumental: false, fetchedAt: Date())
        }
        let records = (try? JSONDecoder().decode([Record].self, from: data)) ?? []
        // Prefer synced lyrics of a recording about the same length.
        let closeEnough: (Record) -> Bool = { record in
            guard query.duration > 0, let d = record.duration else { return true }
            return abs(d - Double(query.duration)) <= 3
        }
        let close = records.filter(closeEnough)
        // Live cuts and remasters differ in length; a wrong-length match beats none.
        let ranked = (close.isEmpty ? records : close).sorted { ($0.syncedLyrics != nil ? 0 : 1) < ($1.syncedLyrics != nil ? 0 : 1) }
        for record in ranked {
            if var entry = entry(from: record) {
                entry.foundBy = query.artist.isEmpty ? "Found by title" : "Found by artist"
                return entry
            }
        }
        return CacheEntry(lyrics: nil, instrumental: false, fetchedAt: Date())
    }

    nonisolated private static func entry(from record: Record) -> CacheEntry? {
        if let synced = record.syncedLyrics, let lyrics = Lyrics.parseLRC(synced) {
            return CacheEntry(lyrics: lyrics, instrumental: false, fetchedAt: Date())
        }
        if let plain = record.plainLyrics, let lyrics = Lyrics.plain(plain) {
            return CacheEntry(lyrics: lyrics, instrumental: false, fetchedAt: Date())
        }
        if record.instrumental == true {
            return CacheEntry(lyrics: nil, instrumental: true, fetchedAt: Date())
        }
        return nil
    }

    /// nil status means "not found" territory (404); transport errors throw.
    nonisolated private static func request(_ url: URL) async throws -> (Data, Int)? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status >= 500 { throw URLError(.badServerResponse) }
        return (data, status)
    }

    // MARK: Disk cache

    nonisolated private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Tama/Lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated private static func readDisk(_ key: String) async -> CacheEntry? {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("\(key).json")) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(CacheEntry.self, from: data)
        }.value
    }

    nonisolated private static func writeDisk(_ entry: CacheEntry, key: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entry) else { return }
        try? data.write(to: directory.appendingPathComponent("\(key).json"), options: .atomic)
    }
}
