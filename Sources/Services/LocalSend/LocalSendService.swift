import AppKit
import SwiftUI
import Combine
import SystemConfiguration
import IOKit

enum LocalSendError: LocalizedError {
    case portInUse
    case discovery(String)
    case receiver(String)
    case invalidResponse
    case unreachable
    case fingerprintMismatch
    case status(Int)
    case cancelled
    case noFiles

    var errorDescription: String? {
        switch self {
        case .portInUse: "Port 53317 is in use. Quit LocalSend on this Mac (or anything else on that port), then turn the receiver on again."
        case let .discovery(reason): "Couldn't join the LocalSend network: \(reason)"
        case let .receiver(reason): "Couldn't start the receiver: \(reason)"
        case .invalidResponse: "The receiver sent an invalid response"
        case .unreachable: "This device can no longer be reached"
        case .fingerprintMismatch: "The device's certificate doesn't match the fingerprint it announced, so nothing was sent."
        case let .status(code): LocalSendFormat.senderError(status: code)
        case .cancelled: "Transfer cancelled"
        case .noFiles: "There are no files to send."
        }
    }
}

public enum LocalSendReceiveMode: String, CaseIterable, Identifiable, Sendable {
    case off, favorites, anyone
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .off: "Off"
        case .favorites: "Favorites"
        case .anyone: "Anyone"
        }
    }
    public var detail: String {
        switch self {
        case .off: "Nobody can send files to this Mac. You can still send."
        case .favorites: "Only devices you marked as favorites can send, and you're asked first unless Quick Save is on."
        case .anyone: "Receive from anyone on this network. You accept each transfer first."
        }
    }
}

/// A device found on the network.
struct LocalSendPeer: Identifiable, Hashable, Sendable {
    var info: LocalSendDeviceInfo
    var host: String
    var lastSeen: Date
    var id: String { info.fingerprint }
    var port: Int { info.port ?? Int(LocalSendProtocol.port) }
    var isHTTPS: Bool { (info.protocol ?? "https") == "https" }
    var symbol: String { LocalSendDeviceType.symbol(type: info.deviceType, model: info.deviceModel) }
    var baseURL: URL? { URL(string: "\(isHTTPS ? "https" : "http")://\(host.contains(":") ? "[\(host)]" : host):\(port)") }
}

struct LocalSendFavorite: Codable, Hashable, Identifiable, Sendable {
    var fingerprint: String
    var alias: String
    var deviceModel: String?
    var deviceType: String?
    var id: String { fingerprint }
    var symbol: String { LocalSendDeviceType.symbol(type: deviceType.flatMap(LocalSendDeviceType.init(rawValue:)), model: deviceModel) }
}

/// LocalSend-compatible nearby transfer: this Mac announces itself, lists
/// devices running LocalSend (phones, PCs, other Macs), sends files to them
/// and receives from them into a folder of your choice.
@MainActor
final class LocalSendService: ObservableObject {
    static let shared = LocalSendService()

    enum ReceiverState: Equatable {
        case off
        /// "Starting the receiver"
        case starting
        case running
        case failed(String)
    }

    struct Outgoing: Equatable {
        enum Phase: Equatable { case waiting, sending, done, failed(String), cancelled }
        var peerName: String
        var fileCount: Int
        var totalBytes: Int64
        var sentBytes: Int64
        var phase: Phase
        var progress: Double { totalBytes > 0 ? min(1, Double(sentBytes) / Double(totalBytes)) : 0 }
    }

    struct IncomingRequest: Identifiable, Equatable {
        let id = UUID()
        var sender: LocalSendDeviceInfo
        var host: String
        var files: [LocalSendFileInfo]
        var message: String?
        var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
    }

    struct Receiving: Equatable {
        var senderName: String
        var fileCount: Int
        var doneCount: Int
        var totalBytes: Int64
        var receivedBytes: Int64
        var progress: Double { totalBytes > 0 ? min(1, Double(receivedBytes) / Double(totalBytes)) : 0 }
    }

