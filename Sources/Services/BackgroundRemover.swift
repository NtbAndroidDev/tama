import AppKit
import CoreImage
@preconcurrency import Vision

/// Remove Background: Vision's subject mask on-device, then the styling from
/// Settings › General › Background removal (backdrop, padding, corner radius,
/// shadow). Writes a PNG (transparency kept) and returns it.
public enum BackgroundRemover {
    public struct Style: Sendable {
        public var background: CutoutBackground
        /// Space around the subject as a fraction of its size; 0 keeps the whole frame.
        public var padding: Double
        public var cornerRadius: Double
        public var shadow: Bool
    }

    @MainActor static var currentStyle: Style {
        return Style(background: FileActionSettings.shared.cutoutBackground, padding: FileActionSettings.shared.cutoutPadding,
                     cornerRadius: FileActionSettings.shared.cutoutCornerRadius, shadow: FileActionSettings.shared.cutoutShadow)
    }

    public static func removeBackground(_ url: URL, style: Style) throws -> URL {
        guard let ciImage = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw FileConverter.ConversionError("Item is not an image.")
        }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            throw FileConverter.ConversionError("No subject found in \(url.lastPathComponent).")
        }
        let mask = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        let filter = CIFilter(name: "CIBlendWithMask")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
        filter?.setValue(CIImage(cvPixelBuffer: mask), forKey: kCIInputMaskImageKey)
        let context = CIContext()
        guard let output = filter?.outputImage,
              let cutout = context.createCGImage(output, from: ciImage.extent, format: .RGBA8,
                                                 colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
            throw FileConverter.ConversionError("Couldn't render the cutout.")
        }
        let styled = try compose(cutout, style: style)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Tama Cutouts/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent(url.deletingPathExtension().lastPathComponent + " cutout").appendingPathExtension("png")
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil) else {
            throw FileConverter.ConversionError("Couldn't write PNG.")
        }
        CGImageDestinationAddImage(dest, styled, nil)
        guard CGImageDestinationFinalize(dest) else { throw FileConverter.ConversionError("Couldn't write PNG.") }
        return out
    }

    /// The subject's bounding box from its alpha.
    static func subjectBounds(_ image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where pixels[row + x] > 12 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // Bitmap rows run top-down; CG rects bottom-up.
        return CGRect(x: minX, y: height - maxY - 1, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Draws the cutout over its backdrop: trimmed to the subject with
    /// padding when asked, rounded, with a soft shadow.
    static func compose(_ cutout: CGImage, style: Style) throws -> CGImage {
        let full = CGRect(x: 0, y: 0, width: cutout.width, height: cutout.height)
        var subjectRect = full
        var canvas = full.size
        if style.padding > 0, let bounds = subjectBounds(cutout) {
            subjectRect = bounds
            let pad = max(bounds.width, bounds.height) * style.padding
            canvas = CGSize(width: bounds.width + pad * 2, height: bounds.height + pad * 2)
        }
        let plain = style.background == .transparent && style.cornerRadius <= 0 && !style.shadow && style.padding <= 0
        if plain { return cutout }
        let width = Int(canvas.width.rounded()), height = Int(canvas.height.rounded())
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw FileConverter.ConversionError("Couldn't compose the image.")
        }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let radius = min(bounds.width, bounds.height) * min(max(style.cornerRadius, 0), 0.5)
        let shape = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let colors = style.background.colors
        if !colors.isEmpty {
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            if colors.count == 1 {
                ctx.setFillColor(colors[0].cgColor)
                ctx.fill(bounds)
            } else if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                                colors: colors.map(\.cgColor) as CFArray, locations: nil) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: bounds.maxY), end: CGPoint(x: bounds.maxX, y: 0), options: [])
            }
            ctx.restoreGState()
        } else if radius > 0 {
            ctx.addPath(shape)
            ctx.clip()
        }
        // The subject, centred, with its drop shadow.
        let origin = CGPoint(x: (canvas.width - subjectRect.width) / 2 - subjectRect.minX,
                             y: (canvas.height - subjectRect.height) / 2 - subjectRect.minY)
        if style.shadow {
            let size = max(canvas.width, canvas.height)
            ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.035,
                          color: NSColor.black.withAlphaComponent(0.45).cgColor)
        }
        ctx.draw(cutout, in: CGRect(origin: origin, size: full.size))
        guard let result = ctx.makeImage() else { throw FileConverter.ConversionError("Couldn't compose the image.") }
        return result
    }
}

// MARK: - Shelf glue

@MainActor
public enum BackgroundRemovalActions {
    /// Remove Background (N): one job over the images; each cutout joins the
    /// Shelf or Basket its image is on (or Smart Export's folder).
    public static func run(_ items: [ShelfItem]) {
        let images = items.filter(\.isImage)
        guard !images.isEmpty else {
            AppState.shared.showNotification(appName: "Remove Background", title: "Background Removal Failed",
                                             message: "Item is not an image.", icon: "exclamationmark.triangle.fill")
            return
        }
        let style = BackgroundRemover.currentStyle
        let sources = images.map { ($0.id, $0.url) }
        JobCenter.shared.run(
            title: images.count == 1 ? "Removing background · \(images[0].name)" : "Removing \(images.count) backgrounds",
            appName: "Remove Background",
            failureTitle: "Background Removal Failed",
            operation: { progress in
                var outputs: [(UUID, URL)] = []
                var failures = 0
                for (index, source) in sources.enumerated() {
                    try Task.checkCancellation()
                    progress.report(Double(index) / Double(sources.count))
                    if let out = try? BackgroundRemover.removeBackground(source.1, style: style) {
                        outputs.append((source.0, out))
                    } else {
                        failures += 1
                    }
                }
                guard !outputs.isEmpty else { throw FileConverter.ConversionError("No subject found.") }
                return CutoutBatch(outputs: outputs.map { CutoutBatch.Entry(source: $0.0, url: $0.1) }, failures: failures)
            },
            onSuccess: { batch in
                let state = AppState.shared
                var shown: [URL] = []
                var totalSize: Int64 = 0
                for entry in batch.outputs {
                    let url = SmartExport.route(entry.url, kind: .cutouts)
                    let surface = state.surface(of: entry.source) ?? .shelf
                    let added = state.addItems([ShelfItem(url: url)], to: surface)
                    shown += added.map(\.url)
                    totalSize += added.first?.fileSize ?? 0
                }
                DroppyAudio.playDropSuccess()
                let urls = shown
                return JobCenter.Banner(
                    title: batch.failures > 0 ? "Background Removal Completed with Issues" : "Background removed",
                    message: batch.outputs.count == 1
                        ? "\(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)) (PNG, transparency kept)"
                        : "\(batch.outputs.count) cutouts" + (batch.failures > 0 ? " · \(batch.failures) failed" : ""),
                    actionTitle: "Show in Finder",
                    action: { NSWorkspace.shared.activateFileViewerSelecting(urls) }
                )
            }
        )
    }

    struct CutoutBatch: Sendable {
        struct Entry: Sendable {
            let source: UUID
            let url: URL
        }
        let outputs: [Entry]
        let failures: Int
    }
}
