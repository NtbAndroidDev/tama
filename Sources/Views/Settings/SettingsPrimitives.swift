import SwiftUI
import AppKit

// MARK: - Settings building blocks
//
// The pieces every Settings page is built from, matching the reference's
// glass window: grey section titles over rounded group cards, rows split by
// hairlines, an ⓘ on rows that explain themselves, full-width tile rows, wallpaper
// preview cards, sliders with a value pill, shortcut recorders and summary
// rows that fold open. Pages compose these instead of `Form`, so the look is
// one system and search can scroll to (and flash) any row by its anchor.
//
// Usage:
//
//     SettingsSection("Startup") {
//         SettingsGroup {
//             SettingsRow("Startup & visibility", help: "…")
//             ToggleTiles([ToggleTile("Menu bar icon", icon: "menubar.rectangle", isOn: $x), …])
//         }
//     }

/// Sizes and fills shared by the building blocks.
enum SettingsStyle {
    static let cardRadius: CGFloat = 16
    static let rowPadding = EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14)
    static let tileHeight: CGFloat = 40
    static let cardFill = Color.white.opacity(0.055)
    static let tileOn = Color.white.opacity(0.17)
    static let tileHover = Color.white.opacity(0.07)
    static let hairline = Color.white.opacity(0.08)
    static let sectionTitle = Font.system(size: 13, weight: .semibold)
    static let rowTitle = Font.system(size: 13, weight: .regular)
    static let rowSubtitle = Font.system(size: 11)
}

// MARK: - Section and group

/// A grey section title (with optional subtitle and ⓘ) above its cards.
struct SettingsSection<Content: View>: View {
    let title: String
    var subtitle: String?
    var help: String?
    var anchor: String?
    @ViewBuilder let content: Content

    init(_ title: String, subtitle: String? = nil, help: String? = nil, anchor: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.help = help
        self.anchor = anchor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(SettingsStyle.sectionTitle).foregroundStyle(.secondary)
                    if let help { InfoButton(help) }
                }
                if let subtitle {
                    Text(subtitle).font(SettingsStyle.rowSubtitle).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, 12)
            .settingsAnchor(anchor)
            content
        }
    }
}

/// A rounded card holding rows. Put `SettingsDivider()` between rows.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsStyle.cardFill, in: RoundedRectangle(cornerRadius: SettingsStyle.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: SettingsStyle.cardRadius, style: .continuous))
    }
}

/// The hairline between two rows of a group, inset from the left edge.
struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(SettingsStyle.hairline).frame(height: 1).padding(.leading, 14)
    }
}

/// Grey caption text inside a group, for notes under a row.
struct SettingsNote: View {
    let text: String
    var icon: String?
    var tint: Color = .secondary

    init(_ text: String, icon: String? = nil, tint: Color = .secondary) {
        self.text = text
        self.icon = icon
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let icon { Image(systemName: icon).foregroundStyle(tint) }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(SettingsStyle.rowSubtitle)
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Rows

/// ⓘ that shows its text in a popover on click (and as a tooltip).
struct InfoButton: View {
    let text: String
    @State private var isShown = false

    init(_ text: String) { self.text = text }

    var body: some View {
        Button { isShown.toggle() } label: {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary.opacity(0.7))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(text)
        .accessibilityLabel("More info")
        .accessibilityHint(text)
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260, alignment: .leading)
                .padding(12)
        }
    }
}

/// One line in a group: optional icon, title (+ subtitle, ⓘ) and a trailing control.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var help: String?
    var anchor: String?
    @ViewBuilder let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, icon: String? = nil, help: String? = nil, anchor: String? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.help = help
        self.anchor = anchor
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(SettingsStyle.rowTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    if let help { InfoButton(help) }
                }
                if let subtitle {
                    Text(subtitle).font(SettingsStyle.rowSubtitle).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(SettingsStyle.rowPadding)
        .frame(minHeight: 44)
        .settingsAnchor(anchor)
    }
}

extension SettingsRow where Trailing == EmptyView {
    /// A title row with nothing trailing, e.g. above a tile row.
    init(_ title: String, subtitle: String? = nil, icon: String? = nil, help: String? = nil, anchor: String? = nil) {
        self.init(title, subtitle: subtitle, icon: icon, help: help, anchor: anchor) { EmptyView() }
    }
}

