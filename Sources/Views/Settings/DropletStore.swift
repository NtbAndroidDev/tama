import SwiftUI

// MARK: - Droplets store
//
// Settings › Droplets, laid out like the reference store: filter chips,
// an "Explore" title, a hero carousel of featured droplets (art drawn here,
// nothing copied), then a two-column list. A row opens the droplet's page:
// title bar with Set Up / Turn On, big icon, chips, an illustration, the
// description and the droplet's own settings.

/// The store's filter chips. None selected shows everything.
enum DropletStoreFilter: String, CaseIterable, Identifiable {
    case installed, ai, productivity, media
    var id: String { rawValue }

    var title: String {
        switch self {
        case .installed: "Installed"
        case .ai: "AI"
        case .productivity: "Productivity"
        case .media: "Media"
        }
    }

    var icon: String {
        switch self {
        case .installed: "checkmark.circle.fill"
        case .ai: "sparkles"
        case .productivity: "bolt.fill"
        case .media: "music.note"
        }
    }

    func includes(_ droplet: DropletModel) -> Bool {
        switch self {
        case .installed: droplet.isEnabled
        case .ai: droplet.category == .ai
        case .productivity: droplet.category == .productivity
        case .media: droplet.category == .media
        }
    }
}

/// Store copy and state that isn't part of `DropletModel`.
@MainActor
enum DropletStoreInfo {
    /// Featured in the hero carousel, in this order, with our own taglines.
    static let featured: [(id: String, tagline: String)] = [
        ("thunderstorm", "Your whole Mac, one keystroke away"),
        ("localSend", "Send to any phone or PC nearby"),
        ("agents", "Watch your coding agents work"),
        ("voiceTranscribe", "Talk. Get text. All on-device."),
        ("meetings", "Every call, under control"),
        ("weather", "The forecast, right in the notch"),
        ("aiCutout", "Subjects out, backgrounds gone"),
        ("termiNotch", "A real shell above your work"),
        ("menuBar", "A tidy menu bar in one click"),
        ("notchface", "A mirror before every call"),
    ]

    /// Droplets that grew out of community requests, captioned like the reference.
    static let community: Set<String> = ["caffeine", "meetings", "timer", "mechey"]

    static func caption(for droplet: DropletModel) -> String {
        community.contains(droplet.id) ? "Community droplet" : droplet.category.rawValue
    }

    /// What a droplet still needs before it fully works, and how to get it.
    struct Setup {
        let reason: String
        let action: () -> Void
    }

    static func setup(for id: String) -> Setup? {
        let permissions = PermissionService.shared
        func missing(_ kinds: [PermissionService.Kind], _ reason: String) -> Setup? {
            guard let kind = kinds.first(where: { permissions.status($0) != .granted }) else { return nil }
            return Setup(reason: reason) { permissions.request(kind) }
        }
        switch id {
        case "appleMusic":
            return missing([.automationMusic], "Allow Tama to control Music for play, skip and scrub.")
        case "windowSnapper", "liquidMouse":
            return missing([.accessibility], "\(PermissionService.accessibilityName) access moves windows and smooths scrolling.")
        case "meetings":
            return missing([.accessibility], "\(PermissionService.accessibilityName) access presses the call app's mute, camera and hang-up shortcuts.")
        case "snipper":
            return missing([.screenRecording], "Screen Recording lets Element Capture take screenshots.")
        case "voiceTranscribe":
            return missing([.microphone, .speechRecognition], "The microphone and Speech Recognition turn recordings into text.")
        case "mechey":
            return missing([.inputMonitoring], "Input Monitoring lets Mechey hear key presses to play their sounds.")
        case "notifications":
            guard NotificationHUDService.shared.status == .needsFullDiskAccess else { return nil }
            return Setup(reason: "Full Disk Access lets Tama read the macOS notification store.") {
                NotificationHUDService.shared.openFullDiskAccessSettings()
            }
        case "obsidian":
            guard ObsidianService.shared.vaultURL == nil else { return nil }
            return Setup(reason: "Choose your Obsidian vault folder.") { ObsidianService.shared.pickVault() }
        default:
            return nil
        }
    }
}

