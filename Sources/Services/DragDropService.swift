import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
public final class DragDropService {
    public static let shared = DragDropService()

    /// What the Shelf, Basket and island accept: files, images and text, and
    /// any other item an app offers as a file promise (Mail messages, Photos
    /// originals), which SwiftUI hands over as a file representation.
    public static let acceptedTypes: [UTType] = [.fileURL, .image, .plainText, .item]

    private init() {}

    /// NSItemProvider isn't Sendable, but loading from it on its callback
    /// queues is what it's built for.
    private final class ProviderBox: @unchecked Sendable {
        let provider: NSItemProvider
        init(_ provider: NSItemProvider) { self.provider = provider }
    }

    /// Collects results from the providers' background callbacks, in drop order.
    private final class Results: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [Int: URL] = [:]
        private var failures: [String] = []
        func set(_ url: URL, at index: Int) { lock.lock(); urls[index] = url; lock.unlock() }
        func fail(_ types: [String]) { lock.lock(); failures += types; lock.unlock() }
        var ordered: [URL] { lock.lock(); defer { lock.unlock() }; return urls.sorted { $0.key < $1.key }.map(\.value) }
        var failedTypes: [String] { lock.lock(); defer { lock.unlock() }; return failures }
    }

    /// Files keep their URL. Promised files (Mail, Photos) are received into
    /// a temporary folder. Images and text dragged from apps that don't
    /// provide a file (a browser image, a text selection) are written to a
    /// temporary file so they can live in the tray too.
    public func handleDrop(providers: [NSItemProvider], completion: @escaping ([ShelfItem]) -> Void) {
        let results = Results()
        let group = DispatchGroup()

        for (index, provider) in providers.enumerated() {
            let types = provider.registeredTypeIdentifiers
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        results.set(url, at: index)
                    } else if let url = item as? URL {
                        results.set(url, at: index)
                    } else {
                        results.fail(types)
                    }
                }
            } else if let promised = Self.promisedFileType(of: provider) {
                // A file promise: ask for the file itself, with its own name.
                group.enter()
                let name = provider.suggestedName
                let box = ProviderBox(provider)
                provider.loadFileRepresentation(forTypeIdentifier: promised) { url, _ in
                    if let url, let kept = Self.copyToTemporary(url, suggestedName: name) {
                        results.set(kept, at: index)
                        group.leave()
                    } else if let imageType = Self.imageType(of: box.provider) {
                        // Some apps only hand over the image data.
                        box.provider.loadDataRepresentation(forTypeIdentifier: imageType.identifier) { data, _ in
                            defer { group.leave() }
                            let ext = imageType == .image ? "png" : (imageType.preferredFilenameExtension ?? "png")
                            if let data, let url = Self.writeTemporary(data, name: name ?? "Dropped Image", ext: ext) {
                                results.set(url, at: index)
                            } else {
                                results.fail(types)
                            }
                        }
                    } else {
                        results.fail(types)
                        group.leave()
                    }
                }
            } else if let imageType = Self.imageType(of: provider) {
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: imageType.identifier) { data, _ in
                    defer { group.leave() }
                    guard let data else { return results.fail(types) }
                    let ext = imageType == .image ? "png" : (imageType.preferredFilenameExtension ?? "png")
                    if let url = Self.writeTemporary(data, name: "Dropped Image", ext: ext) {
                        results.set(url, at: index)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    let text = (item as? String) ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
                    guard let text, !text.isEmpty else { return }
                    // A dragged link is still best kept as a .webloc-like text snippet.
                    let firstLine = text.split(separator: "\n").first.map(String.init) ?? ""
                    let trimmed = String(firstLine.prefix(40)).trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
                    let name = trimmed.isEmpty || trimmed.hasPrefix(".") ? "Text" : trimmed
                    if let url = Self.writeTemporary(Data(text.utf8), name: name, ext: "txt") {
                        results.set(url, at: index)
                    }
                }
            }
        }

        group.notify(queue: .main) {
            MainActor.assumeIsolated {
                let failed = results.failedTypes
                if !failed.isEmpty { Self.reportFailure(types: failed) }
            }
            completion(results.ordered.map { ShelfItem(url: $0) })
        }
    }

    /// Photos and Mail promise files rather than hand over a path; any
    /// provider that isn't plain text but has a data type is treated so.
    nonisolated private static func promisedFileType(of provider: NSItemProvider) -> String? {
        let types = provider.registeredTypeIdentifiers
        guard !provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                || types.contains(where: { $0.contains("mail") || $0.contains("photos") }) else { return nil }
        // Prefer the richest real file type: the original image, then any data.
        if let image = types.first(where: { UTType($0)?.conforms(to: .image) == true }) { return image }
        return types.first { id in
            guard let type = UTType(id) else { return false }
            return type.conforms(to: .data) || type.conforms(to: .package) || type.conforms(to: .content)
        }
    }

    nonisolated private static func imageType(of provider: NSItemProvider) -> UTType? {
        [UTType.png, .jpeg, .heic, .gif, .tiff, .image].first { provider.hasItemConformingToTypeIdentifier($0.identifier) }
    }

    /// Says which app's drag couldn't be received, in the reference's words.
    private static func reportFailure(types: [String]) {
        let joined = types.joined(separator: " ").lowercased()
        let message: String
        if joined.contains("mail") {
            message = "Could not export the selected email from Mail."
        } else if joined.contains("photos") || joined.contains("image") {
            message = "Could not receive file from Photos. Try exporting it to Finder first."
        } else {
            message = "The app didn't hand over the file. Tama needs to communicate with this app to export items when you drag."
        }
        AppState.shared.showNotification(appName: "Tama", title: "Drop failed", message: message,
                                         icon: "exclamationmark.triangle.fill")
    }

    /// A received promise lives only for its callback: copy it out.
    nonisolated private static func copyToTemporary(_ url: URL, suggestedName: String?) -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tama Drops/\(UUID().uuidString)", isDirectory: true)
        var name = url.lastPathComponent
        if let suggestedName, !suggestedName.isEmpty {
            let ext = url.pathExtension
            name = (suggestedName as NSString).pathExtension.isEmpty && !ext.isEmpty ? "\(suggestedName).\(ext)" : suggestedName
            name = name.replacingOccurrences(of: "/", with: "-")
        }
        let destination = dir.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    /// Each drop item gets a folder of its own: several images from one drop
    /// used to share a millisecond stamp and overwrite each other's file.
    nonisolated private static func writeTemporary(_ data: Data, name: String, ext: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tama Drops/\(UUID().uuidString)", isDirectory: true)
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let url = dir.appendingPathComponent("\(name) \(stamp)").appendingPathExtension(ext)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