/// A row with a switch.
struct SettingsToggleRow: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var help: String?
    var anchor: String?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, icon: String? = nil, help: String? = nil, anchor: String? = nil,
         isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.help = help
        self.anchor = anchor
        self._isOn = isOn
    }

    var body: some View {
        SettingsRow(title, subtitle: subtitle, icon: icon, help: help, anchor: anchor) {
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

// MARK: - Dependent rows

extension View {
    /// Disables a row whose setting depends on another one and dims it the
    /// same way everywhere, so an unavailable option reads as unavailable.
    /// Say why in the row's subtitle or a `SettingsNote`.
    func settingsDisabled(_ isDisabled: Bool) -> some View {
        modifier(SettingsDisabledModifier(isDisabled: isDisabled))
    }
}

/// Dims only when nothing above has: a row inside an already-disabled group
/// stays at the group's 0.45 instead of fading to 0.2.
private struct SettingsDisabledModifier: ViewModifier {
    let isDisabled: Bool
    @Environment(\.isEnabled) private var isAncestorEnabled

    func body(content: Content) -> some View {
        content
            .disabled(isDisabled)
            .opacity(isDisabled && isAncestorEnabled ? 0.45 : 1)
    }
}

// MARK: - Tiles

/// One segment of a tile row: icon and label, lighter when on.
private struct TileSegment: View {
    let title: String
    let icon: String?
    let isOn: Bool
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 13)) }
                Text(title).font(.system(size: 13)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(isOn ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: SettingsStyle.tileHeight)
            .background(isOn ? SettingsStyle.tileOn : (isHovered && isEnabled ? SettingsStyle.tileHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: isOn)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// A full-width row of independent on/off tiles (Menu bar icon | Dock icon | Launch at login).
struct ToggleTile: Identifiable {
    let title: String
    var icon: String?
    var isOn: Binding<Bool>
    var id: String { title }

    init(_ title: String, icon: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.icon = icon
        self.isOn = isOn
    }
}

struct ToggleTiles: View {
    let tiles: [ToggleTile]
    var anchor: String?

    init(_ tiles: [ToggleTile], anchor: String? = nil) {
        self.tiles = tiles
        self.anchor = anchor
    }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(tiles) { tile in
                TileSegment(title: tile.title, icon: tile.icon, isOn: tile.isOn.wrappedValue) {
                    tile.isOn.wrappedValue.toggle()
                    DroppyAudio.playTick()
                }
            }
        }
        .background(SettingsStyle.hairline)
        .settingsAnchor(anchor)
    }
}

/// A full-width single-choice tile row (Regular | Enlarged).
struct ChoiceTiles<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
        var icon: String?
        init(_ value: Value, _ title: String, icon: String? = nil) {
            self.value = value
            self.title = title
            self.icon = icon
        }
    }

    let options: [Option]
    @Binding var selection: Value
    var anchor: String?

    init(_ options: [Option], selection: Binding<Value>, anchor: String? = nil) {
        self.options = options
        self._selection = selection
        self.anchor = anchor
    }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                TileSegment(title: option.title, icon: option.icon, isOn: selection == option.value) {
                    guard selection != option.value else { return }
                    selection = option.value
                    DroppyAudio.playTick()
                }
            }
        }
        .background(SettingsStyle.hairline)
        .settingsAnchor(anchor)
    }
}

// MARK: - Preview cards

/// The real desktop behind every Settings preview: the picture is cropped to
/// the screen's shape the way macOS fills a desktop with it, laid out at the
/// card's width, and the card shows its top strip — where the island lives. A
/// soft scrim keeps the black island shapes readable on a bright picture; when
/// the picture can't be read (a video wallpaper) a gradient stands in.
struct PreviewWallpaper: View {
    @ObservedObject private var wallpaper = DesktopWallpaperService.shared

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = wallpaper.image, image.size.width > 0 {
                    // The whole desktop, at this card's width.
                    let desktopHeight = max(geo.size.width / wallpaper.screenAspect, geo.size.height)
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: desktopHeight)
                        .clipped()
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                        .clipped()
                } else {
                    LinearGradient(colors: [Color(red: 0.16, green: 0.18, blue: 0.24),
                                            Color(red: 0.06, green: 0.07, blue: 0.10)],
                                   startPoint: .top, endPoint: .bottom)
                }
                LinearGradient(colors: [.black.opacity(0.3), .black.opacity(0.05)],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task { wallpaper.refresh() }
        .accessibilityHidden(true)
    }
}

