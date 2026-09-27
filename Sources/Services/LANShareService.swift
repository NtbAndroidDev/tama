import Foundation
import Network
import Darwin

/// Serves Tray files over the local network so a phone or another computer on
/// the same Wi-Fi can download them from a link or QR code.
///
/// One share at a time. The URL carries a random token, the server listens only
/// while a share is live, and it stops itself when the share expires.
@MainActor
public final class LANShareService: ObservableObject {
    public static let shared = LANShareService()

    public enum Expiry: String, CaseIterable, Identifiable, Sendable {
        case fifteenMinutes = "15 min"
        case oneHour = "1 hour"
        case untilQuit = "Until Tama quits"
        public var id: String { rawValue }
        var interval: TimeInterval? {
            switch self {
            case .fifteenMinutes: 15 * 60
            case .oneHour: 60 * 60
            case .untilQuit: nil
            }
        }
    }

    public struct Share: Sendable {
        public let url: URL
        public let expiresAt: Date?
        public let fileCount: Int
    }

    @Published public private(set) var activeShare: Share?
    @Published public private(set) var downloadCount = 0

    private var listener: NWListener?
    private var expiryWork: DispatchWorkItem?
    /// Bumped by every start and stop. A start that finds it changed across
    /// an await was superseded or cancelled, and backs out without touching
    /// the share that replaced it.
    private var generation = 0
    /// Zips made of shared folders; removed when the share stops.
    private var zippedCopies: [URL] = []
    private let queue = DispatchQueue(label: "app.tama.lanshare")

    public enum ShareError: LocalizedError {
        case noNetwork, listenerFailed(String)
        public var errorDescription: String? {
            switch self {
            case .noNetwork: "This Mac isn't on a local network. Join Wi-Fi or Ethernet and try again."
            case let .listenerFailed(reason): "Couldn't start sharing: \(reason)"
            }
        }
    }

    /// Starts serving `files`, replacing any share already running.
    public func start(files: [URL], expiry: Expiry) async throws -> Share {
        stop()
        let gen = generation
        guard let host = Self.localIPv4Address() else { throw ShareError.noNetwork }
        // A folder can't be sent as one download; serve it zipped.
        let originals = files
        let files = await Task.detached(priority: .userInitiated) { Self.servableFiles(originals) }.value
        let zipped = zip(originals, files).filter { $0 != $1 }.map(\.1)
        guard gen == generation else {
            Self.removeZipDirs(zipped)
            throw CancellationError()
        }
        zippedCopies = zipped
        do {
            return try await serve(files, host: host, expiry: expiry, generation: gen)
        } catch {
            // A superseded start's zips were already cleared by the stop that
            // replaced it; the ones here now belong to the newer share.
            if gen == generation { removeZippedCopies() }
            throw error
        }
    }

