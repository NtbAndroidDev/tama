import Foundation
import Network

/// A small HTTP/1.1 server for the LocalSend API, over TLS or plain TCP.
/// One request per connection ("Connection: close"): LocalSend opens a new
/// request per call. Request bodies are read into memory for JSON calls and
/// streamed straight to disk for uploads.
final class LocalSendHTTPServer: @unchecked Sendable {
    struct Request: Sendable {
        let method: String
        let target: String
        let headers: [String: String]
        /// The peer's IP address, for binding an upload session to its sender.
        let remoteHost: String
    }

    struct Response: Sendable {
        var status: Int
        var body: Data = Data()
        var contentType = "application/json"
        /// Anything beyond the status, length and type (Content-Disposition,
        /// Cache-Control); written verbatim.
        var headers: [String: String] = [:]

        static func json<T: Encodable>(_ value: T) -> Response {
            Response(status: 200, body: (try? JSONEncoder().encode(value)) ?? Data())
        }
        static func status(_ code: Int, _ message: String? = nil) -> Response {
            let body = message.map { (try? JSONSerialization.data(withJSONObject: ["message": $0])) ?? Data() } ?? Data()
            return Response(status: code, body: body)
        }
    }

    enum BodyError: Error { case disconnected, tooLarge, malformed, writeFailed }

    enum Reply: Sendable {
        case respond(Response)
        /// Read the body (up to `limit` bytes) into memory, then answer.
        case readBody(limit: Int, then: @Sendable (Data) async -> Response)
        /// Write the body to `file`, then answer. The handler also hears about
        /// a sender that disconnected mid-way.
        case streamBody(to: URL, then: @Sendable (Result<Int64, BodyError>) async -> Response,
                        progress: @Sendable (Int64) -> Void)
        /// Answer with a file from disk, read and sent a chunk at a time, so a
        /// browser downloading a large video never has it all in memory.
        case sendFile(URL, contentType: String, fileName: String?,
                      progress: @Sendable (Int64) -> Void = { _ in },
                      finished: @Sendable (Bool) -> Void = { _ in })
    }

    typealias Router = @Sendable (Request) async -> Reply

    private let queue = DispatchQueue(label: "app.tama.localsend.http")
    private var listener: NWListener?
    private let router: Router

    init(router: @escaping Router) {
        self.router = router
    }

    /// RFC 6266: a plain name for old clients, UTF-8 for everyone else. Also
    /// keeps a file name from breaking out of the header it sits in.
    static func disposition(for fileName: String) -> String {
        let ascii = String(fileName.unicodeScalars.map {
            $0.isASCII && $0 != "\"" && $0 != "\\" && $0.value >= 0x20 ? Character($0) : "_"
        })
        let escaped = fileName.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ascii
        return "attachment; filename=\"\(ascii)\"; filename*=UTF-8''\(escaped)"
    }

    /// Starts listening; resolves once the port is open (or failed).
    func start(port: UInt16, identity: LocalSendTLS.Identity?) async throws {
        let parameters: NWParameters
        if let identity, let secIdentity = sec_identity_create(identity.identity) {
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)
            sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
            parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        } else {
            parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        }
        parameters.allowLocalEndpointReuse = true
        let listener = port == 0 ? try NWListener(using: parameters)
                                 : try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port) ?? .any)
        let router = self.router
        let queue = self.queue
        listener.newConnectionHandler = { connection in
            HTTPConnection(connection: connection, router: router, queue: queue).start()
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let once = OnceFlag()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.claim() { cont.resume() }
                case let .failed(error), let .waiting(error):
                    if once.claim() {
                        listener.cancel()
                        if case let .posix(code) = error, code == .EADDRINUSE {
                            cont.resume(throwing: LocalSendError.portInUse)
                        } else {
                            cont.resume(throwing: LocalSendError.receiver(error.localizedDescription))
                        }
                    }
                case .cancelled:
                    if once.claim() { cont.resume(throwing: CancellationError()) }
                default: break
                }
            }
            listener.start(queue: queue)
        }
        self.listener = listener
    }

    /// The port it listens on (tests start it on any free port).
    var port: UInt16? { listener?.port?.rawValue }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}

