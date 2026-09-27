import AppKit

/// Handlers for the macOS Services declared under `NSServices` in Info.plist
/// (Finder › right-click › Services). Selector names must match `NSMessage`.
@MainActor
final class ServicesProvider: NSObject {
    static let shared = ServicesProvider()

    /// `servicesProvider` is not retained by AppKit, hence the shared instance.
    static func install() {
        NSApp.servicesProvider = shared
        // Picks up Info.plist changes without logging out after an update.
        NSUpdateDynamicServices()
    }

    /// "Add to Tama Shelf".
    @objc func addToShelf(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        add(pboard, to: "shelf", error: error)
    }

    /// "Add to Tama Basket".
    @objc func addToBasket(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        add(pboard, to: "basket", error: error)
    }

    /// The service's old name, kept so a cached Services menu still works.
    @objc func addToTray(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        add(pboard, to: "shelf", error: error)
    }

    private func add(_ pboard: NSPasteboard, to target: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = fileURLs(on: pboard)
        guard !urls.isEmpty else {
            error.pointee = "No files were passed to Tama." as NSString
            return
        }
        URLSchemeHandler.add(urls.map { ShelfItem(url: $0) }, to: target)
    }

    @objc func extractText(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = fileURLs(on: pboard).filter(OCRService.canRead)
        guard !urls.isEmpty else {
            error.pointee = "Tama can read text from images and PDFs only." as NSString
            return
        }
        // Services expect a quick return; OCR finishes in the background and reports via a banner.
        Task { @MainActor in
            var texts: [String] = []
            for url in urls {
                if let result = try? await OCRService.recognize(url: url), !result.text.isEmpty {
                    texts.append(result.text)
                }
            }
            let state = AppState.shared
            guard !texts.isEmpty else {
                state.showNotification(appName: "OCR", title: "No text found",
                                       message: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files")
                return
            }
            let text = texts.joined(separator: "\n\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            DroppyAudio.playCopySuccess()
            let words = text.split(whereSeparator: \.isWhitespace).count
            state.showNotification(appName: "OCR", title: "Text copied",
                                   message: "\(words) words from \(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files")")
        }
    }

    @objc func sendToScratchpad(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "No text was passed to Tama." as NSString
            return
        }
        let state = AppState.shared
        NotesStore.shared.append(text)
        DroppyAudio.playDropSuccess()
        state.showNotification(appName: "Notes", title: "Added to Notes",
                               message: String(text.prefix(80)))
    }

    private func fileURLs(on pboard: NSPasteboard) -> [URL] {
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return urls
        }
        // Older senders still hand over the legacy filenames list only.
        let legacy = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        return (pboard.propertyList(forType: legacy) as? [String] ?? []).map { URL(fileURLWithPath: $0) }
    }
}
