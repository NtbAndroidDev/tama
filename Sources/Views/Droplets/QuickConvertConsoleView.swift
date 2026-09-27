import SwiftUI
import AppKit

// Quick Convert Console — interactive console for this Droplet, presented inside the Droplets lane.

struct QuickConvertConsoleView: View {
    /// Written to only (adding results to the Tray), so not observed.
    private var state: AppState { AppState.shared }
    @ObservedObject private var jobCenter = JobCenter.shared
    @State private var selectedFormat = "PNG"
    @State private var quality: FileConverter.Quality = .high
    @State private var droppedFile: URL?
    @State private var isDropTargeted = false
    @State private var errorMessage: String?

    private static let appName = "Quick Convert"

    /// Read from JobCenter, not view state, so a conversion started before the
    /// shelf collapsed is still shown (and cancellable) when it reopens.
    private var runningJobs: [JobCenter.Job] {
        jobCenter.runningJobs.filter { $0.appName == Self.appName }
    }

    private var droppedFileName: String? { droppedFile?.lastPathComponent }
    /// Read when the file is dropped, not per render: the size is a disk
    /// call and the formats a lookup the body asked for several times.
    @State private var droppedFileSize: Int64 = 0
    @State private var availableFormats: [String] = []

    private func refreshDroppedFileInfo(_ url: URL?) {
        guard let url else {
            droppedFileSize = 0
            availableFormats = []
            return
        }
        droppedFileSize = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0
        availableFormats = FileConverter.targets(for: url)
    }
    
