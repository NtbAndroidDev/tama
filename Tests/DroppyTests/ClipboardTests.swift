import Foundation
import Testing
@testable import Droppy

@Suite struct ClipboardClassifyTests {
    @Test(arguments: [
        ("https://example.com/a?b=1", ClipboardType.url), ("http://x.io", .url), ("  https://apple.com\n", .url),
        ("#FF8800", .color), ("#ff880080", .color), ("#a1b2c3", .color),
        ("#design", .text), ("#abc", .text), ("#GGGGGG", .text),
        ("func greet() {}", .code), ("import SwiftUI\nstruct A {}", .code), ("  let x = 1", .code),
        ("const a = 1;", .code), ("hello\n    return nil", .code),
        ("My class starts at 5", .text), ("An important import tax", .text),
        ("see https://apple.com for more", .text), ("https://a.com and more words", .text),
        ("plain words", .text),
    ])
    func classify(_ input: String, _ expected: ClipboardType) {
        #expect(ClipboardType.classify(input) == expected)
    }
}

@Suite struct ClipboardHistoryTests {
    @Test func duplicateOfNewestIsSkipped() {
        let latest = ClipboardItem(content: "hello")
        #expect(ClipboardHistory.isDuplicate(ClipboardItem(content: "hello"), of: latest))
        #expect(!ClipboardHistory.isDuplicate(ClipboardItem(content: "hello!"), of: latest))
        #expect(!ClipboardHistory.isDuplicate(ClipboardItem(content: "hello"), of: nil))
    }

    @Test func sameContentDifferentTypeIsKept() {
        let text = ClipboardItem(content: "/Users/me/a.txt", type: .text)
        #expect(!ClipboardHistory.isDuplicate(ClipboardItem(content: "/Users/me/a.txt", type: .file), of: text))
    }

    @Test func imagesDedupeByHash() {
        let a = ClipboardItem(content: "1.png", type: .image, imageHash: "abc")
        #expect(ClipboardHistory.isDuplicate(ClipboardItem(content: "2.png", type: .image, imageHash: "abc"), of: a))
        #expect(!ClipboardHistory.isDuplicate(ClipboardItem(content: "3.png", type: .image, imageHash: "def"), of: a))
    }

    @Test func retentionDropsOldestHistoryOnly() {
        var items = (0..<6).map { ClipboardItem(content: "clip \($0)") }   // newest first
        items[4].isPinned = true
        items[5].board = "Work"
        let kept = ClipboardHistory.trimmed(items, limit: 2)
        #expect(kept.map(\.content) == ["clip 0", "clip 1", "clip 4", "clip 5"])
    }

    @Test func retentionUnderLimitIsUntouched() {
        let items = (0..<3).map { ClipboardItem(content: "\($0)") }
        #expect(ClipboardHistory.trimmed(items, limit: 3) == items)
        #expect(ClipboardHistory.trimmed(items, limit: 0).count == 1)   // limit clamps to 1
    }
}

@Suite struct ClipboardItemCodingTests {
    @Test func roundTrip() throws {
        var item = ClipboardItem(content: "#112233", type: .color, isPinned: true, board: "Work",
                                 sourceBundleID: "com.apple.Safari", imageHash: "h")
        item.customTitle = "Brand"
        item.ocrText = "text"
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: JSONEncoder().encode(item))
        #expect(decoded == item)
        #expect(decoded.copiedAt == item.copiedAt)
    }

    @Test func decodesOlderFilesWithoutNewKeys() throws {
        let json = """
        [{"id":"8C1D2C4B-6B61-4F4A-9E4B-0B0F2C9E1A11","content":"hi","type":"text",
          "copiedAt":780000000,"isPinned":false}]
        """
        let items = try JSONDecoder().decode([ClipboardItem].self, from: Data(json.utf8))
        let item = try #require(items.first)
        #expect(item.content == "hi" && item.type == .text && !item.isPinned)
        #expect(item.board == nil && item.customTitle == nil && item.sourceBundleID == nil)
        #expect(item.imageHash == nil && item.ocrText == nil)
        #expect(item.copiedAt == Date(timeIntervalSinceReferenceDate: 780000000))
    }

    @Test func derivedValues() throws {
        let color = ClipboardItem(content: "#FF8000", type: .color)
        let rgb = try #require(color.parsedColorComponents)
        #expect(rgb.r == 1 && rgb.b == 0)
        #expect(color.rgbFormatted == "rgb(255, 128, 0)")
        let files = ClipboardItem(content: "/a/one.txt\n/b/two.txt", type: .file)
        #expect(files.fileURLs.map(\.lastPathComponent) == ["one.txt", "two.txt"])
        #expect(files.displayTitle == "2 files")
        #expect(ClipboardItem(content: "/a/one.txt", type: .file).displayTitle == "one.txt")
    }
}

