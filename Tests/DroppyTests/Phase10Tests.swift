import Foundation
import Security
import Testing
@testable import Droppy

@Suite struct LocalSendProtocolTests {
    @Test func routesAndQueries() {
        #expect(LocalSendFormat.route(of: "/api/localsend/v2/prepare-upload?pin=1234")?.name == "prepare-upload")
        #expect(LocalSendFormat.route(of: "/api/localsend/v2/prepare-upload")?.version == 2)
        #expect(LocalSendFormat.route(of: "/api/localsend/v2/register")?.name == "register")
        // v1 is answered too, and says so, so the handlers can shape their replies.
        #expect(LocalSendFormat.route(of: "/api/localsend/v1/send-request")?.version == 1)
        #expect(LocalSendFormat.route(of: "/api/localsend/v1/send?fileId=a&token=b")?.name == "send")
        #expect(LocalSendFormat.route(of: "/api/localsend/v3/send") == nil)
        #expect(LocalSendFormat.route(of: "/") == nil)
        #expect(LocalSendFormat.route(of: "/api/localsend/v2/a/b") == nil)
        #expect(LocalSendFormat.path(of: "/api/localsend/v2/download?fileId=1") == "/api/localsend/v2/download")
        #expect(LocalSendFormat.path(of: "/") == "/")
        let q = LocalSendFormat.query(of: "/api/localsend/v2/upload?sessionId=abc&fileId=f%201&token=t+x")
        #expect(q["sessionId"] == "abc")
        #expect(q["fileId"] == "f 1")
        #expect(q["token"] == "t x")
        #expect(LocalSendFormat.query(of: "/x").isEmpty)
    }

    @Test func safePaths() {
        #expect(LocalSendFormat.safeRelativePath("photo.jpg") == "photo.jpg")
        #expect(LocalSendFormat.safeRelativePath("Album/2024/a.jpg") == "Album/2024/a.jpg")
        #expect(LocalSendFormat.safeRelativePath("/etc/passwd") == "etc/passwd")
        #expect(LocalSendFormat.safeRelativePath("../../evil") == nil)
        #expect(LocalSendFormat.safeRelativePath("a\\..\\b") == nil)
        #expect(LocalSendFormat.safeRelativePath("") == nil)
        #expect(LocalSendFormat.safeRelativePath("./a:b") == "a_b")
    }

