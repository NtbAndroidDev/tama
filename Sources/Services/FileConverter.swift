import AppKit
import AVFoundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// On-device file conversion: ImageIO for images, PDFKit for PDFs,
/// AVFoundation for video and audio, `textutil` + AppKit for text documents.
/// Every conversion writes real files and returns their URLs.
public enum FileConverter {

    public enum Quality: String, CaseIterable, Sendable {
        case lossless = "Lossless"
        case high = "High (85%)"
        case compact = "Compact (60%)"

        var compression: Double {
            switch self {
            case .lossless: return 1.0
            case .high: return 0.85
            case .compact: return 0.6
            }
        }

        var videoPreset: String {
            switch self {
            case .lossless: return AVAssetExportPresetHighestQuality
            case .high: return AVAssetExportPreset1920x1080
            case .compact: return AVAssetExportPresetMediumQuality
            }
        }
    }

    public enum Kind: Sendable { case image, pdf, video, audio, document, unsupported }

    public struct ConversionError: LocalizedError, Sendable {
        public let message: String
        public var errorDescription: String? { message }
        init(_ message: String) { self.message = message }
    }

    // MARK: Capabilities

    public static func kind(of url: URL) -> Kind {
        FileConversionMatrix.kind(forExtension: url.pathExtension)
    }

    /// Formats a file of this kind can be turned into, in display order.
    public static func targets(for kind: Kind) -> [String] {
        FileConversionMatrix.targets(for: kind, webpAvailable: webpAvailable)
    }

    public static func targets(for url: URL) -> [String] {
        // Word, Excel, PowerPoint and Keynote-era files: PDF through LibreOffice.
        if kind(of: url) == .unsupported, isOfficeFile(url), libreOfficeURL != nil { return ["PDF"] }
        return targets(for: kind(of: url))
    }

    /// Office files NSAttributedString can't read.
    static let officeExtensions: Set<String> = ["xlsx", "xls", "pptx", "ppt", "odp", "ods", "pages", "numbers", "key"]

    static func isOfficeFile(_ url: URL) -> Bool {
        officeExtensions.contains(url.pathExtension.lowercased())
    }

    static var libreOfficeURL: URL? { HomebrewHelper.path(of: .libreoffice) }

