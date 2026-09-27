import AppKit
import WebKit

/// Loads an HTML file or web archive in an offscreen WebKit view and prints
/// it to PDF data, so styles and images survive the conversion.
@MainActor
final class WebPagePDFRenderer: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Error>?
    private static var active: Set<WebPagePDFRenderer> = []

    static func render(_ url: URL) async throws -> Data {
        let renderer = WebPagePDFRenderer()
        active.insert(renderer)
        defer { active.remove(renderer) }
        return try await renderer.run(url)
    }

    private func run(_ url: URL) async throws -> Data {
        let config = WKWebViewConfiguration()
        // Local pages only: nothing is fetched to lay them out beyond what they reference.
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 816, height: 1056), configuration: config)
        view.navigationDelegate = self
        webView = view
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            continuation = cont
            if url.pathExtension.lowercased() == "webarchive", let data = try? Data(contentsOf: url) {
                view.load(data, mimeType: "application/x-webarchive", characterEncodingName: "utf-8", baseURL: url)
            } else {
                view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            }
        }
        // Let late layout (fonts, images) settle.
        try await Task.sleep(for: .milliseconds(300))
        let config2 = WKPDFConfiguration()
        let data: Data = try await withCheckedThrowingContinuation { cont in
            view.createPDF(configuration: config2) { result in
                cont.resume(with: result)
            }
        }
        webView = nil
        return data
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: FileConverter.ConversionError("Couldn't load the page: \(error.localizedDescription)"))
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: FileConverter.ConversionError("Couldn't load the page: \(error.localizedDescription)"))
        continuation = nil
    }
}
