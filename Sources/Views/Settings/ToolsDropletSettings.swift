import SwiftUI
import AppKit

// Droplet detail options for Element Capture, OCR, Window Snap and
// LiquidMouse (Settings › Droplets › the droplet's page). Anchors are
// "droplet.<id>.<option>", indexed in SettingsSearch.

/// A labelled toggle with an info bubble.
struct InfoToggle: View {
    let title: String
    let info: String
    @Binding var isOn: Bool

    init(_ title: String, info: String, isOn: Binding<Bool>) {
        self.title = title
        self.info = info
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 6) {
                Text(title)
                InfoButton(info)
            }
        }
    }
}

/// A recordable shortcut inside a grouped Form row.
struct FormShortcutRow: View {
    let slot: ShortcutSlot
    var title: String?
    var help: String?
    var anchor: String?

    init(action: ShortcutAction, title: String? = nil, help: String? = nil, anchor: String? = nil) {
        self.init(slot: .action(action), title: title, help: help, anchor: anchor)
    }

    init(slot: ShortcutSlot, title: String? = nil, help: String? = nil, anchor: String? = nil) {
        self.slot = slot
        self.title = title
        self.help = help
        self.anchor = anchor
    }

    var body: some View {
        ShortcutRecorderRow(slot: slot, title: title, help: help, anchor: anchor)
            .padding(.horizontal, -14)
            .padding(.vertical, -8)
    }
}

// MARK: - Element Capture

struct ElementCaptureDropletSettings: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        Section {
            ForEach(CaptureMode.allCases) { mode in
                FormShortcutRow(action: mode.shortcutAction,
                                anchor: mode == .area ? "droplet.snipper.shortcuts" : nil)
            }
            FormShortcutRow(action: .snipToTray, title: "Quick Snip to Tray")
        } header: {
            Text("Keyboard shortcuts")
        } footer: {
            Text("A customizable keyboard shortcut for each capture mode. Element capture highlights the button, list or panel under the pointer; scroll up to widen it to the enclosing element, click to capture. It needs \(PermissionService.accessibilityName) access to see elements, and falls back to whole windows without it.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            ToggleTiles([
                ToggleTile("Clipboard", icon: "doc.on.clipboard", isOn: $state.captureToClipboard),
                ToggleTile("Tray", icon: "tray.and.arrow.down", isOn: $state.captureToTray),
                ToggleTile("Folder", icon: "folder", isOn: $state.captureToFolder),
                ToggleTile("Editor", icon: "pencil.tip.crop.circle", isOn: $state.captureOpensEditor),
            ], anchor: "droplet.snipper.destinations")
            .padding(.horizontal, -14)
            LabeledContent {
                HStack(spacing: 8) {
                    Text(ScreenCaptureService.folderURL.path(percentEncoded: false)
                        .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button("Choose…", action: chooseFolder)
                    if !state.captureFolderPath.isEmpty {
                        Button {
                            state.captureFolderPath = ""
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Back to the Desktop")
                        .accessibilityLabel("Reset screenshot folder")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Screenshot destination")
                    InfoButton("Automatically save screenshots to this folder when Folder is on, and where the preview's Save button puts them.")
                }
            }
            .settingsAnchor("droplet.snipper.folder")
            InfoToggle("Open editor instantly",
                       info: "Every capture opens in the screenshot editor first; Done then sends it to the other destinations.",
                       isOn: $state.captureOpensEditor)
                .settingsAnchor("droplet.snipper.editor")
        } header: {
            Text("Capture destinations")
        } footer: {
            Text("Choose where captures go after taking a screenshot.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            InfoToggle("Screenshot preview",
                       info: "A card in the corner with quick actions — edit, copy, save, read text and pin — for a few seconds after each capture.",
                       isOn: $state.showCapturePreview)
                .settingsAnchor("droplet.snipper.preview")
            InfoToggle("Auto-compress screenshots",
                       info: "Saves Retina captures at point resolution and runs them through Tama's image compressor, keeping the smaller file.",
                       isOn: $state.captureAutoCompress)
                .settingsAnchor("droplet.snipper.compress")
            InfoToggle("Leave Tama out of captures",
                       info: "The island, shelf, preview and other Tama windows don't appear in Tama's own captures. (Accessibility › Hide from screenshots hides them from every app's screenshots and screen sharing.)",
                       isOn: $state.captureExcludesDroppy)
                .settingsAnchor("droplet.snipper.exclude")
        } header: {
            Text("Capture")
        }

        Section {
            Picker(selection: $state.captureEditorDefaultZoom) {
                ForEach(CaptureEditorZoomDefault.allCases) { Text($0.title).tag($0) }
            } label: {
                HStack(spacing: 6) {
                    Text("Default zoom level")
                    InfoButton("Fit shows the whole screenshot; Native size opens it at 100%, one screenshot point per screen point. ⌘+, ⌘− and ⌘0 or a pinch change it in the editor.")
                }
            }
            .settingsAnchor("droplet.snipper.zoom")
            Picker(selection: $state.captureAnnotationColor) {
                ForEach(Array(RGBAColor.swatchNames.enumerated()), id: \.offset) { index, name in
                    Label {
                        Text(name.capitalized)
                    } icon: {
                        Image(systemName: "circle.fill").foregroundStyle(RGBAColor.swatches[index].color)
                    }
                    .tag(name)
                }
            } label: {
                Text("Default annotation color")
            }
            .settingsAnchor("droplet.snipper.color")
            Picker("Text font", selection: $state.captureEditorFont) {
                ForEach(CaptureFont.allCases.filter(\.isInstalled)) { Text($0.title).tag($0.rawValue) }
            }
            .settingsAnchor("droplet.snipper.font")
            LabeledContent {
                HStack {
                    Slider(value: $state.screenshotRadius, in: 0...40, step: 1)
                        .frame(width: 160)
                        .accessibilityLabel("Screenshot radius")
                        .accessibilityValue("\(Int(state.screenshotRadius)) points")
                    Text("\(Int(state.screenshotRadius)) pt")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Screenshot radius")
                    InfoButton("The corner radius the Beautify backdrop starts with in new editor windows.")
                }
            }
            .settingsAnchor("droplet.snipper.radius")
            .onChange(of: state.screenshotRadius) { _, radius in CaptureEditorModel.applyDefaultRadius(radius) }
            DisclosureGroup("Editor shortcuts") {
                EditorShortcutsSheet()
                    .padding(-16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .settingsAnchor("droplet.snipper.editorShortcuts")
        } header: {
            Text("Screenshot editor")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = ScreenCaptureService.folderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.captureFolderPath = url.path(percentEncoded: false)
    }
}

// MARK: - OCR

struct OCRDropletSettings: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        Section {
            InfoToggle("OCR auto-copy",
                       info: "Text read from a capture, the screenshot preview, a Tray file or the OCR droplet goes straight to the clipboard. Off, a banner offers Copy instead.",
                       isOn: $state.autoCopyOCRText)
                .settingsAnchor("droplet.ocr.autoCopy")
        } header: {
            Text("OCR")
        }
    }
}

// MARK: - Window Snap

struct WindowSnapDropletSettings: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        Section {
            InfoToggle("Show snap preview",
                       info: "When a shortcut snaps a window, a translucent blue zone flashes where it lands.",
                       isOn: $state.windowSnapShowPreview)
                .settingsAnchor("droplet.windowSnapper.preview")
        } header: {
            Text("Window Snap")
        } footer: {
            Text("Snaps the focused window of the app you're using, on the display it's on. Bring Window To Front raises the window under the pointer. Needs \(PermissionService.accessibilityName) access.")
                .font(.caption).foregroundStyle(.secondary)
        }
        ForEach(Array(SnapLayout.groups.enumerated()), id: \.offset) { index, group in
            Section {
                ForEach(group.layouts) { layout in
                    FormShortcutRow(action: layout.shortcutAction,
                                    anchor: index == 0 && layout == group.layouts.first ? "droplet.windowSnapper.shortcuts" : nil)
                }
            } header: {
                Text(index == 0 ? "Snap with shortcuts · \(group.title)" : group.title)
            }
        }
    }
}

