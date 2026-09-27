import SwiftUI
import AppKit
import UniformTypeIdentifiers

// OCR Console — text and barcodes out of images and PDFs, presented inside the Droplets lane.

/// Lives outside the view so a long PDF keeps going, and its result stays put,
/// while the shelf is closed.
@MainActor
final class OCRSession: ObservableObject {
    static let shared = OCRSession()

    @Published var text = ""
    @Published var languageName: String?
    @Published var barcodes: [OCRService.Barcode] = []
    @Published var sourceName: String?
    @Published var progress: Double?
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

    var isRunning: Bool { progress != nil }

    func run(url: URL) {
        guard OCRService.canRead(url) else {
            return fail(OCRService.OCRError.unsupported.localizedDescription)
        }
        start(name: url.lastPathComponent) { report in
            try await OCRService.recognize(url: url, progress: report)
        }
    }

    func run(image: NSImage, name: String) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return fail(OCRService.OCRError.unreadable.localizedDescription)
        }
        start(name: name) { _ in try await OCRService.recognize(cgImage: cgImage) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        progress = nil
    }

    /// Shows an error without leaving the previous source's text beside it.
    private func fail(_ message: String) {
        text = ""
        languageName = nil
        barcodes = []
        errorMessage = message
    }

    func clear() {
        cancel()
        text = ""
        languageName = nil
        barcodes = []
        sourceName = nil
        errorMessage = nil
    }

    private func start(name: String, _ work: @escaping @MainActor (@escaping OCRService.Progress) async throws -> OCRService.Result) {
        task?.cancel()
        sourceName = name
        errorMessage = nil
        progress = 0
        let report: OCRService.Progress = { [weak self] value in
            Task { @MainActor in if self?.progress != nil { self?.progress = value } }
        }
        task = Task { [weak self] in
            do {
                let result = try await work(report)
                guard let self, !Task.isCancelled else { return }
                self.text = result.text
                self.languageName = result.languageName
                self.barcodes = result.barcodes
                if result.text.isEmpty && result.barcodes.isEmpty {
                    self.errorMessage = "No text found"
                } else if AppState.shared.autoCopyOCRText, !result.text.isEmpty {
                    AppState.shared.autoCopyRecognizedText(result.text)
                } else {
                    DroppyAudio.playDropSuccess()
                }
            } catch is CancellationError {
                return
            } catch {
                self?.fail(error.localizedDescription)
            }
            self?.progress = nil
        }
    }
}

