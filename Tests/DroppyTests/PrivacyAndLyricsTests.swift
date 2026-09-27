import Foundation
import Testing
@testable import Droppy

@Suite struct SensitiveContentDetectorTests {
    @Test(arguments: [
        ("4111 1111 1111 1111", SensitiveContentDetector.Kind.creditCard),
        ("5500-0000-0000-0004", .creditCard),
        ("-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----", .privateKey),
        ("AKIAIOSFODNN7EXAMPLE", .awsAccessKey),
        ("ghp_1234567890abcdefghijklmnopqrstuvwxyzAB", .gitHubToken),
    ])
    func flagsSecrets(_ input: String, _ kind: SensitiveContentDetector.Kind) {
        #expect(SensitiveContentDetector.detect(input) == kind)
    }

    @Test(arguments: [
        "123456",                       // one-time codes are kept on purpose
        "4111 1111 1111 1112",          // fails Luhn
        "Order #12345 ships Tuesday",
        "hello world",
        "https://github.com/apple/swift",
    ])
    func keepsOrdinaryText(_ input: String) {
        #expect(!SensitiveContentDetector.isSensitive(input))
    }

    @Test func luhn() {
        #expect(SensitiveContentDetector.luhn([4, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]))
        #expect(!SensitiveContentDetector.luhn([4, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2]))
    }
}

@Suite struct LyricsParserTests {
    @Test func parsesStampsInOrder() throws {
        let lrc = """
        [ar:Someone]
        [00:12.50]Second line
        [00:01.00]First line
        [01:02.25]Third line
        """
        let lyrics = try #require(Lyrics.parseLRC(lrc))
        #expect(lyrics.isSynced)
        #expect(lyrics.lines.map(\.text) == ["First line", "Second line", "Third line"])
        #expect(lyrics.lines.map(\.time) == [1.0, 12.5, 62.25])
    }

    @Test func repeatedStampsDuplicateTheLine() throws {
        let lyrics = try #require(Lyrics.parseLRC("[00:05.00][00:30.00]Chorus"))
        #expect(lyrics.lines.map(\.time) == [5, 30])
        #expect(lyrics.lines.allSatisfy { $0.text == "Chorus" })
    }

    @Test func offsetShiftsLinesEarlier() throws {
        let lyrics = try #require(Lyrics.parseLRC("[offset:+500]\n[00:10.00]Line"))
        #expect(lyrics.lines.first?.time == 9.5)
    }

    @Test func lineIndexFollowsPosition() throws {
        let lyrics = try #require(Lyrics.parseLRC("[00:01.00]A\n[00:05.00]B\n[00:09.00]C"))
        #expect(lyrics.lineIndex(at: 0.5) == nil)
        #expect(lyrics.lineIndex(at: 1) == 0)
        #expect(lyrics.lineIndex(at: 7) == 1)
        #expect(lyrics.lineIndex(at: 100) == 2)
    }

    @Test func plainTextIsUnsynced() throws {
        #expect(Lyrics.parseLRC("no stamps here") == nil)
        let plain = try #require(Lyrics.plain("One\nTwo"))
        #expect(!plain.isSynced)
        #expect(plain.lineIndex(at: 3) == nil)
    }
}
