import SwiftUI

// Notification HUD console: the store's status (and the Full Disk Access
// guide), recent notifications with per-app filters, and quick reply.

struct NotificationHUDConsoleView: View {
    @ObservedObject private var service = NotificationHUDService.shared
    @ObservedObject private var state = AppState.shared
    @State private var filterApp: String?
    @State private var draft = ""
    @State private var isSending = false
    @State private var replyNote: String?
    @FocusState private var composerFocused: Bool

    private var shown: [MirroredNotification] {
        guard let filterApp else { return service.recent }
        return service.recent.filter { $0.bundleID == filterApp }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch service.status {
            case .watching:
                list
            case .checking:
                HStack(spacing: DS.Space.sm) {
                    ProgressView().controlSize(.small)
                    Text("Checking the macOS notification store…").font(DS.Typo.body).foregroundStyle(DS.Palette.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .needsFullDiskAccess:
                FullDiskAccessGuide()
            case .notFound:
                DroppyEmptyState(systemName: "bell.slash", title: "No notification store found",
                                 subtitle: "This version of macOS keeps notifications somewhere Tama doesn't know yet.")
            case let .unsupported(reason):
                DroppyEmptyState(systemName: "exclamationmark.triangle", title: "Can't read notifications", subtitle: reason)
            case .off:
                Color.clear.onAppear { service.sync() }
            }
        }
        .onAppear { service.sync() }
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.sm) {
                Text("Recent notifications").font(DS.Typo.title).foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if !service.recent.isEmpty {
                    DroppyPillButton("Clear all", systemName: "trash", tone: .plain,
                                     help: "Remove every notification from this list") {
                        service.clearRecent()
                        filterApp = nil
                    }
                }
            }
            if state.notificationHUDShowFilters, Set(service.recent.map(\.bundleID)).count > 1 { filters }
            if shown.isEmpty {
                DroppyEmptyState(systemName: "bell", title: "No recent notifications yet",
                                 subtitle: "New notifications show up in the notch and stay here until you quit.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: DS.Space.xs) {
                        ForEach(shown) { note in
                            row(note)
                            if service.replyTargetID == note.id { composer(note) }
                        }
                    }
                }
            }
        }
    }

    /// "Shows filter choices above the notifications."
    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.xs) {
                DroppyChip("All", isSelected: filterApp == nil) { filterApp = nil }
                ForEach(Array(Set(service.recent.map(\.bundleID))).sorted(), id: \.self) { bundleID in
                    DroppyChip(NotificationHUDService.appName(for: bundleID), isSelected: filterApp == bundleID) {
                        filterApp = filterApp == bundleID ? nil : bundleID
                    }
                    .contextMenu {
                        Button("Don't show \(NotificationHUDService.appName(for: bundleID))") {
                            service.setBlocked(bundleID, true)
                        }
                    }
                }
            }
        }
    }

    private func row(_ note: MirroredNotification) -> some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            Group {
                if let icon = AppIcon.image(bundleID: note.bundleID) {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "app.badge").font(.system(size: 16)).foregroundStyle(DS.Palette.textSecondary)
                }
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: DS.Space.sm) {
                    Text(NotificationHUDService.appName(for: note.bundleID))
                        .font(DS.Typo.caption).foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(note.date, format: .relative(presentation: .named))
                        .font(DS.Typo.caption).foregroundStyle(DS.Palette.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Text(note.title).font(DS.Typo.headline).foregroundStyle(DS.Palette.textPrimary).lineLimit(1)
                if !note.preview.isEmpty {
                    Text(note.preview).font(DS.Typo.label).foregroundStyle(DS.Palette.textSecondary).lineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)
            .help([note.title, note.preview].filter { !$0.isEmpty }.joined(separator: "\n"))
            if state.notificationHUDQuickReply, note.replyKind != .none {
                DroppyIconButton("arrowshape.turn.up.left.fill", size: 24, isActive: service.replyTargetID == note.id,
                                 help: service.replyTargetID == note.id ? "Close the reply" : "Reply") { toggleReply(note) }
            }
        }
        .padding(DS.Space.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).fill(DS.Palette.surface1))
        .contextMenu {
            if note.replyKind != .none { Button("Reply") { toggleReply(note) } }
            Button("Open \(NotificationHUDService.appName(for: note.bundleID))") {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: note.bundleID) {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            }
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString([note.title, note.preview].filter { !$0.isEmpty }.joined(separator: "\n"), forType: .string)
            }
            Divider()
            Button("Don't show \(NotificationHUDService.appName(for: note.bundleID))") { service.setBlocked(note.bundleID, true) }
            Button("Remove", role: .destructive) { service.remove(note.id) }
        }
    }

    private func toggleReply(_ note: MirroredNotification) {
        replyNote = nil
        draft = ""
        service.replyTargetID = service.replyTargetID == note.id ? nil : note.id
        composerFocused = service.replyTargetID != nil
    }

    // MARK: Reply

    private func composer(_ note: MirroredNotification) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.sm) {
                TextField("Type a message, then press Return to send", text: $draft)
                    .textFieldStyle(.plain)
                    .font(DS.Typo.body)
                    .focused($composerFocused)
                    .accessibilityLabel("Reply")
                    .onSubmit { send(note) }
                    .disabled(isSending)
                    // A half-typed reply holds the shelf open.
                    .onChange(of: composerFocused) { _, focused in
                        AppState.shared.setEditing(focused, owner: "droplet.notificationHUD.reply")
                    }
                if isSending {
                    ProgressView().controlSize(.mini).accessibilityLabel("Sending")
                } else {
                    DroppyIconButton("paperplane.fill", size: 24, help: "Send") { send(note) }
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.xs)
            .background(DS.Palette.surface1, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            Text(replyNote ?? replyHint(note))
                .font(DS.Typo.caption)
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { composerFocused = true }
    }

    private func replyHint(_ note: MirroredNotification) -> String {
        switch note.replyKind {
        case .messages: "Sent from your Messages account to the chat this came from."
        case .whatsapp: "WhatsApp has no way for other apps to send: Return copies your reply and opens WhatsApp."
        case .telegram: "Telegram has no way for other apps to send: Return copies your reply and opens Telegram."
        case .none: ""
        }
    }

    private func send(_ note: MirroredNotification) {
        guard !isSending else { return }
        isSending = true
        let text = draft
        Task { @MainActor in
            let outcome = await QuickReplyService.reply(text, to: note)
            isSending = false
            switch outcome {
            case .sent:
                draft = ""
                replyNote = nil
                service.replyTargetID = nil
                DroppyAudio.playTick()
                state.showNotification(appName: "Messages", title: "Reply sent", message: text, icon: "paperplane.fill", duration: 2)
                if state.notificationHUDHideAfterReply { state.setIslandExpanded(false) }
            case let .copiedAndOpened(message):
                draft = ""
                replyNote = message
                if state.notificationHUDHideAfterReply { state.setIslandExpanded(false) }
            case let .failed(message):
                replyNote = message
            }
        }
    }
}

/// "Required to read notifications": what Full Disk Access is for and how
/// to grant it, with a button to the right pane.
struct FullDiskAccessGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "lock.shield.fill").font(.system(size: 18)).foregroundStyle(DS.Palette.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Full Disk Access needed").font(DS.Typo.title)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Required to read notifications.").font(DS.Typo.label).foregroundStyle(DS.Palette.textSecondary)
                }
            }
            Text("macOS keeps notifications in a private database. To mirror them, turn on Tama in System Settings › Privacy & Security › Full Disk Access (use + if it isn't listed). Tama only reads notifications and never changes them.")
                .font(DS.Typo.label)
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.sm) {
                DroppyPillButton("Open Full Disk Access", systemName: "gearshape", tone: .accent,
                                 help: "Open Privacy & Security › Full Disk Access in System Settings") {
                    NotificationHUDService.shared.openFullDiskAccessSettings()
                }
                DroppyPillButton("Check again", systemName: "arrow.clockwise", tone: .tonal,
                                 help: "Look for access again after turning it on") {
                    NotificationHUDService.shared.start()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