// MARK: - LiquidMouse

struct LiquidMouseDropletSettings: View {
    @ObservedObject private var liquid = LiquidMouseService.shared
    @ObservedObject private var mice = ExternalMouseMonitor.shared
    @AppStorage(LiquidMouseService.Keys.smooth) private var smooth = false
    @AppStorage(LiquidMouseService.Keys.liquidMode) private var liquidMode = false
    @AppStorage(LiquidMouseService.Keys.glide) private var glide = 0.35
    @AppStorage("liquidMouseSettingsAxis") private var axis: ScrollAxis = .vertical
    private let refresh = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        Section {
            LabeledContent {
                HStack(spacing: 6) {
                    Circle()
                        .fill(mice.hasExternalMouse ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text(mice.hasExternalMouse ? mice.mice.joined(separator: ", ") : "No external mouse")
                        .foregroundStyle(mice.hasExternalMouse ? .primary : .secondary)
                        .lineLimit(1)
                }
            } label: {
                HStack(spacing: 6) {
                    Text("External mouse")
                    InfoButton("Shows whether LiquidMouse currently sees a connected external mouse. Trackpads and Magic Mouse scroll smoothly already and are left alone.")
                }
            }
            .settingsAnchor("droplet.liquidMouse.status")
            InfoToggle("Smooth scrolling",
                       info: "Interpolates non-continuous wheel steps: turns wheel steps into a continuous glide.",
                       isOn: $smooth)
                .settingsAnchor("droplet.liquidMouse.smooth")
            InfoToggle("Liquid Mode",
                       info: "Trackpad-like inertial flow: quick flicks build momentum and coast to a stop. Curves don't apply while it's on.",
                       isOn: $liquidMode)
                .settingsAnchor("droplet.liquidMouse.liquid")
                .disabled(!smooth)
            LabeledContent("Glide") {
                HStack {
                    Slider(value: $glide, in: 0.15...0.8).frame(width: 160)
                        .accessibilityLabel("Glide")
                        .accessibilityValue(glideTitle)
                    Text(glideTitle)
                        .frame(width: 56, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!smooth)
            if !smooth {
                Text("Turn on Smooth scrolling to use Liquid Mode, glide, speed and curves.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if (smooth || reverseBinding(.vertical).wrappedValue || reverseBinding(.horizontal).wrappedValue) && !liquid.hasPermission {
                HStack {
                    Text("Needs \(PermissionService.accessibilityName) to change scroll events.")
                        .font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button("Allow") { liquid.requestPermission() }
                }
            }
        } header: {
            Text("LiquidMouse")
        }

        Section {
            Picker("Axis", selection: $axis) {
                ForEach(ScrollAxis.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .settingsAnchor("droplet.liquidMouse.axis")
            AxisSettings(axis: axis, smooth: smooth, liquidMode: liquidMode)
                .id(axis)
        } header: {
            Text("Direction")
        } footer: {
            Text("Choose which wheel axis to configure. ⇧-scroll counts as horizontal.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            ExternalMouseMonitor.shared.start()
            LiquidMouseService.shared.start()
            liquid.refreshPermission()
        }
        .onReceive(refresh) { _ in ExternalMouseMonitor.shared.refresh() }
    }

    private var glideTitle: String {
        glide < 0.28 ? "Short" : (glide < 0.5 ? "Medium" : "Long")
    }

    private func reverseBinding(_ axis: ScrollAxis) -> Binding<Bool> {
        Binding(get: { UserDefaults.standard.bool(forKey: LiquidMouseService.Keys.reverse(axis)) },
                set: { UserDefaults.standard.set($0, forKey: LiquidMouseService.Keys.reverse(axis)) })
    }
}

/// One axis's settings; re-created per axis so its @AppStorage keys follow.
private struct AxisSettings: View {
    let axis: ScrollAxis
    let smooth: Bool
    let liquidMode: Bool
    @AppStorage private var reverse: Bool
    @AppStorage private var speed: Double
    @AppStorage private var curve: ScrollCurve

    init(axis: ScrollAxis, smooth: Bool, liquidMode: Bool) {
        self.axis = axis
        self.smooth = smooth
        self.liquidMode = liquidMode
        _reverse = AppStorage(wrappedValue: false, LiquidMouseService.Keys.reverse(axis))
        _speed = AppStorage(wrappedValue: 1.0, LiquidMouseService.Keys.speed(axis))
        _curve = AppStorage(wrappedValue: .balanced, LiquidMouseService.Keys.curve(axis))
    }

    var body: some View {
        InfoToggle("Reverse scroll direction",
                   info: "Invert this axis for an external wheel only, so natural scrolling can stay on for the trackpad.",
                   isOn: $reverse)
            .settingsAnchor(axis == .vertical ? "droplet.liquidMouse.reverse" : nil)
        LabeledContent {
            HStack {
                Slider(value: $speed, in: 0.5...3).frame(width: 160)
                    .accessibilityLabel("Speed")
                    .accessibilityValue(String(format: "%.1f times", speed))
                Text(String(format: "%.1f×", speed)).monospacedDigit().frame(width: 44, alignment: .trailing)
            }
        } label: {
            HStack(spacing: 6) {
                Text("Speed")
                InfoButton("Adjust scroll speed from slower to faster.")
            }
        }
        .settingsAnchor(axis == .vertical ? "droplet.liquidMouse.speed" : nil)
        .disabled(!smooth)
        Picker("Curve", selection: $curve) {
            ForEach(ScrollCurve.allCases) { Text($0.title).tag($0) }
        }
        .settingsAnchor(axis == .vertical ? "droplet.liquidMouse.curve" : nil)
        .disabled(!smooth || liquidMode)
        HStack(alignment: .top, spacing: 12) {
            CurvePreview(curve: curve)
                .frame(width: 64, height: 40)
            Text(liquidMode ? "Liquid Mode is on: momentum replaces the curve." : curve.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Restore Balanced") {
                LiquidMouseService.restoreBalanced(axis)
            }
            .disabled(curve == .balanced && abs(speed - 1) < 0.001)
            .help("Restore the balanced curve and normal speed for this direction")
        }
        .settingsAnchor(axis == .vertical ? "droplet.liquidMouse.restore" : nil)
    }
}

/// The curve as a small plot: time across, distance up.
private struct CurvePreview: View {
    let curve: ScrollCurve

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            for i in 0...32 {
                let t = Double(i) / 32
                let point = CGPoint(x: size.width * t, y: size.height * (1 - curve.value(at: t)))
                i == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            ctx.stroke(Path(CGRect(origin: .zero, size: size)), with: .color(.secondary.opacity(0.25)), lineWidth: 1)
            ctx.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}
