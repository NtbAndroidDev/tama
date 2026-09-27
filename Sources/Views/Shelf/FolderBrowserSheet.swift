import SwiftUI
import AppKit

/// A pinned folder on the Shelf opens into this: its contents, searchable,
/// with subfolders to step into. Files drag straight out, open on a double
/// click, or join the Shelf with +.
struct FolderBrowserSheet: View {
    let root: URL
    let onClose: () -> Void

    /// One row, with everything it draws worked out when the folder was read.
    /// Reading it per row in `body` meant a `stat` for every visible file on
    /// every redraw — once per keystroke in the search field.
    private struct Entry: Identifiable, Hashable {
        let url: URL
        let isFolder: Bool
        let sizeText: String
        var id: URL { url }
        var name: String { url.lastPathComponent }
    }

    @State private var path: [URL] = []
    @State private var query = ""
    @State private var entries: [Entry] = []
    @State private var exists = true
    @State private var isLoading = false
    /// Row under the pointer, for hover feedback.
    @State private var hovered: URL?

    private var current: URL { path.last ?? root }

    private var shown: [Entry] {
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !exists {
                DroppyEmptyState(systemName: "questionmark.folder", title: "Folder not found",
                                 subtitle: "It was moved or deleted.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading {
                // A folder on a slow disk or a network share takes a moment;
                // an empty panel would read as "nothing in here".
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Reading this folder")
            } else if shown.isEmpty {
                DroppyEmptyState(systemName: query.isEmpty ? "folder" : "magnifyingglass",
                                 title: query.isEmpty ? "This folder is empty" : "Nothing in this folder matches",
                                 compact: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(shown) { entry in row(entry) }
                    }
                }
            }
        }
        .padding(DS.Space.lg)
        .frame(width: 420, height: 360)
        .background(Color.black.opacity(0.9))
        .preferredColorScheme(.dark)
        .task(id: current) { await load() }
        // Esc closes the sheet, like the Close button.
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if !path.isEmpty {
                DroppyIconButton("chevron.left", size: 24, tone: .tonal, help: "Back") {
                    path.removeLast()
                    query = ""
                }
            }
            Image(systemName: "folder.fill").foregroundStyle(DS.accent)
                .accessibilityHidden(true)
            Text(FileManager.default.displayName(atPath: current.path))
                .font(DS.Typo.title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 130)
                .accessibilityLabel("Search this folder")
            DroppyIconButton("folder", size: 24, tone: .tonal, help: "Open in Finder") { NSWorkspace.shared.open(current) }
            DroppyIconButton("xmark", size: 24, tone: .tonal, help: "Close", action: onClose)
        }
    }

    private func row(_ entry: Entry) -> some View {
        let url = entry.url
        let isFolder = entry.isFolder
        return HStack(spacing: 8) {
            Image(nsImage: FileIcon.image(for: url))
                .resizable()
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(entry.name)
                .font(DS.Typo.body)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if !isFolder {
                Text(entry.sizeText)
                    .font(DS.Typo.caption.monospacedDigit())
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            DroppyIconButton("plus", size: 20, help: "Add to Shelf") {
                AppState.shared.addShelfItems([ShelfItem(url: url)])
                DroppyAudio.playDropSuccess()
            }
            if isFolder {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(DS.Palette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(hovered == url ? DS.Palette.surface2 : DS.Palette.surface1)
        )
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = url } else if hovered == url { hovered = nil }
        }
        .onTapGesture(count: 2) { openEntry(entry) }
        .onDrag { NSItemProvider(object: url as NSURL) }
        .help(isFolder ? "Double-click to open this folder" : "Double-click to open; drag it anywhere")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isFolder ? "Folder \(entry.name)" : "\(entry.name), \(entry.sizeText)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openEntry(entry) }
        .accessibilityAction(named: "Add to Shelf") {
            AppState.shared.addShelfItems([ShelfItem(url: url)])
            DroppyAudio.playDropSuccess()
        }
    }

    /// Double-click (or VoiceOver's default action): step into a folder, open a file.
    private func openEntry(_ entry: Entry) {
        if entry.isFolder {
            path.append(entry.url)
            query = ""
        } else {
            NSWorkspace.shared.open(entry.url)
        }
    }

    /// Reads the folder off the main thread: `contentsOfDirectory` on a large
    /// or networked folder blocks for long enough to be felt, and every row's
    /// kind and size is settled here rather than while drawing.
    private func load() async {
        let folder = current
        isLoading = true
        let result = await Task.detached(priority: .userInitiated) { () -> (Bool, [Entry]) in
            var isDir: ObjCBool = false
            let isFolder = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir) && isDir.boolValue
            guard isFolder else { return (false, []) }
            let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
            let entries = contents.map { url -> Entry in
                let values = try? url.resourceValues(forKeys: Set(keys))
                let isDirectory = values?.isDirectory ?? false
                return Entry(
                    url: url,
                    isFolder: isDirectory,
                    sizeText: isDirectory ? "" : ByteCountFormatter.string(
                        fromByteCount: Int64(values?.fileSize ?? 0), countStyle: .file)
                )
            }
            return (true, entries.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            })
        }.value
        guard !Task.isCancelled else { return }
        exists = result.0
        entries = result.1
        isLoading = false
    }
}