struct DropletsStoreTab: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var permissions = PermissionService.shared
    @Binding var openDropletID: String?
    @State private var filter: DropletStoreFilter?

    private var visible: [DropletModel] {
        let all = state.droplets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard let filter else { return all }
        return all.filter(filter.includes)
    }

    private var featured: [(droplet: DropletModel, tagline: String)] {
        DropletStoreInfo.featured.compactMap { entry in
            guard let droplet = state.droplets.first(where: { $0.id == entry.id }),
                  filter?.includes(droplet) ?? true else { return nil }
            return (droplet, entry.tagline)
        }
    }

    var body: some View {
        if let id = openDropletID, let index = state.droplets.firstIndex(where: { $0.id == id }) {
            DropletDetailView(droplet: $state.droplets[index]) {
                withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.fluid)) { openDropletID = nil }
            }
        } else {
            store
        }
    }

    private var store: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                chips
                Text("Explore")
                    .font(.system(size: 34, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.leading, 4)
                    .settingsAnchor("droplets.store")
                if !featured.isEmpty {
                    DropletHeroCarousel(items: featured) { open($0) }
                        .id(filter)
                }
                list
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { permissions.refresh() }
    }

    private var chips: some View {
        HStack(spacing: 10) {
            StoreFilterChip(title: "All", icon: "square.grid.2x2.fill", isSelected: filter == nil) {
                withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.snap)) { filter = nil }
                DroppyAudio.playTick()
            }
            ForEach(DropletStoreFilter.allCases) { option in
                StoreFilterChip(title: option.title, icon: option.icon, isSelected: filter == option,
                                count: option == .installed ? state.droplets.filter(\.isEnabled).count : nil) {
                    withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.snap)) {
                        filter = filter == option ? nil : option
                    }
                    DroppyAudio.playTick()
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var list: some View {
        if visible.isEmpty {
            DroppyEmptyState(systemName: "drop", title: "No droplets here yet",
                             subtitle: filter == .installed ? "Turn a droplet on and it shows up here." : "Try another category.")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
        } else {
            let columns = [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                ForEach(visible) { droplet in
                    DropletStoreRow(droplet: droplet, needsSetup: DropletStoreInfo.setup(for: droplet.id) != nil) {
                        open(droplet)
                    }
                }
            }
        }
    }

    private func open(_ droplet: DropletModel) {
        DroppyAudio.playTick()
        withAnimation(DS.Motion.respecting(DS.Motion.reduceMotion, DS.Motion.fluid)) { openDropletID = droplet.id }
    }
}

/// A big glass filter capsule (Installed | AI | Productivity | Media).
private struct StoreFilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    var count: Int?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 13.5, weight: .semibold))
                if let count, isSelected {
                    Text("\(count)").font(.system(size: 11, weight: .bold)).monospacedDigit()
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.2)))
                }
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 15)
            .frame(height: 34)
            .background(Capsule().fill(isSelected ? Color.white.opacity(0.2) : (isHovered ? Color.white.opacity(0.1) : Color.white.opacity(0.06))))
            .overlay(Capsule().strokeBorder(Color.white.opacity(isSelected ? 0.25 : 0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.96))
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Hero carousel

private struct DropletHeroCarousel: View {
    let items: [(droplet: DropletModel, tagline: String)]
    let open: (DropletModel) -> Void
    @State private var index = 0
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let timer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                let item = items[min(index, items.count - 1)]
                Button { open(item.droplet) } label: {
                    DropletHeroCard(droplet: item.droplet, tagline: item.tagline)
                }
                .buttonStyle(PressableStyle(scale: 0.985))
                .id(item.droplet.id)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                                    removal: .move(edge: .leading).combined(with: .opacity)))
                .accessibilityLabel("\(item.droplet.name). \(item.tagline)")
                .accessibilityHint("Opens the droplet's page")

                HStack {
                    arrow("chevron.left", help: "Previous") { step(-1) }
                    Spacer()
                    arrow("chevron.right", help: "Next") { step(1) }
                }
                .padding(.horizontal, -14)
            }
            .frame(height: ToolWindowMetrics.dropletHeroHeight)
            .clipped()
            .padding(.horizontal, 14)
            .onHover { isHovered = $0 }

            HStack(spacing: 6) {
                ForEach(items.indices, id: \.self) { i in
                    Button { go(to: i) } label: {
                        Capsule()
                            .fill(Color.white.opacity(i == index ? 0.85 : 0.3))
                            .frame(width: i == index ? 22 : 7, height: 7)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(items[i].droplet.name)
                    .accessibilityLabel("Page \(i + 1) of \(items.count): \(items[i].droplet.name)")
                    .accessibilityAddTraits(i == index ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onReceive(timer) { _ in
            // Auto-advance, paused while the pointer is over it, and off
            // under Reduce Motion: content that moves on its own is exactly
            // what that setting asks to stop.
            guard !isHovered, !reduceMotion, items.count > 1 else { return }
            step(1)
        }
    }

    private func arrow(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(help)
        .help(help)
        .disabled(items.count < 2)
    }

    private func step(_ delta: Int) {
        go(to: (index + delta + items.count) % items.count)
    }

    private func go(to i: Int) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.86)) { index = i }
    }
}