    @Published private(set) var receiverState: ReceiverState = .off
    @Published private(set) var peers: [LocalSendPeer] = []
    @Published private(set) var isScanning = false
    @Published private(set) var favorites: [LocalSendFavorite] = []
    @Published private(set) var fingerprint: String?
    @Published var staged: [URL] = [] {
        didSet {
            guard staged != oldValue else { return }
            stagedBytes = staged.reduce(Int64(0)) { total, url in
                total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
    }
    /// What `staged` adds up to, worked out when the files are picked. The
    /// console's summary is redrawn on every progress tick of a transfer, and
    /// reading the sizes there meant a `stat` per file per tick.
    @Published private(set) var stagedBytes: Int64 = 0
    @Published private(set) var outgoing: Outgoing?
    @Published private(set) var incoming: IncomingRequest?
    @Published private(set) var receiving: Receiving?
    @Published private(set) var lastReceived: [URL] = []
    /// Files this Mac is holding out for a browser to fetch, if any.
    /// Set only through `startOffer()` / `stopOffer()` in LocalSendDownload;
    /// everything else reads it.
    @Published var offer: Offer?

    /// "Share in a browser": instead of pushing files at a device, Tama puts
    /// them behind a plain web page anything on the network can open — a phone
    /// with no LocalSend installed, a Windows PC, a TV.
    struct Offer: Identifiable, Sendable {
        let id: String
        var files: [String: LocalSendFileInfo]
        var sources: [String: URL]
        var started = Date()
        /// Files fetched at least once, so the console can say what has landed.
        var fetched: Set<String> = []

        var sorted: [LocalSendFileInfo] {
            files.values.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
        }
        var totalBytes: Int64 { files.values.reduce(0) { $0 + $1.size } }
    }

    private var server: LocalSendHTTPServer?
    private var multicast: LocalSendMulticast?
    private var identity: LocalSendTLS.Identity?
    private var dropletSink: AnyCancellable?
    private var announceTimer: Timer?
    private var session: ReceiveSession?
    private var sessionTimer: Timer?
    private var decision: CheckedContinuation<Bool, Never>?
    private var sendTask: Task<Void, Never>?
    private var pinFailures: [Date] = []
    private var lastAnswered: [String: Date] = [:]

    static let favoritesKey = "localSendFavorites"
    private static let httpFingerprintKey = "localSendHTTPFingerprint"

    private init() {}

    var isEnabled: Bool { AppState.shared.droplets.first { $0.id == "localSend" }?.isEnabled ?? false }

    // MARK: Lifecycle

    /// Follows the droplet's switch from now on.
    func start() {
        dropletSink = AppState.shared.$droplets
            .map { $0.first { $0.id == "localSend" }?.isEnabled ?? false }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { Task { await self.startReceiver() } } else { self.stopAll() }
            }
    }

    func restart() {
        guard isEnabled else { return }
        stopAll()
        Task { await startReceiver() }
    }

    /// The name or visibility changed: tell the network.
    func settingsChanged() {
        guard receiverState == .running else { return }
        if AppState.shared.localSendVisible { announce() }
    }

    private func startReceiver() async {
        guard isEnabled, server == nil else { return }
        receiverState = .starting
        let encrypted = AppState.shared.localSendEncrypted
        if encrypted {
            do {
                let made = try await Task.detached(priority: .userInitiated) { try LocalSendTLS.loadOrCreate() }.value
                identity = made
                fingerprint = made.fingerprint
            } catch {
                DroppyLog.error("LocalSend", "TLS identity failed: \(error.localizedDescription)")
                receiverState = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                return
            }
        } else {
            identity = nil
            fingerprint = Self.httpFingerprint()
        }
        guard isEnabled else { receiverState = .off; return }

        let server = LocalSendHTTPServer { request in
            await LocalSendService.shared.route(request)
        }
        do {
            try await server.start(port: LocalSendProtocol.port, identity: encrypted ? identity : nil)
        } catch {
            DroppyLog.error("LocalSend", "Receiver failed: \(error.localizedDescription)")
            receiverState = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return
        }
        guard isEnabled else { server.stop(); receiverState = .off; return }
        self.server = server

        let multicast = LocalSendMulticast { data, host in
            Task { @MainActor in LocalSendService.shared.heard(data, from: host) }
        }
        do {
            try multicast.start()
            self.multicast = multicast
        } catch {
            // Sending by address and scanning still work without multicast.
            DroppyLog.error("LocalSend", "Multicast failed: \(error.localizedDescription)")
        }
        receiverState = .running
        DroppyLog.info("LocalSend", "Receiver running (\(encrypted ? "https" : "http")), fingerprint \(fingerprint ?? "-")")
        announce()
        // Re-announce now and then so devices that came later see this Mac.
        announceTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in
                // A sleeping Mac can't take a transfer; don't wake the radio to say it can.
                guard !PowerStateService.shared.isDormant else { return }
                let service = LocalSendService.shared
                service.prunePeers()
                if AppState.shared.localSendVisible { service.announce() }
            }
        }
    }

    private func stopAll() {
        announceTimer?.invalidate()
        announceTimer = nil
        server?.stop()
        server = nil
        multicast?.stop()
        multicast = nil
        if let session { endSession(session, error: "LocalSend was turned off") }
        decision?.resume(returning: false)
        decision = nil
        incoming = nil
        LocalSendPromptController.shared.close()
        sendTask?.cancel()
        // Nothing can be fetched with the server down, so don't keep saying so.
        offer = nil
        peers = []
        receiverState = .off
    }

    // MARK: Identity

    var deviceName: String {
        let name = AppState.shared.localSendDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? Self.macName : name
    }

    static var macName: String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? Host.current().localizedName ?? "Mac"
    }

    /// "MacBook Pro" etc., from the device tree's product name or hw.model.
    static let modelName: String = {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        if entry != 0 {
            defer { IOObjectRelease(entry) }
            if let data = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Data {
                let name = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
                // "MacBook Pro (14-inch, M3, 2023)" → "MacBook Pro"
                let short = name.components(separatedBy: " (").first ?? name
                if !short.isEmpty { return short }
            }
        }
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let id = String(decoding: model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return LocalSendFormat.modelName(fromHardwareModel: id) ?? "Mac"
    }()

    private static func httpFingerprint() -> String {
        if let stored = UserDefaults.standard.string(forKey: httpFingerprintKey) { return stored }
        let made = LocalSendFormat.randomID()
        UserDefaults.standard.set(made, forKey: httpFingerprintKey)
        return made
    }

    func ownInfo(announce: Bool? = nil) -> LocalSendDeviceInfo {
        LocalSendDeviceInfo(alias: deviceName, deviceModel: Self.modelName, deviceType: .desktop,
                            fingerprint: fingerprint ?? Self.httpFingerprint(), port: Int(LocalSendProtocol.port),
                            protocol: AppState.shared.localSendEncrypted && identity != nil ? "https" : "http",
                            // True while files are on offer: LocalSend clients
                            // then show this Mac as one they can pull from.
                            download: offer != nil, announce: announce)
    }

    // MARK: Discovery

    /// "Announcing this Mac on the local network."
    func announce() {
        guard let multicast, let data = try? JSONEncoder().encode(ownInfo(announce: true)) else { return }
        multicast.send(data)
    }

    /// Announce again and refresh the device list; also scans the subnet for
    /// devices whose multicast doesn't get through.
    func refresh() {
        guard receiverState == .running || server == nil else { return }
        peers = []
        announce()
        scanSubnet()
    }

    private func heard(_ data: Data, from host: String) {
        guard let info = try? JSONDecoder().decode(LocalSendDeviceInfo.self, from: data),
              info.fingerprint != fingerprint else { return }
        remember(info, host: host)
        // Answer an announcement so the device lists this Mac too; at most
        // once every few seconds per device.
        guard info.announce == true, AppState.shared.localSendVisible else { return }
        if let last = lastAnswered[info.fingerprint], Date().timeIntervalSince(last) < 3 { return }
        lastAnswered[info.fingerprint] = Date()
        let peer = LocalSendPeer(info: info, host: host, lastSeen: Date())
        let own = ownInfo()
        Task {
            let client = LocalSendClient(expectedFingerprint: nil)
            defer { client.finish() }
            do {
                _ = try await client.register(own, at: peer)
            } catch {
                // Fall back to a multicast answer (announce: false).
                if let data = try? JSONEncoder().encode(ownInfo(announce: false)) { multicast?.send(data) }
            }
        }
    }

    private func remember(_ info: LocalSendDeviceInfo, host: String) {
        guard info.fingerprint != fingerprint else { return }
        var info = info
        info.announce = nil
        let peer = LocalSendPeer(info: info, host: host, lastSeen: Date())
        if let index = peers.firstIndex(where: { $0.id == peer.id }) {
            peers[index] = peer
        } else {
            peers.append(peer)
            peers.sort { $0.info.alias.localizedCaseInsensitiveCompare($1.info.alias) == .orderedAscending }
        }
        // Keep a favorite's name and model current.
        if let index = favorites.firstIndex(where: { $0.fingerprint == info.fingerprint }),
           favorites[index].alias != info.alias {
            favorites[index].alias = info.alias
            saveFavorites()
        }
    }

    private func prunePeers() {
        let cutoff = Date().addingTimeInterval(-180)
        peers.removeAll { $0.lastSeen < cutoff }
    }

    /// "Scanning network": asks every address on this /24 for /register.
    private func scanSubnet() {
        guard !isScanning, let local = LANShareService.localIPv4Address() else { return }
        let parts = local.split(separator: ".")
        guard parts.count == 4 else { return }
        let prefix = parts.prefix(3).joined(separator: ".")
        let hosts = (1...254).map { "\(prefix).\($0)" }.filter { $0 != local }
        let own = ownInfo()
        isScanning = true
        Task {
            await withTaskGroup(of: (LocalSendDeviceInfo, String)?.self) { group in
                // At most 48 probes in flight; each tries HTTPS, then HTTP.
                var next = 0
                var finished = 0
                while next < hosts.count || !group.isEmpty {
                    while next < hosts.count, next < 48 + finished {
                        let host = hosts[next]
                        next += 1
                        group.addTask { await Self.probe(host, own: own) }
                    }
                    guard let result = await group.next() else { break }
                    finished += 1
                    if let (info, host) = result { remember(info, host: host) }
                }
            }
            isScanning = false
        }
    }

    /// Asks one address for /register over HTTPS, then HTTP.
    nonisolated private static func probe(_ host: String, own: LocalSendDeviceInfo) async -> (LocalSendDeviceInfo, String)? {
        for https in [true, false] {
            let probe = LocalSendDeviceInfo(alias: "", deviceModel: nil, deviceType: nil, fingerprint: "",
                                            port: Int(LocalSendProtocol.port), protocol: https ? "https" : "http")
            let peer = LocalSendPeer(info: probe, host: host, lastSeen: Date())
            let client = LocalSendClient(expectedFingerprint: nil, timeout: 1.5)
            defer { client.finish() }
            if var info = try? await client.register(own, at: peer) {
                if info.protocol == nil { info.protocol = https ? "https" : "http" }
                if info.port == nil { info.port = Int(LocalSendProtocol.port) }
                return (info, host)
            }
        }
        return nil
    }

    // MARK: Favorites

    func restoreFavorites() {
        guard let data = UserDefaults.standard.data(forKey: Self.favoritesKey),
              let saved = try? JSONDecoder().decode([LocalSendFavorite].self, from: data) else { return }
        favorites = saved
    }

    func saveFavorites() {
        UserDefaults.standard.set(try? JSONEncoder().encode(favorites), forKey: Self.favoritesKey)
    }

    func isFavorite(_ fingerprint: String) -> Bool { favorites.contains { $0.fingerprint == fingerprint } }

    func toggleFavorite(_ peer: LocalSendPeer) {
        if isFavorite(peer.id) {
            forget(peer.id)
        } else {
            favorites.append(LocalSendFavorite(fingerprint: peer.id, alias: peer.info.alias,
                                               deviceModel: peer.info.deviceModel, deviceType: peer.info.deviceType?.rawValue))
            saveFavorites()
        }
    }

    /// "Forget this device"
    func forget(_ fingerprint: String) {
        favorites.removeAll { $0.fingerprint == fingerprint }
        saveFavorites()
    }

    // MARK: Sending

    /// Holds files for the console's device list ("Send with LocalSend").
    func stage(_ urls: [URL]) {
        let urls = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        staged = urls
        let state = AppState.shared
        if !isEnabled, let index = state.droplets.firstIndex(where: { $0.id == "localSend" }) {
            state.droplets[index].isEnabled = true
        }
        state.open(.widgets)
        state.activeDropletID = "localSend"
        if peers.isEmpty { refresh() }
    }

    func send(to peer: LocalSendPeer, pin: String? = nil) {
        let files = LocalSendFormat.expand(staged)
        guard !files.isEmpty else {
            outgoing = Outgoing(peerName: peer.info.alias, fileCount: 0, totalBytes: 0, sentBytes: 0,
                                phase: .failed(LocalSendError.noFiles.localizedDescription))
            return
        }
        sendTask?.cancel()
        let (infos, sources) = Self.describe(files)
        let total = infos.values.reduce(0) { $0 + $1.size }
        outgoing = Outgoing(peerName: peer.info.alias, fileCount: infos.count, totalBytes: total, sentBytes: 0, phase: .waiting)
        let request = LocalSendPrepareRequest(info: ownInfo(), files: infos)
        DroppyLog.info("LocalSend", "Sending \(infos.count) file(s) to \(peer.info.alias) at \(peer.host)")
        sendTask = Task { await runSend(request, sources: sources, to: peer, pin: pin) }
    }

    /// Turns expanded files into the wire description plus a map back to
    /// where each one lives. Shared by sending and by a browser offer.
    static func describe(_ files: [(url: URL, name: String)]) -> (infos: [String: LocalSendFileInfo], sources: [String: URL]) {
        var infos: [String: LocalSendFileInfo] = [:]
        var sources: [String: URL] = [:]
        for (url, name) in files {
            let id = LocalSendFormat.randomID()
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .contentAccessDateKey])
            infos[id] = LocalSendFileInfo(id: id, fileName: name, size: Int64(values?.fileSize ?? 0),
                                          fileType: LocalSendFormat.mimeType(for: url),
                                          metadata: .init(modified: LocalSendFormat.isoDate(values?.contentModificationDate),
                                                          accessed: LocalSendFormat.isoDate(values?.contentAccessDate)))
            sources[id] = url
        }
        return (infos, sources)
    }

    private func runSend(_ request: LocalSendPrepareRequest, sources: [String: URL], to peer: LocalSendPeer, pin: String?) async {
        let expected = peer.isHTTPS ? peer.info.fingerprint : nil
        let client = LocalSendClient(expectedFingerprint: expected, timeout: 300)
        defer { client.finish() }
        var sessionID: String?
        do {
            let prepared = try await client.prepareUpload(request, to: peer, pin: pin)
            guard let prepared else {
                // 204: nothing to transfer (the receiver already has it all).
                finishSend(.done)
                return
            }
            sessionID = prepared.sessionId
            outgoing?.phase = .sending
            var sentBefore: Int64 = 0
            for (fileID, token) in prepared.files {
                try Task.checkCancellation()
                guard let url = sources[fileID] else { continue }
                let base = sentBefore
                client.onProgress = { sent in
                    Task { @MainActor in LocalSendService.shared.outgoing?.sentBytes = base + sent }
                }
                try await client.upload(url, sessionID: prepared.sessionId, fileID: fileID, token: token, to: peer)
                sentBefore += request.files[fileID]?.size ?? 0
                outgoing?.sentBytes = sentBefore
            }
            finishSend(.done)
            DroppyAudio.playDropSuccess()
            staged = []
        } catch is CancellationError {
            if let sessionID { await client.cancel(sessionID: sessionID, at: peer) }
            finishSend(.cancelled)
        } catch LocalSendError.status(401) {
            outgoing = nil
            if let entered = askPIN(for: peer.info.alias, retry: pin != nil) {
                send(to: peer, pin: entered)
            } else {
                finishSend(.failed(LocalSendFormat.senderError(status: 401)))
            }
        } catch {
            if let sessionID { await client.cancel(sessionID: sessionID, at: peer) }
            let message = (error as? LocalizedError)?.errorDescription ?? Self.describe(error)
            DroppyLog.error("LocalSend", "Send failed: \(message)")
            finishSend(.failed(message))
        }
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut: return "The receiver didn't answer in time."
            case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost:
                return LocalSendError.unreachable.localizedDescription
            case NSURLErrorNotConnectedToInternet: return "Same network, no internet? This Mac isn't on a network right now."
            case NSURLErrorCancelled: return LocalSendError.fingerprintMismatch.localizedDescription
            default: break
            }
        }
        return error.localizedDescription
    }

    private func finishSend(_ phase: Outgoing.Phase) {
        outgoing?.phase = phase
        sendTask = nil
    }

    func cancelSend() {
        sendTask?.cancel()
    }

    func clearOutgoing() {
        if case .sending = outgoing?.phase { return }
        if case .waiting = outgoing?.phase { return }
        outgoing = nil
    }

    private func askPIN(for alias: String, retry: Bool) -> String? {
        let alert = NSAlert()
        alert.messageText = "This device asks for a PIN"
        alert.informativeText = retry ? "That PIN wasn't right. Type the PIN shown in LocalSend on \(alias)."
                                      : "Type the PIN set in LocalSend on \(alias)."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        AppState.shared.setModal(true, owner: "localSend.service")
        defer { AppState.shared.setModal(false, owner: "localSend.service") }
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let pin = field.stringValue.trimmingCharacters(in: .whitespaces)
        return pin.isEmpty ? nil : pin
    }

    // MARK: Receiving

    nonisolated func route(_ request: LocalSendHTTPServer.Request) async -> LocalSendHTTPServer.Reply {
        guard let route = LocalSendFormat.route(of: request.target) else {
            return await browserReply(for: request)
        }
        switch (request.method, route.version, route.name) {
        case ("POST", 2, "register"):
            return .readBody(limit: 64 * 1024) { data in
                await LocalSendService.shared.handleRegister(data, host: request.remoteHost)
            }
        case ("GET", _, "info"):
            return .respond(.json(await ownInfo()))
        // v1 called it send-request, and answered with the tokens alone.
        case ("POST", 2, "prepare-upload"), ("POST", 1, "send-request"):
            return .readBody(limit: 8 * 1024 * 1024) { data in
                await LocalSendService.shared.handlePrepare(data, request: request, version: route.version)
            }
        case ("POST", 2, "upload"), ("POST", 1, "send"):
            return await uploadReply(for: request, version: route.version)
        case ("POST", _, "cancel"):
            return .respond(await handleCancel(request))
        // Browser and app downloads: what is on offer, then the bytes.
        case ("POST", 2, "prepare-download"), ("GET", 2, "prepare-download"):
            return .respond(await handlePrepareDownload(request))
        case ("GET", 2, "download"):
            return await downloadReply(for: request)
        default:
            return .respond(.status(request.method == "GET" || request.method == "POST" ? 404 : 405))
        }
    }

    private func handleRegister(_ data: Data, host: String) -> LocalSendHTTPServer.Response {
        guard let info = try? JSONDecoder().decode(LocalSendDeviceInfo.self, from: data) else {
            return .status(400, "Invalid body")
        }
        remember(info, host: host)
        return .json(ownInfo())
    }

    private func handlePrepare(_ data: Data, request: LocalSendHTTPServer.Request,
                               version: Int) async -> LocalSendHTTPServer.Response {
        let state = AppState.shared
        guard let prepare = try? JSONDecoder().decode(LocalSendPrepareRequest.self, from: data), !prepare.files.isEmpty else {
            return .status(400, "Invalid body")
        }
        var sender = prepare.info
        // v1 senders identify themselves by address alone; give them a stable
        // stand-in so favorites and the device list still work.
        if sender.fingerprint.isEmpty { sender.fingerprint = "v1:\(request.remoteHost)" }
        let favorite = isFavorite(sender.fingerprint)
        switch state.localSendReceiveMode {
        case .off: return .status(403, "Receiving is turned off")
        case .favorites where !favorite: return .status(403, "Only favorites can send to this device")
        default: break
        }
        let pin = state.localSendPIN.trimmingCharacters(in: .whitespaces)
        if !pin.isEmpty {
            pinFailures.removeAll { Date().timeIntervalSince($0) > 60 }
            if pinFailures.count >= 5 { return .status(429, "Too many attempts") }
            guard LocalSendFormat.query(of: request.target)["pin"] == pin else {
                if LocalSendFormat.query(of: request.target)["pin"] != nil { pinFailures.append(Date()) }
                return .status(401, "PIN required")
            }
        }
        guard session == nil, incoming == nil else { return .status(409, "Blocked by another session") }
        remember(sender, host: request.remoteHost)

        let files = prepare.files.values.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
        let isMessage = files.allSatisfy(\.isTextMessage)
        let prompt = IncomingRequest(sender: sender, host: request.remoteHost, files: files,
                                     message: isMessage ? files.compactMap(\.preview).joined(separator: "\n\n") : nil)
        DroppyLog.info("LocalSend", "Incoming request from \(sender.alias) (\(files.count) file(s))")

        let accepted: Bool
        if favorite && state.localSendQuickSaveFavorites && !isMessage {
            accepted = true
        } else {
            incoming = prompt
            LocalSendPromptController.shared.show()
            DroppyAudio.playTick()
            accepted = await withCheckedContinuation { continuation in
                decision = continuation
                DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                    guard let self, self.incoming?.id == prompt.id else { return }
                    self.decide(false)
                }
            }
        }
        guard accepted else { return .status(403, "Declined") }
        if let message = prompt.message {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message, forType: .string)
            state.showNotification(appName: "LocalSend", title: "Message from \(sender.alias) copied",
                                   message: String(message.prefix(140)), icon: "text.bubble.fill")
            return .status(204)
        }
        guard session == nil else { return .status(409, "Blocked by another session") }
        let folder = saveFolder
        let newSession = ReceiveSession(sender: sender, host: request.remoteHost, files: prepare.files, folder: folder)
        do {
            try FileManager.default.createDirectory(at: newSession.partsFolder, withIntermediateDirectories: true)
        } catch {
            return .status(500, "Could not write to the save folder")
        }
        session = newSession
        receiving = Receiving(senderName: sender.alias, fileCount: prepare.files.count, doneCount: 0,
                              totalBytes: prepare.files.values.reduce(0) { $0 + $1.size }, receivedBytes: 0)
        startSessionTimer()
        // v1 answers with the tokens alone; v2 wraps them with the session id.
        return version == 1 ? .json(newSession.tokens)
                            : .json(LocalSendPrepareResponse(sessionId: newSession.id, files: newSession.tokens))
    }

    /// Accept or decline the prompt.
    func decide(_ accept: Bool) {
        incoming = nil
        LocalSendPromptController.shared.close()
        decision?.resume(returning: accept)
        decision = nil
    }

    var saveFolder: URL {
        let path = AppState.shared.localSendSaveFolder
        if !path.isEmpty { return URL(fileURLWithPath: path, isDirectory: true) }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }

    private func uploadReply(for request: LocalSendHTTPServer.Request, version: Int) -> LocalSendHTTPServer.Reply {
        let query = LocalSendFormat.query(of: request.target)
        guard let fileID = query["fileId"], let token = query["token"] else {
            return .respond(.status(400, "Missing parameters"))
        }
        // v1 has no session id: the one open session is the session.
        guard let sessionID = version == 1 ? session?.id : query["sessionId"] else {
            return .respond(.status(version == 1 ? 409 : 400, version == 1 ? "No transfer is open" : "Missing parameters"))
        }
        guard let session, session.id == sessionID else { return .respond(.status(409, "Blocked by another session")) }
        guard session.tokens[fileID] == token, session.host == request.remoteHost else {
            return .respond(.status(403, "Invalid token or IP address"))
        }
        guard !session.done.contains(fileID) else { return .respond(.status(409, "File already transferred")) }
        let part = session.partsFolder.appendingPathComponent(fileID + ".part")
        let counter = session.counter(for: fileID)
        session.lastActivity = Date()
        return .streamBody(to: part, then: { result in
            await LocalSendService.shared.finishFile(fileID, sessionID: sessionID, part: part, result: result)
        }, progress: { counter.set($0) })
    }

    private func finishFile(_ fileID: String, sessionID: String, part: URL,
                            result: Result<Int64, LocalSendHTTPServer.BodyError>) -> LocalSendHTTPServer.Response {
        guard let session, session.id == sessionID else {
            try? FileManager.default.removeItem(at: part)
            return .status(409, "Blocked by another session")
        }
        session.lastActivity = Date()
        guard case .success = result, let info = session.files[fileID] else {
            endSession(session, error: "The sender stopped responding")
            return .status(500, "Transfer interrupted")
        }
        let relative = LocalSendFormat.safeRelativePath(info.fileName) ?? "Received file"
        var destination = session.folder.appendingPathComponent(relative)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            destination = FileOperations.uniqueDestination(for: destination, in: destination.deletingLastPathComponent())
            try fm.moveItem(at: part, to: destination)
            if let modified = info.metadata?.modified.flatMap({ ISO8601DateFormatter().date(from: $0) }) {
                try? fm.setAttributes([.modificationDate: modified], ofItemAtPath: destination.path)
            }
        } catch {
            endSession(session, error: "Couldn't save \(info.fileName): \(error.localizedDescription)")
            return .status(500, "Could not save the file")
        }
        session.done.insert(fileID)
        session.saved.append(destination)
        // What goes to the shelf: each top-level file or folder once.
        let top = relative.split(separator: "/").first.map(String.init) ?? relative
        let topURL = relative.contains("/") ? session.folder.appendingPathComponent(top) : destination
        if !session.topLevel.contains(topURL) { session.topLevel.append(topURL) }
        receiving?.doneCount = session.done.count
        if session.done.count == session.files.count { completeSession(session) }
        return .status(200)
    }

    private func handleCancel(_ request: LocalSendHTTPServer.Request) -> LocalSendHTTPServer.Response {
        let query = LocalSendFormat.query(of: request.target)
        if let session, session.host == request.remoteHost, query["sessionId"] == nil || query["sessionId"] == session.id {
            endSession(session, error: "The sender cancelled the transfer")
        } else if let incoming, incoming.host == request.remoteHost {
            decide(false)
        }
        return .status(200)
    }

    private func startSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor in LocalSendService.shared.tickSession() }
        }
    }

    private func tickSession() {
        guard let session else { sessionTimer?.invalidate(); sessionTimer = nil; return }
        let bytes = session.receivedBytes
        if bytes != session.lastBytes {
            session.lastBytes = bytes
            session.lastActivity = Date()
        }
        receiving?.receivedBytes = bytes
        if let receiving {
            LiveActivityCenter.shared.post(LiveActivity(
                id: "localSend", icon: "dot.radiowaves.left.and.right", tint: Color(red: 0.0, green: 0.55, blue: 0.53),
                trailing: .progress(receiving.progress), priority: .ambient,
                label: "Receiving from \(receiving.senderName)"))
        }
        // No bytes for two minutes: the sender went away.
        if Date().timeIntervalSince(session.lastActivity) > 120 {
            endSession(session, error: "The sender stopped responding")
        }
    }

    private func completeSession(_ session: ReceiveSession) {
        let saved = session.saved
        let top = session.topLevel
        let sender = session.sender.alias
        cleanUp(session)
        lastReceived = saved
        DroppyLog.info("LocalSend", "Received \(saved.count) file(s) from \(sender)")
        let state = AppState.shared
        if state.localSendAddToShelf {
            state.addShelfItems(top.map { ShelfItem(url: $0) })
        }
        DroppyAudio.playDropSuccess()
        state.showNotification(appName: "LocalSend",
                               title: "Received \(saved.count) file\(saved.count == 1 ? "" : "s")",
                               message: "From \(sender) · saved to \(session.folder.lastPathComponent)",
                               icon: "arrow.down.circle.fill", actionTitle: "Show",
                               action: { NSWorkspace.shared.activateFileViewerSelecting(top) })
    }

    private func endSession(_ session: ReceiveSession, error: String) {
        cleanUp(session)
        DroppyLog.error("LocalSend", "Receive ended: \(error)")
        AppState.shared.showNotification(appName: "LocalSend", title: "Transfer stopped", message: error,
                                         icon: "exclamationmark.triangle.fill")
    }

    private func cleanUp(_ session: ReceiveSession) {
        try? FileManager.default.removeItem(at: session.partsFolder)
        if self.session === session { self.session = nil }
        receiving = nil
        sessionTimer?.invalidate()
        sessionTimer = nil
        LiveActivityCenter.shared.end("localSend")
    }
}