/// One card of a `PreviewCardPicker`.
struct PreviewCardOption<Value: Hashable> {
    let value: Value
    let title: String
    var subtitle: String?

    init(_ value: Value, _ title: String, subtitle: String? = nil) {
        self.value = value
        self.title = title
        self.subtitle = subtitle
    }
}

/// Cards with a miniature of each option on the desktop wallpaper; the chosen
/// one gets a white border. `thumbnail` draws the miniature over the wallpaper.
struct PreviewCardPicker<Value: Hashable, Thumbnail: View>: View {
    let options: [PreviewCardOption<Value>]
    @Binding var selection: Value
    var columns = 2
    var thumbnailHeight: CGFloat = 88
    var anchor: String?
    @ViewBuilder let thumbnail: (Value) -> Thumbnail

    init(_ options: [PreviewCardOption<Value>], selection: Binding<Value>, columns: Int = 2,
         thumbnailHeight: CGFloat = 88, anchor: String? = nil,
         @ViewBuilder thumbnail: @escaping (Value) -> Thumbnail) {
        self.options = options
        self._selection = selection
        self.columns = columns
        self.thumbnailHeight = thumbnailHeight
        self.anchor = anchor
        self.thumbnail = thumbnail
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: columns),
                  spacing: 14) {
            ForEach(options.indices, id: \.self) { index in
                card(options[index])
            }
        }
        .padding(12)
        .settingsAnchor(anchor)
    }

    private func card(_ option: PreviewCardOption<Value>) -> some View {
        let isSelected = selection == option.value
        return Button {
            guard selection != option.value else { return }
            selection = option.value
            DroppyAudio.playTick()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    PreviewWallpaper()
                    thumbnail(option.value)
                }
                .frame(height: thumbnailHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? Color.white : Color.white.opacity(0.08), lineWidth: isSelected ? 2.5 : 1)
                )
                Text(option.title)
                    .font(.system(size: 12.5, weight: isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                if let subtitle = option.subtitle {
                    Text(subtitle).font(SettingsStyle.rowSubtitle).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// One card of a card grid (Settings › HUDs' System and Droplets grids):
/// a miniature on the desktop wallpaper with a title and subtitle under it.
/// On cards get the white border; a badge ("Set up") sits over the
/// miniature, which is dimmed while the card is off.
struct PreviewActionCard<Thumbnail: View>: View {
    let title: String
    var subtitle: String?
    var isOn: Bool
    var badge: String?
    var thumbnailHeight: CGFloat = 64
    var anchor: String?
    let action: () -> Void
    @ViewBuilder let thumbnail: Thumbnail
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: String, subtitle: String? = nil, isOn: Bool, badge: String? = nil, thumbnailHeight: CGFloat = 64,
         anchor: String? = nil, action: @escaping () -> Void, @ViewBuilder thumbnail: () -> Thumbnail) {
        self.title = title
        self.subtitle = subtitle
        self.isOn = isOn
        self.badge = badge
        self.thumbnailHeight = thumbnailHeight
        self.anchor = anchor
        self.action = action
        self.thumbnail = thumbnail()
    }

    var body: some View {
        Button {
            action()
            DroppyAudio.playTick()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    PreviewWallpaper()
                    thumbnail
                        .opacity(isOn ? 1 : 0.45)
                        .padding(.horizontal, 10)
                    if let badge {
                        VStack {
                            Spacer()
                            Text(badge)
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.75), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                                .padding(.bottom, 6)
                        }
                    }
                }
                .frame(height: thumbnailHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isOn ? Color.white : Color.white.opacity(isHovered ? 0.2 : 0.08),
                                      lineWidth: isOn ? 2.5 : 1)
                )
                Text(title)
                    .font(.system(size: 12.5, weight: isOn ? .bold : .semibold))
                    .foregroundStyle(isOn ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle).font(SettingsStyle.rowSubtitle).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.snap), value: isOn)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
        .accessibilityValue(badge ?? (isOn ? "On" : "Off"))
        .accessibilityAddTraits(isOn && badge == nil ? [.isButton, .isSelected] : .isButton)
        .settingsAnchor(anchor)
    }
}

/// A grid of `PreviewActionCard`s inside a group.
struct PreviewCardGrid<Content: View>: View {
    var columns = 3
    @ViewBuilder let content: Content