    /// ImageIO writes WebP on systems that ship an encoder; otherwise cwebp.
    static var imageIOWritesWebP: Bool {
        ((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []).contains("org.webmproject.webp")
    }

    static var webpAvailable: Bool { imageIOWritesWebP || cwebpURL != nil }

    /// Formats offered for a whole selection: those every convertible item supports.
    public static func commonTargets(for urls: [URL]) -> [String] {
        FileConversionMatrix.common(urls.map { targets(for: $0) })
    }

    /// Homebrew's `cwebp`, for systems without a WebP encoder (checked each
    /// time, so installing it from Settings works straight away).
    static var cwebpURL: URL? { HomebrewHelper.path(of: .webp) }

    // MARK: Entry point

    /// Reports 0…1 for this one file. Called from background threads.
    public typealias Progress = @Sendable (Double) -> Void

    /// Honors task cancellation: a cancelled conversion throws
    /// `CancellationError` and leaves no partial output behind.
    public static func convert(_ url: URL, to format: String, quality: Quality = .high,
                               progress: Progress? = nil) async throws -> [URL] {
        let target = format.uppercased()
        try Task.checkCancellation()
        switch kind(of: url) {
        case .image:
            return [try await detached { try convertImage(url, to: target, quality: quality) }]
        case .pdf:
            return try await detached { try convertPDF(url, to: target, quality: quality, progress: progress) }
        case .video, .audio:
            if target == "GIF" {
                let duration = CMTimeGetSeconds(try await AVURLAsset(url: url).load(.duration))
                return [try await detached { try videoToGIF(url, duration: duration, quality: quality, progress: progress) }]
            }
            return [try await exportMedia(url, to: target, quality: quality, progress: progress)]
        case .document:
            return [try await convertDocument(url, to: target)]
        case .unsupported:
            if target == "PDF", isOfficeFile(url) {
                return [try await detached { try libreOfficeToPDF(url) }]
            }
            throw ConversionError("\(url.lastPathComponent) can't be converted.")
        }
    }

    /// Detached tasks don't inherit cancellation, so forward it by hand;
    /// the work checks `Task.isCancelled` between frames/pages.
    private static func detached<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        let task = Task.detached(priority: .userInitiated, operation: work)
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Deletes whatever a failed or cancelled conversion managed to write.
    static func removePartial(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: Output

    static func outputURL(for source: URL, ext: String, suffix: String = "") -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Tama Converted", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = source.deletingPathExtension().lastPathComponent + suffix
        return UniqueFileNamer.url(in: dir, base: base, ext: ext) { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: Images

    private static func imageUTType(_ format: String) -> UTType? {
        switch format {
        case "PNG": return .png
        case "JPEG", "JPG": return .jpeg
        case "HEIC": return .heic
        case "GIF": return .gif
        case "TIFF": return .tiff
        default: return nil
        }
    }

    static func convertImage(_ url: URL, to format: String, quality: Quality) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let first = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ConversionError("Couldn't read \(url.lastPathComponent).")
        }

        switch format {
        case "PDF":
            let output = outputURL(for: url, ext: "pdf")
            let image = NSImage(cgImage: first, size: NSSize(width: first.width, height: first.height))
            guard let page = PDFPage(image: image) else { throw ConversionError("Couldn't build a PDF page.") }
            let doc = PDFDocument()
            doc.insert(page, at: 0)
            guard doc.write(to: output) else {
                removePartial([output])
                throw ConversionError("Couldn't write the PDF.")
            }
            return output

        case "WEBP" where imageIOWritesWebP:
            let output = outputURL(for: url, ext: "webp")
            guard let dest = CGImageDestinationCreateWithURL(output as CFURL, "org.webmproject.webp" as CFString, 1, nil) else {
                throw ConversionError("Can't encode WebP on this Mac.")
            }
            CGImageDestinationAddImage(dest, first, [kCGImageDestinationLossyCompressionQuality: quality.compression] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else {
                removePartial([output])
                throw ConversionError("Couldn't write WebP.")
            }
            return output

        case "WEBP":
            guard let cwebp = cwebpURL else { throw ConversionError("WebP needs cwebp: install WebP tools in Settings › General › Helper tools.") }
            let png = try convertImage(url, to: "PNG", quality: .lossless)
            defer { try? FileManager.default.removeItem(at: png) }
            let output = outputURL(for: url, ext: "webp")
            var args = [png.path, "-o", output.path, "-quiet"]
            args += quality == .lossless ? ["-lossless"] : ["-q", String(Int(quality.compression * 100))]
            do { try run(cwebp, args) } catch { removePartial([output]); throw error }
            return output

        default:
            guard let type = imageUTType(format) else { throw ConversionError("Unsupported format \(format).") }
            let output = outputURL(for: url, ext: type.preferredFilenameExtension ?? format.lowercased())
            // Keep every frame when both ends support animation (GIF → GIF, HEICS…).
            let frameCount = type == .gif ? CGImageSourceGetCount(source) : 1
            guard let dest = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, frameCount, nil) else {
                throw ConversionError("Can't encode \(format) on this Mac.")
            }
            var props: [CFString: Any] = [:]
            if type == .jpeg || type == .heic {
                props[kCGImageDestinationLossyCompressionQuality] = quality.compression
            }
            if frameCount > 1 {
                CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
                for i in 0..<frameCount {
                    let frameProps = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any] ?? [:]
                    var merged = props
                    if let gif = frameProps[kCGImagePropertyGIFDictionary] { merged[kCGImagePropertyGIFDictionary] = gif }
                    CGImageDestinationAddImageFromSource(dest, source, i, merged as CFDictionary)
                }
            } else {
                // Carry orientation / colour metadata across.
                if let meta = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                    for key in [kCGImagePropertyOrientation, kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
                        if let value = meta[key] { props[key] = value }
                    }
                }
                CGImageDestinationAddImage(dest, first, props as CFDictionary)
            }
            guard CGImageDestinationFinalize(dest) else {
                removePartial([output])
                throw ConversionError("Couldn't write \(format).")
            }
            return output
        }
    }

    // MARK: PDF

    static func convertPDF(_ url: URL, to format: String, quality: Quality, progress: Progress? = nil) throws -> [URL] {
        guard let doc = PDFDocument(url: url) else { throw ConversionError("Couldn't open \(url.lastPathComponent).") }

        if format == "TXT" {
            let output = outputURL(for: url, ext: "txt")
            try (doc.string ?? "").write(to: output, atomically: true, encoding: .utf8)
            progress?(1)
            return [output]
        }

        guard let type = imageUTType(format) else { throw ConversionError("Unsupported format \(format).") }
        let scale: CGFloat = quality == .compact ? 1.5 : 2.0
        let pageCount = min(doc.pageCount, 100)
        var outputs: [URL] = []
        for index in 0..<pageCount {
            if Task.isCancelled {
                removePartial(outputs)
                throw CancellationError()
            }
            defer { progress?(Double(index + 1) / Double(pageCount)) }
            guard let page = doc.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.setFillColor(.white)
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: ctx)
            guard let image = ctx.makeImage() else { continue }

            let suffix = pageCount > 1 ? " – page \(index + 1)" : ""
            let output = outputURL(for: url, ext: type.preferredFilenameExtension ?? "png", suffix: suffix)
            guard let dest = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality.compression] as CFDictionary)
            if CGImageDestinationFinalize(dest) { outputs.append(output) }
        }
        guard !outputs.isEmpty else { throw ConversionError("Couldn't render any pages.") }
        return outputs
    }

    // MARK: Video & audio

    private final class ExportBox: @unchecked Sendable {
        let session: AVAssetExportSession
        init(_ session: AVAssetExportSession) { self.session = session }
    }

    static func exportMedia(_ url: URL, to format: String, quality: Quality, progress: Progress? = nil) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let preset: String
        let fileType: AVFileType
        let ext: String
        switch format {
        case "WAV":
            // afconvert ships with macOS: 16-bit little-endian PCM.
            let output = outputURL(for: url, ext: "wav")
            do {
                try await detached {
                    try run(URL(fileURLWithPath: "/usr/bin/afconvert"), ["-f", "WAVE", "-d", "LEI16", url.path, output.path])
                }
            } catch {
                removePartial([output])
                throw error
            }
            progress?(1)
            return output
        case "MP4": preset = quality.videoPreset; fileType = .mp4; ext = "mp4"
        case "MOV": preset = quality.videoPreset; fileType = .mov; ext = "mov"
        case "M4A": preset = AVAssetExportPresetAppleM4A; fileType = .m4a; ext = "m4a"
        default: throw ConversionError("Unsupported format \(format).")
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ConversionError("This file can't be exported as \(format).")
        }
        let output = outputURL(for: url, ext: ext)
        session.outputURL = output
        session.outputFileType = fileType
        session.shouldOptimizeForNetworkUse = true

        let box = ExportBox(session)
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            // The session has no progress callback; poll it while it runs.
            let poller = progress.map { report in
                Task.detached {
                    while !Task.isCancelled {
                        report(Double(box.session.progress))
                        try? await Task.sleep(for: .milliseconds(200))
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
            removePartial([output])
            throw CancellationError()
        }
        guard box.session.status == .completed else {
            removePartial([output])
            throw ConversionError(box.session.error?.localizedDescription ?? "Export failed.")
        }
        progress?(1)
        return output
    }

    /// Up to 15 s of video at 10 fps, scaled to fit the quality's width.
    static func videoToGIF(_ url: URL, duration: Double, quality: Quality, progress: Progress? = nil) throws -> URL {
        let asset = AVURLAsset(url: url)
        guard duration.isFinite, duration > 0 else { throw ConversionError("This file has no video.") }

        let fps = 10.0
        let length = min(duration, 15)
        let frameCount = max(1, Int(length * fps))
        let maxWidth: CGFloat = quality == .compact ? 320 : (quality == .high ? 480 : 720)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxWidth, height: maxWidth * 4)
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 20)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 20)

        let output = outputURL(for: url, ext: "gif")
        guard let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
            throw ConversionError("Can't encode GIF.")
        }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps]] as CFDictionary
        var written = 0
        for i in 0..<frameCount {
            if Task.isCancelled {
                removePartial([output])
                throw CancellationError()
            }
            progress?(Double(i) / Double(frameCount))
            let time = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
            guard let frame = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
            CGImageDestinationAddImage(dest, frame, frameProps)
            written += 1
        }
        guard written > 0, CGImageDestinationFinalize(dest) else {
            removePartial([output])
            throw ConversionError("Couldn't read video frames.")
        }
        return output
    }

    // MARK: Documents

    static func convertDocument(_ url: URL, to format: String) async throws -> URL {
        if format == "PDF" {
            let ext = url.pathExtension.lowercased()
            if ["html", "htm", "webarchive", "xhtml"].contains(ext) { return try await webPageToPDF(url) }
            // LibreOffice keeps Word layouts (tables, headers) that AppKit's reader flattens.
            if ["doc", "docx", "odt"].contains(ext), libreOfficeURL != nil {
                return try await detached { try libreOfficeToPDF(url) }
            }
            return try await documentToPDF(url)
        }
        let ext: String
        switch format {
        case "TXT": ext = "txt"
        case "RTF": ext = "rtf"
        case "HTML": ext = "html"
        case "DOCX": ext = "docx"
        default: throw ConversionError("Unsupported format \(format).")
        }
        let output = outputURL(for: url, ext: ext)
        do {
            try await detached {
                try run(URL(fileURLWithPath: "/usr/bin/textutil"),
                        ["-convert", ext, url.path, "-output", output.path])
            }
        } catch {
            removePartial([output])
            throw error
        }
        return output
    }

    /// Lays the document out on US-Letter pages with AppKit's print system.
    @MainActor
    static func documentToPDF(_ url: URL) async throws -> URL {
        let text: NSAttributedString
        do {
            text = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        } catch {
            throw ConversionError("Couldn't read \(url.lastPathComponent).")
        }
        let output = outputURL(for: url, ext: "pdf")

        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 612, height: 792)
        info.topMargin = 54; info.bottomMargin = 54; info.leftMargin = 54; info.rightMargin = 54
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        view.textStorage?.setAttributedString(text)
        view.isVerticallyResizable = true
        view.sizeToFit()

        let op = NSPrintOperation(view: view, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run(), FileManager.default.fileExists(atPath: output.path) else {
            removePartial([output])
            throw ConversionError("Couldn't lay out the PDF.")
        }
        // Print layout can't be interrupted; honor a cancel once it returns.
        if Task.isCancelled {
            removePartial([output])
            throw CancellationError()
        }
        return output
    }

    /// Web pages print through WebKit, so CSS and images come along. The PDF
    /// is one continuous page as tall as the document.
    @MainActor
    static func webPageToPDF(_ url: URL) async throws -> URL {
        let output = outputURL(for: url, ext: "pdf")
        let data = try await WebPagePDFRenderer.render(url)
        try Task.checkCancellation()
        do {
            try data.write(to: output)
        } catch {
            throw ConversionError("Couldn't write the PDF.")
        }
        return output
    }

    /// `soffice --headless --convert-to pdf`, when LibreOffice is installed.
    static func libreOfficeToPDF(_ url: URL) throws -> URL {
        guard let soffice = libreOfficeURL else {
            throw ConversionError("Office files need LibreOffice: install it in Settings › General › Helper tools.")
        }
        let output = outputURL(for: url, ext: "pdf")
        let work = output.deletingLastPathComponent().appendingPathComponent("lo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        // A private profile, so a running LibreOffice doesn't block the headless one.
        let profile = "file://" + work.appendingPathComponent("profile").path
        try run(soffice, ["-env:UserInstallation=\(profile)", "--headless", "--convert-to", "pdf", "--outdir", work.path, url.path])
        let produced = work.appendingPathComponent(url.deletingPathExtension().lastPathComponent).appendingPathExtension("pdf")
        guard FileManager.default.fileExists(atPath: produced.path) else { throw ConversionError("LibreOffice didn't produce a PDF.") }
        try FileManager.default.moveItem(at: produced, to: output)
        return output
    }

    // MARK: Helpers

    /// Runs a tool to completion. Its error output is drained as it comes
    /// (FFmpeg and Homebrew write a lot of it), so the pipe never fills and
    /// stalls the tool; the tail is used for the error message.
    static func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice
        let tail = OutputTail()
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            tail.append(handle.availableData)
        }
        try process.run()
        // Poll instead of waitUntilExit so a cancelled job stops the tool.
        while process.isRunning {
            if Task.isCancelled { process.terminate() }
            usleep(20_000)
        }
        errPipe.fileHandleForReading.readabilityHandler = nil
        if Task.isCancelled { throw CancellationError() }
        guard process.terminationStatus == 0 else {
            let msg = tail.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let lastLines = msg.split(separator: "\n").suffix(3).joined(separator: "\n")
            throw ConversionError(lastLines.isEmpty ? "\(executable.lastPathComponent) failed." : lastLines)
        }
    }
}

