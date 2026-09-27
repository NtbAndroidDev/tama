import AppKit
import AVFoundation
import ImageIO
import PDFKit
import Quartz
import UniformTypeIdentifiers

/// Compress › Low / Medium / High for images, PDFs and videos, and Video
/// Target Size. Every result goes through the Size Guard: a "compressed" file
/// that isn't smaller than the original is thrown away.
public enum FileCompressor {
    public enum Kind: Sendable { case image, pdf, video }

    public static func kind(of url: URL) -> Kind? {
        switch FileConversionMatrix.kind(forExtension: url.pathExtension) {
        case .image: return url.pathExtension.lowercased() == "gif" ? nil : .image
        case .pdf: return .pdf
        case .video: return .video
        default: return nil
        }
    }

    public static func canCompress(_ url: URL) -> Bool { kind(of: url) != nil }

    static func outputURL(for source: URL, ext: String? = nil) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Tama Compressed/\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(source.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(ext ?? source.pathExtension)
    }

    /// Compresses one file into a new one next to nothing the user owns (the
    /// temporary folder); the original is never touched.
    public static func compress(_ url: URL, level: CompressionLevel,
                                progress: FileConverter.Progress? = nil) async throws -> URL {
        guard let kind = kind(of: url) else { throw FileConverter.ConversionError("\(url.lastPathComponent) can't be compressed.") }
        let output: URL
        switch kind {
        case .image:
            output = try await Task.detached(priority: .userInitiated) { try compressImage(url, level: level) }.value
        case .pdf:
            output = try await Task.detached(priority: .userInitiated) { try compressPDF(url, level: level) }.value
        case .video:
            output = try await compressVideo(url, level: level, progress: progress)
        }
        try sizeGuard(original: url, result: output)
        return output
    }

    /// Size Guard: no bigger than the input, or it's discarded.
    static func sizeGuard(original: URL, result: URL) throws {
        let before = ShelfItem.size(of: original)
        let after = ShelfItem.size(of: result)
        guard after > 0, after < before else {
            try? FileManager.default.removeItem(at: result.deletingLastPathComponent())
            throw FileConverter.ConversionError("Compression failed or no size reduction (Size Guard)")
        }
    }

    // MARK: Images