/// The big featured card: the name and tagline on the left, and on the right
/// the droplet's own console as it will look in the notch. The reference puts
/// a screenshot there; we draw ours, which is the same promise kept honestly.
private struct DropletHeroCard: View {
    let droplet: DropletModel
    let tagline: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            DropletArt(id: droplet.id, symbol: droplet.iconSystemName)
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(droplet.name)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                    Spacer(minLength: 8)
                    Text(tagline)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                    if droplet.isEnabled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.3)))
                            .padding(.top, 10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                DropletShelfMock(droplet: droplet, width: 272)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
        }
        .frame(maxWidth: .infinity)
        .frame(height: ToolWindowMetrics.dropletHeroHeight)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
    }
}

/// Our own art for a droplet: a deep gradient in its tint, sweeping light
/// streaks and a motif for what it does. Used by the hero and the detail page.
struct DropletArt: View {
    let id: String
    let symbol: String

    var body: some View {
        let tint = DropletPalette.tint(for: id)
        ZStack {
            LinearGradient(colors: [Color(white: 0.05), tint.opacity(0.55), Color(white: 0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { context, size in
                let w = size.width, h = size.height
                for (i, offset) in [0.0, 0.18, 0.34].enumerated() {
                    var path = Path()
                    path.move(to: CGPoint(x: w * (0.05 + offset), y: h * 1.05))
                    path.addCurve(to: CGPoint(x: w * 1.05, y: h * (0.05 + offset * 0.8)),
                                  control1: CGPoint(x: w * (0.45 + offset), y: h * 0.75),
                                  control2: CGPoint(x: w * 0.7, y: h * (0.25 + offset)))
                    var glow = context
                    glow.addFilter(.blur(radius: 10))
                    glow.stroke(path, with: .color(tint.opacity(0.5)), lineWidth: 10 - Double(i) * 2)
                    context.stroke(path, with: .color(.white.opacity(0.5 - Double(i) * 0.12)), lineWidth: 1.4)
                }
            }
            motif(tint: tint)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func motif(tint: Color) -> some View {
        switch id {
        case "thunderstorm":
            // A launcher bar.
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                Text("Search your Mac").font(.system(size: 14))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 18)
            .frame(height: 42)
            .background(Capsule().fill(Color.black.opacity(0.75)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.15)))
            .padding(.horizontal, 40)
        case "localSend":
            ZStack {
                ForEach(0..<3) { ring in
                    Circle()
                        .stroke(Color.white.opacity(0.28 - Double(ring) * 0.07),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: [16, 14]))
                        .frame(width: 70 + CGFloat(ring) * 52, height: 70 + CGFloat(ring) * 52)
                }
                Circle().fill(tint).frame(width: 44, height: 44)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 40)
        case "agents", "termiNotch":
            VStack(alignment: .leading, spacing: 6) {
                Text("$ claude \"fix the build\"").foregroundStyle(.white.opacity(0.8))
                Text("✓ Edited 3 files").foregroundStyle(Color.green.opacity(0.8))
                Text("● Running tests…").foregroundStyle(.white.opacity(0.5))
            }
            .font(.system(size: 13, design: .monospaced))
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.7)))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 36)
        default:
            Image(systemName: symbol)
                .font(.system(size: 120, weight: .semibold))
                .foregroundStyle(.white.opacity(0.14))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 36)
                .rotationEffect(.degrees(-8))
        }
    }
}

// MARK: - List row

