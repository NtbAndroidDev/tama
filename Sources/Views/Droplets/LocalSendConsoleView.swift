import SwiftUI
import UniformTypeIdentifiers

/// LocalSend in the shelf: this Mac's name and receiver state, files waiting
/// to go, the devices nearby (click one to send), and transfers in progress.
struct LocalSendConsoleView: View {
    nonisolated static let tint = Color(red: 0.0, green: 0.55, blue: 0.53)

    @ObservedObject private var service = LocalSendService.shared
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var localSendSettings = LocalSendSettings.shared
    @ObservedObject private var connectivity = ConnectivityService.shared
    @State private var isTargeted = false

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 130), spacing: DS.Space.sm)]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            header
            if let request = service.incoming {
                LocalSendIncomingCard(request: request)
                    .padding(DS.Space.sm)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Palette.surface2))
            }
            if let receiving = service.receiving { receivingRow(receiving) }
            if let outgoing = service.outgoing { outgoingRow(outgoing) }
            if let offer = service.offer { offerRow(offer) }
            stagedRow
            nearby
        }
        .padding(.top, DS.Space.xs)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task { @MainActor in
                let urls = await Self.urls(from: providers)
                if !urls.isEmpty { service.staged = urls }
            }
            return true
        }
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(Self.tint, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .opacity(isTargeted ? 1 : 0)
                .allowsHitTesting(false)
        )
        .onAppear { if service.peers.isEmpty && service.receiverState == .running { service.refresh() } }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: DS.Space.sm) {
            Circle().fill(statusColor).frame(width: 7, height: 7).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(service.deviceName)
                    .font(DS.Typo.title)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(statusText)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(2)
                    .help(statusText)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if service.isScanning {
                ProgressView().controlSize(.small)
                    .help("Scanning network")
                    .accessibilityLabel("Scanning network")
            }
            DroppyIconButton("arrow.clockwise", size: 26, help: "Announce again and refresh the device list") {
                service.refresh()
            }
            .disabled(service.receiverState != .running)
            DroppyIconButton("gearshape", size: 26, help: "LocalSend settings") {
                SettingsNavigator.shared.page = .droplets
                SettingsNavigator.shared.openDropletID = "localSend"
                SettingsWindowController.shared.showWindow()
            }
        }
    }

    private var statusColor: Color {
        switch service.receiverState {
        case .running: localSendSettings.receiveMode == .off ? DS.Palette.warning : DS.Palette.success
        case .starting: DS.Palette.info
        case .failed: DS.Palette.danger
        case .off: DS.Palette.textTertiary
        }
    }

    private var statusText: String {
        switch service.receiverState {
        case .off: return "LocalSend was turned off"
        case .starting: return "Starting the receiver"
        case let .failed(message): return message
        case .running:
            if !connectivity.isOnline { return "Same network, no internet — nearby transfer still works." }
            let visibility = localSendSettings.isVisible ? "Visible to other devices" : "Hidden from other devices"
            let receive = localSendSettings.receiveMode == .off ? "not receiving" : "receiving from \(localSendSettings.receiveMode.title.lowercased())"
            return "\(visibility) · \(receive)\(localSendSettings.isEncrypted ? " · Encrypted (HTTPS)" : "")"
        }
    }

    // MARK: Transfers

    private func receivingRow(_ receiving: LocalSendService.Receiving) -> some View {
        progressRow(icon: "arrow.down.circle.fill",
                    title: "Receiving from \(receiving.senderName)",
                    detail: "\(receiving.doneCount) of \(receiving.fileCount) · \(bytes(receiving.receivedBytes)) of \(bytes(receiving.totalBytes))",
                    progress: receiving.progress, trailing: nil)
    }

    @ViewBuilder
    private func outgoingRow(_ outgoing: LocalSendService.Outgoing) -> some View {
        switch outgoing.phase {
        case .waiting:
            progressRow(icon: "hourglass", title: "Waiting for \(outgoing.peerName) to accept",
                        detail: "\(outgoing.fileCount) file\(outgoing.fileCount == 1 ? "" : "s") · \(bytes(outgoing.totalBytes))",
                        progress: nil, trailing: ("Cancel", { service.cancelSend() }))
        case .sending:
            progressRow(icon: "arrow.up.circle.fill", title: "Sending to \(outgoing.peerName)",
                        detail: "\(bytes(outgoing.sentBytes)) of \(bytes(outgoing.totalBytes))",
                        progress: outgoing.progress, trailing: ("Cancel", { service.cancelSend() }))
        case .done:
            progressRow(icon: "checkmark.circle.fill", title: "Sent to \(outgoing.peerName)",
                        detail: "\(outgoing.fileCount) file\(outgoing.fileCount == 1 ? "" : "s") · \(bytes(outgoing.totalBytes))",
                        progress: nil, trailing: ("Done", { service.clearOutgoing() }))
        case let .failed(message):
            progressRow(icon: "exclamationmark.triangle.fill", title: message, detail: "Sending to \(outgoing.peerName)",
                        progress: nil, trailing: ("OK", { service.clearOutgoing() }), tint: DS.Palette.warning)
        case .cancelled:
            progressRow(icon: "xmark.circle.fill", title: "Transfer cancelled", detail: outgoing.peerName,
                        progress: nil, trailing: ("OK", { service.clearOutgoing() }))
        }
    }

    private func progressRow(icon: String, title: String, detail: String, progress: Double?,
                             trailing: (String, () -> Void)?, tint: Color = LocalSendConsoleView.tint) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(DS.Typo.body).foregroundStyle(DS.Palette.textPrimary).lineLimit(2)
                    Text(detail).font(DS.Typo.caption).foregroundStyle(DS.Palette.textSecondary)
                        .monospacedDigit().lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                if let trailing {
                    DroppyPillButton(trailing.0, tone: .tonal, action: trailing.1)
                }
            }
            if let progress {
                ProgressView(value: progress).tint(tint).controlSize(.small)
                    .accessibilityLabel(title)
            }
        }
        .padding(DS.Space.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Palette.surface1))
    }

    // MARK: Files to send

    private var stagedRow: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: service.staged.isEmpty ? "doc.badge.plus" : "doc.on.doc.fill")
                .font(.system(size: 14))
                .foregroundStyle(service.staged.isEmpty ? DS.Palette.textTertiary : Self.tint)
                .accessibilityHidden(true)
            if service.staged.isEmpty {
                Text("Drop files here, or pick them, then click a device to send.")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(2)
            } else {
                Text(stagedSummary)
                    .font(DS.Typo.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .help(service.staged.map(\.lastPathComponent).joined(separator: "\n"))
            }
            Spacer(minLength: 0)
            if !service.staged.isEmpty {
                DroppyIconButton("xmark", size: 22, help: "Clear the files to send") { service.staged = [] }
            }
            if service.offer == nil, !service.staged.isEmpty {
                DroppyPillButton("Browser", systemName: "safari", tone: .tonal,
                                 help: "Hold these files behind a web page, so a device with no LocalSend can download them.") {
                    service.startOffer()
                }
            }
            DroppyPillButton("Add files…", systemName: "plus", tone: .tonal,
                             help: "Choose files or folders to send") { pickFiles() }
        }
    }

    // MARK: Share in a browser

    /// What is on offer, the address to type on the other device, and a way
    /// to stop. The address is the whole point, so it is the biggest thing here.
    private func offerRow(_ offer: LocalSendService.Offer) -> some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "safari.fill")
                .font(.system(size: 14))
                .foregroundStyle(Self.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(service.offerURL ?? "Not on a network")
                    .font(DS.Typo.headline.monospaced())
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Text(offerSummary(offer))
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let url = service.offerURL {
                DroppyIconButton("doc.on.doc", size: 22, help: "Copy the address") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                    DroppyAudio.playCopySuccess()
                }
            }
            DroppyPillButton("Stop", systemName: "stop.fill", tone: .tonal,
                             help: "Stop sharing these files in a browser") { service.stopOffer() }
        }
        .padding(DS.Space.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Palette.surface2))
    }

    private func offerSummary(_ offer: LocalSendService.Offer) -> String {
        let count = offer.files.count
        let files = "\(count) file\(count == 1 ? "" : "s") · \(LocalSendService.readable(offer.totalBytes))"
        if !localSendSettings.pin.trimmingCharacters(in: .whitespaces).isEmpty {
            return offer.fetched.isEmpty ? "\(files) · PIN required" : "\(offer.fetched.count) downloaded · PIN required"
        }
        return offer.fetched.isEmpty ? files : "\(offer.fetched.count) of \(count) downloaded · \(files)"
    }

    private var stagedSummary: String {
        let count = service.staged.count
        let size = service.stagedBytes
        let first = service.staged.first?.lastPathComponent ?? ""
        return count == 1 ? "\(first) · \(bytes(size))" : "\(count) items · \(bytes(size))"
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Choose"
        state.setModal(true, owner: "localSend.console")
        defer { state.setModal(false, owner: "localSend.console") }
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { service.staged = panel.urls }
    }

    // MARK: Nearby

    @ViewBuilder
    private var nearby: some View {
        Text("Nearby")
            .font(DS.Typo.caption)
            .foregroundStyle(DS.Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
        if service.peers.isEmpty {
            DroppyEmptyState(systemName: "dot.radiowaves.left.and.right",
                             title: service.receiverState == .running
                                 ? (service.isScanning ? "Looking for devices…" : "No known devices yet")
                                 : "Turn LocalSend on to find devices",
                             subtitle: "Open LocalSend on your phone or computer, on the same network.")
        } else {
            // A busy network fills more rows than the console is tall.
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: DS.Space.sm) {
                    ForEach(service.peers) { peer in
                        PeerTile(peer: peer, canSend: !service.staged.isEmpty && !isBusy) {
                            service.send(to: peer)
                        }
                    }
                }
            }
        }
    }

    private var isBusy: Bool {
        guard let phase = service.outgoing?.phase else { return false }
        return phase == .waiting || phase == .sending
    }

    private func bytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }

    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
            }
            if let url { urls.append(url) }
        }
        return urls
    }
}

