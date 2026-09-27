import Foundation
import Testing
@testable import Droppy

@Suite struct LANShareTests {
    let token = "0123456789abcdef01234567"

    @Test func tokenIsTwentyFourHexCharsAndRandom() {
        let a = LANShareService.randomToken(), b = LANShareService.randomToken()
        #expect(a.count == 24 && b.count == 24)
        #expect(a.allSatisfy { $0.isHexDigit })
        #expect(a != b)
    }

    @Test func shareURL() {
        let url = LANShareService.shareURL(host: "192.168.1.20", port: 51234, token: token)
        #expect(url.absoluteString == "http://192.168.1.20:51234/\(token)/")
        #expect(url.host == "192.168.1.20" && url.port == 51234)
    }

    @Test func routes() {
        func route(_ target: String, files: Int = 3) -> ShareRoute { ShareRoute(target: target, token: token, fileCount: files) }
        #expect(route("/\(token)/") == .index)
        #expect(route("/\(token)") == .index)
        #expect(route("/\(token)/?utm=1") == .index)
        #expect(route("/\(token)/f/0") == .file(0))
        #expect(route("/\(token)/f/2?download") == .file(2))
        #expect(route("/\(token)/f/3") == .notFound)
        #expect(route("/\(token)/f/-1") == .notFound)
        // Regression: Int("+1") parsed, aliasing file 1.
        #expect(route("/\(token)/f/+1") == .notFound)
        #expect(route("/\(token)/f/") == .notFound)
        #expect(route("/wrongtoken/f/0") == .notFound)
        #expect(route("/") == .notFound)
        #expect(route("/\(token)/../etc/passwd") == .notFound)
    }

    @Test func contentDispositionEscapes() {
        #expect(ShareRoute.contentDisposition(filename: "report.pdf")
                == "attachment; filename=\"report.pdf\"; filename*=UTF-8''report.pdf")
        let tricky = ShareRoute.contentDisposition(filename: "a\"b\r\nX: y.txt")
        #expect(!tricky.contains("\r") && !tricky.contains("\n"))
        #expect(tricky.hasPrefix("attachment; filename=\"a_b__X: y.txt\""))
        #expect(ShareRoute.contentDisposition(filename: "Ảnh 1.png").contains("filename*=UTF-8''%E1%BA%A2nh%201.png"))
    }

    @Test func foldersAreServedZippedAndFilesAsIs() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("LANShareTests-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("Ảnh chụp 1")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data("hi".utf8).write(to: folder.appendingPathComponent("a.txt"))
        let file = root.appendingPathComponent("note.txt")
        try Data("x".utf8).write(to: file)

        let served = LANShareService.servableFiles([file, folder])
        #expect(served[0] == file)
        #expect(served[1].lastPathComponent == "Ảnh chụp 1.zip")
        #expect(fm.fileExists(atPath: served[1].path))
        try? fm.removeItem(at: served[1].deletingLastPathComponent())
    }
}
