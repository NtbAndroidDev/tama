import SwiftUI
import UniformTypeIdentifiers
import AppKit
import PDFKit
@preconcurrency import Vision

public struct ShelfItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    /// Where the file is now; Rename and Move to… change it.
    public var url: URL
    public var name: String
    public var fileSize: Int64
    /// When it joined the Shelf or Basket; Auto-cleanup counts from here.
    public var addedAt: Date
    /// Pinned files never expire and never leave to make room.
    public var isPinned: Bool
    /// Settings › Shelf › Two Stacks: 0 = Stack 1, 1 = Stack 2. In a Basket
    /// the same field picks the main bucket (0) or the second bucket (1).
    public var stack: Int
    /// Tag names, shared with the clipboard's pinboards.
    public var tags: [String]
    /// Read once when the item is made (or moved): tiles ask on every render,
    /// and a disk check per tile per frame added up on a full Shelf.
    public private(set) var isDirectory: Bool

    public init(
        id: UUID = UUID(),
        name: String? = nil,
        url: URL,
        fileSize: Int64? = nil,
        fileExtension: String? = nil,
        isPinned: Bool = false,
        addedAt: Date = Date(),
        stack: Int = 0,
        tags: [String] = []
    ) {
        self.id = id
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.addedAt = addedAt
        self.isPinned = isPinned
        self.stack = stack
        self.tags = tags

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = exists && isDir.boolValue
        if let customSize = fileSize {
            self.fileSize = customSize
        } else if isDirectory {
            // Walking a folder can take a while and this runs on main for
            // every drop: the Shelf or Basket that holds it measures it in the
            // background (`AppState.measureFolderSizes`) and patches it in.
            self.fileSize = 0
        } else {
            self.fileSize = Self.size(of: url)
        }
    }

    /// A file's size, or a folder's total, from its attributes.
    static func size(of url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }
        // Folders: add up what's inside, but don't walk a whole disk for a tile.
        var total: Int64 = 0
        var count = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey]
        if let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) {
            for case let child as URL in walker {
                count += 1
                if count > 5000 { break }
                let values = try? child.resourceValues(forKeys: Set(keys))
                total += Int64(values?.fileSize ?? values?.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }

    /// The same item pointing at a file that moved or was renamed.
    public func moved(to newURL: URL) -> ShelfItem {
        var copy = self
        copy.url = newURL
        copy.name = newURL.lastPathComponent
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: newURL.path, isDirectory: &isDir)
        copy.isDirectory = exists && isDir.boolValue
        // A moved or renamed folder holds what it held: keep its total rather
        // than walking it again on main. A file's size is one cheap stat.
        if !(isDirectory && copy.isDirectory) { copy.fileSize = Self.size(of: newURL) }
        return copy
    }

    /// Settings › Shelf › Auto-cleanup: when this item goes, or nil if it stays.
    public func expiryDate(after interval: TimeInterval?) -> Date? {
        guard let interval, !isPinned else { return nil }
        return addedAt.addingTimeInterval(interval)
    }

    /// Close to its expiry: a tenth of its lifetime left, or five minutes.
    public func expiresSoon(after interval: TimeInterval?, now: Date = Date()) -> Bool {
        guard let interval, let end = expiryDate(after: interval) else { return false }
        let left = end.timeIntervalSince(now)
        return left > 0 && (left < interval * 0.1 || left < 300)
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    public var fileExtension: String {
        let ext = url.pathExtension.uppercased()
        return ext.isEmpty ? "FILE" : ext
    }
    
    public var isImage: Bool {
        let ext = url.pathExtension.lowercased()
        // SVG is XML to Vision and the image tools, so it stays a plain file.
        guard ext != "svg", let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .image)
    }
    
    public var badgeColor: Color {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "webp", "gif", "svg", "heic":
            return Color(red: 40/255, green: 180/255, blue: 230/255)
        case "pdf":
            return Color(red: 235/255, green: 65/255, blue: 65/255)
        case "zip", "tar", "gz", "rar", "7z", "dmg":
            return Color(red: 245/255, green: 145/255, blue: 40/255)
        case "swift", "js", "ts", "py", "html", "css", "json", "sh":
            return Color(red: 0.62, green: 0.48, blue: 0.98)
        case "mov", "mp4", "mkv", "avi":
            return Color(red: 160/255, green: 70/255, blue: 230/255)
        case "mp3", "m4a", "wav", "flac":
            return Color(red: 50/255, green: 200/255, blue: 110/255)
        default:
            return DS.Palette.textTertiary
        }
    }
    
    public var systemIconName: String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "webp", "gif", "svg", "heic":
            return "photo.fill"
        case "mov", "mp4", "mkv", "avi":
            return "film.fill"
        case "mp3", "m4a", "wav", "flac":
            return "music.note"
        case "pdf":
            return "doc.richtext.fill"
        case "zip", "tar", "gz", "rar", "7z", "dmg":
            return "archivebox.fill"
        case "swift", "js", "ts", "py", "html", "css", "json", "sh":
            return "curlybraces"
        default:
            return isDirectory ? "folder.fill" : "doc.fill"
        }
    }
    
    /// A downsampled copy (≤ 1024 px): never the full-size image in memory.
    /// Synchronous; views use `ShelfThumbnail`, which loads off the main thread.
    public var thumbnailImage: NSImage? {
        guard isImage, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
    
    /// Pixel size from the file's header, without decoding the image.
    public var imageDimensions: CGSize? {
        guard isImage, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: width, height: height)
    }
    
    public func revealInFinder() {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
    }
    
    public func openFile() {
        NSWorkspace.shared.open(url)
    }
    
    @MainActor
    public func quickLook() {
        QuickLookService.shared.preview([url])
    }
    
    /// Formats this file can be converted to (see `FileConverter`).
    public var convertTargets: [String] { FileConverter.targets(for: url) }

    public func extractText(completion: @escaping @Sendable (String) -> Void) {
        // Vision reads the file itself, off the main thread; decoding it into
        // an NSImage and a TIFF copy first held the image in memory three times.
        let url = url
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(url: url, options: [:])
            // An unreadable file throws; it still reports back, with no text.
            try? handler.perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let fullText = lines.joined(separator: "\n")
            DispatchQueue.main.async {
                completion(fullText)
            }
        }
    }
}

// MARK: - Persistence

/// What survives a relaunch of a held file: its path and the Shelf's own
/// bookkeeping (when it came, pinned, stack, tags).
struct HeldFileRecord: Codable, Sendable {
    var id: UUID
    var path: String
    var addedAt: Date
    var isPinned: Bool
    var stack: Int
    var tags: [String]
    /// Optional so records saved before it existed still decode. Kept for
    /// folders, whose total is otherwise walked again at every launch.
    var fileSize: Int64?

    init(_ item: ShelfItem) {
        id = item.id
        path = item.url.path
        addedAt = item.addedAt
        isPinned = item.isPinned
        stack = item.stack
        tags = item.tags
        fileSize = item.fileSize
    }

    /// nil when the file is gone.
    var item: ShelfItem? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return nil }
        // A folder keeps last session's total (an old record without one is
        // measured in the background); a file's own size is read fresh.
        return ShelfItem(id: id, url: URL(fileURLWithPath: path),
                         fileSize: isDir.boolValue ? fileSize : nil, isPinned: isPinned,
                         addedAt: addedAt, stack: stack, tags: tags)
    }
}
