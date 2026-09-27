import AppKit
import Quartz

/// Shows files in the system Quick Look panel, straight from Tama.
@MainActor
final class QuickLookService: NSObject, @preconcurrency QLPreviewPanelDataSource {
    static let shared = QuickLookService()

    private var urls: [URL] = []

    func preview(_ urls: [URL], startingAt index: Int = 0) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        NSApp.activate(ignoringOtherApps: true)
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = min(max(index, 0), urls.count - 1)
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls[index] as NSURL
    }
}