    init(columns: Int = 3, @ViewBuilder content: () -> Content) {
        self.columns = columns
        self.content = content()
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: columns),
                  spacing: 16) {
            content
        }
        .padding(12)
    }
}

// MARK: - Slider

/// A labelled slider with its value in a pill and, when a default is given
/// and the value is off it, a reset ↺.
struct SettingsSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    var defaultValue: Double?
    var help: String?
    var anchor: String?
    /// A line under the slider, e.g. why it's unavailable.
    var subtitle: String?
    let format: (Double) -> String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double? = nil,
         defaultValue: Double? = nil, help: String? = nil, anchor: String? = nil, subtitle: String? = nil,
         format: @escaping (Double) -> String) {
        self.title = title
        self.subtitle = subtitle
        self._value = value
        self.range = range
        self.step = step
        self.defaultValue = defaultValue
        self.help = help
        self.anchor = anchor
        self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            control
            if let subtitle {
                Text(subtitle).font(SettingsStyle.rowSubtitle).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SettingsStyle.rowPadding)
        .settingsAnchor(anchor)
    }

    private var control: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text(title).font(SettingsStyle.rowTitle).lineLimit(1)
                if let help { InfoButton(help) }
            }
            .layoutPriority(1)
            Group {
                if let step {
                    Slider(value: $value, in: range, step: step)
                } else {
                    Slider(value: $value, in: range)
                }
            }
            .labelsHidden()
            .accessibilityLabel(title)
            .accessibilityValue(format(value))
            Text(format(value))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .padding(.horizontal, 10)
                .frame(minWidth: 58, minHeight: 24)
                .background(Color.white.opacity(0.08), in: Capsule())
            if let defaultValue {
                Button {
                    withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.snap)) { value = defaultValue }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(abs(value - defaultValue) > 0.0001 ? 1 : 0.3)
                .disabled(abs(value - defaultValue) <= 0.0001)
                .help("Reset to default")
                .accessibilityLabel("Reset \(title)")
            }
        }
    }
}

// MARK: - Shortcut recorder

/// A global shortcut: the current keys in a pill (or "None"), a blue
/// "Record shortcut" button and a reset ↺. While recording, the next key
/// press with ⌃, ⌥ or ⌘ (or a function key) becomes the shortcut; Esc
/// cancels and ⌫ clears it. Hot keys are paused meanwhile, so pressing the
/// current combo records it instead of firing it. Changes register at once.
struct ShortcutRecorderRow: View {
    let slot: ShortcutSlot
    var title: String?
    var help: String?
    var anchor: String?
    @ObservedObject private var shortcuts = GlobalShortcutService.shared
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var message: String?

    init(_ action: ShortcutAction, title: String? = nil, help: String? = nil, anchor: String? = nil) {
        self.init(slot: .action(action), title: title, help: help, anchor: anchor)
    }

    init(slot: ShortcutSlot, title: String? = nil, help: String? = nil, anchor: String? = nil) {
        self.slot = slot
        self.title = title
        self.help = help
        self.anchor = anchor
    }

