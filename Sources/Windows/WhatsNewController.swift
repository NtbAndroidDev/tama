import SwiftUI
import AppKit

/// What's New after an update, and the Setup Guide ("Recommended setup",
/// a quick one-time checklist). Both open from Settings › About; What's New
/// also opens by itself once when the version changes.
@MainActor
final class WhatsNewController: NSObject {
    static let shared = WhatsNewController()
    static let lastVersionKey = "lastSeenWhatsNewVersion"

    enum Tab: String { case whatsNew, setup }

    private var window: NSWindow?
    private let model = WhatsNewModel()

    private override init() { super.init() }

    static var currentVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "dev") (\(info?["CFBundleVersion"] as? String ?? "0"))"
    }

    /// Shows What's New when this version is newer than the last one seen.
    /// A first run gets the welcome tour instead, so it only records the version.
    func showIfUpdated() {
        let defaults = UserDefaults.standard
        let current = Self.currentVersion
        let last = defaults.string(forKey: Self.lastVersionKey)
        defaults.set(current, forKey: Self.lastVersionKey)
        guard let last, last != current, AppState.shared.showWhatsNew,
              defaults.bool(forKey: OnboardingWindowController.completedKey) else { return }
        DroppyLog.info("App", "Updated from \(last) to \(current)")
        // Let the notch settle first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.show(.whatsNew) }
    }

    func show(_ tab: Tab) {
        model.tab = tab
        if window == nil {
            let size = ToolWindowMetrics.whatsNewSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: WhatsNewView(model: model) { [weak self] in self?.window?.close() })
            // The window sets its own frame and minSize, so SwiftUI must not also
            // push content-size extrema onto it — that feedback is what AppKit
            // aborts with an "Update Constraints in Window" throw.
            host.sizingOptions = []
            window.contentView = host
            window.center()
            self.window = window
        }
        window?.title = tab == .whatsNew ? "What's New" : "Setup Guide"
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class WhatsNewModel: ObservableObject {
    @Published var tab: WhatsNewController.Tab = .whatsNew
}

/// The newest section of CHANGELOG.md, split into its bold group headings.
struct ReleaseNotes: Equatable {
    struct Group: Equatable {
        var title: String
        var items: [String]
    }

    var title: String
    var groups: [Group]

    /// Reads the first "## " section. Bold-only lines ("**Settings window**")
    /// start a group; "- " lines are its items.
    static func latest(from markdown: String) -> ReleaseNotes? {
        var title: String?
        var groups: [Group] = []
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                if title != nil { break }
                title = String(line.dropFirst(3))
                continue
            }
            guard title != nil, !line.isEmpty else { continue }
            if line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4 {
                groups.append(Group(title: String(line.dropFirst(2).dropLast(2)), items: []))
            } else if line.hasPrefix("- ") {
                if groups.isEmpty { groups.append(Group(title: "New Features", items: [])) }
                groups[groups.count - 1].items.append(String(line.dropFirst(2)))
            }
        }
        guard let title else { return nil }
        return ReleaseNotes(title: title, groups: groups.filter { !$0.items.isEmpty })
    }

    static func bundled() -> ReleaseNotes? {
        let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("CHANGELOG.md")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return latest(from: text)
    }
}

private struct WhatsNewView: View {
    @ObservedObject var model: WhatsNewModel
    let close: () -> Void
    @ObservedObject private var state = AppState.shared