final class OnceFlag: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// One request and its answer.
private final class HTTPConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let router: LocalSendHTTPServer.Router
    private let queue: DispatchQueue
    private var buffer = Data()

    init(connection: NWConnection, router: @escaping LocalSendHTTPServer.Router, queue: DispatchQueue) {
        self.connection = connection
        self.router = router
        self.queue = queue
    }

    func start() {
        connection.start(queue: queue)
        readHead()
    }

    private var remoteHost: String {
        if case let .hostPort(host, _) = connection.endpoint {
            switch host {
            case let .ipv4(address): return "\(address)".components(separatedBy: "%").first ?? "\(address)"
            case let .ipv6(address):
                let text = "\(address)".components(separatedBy: "%").first ?? "\(address)"
                return text.hasPrefix("::ffff:") ? String(text.dropFirst(7)) : text
            case let .name(name, _): return name
            @unknown default: return ""
            }
        }
        return ""
    }

    private func readHead() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [self] data, _, isComplete, error in
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                let rest = Data(buffer[end.upperBound...])
                buffer = Data()
                handle(head: head, leftover: rest)
            } else if isComplete || error != nil || buffer.count > 32 * 1024 {
                connection.cancel()
            } else {
                readHead()
            }
        }
    }

    private func handle(head: String, leftover: Data) {
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return send(.status(400)) }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased().trimmingCharacters(in: .whitespaces)] =
                line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let request = LocalSendHTTPServer.Request(method: String(parts[0]).uppercased(), target: String(parts[1]),
                                                  headers: headers, remoteHost: remoteHost)
        let router = self.router
        Task {
            let reply = await router(request)
            self.queue.async { self.run(reply, request: request, leftover: leftover) }
        }
    }

    private func run(_ reply: LocalSendHTTPServer.Reply, request: LocalSendHTTPServer.Request, leftover: Data) {
        let body = BodyReader(headers: request.headers)
        switch reply {
        case let .respond(response):
            send(response)
        case let .readBody(limit, then):
            var collected = Data()
            read(body, leftover: leftover, sink: { chunk in
                collected.append(chunk)
                return collected.count <= limit
            }, done: { [self] result in
                switch result {
                case .success:
                    let data = collected
                    Task { let response = await then(data); self.queue.async { self.send(response) } }
                case .failure(.tooLarge): send(.status(413))
                case .failure: connection.cancel()
                }
            })
        case let .sendFile(url, contentType, fileName, progress, finished):
            sendFile(url, contentType: contentType, fileName: fileName, progress: progress, finished: finished)
        case let .streamBody(file, then, progress):
            FileManager.default.createFile(atPath: file.path, contents: nil)
            guard let handle = try? FileHandle(forWritingTo: file) else {
                Task { _ = await then(.failure(.writeFailed)) }
                return send(.status(500, "Could not write the file"))
            }
            var written: Int64 = 0
            read(body, leftover: leftover, sink: { chunk in
                guard (try? handle.write(contentsOf: chunk)) != nil else { return false }
                written += Int64(chunk.count)
                progress(written)
                return true
            }, done: { [self] result in
                try? handle.close()
                let outcome: Result<Int64, LocalSendHTTPServer.BodyError>
                switch result {
                case .success: outcome = .success(written)
                case .failure(.tooLarge): outcome = .failure(.writeFailed)
                case let .failure(error): outcome = .failure(error)
                }
                Task {
                    let response = await then(outcome)
                    self.queue.async { self.send(response) }
                }
            })
        }
    }

    /// Feeds the body to `sink` chunk by chunk until the reader says it's
    /// complete. `sink` returning false stops with `.tooLarge`.
    private func read(_ reader: BodyReader, leftover: Data,
                      sink: @escaping (Data) -> Bool,
                      done: @escaping (Result<Void, LocalSendHTTPServer.BodyError>) -> Void) {
        BodyPump(connection: connection, reader: reader, sink: sink, done: done).run(leftover: leftover)
    }

    private func send(_ response: LocalSendHTTPServer.Response) {
        let reason = HTTPURLResponse.localizedString(forStatusCode: response.status).capitalized
        var head = "HTTP/1.1 \(response.status) \(reason)\r\n"
        head += "Content-Length: \(response.body.count)\r\n"
        if !response.body.isEmpty { head += "Content-Type: \(response.contentType)\r\n" }
        for (name, value) in response.headers.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        head += "Connection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + response.body, isComplete: true, completion: .contentProcessed { [self] _ in
            connection.cancel()
        })
    }

    /// Streams a file as the answer. `FileSender` owns the handle and the
    /// running total; everything it does happens on the connection's queue.
    private func sendFile(_ url: URL, contentType: String, fileName: String?,
                          progress: @escaping @Sendable (Int64) -> Void,
                          finished: @escaping @Sendable (Bool) -> Void) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64
        guard let size, let handle = try? FileHandle(forReadingFrom: url) else {
            finished(false)
            return send(.status(404, "The file is no longer there"))
        }
        var head = "HTTP/1.1 200 OK\r\n"
        head += "Content-Length: \(size)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        if let fileName { head += "Content-Disposition: \(LocalSendHTTPServer.disposition(for: fileName))\r\n" }
        head += "Connection: close\r\n\r\n"
        FileSender(connection: connection, handle: handle, size: size,
                   progress: progress, finished: finished).start(head: Data(head.utf8))
    }

}

/// Pushes a file down one connection, queueing the next chunk only once the
/// last is on the wire, so a slow client can't make Tama buffer the file.
private final class FileSender: @unchecked Sendable {
    private let connection: NWConnection
    private let handle: FileHandle
    private let size: Int64
    private let progress: @Sendable (Int64) -> Void
    private let finished: @Sendable (Bool) -> Void
    private var sent: Int64 = 0