    /// Re-encodes in the same format at a lower quality, scaling large
    /// images down. PNG stays lossless, so only the scaling shrinks it.
    static func compressImage(_ url: URL, level: CompressionLevel) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source) else {
            throw FileConverter.ConversionError("Couldn't read \(url.lastPathComponent).")
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let longest = max(width, height)
        let image: CGImage?
        if let limit = level.imageMaxPixels, longest > limit {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: limit,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image else { throw FileConverter.ConversionError("Couldn't decode \(url.lastPathComponent).") }
        // Formats ImageIO can't write lossy (TIFF, BMP…) become JPEG.
        let lossy: Set<String> = [UTType.jpeg.identifier, UTType.heic.identifier, "public.heif"]
        let isPNG = (type as String) == UTType.png.identifier
        let outType: String = lossy.contains(type as String) || isPNG ? type as String : UTType.jpeg.identifier
        let ext = UTType(outType)?.preferredFilenameExtension ?? "jpg"
        let output = outputURL(for: url, ext: outType == type as String ? url.pathExtension : ext)
        guard let dest = CGImageDestinationCreateWithURL(output as CFURL, outType as CFString, 1, nil) else {
            throw FileConverter.ConversionError("Can't write \(ext.uppercased()) on this Mac.")
        }
        var options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: level.imageQuality]
        // Keep orientation only when the pixels weren't already rotated by the thumbnail.
        if level.imageMaxPixels == nil || longest <= (level.imageMaxPixels ?? 0),
           let orientation = props[kCGImagePropertyOrientation] {
            options[kCGImagePropertyOrientation] = orientation
        }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw FileConverter.ConversionError("Couldn't write the image.") }
        return output
    }

    // MARK: PDF

    /// Ghostscript when installed (deep compression); otherwise Quartz: the
    /// system's Reduce File Size filter for Low, JPEG images downsampled for
    /// screen for Medium, JPEG images for High.
    static func compressPDF(_ url: URL, level: CompressionLevel) throws -> URL {
        let output = outputURL(for: url, ext: "pdf")
        if let gs = HomebrewHelper.path(of: .ghostscript) {
            try FileConverter.run(gs, [
                "-sDEVICE=pdfwrite", "-dCompatibilityLevel=1.5", "-dPDFSETTINGS=\(level.ghostscriptPreset)",
                "-dNOPAUSE", "-dQUIET", "-dBATCH", "-sOutputFile=\(output.path)", url.path,
            ])
            return output
        }
        guard let doc = PDFDocument(url: url) else { throw FileConverter.ConversionError("Couldn't open \(url.lastPathComponent).") }
        var options: [PDFDocumentWriteOption: Any] = [:]
        switch level {
        case .low:
            let filterURL = URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter")
            if let filter = QuartzFilter(url: filterURL) {
                options[PDFDocumentWriteOption(rawValue: "QuartzFilter")] = filter
            } else {
                options[.saveImagesAsJPEGOption] = true
                options[.optimizeImagesForScreenOption] = true
            }
        case .medium:
            options[.saveImagesAsJPEGOption] = true
            options[.optimizeImagesForScreenOption] = true
        case .high:
            options[.saveImagesAsJPEGOption] = true
        }
        guard doc.write(to: output, withOptions: options) else {
            throw FileConverter.ConversionError("Couldn't write the compressed PDF.")
        }
        return output
    }

    // MARK: Video

    private final class ExportBox: @unchecked Sendable {
        let session: AVAssetExportSession
        init(_ session: AVAssetExportSession) { self.session = session }
    }

    /// AVFoundation presets: Low 960×540, Medium 1280×720, High HEVC 1080p.
    static func compressVideo(_ url: URL, level: CompressionLevel, progress: FileConverter.Progress?) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let preset: String
        switch level {
        case .low: preset = AVAssetExportPreset960x540
        case .medium: preset = AVAssetExportPreset1280x720
        case .high: preset = AVAssetExportPresetHEVC1920x1080
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw FileConverter.ConversionError("This video can't be compressed.")
        }
        let fileType: AVFileType = session.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
        let output = outputURL(for: url, ext: fileType == .mp4 ? "mp4" : "mov")
        session.outputURL = output
        session.outputFileType = fileType
        session.shouldOptimizeForNetworkUse = true
        let box = ExportBox(session)
        await withTaskCancellationHandler {
            let poller = progress.map { report in
                Task.detached {
                    while !Task.isCancelled {
                        report(Double(box.session.progress))
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                }
            }
            defer { poller?.cancel() }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                box.session.exportAsynchronously { cont.resume() }
            }
        } onCancel: {
            box.session.cancelExport()
        }
        if box.session.status == .cancelled || Task.isCancelled {
            try? FileManager.default.removeItem(at: output)
            throw CancellationError()
        }
        guard box.session.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw FileConverter.ConversionError(box.session.error?.localizedDescription ?? "Export failed.")
        }
        return output
    }

    /// Video Target Size: two FFmpeg passes at the bitrate that lands the
    /// file on `megabytes` (audio kept at 128 kb/s, or dropped when the
    /// budget is too small for it).
    public static func compressVideo(_ url: URL, toMegabytes megabytes: Double,
                                     progress: FileConverter.Progress? = nil) async throws -> URL {
        guard let ffmpeg = HomebrewHelper.path(of: .ffmpeg) else {
            throw FileConverter.ConversionError("Video Target Size needs FFmpeg.")
        }
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(try await asset.load(.duration))
        guard seconds.isFinite, seconds > 0.5 else { throw FileConverter.ConversionError("This file has no video.") }
        let hasAudio = !(try await asset.loadTracks(withMediaType: .audio)).isEmpty
        // 3% for the container.
        let totalKbps = megabytes * 8 * 1024 * 0.97 / seconds
        var audioKbps = hasAudio ? 128.0 : 0
        if totalKbps - audioKbps < 150 { audioKbps = hasAudio && totalKbps > 200 ? 64 : 0 }
        let videoKbps = Int(totalKbps - audioKbps)
        guard videoKbps >= 50 else {
            throw FileConverter.ConversionError("\(Int(megabytes)) MB is too small for \(Int(seconds)) s of video.")
        }
        let output = outputURL(for: url, ext: "mp4")
        let work = output.deletingLastPathComponent()
        let passLog = work.appendingPathComponent("ffmpeg2pass").path
        let common = ["-y", "-hide_banner", "-loglevel", "error", "-i", url.path,
                      "-c:v", "libx264", "-preset", "medium", "-b:v", "\(videoKbps)k", "-passlogfile", passLog]
        progress?(0.05)
        try await Task.detached(priority: .userInitiated) {
            try FileConverter.run(ffmpeg, common + ["-pass", "1", "-an", "-f", "mp4", "/dev/null"])
        }.value
        progress?(0.5)
        let audio = audioKbps > 0 ? ["-c:a", "aac", "-b:a", "\(Int(audioKbps))k"] : ["-an"]
        try await Task.detached(priority: .userInitiated) {
            try FileConverter.run(ffmpeg, common + ["-pass", "2"] + audio + ["-movflags", "+faststart", output.path])
        }.value
        progress?(1)
        for file in (try? FileManager.default.contentsOfDirectory(atPath: work.path)) ?? [] where file.hasPrefix("ffmpeg2pass") {
            try? FileManager.default.removeItem(atPath: work.appendingPathComponent(file).path)
        }
        try sizeGuard(original: url, result: output)
        return output
    }
}