/// One accepted incoming transfer.
@MainActor
final class ReceiveSession {
    let id = LocalSendFormat.randomID()
    let sender: LocalSendDeviceInfo
    let host: String
    let files: [String: LocalSendFileInfo]
    let tokens: [String: String]
    let folder: URL
    var done = Set<String>()
    var saved: [URL] = []
    var topLevel: [URL] = []
    var lastActivity = Date()
    var lastBytes: Int64 = 0
    private var counters: [String: ByteCounter] = [:]

    init(sender: LocalSendDeviceInfo, host: String, files: [String: LocalSendFileInfo], folder: URL) {
        self.sender = sender
        self.host = host
        self.files = files
        self.folder = folder
        tokens = Dictionary(uniqueKeysWithValues: files.keys.map { ($0, LocalSendFormat.randomID()) })
    }

    /// Hidden, beside the destination, so finished files move without copying.
    var partsFolder: URL { folder.appendingPathComponent(".tama-localsend-\(id)", isDirectory: true) }

    func counter(for fileID: String) -> ByteCounter {
        if let counter = counters[fileID] { return counter }
        let counter = ByteCounter()
        counters[fileID] = counter
        return counter
    }

    var receivedBytes: Int64 {
        files.reduce(0) { total, entry in
            total + (done.contains(entry.key) ? entry.value.size : (counters[entry.key]?.value ?? 0))
        }
    }
}

