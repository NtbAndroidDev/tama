import SwiftUI
import AppKit
import Vision
import CoreImage
import UniformTypeIdentifiers

// AI Cutout Console — interactive console for this Droplet, presented inside the Droplets lane.

enum CutoutBackgroundStyle: String, CaseIterable, Identifiable {
    case transparent = "Transparent"
    case white = "White"
    case black = "Black"
    case neonGradient = "Neon"
    case pastelGlow = "Pastel"

    var id: String { rawValue }
}

struct CheckerboardPatternView: View {
    var body: some View {
        checkerboard.accessibilityHidden(true)
    }

    private var checkerboard: some View {
        Canvas { context, size in
            let step: CGFloat = 8
            let cols = Int(ceil(size.width / step))
            let rows = Int(ceil(size.height / step))

            for r in 0..<rows {
                for c in 0..<cols {
                    let rect = CGRect(x: CGFloat(c) * step, y: CGFloat(r) * step, width: step, height: step)
                    let color = (r + c) % 2 == 0 ? Color(white: 0.16) : Color(white: 0.24)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }
}

struct AICutoutConsoleView: View {
    @ObservedObject var state = AppState.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTargeted = false
    @State private var originalImage: NSImage?
    @State private var cutoutImage: NSImage?
    @State private var isProcessing = false
    @State private var selectedBgStyle: CutoutBackgroundStyle = .transparent
    @State private var showOriginalComparison = false
    @State private var inferenceTimeMs: Int = 0
    @State private var sourceFileName: String = "photo.png"
    @State private var errorMessage: String?
    /// The cutout being computed; Reset or a newer image changes it, so a
    /// finishing stale job can't bring back the old result.
    @State private var jobID = UUID()

    /// The droplet's own tint, as the other consoles use theirs.
    private let tint = DropletPalette.tint(for: "aiCutout")

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if let img = cutoutImage ?? originalImage {
                // Interactive Preview Area
                VStack(spacing: DS.Space.md) {
                    ZStack {
                        // Background preview layer
                        backgroundLayer
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

                        // Subject Foreground Image
                        Image(nsImage: showOriginalComparison ? (originalImage ?? img) : (cutoutImage ?? img))
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 105)
                            .padding(DS.Space.sm)
                            .shadow(color: selectedBgStyle == .transparent ? .clear : .black.opacity(0.35), radius: 6)
                            .accessibilityLabel(showOriginalComparison ? "Original of \(sourceFileName)" : "Cutout of \(sourceFileName)")

                        if isProcessing {
                            ZStack {
                                Color.black.opacity(0.65)
                                VStack(spacing: DS.Space.sm) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Isolating subject…")
                                        .font(DS.Typo.labelStrong)
                                        .foregroundColor(DS.Palette.textPrimary)
                                }
                                .accessibilityElement(children: .combine)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                        }

                        // Toggle comparison pill
                        VStack {
                            HStack {
                                Spacer()
                                Button {
                                    showOriginalComparison.toggle()
                                } label: {
                                    // Names what a click shows, not what's on screen now.
                                    HStack(spacing: DS.Space.xs) {
                                        Image(systemName: showOriginalComparison ? "wand.and.stars" : "photo")
                                            .accessibilityHidden(true)
                                        Text(showOriginalComparison ? "Show cutout" : "Show original")
                                    }
                                    .font(DS.Typo.micro)
                                    .padding(.horizontal, DS.Space.sm)
                                    .padding(.vertical, DS.Space.xs)
                                    .background(Color.black.opacity(0.75))
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(DroppyPressStyle(scale: 0.95))
                                .help(showOriginalComparison ? "Showing the original; click to see the cutout" : "Showing the cutout; click to compare with the original")
                                .disabled(cutoutImage == nil)
                                .padding(DS.Space.sm)
                            }
                            Spacer()
                        }
                    }
                    .frame(height: 115)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .stroke(DS.Palette.hairline, lineWidth: 1)
                    )

                    // Backdrop style picker row
                    // Segmented chips, like the pack and app pickers in the other consoles.
                    HStack(spacing: DS.Space.xs) {
                        Text("Backdrop")
                            .font(DS.Typo.caption)
                            .foregroundColor(DS.Palette.textSecondary)
                            .padding(.trailing, DS.Space.xs)
                            .accessibilityHidden(true)

                        ForEach(CutoutBackgroundStyle.allCases) { style in
                            DroppyChip(style.rawValue, isSelected: selectedBgStyle == style,
                                       help: "Show and export the cutout on a \(style.rawValue.lowercased()) backdrop") {
                                withAnimation(DS.Motion.respecting(reduceMotion, .easeInOut(duration: 0.15))) {
                                    selectedBgStyle = style
                                }
                            }
                            .accessibilityLabel("\(style.rawValue) backdrop")
                        }

                        Spacer(minLength: 0)
                    }

                    // Stats & Action Buttons
                    HStack(spacing: DS.Space.sm) {
                        if let errorMessage {
                            Text(errorMessage)
                                .font(DS.Typo.caption)
                                .foregroundColor(DS.Palette.danger)
                                .lineLimit(2)
                                .help(errorMessage)
                        } else {
                            HStack(spacing: DS.Space.xs) {
                                if cutoutImage != nil {
                                    Text("\(inferenceTimeMs) ms")
                                        .font(DS.Typo.mono)
                                        .monospacedDigit()
                                        .foregroundColor(DS.Palette.success)
                                        .help("Time Vision took to isolate the subject")
                                }
                                Text(sourceFileName)
                                    .font(DS.Typo.caption)
                                    .foregroundColor(DS.Palette.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 140, alignment: .leading)
                                    .help(sourceFileName)
                            }
                        }

                        Spacer(minLength: 0)

                        DroppyIconButton("arrow.counterclockwise", size: 24, help: "Clear and process another image") {
                            resetState()
                        }

                        DroppyPillButton("Copy", systemName: "doc.on.doc", tone: .tonal,
                                         help: "Copy the cutout on the chosen backdrop") {
                            copyCutoutToClipboard()
                        }
                        .disabled(cutoutImage == nil)

                        DroppyPillButton("Add to Tray", systemName: "tray.and.arrow.down.fill", tone: .accent,
                                         help: "Save the cutout as a PNG in the Tray") {
                            saveCutoutToShelf()
                        }
                        .disabled(cutoutImage == nil)
                    }
                }
            } else {
                // Dropzone when empty
                ZStack {
                    // Filled inside the same rounded shape, so the wash doesn't
                    // poke out square past the dashed corners.
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(isTargeted ? tint.opacity(0.15) : DS.Palette.surface1)
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .strokeBorder(isTargeted ? tint : DS.Palette.hairlineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))

                    VStack(spacing: DS.Space.sm) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 24))
                            .foregroundColor(tint)
                            .accessibilityHidden(true)

                        Text("Drop a portrait, animal or product photo here")
                            .font(DS.Typo.labelStrong)
                            .foregroundColor(DS.Palette.textPrimary)
                        if let errorMessage {
                            Text(errorMessage)
                                .font(DS.Typo.caption)
                                .foregroundColor(DS.Palette.danger)
                                .lineLimit(2)
                        } else {
                            Text("The subject is isolated on this Mac with Apple Vision")
                                .font(DS.Typo.caption)
                                .foregroundColor(DS.Palette.textSecondary)
                        }

                        DroppyPillButton("Browse Photo…", systemName: "folder", tone: .tonal,
                                         help: "Choose a photo to cut out") {
                            openFilePicker()
                        }
                        .padding(.top, DS.Space.xxs)
                    }
                }
                .frame(height: 115)
                .onDrop(of: ["public.file-url"], isTargeted: $isTargeted) { providers in
                    handleDrop(providers: providers)
                    return true
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        switch selectedBgStyle {
        case .transparent:
            CheckerboardPatternView()
        case .white:
            Color.white
        case .black:
            Color.black
        case .neonGradient:
            LinearGradient(colors: [Color.purple.opacity(0.8), Color.blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .pastelGlow:
            LinearGradient(colors: [Color.pink.opacity(0.6), Color.orange.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func resetState() {
        jobID = UUID()
        withAnimation(DS.Motion.respecting(reduceMotion, .default)) {
            originalImage = nil
            cutoutImage = nil
            isProcessing = false
            showOriginalComparison = false
            errorMessage = nil
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        DragDropService.shared.handleDrop(providers: providers) { items in
            guard let first = items.first else { return }
            guard let img = NSImage(contentsOf: first.url) else {
                self.errorMessage = "\(first.name) isn't an image. Drop a photo instead."
                return
            }
            self.originalImage = img
            self.sourceFileName = first.name
            processImageCutout(image: img)
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        // Keep the island open while the panel has focus, or this console unmounts.
        state.setModal(true, owner: "aiCutout.console")
        defer { state.setModal(false, owner: "aiCutout.console") }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let img = NSImage(contentsOf: url) else {
            errorMessage = "\(url.lastPathComponent) couldn't be opened as an image."
            return
        }
        self.originalImage = img
        self.sourceFileName = url.lastPathComponent
        processImageCutout(image: img)
    }

    private func processImageCutout(image: NSImage) {
        let job = UUID()
        jobID = job
        isProcessing = true
        cutoutImage = nil
        errorMessage = nil
        let startTime = CFAbsoluteTimeGetCurrent()

        DispatchQueue.global(qos: .userInitiated).async {
            var finalCutout: NSImage? = nil

            if let tiffData = image.tiffRepresentation,
               let ciImage = CIImage(data: tiffData) {
                let request = VNGenerateForegroundInstanceMaskRequest()
                let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])

                if (try? handler.perform([request])) != nil,
                   let result = request.results?.first,
                   let maskPixelBuffer = try? result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler) {
                    let filter = CIFilter(name: "CIBlendWithMask")
                    filter?.setValue(ciImage, forKey: kCIInputImageKey)
                    filter?.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
                    filter?.setValue(CIImage(cvPixelBuffer: maskPixelBuffer), forKey: kCIInputMaskImageKey)
                    // Render now, so saving and copying work on real pixels.
                    if let output = filter?.outputImage,
                       let cg = CIContext().createCGImage(output, from: ciImage.extent, format: .RGBA8,
                                                          colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) {
                        finalCutout = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                    }
                }
            }

            let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

            DispatchQueue.main.async {
                guard self.jobID == job else { return }
                self.isProcessing = false
                self.inferenceTimeMs = elapsed
                guard let finalCutout else {
                    self.errorMessage = "No subject found — Vision couldn't separate a foreground."
                    return
                }
                self.cutoutImage = finalCutout
                DroppyAudio.playDropSuccess()
            }
        }
    }

    /// The cutout over the chosen backdrop (transparent keeps the alpha).
    private func exportImage() -> NSImage? {
        guard let cutout = cutoutImage else { return nil }
        let size = cutout.size
        let colors: [NSColor]
        switch selectedBgStyle {
        case .transparent: return cutout
        case .white: colors = [.white]
        case .black: colors = [.black]
        case .neonGradient: colors = [NSColor.systemPurple.withAlphaComponent(0.8), NSColor.systemBlue.withAlphaComponent(0.8)]
        case .pastelGlow: colors = [NSColor.systemPink.withAlphaComponent(0.6), NSColor.systemOrange.withAlphaComponent(0.6)]
        }
        let result = NSImage(size: size)
        result.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        if colors.count == 1 {
            colors[0].setFill()
            rect.fill()
        } else {
            NSGradient(colors: colors)?.draw(in: rect, angle: -45)
        }
        cutout.draw(in: rect)
        result.unlockFocus()
        return result
    }

    private func saveCutoutToShelf() {
        guard let img = exportImage() else { return }
        let base = (sourceFileName as NSString).deletingPathExtension
        let fileName = "\(base) cutout \(Int(Date().timeIntervalSince1970)).png"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let state = state
        // The drawing stays here (AppKit); the PNG encode and the write run
        // off main — a full-resolution cutout took a visible beat to encode,
        // and TIFF → bitmap → PNG did it twice.
        let cgImage = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        Task {
            let written = await Task.detached(priority: .userInitiated) { () -> Bool in
                guard let cgImage, let png = Self.pngData(cgImage) else { return false }
                return (try? png.write(to: tempURL)) != nil
            }.value
            guard written else {
                state.showNotification(appName: "AI Cutout", title: "Couldn't save", message: fileName)
                return
            }
            state.addShelfItems([ShelfItem(url: tempURL)])
            state.showNotification(
                appName: "AI Cutout",
                title: "Cutout saved to Tray",
                message: "\(fileName) is ready in your Tray"
            )
            DroppyAudio.playCopySuccess()
        }
    }

    private func copyCutoutToClipboard() {
        guard let img = exportImage() else { return }
        let state = state
        let message = selectedBgStyle == .transparent ? "Transparent cutout copied as image" : "Cutout on \(selectedBgStyle.rawValue) copied as image"
        // PNG (alpha kept) encoded off main, instead of `writeObjects([NSImage])`
        // turning the full image into TIFF on it.
        let cgImage = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        Task {
            let png = await Task.detached(priority: .userInitiated) { cgImage.flatMap(Self.pngData) }.value
            let pb = NSPasteboard.general
            pb.clearContents()
            if let png {
                pb.writeObjects([ClipboardService.imageItem(png: png)])
            } else {
                pb.writeObjects([img])
            }
            DroppyAudio.playCopySuccess()
            state.showNotification(appName: "AI Cutout", title: "Copied to clipboard", message: message)
        }
    }

    private nonisolated static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