/// One droplet in the two-column list: 56 pt icon, category caption, bold
/// title, a two-line subtitle and a chevron; lighter on hover.
private struct DropletStoreRow: View {
    let droplet: DropletModel
    let needsSetup: Bool
    let open: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                DropletIcon(id: droplet.id, symbol: droplet.iconSystemName, size: ToolWindowMetrics.dropletListIcon)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(DropletStoreInfo.caption(for: droplet))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(droplet.name)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                        if droplet.isEnabled {
                            Image(systemName: needsSetup ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(needsSetup ? Color.orange : Color.green)
                                .help(needsSetup ? "Needs setup" : "Installed")
                                .accessibilityHidden(true)
                        }
                    }
                    Text(droplet.tag)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isHovered ? .primary : .tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(minHeight: 82)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.08) : .clear))
            .overlay(alignment: .bottom) {
                Rectangle().fill(SettingsStyle.hairline).frame(height: 1)
                    .padding(.leading, ToolWindowMetrics.dropletListIcon + 24)
                    .opacity(isHovered ? 0 : 1)
            }
            .contentShape(Rectangle())
            .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: isHovered)
        }
        // Dips slightly while held (a dim instead under Reduce Motion), so a
        // click on the row is felt before the page swaps in.
        .buttonStyle(PressableStyle(scale: 0.985))
        .onHover { isHovered = $0 }
        .help(droplet.summary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(droplet.name), \(DropletStoreInfo.caption(for: droplet)), \(droplet.isEnabled ? (needsSetup ? "installed, needs setup" : "installed") : "not installed")")
        .accessibilityValue(droplet.tag)
        .accessibilityHint("Opens the droplet's page")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Detail page

/// A droplet's own page.
struct DropletDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var droplet: DropletModel
    let back: () -> Void
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var permissions = PermissionService.shared
    @ObservedObject private var navigator = SettingsNavigator.shared
    @ObservedObject private var notifications = NotificationHUDService.shared

    private var hasHomeCard: Bool { HomeWidget.cardDroplets.contains(droplet.id) }
    private var setup: DropletStoreInfo.Setup? { DropletStoreInfo.setup(for: droplet.id) }
    private var tagline: String {
        DropletStoreInfo.featured.first { $0.id == droplet.id }?.tagline ?? droplet.tag
    }

    /// Settings › "Show in Settings sidebar" for this droplet.
    private var showsInSidebar: Binding<Bool> {
        Binding(
            get: { !state.sidebarHiddenDroplets.split(separator: ",").contains(Substring(droplet.id)) },
            set: { show in
                var ids = Set(state.sidebarHiddenDroplets.split(separator: ",").map(String.init))
                if show { ids.remove(droplet.id) } else { ids.insert(droplet.id) }
                state.sidebarHiddenDroplets = ids.sorted().joined(separator: ",")
            }
        )
    }

    /// On the home page or off it, keeping at most two widgets and never none.
    private var showsOnHome: Binding<Bool> {
        Binding(
            get: { state.homeWidgets.contains(droplet.id) },
            set: { on in
                var widgets = state.homeWidgets.filter { $0 != droplet.id }
                if on {
                    if widgets.count >= HomeWidget.limit { widgets.removeLast() }
                    widgets.append(droplet.id)
                }
                state.homeWidgets = widgets.isEmpty ? [HomeWidget.media] : widgets
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 6)
            ScrollViewReader { proxy in
                Form {
                    Section {
                        Text(droplet.summary)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let setup {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                                    .accessibilityHidden(true)
                                Text(setup.reason).fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Button("Set Up", action: setup.action)
                            }
                            .font(.system(size: 12))
                        }
                    } header: {
                        hero
                    }
                    useSection
                    // The droplet's own options.
                    DropletSettingsSections(id: droplet.id)
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .onAppear { scroll(proxy) }
                .onChange(of: navigator.scrollTarget) { _, _ in scroll(proxy) }
            }
        }
        .onAppear { permissions.refresh() }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let target = navigator.scrollTarget, target.hasPrefix("droplet.") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid)) { proxy.scrollTo(target, anchor: .center) }
            navigator.scrollTarget = nil
        }
    }

    // MARK: Title bar

    private var titleBar: some View {
        HStack(spacing: 12) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("All Droplets")
            .accessibilityLabel("Back to all droplets")
            Text(droplet.name)
                .font(.system(size: 28, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let setup {
                DetailPill(title: "Set Up", icon: nil, fill: Color.red.opacity(0.75), foreground: .white, action: setup.action)
                    .help(setup.reason)
            }
            DetailPill(title: droplet.isEnabled ? "Turn Off" : "Turn On", icon: "power",
                       fill: Color.white.opacity(0.1),
                       foreground: droplet.isEnabled ? .primary : .green) {
                withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.snap)) { droplet.isEnabled.toggle() }
                DroppyAudio.playTick()
            }
            .help(droplet.isEnabled ? "Turn \(droplet.name) off" : "Turn \(droplet.name) on")
            .accessibilityLabel(droplet.isEnabled ? "Turn \(droplet.name) off" : "Turn \(droplet.name) on")
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 18) {
                DropletIcon(id: droplet.id, symbol: droplet.iconSystemName, size: 88)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                VStack(alignment: .leading, spacing: 10) {
                    Text(tagline)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        DetailChip(title: DropletStoreInfo.caption(for: droplet), tint: DropletPalette.tint(for: droplet.id))
                        if setup != nil {
                            DetailChip(title: "Needs setup", tint: .orange)
                        } else if droplet.isEnabled {
                            DetailChip(title: "Installed", tint: .green)
                        } else {
                            DetailChip(title: "Not installed", tint: .gray)
                        }
                        if droplet.isNew { DetailChip(title: "New", tint: .blue) }
                    }
                }
            }
            Rectangle().fill(SettingsStyle.hairline).frame(height: 1)
            DropletPreview(droplet: droplet)
                .frame(height: 220)
        }
        .textCase(nil)
        .foregroundStyle(.primary)
        .padding(.bottom, 8)
    }

    // MARK: Use

    private var useSection: some View {
        Section {
            if hasHomeCard {
                Toggle("Show on the Home page", isOn: showsOnHome)
                    .disabled(!droplet.isEnabled || state.isCustomizingHome)
            }
            LabeledContent("Open it in the notch") {
                Button("Open") {
                    state.open(.widgets)
                    state.activeDropletID = droplet.id
                }
                .disabled(!droplet.isEnabled)
            }
            FormShortcutRow(slot: .droplet(droplet.id), title: "Shortcut to open",
                            help: "Opens this widget's console in the shelf from anywhere; press it again to close. All shortcuts are listed under Keyboard Shortcuts.",
                            anchor: "droplet.\(droplet.id).openShortcut")
                .disabled(!droplet.isEnabled)
            Toggle(isOn: showsInSidebar) {
                HStack(spacing: 6) {
                    Text("Show in Settings sidebar")
                    InfoButton("List this droplet under Enabled Droplets in the sidebar while it's on, for quick access to its settings.")
                }
            }
            .disabled(!droplet.isEnabled)
            .settingsAnchor("droplet.\(droplet.id).sidebar")
        } header: {
            Text("Use")
        } footer: {
            if !droplet.isEnabled {
                Text("Turn \(droplet.name) on to use it from the notch.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if hasHomeCard, state.isCustomizingHome {
                Text("Finish customizing the Home page to change which widgets it shows.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if hasHomeCard {
                Text("The Home page holds up to two widgets; adding a third replaces the second.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct DetailPill: View {
    let title: String
    let icon: String?
    let fill: Color
    let foreground: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .bold)) }
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Capsule().fill(fill).brightness(isHovered ? 0.06 : 0))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.96))
        .onHover { isHovered = $0 }
    }
}

