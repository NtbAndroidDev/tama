import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Image clips live as PNGs in `~/Library/Application Support/Tama/Clipboard`;
/// the clip itself only stores the filename. Everything here is synchronous and
/// meant to be called off the main thread.
enum ClipboardImageStore {
    static let maxPixelSize = 2048

    struct Encoded: Sendable {
        let png: Data
        let hash: String
    }

    /// Just the path: cards and thumbnails ask for URLs on every render, so
    /// the folder is only created where a PNG is written (`write`), which also
    /// brings it back after Settings › Reset deleted it.
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Tama/Clipboard", isDirectory: true)
    }

    static func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    /// Re-encodes pasteboard image data (PNG or TIFF) as PNG, no larger than
    /// `maxPixelSize` on the long edge, and hashes the result for de-duplication.
    static func encode(_ data: Data) -> Encoded? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let image: CGImage?
        if max(width, height) > maxPixelSize {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        let png = out as Data
        let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        return Encoded(png: png, hash: hash)
    }

    static func write(_ png: Data, filename: String) -> Bool {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (try? png.write(to: url(for: filename), options: .atomic)) != nil
    }

    /// Deletes stored PNGs no clip points at. Files younger than a minute are
    /// kept: they may belong to a capture that hasn't reached the history yet.
    static func removeOrphans(keeping referenced: Set<String>) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-60)
        for file in files where file.pathExtension == "png" && !referenced.contains(file.lastPathComponent) {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if modified < cutoff { try? fm.removeItem(at: file) }
        }
    }

    /// On-device OCR so screenshots can be found by the words in them.
    static func recognizeText(in filename: String) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let wanted = ["vi-VN", "en-US"].filter(supported.contains)
        if !wanted.isEmpty { request.recognitionLanguages = wanted }
        let handler = VNImageRequestHandler(url: url(for: filename), options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
