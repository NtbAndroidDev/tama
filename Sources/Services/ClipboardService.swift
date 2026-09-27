import SwiftUI
import AppKit

@MainActor
public final class ClipboardService {
    public static let shared = ClipboardService()
    
    private var lastChangeCount: Int = 0
    private var timer: Timer?
    public var onNewItem: ((ClipboardItem) -> Void)?
    /// Called on the main actor once OCR for an image clip finishes, with
    /// the pasteboard's change count from when the image was copied.
    public var onRecognizedText: ((UUID, String, Int) -> Void)?
    /// Hash of the newest clip, so the same screenshot isn't stored twice.
    public var latestImageHash: (() -> String?)?

    /// Bigger text is usually an accidental select-all of a log or dump.
    private static let maxTextBytes = 1_000_000
    /// Styled copies past this are dropped; the plain text is still kept.
    private static let maxRichBytes = 512_000
    
    private init() {
        self.lastChangeCount = NSPasteboard.general.changeCount
    }
    
    public var isMonitoring: Bool { timer != nil }

    /// The pasteboard's current change count.
    public var changeCount: Int { NSPasteboard.general.changeCount }

    public func startMonitoring() {
        // Whatever was copied while monitoring was off isn't picked up.
        lastChangeCount = NSPasteboard.general.changeCount
        timer?.invalidate()
        // Scheduled on the main run loop, so the tick is already on the main
        // actor; a Task per tick was an allocation and a hop for nothing.
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                // The change count keeps; a copy made while the screen was
                // off is picked up on the first tick after it wakes.
                guard !PowerStateService.shared.isDormant else { return }
                self?.checkPasteboard()
            }
        }
        // Lets macOS fold these wake-ups into others while the Mac idles.
        timer?.tolerance = 0.2
    }
    
    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        // Password managers mark secrets as concealed or transient; never keep those.
        let types = pasteboard.types ?? []
        let privateTypes: [NSPasteboard.PasteboardType] = [
            .init("org.nspasteboard.ConcealedType"),
            .init("org.nspasteboard.TransientType")
        ]
        guard !types.contains(where: privateTypes.contains) else { return }
        // The change count still advances while paused, so resuming doesn't
        // pick up whatever was copied in the meantime.
        let privacy = ClipboardPrivacy.shared
        guard !privacy.isPaused else { return }
        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard !privacy.isExcluded(source) else { return }

        // Finder copies carry file URLs (plus an icon image), so check those first.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            let item = ClipboardItem(content: urls.map(\.path).joined(separator: "\n"), type: .file, sourceBundleID: source)
            onNewItem?(item)
            return
        }

        // Rich-text copies (Office, Numbers) also attach a rendered picture; the
        // writer's type order tells us whether the text or the image is the point.
        let imageIndex = types.firstIndex(where: { $0 == .png || $0 == .tiff })
        let stringIndex = types.firstIndex(of: .string)
        if let imageIndex, stringIndex.map({ imageIndex < $0 }) ?? true,
           let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            captureImage(data, source: source)
            return
        }

        if let str = pasteboard.string(forType: .string),
           str.utf8.count <= Self.maxTextBytes,
           !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let sensitive = SensitiveContentDetector.isSensitive(str)
            // Skip passwords wins; otherwise Blur sensitive keeps it, veiled.
            if sensitive, privacy.filterSensitive { return }
            let type = ClipboardType.classify(str)
            var item = ClipboardItem(content: str, type: type, sourceBundleID: source)
            item.isSensitive = sensitive && privacy.blurSensitive
            // The styled version, so pasting keeps bold, links and colours.
            // Never for secrets: a veiled clip stays plain.
            if !item.isSensitive {
                if let rtf = pasteboard.data(forType: .rtf), rtf.count <= Self.maxRichBytes { item.rtfData = rtf }
                if let html = pasteboard.data(forType: .html), html.count <= Self.maxRichBytes { item.htmlData = html }
            }
            onNewItem?(item)
        }
    }
    
    /// Encodes and stores the image off the main thread, then records the clip
    /// and runs OCR on it.
    private func captureImage(_ data: Data, source: String?) {
        let copiedAt = lastChangeCount
        Task { [weak self] in
            guard let encoded = await Task.detached(priority: .utility, operation: { ClipboardImageStore.encode(data) }).value,
                  self?.latestImageHash?() != encoded.hash else { return }
            let filename = UUID().uuidString + ".png"
            let png = encoded.png
            guard await Task.detached(priority: .utility, operation: { ClipboardImageStore.write(png, filename: filename) }).value else { return }
            let item = ClipboardItem(content: filename, type: .image, sourceBundleID: source, imageHash: encoded.hash)
            self?.onNewItem?(item)
            if let text = await Task.detached(priority: .background, operation: { ClipboardImageStore.recognizeText(in: filename) }).value {
                self?.onRecognizedText?(item.id, text, copiedAt)
            }
        }
    }

    /// An image for the pasteboard: the PNG bytes as they are, and TIFF made
    /// only if the pasting app asks for it (some read nothing else). Writing an
    /// `NSImage` instead would decode it and build the TIFF up front, on main.
    static func imageItem(png: Data) -> NSPasteboardItem {
        let entry = NSPasteboardItem()
        entry.setData(png, forType: .png)
        let provider = PNGToTIFFProvider(png: png)
        entry.setDataProvider(provider, forTypes: [.tiff])
        // Kept until the pasteboard lets go of it; see `pasteboardFinishedWithDataProvider`.
        PNGToTIFFProvider.live.insert(provider)
        return entry
    }

    /// False when an image clip's PNG or all of a file clip's files are gone;
    /// the pasteboard is left as it was then.
    @discardableResult
    public func copyToPasteboard(item: ClipboardItem, plainText: Bool = false) -> Bool {
        let pasteboard = NSPasteboard.general
        switch item.type {
        case .image:
            guard let png = Self.storedPNG(item.content) else { return false }
            pasteboard.clearContents()
            pasteboard.writeObjects([Self.imageItem(png: png)])
        case .file:
            let urls = item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !urls.isEmpty else { return false }
            pasteboard.clearContents()
            pasteboard.writeObjects(urls.map { $0 as NSURL })
        default:
            pasteboard.clearContents()
            // Rich by default; "Paste as Plain Text" writes the string alone.
            if !plainText {
                if let rtf = item.rtfData { pasteboard.setData(rtf, forType: .rtf) }
                if let html = item.htmlData { pasteboard.setData(html, forType: .html) }
            }
            pasteboard.setString(item.content, forType: .string)
        }
        // Our own write: the next poll must not record it as a new copy.
        self.lastChangeCount = pasteboard.changeCount
        return true
    }

    /// Several clips at once (see `ClipboardMultiPaste`). False when nothing
    /// of them is left to put on the pasteboard.
    @discardableResult
    public func copyToPasteboard(items: [ClipboardItem], plainText: Bool = false) -> Bool {
        if items.count == 1, let item = items.first { return copyToPasteboard(item: item, plainText: plainText) }
        let pasteboard = NSPasteboard.general
        switch ClipboardMultiPaste.payload(for: items) {
        case .files(let urls):
            let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !existing.isEmpty else { return false }
            pasteboard.clearContents()
            pasteboard.writeObjects(existing.map { $0 as NSURL })
        case .images(let names):
            let images = names.compactMap(Self.storedPNG).map(Self.imageItem(png:))
            guard !images.isEmpty else { return false }
            pasteboard.clearContents()
            pasteboard.writeObjects(images)
        case .text(let text):
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        case nil:
            return false
        }
        self.lastChangeCount = pasteboard.changeCount
        return true
    }

    /// A stored clip's PNG bytes, as they are on disk. Pasting them as-is
    /// skips what `writeObjects([NSImage])` did on main: decode the full
    /// image, then re-encode it as TIFF. Only the header is checked, so a
    /// damaged file still reports false instead of pasting garbage.
    private static func storedPNG(_ filename: String) -> Data? {
        guard let data = try? Data(contentsOf: ClipboardImageStore.url(for: filename)),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        return data
    }

    /// Clears stored images that no clip references any more.
    public func removeUnusedImages(referencedBy items: [ClipboardItem]) {
        let referenced = Set(items.filter { $0.type == .image }.map(\.content))
        Task.detached(priority: .background) { ClipboardImageStore.removeOrphans(keeping: referenced) }
    }

    public func copyToPasteboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        self.lastChangeCount = pasteboard.changeCount
    }
}

/// Supplies TIFF for an image put on the pasteboard as PNG, on request only.
@MainActor
final class PNGToTIFFProvider: NSObject, NSPasteboardItemDataProvider {
    static var live: Set<PNGToTIFFProvider> = []
    private let png: Data

    init(png: Data) {
        self.png = png
    }

    nonisolated func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .tiff, let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation else { return }
        item.setData(tiff, forType: .tiff)
    }

    nonisolated func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
        Task { @MainActor in _ = Self.live.remove(self) }
    }
}
