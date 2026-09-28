import AppKit
@preconcurrency import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers

/// Where a capture goes once it's taken (Settings › Element Capture ›
/// Capture destinations). Several can be on at once; with the editor on it
/// opens first and delivers to the others when you click Done.
struct CaptureDestinations: Equatable, Sendable {
    var clipboard: Bool
    var tray: Bool
    var folder: Bool
    var editor: Bool

    @MainActor static var current: CaptureDestinations {
        return CaptureDestinations(clipboard: CaptureSettings.shared.toClipboard, tray: CaptureSettings.shared.toTray,
                                   folder: CaptureSettings.shared.toFolder, editor: CaptureSettings.shared.opensEditor)
    }
}

/// Every screenshot Tama takes: the selection overlay, the pixels
/// (ScreenCaptureKit, with `screencapture` as the fallback), then delivery to
/// the chosen destinations, the corner preview or OCR. Started only by an
/// explicit action — a shortcut, the console, the Tray or the Ring.
@MainActor
final class ScreenCaptureService: ObservableObject {
    static let shared = ScreenCaptureService()

    @Published private(set) var isCapturing = false
    @Published private(set) var countdown = 0
    @Published private(set) var status = "Ready to snip"
    @Published private(set) var needsPermission = false
    @Published private(set) var lastURL: URL?
    @Published private(set) var lastImage: NSImage?
    @Published private(set) var lastOCRText = ""
    @Published private(set) var isReadingText = false

    private init() {}

    // MARK: Capture

    /// Takes a capture. `destinations` overrides the settings (Quick Snip to
    /// Tray); `delay` counts down first, one tick per second.
    func capture(_ mode: CaptureMode, destinations: CaptureDestinations? = nil, delay: Int = 0, revealTray: Bool = false) {
        guard !isCapturing, !CaptureSelectionController.shared.isActive else { return }
        guard ensurePermission() else { return }
        isCapturing = true
        lastOCRText = ""
        DroppyAudio.playTick()
        let previousApp = NSWorkspace.shared.frontmostApplication
        Task {
            defer { self.isCapturing = false; self.countdown = 0 }
            if delay > 0 {
                for remaining in stride(from: delay, to: 0, by: -1) {
                    countdown = remaining
                    status = "Capturing in \(remaining)…"
                    if remaining != delay { DroppyAudio.playTick() }
                    try? await Task.sleep(for: .seconds(1))
                }
                countdown = 0
            }
            guard let selection = await select(mode) else {
                status = "Capture cancelled"
                Self.reactivate(previousApp)
                return
            }
            status = "Capturing…"
            let excludeDroppy = CaptureSettings.shared.excludesDroppy
            let overlays = CaptureSelectionController.shared.overlayWindowIDs
            do {
                let image = try await Self.grab(selection, excludeOwnWindows: excludeDroppy, alwaysExcluded: overlays)
                let points = selection.rect.width
                let scale = points > 0 ? max(1, (CGFloat(image.width) / points).rounded()) : 1
                let opensEditor = (destinations ?? .current).editor && mode != .ocr
                if !opensEditor { Self.reactivate(previousApp) }
                await deliver(image, scale: scale, mode: mode,
                              destinations: destinations ?? .current, revealTray: revealTray)
            } catch {
                Self.reactivate(previousApp)
                status = "Couldn't capture: \(error.localizedDescription)"
                AppState.shared.showNotification(appName: "Capture", title: "Couldn't capture the screen",
                                                 message: error.localizedDescription)
            }
        }
    }

    private func select(_ mode: CaptureMode) async -> CaptureSelection? {
        if mode == .fullscreen {
            let pointer = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
            guard let screen else { return nil }
            return .rect(WindowSnapService.axRect(fromCocoa: screen.frame))
        }
        status = mode == .element ? "Pick an element…" : mode == .window ? "Pick a window…" : "Select an area…"
        return await CaptureSelectionController.shared.select(mode: mode)
    }