    var body: some View {
        VStack(spacing: DS.Space.md) {
            // Header
            HStack {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(DS.accent)
                        .accessibilityHidden(true)
                    Text("Format converter")
                        .font(DS.Typo.title)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
                // The drop zone is mouse-only; this reaches it from the keyboard too.
                DroppyPillButton(droppedFile == nil ? "Choose file…" : "Choose another…", systemName: "folder",
                                 help: "Pick a file to convert") {
                    pickFile()
                }
            }
            
            // Drop Target & Source File Preview
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(
                        isDropTargeted ? DS.accent : DS.Palette.hairlineStrong,
                        style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [6, 4])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(isDropTargeted ? DS.glow : DS.Palette.surface1)
                    )
                
                if let name = droppedFileName {
                    HStack(spacing: DS.Space.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                .fill(DS.accent.opacity(0.2))
                                .frame(width: 44, height: 44)
                            Image(systemName: "doc.viewfinder.fill")
                                .font(.system(size: 22))
                                .foregroundColor(DS.accent)
                        }
                        .accessibilityHidden(true)
                        
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(name)
                                .font(DS.Typo.headline)
                                .foregroundStyle(DS.Palette.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(name)
                            Text(errorMessage ?? "\(ByteCountFormatter.string(fromByteCount: droppedFileSize, countStyle: .file)) · \(availableFormats.isEmpty ? "This file type can't be converted" : "Ready to convert")")
                                .font(DS.Typo.caption)
                                .foregroundColor(errorMessage == nil ? DS.Palette.textSecondary : DS.Palette.danger)
                                .lineLimit(2)
                                .optionalHelp(errorMessage)
                        }
                        
                        Spacer()
                        
                        DroppyIconButton("xmark", size: 22, tone: .tonal, help: "Remove file") {
                            droppedFile = nil
                            errorMessage = nil
                        }
                    }
                    .padding(12)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 24))
                            .foregroundColor(DS.accent)
                            .accessibilityHidden(true)
                        Text("Drag & drop an image, video, or document here")
                            .font(DS.Typo.label)
                            .foregroundColor(DS.Palette.textSecondary)
                    }
                    .padding(10)
                }
            }
            .frame(height: 80)
            .onChange(of: droppedFile, initial: true) { _, url in refreshDroppedFileInfo(url) }
            .onDrop(of: ["public.file-url"], isTargeted: $isDropTargeted) { providers in
                if let provider = providers.first {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let fileURL = url else { return }
                        Task { @MainActor in
                            self.load(fileURL)
                            DroppyAudio.playDropSuccess()
                        }
                    }
                    return true
                }
                return false
            }
            
            // Format & Quality Controls — only once a file says what it can become.
            if droppedFile != nil, !availableFormats.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    // Own row, scrolling: a long target list must not squeeze the picker.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Space.xs) {
                            ForEach(availableFormats, id: \.self) { fmt in
                                Button {
                                    selectedFormat = fmt
                                    DroppyAudio.playTick()
                                } label: {
                                    Text(fmt)
                                        .font(selectedFormat == fmt ? DS.Typo.labelStrong : DS.Typo.label)
                                        .padding(.horizontal, DS.Space.sm)
                                        .padding(.vertical, DS.Space.xs)
                                        .background(selectedFormat == fmt ? DS.accent : DS.Palette.surface2)
                                        .foregroundColor(selectedFormat == fmt ? .white : DS.Palette.textSecondary)
                                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs))
                                }
                                .buttonStyle(DroppyPressStyle(scale: 0.95))
                                .help("Convert to \(fmt)")
                                .accessibilityLabel("Convert to \(fmt)")
                                .accessibilityAddTraits(selectedFormat == fmt ? .isSelected : [])
                            }
                        }
                    }
                    
                    HStack(spacing: DS.Space.sm) {
                        Text("Compression")
                            .font(DS.Typo.caption)
                            .foregroundColor(DS.Palette.textSecondary)
                            .accessibilityHidden(true)
                        
                        Picker("Compression", selection: $quality) {
                            ForEach(FileConverter.Quality.allCases, id: \.self) { opt in
                                Text(opt.rawValue).tag(opt)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                        
                        Spacer()
                    }
                }
                .padding(.horizontal, 2)
            }
            
            // Running jobs, each with its own bar and cancel button.
            if !runningJobs.isEmpty {
                VStack(spacing: DS.Space.sm) {
                    ForEach(runningJobs) { job in
                        JobRow(job: job) { jobCenter.cancel(job.id) }
                    }
                }
                .padding(.top, DS.Space.xs)
            }
            if droppedFile != nil || runningJobs.isEmpty {
                Button {
                    startConversion()
                } label: {
                    HStack(spacing: DS.Space.sm) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .accessibilityHidden(true)
                        Text("Convert & add to Tray")
                            .lineLimit(1)
                    }
                    .font(DS.Typo.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Space.sm + DS.Space.xxs)
                    .background(canConvert ? DS.accent : DS.Palette.surface3)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                }
                .buttonStyle(DroppyPressStyle(scale: 0.97))
                .disabled(!canConvert)
                .optionalHelp(convertHelp)
                .padding(.top, DS.Space.xs)
            }
        }
    }
    
    /// A newly picked or dropped file, with a target it can actually become.
    private func load(_ url: URL) {
        droppedFile = url
        errorMessage = nil
        let targets = FileConverter.targets(for: url)
        if !targets.contains(selectedFormat), let first = targets.first {
            selectedFormat = first
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // Keep the island open while the panel has focus, or this console unmounts.
        state.setModal(true, owner: "quickConvert.console")
        defer { state.setModal(false, owner: "quickConvert.console") }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
        DroppyAudio.playTick()
    }

    /// Why Convert is off, or what it will do.
    private var convertHelp: String {
        if droppedFile == nil { return "Drop or choose a file to convert it" }
        if isConvertingDroppedFile { return "This file is already converting" }
        if availableFormats.isEmpty { return "This file type can't be converted" }
        return "Convert to \(selectedFormat) and add the result to the Tray"
    }

    private var canConvert: Bool {
        droppedFile != nil && availableFormats.contains(selectedFormat) && !isConvertingDroppedFile
    }

    /// Jobs are titled "<file name> → <format>"; a second run of the same file
    /// would race the first for the same output name.
    private var isConvertingDroppedFile: Bool {
        guard let name = droppedFileName else { return false }
        return runningJobs.contains { $0.title.hasPrefix("\(name) → ") }
    }

    private func startConversion() {
        guard let url = droppedFile, canConvert else { return }
        errorMessage = nil
        let format = selectedFormat
        let quality = quality
        let state = state
        JobCenter.shared.run(
            title: "\(url.lastPathComponent) → \(format)",
            appName: Self.appName,
            operation: { progress in
                try await FileConverter.convert(url, to: format, quality: quality, progress: { progress.report($0) })
            },
            onSuccess: { outputs in
                let items = outputs.map { ShelfItem(url: $0) }
                state.addShelfItems(items)
                DroppyAudio.playDropSuccess()
                let total = items.reduce(Int64(0)) { $0 + $1.fileSize }
                return JobCenter.Banner(
                    title: "Conversion complete",
                    message: items.count == 1
                        ? "Saved \(items[0].name) (\(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))) to your Tray"
                        : "Saved \(items.count) files to your Tray"
                )
            },
            onFinish: { outcome in
                if case let .failed(reason) = outcome { errorMessage = reason }
            }
        )
    }
}