    private func serve(_ files: [URL], host: String, expiry: Expiry, generation gen: Int) async throws -> Share {

        let token = Self.randomToken()
        let catalog = ShareCatalog(token: token, files: files)
        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp, on: .any)
        } catch {
            throw ShareError.listenerFailed(error.localizedDescription)
        }
        // @Sendable: these run on the network queue, never on the main actor.
        let queue = self.queue
        let onServed: @Sendable (Bool) -> Void = { [weak self] served in
            guard served else { return }
            Task { @MainActor in self?.downloadCount += 1 }
        }
        listener.newConnectionHandler = { @Sendable connection in
            HTTPExchange(connection: connection, catalog: catalog, onServed: onServed).start(on: queue)
        }

        let port: UInt16 = try await withCheckedThrowingContinuation { cont in
            let resumed = ResumeOnce()
            listener.stateUpdateHandler = { @Sendable state in
                switch state {
                case .ready:
                    if resumed.claim() { cont.resume(returning: listener.port?.rawValue ?? 0) }
                case let .failed(error):
                    if resumed.claim() { cont.resume(throwing: ShareError.listenerFailed(error.localizedDescription)) }
                case .cancelled:
                    if resumed.claim() { cont.resume(throwing: ShareError.listenerFailed("cancelled")) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }

        guard gen == generation else {
            listener.cancel()
            throw CancellationError()
        }
        self.listener = listener
        downloadCount = 0
        let url = Self.shareURL(host: host, port: port, token: token)
        let expiresAt = expiry.interval.map { Date().addingTimeInterval($0) }
        let share = Share(url: url, expiresAt: expiresAt, fileCount: files.count)
        activeShare = share

        if let interval = expiry.interval {
            let work = DispatchWorkItem { [weak self] in self?.stop() }
            expiryWork = work
            // Wall clock: a Mac that sleeps through the expiry still stops on
            // time instead of the link living on for the length of the nap.
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + interval, execute: work)
        }
        return share
    }

    public func stop() {
        generation += 1
        expiryWork?.cancel()
        expiryWork = nil
        listener?.cancel()
        listener = nil
        activeShare = nil
        removeZippedCopies()
    }

    private func removeZippedCopies() {
        let copies = zippedCopies
        zippedCopies = []
        Self.removeZipDirs(copies)
    }

    private static func removeZipDirs(_ copies: [URL]) {
        let dirs = copies.map { $0.deletingLastPathComponent() }
        guard !dirs.isEmpty else { return }
        Task.detached(priority: .background) {
            for dir in dirs { try? FileManager.default.removeItem(at: dir) }
        }
    }

    // MARK: Helpers

    /// Files as they are; each folder replaced by a zip of it in the temporary
    /// folder (a folder that can't be zipped stays and is reported missing).
    nonisolated static func servableFiles(_ files: [URL]) -> [URL] {
        let fm = FileManager.default
        return files.map { url in
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return url }
            let dir = fm.temporaryDirectory.appendingPathComponent("Tama Share/\(UUID().uuidString)", isDirectory: true)
            let zip = dir.appendingPathComponent(url.lastPathComponent + ".zip")
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", url.path, zip.path]
            guard (try? process.run()) != nil else { return url }
            process.waitUntilExit()
            return process.terminationStatus == 0 && fm.fileExists(atPath: zip.path) ? zip : url
        }
    }

    /// The link printed in the QR code: the token is the only path segment.
    nonisolated static func shareURL(host: String, port: UInt16, token: String) -> URL {
        URL(string: "http://\(host):\(port)/\(token)/")!
    }

    nonisolated static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 12)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// The Mac's LAN address, preferring Wi-Fi/Ethernet (en*) over anything else.
    nonisolated static func localIPv4Address() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var candidates: [(name: String, address: String)] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = pointer.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  (ifa.ifa_flags & UInt32(IFF_UP)) != 0, (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let address = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard !address.hasPrefix("169.254.") else { continue }
            candidates.append((String(cString: ifa.ifa_name), address))
        }
        return (candidates.first { $0.name.hasPrefix("en") } ?? candidates.first)?.address
    }
}

/// Guards a continuation against the listener reporting more than one state.
private final class ResumeOnce: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// What a share exposes: an index page and each file by position.
private struct ShareCatalog: Sendable {
    let token: String
    let files: [URL]
}

/// Maps a request target to what a share serves. Only the token's paths exist.
enum ShareRoute: Equatable {
    case index
    case file(Int)
    case notFound