    /// Hands focus back to the app that had it, once the overlay is gone.
    private static func reactivate(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != getpid(), !app.isTerminated else { return }
        app.activate()
    }

    private func ensurePermission() -> Bool {
        guard !CGPreflightScreenCaptureAccess() else {
            needsPermission = false
            return true
        }
        needsPermission = true
        let permissions = PermissionService.shared
        // Already asked this session: the switch may be on, but macOS only
        // applies it to a fresh process.
        if permissions.screenRecordingNeedsRelaunch {
            AppState.shared.showNotification(
                appName: "Capture", title: "Relaunch to capture",
                message: "Once Tama is allowed under Screen Recording, it needs a relaunch.",
                actionTitle: "Relaunch", action: { PermissionService.shared.relaunch() })
        } else {
            permissions.request(.screenRecording)
            AppState.shared.showNotification(
                appName: "Capture", title: "Screen Recording needed",
                message: "Allow Tama in Privacy & Security to capture the screen.",
                actionTitle: "Open Settings", action: { PermissionService.shared.openSettings(.screenRecording) })
        }
        return false
    }

    // MARK: Pixels

    enum CaptureError: LocalizedError {
        case noDisplay, noWindow, fallbackFailed
        var errorDescription: String? {
            switch self {
            case .noDisplay: "That area isn't on a connected display."
            case .noWindow: "That window is no longer on screen."
            case .fallbackFailed: "The system capture tool returned nothing."
            }
        }
    }

    /// ScreenCaptureKit first; `screencapture` when it fails.
    nonisolated static func grab(_ selection: CaptureSelection, excludeOwnWindows: Bool,
                                 alwaysExcluded: [CGWindowID]) async throws -> CGImage {
        do {
            return try await grabWithScreenCaptureKit(selection, excludeOwnWindows: excludeOwnWindows,
                                                      alwaysExcluded: alwaysExcluded)
        } catch {
            // The overlay must be off screen before the system tool looks.
            try? await Task.sleep(for: .milliseconds(120))
            return try await grabWithScreencapture(selection)
        }
    }

    private nonisolated static func grabWithScreenCaptureKit(_ selection: CaptureSelection, excludeOwnWindows: Bool,
                                                            alwaysExcluded: [CGWindowID]) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.captureResolution = .best

        if case let .window(id, _) = selection {
            guard let window = content.windows.first(where: { $0.windowID == id }) else { throw CaptureError.noWindow }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = CGFloat(filter.pointPixelScale)
            config.width = Int((filter.contentRect.width * scale).rounded())
            config.height = Int((filter.contentRect.height * scale).rounded())
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        }

        let rect = selection.rect
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let display = content.displays.first { CGDisplayBounds($0.displayID).contains(center) }
            ?? content.displays.max { a, b in
                area(CGDisplayBounds(a.displayID).intersection(rect)) < area(CGDisplayBounds(b.displayID).intersection(rect))
            }
        guard let display else { throw CaptureError.noDisplay }
        let displayBounds = CGDisplayBounds(display.displayID)
        let clipped = rect.intersection(displayBounds)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { throw CaptureError.noDisplay }

