import SwiftUI
import AppKit

// Screen Snipper & On-Device OCR Console — interactive console for this Droplet, presented inside the Droplets lane.

struct ScreenSnipperConsoleView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject private var permissions = PermissionService.shared
    @ObservedObject private var capture = ScreenCaptureService.shared

    @AppStorage("snipperMode") private var selectedMode: CaptureMode = .area
    @AppStorage("snipperDelay") private var delaySeconds: Int = 0
    /// This console started the capture, so it keeps the island open meanwhile.
    @State private var startedHere = false
    @State private var showCopiedBadge: Bool = false

    private var isCapturing: Bool { capture.isCapturing }
    private var isOCRProcessing: Bool { capture.isReadingText }
    private var countdownRemaining: Int { capture.countdown }
    private var recentCaptureURL: URL? { capture.lastURL }
    private var recentCaptureImage: NSImage? { capture.lastImage }
    private var extractedOCRText: String { capture.lastOCRText }
    private var statusMessage: String { capture.status }
    private var needsScreenPermission: Bool { capture.needsPermission }

    var body: some View {
        VStack(spacing: DS.Space.sm) {
            // Controls (the page header already names the Droplet)
            HStack {
                Spacer()
                
                // Delay selector
                HStack(spacing: DS.Space.xs) {
                    Text("Delay")
                        .font(DS.Typo.caption)
                        .foregroundColor(DS.Palette.textSecondary)
                        .accessibilityHidden(true)
                    ForEach([0, 3, 5], id: \.self) { sec in
                        Button {
                            delaySeconds = sec
                            DroppyAudio.playTick()
                        } label: {
                            Text(sec == 0 ? "Off" : "\(sec)s")
                                .font(delaySeconds == sec ? DS.Typo.labelStrong : DS.Typo.label)
                                .monospacedDigit()
                                .padding(.horizontal, DS.Space.sm)
                                .padding(.vertical, DS.Space.xxs)
                                .background(delaySeconds == sec ? Color.pink.opacity(0.8) : DS.Palette.surface2)
                                .foregroundColor(delaySeconds == sec ? .white : DS.Palette.textSecondary)
                                .clipShape(Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(DroppyPressStyle(scale: 0.95))
                        .accessibilityLabel(sec == 0 ? "No delay" : "\(sec) second delay")
                        .help(sec == 0 ? "Capture right away" : "Capture after \(sec) seconds")
                        .accessibilityAddTraits(delaySeconds == sec ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, DS.Space.xxs)
            
            // Mode Selectors
            HStack(spacing: DS.Space.sm) {
                ForEach(CaptureMode.allCases) { mode in
                    Button {
                        selectedMode = mode
                        DroppyAudio.playTick()
                    } label: {
                        HStack(spacing: DS.Space.xs) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 10))
                                .accessibilityHidden(true)
                            Text(mode.title)
                                .font(selectedMode == mode ? DS.Typo.labelStrong : DS.Typo.label)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .padding(.horizontal, DS.Space.xs)
                        .padding(.vertical, DS.Space.xs)
                        .frame(maxWidth: .infinity)
                        .background(
                            selectedMode == mode ?
                            Color.pink.opacity(0.85) :
                            DS.Palette.surface1
                        )
                        .foregroundColor(selectedMode == mode ? .white : DS.Palette.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    }
                    .buttonStyle(DroppyPressStyle(scale: 0.97))
                    .help(mode.summary)
                    .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
                }
            }
            
            // Action & Preview Grid
            HStack(spacing: DS.Space.md) {
                // Left Column: Capture Button & Option Toggles
                VStack(spacing: DS.Space.sm) {
                    Button {
                        triggerCapture(mode: selectedMode)
                    } label: {
                        VStack(spacing: DS.Space.xs) {
                            if isCapturing {
                                ProgressView()
                                    .controlSize(.small)
                                    .accessibilityHidden(true)
                                Text(countdownRemaining > 0 ? "Capturing in \(countdownRemaining)…" : "Selecting…")
                                    .font(DS.Typo.labelStrong.monospacedDigit())
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            } else {
                                Image(systemName: selectedMode == .ocr ? "text.viewfinder" : selectedMode == .element ? "viewfinder.rectangular" : "camera.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .accessibilityHidden(true)
                                Text(selectedMode == .ocr ? "Snip & read text" : selectedMode == .element ? "Pick element" : "Snip screen")
                                    .font(DS.Typo.labelStrong)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(
                            LinearGradient(
                                colors: [Color.pink.opacity(0.95), Color(red: 200/255, green: 50/255, blue: 180/255)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                        .shadow(color: Color.pink.opacity(0.35), radius: 5, y: 2)
                    }
                    .buttonStyle(DroppyPressStyle(scale: 0.97))
                    .disabled(isCapturing)
                    .help(isCapturing ? "Capturing…" : selectedMode.summary)
                    
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        destinationToggle("Clipboard", isOn: $state.captureToClipboard)
                        destinationToggle("Tray", isOn: $state.captureToTray)
                        destinationToggle("Folder", isOn: $state.captureToFolder)
                            .help("Save to \(ScreenCaptureService.folderURL.lastPathComponent)")
                        destinationToggle("Open editor instantly", isOn: $state.captureOpensEditor)
                    }
                    .padding(.horizontal, DS.Space.xxs)
                }
                .frame(width: 130)
                
                // Right Column: Preview / Result Container
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .fill(DS.Palette.surface1)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                .stroke(DS.Palette.hairline, lineWidth: 1)
                        )
                    
                    if let image = recentCaptureImage, let url = recentCaptureURL {
                        VStack(spacing: DS.Space.xs) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 65)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
                                .dsShadow(.low)
                                .accessibilityLabel("Latest snip")
                            
                            HStack(spacing: DS.Space.sm) {
                                Text("\(Int(image.size.width))×\(Int(image.size.height)) px")
                                    .font(DS.Typo.mono)
                                    .foregroundColor(DS.Palette.textSecondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                
                                Spacer()
                                
                                Button {
                                    copyImageToClipboard(image)
                                } label: {
                                    HStack(spacing: DS.Space.xxs) {
                                        Image(systemName: "doc.on.doc").accessibilityHidden(true)
                                        Text("Copy")
                                    }
                                    .font(DS.Typo.micro)
                                    .foregroundColor(DS.Palette.textPrimary)
                                    .padding(.horizontal, DS.Space.sm)
                                    .padding(.vertical, DS.Space.xxs)
                                    .background(DS.Palette.surface2)
                                    .clipShape(Capsule())
                                    .contentShape(Capsule())
                                }
                                .buttonStyle(DroppyPressStyle(scale: 0.95))
                                .help("Copy the snip to the clipboard")
                                
                                Button {
                                    CaptureEditorWindowController.shared.open(image: image, sourceURL: url)
                                } label: {
                                    HStack(spacing: DS.Space.xxs) {
                                        Image(systemName: "pencil.tip.crop.circle").accessibilityHidden(true)
                                        Text("Edit")
                                    }
                                    .font(DS.Typo.micro)
                                    .foregroundColor(DS.Palette.textPrimary)
                                    .padding(.horizontal, DS.Space.sm)
                                    .padding(.vertical, DS.Space.xxs)
                                    .background(DS.Palette.surface2)
                                    .clipShape(Capsule())
                                    .contentShape(Capsule())
                                }
                                .buttonStyle(DroppyPressStyle(scale: 0.95))
                                .help("Annotate in the screenshot editor")
                                
                                Button {
                                    runOCR(on: image)
                                } label: {
                                    HStack(spacing: DS.Space.xxs) {
                                        if isOCRProcessing {
                                            ProgressView().controlSize(.mini).accessibilityHidden(true)
                                        } else {
                                            Image(systemName: "text.viewfinder").accessibilityHidden(true)
                                        }
                                        Text("OCR")
                                    }
                                    .font(DS.Typo.micro)
                                    .padding(.horizontal, DS.Space.sm)
                                    .padding(.vertical, DS.Space.xxs)
                                    .background(Color.pink.opacity(0.8))
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(DroppyPressStyle(scale: 0.95))
                                .disabled(isOCRProcessing)
                                .help(isOCRProcessing ? "Reading text…" : "Read the text in this snip")
                                .accessibilityLabel(isOCRProcessing ? "Reading text" : "Read text")
                                
                                DroppyIconButton("tray.and.arrow.down", size: 20, tone: .tonal, help: "Keep in Tray") {
                                    addToShelf(url: url)
                                }
                                
                                DroppyIconButton("folder", size: 20, tone: .tonal, help: "Reveal in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                            }
                            .padding(.horizontal, DS.Space.sm)
                        }
                        .padding(DS.Space.sm)
                    } else {
                        VStack(spacing: DS.Space.xs) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 22))
                                .foregroundColor(DS.Palette.textTertiary)
                                .accessibilityHidden(true)
                            
                            Text("Ready to capture screen")
                                .font(DS.Typo.caption)
                                .foregroundColor(DS.Palette.textSecondary)
                            
                            Text("Drag to snip any region or window")
                                .font(DS.Typo.caption)
                                .foregroundColor(DS.Palette.textTertiary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(DS.Space.sm)
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Bottom Status / OCR Output
            // Permission comes first: a stale OCR result must not hide why capture fails.
            if needsScreenPermission {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundColor(DS.Palette.warning)
                        .accessibilityHidden(true)
                    Text(permissions.screenRecordingNeedsRelaunch
                         ? "Relaunch Tama after allowing Screen Recording."
                         : "Tama needs Screen Recording access to capture.")
                        .font(DS.Typo.caption)
                        .foregroundColor(DS.Palette.warning)
                        .lineLimit(1)
                        .help(permissions.screenRecordingNeedsRelaunch
                              ? "Relaunch Tama after allowing Screen Recording."
                              : "Tama needs Screen Recording access to capture.")
                    Spacer()
                    if permissions.screenRecordingNeedsRelaunch {
                        DroppyPillButton("Relaunch", systemName: "arrow.clockwise", tone: .accent,
                                         help: "Quit and reopen Tama so the new access applies") {
                            PermissionService.shared.relaunch()
                        }
                    }
                    DroppyPillButton("Open Settings", systemName: "gear", tone: .tonal,
                                     help: "Open Screen Recording in System Settings") {
                        PermissionService.shared.openSettings(.screenRecording)
                    }
                }
                .padding(.horizontal, DS.Space.xs)
            } else if !extractedOCRText.isEmpty {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 9))
                        .foregroundColor(.pink)
                        .accessibilityHidden(true)
                    
                    Text(extractedOCRText)
                        .font(DS.Typo.mono)
                        .foregroundColor(DS.Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(extractedOCRText)
                    
                    Spacer()
                    
                    Button {
                        ScreenCaptureService.copyText(extractedOCRText)
                        showCopiedBadge = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            showCopiedBadge = false
                        }
                    } label: {
                        Text(showCopiedBadge ? "Copied" : "Copy text")
                            .font(DS.Typo.micro)
                            .padding(.horizontal, DS.Space.sm)
                            .padding(.vertical, DS.Space.xxs)
                            .background(Color.pink.opacity(0.85))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(DroppyPressStyle(scale: 0.95))
                    .help("Copy the recognized text")
                }
                .padding(.horizontal, DS.Space.sm)
                .padding(.vertical, DS.Space.xs)
                .background(Color.pink.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
            } else {
                HStack(spacing: DS.Space.sm) {
                    Circle()
                        .fill(isCapturing || isOCRProcessing ? DS.Palette.warning : DS.Palette.success)
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                    Text(statusMessage)
                        .font(DS.Typo.caption)
                        .foregroundColor(DS.Palette.textSecondary)
                        .lineLimit(1)
                        .help(statusMessage)
                    Spacer()
                }
                .padding(.horizontal, DS.Space.xs)
            }
        }
        .padding(.horizontal, DS.Space.xs)
        .padding(.vertical, DS.Space.xxs)
        .onChange(of: capture.isCapturing) { _, capturing in
            guard !capturing, startedHere else { return }
            startedHere = false
            state.setModal(false, owner: "screenSnipper.capture")
        }
    }
    
    private func triggerCapture(mode: CaptureMode) {
        guard CGPreflightScreenCaptureAccess() else {
            // The service asks and explains; the console shows why meanwhile.
            capture.capture(mode)
            return
        }
        startedHere = true
        // Keep the island open through the countdown and selection, or this console unmounts.
        state.setModal(true, owner: "screenSnipper.capture")
        capture.capture(mode, delay: delaySeconds)
    }

    private func destinationToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 9))
                .foregroundColor(DS.Palette.textSecondary)
                .lineLimit(1)
        }
        .toggleStyle(.checkbox)
    }

    private func copyImageToClipboard(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        DroppyAudio.playTick()
    }
    
    @discardableResult
    private func addToShelf(url: URL) -> URL {
        let item = ShelfItem(
            name: url.lastPathComponent,
            url: url,
            fileExtension: "PNG"
        )
        return state.addShelfItems([item]).first?.url ?? url
    }
    
    private func runOCR(on image: NSImage) {
        guard !isOCRProcessing, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        Task { await capture.readText(cgImage) }
    }
}