/// A device in the Nearby grid: its kind of icon, name and model.
private struct PeerTile: View {
    let peer: LocalSendPeer
    let canSend: Bool
    let send: () -> Void
    @ObservedObject private var service = LocalSendService.shared
    @State private var isHovered = false

    var body: some View {
        Button(action: send) {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: peer.symbol)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(LocalSendConsoleView.tint.opacity(canSend ? 0.9 : 0.45)))
                    if service.isFavorite(peer.id) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                            .offset(x: 3, y: -2)
                    }
                }
                .accessibilityHidden(true)
                Text(peer.info.alias)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                Text(peer.info.deviceModel ?? peer.info.deviceType?.rawValue.capitalized ?? "")
                    .font(.system(size: 9.5))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Space.xs)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.sm)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(isHovered && canSend ? DS.Palette.surface3 : DS.Palette.surface1))
            .contentShape(Rectangle())
        }
        // The tile dims its own circle while it can't send, so the style doesn't dim it again.
        .buttonStyle(PressableStyle(scale: 0.95, dimsWhenDisabled: false))
        .disabled(!canSend)
        .onHover { isHovered = $0 }
        .help(canSend ? "Send to \(peer.info.alias) (\(peer.host))" : "Add files first, then click \(peer.info.alias) to send")
        .contextMenu {
            Button(service.isFavorite(peer.id) ? "Remove from favorites" : "Add to favorites") { service.toggleFavorite(peer) }
            Button("Copy address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(peer.host, forType: .string)
            }
        }
        .accessibilityLabel("\(peer.info.alias), \(peer.info.deviceModel ?? "device")\(service.isFavorite(peer.id) ? ", favorite" : "")")
        .accessibilityHint(canSend ? "Sends the files" : "Add files first")
    }
}