        let ownPID = getpid()
        let excluded = content.windows.filter { window in
            alwaysExcluded.contains(window.windowID)
                || (excludeOwnWindows && window.owningApplication?.processID == ownPID)
        }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let scale = CGFloat(filter.pointPixelScale)
        config.sourceRect = clipped.offsetBy(dx: -displayBounds.minX, dy: -displayBounds.minY)
        config.width = Int((clipped.width * scale).rounded())
        config.height = Int((clipped.height * scale).rounded())
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private nonisolated static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }

    /// `/usr/sbin/screencapture` for a rect or a window. It can't leave
    /// Tama's windows out, so it is only the fallback.
    private nonisolated static func grabWithScreencapture(_ selection: CaptureSelection) async throws -> CGImage {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Tama_Capture_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        var args = ["-x"]
        switch selection {
        case let .window(id, _):
            args += ["-o", "-l", "\(id)"]
        case let .rect(r):
            args += ["-R", "\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))"]
        }
        args.append(url.path)
        let arguments = args
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = arguments
            try process.run()
            process.waitUntilExit()
        }.value
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CaptureError.fallbackFailed }
        return image
    }

    // MARK: Delivery

    private func deliver(_ image: CGImage, scale: CGFloat, mode: CaptureMode,
                         destinations: CaptureDestinations, revealTray: Bool) async {
        let state = AppState.shared
        let compress = CaptureSettings.shared.autoCompress && mode != .ocr
        let name = Self.fileName()
        guard let url = await Self.write(image, scale: scale, name: name, compress: compress) else {
            status = "Could not encode the screenshot."
            AppState.shared.showNotification(appName: "Capture", title: "Couldn't save the capture",
                                             message: "Could not encode the screenshot.")
            return
        }
        // Read off main (a Retina capture is megabytes); the bytes serve the
        // preview image and the clipboard below, so the file is read once.
        let fileData = await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
        let nsImage = fileData.flatMap(NSImage.init(data:))
        lastURL = url
        lastImage = nsImage
        DroppyAudio.playDropSuccess()
        let sizeText = "\(image.width) × \(image.height) px"

        if mode == .ocr {
            await readText(image)
            return
        }

        if destinations.editor, let nsImage {
            status = "Editing \(sizeText) capture"
            let delivery = CaptureDelivery(copyToClipboard: destinations.clipboard, addToTray: destinations.tray,
                                           saveToFolder: destinations.folder)
            // Editor only: Done then behaves as for any image, copying unsaved edits.
            CaptureEditorWindowController.shared.open(image: nsImage, sourceURL: url,
                                                      delivery: delivery.isEmpty ? nil : delivery)
            return
        }

        if destinations.clipboard, let data = fileData {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(data, forType: url.pathExtension.lowercased() == "png" ? .png : NSPasteboard.PasteboardType(UTType.jpeg.identifier))
            if let nsImage, url.pathExtension.lowercased() != "png" { pb.writeObjects([nsImage]) }
        }
        var shown = url
        var savedTo: URL?
        if destinations.folder {
            savedTo = Self.saveToFolder(url)
            if let savedTo { shown = savedTo }
        }
        if destinations.tray {
            // The Tray moves temporary files into its own storage.
            let held = state.addShelfItems([ShelfItem(url: url)], reveal: revealTray)
            if savedTo == nil { shown = held.first?.url ?? url }
        }
        lastURL = shown
        CapturePreviewController.shared.show(url: shown, copied: destinations.clipboard)
        status = "Captured \(sizeText)"
        let places = [destinations.tray ? "Tray" : nil, destinations.clipboard ? "Clipboard" : nil,
                      savedTo.map { $0.deletingLastPathComponent().lastPathComponent }]
            .compactMap { $0 }
        var actionTitle: String?
        var action: (@MainActor @Sendable () -> Void)?
        if let savedTo {
            actionTitle = "Reveal"
            action = { NSWorkspace.shared.activateFileViewerSelecting([savedTo]) }
        } else if destinations.tray {
            actionTitle = "Show"
            action = { AppState.shared.open(.tray) }
        }
        state.showNotification(
            appName: "Capture", title: "Screenshot Captured",
            message: places.isEmpty ? "\(shown.lastPathComponent) is in the preview" : "Saved to \(places.joined(separator: " & "))",
            actionTitle: actionTitle, action: action)
    }

    /// "Screenshot 2026-09-22 at 14.03.11.png", like macOS names its own.
    nonisolated static func fileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: date))"
    }

    /// PNG in a private temporary folder, tagged with its pixel density so
    /// the editor and other apps show it at its real size. Auto-compress
    /// keeps point resolution and runs it through the image compressor.
    nonisolated static func write(_ image: CGImage, scale: CGFloat, name: String, compress: Bool) async -> URL? {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TamaCapture", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(name).appendingPathExtension("png")
        let written: Bool = await Task.detached(priority: .userInitiated) {
            do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch { return false }
            var output = image
            var density = scale
            if compress, scale > 1, let small = downsample(image, by: scale) {
                output = small
                density = 1
            }
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
            let props: [CFString: Any] = [kCGImagePropertyDPIWidth: 72 * density, kCGImagePropertyDPIHeight: 72 * density]
            CGImageDestinationAddImage(dest, output, props as CFDictionary)
            return CGImageDestinationFinalize(dest)
        }.value
        guard written else { return nil }
        guard compress, let smaller = try? await FileCompressor.compress(url, level: .medium) else { return url }
        // Keep the capture's own name; the compressor writes into a folder of its own.
        let renamed = folder.appendingPathComponent(name).appendingPathExtension(smaller.pathExtension)
        try? FileManager.default.removeItem(at: url)
        do {
            try FileManager.default.moveItem(at: smaller, to: renamed)
            return renamed
        } catch {
            return smaller
        }
    }

    private nonisolated static func downsample(_ image: CGImage, by scale: CGFloat) -> CGImage? {
        let width = Int((CGFloat(image.width) / scale).rounded()), height = Int((CGFloat(image.height) / scale).rounded())
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// The screenshot folder: the one chosen in Settings, else the Desktop.
    static var folderURL: URL {
        let path = CaptureSettings.shared.folderPath
        if !path.isEmpty { return URL(fileURLWithPath: path, isDirectory: true) }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
    }

    /// Copies `file` into the screenshot folder under a free name.
    @discardableResult
    static func saveToFolder(_ file: URL) -> URL? {
        let folder = folderURL
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let stem = file.deletingPathExtension().lastPathComponent
            var target = folder.appendingPathComponent(file.lastPathComponent)
            var n = 2
            while fm.fileExists(atPath: target.path) {
                target = folder.appendingPathComponent("\(stem) \(n)").appendingPathExtension(file.pathExtension)
                n += 1
            }
            try fm.copyItem(at: file, to: target)
            return target
        } catch {
            AppState.shared.showNotification(appName: "Capture", title: "Couldn't save to \(folder.lastPathComponent)",
                                             message: error.localizedDescription)
            return nil
        }
    }

    // MARK: OCR

    /// Reads a capture's text. Settings › Auto-copy OCR text decides whether
    /// it goes straight to the clipboard or waits behind a Copy button.
    func readText(_ image: CGImage) async {
        isReadingText = true
        status = "Reading text on-device…"
        defer { isReadingText = false }
        do {
            let result = try await OCRService.recognize(cgImage: image)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            lastOCRText = text
            guard !text.isEmpty else {
                status = "No text detected in the selected area."
                AppState.shared.showNotification(appName: "OCR", title: "No text found",
                                                 message: "No text detected in the selected area.")
                return
            }
            let lines = text.components(separatedBy: .newlines).count
            if TraySettings.shared.autoCopyOCRText {
                AppState.shared.autoCopyRecognizedText(text)
                status = "Copied \(lines) line\(lines == 1 ? "" : "s") of text"
            } else {
                status = "Read \(lines) line\(lines == 1 ? "" : "s") of text"
                AppState.shared.showNotification(
                    appName: "OCR", title: "Text recognized",
                    message: text.count > 60 ? "\(text.prefix(57))…" : text,
                    actionTitle: "Copy", action: { ScreenCaptureService.copyText(text) })
            }
        } catch {
            status = "Text recognition failed: \(error.localizedDescription)"
        }
    }

    static func copyText(_ text: String) {
        ClipboardService.shared.copyToPasteboard(text: text)
        // Through the monitor's path so dedupe and the history limit apply.
        ClipboardService.shared.onNewItem?(ClipboardItem(content: text, type: .text))
        DroppyAudio.playCopySuccess()
    }
}