/// The last few KB a tool printed, collected from a background handler.
final class OutputTail: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        if data.count > 8192 { data = data.suffix(4096) }
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Routing

/// Which converter handles a file type and what it can become. Pure lookups,
/// separate from the conversion work so the routing can be tested.
public enum FileConversionMatrix {
    /// Types ImageIO can actually decode. SVG conforms to public.image but
    /// ImageIO can't read it, so it used to be offered formats that always failed.
    static let decodableImageTypes: [UTType] = ((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])
        .compactMap { UTType($0) }

    public static func kind(forExtension rawExtension: String) -> FileConverter.Kind {
        let ext = rawExtension.lowercased()
        guard let type = UTType(filenameExtension: ext) else { return .unsupported }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) {
            return decodableImageTypes.contains { type.conforms(to: $0) } ? .image : .unsupported
        }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .text) || type.conforms(to: .rtf) || type.conforms(to: .rtfd)
            || type.conforms(to: .html) || type.conforms(to: .webArchive)
            || ["doc", "docx", "odt", "wordml"].contains(ext) {
            return .document
        }
        return .unsupported
    }

    /// Formats a file of this kind can be turned into, in display order.
    public static func targets(for kind: FileConverter.Kind, webpAvailable: Bool) -> [String] {
        switch kind {
        case .image:
            var formats = ["PNG", "JPEG", "HEIC", "GIF", "TIFF", "PDF"]
            if webpAvailable { formats.insert("WEBP", at: 2) }
            return formats
        case .pdf: return ["PNG", "JPEG", "TXT"]
        case .video: return ["MP4", "MOV", "GIF", "M4A"]
        case .audio: return ["M4A", "WAV"]
        case .document: return ["PDF", "TXT", "RTF", "HTML", "DOCX"]
        case .unsupported: return []
        }
    }

    /// Formats every convertible item supports, in the first one's order.
    /// Unconvertible items are ignored rather than emptying the list.
    public static func common(_ lists: [[String]]) -> [String] {
        let lists = lists.filter { !$0.isEmpty }
        guard let first = lists.first else { return [] }
        return first.filter { format in lists.allSatisfy { $0.contains(format) } }
    }
}