    @Test func decodesAnnouncementWithUnknownDeviceType() throws {
        let json = #"{"alias":"Pixel","version":"2.1","deviceModel":"Google","deviceType":"toaster","fingerprint":"abc","port":53317,"protocol":"https","download":false,"announce":true}"#
        let info = try JSONDecoder().decode(LocalSendDeviceInfo.self, from: Data(json.utf8))
        #expect(info.alias == "Pixel")
        #expect(info.deviceType == nil)
        #expect(info.announce == true)
        let minimal = try JSONDecoder().decode(LocalSendDeviceInfo.self, from: Data(#"{"alias":"A","fingerprint":"f"}"#.utf8))
        #expect(minimal.port == nil && minimal.protocol == nil)
    }

    @Test func deviceSymbolsAndModels() {
        #expect(LocalSendDeviceType.symbol(type: .mobile, model: "iPhone") == "iphone")
        #expect(LocalSendDeviceType.symbol(type: .desktop, model: "MacBook Pro") == "laptopcomputer")
        #expect(LocalSendDeviceType.symbol(type: .desktop, model: "Windows") == "pc")
        #expect(LocalSendDeviceType.symbol(type: .web, model: nil) == "globe")
        #expect(LocalSendFormat.modelName(fromHardwareModel: "MacBookPro18,3") == "MacBook Pro")
        #expect(LocalSendFormat.modelName(fromHardwareModel: "Macmini9,1") == "Mac mini")
        #expect(LocalSendFormat.modelName(fromHardwareModel: "Mac14,2") == nil)
    }

    @Test func senderErrors() {
        #expect(LocalSendFormat.senderError(status: 401) == "This device asks for a PIN")
        #expect(LocalSendFormat.senderError(status: 403) == "The receiver declined the transfer")
        #expect(LocalSendFormat.senderError(status: 409) == "The receiver is busy with another transfer")
        #expect(LocalSendFormat.senderError(status: 500) == "The receiver reported an error (500)")
    }

    @Test func textMessageDetection() {
        let text = LocalSendFileInfo(id: "1", fileName: "m.txt", size: 5, fileType: "text/plain", preview: "hello")
        let file = LocalSendFileInfo(id: "2", fileName: "a.txt", size: 5, fileType: "text/plain")
        #expect(text.isTextMessage)
        #expect(!file.isTextMessage)
    }
}

@Suite struct LocalSendBodyTests {
    @Test func contentLengthBody() {
        var reader = BodyReader(headers: ["content-length": "5"])
        #expect(reader.feed(Data("he".utf8)) == .more(Data("he".utf8)))
        #expect(reader.feed(Data("lloEXTRA".utf8)) == .finished(Data("llo".utf8)))
        var empty = BodyReader(headers: [:])
        #expect(empty.feed(Data()) == .finished(Data()))
    }

    @Test func chunkedBodyInPieces() {
        let raw = Data("4\r\nWiki\r\n5;ext=1\r\npedia\r\n0\r\n\r\n".utf8)
        // Feed a byte at a time, the hardest split.
        var decoder = ChunkedDecoder()
        var output = Data()
        var finished = false
        for byte in raw {
            switch decoder.feed(Data([byte])) {
            case let .more(d): output.append(d)
            case let .finished(d): output.append(d); finished = true
            case .malformed: Issue.record("malformed")
            }
        }
        #expect(finished)
        #expect(String(decoding: output, as: UTF8.self) == "Wikipedia")
        var bad = ChunkedDecoder()
        #expect(bad.feed(Data("zz\r\n".utf8)) == .malformed)
    }
}

@Suite struct LocalSendCertificateTests {
    @Test func selfSignedCertificateParsesAndVerifies() throws {
        // An in-memory key only; nothing touches the keychain.
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeySizeInBits: 256]
        let key = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
        let der = try LocalSendTLS.selfSignedCertificate(for: key)
        let certificate = try #require(SecCertificateCreateWithData(nil, der as CFData))
        #expect(SecCertificateCopySubjectSummary(certificate) as String? == "Tama LocalSend")
        let publicKey = try #require(SecCertificateCopyKey(certificate))
        #expect(SecKeyCopyExternalRepresentation(publicKey, nil) as Data? == SecKeyCopyExternalRepresentation(SecKeyCopyPublicKey(key)!, nil) as Data?)
        // A self-signed certificate evaluates as untrusted but well-formed:
        // the trust object can be built from it.
        var trust: SecTrust?
        #expect(SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust) == errSecSuccess)
        let fingerprint = LocalSendTLS.fingerprint(ofCertificate: der)
        #expect(fingerprint.count == 64 && fingerprint.allSatisfy(\.isHexDigit))
    }

    @Test func derPrimitives() {
        #expect(DER.integer([0x00, 0x80]) == Data([0x02, 0x02, 0x00, 0x80]))
        #expect(DER.oid([1, 2, 840, 10045, 2, 1]) == Data([0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]))
        let long = DER.tlv(0x04, Data(repeating: 1, count: 300))
        #expect(Array(long.prefix(4)) == [0x04, 0x82, 0x01, 0x2C])
    }
}

@Suite struct LocalSendServerTests {
    /// The HTTP server end to end on a free port: register (buffered body),
    /// upload (streamed, chunked) and an unknown route.
    @Test func serverRoundTrip() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("droppy-ls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appendingPathComponent("upload.bin")
        let server = LocalSendHTTPServer { request in
            switch LocalSendFormat.route(of: request.target)?.name {
            case "register":
                return .readBody(limit: 1024) { data in
                    .json(["echo": String(decoding: data, as: UTF8.self), "host": request.remoteHost])
                }
            case "upload":
                return .streamBody(to: target, then: { result in
                    if case let .success(count) = result { return .json(["bytes": count]) }
                    return .status(500)
                }, progress: { _ in })
            default:
                return .respond(.status(404))
            }
        }
        try await server.start(port: 0, identity: nil)
        defer { server.stop() }
        let port = try #require(server.port)
        let base = "http://127.0.0.1:\(port)/api/localsend/v2/"

        var register = URLRequest(url: URL(string: base + "register")!)
        register.httpMethod = "POST"
        register.httpBody = Data("{\"alias\":\"x\"}".utf8)
        let (data, response) = try await URLSession.shared.data(for: register)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let echoed = try JSONDecoder().decode([String: String].self, from: data)
        #expect(echoed["echo"] == "{\"alias\":\"x\"}")
        #expect(echoed["host"] == "127.0.0.1")

        let payload = Data((0..<200_000).map { UInt8($0 % 251) })
        var upload = URLRequest(url: URL(string: base + "upload?sessionId=s&fileId=f&token=t")!)
        upload.httpMethod = "POST"
        let (uploadData, uploadResponse) = try await URLSession.shared.upload(for: upload, from: payload)
        #expect((uploadResponse as? HTTPURLResponse)?.statusCode == 200)
        #expect(try JSONDecoder().decode([String: Int].self, from: uploadData)["bytes"] == payload.count)
        #expect(try Data(contentsOf: target) == payload)

        var missing = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/nope")!)
        missing.httpMethod = "GET"
        let (_, missingResponse) = try await URLSession.shared.data(for: missing)
        #expect((missingResponse as? HTTPURLResponse)?.statusCode == 404)
    }
}

@Suite struct ReleaseNotesTests {
    @Test func latestSectionWithGroups() {
        let markdown = """
        # Changelog

        Intro.

        ## Phase 10: Droplet store

        **Droplets**
        - A new store.
        - LocalSend.

        **Fixes**
        - Fewer bugs.

        ## Phase 9

        - Old.
        """
        let notes = ReleaseNotes.latest(from: markdown)
        #expect(notes?.title == "Phase 10: Droplet store")
        #expect(notes?.groups.map(\.title) == ["Droplets", "Fixes"])
        #expect(notes?.groups.first?.items == ["A new store.", "LocalSend."])
        let plain = ReleaseNotes.latest(from: "## One\n- a\n- b\n")
        #expect(plain?.groups == [ReleaseNotes.Group(title: "New Features", items: ["a", "b"])])
        #expect(ReleaseNotes.latest(from: "nothing") == nil)
    }
}

@MainActor @Suite struct Phase10SettingsTests {
    @Test func newOptionsAreSearchableAndReset() {
        #expect(SettingsSearchIndex.search("localsend pin").contains { $0.anchor == "droplet.localSend.pin" })
        #expect(SettingsSearchIndex.search("tooltips").first?.anchor == "a11y.tooltips")
        #expect(SettingsSearchIndex.search("export logs").contains { $0.anchor == "about.exportLogs" })
        #expect(SettingsSearchIndex.search("forget this device").contains { $0.anchor == "droplet.localSend.favorites" })
        for key in ["localSendPIN", "localSendReceiveMode", "diagnosticLogging", "showTooltips", "showWhatsNew", "sidebarHiddenDroplets"] {
            #expect(AppState.settingsKeys.contains(key))
        }
        #expect(AppState.defaultDroplets.contains { $0.id == "localSend" && !$0.isEnabled })
        #expect(QuickAction.choosable.contains(.localSend))
    }
}
