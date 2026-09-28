import AppKit
import SwiftUI

/// One file uploaded with Quickshare, kept in the Recent Uploads list.
public struct QuickshareUpload: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var fileName: String
    public var link: String
    public var size: Int64
    public var date: Date
    /// When 0x0.st says the file goes away, if it said.
    public var expires: Date?
    /// 0x0.st's management token: lets Tama delete the file from the server.
    public var token: String?
}

/// Quickshare: uploads a file (several are zipped first) to 0x0.st, the
/// no-account file host, and copies the link. Files expire there on their own
/// (30 days to a year, depending on size). Every upload is listed under
/// Settings › General › Quick Actions › Recent Uploads, where its link can be
/// copied, and the file taken off the list or deleted from the server.
@MainActor
public final class QuickshareService: ObservableObject {
    public static let shared = QuickshareService()

    nonisolated static let endpoint = URL(string: "https://0x0.st")!
    /// 0x0.st's upload limit.
    nonisolated static let maxBytes: Int64 = 512 * 1024 * 1024
    private static let historyKey = "quickshareUploads"
    private static let activityID = "quickshare"

    @Published public private(set) var uploads: [QuickshareUpload] = []
    @Published public private(set) var isUploading = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.historyKey),
           let saved = try? JSONDecoder().decode([QuickshareUpload].self, from: data) {
            uploads = saved
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(uploads) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }

    // MARK: Upload

    /// Asks first when Settings says so, zips several files or a folder,
    /// uploads, and copies the link.
    public func upload(_ urls: [URL]) {
        let files = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !files.isEmpty else { return }
        guard ConnectivityService.shared.isOnline else {
            AppState.shared.showNotification(appName: "Quickshare", title: "No Internet Connection",
                                             message: "Connect to Wi-Fi, Ethernet, or Personal Hotspot to continue.",
                                             icon: "wifi.slash")
            return
        }
        guard !isUploading else {
            AppState.shared.showNotification(appName: "Quickshare", title: "Upload in progress",
                                             message: "Wait for the current upload to finish.", icon: "hourglass")
            return
        }
        if FileActionSettings.shared.quickshareConfirm, !confirm(files) {
            AppState.shared.showNotification(appName: "Quickshare", title: "Upload cancelled", message: "Nothing was uploaded.",
                                             icon: "xmark.circle")
            return
        }
        isUploading = true
        LiveActivityCenter.shared.post(LiveActivity(
            id: Self.activityID, icon: "link.icloud.fill", tint: DS.accent, trailing: .none,
            priority: .ambient, label: "Uploading to Quickshare…"
        ))
        Task { @MainActor in
            defer {
                isUploading = false
                LiveActivityCenter.shared.end(Self.activityID)
            }
            do {
                let payload = try await Self.preparePayload(files)
                defer { if payload.isTemporary { try? FileManager.default.removeItem(at: payload.url) } }
                let size = ShelfItem.size(of: payload.url)
                guard size <= Self.maxBytes else {
                    throw FileConverter.ConversionError("0x0.st takes files up to 512 MB; this is \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).")
                }
                let result = try await Self.post(payload.url)
                let upload = QuickshareUpload(id: UUID(), fileName: payload.url.lastPathComponent, link: result.link,
                                              size: size, date: Date(), expires: result.expires, token: result.token)
                uploads.insert(upload, at: 0)
                persist()
                ClipboardService.shared.copyToPasteboard(text: result.link)
                DroppyAudio.playCopySuccess()
                AppState.shared.showNotification(
                    appName: "Quickshare", title: "Link copied",
                    message: "\(payload.url.lastPathComponent) · \(result.link)",
                    icon: "link",
                    actionTitle: "Open", action: { if let url = URL(string: result.link) { NSWorkspace.shared.open(url) } }
                )
            } catch {
                AppState.shared.showNotification(appName: "Quickshare", title: "Upload failed",
                                                 message: error.localizedDescription, icon: "exclamationmark.triangle.fill")
            }
        }
    }

    /// Settings › Require upload confirmation.
    private func confirm(_ files: [URL]) -> Bool {
        let alert = NSAlert()
        alert.messageText = files.count == 1 ? "Upload \(files[0].lastPathComponent)?" : "Upload \(files.count) files?"
        alert.informativeText = "Quickshare puts \(files.count == 1 ? "it" : "them, zipped,") on 0x0.st and copies a link. Anyone with the link can download \(files.count == 1 ? "it" : "them") until the file expires (30 days to a year, depending on size)."
        alert.addButton(withTitle: "Upload")
        alert.addButton(withTitle: "Cancel")
        let state = AppState.shared
        state.setModal(true, owner: "quickshare.confirm")
        NSApp.activate(ignoringOtherApps: true)
        defer { state.setModal(false, owner: "quickshare.confirm") }
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Upload from Clipboard: whatever is on the pasteboard right now —
    /// the files themselves, an image written as a PNG, or the text as a
    /// `.txt` — goes up and the link is copied back.
    public func uploadFromClipboard() {
        let board = NSPasteboard.general
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            upload(urls)
            return
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tama Quickshare", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        if let image = NSImage(pasteboard: board),
           let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            let url = folder.appendingPathComponent("Clipboard \(stamp).png")
            guard (try? png.write(to: url)) != nil else { return }
            upload([url])
            return
        }
        let text = board.string(forType: .string) ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            AppState.shared.showNotification(appName: "Quickshare", title: "Nothing to upload",
                                             message: "Copy a file, an image or some text first.",
                                             icon: "doc.on.clipboard")
            return
        }
        let url = folder.appendingPathComponent("Clipboard \(stamp).txt")
        guard (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
        upload([url])
    }

    /// Select File to Upload…: a picker for the Settings page.
    public func chooseAndUpload() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = "Upload"
        panel.message = "Select File to Upload…"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        upload(panel.urls)
    }

    private struct Payload: Sendable {
        let url: URL
        let isTemporary: Bool
    }

    /// One file goes as it is; several files or a folder become one zip.
    nonisolated private static func preparePayload(_ files: [URL]) async throws -> Payload {
        var isDir: ObjCBool = false
        if files.count == 1, FileManager.default.fileExists(atPath: files[0].path, isDirectory: &isDir), !isDir.boolValue {
            return Payload(url: files[0], isTemporary: false)
        }
        return try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("Tama Quickshare/\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let name = files.count == 1 ? files[0].lastPathComponent : "Tama \(Int(Date().timeIntervalSince1970))"
            let staging = work.appendingPathComponent(name, isDirectory: true)
            if files.count == 1 {
                try fm.copyItem(at: files[0], to: staging)
            } else {
                try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                for file in files {
                    let destination = UniqueFileNamer.url(in: staging, base: file.deletingPathExtension().lastPathComponent,
                                                          ext: file.pathExtension) { fm.fileExists(atPath: $0.path) }
                    try fm.copyItem(at: file, to: destination)
                }
            }
            let zip = work.appendingPathComponent(name + ".zip")
            try FileConverter.run(URL(fileURLWithPath: "/usr/bin/ditto"),
                                  ["-c", "-k", "--sequesterRsrc", "--keepParent", staging.path, zip.path])
            try? fm.removeItem(at: staging)
            return Payload(url: zip, isTemporary: true)
        }.value
    }

    private struct PostResult: Sendable {
        let link: String
        let token: String?
        let expires: Date?
    }

    /// A multipart POST with a `file` field. `secret` asks for a longer,
    /// unguessable link.
    nonisolated private static func post(_ file: URL) async throws -> PostResult {
        let boundary = "Tama-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Tama/1.0 (macOS)", forHTTPHeaderField: "User-Agent")

        let body = FileManager.default.temporaryDirectory.appendingPathComponent("Tama Quickshare/\(UUID().uuidString).body")
        try FileManager.default.createDirectory(at: body.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: body) }
        FileManager.default.createFile(atPath: body.path, contents: nil)
        let handle = try FileHandle(forWritingTo: body)
        let filename = file.lastPathComponent.replacingOccurrences(of: "\"", with: "'")
        var head = "--\(boundary)\r\nContent-Disposition: form-data; name=\"secret\"\r\n\r\n\r\n"
        head += "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
        head += "Content-Type: application/octet-stream\r\n\r\n"
        try handle.write(contentsOf: Data(head.utf8))
        let source = try FileHandle(forReadingFrom: file)
        while let chunk = try source.read(upToCount: 1 << 20), !chunk.isEmpty {
            try handle.write(contentsOf: chunk)
        }
        try source.close()
        try handle.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        try handle.close()

        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: body)
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let http = response as? HTTPURLResponse else { throw FileConverter.ConversionError("No answer from 0x0.st.") }
        guard (200..<300).contains(http.statusCode), text.hasPrefix("http") else {
            let reason = text.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: http.statusCode) : String(text.prefix(160))
            throw FileConverter.ConversionError("0x0.st said: \(reason)")
        }
        let token = http.value(forHTTPHeaderField: "X-Token")
        // X-Expires is milliseconds since 1970.
        let expires = http.value(forHTTPHeaderField: "X-Expires").flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) }
        return PostResult(link: text, token: token, expires: expires)
    }

    // MARK: History

    public func copyLink(_ upload: QuickshareUpload) {
        ClipboardService.shared.copyToPasteboard(text: upload.link)
        DroppyAudio.playCopySuccess()
    }

    public func removeFromList(_ upload: QuickshareUpload) {
        uploads.removeAll { $0.id == upload.id }
        persist()
    }

    public func clearList() {
        uploads.removeAll()
        persist()
    }

    /// Deletes the file on 0x0.st with its token, then drops it from the list.
    public func deleteFromServer(_ upload: QuickshareUpload) {
        guard let token = upload.token, let url = URL(string: upload.link) else {
            removeFromList(upload)
            return
        }
        Task { @MainActor in
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("Tama/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
            request.httpBody = Data("token=\(token)&delete=".utf8)
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(status) || status == 404 else {
                    throw FileConverter.ConversionError("0x0.st answered \(status).")
                }
                removeFromList(upload)
                AppState.shared.showNotification(appName: "Quickshare", title: "Deleted", message: upload.fileName, icon: "trash")
            } catch {
                AppState.shared.showNotification(appName: "Quickshare", title: "Couldn't delete",
                                                 message: error.localizedDescription, icon: "exclamationmark.triangle.fill")
            }
        }
    }
}
