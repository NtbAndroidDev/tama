import SwiftUI

public enum ClipboardType: String, CaseIterable, Codable, Sendable {
    case text
    case url
    case code
    case color
    case image
    case file
    
    public var iconName: String {
        switch self {
        case .text: return "text.quote"
        case .url: return "link"
        case .code: return "curlybraces"
        case .color: return "paintpalette.fill"
        case .image: return "photo"
        case .file: return "doc"
        }
    }
    
    public var label: String {
        switch self {
        case .text: return "Text"
        case .url: return "Links"
        case .code: return "Code"
        case .color: return "Colors"
        case .image: return "Images"
        case .file: return "Files"
        }
    }
}

/// A tag clips can carry (Settings › Clipboard › Clipboard actions › Tags).
/// Unlike pinboards a clip can have any number of them.
public struct ClipTag: Identifiable, Hashable, Codable, Sendable {
    public var id: String { name }
    public var name: String
    public var tint: Int

    public init(name: String, tint: Int) {
        self.name = name
        self.tint = tint
    }

    public var color: Color { Pinboard.tints[tint % Pinboard.tints.count] }
}

public struct ClipboardItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let content: String
    public let type: ClipboardType
    /// When it was last copied; a repeat copy of the clip refreshes it.
    public var copiedAt: Date
    public var isPinned: Bool
    /// Pinboard this clip belongs to, if any.
    public var board: String?
    /// Name the user gave the card; falls back to the type label.
    public var customTitle: String?
    /// App that was frontmost when the copy happened.
    public var sourceBundleID: String?
    /// SHA-256 of the stored PNG, for skipping repeat copies of the same image.
    public var imageHash: String?
    /// Text Vision found in an image clip; searched alongside the content.
    public var ocrText: String?
    /// Settings › Clipboard › Tags: any number of tag names (see `ClipTag`).
    public var tags: [String] = []
    /// Looked like a password or key and was kept under Blur sensitive
    /// content: drawn blurred until hovered.
    public var isSensitive: Bool = false
    /// The styled copy of a text clip (RTF / HTML as the source app wrote
    /// it), so a paste keeps its formatting; "Paste as Plain Text" skips it.
    public var rtfData: Data?
    public var htmlData: Data?

    public init(
        id: UUID = UUID(),
        content: String,
        type: ClipboardType = .text,
        isPinned: Bool = false,
        board: String? = nil,
        sourceBundleID: String? = nil,
        imageHash: String? = nil
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.copiedAt = Date()
        self.isPinned = isPinned
        self.board = board
        self.sourceBundleID = sourceBundleID
        self.imageHash = imageHash
    }

    /// Clips saved by older builds have none of the newer keys.
    private enum CodingKeys: String, CodingKey {
        case id, content, type, copiedAt, isPinned, board, customTitle, sourceBundleID, imageHash, ocrText
        case tags, isSensitive, rtfData, htmlData
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        content = try c.decode(String.self, forKey: .content)
        type = try c.decode(ClipboardType.self, forKey: .type)
        copiedAt = try c.decode(Date.self, forKey: .copiedAt)
        isPinned = try c.decode(Bool.self, forKey: .isPinned)
        board = try c.decodeIfPresent(String.self, forKey: .board)
        customTitle = try c.decodeIfPresent(String.self, forKey: .customTitle)
        sourceBundleID = try c.decodeIfPresent(String.self, forKey: .sourceBundleID)
        imageHash = try c.decodeIfPresent(String.self, forKey: .imageHash)
        ocrText = try c.decodeIfPresent(String.self, forKey: .ocrText)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        isSensitive = try c.decodeIfPresent(Bool.self, forKey: .isSensitive) ?? false
        rtfData = try c.decodeIfPresent(Data.self, forKey: .rtfData)
        htmlData = try c.decodeIfPresent(Data.self, forKey: .htmlData)
    }

    /// Has a styled version to paste besides the plain text.
    public var hasRichText: Bool { rtfData != nil || htmlData != nil }

    /// What the clip contributes when several are pasted as one piece of
    /// text: the text itself, a file clip's paths, an image's OCR text.
    public var pasteText: String? {
        switch type {
        case .image: return ocrText
        case .file: return fileURLs.map(\.path).joined(separator: "\n")
        default: return content
        }
    }

    public var displayTitle: String {
        if let customTitle { return customTitle }
        switch type {
        case .text: return "Text"
        case .url: return "Link"
        case .code: return "Code"
        case .color: return "Color"
        case .image: return "Image"
        case .file:
            let urls = fileURLs
            return urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
        }
    }

    /// For `.file` clips: one path per line in `content`.
    public var fileURLs: [URL] {
        guard type == .file else { return [] }
        return content.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }
    
    public var previewText: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Longest `displayPreview` a card or tooltip gets; far more than fits.
    public static let displayPreviewLimit = 2_000

    /// `previewText` capped for drawing: a card shows a few lines, so a clip of
    /// megabytes isn't trimmed (and laid out) whole on every render. Same text
    /// as `previewText` for anything shorter than the limit.
    public var displayPreview: String {
        // utf8.count is O(1) for native strings; a Character is ≥ 1 byte.
        guard content.utf8.count > Self.displayPreviewLimit else { return previewText }
        return String(content.drop(while: \.isWhitespace).prefix(Self.displayPreviewLimit))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public var characterCount: Int {
        content.count
    }
    
    public var parsedColorComponents: (r: Double, g: Double, b: Double)? {
        guard type == .color || content.hasPrefix("#") else { return nil }
        var hex = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        // #RRGGBBAA (which classify() files under Colors too): drop the alpha.
        if hex.count == 8 { hex = String(hex.prefix(6)) }
        guard hex.count == 6, let intVal = Int(hex, radix: 16) else { return nil }
        let r = Double((intVal >> 16) & 0xFF) / 255.0
        let g = Double((intVal >> 8) & 0xFF) / 255.0
        let b = Double(intVal & 0xFF) / 255.0
        return (r, g, b)
    }
    
    public var parsedColor: Color? {
        guard let (r, g, b) = parsedColorComponents else { return nil }
        return Color(red: r, green: g, blue: b)
    }
    
    public var rgbFormatted: String? {
        guard let (r, g, b) = parsedColorComponents else { return nil }
        return "rgb(\(Int(r * 255)), \(Int(g * 255)), \(Int(b * 255)))"
    }
    
    public var swiftUIColorFormatted: String? {
        guard let (r, g, b) = parsedColorComponents else { return nil }
        return String(format: "Color(red: %.2f, green: %.2f, blue: %.2f)", r, g, b)
    }
    
    public var nsColorFormatted: String? {
        guard let (r, g, b) = parsedColorComponents else { return nil }
        return String(format: "NSColor(red: %.2f, green: %.2f, blue: %.2f, alpha: 1.0)", r, g, b)
    }
    
    public var uppercaseContent: String {
        content.uppercased()
    }
    
    public var lowercaseContent: String {
        content.lowercased()
    }
    
    public var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