    init(target: String, token: String, fileCount: Int) {
        let path = target.split(separator: "?", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let prefix = "/\(token)/"
        if path == prefix || path == String(prefix.dropLast()) {
            self = .index
            return
        }
        // Digits only: Int("+1") would otherwise alias file 1.
        let rest = path.hasPrefix(prefix + "f/") ? path.dropFirst(prefix.count + 2) : ""
        guard !rest.isEmpty, rest.allSatisfy(\.isASCII), rest.allSatisfy(\.isNumber),
              let index = Int(rest), index < fileCount else {
            self = .notFound
            return
        }
        self = .file(index)
    }

    /// ASCII fallback for old clients plus the RFC 5987 UTF-8 name. Quotes
    /// and control characters can't break out of the header.
    static func contentDisposition(filename name: String) -> String {
        let ascii = name.unicodeScalars.map { $0.isASCII && $0 != "\"" && $0 != "\\" && $0.value >= 0x20 && $0.value != 0x7F ? String($0) : "_" }.joined()
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? ascii
        return "attachment; filename=\"\(ascii)\"; filename*=UTF-8''\(encoded)"
    }
}

/// One request/response over a connection. Only GET, only the token's paths.
private final class HTTPExchange: @unchecked Sendable {
    private let connection: NWConnection
    private let catalog: ShareCatalog
    private let onServed: @Sendable (Bool) -> Void
    private var buffer = Data()

    init(connection: NWConnection, catalog: ShareCatalog, onServed: @escaping @Sendable (Bool) -> Void) {
        self.connection = connection
        self.catalog = catalog
        self.onServed = onServed
    }

    func start(on queue: DispatchQueue) {
        connection.start(queue: queue)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [self] data, _, isComplete, error in
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                respond(to: String(decoding: buffer[..<end.lowerBound], as: UTF8.self))
            } else if isComplete || error != nil || buffer.count > 64 * 1024 {
                connection.cancel()
            } else {
                receive()
            }
        }
    }

    private func respond(to head: String) {
        let parts = head.split(separator: "\r\n").first?.split(separator: " ") ?? []
        guard parts.count >= 2, parts[0] == "GET" else { return send(status: "405 Method Not Allowed", body: "") }
        let index: Int
        switch ShareRoute(target: String(parts[1]), token: catalog.token, fileCount: catalog.files.count) {
        case .index: return send(status: "200 OK", type: "text/html; charset=utf-8", body: indexPage())
        case .notFound: return send(status: "404 Not Found", body: "Not found")
        case let .file(i): index = i
        }
        let url = catalog.files[index]
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return send(status: "410 Gone", body: "This file is no longer on the Mac.")
        }
        let header = "HTTP/1.1 200 OK\r\n"
            + "Content-Type: application/octet-stream\r\n"
            + "Content-Length: \(data.count)\r\n"
            + "Content-Disposition: \(ShareRoute.contentDisposition(filename: url.lastPathComponent))\r\n"
            + "Connection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in })
        connection.send(content: data, isComplete: true, completion: .contentProcessed { [self] error in
            onServed(error == nil)
            connection.cancel()
        })
    }

    private func send(status: String, type: String = "text/plain; charset=utf-8", body: String) {
        let bytes = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(bytes.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + bytes, isComplete: true, completion: .contentProcessed { [self] _ in
            connection.cancel()
        })
    }

    private func indexPage() -> String {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        let rows = catalog.files.enumerated().map { index, url -> String in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }
                .map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "missing"
            // Absolute: from "/<token>" (no trailing slash) a relative "f/0"
            // would resolve to "/f/0" and 404.
            return "<a href=\"/\(catalog.token)/f/\(index)\"><span>\(escape(url.lastPathComponent))</span><small>\(size)</small></a>"
        }.joined()
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Tama</title><style>
        body{font:16px -apple-system,system-ui,sans-serif;margin:0;padding:24px 16px;background:#0b0b0d;color:#f2f2f5}
        h1{font-size:20px;margin:0 0 4px}p{color:#9a9aa3;margin:0 0 20px;font-size:14px}
        a{display:flex;justify-content:space-between;gap:12px;padding:14px 16px;margin-bottom:8px;border-radius:12px;
        background:#1c1c20;color:inherit;text-decoration:none}a:active{background:#2a2a30}
        span{overflow-wrap:anywhere}small{color:#9a9aa3;white-space:nowrap}
        </style></head><body><h1>Files from Tama</h1><p>Tap a file to download it.</p>\(rows)</body></html>
        """
    }
}