    init(connection: NWConnection, handle: FileHandle, size: Int64,
         progress: @escaping @Sendable (Int64) -> Void, finished: @escaping @Sendable (Bool) -> Void) {
        self.connection = connection
        self.handle = handle
        self.size = size
        self.progress = progress
        self.finished = finished
    }

    func start(head: Data) { pump(head) }

    private func stop(complete: Bool) {
        try? handle.close()
        finished(complete)
        connection.cancel()
    }

    private func pump(_ payload: Data?) {
        connection.send(content: payload, isComplete: payload == nil, completion: .contentProcessed { [self] error in
            guard error == nil else { return stop(complete: false) }
            guard payload != nil else { return stop(complete: sent == size) }
            let next = (try? handle.read(upToCount: 256 * 1024)) ?? Data()
            guard !next.isEmpty else { return pump(nil) }
            sent += Int64(next.count)
            progress(sent)
            pump(next)
        })
    }
}

/// Reads a request body framed by Content-Length or chunked encoding.
struct BodyReader {
    enum Step: Equatable {
        case more(Data)
        case finished(Data)
        case malformed
    }

    private enum Mode { case length(Int64), chunked, none }
    private var mode: Mode
    private var remaining: Int64 = 0
    private var chunked = ChunkedDecoder()

    init(headers: [String: String]) {
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            mode = .chunked
        } else if let length = headers["content-length"].flatMap({ Int64($0) }) {
            mode = .length(length)
            remaining = length
        } else {
            mode = .none
        }
    }

    mutating func feed(_ data: Data) -> Step {
        switch mode {
        case .none:
            return .finished(Data())
        case .length:
            let take = Int(min(Int64(data.count), remaining))
            remaining -= Int64(take)
            let output = data.prefix(take)
            return remaining == 0 ? .finished(Data(output)) : .more(Data(output))
        case .chunked:
            return chunked.feed(data)
        }
    }
}

/// Decodes `Transfer-Encoding: chunked`, fed in arbitrary pieces.
struct ChunkedDecoder {
    private enum State { case size, data(Int), dataEnd, trailer, done }
    private var state = State.size
    private var line = Data()

    mutating func feed(_ input: Data) -> BodyReader.Step {
        var output = Data()
        var index = input.startIndex
        while index < input.endIndex {
            switch state {
            case .size, .dataEnd, .trailer:
                let byte = input[index]
                index += 1
                guard byte == 0x0A else {
                    if byte != 0x0D { line.append(byte) }
                    if line.count > 1024 { return .malformed }
                    continue
                }
                let text = String(decoding: line, as: UTF8.self)
                line = Data()
                switch state {
                case .size:
                    let hex = text.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                    guard let size = Int(hex, radix: 16), size >= 0 else { return .malformed }
                    state = size == 0 ? .trailer : .data(size)
                case .dataEnd:
                    guard text.isEmpty else { return .malformed }
                    state = .size
                case .trailer:
                    if text.isEmpty { state = .done; return .finished(output) }
                default: break
                }
            case let .data(left):
                let take = min(left, input.endIndex - index)
                output.append(input[index..<(index + take)])
                index += take
                state = left - take == 0 ? .dataEnd : .data(left - take)
            case .done:
                return .finished(output)
            }
        }
        if case .done = state { return .finished(output) }
        return .more(output)
    }
}

/// Pulls a body off the connection into a sink. Runs on the server's queue.
private final class BodyPump: @unchecked Sendable {
    private let connection: NWConnection
    private var reader: BodyReader
    private let sink: (Data) -> Bool
    private let done: (Result<Void, LocalSendHTTPServer.BodyError>) -> Void

    init(connection: NWConnection, reader: BodyReader, sink: @escaping (Data) -> Bool,
         done: @escaping (Result<Void, LocalSendHTTPServer.BodyError>) -> Void) {
        self.connection = connection
        self.reader = reader
        self.sink = sink
        self.done = done
    }

    func run(leftover: Data) {
        switch feed(leftover) {
        case .some(true), nil: return
        case .some(false): next()
        }
    }

    /// true = finished, false = wants more, nil = stopped with an error.
    private func feed(_ data: Data) -> Bool? {
        switch reader.feed(data) {
        case let .more(output):
            if !output.isEmpty, !sink(output) { done(.failure(.tooLarge)); return nil }
            return false
        case let .finished(output):
            if !output.isEmpty, !sink(output) { done(.failure(.tooLarge)); return nil }
            done(.success(()))
            return true
        case .malformed:
            done(.failure(.malformed))
            return nil
        }
    }

    private func next() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                guard let finished = feed(data) else { return }
                if finished { return }
            }
            if error != nil || isComplete {
                done(.failure(.disconnected))
                return
            }
            next()
        }
    }
}
