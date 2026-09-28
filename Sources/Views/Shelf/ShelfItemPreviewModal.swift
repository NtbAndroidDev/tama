import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Quick look at one held file: the preview, what it is, and the handful of
/// things you would actually do with it next.
public struct ShelfItemPreviewModal: View {
    public let item: ShelfItem
    public let onDismiss: () -> Void

    @State private var ocrText = ""
    @State private var isExtractingOCR = false
    @State private var ocrCopied = false
    @State private var ocrFoundNothing = false
    @State private var isLiveTextHovered = false
    @State private var fileCopied = false
    /// Pixel size, read once off the main thread: `item.imageDimensions`
    /// opens the file for its header, which the body did on every render.
    @State private var imageDimensions: CGSize?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(item: ShelfItem, onDismiss: @escaping () -> Void) {
        self.item = item
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            header
            preview
            if !ocrText.isEmpty { ocrStrip }
            metadata
            Divider().overlay(DS.Palette.hairline)
            actions
        }
        .padding(DS.Space.xl)
        .frame(width: 480, height: 400)
        .background(sheetBackground)
        .task(id: item.url) {
            let item = item
            imageDimensions = await Task.detached(priority: .userInitiated) { item.imageDimensions }.value
        }
    }

    private var sheetBackground: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            Color.black.opacity(0.55)
        }
        .ignoresSafeArea()
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: DS.Space.md) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(item.badgeColor.opacity(0.18))
                Image(systemName: item.systemIconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.badgeColor)
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(DS.Typo.title)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.name)
                Text(item.fileExtension)
                    .font(DS.Typo.micro)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: DS.Space.sm)

            DroppyIconButton("xmark", size: 24, tone: .tonal, help: "Close (Esc)") { onDismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: Preview

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Palette.surfaceSunken)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .strokeBorder(DS.Palette.hairline, lineWidth: 1)
                )

            if item.isImage {
                ShelfThumbnail(url: item.url, maxPixelSize: 900) {
                    ProgressView().controlSize(.small)
                }
                .padding(DS.Space.sm)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            } else {
                VStack(spacing: DS.Space.md) {
                    Image(systemName: item.systemIconName)
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(item.badgeColor)
                    Text(item.fileExtension)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Space.sm)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(item.badgeColor.opacity(0.85)))
                }
                .accessibilityHidden(true)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: OCR result

    private var ocrStrip: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.accent)
                .accessibilityHidden(true)

            Text(ocrText)
                .font(DS.Typo.mono)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(2)

            Spacer(minLength: DS.Space.sm)

            DroppyPillButton(ocrCopied ? "Copied" : "Copy text", tone: ocrCopied ? .tonal : .accent) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(ocrText, forType: .string)
                DroppyAudio.playCopySuccess()
                let snap = DS.Motion.respecting(reduceMotion, DS.Motion.snap)
                withAnimation(snap) { ocrCopied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(snap) { ocrCopied = false }
                }
            }
        }
        .padding(DS.Space.md)
        .dsSurface(1, radius: DS.Radius.sm)
        .transition(DS.Motion.transition(reduceMotion, .opacity.combined(with: .move(edge: .bottom))))
    }

    // MARK: Metadata

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DS.Space.sm) {
                Text(item.formattedSize)
                    .font(DS.Typo.numeric.monospacedDigit())
                    .foregroundStyle(DS.Palette.textPrimary)
                if let dim = imageDimensions {
                    Text("\(Int(dim.width)) × \(Int(dim.height)) px")
                        .font(DS.Typo.mono)
                        .foregroundStyle(DS.accent)
                }
            }
            Text(item.url.path)
                .font(DS.Typo.micro)
                .foregroundStyle(DS.Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(item.url.path)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: DS.Space.sm) {
            DroppyPillButton("Quick Look", systemName: "eye", tone: .tonal) {
                item.quickLook()
                onDismiss()
            }

            DroppyPillButton(fileCopied ? "Copied" : "Copy file",
                             systemName: fileCopied ? "checkmark" : "doc.on.doc", tone: .tonal) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([item.url as NSURL])
                DroppyAudio.playCopySuccess()
                // Say so on the button, like "Copy text": a sound alone is easy to miss.
                fileCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { fileCopied = false }
            }

            if item.isImage {
                Button {
                    runOCR()
                } label: {
                    HStack(spacing: DS.Space.xs) {
                        if isExtractingOCR {
                            ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                        } else {
                            Image(systemName: ocrFoundNothing ? "text.badge.xmark" : "text.viewfinder")
                                .font(.system(size: 10, weight: .semibold))
                                .accessibilityHidden(true)
                        }
                        Text(ocrFoundNothing ? "No text found" : "Live Text").font(DS.Typo.caption)
                    }
                    .foregroundStyle(isLiveTextHovered ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                    .padding(.horizontal, DS.Space.md)
                    .frame(height: 24)
                    .background(Capsule().fill(isLiveTextHovered ? DS.Palette.surface3 : DS.Palette.surface2))
                    .contentShape(Capsule())
                }
                .buttonStyle(DroppyPressStyle(scale: 0.95))
                .disabled(isExtractingOCR)
                .onHover { isLiveTextHovered = $0 }
                .help("Find the text in this image")
                .animation(DS.Motion.respecting(reduceMotion, DS.Motion.hover), value: isLiveTextHovered)
                .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: ocrFoundNothing)
            }

            if !item.convertTargets.isEmpty {
                Menu {
                    ForEach(item.convertTargets, id: \.self) { format in
                        Button("Convert to \(format)") {
                            ConvertActions.convert([item], to: format)
                            onDismiss()
                        }
                    }
                } label: {
                    Text("Convert").font(DS.Typo.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Convert this file to another format")
                .accessibilityLabel("Convert")
            }

            Spacer(minLength: DS.Space.sm)

            DroppyPillButton("Reveal", tone: .tonal, help: "Show in Finder") {
                item.revealInFinder()
                onDismiss()
            }

            DroppyPillButton("Open", tone: .accent, help: "Open in its default app (Return)") {
                item.openFile()
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func runOCR() {
        isExtractingOCR = true
        ocrFoundNothing = false
        item.extractText { text in
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                isExtractingOCR = false
                withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { ocrText = clean }
                guard clean.isEmpty else {
                    if TraySettings.shared.autoCopyOCRText {
                        AppState.shared.autoCopyRecognizedText(clean)
                    } else {
                        DroppyAudio.playDropSuccess()
                    }
                    return
                }
                // Say so on the button itself, otherwise the click looks ignored.
                ocrFoundNothing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { ocrFoundNothing = false }
            }
        }
    }
}
