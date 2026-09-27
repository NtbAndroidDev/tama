import Foundation
import Testing
@testable import Droppy

/// Drives the real share page and download link over a live socket, the way a
/// phone's browser would: fetch "/", follow a link, get the bytes back.
@Suite struct LocalSendBrowserProbeTests {
    @Test @MainActor func browserFetchesThePageThenTheFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("droppy-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("notes & <plans>.txt")
        try Data("hello from droppy".utf8).write(to: file)

        let service = LocalSendService.shared
        service.staged = [file]
        #expect(service.startOffer())
        defer { service.stopOffer() }
        let offer = try #require(service.offer)

        let server = LocalSendHTTPServer { request in await service.route(request) }
        try await server.start(port: 0, identity: nil)
        defer { server.stop() }
        let port = try #require(server.port)
        let base = "http://127.0.0.1:\(port)"

        let (pageData, pageResponse) = try await URLSession.shared.data(from: URL(string: base + "/")!)
        #expect((pageResponse as? HTTPURLResponse)?.statusCode == 200)
        let page = String(decoding: pageData, as: UTF8.self)
        // The name is shown, escaped, and its link carries the session.
        #expect(page.contains("notes &amp; &lt;plans&gt;.txt"))
        #expect(page.contains("sessionId=\(offer.id)"))
        let fileID = try #require(offer.files.keys.first)

        let link = "\(base)/api/localsend/v2/download?sessionId=\(offer.id)&fileId=\(fileID)"
        let (data, response) = try await URLSession.shared.data(from: URL(string: link)!)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == "hello from droppy")

        // A stale session is refused rather than served.
        let (_, stale) = try await URLSession.shared.data(
            from: URL(string: "\(base)/api/localsend/v2/download?sessionId=nope&fileId=\(fileID)")!)
        #expect((stale as? HTTPURLResponse)?.statusCode == 409)
    }
}