/// Finder-style collision policy: "name.ext", then "name 2.ext", "name 3.ext"…
public enum UniqueFileNamer {
    public static func url(in directory: URL, base: String, ext: String, exists: (URL) -> Bool) -> URL {
        func make(_ name: String) -> URL {
            let url = directory.appendingPathComponent(name)
            return ext.isEmpty ? url : url.appendingPathExtension(ext)
        }
        var candidate = make(base)
        var n = 2
        while exists(candidate) {
            candidate = make("\(base) \(n)")
            n += 1
        }
        return candidate
    }
}

// MARK: - Tray glue

@MainActor
public enum ConvertActions {
    /// Converts each item as one cancellable job; results land in the tray.
    /// The job lives in `JobCenter`, so it keeps going when the shelf closes.
    @discardableResult
    public static func convert(_ items: [ShelfItem], to format: String, quality: FileConverter.Quality = .high,
                               completion: (@MainActor (Bool) -> Void)? = nil) -> UUID? {
        let urls = items.map(\.url).filter { FileConverter.targets(for: $0).contains(format) }
        guard !urls.isEmpty else { completion?(false); return nil }
        let title = urls.count == 1 ? "\(urls[0].lastPathComponent) → \(format)" : "\(urls.count) files → \(format)"
        return JobCenter.shared.run(
            title: title,
            appName: "Convert",
            operation: { progress in
                try await BatchConversion.run(urls, to: format, quality: quality, progress: { progress.report($0) })
            },
            onSuccess: { batch in
                deliver(batch, format: format)
            },
            onFinish: { outcome in completion?(outcome == .succeeded) }
        )
    }
}

