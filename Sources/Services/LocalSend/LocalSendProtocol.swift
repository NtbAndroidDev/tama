import Foundation
import UniformTypeIdentifiers

// The LocalSend v2 wire format (https://github.com/localsend/protocol):
// UDP multicast on 224.0.0.167:53317 to find devices, then a small REST API
// on TCP 53317 (HTTPS with a self-signed certificate, or plain HTTP) to
// register, prepare an upload and send each file.

enum LocalSendProtocol {
    static let multicastGroup = "224.0.0.167"
    static let port: UInt16 = 53317
    static let version = "2.1"
    static let apiPrefix = "/api/localsend/v2/"
    /// LocalSend 1.x. Older clients still speak it, so Tama answers it too:
    /// same ideas, different route names, and no session id.
    static let apiPrefixV1 = "/api/localsend/v1/"
}

/// Who a device says it is: in multicast announcements, /register and prepare-upload.
struct LocalSendDeviceInfo: Codable, Hashable, Sendable {
    var alias: String
    var version: String?
    var deviceModel: String?
    var deviceType: LocalSendDeviceType?
    var fingerprint: String
    var port: Int?
    /// "http" or "https".
    var `protocol`: String?
    var download: Bool?
    /// Multicast only: true asks everyone to answer.
    var announce: Bool?

    enum CodingKeys: String, CodingKey {
        case alias, version, deviceModel, deviceType, fingerprint, port, `protocol`, download, announce
    }

    // Unknown device types from newer clients decode as nil, not a failure.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alias = try c.decode(String.self, forKey: .alias)
        version = try c.decodeIfPresent(String.self, forKey: .version)
        deviceModel = try c.decodeIfPresent(String.self, forKey: .deviceModel)
        deviceType = (try? c.decodeIfPresent(String.self, forKey: .deviceType)).flatMap { $0 }.flatMap(LocalSendDeviceType.init(rawValue:))
        // v1 devices have no fingerprint; the caller fills one in from the host.
        fingerprint = try c.decodeIfPresent(String.self, forKey: .fingerprint) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        `protocol` = try c.decodeIfPresent(String.self, forKey: .protocol)
        download = try c.decodeIfPresent(Bool.self, forKey: .download)
        announce = try c.decodeIfPresent(Bool.self, forKey: .announce)
    }

    init(alias: String, version: String? = LocalSendProtocol.version, deviceModel: String?, deviceType: LocalSendDeviceType?,
         fingerprint: String, port: Int?, protocol: String?, download: Bool? = false, announce: Bool? = nil) {
        self.alias = alias
        self.version = version
        self.deviceModel = deviceModel
        self.deviceType = deviceType
        self.fingerprint = fingerprint
        self.port = port
        self.protocol = `protocol`
        self.download = download
        self.announce = announce
    }
}

enum LocalSendDeviceType: String, Codable, Sendable, CaseIterable {
    case mobile, desktop, web, headless, server

    /// An SF Symbol for the peer list, refined by the model name when there is one.
    static func symbol(type: LocalSendDeviceType?, model: String?) -> String {
        let model = (model ?? "").lowercased()
        if model.contains("iphone") { return "iphone" }
        if model.contains("ipad") { return "ipad" }
        if model.contains("macbook") { return "laptopcomputer" }
        if model.contains("imac") { return "desktopcomputer" }
        if model.contains("mac mini") || model.contains("macmini") { return "macmini" }
        if model.contains("mac pro") || model.contains("mac studio") { return "macpro.gen3" }
        switch type {
        case .mobile: return model.contains("tablet") ? "ipad" : "smartphone"
        case .desktop: return model.contains("linux") || model.contains("windows") ? "pc" : "desktopcomputer"
        case .web: return "globe"
        case .headless: return "terminal"
        case .server: return "server.rack"
        case nil: return "questionmark.circle"
        }
    }
}

/// One file offered in prepare-upload.
struct LocalSendFileInfo: Codable, Hashable, Sendable {
    var id: String
    var fileName: String
    var size: Int64
    var fileType: String
    var sha256: String?
    /// Text messages carry their text here and are never uploaded.
    var preview: String?
    var metadata: Metadata?

    struct Metadata: Codable, Hashable, Sendable {
        var modified: String?
        var accessed: String?
    }

