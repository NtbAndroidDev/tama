import AppKit

// "Share in a browser": the other half of LocalSend. Instead of pushing files
// at a device that runs the app, Tama holds them behind a plain web page on
// the same HTTP server, so anything with a browser can fetch them — a phone
// with nothing installed, a Windows PC, a TV. LocalSend's own clients find the
// same files through prepare-download, because the device announces
// `download: true` while an offer is live.

extension LocalSendService {

    // MARK: Starting and stopping an offer

    /// Offers everything staged. Returns false when there is nothing to offer.
    @discardableResult
    func startOffer() -> Bool {
        let files = LocalSendFormat.expand(staged)
        guard !files.isEmpty else { return false }
        let (infos, sources) = Self.describe(files)
        offer = Offer(id: LocalSendFormat.randomID(), files: infos, sources: sources)
        DroppyLog.info("LocalSend", "Offering \(infos.count) file(s) to browsers")
        // The flag rides on the announcement, so LocalSend clients list this
        // Mac as one they can pull from.
        announce()
        let address = offerURL.map { "Open \($0) on the other device." }
            ?? "This Mac isn't on a network, so nothing can reach the page."
        // The certificate is made on this Mac, so a browser will warn about it.
        // Say so here rather than leaving them at a scary page with no idea why.
        let https = LocalSendSettings.shared.isEncrypted
            ? " The browser will warn about the certificate; turn off Encrypted (HTTPS) in Settings to avoid it."
            : ""
        AppState.shared.showNotification(
            appName: "LocalSend", title: "Ready in a browser",
            message: address + https,
            icon: "safari.fill"
        )
        return true
    }

    func stopOffer() {
        guard offer != nil else { return }
        offer = nil
        DroppyLog.info("LocalSend", "Stopped offering files to browsers")
        announce()
    }

    /// What to type into the other device's browser.
    var offerURL: String? {
        guard let host = LANShareService.localIPv4Address() else { return nil }
        let scheme = LocalSendSettings.shared.isEncrypted ? "https" : "http"
        return "\(scheme)://\(host):\(LocalSendProtocol.port)"
    }

    // MARK: The API a LocalSend client uses

    func handlePrepareDownload(_ request: LocalSendHTTPServer.Request) -> LocalSendHTTPServer.Response {
        guard let offer else { return .status(403, "Nothing is being shared") }
        guard passesPIN(request) else { return .status(401, "PIN required") }
        return .json(LocalSendPrepareDownloadResponse(info: ownInfo(), sessionId: offer.id, files: offer.files))
    }

    func downloadReply(for request: LocalSendHTTPServer.Request) -> LocalSendHTTPServer.Reply {
        let query = LocalSendFormat.query(of: request.target)
        guard let offer else { return .respond(.status(403, "Nothing is being shared")) }
        guard passesPIN(request) else { return .respond(.status(401, "PIN required")) }
        guard let fileID = query["fileId"] else { return .respond(.status(400, "Missing parameters")) }
        // v2 quotes the session; the browser page links carry it too.
        if let sessionID = query["sessionId"], sessionID != offer.id {
            return .respond(.status(409, "That share has ended"))
        }
        guard let info = offer.files[fileID], let source = offer.sources[fileID] else {
            return .respond(.status(404, "No such file"))
        }
        guard FileManager.default.fileExists(atPath: source.path) else {
            return .respond(.status(410, "That file has moved or been deleted"))
        }
        return .sendFile(source, contentType: info.fileType, fileName: info.fileName,
                         finished: { complete in
            guard complete else { return }
            Task { @MainActor in LocalSendService.shared.noteFetched(fileID) }
        })
    }

    func noteFetched(_ fileID: String) {
        guard offer?.files[fileID] != nil else { return }
        offer?.fetched.insert(fileID)
    }

    /// The PIN guards downloads exactly as it guards uploads.
    private func passesPIN(_ request: LocalSendHTTPServer.Request) -> Bool {
        let pin = LocalSendSettings.shared.pin.trimmingCharacters(in: .whitespaces)
        guard !pin.isEmpty else { return true }
        return LocalSendFormat.query(of: request.target)["pin"] == pin
    }

    // MARK: The page a browser sees