private struct DetailChip: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(tint.opacity(0.18)))
    }
}

/// The detail page's illustration: the droplet's art behind a miniature
/// shelf that shows its icon, name, a few content lines and the nav capsule.
private struct DropletPreview: View {
    let droplet: DropletModel

    var body: some View {
        ZStack {
            DropletArt(id: droplet.id, symbol: droplet.iconSystemName)
            // The shelf sits on the art with a drop shadow, the way a
            // screenshot of it on a wallpaper would.
            DropletShelfMock(droplet: droplet, width: 344, showsNavPill: true)
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
        .accessibilityHidden(true)
    }
}

/// The droplet's console drawn inside a miniature shelf — the black surface
/// with its soft bottom corners, and optionally the nav capsule below it — so
/// the picture reads as "this is what your notch will look like".
private struct DropletShelfMock: View {
    let droplet: DropletModel
    /// The width the mock has to fit into; the shelf is drawn at its natural
    /// size and scaled down to it, so every showcase stays in proportion.
    let width: CGFloat
    var showsNavPill = false

    private static let natural = ShowcaseMetrics.width + 28
    private var scale: CGFloat { min(width / Self.natural, 1) }

    var body: some View {
        VStack(spacing: 9) {
            DropletShowcase(droplet: droplet)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .frame(width: Self.natural)
                .background(
                    UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous)
                        .fill(Color.black.opacity(0.92))
                )
                .overlay(
                    UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08))
                )
                // Drawn at a fixed width so every showcase lines up, then
                // scaled to whatever the card gives it.
                .scaleEffect(scale, anchor: .top)
                .frame(width: width, height: (ShowcaseMetrics.height + 26) * scale)
            if showsNavPill {
                HStack(spacing: 12) {
                    Image(systemName: "house.fill")
                    Image(systemName: "tray.fill")
                    Image(systemName: "square.grid.2x2.fill")
                        .padding(5)
                        .background(Circle().fill(Color.white.opacity(0.22)))
                }
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Capsule().fill(.ultraThinMaterial))
            }
        }
        .accessibilityHidden(true)
    }
}