    var isTextMessage: Bool { fileType.hasPrefix("text/plain") && preview != nil }
}

struct LocalSendPrepareRequest: Codable, Sendable {
    var info: LocalSendDeviceInfo
    var files: [String: LocalSendFileInfo]
}

struct LocalSendPrepareResponse: Codable, Sendable {
    var sessionId: String
    var files: [String: String]
}

/// What a browser or another device gets back from prepare-download: who is
/// offering, the session to quote and what is on offer.
struct LocalSendPrepareDownloadResponse: Codable, Sendable {
    var info: LocalSendDeviceInfo
    var sessionId: String
    var files: [String: LocalSendFileInfo]
}

// MARK: - Helpers shared by the sender and receiver

enum LocalSendFormat {
    /// "fileId" → "id", query parsing for `?sessionId=…&fileId=…&token=…&pin=…`.
    static func query(of target: String) -> [String: String] {
        guard let q = target.split(separator: "?", maxSplits: 1).dropFirst().first else { return [:] }
        var result: [String: String] = [:]
        for pair in q.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = parts.first.map(String.init)?.removingPercentEncoding else { continue }
            let raw = parts.count > 1 ? String(parts[1]) : ""
            result[key] = raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? raw
        }
        return result
    }

    /// The API version and route of a request, e.g. (2, "prepare-upload");
    /// nil for a path that isn't the LocalSend API at all.
    static func route(of target: String) -> (version: Int, name: String)? {
        let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        let prefixes = [(2, LocalSendProtocol.apiPrefix), (1, LocalSendProtocol.apiPrefixV1)]
        guard let (version, prefix) = prefixes.first(where: { path.hasPrefix($0.1) }) else { return nil }
        let rest = path.dropFirst(prefix.count)
        guard !rest.isEmpty, !rest.contains("/") else { return nil }
        return (version, String(rest))
    }

    /// The path of a request, without its query.
    static func path(of target: String) -> String {
        target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
    }

    /// A sender's file name made safe to write under the save folder: folders
    /// it names are kept, but never "..", absolute paths or hidden tricks.
    static func safeRelativePath(_ fileName: String) -> String? {
        let parts = fileName.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "." }
        guard !parts.isEmpty, !parts.contains("..") else { return nil }
        let cleaned = parts.map { part in
            String(part.unicodeScalars.map { $0.value < 0x20 || $0 == ":" ? "_" : Character($0) })
        }
        return cleaned.joined(separator: "/")
    }

    static func mimeType(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    static func isoDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        return ISO8601DateFormatter().string(from: date)
    }

    static func randomID() -> String { UUID().uuidString.lowercased() }

    /// What a sender shows for an HTTP status from prepare-upload or upload.
    static func senderError(status: Int) -> String {
        switch status {
        case 401: "This device asks for a PIN"
        case 403: "The receiver declined the transfer"
        case 409: "The receiver is busy with another transfer"
        case 429: "Too many requests. Wait a moment and try again."
        default: "The receiver reported an error (\(status))"
        }
    }

    /// "MacBookPro18,3" → "MacBook Pro"; newer "Mac14,2" style ids give nil.
    static func modelName(fromHardwareModel id: String) -> String? {
        let known: [(String, String)] = [("MacBookPro", "MacBook Pro"), ("MacBookAir", "MacBook Air"), ("MacBook", "MacBook"),
                                         ("iMacPro", "iMac Pro"), ("iMac", "iMac"), ("Macmini", "Mac mini"), ("MacPro", "Mac Pro")]
        return known.first { id.hasPrefix($0.0) }?.1
    }

    /// Expands folders into their files, named by their path under the
    /// folder's parent ("Photos/2024/a.jpg"), the way LocalSend sends folders.
    static func expand(_ urls: [URL]) -> [(url: URL, name: String)] {
        let fm = FileManager.default
        var result: [(URL, String)] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            guard isDirectory.boolValue else {
                result.append((url, url.lastPathComponent))
                continue
            }
            let base = url.deletingLastPathComponent().standardizedFileURL.path
            let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            while let file = enumerator?.nextObject() as? URL {
                guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let path = file.standardizedFileURL.path
                let relative = path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : file.lastPathComponent
                result.append((file, relative))
            }
        }
        return result
    }
}
