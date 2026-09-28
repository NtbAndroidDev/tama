import SwiftUI
import AppKit

// Settings for files: General › Quick Actions, Conversion, Automation,
// Background removal, Helper tools and Integrations; the Basket page; and
// the Shelf page's clean-up rows. Built from SettingsPrimitives.

// MARK: - Quick Actions

struct QuickActionsSettingsSection: View {
    @ObservedObject private var fileActionSettings = FileActionSettings.shared

    var body: some View {
        SettingsSection("Quick Actions") {
            SettingsGroup {
                SettingsToggleRow("Quick Actions",
                                  help: "While you drag files onto the Shelf, a Basket or the island, they unfold into tiles: drop on one to keep, AirDrop, convert, upload or email the files. Off, a drop simply lands.",
                                  anchor: "general.quickActions", isOn: $fileActionSettings.quickActionsEnabled)
                SettingsDivider()
                Group {
                    SettingsRow("Quick Action tiles",
                                subtitle: fileActionSettings.quickActionsEnabled ? nil : "Turn on Quick Actions to change the tiles.",
                                help: "Keep is always first; choose up to three more. Quickshare uploads to 0x0.st and copies a link; iCloud Drive copies the files to iCloud Drive › Tama; Share Link makes a link for devices on your network.",
                                anchor: "general.quickActionTiles")
                    QuickActionTileEditor()
                    SettingsNote("Click a tile to swap or remove it, or + to add one. These tiles appear when you drag files onto the Shelf, a Basket or the island.",
                                 icon: "hand.tap")
                    SettingsDivider()
                    SettingsRow("Quick Action mail app",
                                help: "Choose which app opens for the Mail quick action. Default uses the system's mail app.",
                                anchor: "general.mailApp")
                    ChoiceTiles(QuickActionMailApp.allCases.map { .init($0, $0.title, icon: $0.icon) },
                                selection: $fileActionSettings.quickActionMailApp)
                }
                .settingsDisabled(!fileActionSettings.quickActionsEnabled)
            }
            SettingsGroup {
                SettingsToggleRow("Require upload confirmation",
                                  subtitle: "Ask before uploading. Quickshare files expire automatically (30–365 days, depending on size).",
                                  anchor: "general.quickshareConfirm", isOn: $fileActionSettings.quickshareConfirm)
                SettingsDivider()
                RecentUploadsRow()
            }
        }
    }
}

/// The capsule of round tiles on the wallpaper: Keep, the chosen tiles and a
/// dashed + while there's room.
private struct QuickActionTileEditor: View {
    @ObservedObject private var state = AppState.shared
    @State private var editing: Int?
    @State private var isAdding = false

    private var tiles: [QuickAction] { state.quickActionTiles }