    /// Anything that isn't the LocalSend API: the share page, or a polite 404.
    func browserReply(for request: LocalSendHTTPServer.Request) -> LocalSendHTTPServer.Reply {
        let path = LocalSendFormat.path(of: request.target)
        guard request.method == "GET" || request.method == "HEAD" else { return .respond(.status(405)) }
        switch path {
        case "", "/", "/index.html":
            return .respond(sharePage(query: LocalSendFormat.query(of: request.target)))
        case "/favicon.ico":
            return .respond(.status(404))
        default:
            return .respond(.status(404))
        }
    }

    private func sharePage(query: [String: String]) -> LocalSendHTTPServer.Response {
        let pin = LocalSendSettings.shared.pin.trimmingCharacters(in: .whitespaces)
        guard let offer else {
            return html(Self.page(title: "Nothing shared",
                                  body: "<p class=\"note\">\(Self.escape(deviceName)) isn’t sharing any files right now.</p>"))
        }
        if !pin.isEmpty, query["pin"] != pin {
            let wrong = query["pin"] != nil
            return html(Self.page(title: "PIN required", body: """
            <form method="get" action="/">
              <p class="note">\(wrong ? "That PIN wasn’t right." : "Type the PIN shown on \(Self.escape(deviceName)).")</p>
              <input class="pin" name="pin" inputmode="numeric" autocomplete="one-time-code" autofocus placeholder="PIN">
              <button class="go" type="submit">Continue</button>
            </form>
            """), status: wrong ? 403 : 401)
        }
        let suffix = pin.isEmpty ? "" : "&pin=\(pin.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? pin)"
        let rows = offer.sorted.map { file in
            let href = "/api/localsend/v2/download?sessionId=\(offer.id)&fileId=\(file.id)\(suffix)"
            return """
            <li><a href="\(href)" download>
              <span class="name">\(Self.escape(file.fileName))</span>
              <span class="size">\(Self.readable(file.size))</span>
            </a></li>
            """
        }.joined(separator: "\n")
        let count = offer.files.count
        return html(Self.page(title: Self.escape(deviceName), body: """
        <p class="note">\(count) file\(count == 1 ? "" : "s") · \(Self.readable(offer.totalBytes))</p>
        <ul class="files">\(rows)</ul>
        """))
    }

    private func html(_ body: String, status: Int = 200) -> LocalSendHTTPServer.Response {
        LocalSendHTTPServer.Response(status: status, body: Data(body.utf8),
                                     contentType: "text/html; charset=utf-8",
                                     headers: ["Cache-Control": "no-store"])
    }

    // MARK: Page rendering

    /// One self-contained page: no scripts, no fetched assets, and it reads on
    /// a phone. It follows the browser's own light/dark setting.
    nonisolated static func page(title: String, body: String) -> String {
        """
        <!DOCTYPE html><html lang="en"><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>\(title)</title>
        <style>
        :root { --bg:#f5f5f7; --card:#fff; --text:#111; --muted:#6b6b70; --line:#e3e3e8; --accent:#0a84ff; }
        @media (prefers-color-scheme: dark) {
          :root { --bg:#131316; --card:#1d1d21; --text:#f2f2f5; --muted:#9a9aa2; --line:#2c2c32; }
        }
        * { box-sizing: border-box; }
        body { margin:0; padding:24px 16px 48px; background:var(--bg); color:var(--text);
               font:16px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
        main { max-width:640px; margin:0 auto; }
        h1 { font-size:22px; margin:0 0 4px; }
        .note { color:var(--muted); margin:0 0 20px; font-size:14px; }
        ul.files { list-style:none; margin:0; padding:0; border:1px solid var(--line);
                   border-radius:14px; overflow:hidden; background:var(--card); }
        ul.files li + li { border-top:1px solid var(--line); }
        ul.files a { display:flex; gap:12px; align-items:center; justify-content:space-between;
                     padding:14px 16px; text-decoration:none; color:inherit; }
        ul.files a:active { background:var(--line); }
        .name { overflow-wrap:anywhere; }
        .size { color:var(--muted); font-size:13px; white-space:nowrap; }
        .pin { font-size:17px; padding:12px 14px; border-radius:10px; border:1px solid var(--line);
               background:var(--card); color:var(--text); width:140px; }
        .go { font-size:17px; padding:12px 18px; margin-left:8px; border:0; border-radius:10px;
              background:var(--accent); color:#fff; }
        footer { margin-top:24px; color:var(--muted); font-size:12px; text-align:center; }
        </style></head><body><main>
        <h1>\(title)</h1>
        \(body)
        <footer>Shared from Tama</footer>
        </main></body></html>
        """
    }

    nonisolated static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    nonisolated static func readable(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