extension ConvertActions {
    /// Settings › General › Conversion: the converted files' folder —
    /// Smart Export's Converted folder when that's on, else the chosen
    /// destination (Downloads by default).
    static var destinationFolder: URL {
        if let smart = SmartExport.folder(for: .converted) { return smart }
        let custom = FileActionSettings.shared.convertDestination
        if !custom.isEmpty, FileManager.default.fileExists(atPath: custom) {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileOperations.downloadsFolder
    }

    /// Moves the results out of the temporary folder into the destination,
    /// then does what "After converting" says.
    static func deliver(_ batch: BatchConversion.Result, format: String) -> JobCenter.Banner {
        let state = AppState.shared
        let folder = destinationFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var saved: [URL] = []
        for output in batch.outputs {
            let destination = FileOperations.uniqueDestination(for: output, in: folder)
            if (try? FileManager.default.moveItem(at: output, to: destination)) != nil {
                saved.append(destination)
            } else {
                saved.append(output)
            }
        }
        switch FileActionSettings.shared.afterConvertAction {
        case .reveal: NSWorkspace.shared.activateFileViewerSelecting(saved)
        case .openFolder: NSWorkspace.shared.open(folder)
        case .addToShelf: state.addShelfItems(saved.map { ShelfItem(url: $0) })
        case .nothing: break
        }
        DroppyAudio.playDropSuccess()
        let failed = batch.failures.isEmpty ? "" : " · \(batch.failures.count) failed"
        let urls = saved
        return JobCenter.Banner(
            title: "Completed",
            message: "\(saved.count) converted file\(saved.count == 1 ? "" : "s") → \(format), in \(folder.lastPathComponent)" + failed,
            actionTitle: "Show in Finder",
            action: { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        )
    }
}

/// Converts several files in turn, spreading progress evenly across them.
public enum BatchConversion {
    public struct Result: Sendable {
        public var outputs: [URL]
        public var failures: [String]
    }

    public typealias Convert = @Sendable (URL, @escaping FileConverter.Progress) async throws -> [URL]

    /// Fails only when nothing converted. A cancel discards the whole batch,
    /// including files that finished, so a cancelled job leaves nothing behind.
    public static func run(_ urls: [URL], to format: String, quality: FileConverter.Quality,
                           progress: @escaping FileConverter.Progress,
                           convert: Convert? = nil) async throws -> Result {
        let convert = convert ?? { url, report in
            try await FileConverter.convert(url, to: format, quality: quality, progress: report)
        }
        var result = Result(outputs: [], failures: [])
        let total = Double(max(urls.count, 1))
        for (i, url) in urls.enumerated() {
            do {
                try Task.checkCancellation()
                progress(Double(i) / total)
                result.outputs += try await convert(url) { fraction in
                    progress((Double(i) + min(max(fraction, 0), 1)) / total)
                }
            } catch is CancellationError {
                FileConverter.removePartial(result.outputs)
                throw CancellationError()
            } catch {
                result.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if Task.isCancelled {
            FileConverter.removePartial(result.outputs)
            throw CancellationError()
        }
        guard !result.outputs.isEmpty else {
            throw FileConverter.ConversionError(result.failures.first ?? "Nothing was converted.")
        }
        progress(1)
        return result
    }
}
