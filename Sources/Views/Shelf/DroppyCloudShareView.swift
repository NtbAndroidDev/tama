import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Share sheet for held files: AirDrop, or a link that serves the files over
/// the local network (see `LANShareService`) with a QR code for phones.
public struct DroppyCloudShareView: View {
    public let items: [ShelfItem]
    public let onDismiss: () -> Void

    @ObservedObject private var sharing = LANShareService.shared
    @State private var expiry: LANShareService.Expiry = .fifteenMinutes
    @State private var phase: Phase = .configuring
    @State private var errorMessage: String?
    @State private var isCopied = false
    @State private var isAirDropHovered = false
    @State private var isCreateHovered = false
    /// The share being started, so closing the sheet mid-way can call it off.
    @State private var startTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public enum Phase { case configuring, preparing, ready }

    public init(items: [ShelfItem], onDismiss: @escaping () -> Void) {
        self.items = items
        self.onDismiss = onDismiss
    }

    private var totalSize: String {
        ByteCountFormatter.string(fromByteCount: items.reduce(0) { $0 + $1.fileSize }, countStyle: .file)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            header
            Divider().overlay(DS.Palette.hairline)

            switch phase {
            case .configuring: configuring
            case .preparing: preparing
            case .ready: ready
            }
        }
        .padding(DS.Space.xl)
        .frame(width: 400, height: 380)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.55)
            }
            .ignoresSafeArea()
        )
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid), value: phase)
        // Closed while still starting: don't leave a link live that nobody saw.
        .onDisappear(perform: cancelPreparing)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: DS.Space.md) {
            ZStack {
                Circle().fill(DS.accent)
                Image(systemName: "square.and.arrow.up.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Share")
                    .font(DS.Typo.title)
                    .foregroundStyle(DS.Palette.textPrimary)
                Text("\(items.count) file\(items.count == 1 ? "" : "s") · \(totalSize)")
                    .font(DS.Typo.caption.monospacedDigit())
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: DS.Space.sm)

            DroppyIconButton("xmark", size: 24, tone: .tonal, help: "Close") { close() }
                .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: Configure

    private var configuring: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            // AirDrop actually moves the files, so it leads.
            Button {
                airDrop()
            } label: {
                HStack(spacing: DS.Space.md) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Send with AirDrop")
                            .font(DS.Typo.headline)
                            .foregroundStyle(.white)
                        Text("Sends the files themselves to a nearby device")
                            .font(DS.Typo.micro)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, DS.Space.lg)
                .frame(height: 46)
                .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(isAirDropHovered ? DS.accent.opacity(0.92) : DS.accent))
                .contentShape(Rectangle())
            }
            .buttonStyle(DroppyPressStyle(scale: 0.98))
            .onHover { isAirDropHovered = $0 }
            .animation(DS.Motion.respecting(reduceMotion, DS.Motion.hover), value: isAirDropHovered)

            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text("SHARE ON THIS NETWORK")
                    .font(DS.Typo.micro)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .accessibilityLabel("Share on this network")
                    .accessibilityAddTraits(.isHeader)
                Text("Anyone on the same Wi-Fi with the link can download these files while it's live.")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: DS.Space.xxs) {
                    ForEach(LANShareService.Expiry.allCases) { option in
                        DroppyChip(option.rawValue, isSelected: expiry == option) {
                            withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.snap)) { expiry = option }
                        }
                    }
                }
                .help("How long the link keeps working")

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            Button {
                startSharing()
            } label: {
                Label("Create link", systemImage: "qrcode")
                    .font(DS.Typo.headline)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .fill(isCreateHovered ? DS.Palette.surface3 : DS.Palette.surface2))
                    .contentShape(Rectangle())
            }
            .buttonStyle(DroppyPressStyle(scale: 0.98))
            .keyboardShortcut(.defaultAction)
            .onHover { isCreateHovered = $0 }
            .animation(DS.Motion.respecting(reduceMotion, DS.Motion.hover), value: isCreateHovered)
        }
    }

    // MARK: Preparing

    private var preparing: some View {
        VStack(spacing: DS.Space.lg) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Starting the share")
                .font(DS.Typo.label)
                .foregroundStyle(DS.Palette.textSecondary)
            // A slow network can hold this for a while; give a way back
            // besides the close button.
            DroppyPillButton("Cancel", tone: .tonal) {
                cancelPreparing()
                DroppyAudio.playTick()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Ready

    private var link: String { sharing.activeShare?.url.absoluteString ?? "" }

    private var ready: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.sm) {
                Circle()
                    .fill(sharing.activeShare == nil ? DS.Palette.textTertiary : DS.Palette.success)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(sharing.activeShare == nil ? "Link stopped" : "Sharing on this network")
                    .font(DS.Typo.headline)
                    .foregroundStyle(DS.Palette.textPrimary)
                Spacer()
                if sharing.downloadCount > 0 {
                    Text("\(sharing.downloadCount) download\(sharing.downloadCount == 1 ? "" : "s")")
                        .font(DS.Typo.micro.monospacedDigit())
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }

            HStack(spacing: DS.Space.sm) {
                Text(link.isEmpty ? "—" : link)
                    .font(DS.Typo.mono)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .optionalHelp(link.isEmpty ? nil : link)
                Spacer(minLength: DS.Space.sm)
                DroppyPillButton(
                    isCopied ? "Copied" : "Copy",
                    systemName: isCopied ? "checkmark" : "doc.on.doc",
                    tone: isCopied ? .tonal : .accent
                ) {
                    copyLink()
                }
                .disabled(link.isEmpty)
            }
            .padding(DS.Space.md)
            .dsSurface(0, radius: DS.Radius.sm)

            HStack(alignment: .top, spacing: DS.Space.lg) {
                VStack(spacing: DS.Space.xs) {
                    qrCode
                    Text("Scan on the same Wi-Fi")
                        .font(DS.Typo.micro)
                        .foregroundStyle(DS.Palette.textTertiary)
                }

                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    if let expiresAt = sharing.activeShare?.expiresAt {
                        DroppyKeyValue(key: "Stops", value: expiresAt.formatted(date: .omitted, time: .shortened))
                    } else if sharing.activeShare != nil {
                        DroppyKeyValue(key: "Stops", value: "When Tama quits")
                    }
                    DroppyPillButton("Send with AirDrop", systemName: "paperplane.fill", tone: .accent) {
                        airDrop()
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                DroppyPillButton("Stop sharing", systemName: "stop.fill", tone: .tonal) {
                    sharing.stop()
                    DroppyAudio.playTick()
                }
                .disabled(sharing.activeShare == nil)
                Spacer()
                DroppyPillButton("Done", tone: .tonal) { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var qrCode: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(.white)
            if let image = Self.qrImage(for: link) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(5)
            }
        }
        .frame(width: 76, height: 76)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(link.isEmpty ? "No link" : "QR code for the share link")
    }

    /// A genuine QR of whatever the link currently is, rather than a QR glyph.
    private static func qrImage(for string: String) -> NSImage? {
        guard !string.isEmpty, let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: Actions

    private func startSharing() {
        errorMessage = nil
        phase = .preparing
        DroppyAudio.playTick()
        let files = items.map(\.url)
        startTask = Task {
            do {
                let share = try await sharing.start(files: files, expiry: expiry)
                // The sheet closed while this was starting. Stop only our own
                // share, never one a newer sheet has started since.
                guard !Task.isCancelled else {
                    if sharing.activeShare?.url == share.url { sharing.stop() }
                    return
                }
                phase = .ready
                DroppyAudio.playDropSuccess()
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                errorMessage = error.localizedDescription
                phase = .configuring
            }
        }
    }

    private func close() {
        cancelPreparing()
        onDismiss()
    }

    private func cancelPreparing() {
        guard phase == .preparing, let startTask else { return }
        startTask.cancel()
        self.startTask = nil
        phase = .configuring
        sharing.stop()
    }

    private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        DroppyAudio.playCopySuccess()
        let snap = DS.Motion.respecting(reduceMotion, DS.Motion.snap)
        withAnimation(snap) { isCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(snap) { isCopied = false }
        }
    }

    private func airDrop() {
        guard !items.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        let urls = items.map(\.url)
        guard service.canPerform(withItems: urls) else {
            AppState.shared.showNotification(
                appName: "AirDrop",
                title: "Cannot send these files",
                message: "AirDrop refused the current selection."
            )
            return
        }
        DroppyAudio.playTick()
        service.perform(withItems: urls)
        onDismiss()
    }
}