/// Bytes written so far, updated from the network queue.
final class ByteCounter: @unchecked Sendable {
    private var bytes: Int64 = 0
    private let lock = NSLock()
    func set(_ value: Int64) { lock.lock(); bytes = value; lock.unlock() }
    var value: Int64 { lock.lock(); defer { lock.unlock() }; return bytes }
}

// MARK: - Client

/// Talks to another device's LocalSend API. Self-signed certificates are
/// accepted when their SHA-256 matches the fingerprint the device announced.
final class LocalSendClient: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let expectedFingerprint: String?
    private let timeout: TimeInterval
    var onProgress: (@Sendable (Int64) -> Void)?
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = 24 * 3600
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    init(expectedFingerprint: String?, timeout: TimeInterval = 10) {
        self.expectedFingerprint = expectedFingerprint
        self.timeout = timeout
    }

    /// Releases the session (it holds this delegate strongly). Call when done.
    func finish() { session.finishTasksAndInvalidate() }

    func register(_ own: LocalSendDeviceInfo, at peer: LocalSendPeer) async throws -> LocalSendDeviceInfo {
        let (data, status) = try await post("register", to: peer, body: try JSONEncoder().encode(own))
        guard status == 200 else { throw LocalSendError.status(status) }
        guard let info = try? JSONDecoder().decode(LocalSendDeviceInfo.self, from: data) else { throw LocalSendError.invalidResponse }
        return info
    }

    /// nil = 204, nothing to send.
    func prepareUpload(_ request: LocalSendPrepareRequest, to peer: LocalSendPeer, pin: String?) async throws -> LocalSendPrepareResponse? {
        var query: [URLQueryItem] = []
        if let pin { query.append(URLQueryItem(name: "pin", value: pin)) }
        let (data, status) = try await post("prepare-upload", to: peer, query: query, body: try JSONEncoder().encode(request))
        switch status {
        case 200:
            guard let response = try? JSONDecoder().decode(LocalSendPrepareResponse.self, from: data) else {
                throw LocalSendError.invalidResponse
            }
            return response
        case 204: return nil
        default: throw LocalSendError.status(status)
        }
    }

    func upload(_ file: URL, sessionID: String, fileID: String, token: String, to peer: LocalSendPeer) async throws {
        guard var request = makeRequest("upload", peer: peer, query: [
            URLQueryItem(name: "sessionId", value: sessionID),
            URLQueryItem(name: "fileId", value: fileID),
            URLQueryItem(name: "token", value: token),
        ]) else { throw LocalSendError.invalidResponse }
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.upload(for: request, fromFile: file)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw LocalSendError.status(status) }
    }

    func cancel(sessionID: String, at peer: LocalSendPeer) async {
        _ = try? await post("cancel", to: peer, query: [URLQueryItem(name: "sessionId", value: sessionID)], body: Data())
    }

    private func makeRequest(_ route: String, peer: LocalSendPeer, query: [URLQueryItem] = []) -> URLRequest? {
        guard let base = peer.baseURL,
              var components = URLComponents(url: base.appendingPathComponent(LocalSendProtocol.apiPrefix + route), resolvingAgainstBaseURL: false)
        else { return nil }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        return request
    }

    private func post(_ route: String, to peer: LocalSendPeer, query: [URLQueryItem] = [], body: Data) async throws -> (Data, Int) {
        guard var request = makeRequest(route, peer: peer, query: query) else { throw LocalSendError.invalidResponse }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // LocalSend devices use self-signed certificates; pin to the
        // announced fingerprint when it's a certificate hash.
        if let expected = expectedFingerprint?.lowercased(), expected.count == 64, expected.allSatisfy(\.isHexDigit) {
            guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first,
                  LocalSendTLS.fingerprint(ofCertificate: SecCertificateCopyData(leaf) as Data) == expected else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        onProgress?(totalBytesSent)
    }
}