// MARK: - Shelf glue

@MainActor
public enum CompressActions {
    /// Compresses each file as one job. A compressed file takes the original's
    /// place on the Shelf or in the Basket (the original stays on disk), or
    /// lands in Smart Export's Compressed folder.
    public static func compress(_ items: [ShelfItem], level: CompressionLevel) {
        let targets = items.filter { FileCompressor.canCompress($0.url) }
        guard !targets.isEmpty else {
            AppState.shared.showNotification(appName: "Compress", title: "Can't compress these",
                                             message: "Compress works on images, PDFs and videos.", icon: "arrow.down.right.and.arrow.up.left")
            return
        }
        let pairs = targets.map { ($0.id, $0.url) }
        let title = targets.count == 1 ? "Compressing \(targets[0].name)" : "Compressing \(targets.count) files"
        JobCenter.shared.run(
            title: title,
            appName: "Compress",
            failureTitle: "Compression Failed",
            operation: { progress in
                var results: [(UUID, URL, URL)] = []
                var failures: [String] = []
                for (index, pair) in pairs.enumerated() {
                    try Task.checkCancellation()
                    do {
                        let out = try await FileCompressor.compress(pair.1, level: level) { fraction in
                            progress.report((Double(index) + fraction) / Double(pairs.count))
                        }
                        results.append((pair.0, pair.1, out))
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        failures.append(error.localizedDescription)
                    }
                }
                guard !results.isEmpty else {
                    throw FileConverter.ConversionError(failures.first ?? "Nothing was compressed.")
                }
                return CompressBatch(results: results.map { CompressBatch.Entry(id: $0.0, original: $0.1, output: $0.2) },
                                     failures: failures.count)
            },
            onSuccess: { batch in finish(batch) }
        )
    }

    struct CompressBatch: Sendable {
        struct Entry: Sendable {
            let id: UUID
            let original: URL
            let output: URL
        }
        let results: [Entry]
        let failures: Int
    }

    private static func finish(_ batch: CompressBatch) -> JobCenter.Banner {
        let state = AppState.shared
        var saved: Int64 = 0
        var finalURLs: [URL] = []
        for entry in batch.results {
            saved += ShelfItem.size(of: entry.original) - ShelfItem.size(of: entry.output)
            let routed = SmartExport.route(entry.output, kind: .compressed)
            finalURLs.append(routed)
            if var item = state.heldItems([entry.id]).first {
                let replacement = item.moved(to: routed)
                item = replacement
                state.replaceHeldItem(entry.id, with: [item])
            }
        }
        DroppyAudio.playDropSuccess()
        let urls = finalURLs
        let failed = batch.failures > 0 ? " · \(batch.failures) not smaller" : ""
        return JobCenter.Banner(
            title: "Compressed",
            message: "Saved \(ByteCountFormatter.string(fromByteCount: max(saved, 0), countStyle: .file))\(failed)",
            actionTitle: "Show in Finder",
            action: { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        )
    }

    /// Video Target Size: the dialog, then a two-pass FFmpeg job.
    public static func compressToTargetSize(_ item: ShelfItem) {
        guard HomebrewHelper.shared.require(.ffmpeg, for: "Video Target Size") else { return }
        guard let megabytes = TargetSizeDialog.run(for: item) else { return }
        let id = item.id, url = item.url
        JobCenter.shared.run(
            title: "\(item.name) → \(Int(megabytes)) MB",
            appName: "Compress",
            failureTitle: "Compression Failed",
            operation: { progress in
                try await FileCompressor.compressVideo(url, toMegabytes: megabytes) { progress.report($0) }
            },
            onSuccess: { output in
                finish(CompressBatch(results: [.init(id: id, original: url, output: output)], failures: 0))
            }
        )
    }
}