    private var current: KeyCombo? {
        _ = shortcuts.revision
        return shortcuts.combo(for: slot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(title ?? slot.title, help: help, anchor: anchor) {
                HStack(spacing: 8) {
                    Text(isRecording ? "Press keys…" : (current?.display ?? "None"))
                        .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isRecording ? .secondary : .primary)
                        .padding(.horizontal, 14)
                        .frame(minWidth: 96, minHeight: 26)
                        .background(Color.white.opacity(0.08), in: Capsule())
                    Button(isRecording ? "Cancel" : "Record shortcut") {
                        isRecording ? stop() : start()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isRecording ? .gray : .blue)
                    .controlSize(.regular)
                    Button {
                        shortcuts.resetCombo(for: slot)
                        message = nil
                    } label: {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 12, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(current == shortcuts.defaultCombo(for: slot))
                    .opacity(current == shortcuts.defaultCombo(for: slot) ? 0.3 : 1)
                    .help("Back to \(shortcuts.defaultCombo(for: slot)?.display ?? "None")")
                    .accessibilityLabel("Reset \(title ?? slot.title) shortcut")
                }
            }
            if let message {
                SettingsNote(message, icon: "exclamationmark.triangle.fill", tint: DS.Palette.warning)
            } else if shortcuts.failedSlots.contains(slot), let current {
                SettingsNote("Another app already uses \(current.display). Record a different shortcut.",
                             icon: "exclamationmark.triangle.fill", tint: DS.Palette.warning)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        message = nil
        isRecording = true
        shortcuts.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording { shortcuts.resume() }
        isRecording = false
    }

    private func handle(_ event: NSEvent) {
        let combo = KeyCombo(event: event)
        switch Int(event.keyCode) {
        case 53 where !combo.hasModifier: // Esc
            stop()
            return
        case 51 where !combo.hasModifier, 117 where !combo.hasModifier: // ⌫ / ⌦
            stop()
            shortcuts.setCombo(nil, for: slot)
            return
        default:
            break
        }
        guard combo.isValidGlobal else {
            message = "Add ⌃, ⌥ or ⌘ — a plain key would get in the way of typing."
            return
        }
        stop()
        if let owner = shortcuts.setCombo(combo, for: slot) {
            message = "\(combo.display) is already \u{201C}\(owner.title)\u{201D}."
        } else {
            DroppyAudio.playTick()
        }
    }
}

// MARK: - Summary rows

/// A small progress ring, e.g. "4 of 10 granted".
struct ProgressRing: View {
    let fraction: Double
    var size: CGFloat = 18
    var tint: Color = .orange

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A row that summarises a list ("4 of 10 granted ⌄") and folds it open in place.
struct SummaryDisclosureRow<Content: View>: View {
    let title: String
    var subtitle: String?
    let done: Int
    let total: Int
    var unit: String
    var anchor: String?
    @ViewBuilder let content: Content
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: String, subtitle: String? = nil, done: Int, total: Int, unit: String, anchor: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.done = done
        self.total = total
        self.unit = unit
        self.anchor = anchor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(DS.Motion.respecting(reduceMotion, DS.Motion.disclose)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 13.5, weight: .semibold))
                        if let subtitle {
                            Text(subtitle).font(SettingsStyle.rowSubtitle).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    ProgressRing(fraction: total > 0 ? Double(done) / Double(total) : 0,
                                 tint: done == total ? DS.Palette.success : .orange)
                    Text("\(done) of \(total) \(unit)")
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(SettingsStyle.rowPadding)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue("\(done) of \(total) \(unit), \(isExpanded ? "expanded" : "collapsed")")
            .accessibilityHint(isExpanded ? "Collapses the list" : "Expands the list")
            if isExpanded {
                SettingsDivider()
                content
                    .transition(DS.Motion.transition(reduceMotion, .opacity.combined(with: .move(edge: .top))))
            }
        }
        .settingsAnchor(anchor)
    }
}

// MARK: - Card buttons

/// A square-ish card with an icon, a bold title and a grey subtitle (About's
/// Changelog / Developer / Introduction). With `help`, an ⓘ sits in its corner.
struct SettingsCardButton: View {
    let icon: String
    let title: String
    let subtitle: String
    var help: String?
    var anchor: String?
    var action: (() -> Void)?
    @State private var isHovered = false

    init(icon: String, title: String, subtitle: String, help: String? = nil, anchor: String? = nil,
         action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.help = help
        self.anchor = anchor
        self.action = action
    }

