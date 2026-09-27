import Foundation
import Testing
@testable import Droppy

/// "Share in a browser": the page a browser gets, and the streamed file
/// response the download links point at.
@Suite struct LocalSendSharePageTests {
    @Test func escapesTextThatWouldOtherwiseBeMarkup() {
        let escaped = LocalSendService.escape("a<b>&\"c\"'d")
        #expect(escaped == "a&lt;b&gt;&amp;&quot;c&quot;&#39;d")
        #expect(!escaped.contains("<"))
    }

    @Test func pageCarriesItsTitleAndBody() {
        let page = LocalSendService.page(title: "MacBook", body: "<ul class=\"files\"></ul>")
        #expect(page.hasPrefix("<!DOCTYPE html>"))
        #expect(page.contains("<title>MacBook</title>"))
        #expect(page.contains("<ul class=\"files\"></ul>"))
        // It has to read on a phone and follow the browser's own theme.
        #expect(page.contains("width=device-width"))
        #expect(page.contains("prefers-color-scheme: dark"))
        // Self-contained: nothing to fetch, so it works with no internet.
        #expect(!page.contains("<script"))
        #expect(!page.contains("http://"))
    }

    /// A downloaded file keeps its name, including one a header can't spell.
    @Test func dispositionQuotesAndEscapesTheName() throws {
        let plain = LocalSendHTTPServer.disposition(for: "report.pdf")
        #expect(plain.contains("filename=\"report.pdf\""))
        #expect(plain.contains("filename*=UTF-8''"))
        // A name with quotes, newlines or non-ASCII can't break out of the
        // header: the quoted form is scrubbed, the real name rides in UTF-8.
        let awkward = LocalSendHTTPServer.disposition(for: "sơ \"đồ\"\r\nv2.pdf")
        let quoted = try #require(awkward.split(separator: "\"").dropFirst().first)
        #expect(!quoted.contains("\""))
        #expect(quoted == "s_ ______v2.pdf")
        #expect(awkward.contains("filename*=UTF-8''"))
        #expect(!awkward.contains("\r") && !awkward.contains("\n"))
    }
}

@Suite struct LocalSendFileResponseTests {
    /// The bytes come back whole, with the right length, name and type —
    /// read from disk a chunk at a time rather than held in memory.
    @Test func sendFileStreamsTheWholeFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("droppy-dl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // Bigger than one 256 KB chunk, so more than one pass is exercised.
        let payload = Data((0..<(700 * 1024)).map { UInt8($0 % 251) })
        let file = folder.appendingPathComponent("clip.bin")
        try payload.write(to: file)

        let server = LocalSendHTTPServer { request in
            guard LocalSendFormat.route(of: request.target)?.name == "download" else { return .respond(.status(404)) }
            return .sendFile(file, contentType: "application/octet-stream", fileName: "clip.bin")
        }
        try await server.start(port: 0, identity: nil)
        defer { server.stop() }
        let port = try #require(server.port)

        let url = URL(string: "http://127.0.0.1:\(port)/api/localsend/v2/download?fileId=1")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(data == payload)
        #expect(http.value(forHTTPHeaderField: "Content-Length") == "\(payload.count)")
        #expect(http.value(forHTTPHeaderField: "Content-Disposition")?.contains("clip.bin") == true)
    }

    @Test func sendFileAnswers404WhenItHasGone() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("droppy-gone-\(UUID().uuidString)")
        let server = LocalSendHTTPServer { _ in
            .sendFile(missing, contentType: "text/plain", fileName: "gone.txt")
        }
        try await server.start(port: 0, identity: nil)
        defer { server.stop() }
        let port = try #require(server.port)
        let (_, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/x")!)
        #expect((response as? HTTPURLResponse)?.statusCode == 404)
    }

    /// Extra headers reach the client verbatim.
    @Test func responseHeadersAreWritten() async throws {
        let server = LocalSendHTTPServer { _ in
            .respond(.init(status: 200, body: Data("hi".utf8), contentType: "text/html; charset=utf-8",
                           headers: ["Cache-Control": "no-store"]))
        }
        try await server.start(port: 0, identity: nil)
        defer { server.stop() }
        let port = try #require(server.port)
        let (_, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/")!)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.value(forHTTPHeaderField: "Cache-Control") == "no-store")
        #expect(http.value(forHTTPHeaderField: "Content-Type") == "text/html; charset=utf-8")
    }
}

@Suite struct LocalSendV1Tests {
    /// v1 senders don't send a fingerprint; the body still has to decode so
    /// the receiver can stand one in from the sender's address.
    @Test func v1InfoWithoutAFingerprintStillDecodes() throws {
        let json = #"{"info":{"alias":"Old Phone","deviceModel":"Pixel","deviceType":"mobile"},"files":{"a":{"id":"a","fileName":"x.txt","size":3,"fileType":"text/plain"}}}"#
        let request = try JSONDecoder().decode(LocalSendPrepareRequest.self, from: Data(json.utf8))
        #expect(request.info.alias == "Old Phone")
        #expect(request.info.fingerprint.isEmpty)
        #expect(request.files["a"]?.fileName == "x.txt")
    }

    /// v2 bodies are unaffected.
    @Test func v2InfoKeepsItsFingerprint() throws {
        let json = #"{"info":{"alias":"Pixel","fingerprint":"abc"},"files":{}}"#
        let request = try JSONDecoder().decode(LocalSendPrepareRequest.self, from: Data(json.utf8))
        #expect(request.info.fingerprint == "abc")
    }

    /// v1 answers send-request with the tokens alone; v2 wraps them.
    @Test func theTwoPrepareRepliesHaveDifferentShapes() throws {
        let tokens = ["a": "tok"]
        let v1 = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tokens)) as? [String: Any]
        #expect(v1?["a"] as? String == "tok")
        #expect(v1?["files"] == nil)
        let v2 = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(LocalSendPrepareResponse(sessionId: "s", files: tokens))) as? [String: Any]
        #expect(v2?["sessionId"] as? String == "s")
        #expect((v2?["files"] as? [String: Any])?["a"] as? String == "tok")
    }
}