    var body: some View {
        ZStack {
            PreviewWallpaper()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            HStack(spacing: 8) {
                tile(.keep, index: nil)
                ForEach(Array(tiles.enumerated()), id: \.element.id) { index, action in
                    tile(action, index: index)
                }
                if tiles.count < QuickAction.slots {
                    Button { isAdding = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 44, height: 44)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])))
                    }
                    .buttonStyle(.plain)
                    .help("Add a tile")
                    .accessibilityLabel("Add quick action")
                    .popover(isPresented: $isAdding, arrowEdge: .bottom) {
                        picker(title: "Add quick action", current: nil) { choice in
                            if let choice { state.quickActionTiles = tiles + [choice] }
                            isAdding = false
                        }
                    }
                }
            }
            .padding(6)
            .background(Capsule().fill(Color(white: 0.12).opacity(0.92)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .frame(width: 300, height: 110)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func tile(_ action: QuickAction, index: Int?) -> some View {
        Button {
            if let index { editing = index }
        } label: {
            Image(systemName: action.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(index == nil ? Color.white.opacity(0.22) : Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(index == nil ? "Keep — always first" : "\(action.title): \(action.subtitle). Click to swap or remove.")
        .accessibilityLabel(action.title)
        .accessibilityHint(index == nil ? "Always first" : "Swap or remove this tile")
        .popover(isPresented: Binding(get: { index != nil && editing == index }, set: { if !$0 { editing = nil } }),
                 arrowEdge: .bottom) {
            picker(title: "Swap \(action.title)", current: action) { choice in
                guard let index, tiles.indices.contains(index) else { return }
                var list = tiles
                if let choice {
                    list[index] = choice
                } else {
                    list.remove(at: index)
                }
                state.quickActionTiles = list
                editing = nil
            }
        }
    }

    /// Choose a tile; nil removes the current one.
    private func picker(title: String, current: QuickAction?, choose: @escaping (QuickAction?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 4)
            ForEach(QuickAction.choosable) { option in
                let used = tiles.contains(option) && option != current
                Button { choose(option) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: option.iconName).frame(width: 18).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.title).font(.system(size: 12, weight: .semibold))
                            Text(option.subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if option == current { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(used)
                .opacity(used ? 0.4 : 1)
                .help(used ? "Already on the row" : "")
                .accessibilityAddTraits(option == current ? .isSelected : [])
            }
            if current != nil {
                Divider().padding(.vertical, 4)
                Button(role: .destructive) { choose(nil) } label: {
                    Label("Take this tile off the row", systemImage: "minus.circle").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.Palette.danger)
                .padding(.horizontal, 6)
            }
        }
        .padding(10)
        .frame(width: 290)
    }
}

/// Quickshare Upload Manager: recent uploads with copy / delete.
private struct RecentUploadsRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var quickshare = QuickshareService.shared
    @State private var isOpen = false
    @State private var isConfirmingClear = false
    /// The upload whose file is about to be deleted from 0x0.st.
    @State private var pendingDelete: QuickshareUpload?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow("Recent uploads",
                        subtitle: quickshare.uploads.isEmpty ? "No shared files yet" : "\(quickshare.uploads.count) shared file\(quickshare.uploads.count == 1 ? "" : "s")",
                        help: "Everything Quickshare uploaded: copy a link again, take it off this list, or delete the file from 0x0.st.",
                        anchor: "general.uploads") {
                Button(isOpen ? "Done" : "Manage Uploads") {
                    withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.disclose)) { isOpen.toggle() }
                }
                .disabled(quickshare.uploads.isEmpty && !isOpen)
            }
            // On their own line, so the title keeps its width in a narrow window.
            HStack(spacing: 8) {
                Button("Upload File…") { quickshare.chooseAndUpload() }
                Button("Upload from Clipboard") { quickshare.uploadFromClipboard() }
                    .help("Upload whatever is on the clipboard right now — files, an image or text — and copy the link back.")
            }
            .controlSize(.small)
            .padding(.horizontal, SettingsStyle.rowPadding.leading)
            .padding(.bottom, SettingsStyle.rowPadding.bottom)
            if isOpen {
                VStack(spacing: 0) {
                    ForEach(quickshare.uploads) { upload in
                        SettingsDivider()
                        HStack(spacing: 10) {
                            Image(systemName: "link").foregroundStyle(.secondary).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(upload.fileName).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                Text(detail(upload)).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button { quickshare.copyLink(upload) } label: {
                                Image(systemName: "doc.on.doc").frame(width: 22, height: 22).contentShape(Rectangle())
                            }
                                .buttonStyle(.plain).help("Copy link")
                                .accessibilityLabel("Copy link to \(upload.fileName)")
                            Menu {
                                Button("Open Link") { if let url = URL(string: upload.link) { NSWorkspace.shared.open(url) } }
                                Button("Remove from List") { quickshare.removeFromList(upload) }
                                if upload.token != nil {
                                    Button("Delete from 0x0.st…", role: .destructive) { pendingDelete = upload }
                                }
                            } label: { Image(systemName: "ellipsis.circle") }
                                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                                .help("More")
                                .accessibilityLabel("More actions for \(upload.fileName)")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    if !quickshare.uploads.isEmpty {
                        SettingsDivider()
                        HStack {
                            Spacer()
                            Button("Clear List…", role: .destructive) { isConfirmingClear = true }
                        }
                        .padding(10)
                    }
                }
                .transition(.opacity)
            }
        }
        .confirmationDialog("Clear the upload list?", isPresented: $isConfirmingClear) {
            Button("Clear List", role: .destructive) { quickshare.clearList() }
        } message: {
            Text("The files stay on 0x0.st until they expire, but their links and delete tokens are forgotten, so Tama can no longer copy or delete them.")
        }
        .confirmationDialog("Delete this file from 0x0.st?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { upload in
            Button("Delete", role: .destructive) { quickshare.deleteFromServer(upload) }
        } message: { upload in
            Text("\u{201C}\(upload.fileName)\u{201D} is removed from the server and its link stops working. This can't be undone.")
        }
    }

    private func detail(_ upload: QuickshareUpload) -> String {
        var parts = [ByteCountFormatter.string(fromByteCount: upload.size, countStyle: .file),
                     upload.date.formatted(date: .abbreviated, time: .shortened)]
        if let expires = upload.expires {
            parts.append(expires < Date() ? "Expired" : "Expires \(expires.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ") + " · " + upload.link
    }
}

// MARK: - Conversion

struct ConversionSettingsSection: View {
    @ObservedObject private var fileActionSettings = FileActionSettings.shared

    private var destinationName: String {
        fileActionSettings.convertDestination.isEmpty ? "Downloads" : FileManager.default.displayName(atPath: fileActionSettings.convertDestination)
    }

    var body: some View {
        SettingsSection("Conversion", subtitle: "Convert files on your Mac, never in the cloud.") {
            SettingsGroup {
                SettingsRow("Destination folder",
                            subtitle: fileActionSettings.smartExportEnabled && fileActionSettings.smartExportConverted
                                ? "Smart Export is on: converted files go to its Converted folder."
                                : "Converted files go to \(destinationName).",
                            help: "Choose where converted files are saved.",
                            anchor: "general.convertDestination") {
                    HStack(spacing: 8) {
                        Button("Choose…") {
                            if let folder = FileOperations.chooseFolder(prompt: "Choose", message: "Choose where converted files are saved") {
                                fileActionSettings.convertDestination = folder.path
                            }
                        }
                        if !fileActionSettings.convertDestination.isEmpty {
                            Button("Downloads") { fileActionSettings.convertDestination = "" }
                        }
                    }
                }
                SettingsDivider()
                SettingsRow("After converting",
                            help: "Show the new files in Finder, open the destination folder, add them to the Shelf, or only show the completion banner.",
                            anchor: "general.afterConvert")
                ChoiceTiles(AfterConvertAction.allCases.map { .init($0, $0.title) }, selection: $fileActionSettings.afterConvertAction)
            }
        }
    }
}

// MARK: - Automation

struct AutomationSettingsSection: View {
    @ObservedObject private var fileActionSettings = FileActionSettings.shared
    @ObservedObject private var traySettings = TraySettings.shared

    /// Read from the stored list, so adding a folder redraws the level row.
    private var folders: [TrackedFolder] {
        fileActionSettings.trackedFoldersEnabled ? TrackedFolder.decode(fileActionSettings.trackedFoldersStorage) : []
    }

    var body: some View {
        SettingsSection("Automation") {
            SettingsGroup {
                SettingsToggleRow("Auto-copy OCR text",
                                  help: "Text the OCR droplet or a Tray preview reads from an image or PDF is copied to the clipboard right away, and kept in its history.",
                                  anchor: "general.autoCopyOCR", isOn: $traySettings.autoCopyOCRText)
                SettingsDivider()
                SettingsToggleRow("Smart Export",
                                  help: "Automatically save processed files to designated folders: compressed images, videos and PDFs; converted files (PNG → JPEG, etc.); background-removed images.",
                                  anchor: "general.smartExport", isOn: $fileActionSettings.smartExportEnabled)
                if fileActionSettings.smartExportEnabled {
                    SettingsDivider()
                    SettingsRow("Folder", subtitle: SmartExport.baseFolder.path, icon: "folder") {
                        HStack(spacing: 8) {
                            Button("Choose…") {
                                if let folder = FileOperations.chooseFolder(prompt: "Choose", message: "Processed files will be saved automatically in folders inside this one.") {
                                    fileActionSettings.smartExportFolder = folder.path
                                }
                            }
                            Button("Show in Finder") {
                                try? FileManager.default.createDirectory(at: SmartExport.baseFolder, withIntermediateDirectories: true)
                                NSWorkspace.shared.open(SmartExport.baseFolder)
                            }
                        }
                    }
                    ToggleTiles([
                        ToggleTile("Compressed", icon: "arrow.down.right.and.arrow.up.left", isOn: $fileActionSettings.smartExportCompressed),
                        ToggleTile("Converted", icon: "arrow.triangle.2.circlepath", isOn: $fileActionSettings.smartExportConverted),
                        ToggleTile("Background removed", icon: "person.crop.rectangle", isOn: $fileActionSettings.smartExportCutouts),
                    ])
                }
                SettingsDivider()
                SettingsToggleRow("Tracked folders",
                                  help: "Watch and process files from selected folders. Each folder says what a new file does: join the Tray, go to a Basket, or be compressed as it lands. A file counts once it has finished writing; partial downloads are skipped.",
                                  anchor: "general.trackedFolders", isOn: $fileActionSettings.trackedFoldersEnabled)
                if fileActionSettings.trackedFoldersEnabled {
                    TrackedFoldersList()
                    if folders.contains(where: { $0.action == .compress }) {
                        SettingsRow("Compression level",
                                    subtitle: "Used by folders set to Add and compress, which run unattended.",
                                    anchor: "general.trackedFoldersLevel") {
                            Picker("Compression level", selection: $fileActionSettings.trackedFoldersCompressionLevel) {
                                ForEach(CompressionLevel.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }
            }
        }
    }
}

private struct TrackedFoldersList: View {
    @ObservedObject private var fileActionSettings = FileActionSettings.shared

    /// Decoded from the stored value rather than read once, so the list
    /// redraws when a folder is added, removed or given another action.
    private var folders: [TrackedFolder] {
        TrackedFolder.decode(fileActionSettings.trackedFoldersStorage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if folders.isEmpty {
                SettingsNote("No folders added", icon: "folder.badge.questionmark")
                    .padding(.top, 4)
            }
            ForEach(folders) { folder in
                HStack(spacing: 8) {
                    Image(nsImage: FileIcon.image(for: folder.path)).resizable().frame(width: 18, height: 18)
                    Text(folder.path).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Picker("Action", selection: Binding(
                        get: { folder.action },
                        set: { TrackedFolderService.shared.setAction($0, for: folder) }
                    )) {
                        ForEach(TrackedFolderAction.allCases) { action in
                            Label(action.title, systemImage: action.icon).tag(action)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .help("What happens to a new file in \(folder.name)")
                    Button { TrackedFolderService.shared.remove(folder) } label: {
                        Image(systemName: "minus.circle").frame(width: 22, height: 22).contentShape(Rectangle())
                    }
                        .buttonStyle(.plain)
                        .help("Stop watching")
                        .accessibilityLabel("Stop watching \(folder.name)")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            HStack {
                Spacer()
                Button("Add Folder…") {
                    if let folder = FileOperations.chooseFolder(prompt: "Watch", message: "Watch and process files from selected folders.") {
                        TrackedFolderService.shared.add(folder)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }
}

// MARK: - Background removal

struct BackgroundRemovalSettingsSection: View {
    @ObservedObject private var fileActionSettings = FileActionSettings.shared

    var body: some View {
        SettingsSection("Background removal",
                        subtitle: "Remove Background in the Shelf and Basket menus uses Vision, on your Mac. Results are PNGs with transparency kept.") {
            SettingsGroup {
                SettingsRow("Backdrop", anchor: "general.cutoutStyle")
                ChoiceTiles(CutoutBackground.allCases.map { .init($0, $0.title) }, selection: $fileActionSettings.cutoutBackground)
                SettingsDivider()
                SettingsSlider("Padding", value: $fileActionSettings.cutoutPadding, in: 0...0.4, step: 0.02, defaultValue: 0,
                               help: "Trims to the subject and adds this much space around it. 0 keeps the whole frame.") {
                    $0 == 0 ? "None" : "\(Int(($0 * 100).rounded()))%"
                }
                SettingsDivider()
                SettingsSlider("Corner radius", value: $fileActionSettings.cutoutCornerRadius, in: 0...0.5, step: 0.02, defaultValue: 0) {
                    $0 == 0 ? "Square" : "\(Int(($0 * 100).rounded()))%"
                }
                SettingsDivider()
                SettingsToggleRow("Shadow", subtitle: "A soft drop shadow under the subject.", isOn: $fileActionSettings.cutoutShadow)
            }
        }
    }
}

// MARK: - Helper tools

struct HelperToolsSettingsSection: View {
    @ObservedObject private var brew = HomebrewHelper.shared

    var body: some View {
        SettingsSection("Helper tools",
                        subtitle: HomebrewHelper.brewURL == nil
                            ? "Homebrew required: some actions use free command-line tools installed with Homebrew."
                            : "Homebrew detected. Install the tools some actions use.",
                        anchor: "general.helperTools") {
            SettingsGroup {
                ForEach(Array(HomebrewHelper.Tool.allCases.enumerated()), id: \.element.id) { index, tool in
                    if index > 0 { SettingsDivider() }
                    SettingsRow(tool.title, subtitle: tool.purpose) {
                        if brew.installing.contains(tool) {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Installing…").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        } else if brew.isInstalled(tool) {
                            Label("Installed", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(DS.Palette.success)
                        } else {
                            Button("Install \(tool.title)") { brew.install(tool) }
                        }
                    }
                }
                if HomebrewHelper.brewURL == nil {
                    SettingsNote("Install Homebrew from brew.sh, then come back and click Install beside a tool.",
                                 icon: "shippingbox")
                        .padding(.top, 8)
                }
            }
        }
    }
}

// MARK: - Integrations

struct IntegrationsSettingsSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsFinderGuide = false

    private var bundledWorkflow: URL? {
        Bundle.main.url(forResource: "Tama", withExtension: "alfredworkflow")
    }

    var body: some View {
        SettingsSection("Integrations") {
            SettingsGroup {
                SettingsRow("Finder Services",
                            subtitle: "Right-click files in Finder › Services › Add to Tama Shelf or Add to Tama Basket.",
                            help: "Finder lists Tama's services once they're switched on in System Settings.",
                            anchor: "general.finderServices") {
                    Button(showsFinderGuide ? "Hide Guide" : "Setup Guide") {
                        withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.disclose)) { showsFinderGuide.toggle() }
                    }
                }
                if showsFinderGuide {
                    VStack(alignment: .leading, spacing: 6) {
                        guideStep(1, "Open System Settings › Keyboard › Keyboard Shortcuts…")
                        guideStep(2, "In the left sidebar, select Services.")
                        guideStep(3, "Then open Files and Folders, and tick Add to Tama Shelf and Add to Tama Basket.")
                        guideStep(4, "In Finder: right-click a file › Services (or Quick Actions) › Add to Tama Shelf.")
                        HStack {
                            Spacer()
                            Button("Open Keyboard Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
                SettingsDivider()
                SettingsRow("Alfred",
                            subtitle: "Integrate Tama actions into Alfred: Add to Shelf and Add to Basket as file actions.",
                            anchor: "general.alfred") {
                    Button("Install Workflow") {
                        if let bundledWorkflow { NSWorkspace.shared.open(bundledWorkflow) }
                    }
                    .disabled(bundledWorkflow == nil)
                    .help(bundledWorkflow == nil ? "Run Tama from its app bundle to install the workflow" : "Opens the workflow in Alfred")
                }
                SettingsDivider()
                SettingsRow("URL scheme",
                            subtitle: "tama://add?target=shelf|basket&path=/path/to/file, and tama://show?target=shelf|basket|clipboard|calendar|guide|settings — for scripts, Shortcuts and launchers.",
                            anchor: "general.urlScheme") {
                    Button("Copy Example") {
                        ClipboardService.shared.copyToPasteboard(text: "tama://add?target=shelf&path=" +
                            (FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path
                                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""))
                        DroppyAudio.playCopySuccess()
                    }
                }
            }
        }
    }

    private func guideStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)").font(.system(size: 11, weight: .bold, design: .rounded))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(0.1)))
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Shelf page rows

/// Settings › Shelf › Tray: Auto-cleanup and Two Stacks.
struct ShelfFileRows: View {
    @ObservedObject private var traySettings = TraySettings.shared

    var body: some View {
        SettingsRow("Auto-cleanup",
                    subtitle: "Auto-remove unpinned Tray files after this long. Pinned files stay; a clock badge marks files that expire soon.",
                    help: "Choose how long Tray files are kept. Smart expiration tracking counts from when each file was added.",
                    anchor: "shelf.autoCleanup") {
            Picker("Auto-cleanup", selection: $traySettings.expiry) {
                ForEach(TrayExpiry.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
        SettingsDivider()
        SettingsToggleRow("Two Stacks",
                          subtitle: "Keep two separate stacks of files; the 1 | 2 pill on the Tray switches between them.",
                          anchor: "shelf.twoStacks", isOn: $traySettings.twoStacks)
    }
}

// MARK: - Basket page

struct BasketSettingsPage: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject private var basketSettings = BasketSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Floating Basket") {
                SettingsGroup {
                    SettingsToggleRow("Floating Basket", subtitle: "Shows or hides the Basket now; its files stay.", icon: "basket.fill",
                                      help: "A detachable basket that floats above every app and Space, so you can gather files from anywhere. This switch shows or hides it right now; shaking a drag, Instant appear or the Summon Basket shortcut bring it back.",
                                      anchor: "basket.show", isOn: $state.isBasketVisible)
                    ToggleTiles([
                        ToggleTile("Instant appear", icon: "bolt.fill", isOn: $basketSettings.instantAppear),
                        ToggleTile("Auto-hide", icon: "eye.slash", isOn: $basketSettings.autoHide),
                    ], anchor: "basket.instant")
                    if basketSettings.instantAppear {
                        SettingsDivider()
                        SettingsSlider("Instant delay", value: $basketSettings.instantDelay, in: 0...1.5, step: 0.05, defaultValue: 0.35,
                                       help: "How long a file drag lasts before the Basket appears on its own, no shake needed.") {
                            String(format: "%.2f s", $0)
                        }
                    }
                    if basketSettings.autoHide {
                        SettingsDivider()
                        SettingsSlider("Hide after", value: $basketSettings.autoHideDelay, in: 1...15, step: 0.5, defaultValue: 3,
                                       help: "How long the Basket waits before hiding once it's idle: no drag going on and the pointer away from it. Its files are kept.") {
                            String(format: "%.1f s", $0)
                        }
                    }
                    SettingsDivider()
                    SettingsToggleRow("Shake to summon",
                                      subtitle: "Shake a file drag and the Basket appears beside the pointer.",
                                      anchor: "basket.shake", isOn: $basketSettings.jiggleToOpenBasket)
                    SettingsDivider()
                    SettingsSlider("Shake sensitivity", value: $basketSettings.shakeSensitivity, in: 0...1, step: 0.25, defaultValue: 0.5,
                                   help: "How much shaking brings the Basket: higher needs only a small, quick shake.",
                                   anchor: "basket.sensitivity",
                                   subtitle: basketSettings.jiggleToOpenBasket ? nil : "Needs Shake to summon.") { JiggleService.sensitivityLabel($0) }
                        .settingsDisabled(!basketSettings.jiggleToOpenBasket)
                    SettingsDivider()
                    ModifierRecorderRow("Drag shortcut",
                                        help: "Press this while dragging to reveal the basket. Record a modifier combination, such as ⌥ Option.",
                                        anchor: "basket.dragShortcut", flags: $basketSettings.dragModifiers)
                    SettingsDivider()
                    ShortcutRecorderRow(.toggleBasket, title: "Summon Basket", anchor: "basket.shortcut")
                }
            }

            SettingsSection("Multi-Basket") {
                SettingsGroup {
                    SettingsRow("Basket mode",
                                help: "Single Basket: only one basket at a time. Multi-Basket: jiggling while a basket is open spawns another basket, each color-sorted.",
                                anchor: "basket.mode")
                    ChoiceTiles([
                        .init(BasketMode.single, "Single Basket", icon: "tray"),
                        .init(BasketMode.multi, "Multi-Basket", icon: "square.stack.3d.up.fill"),
                    ], selection: $basketSettings.mode)
                    SettingsDivider()
                    ShortcutRecorderRow(.basketSwitcher,
                                        help: "Shortcut to show all baskets and switch between them.",
                                        anchor: "basket.switcher")
                    SettingsDivider()
                    SettingsToggleRow("Second bucket",
                                      subtitle: "Add a second bucket for rarely used items; the Main | 2nd pill in the Basket switches.",
                                      anchor: "basket.secondBucket", isOn: $basketSettings.secondBucket)
                }
            }
        }
    }
}

/// A modifier-only shortcut (held while dragging): the keys in a pill, a
/// blue "Record shortcut" button and a reset. While recording, releasing
/// the modifiers records what was held; Esc cancels, ⌫ clears.
struct ModifierRecorderRow: View {
    let title: String
    var help: String?
    var anchor: String?
    @Binding var flags: Int
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var peak: NSEvent.ModifierFlags = []

    init(_ title: String, help: String? = nil, anchor: String? = nil, flags: Binding<Int>) {
        self.title = title
        self.help = help
        self.anchor = anchor
        self._flags = flags
    }

    static func display(_ raw: Int) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(max(raw, 0)))
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text.isEmpty ? "None" : text
    }

    var body: some View {
        SettingsRow(title, help: help, anchor: anchor) {
            HStack(spacing: 8) {
                Text(isRecording ? (peak.isEmpty ? "Hold keys…" : Self.display(Int(peak.rawValue))) : Self.display(flags))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isRecording ? .secondary : .primary)
                    .padding(.horizontal, 14)
                    .frame(minWidth: 96, minHeight: 26)
                    .background(Color.white.opacity(0.08), in: Capsule())
                Button(isRecording ? "Cancel" : "Record shortcut") { isRecording ? stop() : start() }
                    .buttonStyle(.borderedProminent)
                    .tint(isRecording ? .gray : .blue)
                Button {
                    flags = 0
                } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 12, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(flags == 0)
                .opacity(flags == 0 ? 0.3 : 1)
                .help("Back to None")
                .accessibilityLabel("Clear \(title)")
            }
        }
        .onDisappear { stop() }
    }

    private static let relevant: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    private func start() {
        peak = []
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            if event.type == .keyDown {
                if event.keyCode == 53 { stop() }                      // Esc
                if event.keyCode == 51 { flags = 0; stop() }           // ⌫
                return nil
            }
            let now = event.modifierFlags.intersection(Self.relevant)
            if now.isEmpty {
                if !peak.isEmpty {
                    flags = Int(peak.rawValue)
                    DroppyAudio.playTick()
                }
                stop()
            } else if now.isSuperset(of: peak) {
                peak = now
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}