    var body: some View {
        let card = VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 22)).padding(.bottom, 4).accessibilityHidden(true)
            Text(title).font(.system(size: 13.5, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 116)
        .padding(.horizontal, 8)
        .background((isHovered && action != nil) ? Color.white.opacity(0.09) : SettingsStyle.cardFill,
                    in: RoundedRectangle(cornerRadius: SettingsStyle.cardRadius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if let help { InfoButton(help).padding(10) }
        }
        .contentShape(RoundedRectangle(cornerRadius: SettingsStyle.cardRadius, style: .continuous))
        .onHover { isHovered = $0 }
        .settingsAnchor(anchor)

        if let action {
            Button(action: action) { card }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title), \(subtitle)")
        } else {
            card.accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Tape colour picker

/// A swatch on a `TapeColorPicker`.
struct TapeSwatch: Identifiable, Equatable {
    /// "default", a preset name, or "custom".
    let id: String
    let name: String
    /// nil draws the rainbow "custom" tick.
    let color: Color?
}

/// A tick "tape" to scrub along for a colour: the dot above shows the pick,
/// the triangle under it marks the tick, the label names it. The first tick
/// is Default; the last is a custom colour edited with the system picker.
struct TapeColorPicker: View {
    let title: String
    var help: String?
    var anchor: String?
    let swatches: [TapeSwatch]
    @Binding var selection: String
    @Binding var customHex: String
    @State private var dragStart: Int?

    init(_ title: String, help: String? = nil, anchor: String? = nil, swatches: [TapeSwatch],
         selection: Binding<String>, customHex: Binding<String>) {
        self.title = title
        self.help = help
        self.anchor = anchor
        self.swatches = swatches
        self._selection = selection
        self._customHex = customHex
    }

    private static let tickPitch: CGFloat = 9

    private var index: Int { swatches.firstIndex { $0.id == selection } ?? 0 }
    private var selected: TapeSwatch { swatches[index] }
    private var customColor: Color { Color(hex: customHex) ?? .white }

    private func color(of swatch: TapeSwatch) -> Color { swatch.color ?? customColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                if let help { InfoButton(help) }
                Spacer()
                if selected.id == "custom" {
                    ColorPicker("Custom color", selection: Binding(
                        get: { customColor },
                        set: { customHex = $0.hexString }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }
            }
            GeometryReader { geo in
                let mid = geo.size.width / 2
                // The tape slides so the chosen tick sits under the centre.
                let offset = mid - CGFloat(index) * Self.tickPitch
                ZStack(alignment: .topLeading) {
                    ForEach(swatches.indices, id: \.self) { i in
                        let swatch = swatches[i]
                        let x = offset + CGFloat(i) * Self.tickPitch
                        let distance = abs(CGFloat(i - index))
                        Group {
                            if swatch.color == nil {
                                Capsule().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                                               center: .center))
                            } else {
                                Capsule().fill(color(of: swatch))
                            }
                        }
                        .frame(width: 3, height: 26)
                        .opacity(max(0.25, 1 - Double(distance) * 0.09))
                        .position(x: x, y: 34)
                        if distance <= 4, distance.truncatingRemainder(dividingBy: 4) == 0 {
                            Circle().fill(color(of: swatch))
                                .frame(width: i == index ? 14 : 10, height: i == index ? 14 : 10)
                                .opacity(i == index ? 1 : 0.55)
                                .position(x: x, y: 8)
                        }
                    }
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 8))
                        .position(x: mid, y: 56)
                }
                .frame(width: geo.size.width, height: 62)
                .clipped()
                .contentShape(Rectangle())
                // Scrub: dragging the tape left moves to later swatches. A
                // click jumps to the tick under the pointer.
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let start = dragStart ?? index
                            if dragStart == nil { dragStart = start }
                            guard abs(value.translation.width) > 3 else { return }
                            pick(start - Int((value.translation.width / Self.tickPitch).rounded()))
                        }
                        .onEnded { value in
                            let start = dragStart ?? index
                            dragStart = nil
                            if abs(value.translation.width) <= 3 {
                                pick(start + Int(((value.startLocation.x - mid) / Self.tickPitch).rounded()))
                            }
                        }
                )
            }
            .frame(height: 62)
            // The tape itself is one adjustable element; the header row stays
            // separate so VoiceOver can still reach ⓘ and the custom picker.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(selected.name)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: pick(index + 1)
                case .decrement: pick(index - 1)
                @unknown default: break
                }
            }
            // With keyboard navigation on, Tab reaches the tape (with its
            // focus ring) and ← → step along it, like the drag does.
            .focusable(interactions: .activate)
            .onMoveCommand { direction in
                switch direction {
                case .left: pick(index - 1)
                case .right: pick(index + 1)
                default: break
                }
            }
            Text(selected.id == "custom" ? "Custom \(customHex.isEmpty ? "" : customHex)" : selected.name)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(SettingsStyle.cardFill, in: RoundedRectangle(cornerRadius: SettingsStyle.cardRadius, style: .continuous))
        .settingsAnchor(anchor)
    }

    private func pick(_ i: Int) {
        let clamped = min(max(i, 0), swatches.count - 1)
        guard swatches[clamped].id != selection else { return }
        selection = swatches[clamped].id
        if swatches[clamped].id == "custom", customHex.isEmpty {
            customHex = (swatches[max(clamped - 1, 0)].color ?? .white).hexString
        }
        DroppyAudio.playTick()
    }
}