@Suite struct ClipboardInsertTests {
    @Test func repeatOfNewestChangesNothing() {
        let items = [ClipboardItem(content: "a"), ClipboardItem(content: "b")]
        #expect(ClipboardHistory.inserting(ClipboardItem(content: "a"), into: items) == nil)
    }

    @Test func newClipGoesOnTop() throws {
        let items = [ClipboardItem(content: "a")]
        let result = try #require(ClipboardHistory.inserting(ClipboardItem(content: "b"), into: items))
        #expect(result.map(\.content) == ["b", "a"])
    }

    @Test func repeatOfOlderClipMovesItToFrontKeepingItsDetails() throws {
        var old = ClipboardItem(content: "b")
        old.isPinned = true
        old.board = "Work"
        old.customTitle = "Mine"
        let items = [ClipboardItem(content: "a"), old, ClipboardItem(content: "c")]
        let now = Date().addingTimeInterval(60)
        let result = try #require(ClipboardHistory.inserting(ClipboardItem(content: "b"), into: items, now: now))
        #expect(result.map(\.content) == ["b", "a", "c"])
        #expect(result.count == 3)
        #expect(result[0].id == old.id)
        #expect(result[0].isPinned && result[0].board == "Work" && result[0].customTitle == "Mine")
        #expect(result[0].copiedAt == now)
    }

    @Test func repeatedImageMatchesByHash() throws {
        let items = [ClipboardItem(content: "t"), ClipboardItem(content: "1.png", type: .image, imageHash: "h")]
        let result = try #require(ClipboardHistory.inserting(ClipboardItem(content: "2.png", type: .image, imageHash: "h"), into: items))
        #expect(result.map(\.content) == ["1.png", "t"])
    }

    @Test func eightDigitHexColorHasASwatch() throws {
        let rgb = try #require(ClipboardItem(content: "#FF800080", type: .color).parsedColorComponents)
        #expect(rgb.r == 1 && rgb.b == 0)
    }
}

@Suite struct ClipboardParityTests {
    @Test func rejectDuplicatesLeavesHistoryAlone() {
        let items = [ClipboardItem(content: "a"), ClipboardItem(content: "b")]
        #expect(ClipboardHistory.inserting(ClipboardItem(content: "b"), into: items, rejectDuplicates: true) == nil)
        let moved = ClipboardHistory.inserting(ClipboardItem(content: "b"), into: items, rejectDuplicates: false)
        #expect(moved?.map(\.content) == ["b", "a"])
        #expect(ClipboardHistory.inserting(ClipboardItem(content: "c"), into: items, rejectDuplicates: true)?.count == 3)
    }

    @Test func newFieldsRoundTripAndDefault() throws {
        var item = ClipboardItem(content: "secret")
        item.tags = ["Work", "Later"]
        item.isSensitive = true
        item.rtfData = Data("{\\rtf1}".utf8)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: JSONEncoder().encode(item))
        #expect(decoded == item)
        let old = try JSONDecoder().decode(ClipboardItem.self, from: Data("""
        {"id":"8C1D2C4B-6B61-4F4A-9E4B-0B0F2C9E1A11","content":"hi","type":"text","copiedAt":1,"isPinned":false}
        """.utf8))
        #expect(old.tags.isEmpty && !old.isSensitive && !old.hasRichText)
    }

    @Test func multiPastePayloads() {
        let text = ClipboardItem(content: "one")
        let file = ClipboardItem(content: "/a/b.txt", type: .file)
        let image = ClipboardItem(content: "1.png", type: .image)
        #expect(ClipboardMultiPaste.payload(for: [text, file]) == .text("one\n/a/b.txt"))
        #expect(ClipboardMultiPaste.payload(for: [file, file]) == .files([URL(fileURLWithPath: "/a/b.txt"), URL(fileURLWithPath: "/a/b.txt")]))
        #expect(ClipboardMultiPaste.payload(for: [image]) == .images(["1.png"]))
        #expect(ClipboardMultiPaste.payload(for: [text, image]) == .text("one"))
        #expect(ClipboardMultiPaste.payload(for: []) == nil)
    }

    @Test func historyLimitStops() {
        #expect(ClipboardHistoryLimit.index(of: 50) == 2)
        #expect(ClipboardHistoryLimit.index(of: 60) == 2)
        #expect(ClipboardHistoryLimit.index(of: 1) == 0)
        #expect(ClipboardHistoryLimit.steps.last == 2500)
    }
}
