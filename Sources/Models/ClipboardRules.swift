import Foundation

extension ClipboardType {
    /// Keywords that start a line of source code. Matching them anywhere
    /// ("my class starts at 5") filed plain prose under Code.
    private static let codeLineStarts = [
        "func ", "class ", "import ", "const ", "struct ", "enum ", "let ", "var ",
        "def ", "#include", "public ", "private ", "return ", "function ", "@objc", "if (", "for ("
    ]

    /// Classifies copied text. Leading/trailing whitespace (a stray newline
    /// from a terminal copy) doesn't change what the text is.
    static func classify(_ string: String) -> ClipboardType {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if (text.hasPrefix("http://") || text.hasPrefix("https://")),
           !text.contains(where: \.isWhitespace) {
            return .url
        }
        if text.hasPrefix("#"), text.count == 7 || text.count == 9,
           text.dropFirst().allSatisfy(\.isHexDigit) {
            return .color
        }
        let lines = text.split(whereSeparator: \.isNewline)
        if lines.contains(where: { line in
            let trimmed = line.drop(while: \.isWhitespace)
            return codeLineStarts.contains { trimmed.hasPrefix($0) }
        }) {
            return .code
        }
        return .text
    }
}

/// History bookkeeping for the clipboard, independent of the pasteboard.
enum ClipboardHistory {
    /// A copy repeating the newest clip is dropped instead of stacking up.
    /// The type must match too: copying a path as text and then the file
    /// itself are two different clips.
    static func isDuplicate(_ item: ClipboardItem, of latest: ClipboardItem?) -> Bool {
        guard let latest else { return false }
        if let hash = item.imageHash, latest.imageHash == hash { return true }
        return latest.type == item.type && latest.content == item.content
    }

    /// Where a new copy goes: nil when it repeats the newest clip (nothing
    /// changes), the existing clip moved to the front and re-dated when it
    /// repeats an older one (keeping its star, pinboard, title and OCR text),
    /// otherwise the new clip on top. With `rejectDuplicates` (Settings ›
    /// Clipboard › Reject duplicates) a repeat of any clip is dropped and
    /// the history stays exactly as it was.
    static func inserting(_ item: ClipboardItem, into items: [ClipboardItem], now: Date = Date(),
                          rejectDuplicates: Bool = false) -> [ClipboardItem]? {
        if isDuplicate(item, of: items.first) { return nil }
        var result = items
        if let index = result.firstIndex(where: { isDuplicate(item, of: $0) }) {
            if rejectDuplicates { return nil }
            var existing = result.remove(at: index)
            existing.copiedAt = now
            result.insert(existing, at: 0)
        } else {
            result.insert(item, at: 0)
        }
        return result
    }

    /// Drops the oldest history clips past `limit`. Starred clips and clips
    /// filed on a pinboard don't count and are never removed.
    static func trimmed(_ items: [ClipboardItem], limit: Int) -> [ClipboardItem] {
        let isHistory: (ClipboardItem) -> Bool = { !$0.isPinned && $0.board == nil }
        var excess = items.filter(isHistory).count - max(limit, 1)
        guard excess > 0 else { return items }
        var result = items
        for index in result.indices.reversed() where excess > 0 && isHistory(result[index]) {
            result.remove(at: index)
            excess -= 1
        }
        return result
    }
}

/// Settings › Clipboard › History limit: the stops of the slider.
enum ClipboardHistoryLimit {
    static let steps = [10, 25, 50, 100, 200, 500, 1000, 2500]

    /// The stop at or just below `limit` (limits from older builds that fall
    /// between stops still show on the right notch).
    static func index(of limit: Int) -> Int {
        steps.lastIndex(where: { $0 <= limit }) ?? 0
    }
}

/// What several selected clips become on the pasteboard at once.
enum ClipboardMultiPaste {
    enum Payload: Equatable {
        case text(String)
        case files([URL])
        case images([String])
    }

    /// All files → the files; all images → the images; anything else → the
    /// clips' text joined by newlines (file paths, an image's OCR text).
    static func payload(for items: [ClipboardItem]) -> Payload? {
        guard !items.isEmpty else { return nil }
        if items.allSatisfy({ $0.type == .file }) { return .files(items.flatMap(\.fileURLs)) }
        if items.allSatisfy({ $0.type == .image }) { return .images(items.map(\.content)) }
        let parts = items.compactMap(\.pasteText).filter { !$0.isEmpty }
        return parts.isEmpty ? nil : .text(parts.joined(separator: "\n"))
    }
}