    var body: some View {
        VStack(spacing: 14) {
            Picker("Show", selection: $model.tab) {
                Text("What's New").tag(WhatsNewController.Tab.whatsNew)
                Text("Setup Guide").tag(WhatsNewController.Tab.setup)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .padding(.top, 26)

            Group {
                switch model.tab {
                case .whatsNew: WhatsNewNotes()
                case .setup: SetupGuideList()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                if model.tab == .whatsNew {
                    Toggle("Show after updates", isOn: $state.showWhatsNew)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                } else {
                    // The checklist gets you set up; the guide explains what
                    // you just switched on.
                    Button("Tama Guide…") { UserGuideWindowController.shared.show() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(state.accentColor.color)
                        .help("Open the Tama Guide")
                }
                Spacer()
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
        }
        // Esc closes it too, as it does every other Tama panel.
        .background {
            Button("", action: close)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(width: ToolWindowMetrics.whatsNewSize.width, height: ToolWindowMetrics.whatsNewSize.height)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea())
        .tint(state.accentColor.color)
    }
}

private struct WhatsNewNotes: View {
    private let notes = ReleaseNotes.bundled()
    @ObservedObject private var state = AppState.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(state.accentColor.color.gradient))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New in Tama").font(.system(size: 18, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                        Text(notes?.title ?? WhatsNewController.currentVersion)
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                if let notes, !notes.groups.isEmpty {
                    ForEach(notes.groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.title).font(.system(size: 13, weight: .semibold))
                                .accessibilityAddTraits(.isHeader)
                            ForEach(group.items, id: \.self) { item in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("•").foregroundStyle(.secondary).accessibilityHidden(true)
                                    Text((try? AttributedString(markdown: item)) ?? AttributedString(item))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.system(size: 12))
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SettingsStyle.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                } else {
                    Text("Bug fixes and more polish. The full history is in Settings › About › Changelog.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// "Recommended setup": each step shows whether it's done, with a button to
/// do it. Steps that can't be detected can be ticked off by hand.
struct SetupGuideList: View {
    @ObservedObject private var permissions = PermissionService.shared
    @ObservedObject private var launch = LaunchAtLoginService.shared
    @ObservedObject private var state = AppState.shared
    @AppStorage("setupGuideDone") private var manualDone: String = ""

    struct Step: Identifiable {
        let id: String
        let icon: String
        let title: String
        let detail: String
        let isDone: Bool
        let actionTitle: String
        let action: () -> Void
    }

    private var steps: [Step] {
        let manual = Set(manualDone.split(separator: ",").map(String.init))
        return [
            Step(id: "accessibility", icon: "accessibility", title: "Allow \(PermissionService.accessibilityName)",
                 detail: "Media keys, Window Snap, the clipboard's paste and hiding the system HUDs.",
                 isDone: permissions.status(.accessibility) == .granted, actionTitle: "Allow") {
                permissions.request(.accessibility)
            },
            Step(id: "login", icon: "power", title: "Open at login",
                 detail: "Keep the notch ready after every restart.",
                 isDone: launch.isEnabled, actionTitle: "Turn On") { launch.setEnabled(true) },
            Step(id: "music", icon: "music.note", title: "Control Music",
                 detail: "Play, skip and scrub Apple Music from the notch.",
                 isDone: permissions.status(.automationMusic) == .granted, actionTitle: "Allow") {
                permissions.request(.automationMusic)
            },
            Step(id: "calendar", icon: "calendar", title: "Show your calendar",
                 detail: "Events and reminders on the Calendar page.",
                 isDone: permissions.status(.calendars) == .granted, actionTitle: "Allow") {
                permissions.request(.calendars)
            },
            Step(id: "widgets", icon: "square.grid.2x2.fill", title: "Pick your Droplets",
                 detail: "Turn on the widgets you want in Settings › Droplets.",
                 isDone: manual.contains("widgets"), actionTitle: "Open") {
                mark("widgets")
                SettingsWindowController.shared.showWindow(page: .droplets)
            },
            Step(id: "clipboard", icon: "clipboard.fill", title: "Try the clipboard",
                 detail: GlobalShortcutService.shared.display(for: .toggleClipboard)
                    .map { "Press \($0) to open your history." }
                    ?? "Record a shortcut for it in Settings › Clipboard, then open your history from anywhere.",
                 isDone: state.clipboardEnabled && manual.contains("clipboard"), actionTitle: "Show") {
                mark("clipboard")
                if !state.clipboardEnabled { state.clipboardEnabled = true }
                SettingsWindowController.shared.showWindow(page: .clipboard)
            },
            Step(id: "drop", icon: "tray.and.arrow.down.fill", title: "Drop a file on the notch",
                 detail: "Drag anything onto the notch to hold it in the Tray, or shake it for the Basket.",
                 isDone: !state.shelfItems.isEmpty || manual.contains("drop"), actionTitle: "Open Tray") {
                mark("drop")
                state.open(.tray)
            },
        ]
    }

    private func mark(_ id: String) {
        var set = Set(manualDone.split(separator: ",").map(String.init))
        set.insert(id)
        manualDone = set.sorted().joined(separator: ",")
    }

    var body: some View {
        let steps = steps
        let done = steps.filter(\.isDone).count
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(DS.Palette.track, lineWidth: 5)
                    Circle().trim(from: 0, to: CGFloat(done) / CGFloat(max(steps.count, 1)))
                        .stroke(state.accentColor.color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recommended setup").font(.system(size: 18, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Quick one-time setup · \(done) of \(steps.count) done")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        if index > 0 { SettingsDivider() }
                        HStack(spacing: 10) {
                            Image(systemName: step.isDone ? "checkmark.circle.fill" : step.icon)
                                .font(.system(size: 15))
                                .foregroundStyle(step.isDone ? DS.Palette.success : .secondary)
                                .frame(width: 22)
                                .accessibilityLabel(step.isDone ? "Done" : "To do")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title).font(.system(size: 13, weight: .medium))
                                Text(step.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            if !step.isDone {
                                Button(step.actionTitle, action: step.action).controlSize(.small)
                                    .accessibilityLabel("\(step.actionTitle): \(step.title)")
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                    }
                }
                .background(SettingsStyle.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .onAppear { permissions.refresh(); launch.refresh() }
    }
}