struct OCRConsoleView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject private var session = OCRSession.shared
    @State private var isDropTargeted = false
    @FocusState private var editorFocused: Bool

    private var readableTrayItems: [ShelfItem] {
        state.shelfItems.filter { OCRService.canRead($0.url) }
    }

    var body: some View {
        VStack(spacing: DS.Space.md) {
            header
            dropZone
            if !session.text.isEmpty {
                resultEditor
            }
            if !session.barcodes.isEmpty {
                // One row per code found: a dense sheet outgrows the console.
                ScrollView(.vertical, showsIndicators: false) {
                    barcodeList
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        // Corrections typed into the recognised text hold the shelf open.
        .onChange(of: editorFocused) { _, focused in
            state.setEditing(focused, owner: "droplet.ocr.editor")
        }
        .onDisappear { state.clearEditing(withPrefix: "droplet.ocr") }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "text.viewfinder").foregroundColor(DS.accent).accessibilityHidden(true)
            Text("Text extraction").font(DS.Typo.title)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            if let language = session.languageName {
                Text(language)
                    .font(DS.Typo.micro)
                    .foregroundStyle(DS.accent)
                    .lineLimit(1)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, DS.Space.xxs)
                    .background(Capsule().fill(DS.accentSoft))
                    .help("Detected language")
                    .accessibilityLabel("Detected language: \(language)")
            }
            Spacer()
            Menu {
                if readableTrayItems.isEmpty {
                    Text("No images or PDFs in the Tray")
                } else {
                    ForEach(readableTrayItems) { item in
                        Button(item.name) { session.run(url: item.url) }
                    }
                }
            } label: {
                Label("From Tray", systemImage: "tray")
                    .lineLimit(1)
                    .font(DS.Typo.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(session.isRunning)
            .help("Read text from an image or PDF in the Tray")

            DroppyPillButton("Clipboard", systemName: "doc.on.clipboard",
                             help: "Read text from the image on the clipboard") {
                readClipboard()
            }
            .disabled(session.isRunning)
        }
    }

    // MARK: Drop zone

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? DS.accent : DS.Palette.hairlineStrong,
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [6, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(isDropTargeted ? DS.glow : DS.Palette.surfaceGhost)
                )

            if let progress = session.progress {
                HStack(spacing: DS.Space.md) {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("Reading \(session.sourceName ?? "file")…")
                            .font(DS.Typo.label)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        DroppyMeter(value: progress, tint: DS.accent)
                    }
                    DroppyIconButton("xmark", size: 22, tone: .tonal, help: "Cancel reading") {
                        session.cancel()
                    }
                }
                .padding(.horizontal, DS.Space.lg)
            } else {
                VStack(spacing: DS.Space.xs) {
                    Image(systemName: session.errorMessage == nil ? "arrow.down.doc.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(session.errorMessage == nil ? DS.accent : DS.Palette.warning)
                        .accessibilityHidden(true)
                    Text(session.errorMessage ?? "Drop an image or PDF to extract its text")
                        .font(DS.Typo.label)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .truncationMode(.middle)
                        .optionalHelp(session.errorMessage)
                }
                .padding(DS.Space.md)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(height: 64)
        .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in OCRSession.shared.run(url: url) }
            }
            return true
        }
        // Images dragged straight out of a browser or Preview arrive as data, not files.
        guard provider.canLoadObject(ofClass: NSImage.self) else { return false }
        _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
            guard let image = object as? NSImage else { return }
            Task { @MainActor in OCRSession.shared.run(image: image, name: "Dropped image") }
        }
        return true
    }

    private func readClipboard() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first(where: OCRService.canRead) {
            session.run(url: url)
        } else if let image = NSImage(pasteboard: pasteboard) {
            session.run(image: image, name: "Clipboard image")
        } else {
            session.errorMessage = "No image on the clipboard"
            DroppyAudio.playTick()
        }
    }

    // MARK: Result

    private var resultEditor: some View {
        VStack(spacing: DS.Space.sm) {
            TextEditor(text: $session.text)
                .font(DS.Typo.body)
                .focused($editorFocused)
                .accessibilityLabel("Recognized text")
                .scrollContentBackground(.hidden)
                .padding(DS.Space.sm)
                .background(DS.Palette.surface1)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                // Fixed: an unbounded TextEditor collapses when a parent scrolls.
                .frame(height: 130)

            HStack(spacing: DS.Space.sm) {
                let words = session.text.split(whereSeparator: \.isWhitespace).count
                Text("\(words) \(words == 1 ? "word" : "words")")
                    .font(DS.Typo.caption.monospacedDigit())
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                Spacer()
                DroppyPillButton("Clear", systemName: "trash", tone: .plain, help: "Clear the recognized text") {
                    session.clear()
                    DroppyAudio.playTick()
                }
                DroppyPillButton("Save to Tray", systemName: "tray.and.arrow.down.fill",
                                 help: "Save the text to the Tray as a .txt file") {
                    saveToTray()
                }
                .disabled(isTextEmpty)
                DroppyPillButton("Copy", systemName: "doc.on.doc", tone: .accent, help: "Copy the recognized text") {
                    copy(session.text)
                }
                .disabled(isTextEmpty)
            }
        }
    }

    private var barcodeList: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            ForEach(session.barcodes, id: \.self) { code in
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: code.symbology.hasPrefix("QR") ? "qrcode" : "barcode")
                        .foregroundStyle(DS.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(code.payload)
                            .font(DS.Typo.label)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Text(code.symbology)
                            .font(DS.Typo.micro)
                            .foregroundStyle(DS.Palette.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let url = code.url {
                        DroppyIconButton("arrow.up.right.square", size: 22, help: "Open link") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    DroppyIconButton("doc.on.doc", size: 22, help: "Copy code") {
                        copy(code.payload)
                    }
                }
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.xs)
                .dsSurface(1, radius: DS.Radius.sm)
            }
        }
    }

    private var isTextEmpty: Bool {
        session.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        DroppyAudio.playCopySuccess()
        state.showNotification(appName: "OCR", title: "Copied", message: "Text copied to the clipboard")
    }

    private func saveToTray() {
        let base = (session.sourceName as NSString?)?.deletingPathExtension ?? "Extracted Text"
        let fileName = "\(base) (text).txt"
        let folder = AppState.trayStorageDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try session.text.write(to: url, atomically: true, encoding: .utf8)
            state.addShelfItems([ShelfItem(url: url)])
            DroppyAudio.playDropSuccess()
            state.showNotification(appName: "OCR", title: "Saved to Tray", message: fileName)
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }
}
