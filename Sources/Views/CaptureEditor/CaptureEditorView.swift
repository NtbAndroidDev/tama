import SwiftUI
import AppKit

/// The compact dark editor: tools across the top, canvas, then styling and
/// output actions along the bottom.
struct CaptureEditorView: View {
    @ObservedObject var model: CaptureEditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            toolBar
            Rectangle().fill(DS.Palette.hairline).frame(height: 1)
            CaptureCanvasView(model: model)
            if model.showsStylePanel {
                Rectangle().fill(DS.Palette.hairline).frame(height: 1)
                CaptureStylePanel(model: model)
                    .transition(DS.Motion.transition(reduceMotion, .move(edge: .bottom).combined(with: .opacity)))
            }
            Rectangle().fill(DS.Palette.hairline).frame(height: 1)
            bottomBar
        }
        .background(Color(red: 0.07, green: 0.075, blue: 0.09))
        .environment(\.colorScheme, .dark)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.fluid), value: model.showsStylePanel)
    }

    // MARK: Top bar

    private var toolBar: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(Array(CaptureTool.groups.enumerated()), id: \.offset) { _, group in
                ToolGroupButton(model: model, tools: group)
                if let first = group.first, CaptureTool.dividerAfter.contains(first) {
                    divider
                }
            }
            Spacer(minLength: DS.Space.md)
            DroppyIconButton("arrow.uturn.backward", size: 28, help: "Undo (⌘Z)") { model.undo() }
                .disabled(!model.document.canUndo)
            DroppyIconButton("arrow.uturn.forward", size: 28, help: "Redo (⇧⌘Z)") { model.redo() }
                .disabled(!model.document.canRedo)
            if model.selectedID != nil {
                DroppyIconButton("trash", size: 28, tone: .destructive, help: "Delete (⌫)") { model.deleteSelection() }
            }
            DroppyIconButton("keyboard", size: 28, tone: .plain, isActive: model.showsShortcuts, help: "Editor shortcuts (?)") {
                model.showsShortcuts.toggle()
            }
            .popover(isPresented: $model.showsShortcuts, arrowEdge: .bottom) {
                EditorShortcutsSheet()
            }
        }
        // Clear the traffic lights, which sit over this bar.
        .padding(.leading, 78)
        .padding(.trailing, DS.Space.md)
        .frame(height: 46)
        .background(WindowDragArea())
    }

    private var divider: some View {
        Rectangle().fill(DS.Palette.hairlineStrong).frame(width: 1, height: 18).padding(.horizontal, DS.Space.xxs)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: DS.Space.sm) {
            if model.tool == .crop {
                cropControls
            } else {
                styleControls
            }
            Spacer(minLength: DS.Space.sm)
            outputControls
        }
        .padding(.horizontal, DS.Space.md)
        .frame(height: 46)
    }

    private var styleControls: some View {
        HStack(spacing: DS.Space.sm) {
            HStack(spacing: 5) {
                ForEach(RGBAColor.swatches, id: \.self) { swatch in
                    ColorSwatch(color: swatch, isSelected: model.color == swatch) { model.setColor(swatch) }
                }
            }
            divider
            HStack(spacing: 2) {
                ForEach(StrokeSize.allCases) { size in
                    DroppyChip(size.title, isSelected: model.strokeSize == size,
                               help: "\(size.rawValue.capitalized) stroke") { model.setStrokeSize(size) }
                        // The chip only says S, M or L.
                        .accessibilityLabel("\(size.rawValue.capitalized) stroke")
                }
            }
            if model.tool == .text || model.textEdit != nil || isTextSelected {
                divider
                fontMenu
            }
            divider
            zoomControls
            divider
            DroppyIconButton("sparkles.rectangle.stack", size: 28, tone: .plain,
                             isActive: model.showsStylePanel || model.backdrop.isEnabled,
                             help: "Backdrop & styling") {
                model.showsStylePanel.toggle()
                DroppyAudio.playTick()
            }
            if !(model.tool == .text || model.textEdit != nil || isTextSelected) {
                Text(sizeLabel)
                    .font(DS.Typo.mono)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private var isTextSelected: Bool {
        if case .text? = model.selected?.kind { return true }
        return false
    }

    private var fontMenu: some View {
        Menu {
            ForEach(CaptureFont.allCases.filter(\.isInstalled)) { font in
                Button {
                    model.setFont(font)
                } label: {
                    if font == model.font { Label(font.title, systemImage: "checkmark") } else { Text(font.title) }
                }
            }
        } label: {
            Label(model.font.title, systemImage: "textformat")
                .font(DS.Typo.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Font")
        .accessibilityLabel("Font")
        .accessibilityValue(model.font.title)
    }

    /// One compact menu, so the bottom bar still fits the narrowest window.
    private var zoomControls: some View {
        Menu {
            Button("Zoom In (⌘+)") { model.zoomIn() }
            Button("Zoom Out (⌘−)") { model.zoomOut() }
            Button("Zoom to Fit (⌘0)") { model.zoomToFit() }
            Button("Actual Size (⌘1)") { model.zoomToActualSize() }
            Divider()
            ForEach([0.5, 1, 1.5, 2, 3, 4] as [CGFloat], id: \.self) { step in
                Button("\(Int(step * 100))%") { model.setZoom(step) }
            }
        } label: {
            Label(model.zoomLabel, systemImage: "plus.magnifyingglass")
                .font(DS.Typo.mono)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Zoom · pinch to zoom, scroll to pan")
        .accessibilityLabel("Zoom")
        .accessibilityValue(model.zoomLabel)
    }

    private var cropControls: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "crop").font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.accent)
                .accessibilityHidden(true)
            let crop = model.cropDraft ?? model.document.imageRect
            Text("\(Int(crop.width.rounded())) × \(Int(crop.height.rounded())) px")
                .font(DS.Typo.mono)
                .foregroundStyle(DS.Palette.textSecondary)
            DroppyPillButton("Reset", systemName: "arrow.counterclockwise", tone: .tonal,
                             help: "Back to the whole image") { model.resetCrop() }
            DroppyPillButton("Apply", systemName: "checkmark", tone: .accent, help: "Apply the crop (↩) · Esc cancels") {
                model.tool = .select
                DroppyAudio.playTick()
            }
        }
    }

    private var outputControls: some View {
        HStack(spacing: DS.Space.sm) {
            if model.isBusy {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                    .accessibilityLabel("Working")
            }
            CaptureDragHandle(model: model)
            DroppyPillButton("Copy", systemName: "doc.on.doc", tone: .tonal) { model.copy() }
                .help("Copy image (⌘C)")
            DroppyPillButton("Save…", systemName: "square.and.arrow.down", tone: .tonal) { model.save() }
                .help("Save as PNG or JPEG (⌘S)")
            DroppyPillButton("Tray", systemName: "tray.and.arrow.down", tone: .tonal) { model.addToTray() }
                .help("Add to Tama's Tray")
            DroppyPillButton("Done", systemName: "checkmark", tone: .accent) { model.finish() }
                .help(model.delivery == nil ? "Close and copy unsaved edits (↩)" : "Deliver the screenshot and close (↩)")
        }
    }

    private var sizeLabel: String {
        let size = model.exportPixelSize
        return "\(Int(size.width)) × \(Int(size.height))"
    }
}

// MARK: - Pieces

/// One toolbar slot. A group with variants (arrows, shapes, stickers) shows
/// its current tool; clicking picks it, the chevron menu picks a variant.
private struct ToolGroupButton: View {
    @ObservedObject var model: CaptureEditorModel
    let tools: [CaptureTool]
    @State private var lastUsed: CaptureTool?

    private var current: CaptureTool {
        if tools.contains(model.tool) { return model.tool }
        return lastUsed ?? tools[0]
    }

    var body: some View {
        HStack(spacing: 0) {
            DroppyIconButton(current.icon, size: 28, tone: .plain, isActive: tools.contains(model.tool), help: current.help) {
                select(current)
            }
            if tools.count > 1 {
                Menu {
                    ForEach(tools) { tool in
                        Button {
                            select(tool)
                        } label: {
                            Label(tool.shortcut.map { "\(tool.title)  \(String($0).uppercased())" } ?? tool.title,
                                  systemImage: tool.icon)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: 14, height: 28)
                .help("More \(tools[0].title.lowercased()) tools")
                .accessibilityLabel("More \(tools[0].title.lowercased()) tools")
            }
        }
        .onChange(of: model.tool) { _, tool in
            if tools.contains(tool) { lastUsed = tool }
        }
    }

    private func select(_ tool: CaptureTool) {
        model.tool = tool
        lastUsed = tool
        DroppyAudio.playTick()
    }
}

/// The editor's keyboard shortcuts.
struct EditorShortcutsSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Editor shortcuts").font(DS.Typo.title)
            HStack(alignment: .top, spacing: DS.Space.xl) {
                list("Tools", CaptureEditorShortcuts.tools)
                list("Editing", CaptureEditorShortcuts.general)
            }
        }
        .padding(DS.Space.lg)
        .frame(width: 520)
    }

    private func list(_ title: String, _ rows: [(keys: String, action: String)]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(DS.Typo.micro).tracking(1)
                .foregroundStyle(.secondary)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: DS.Space.sm) {
                    Text(row.keys)
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .padding(.horizontal, 6)
                        .frame(minWidth: 30, minHeight: 18)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1)))
                    Text(row.action).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ColorSwatch: View {
    let color: RGBAColor
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.color)
                .frame(width: 15, height: 15)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                .padding(2.5)
                .overlay(Circle().strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 1.5))
                .scaleEffect(isHovered && !reduceMotion ? 1.1 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(DS.Motion.respecting(reduceMotion, DS.Motion.hover), value: isHovered)
        .onHover { isHovered = $0 }
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var name: String {
        switch color {
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .purple: "Purple"
        case .white: "White"
        case .black: "Black"
        default: "Color"
        }
    }
}

/// Drag the flattened result anywhere a file can go: Finder, Mail, Slack…
private struct CaptureDragHandle: View {
    @ObservedObject var model: CaptureEditorModel
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: "hand.draw").font(.system(size: 10, weight: .semibold))
            Text("Drag").font(DS.Typo.caption)
        }
        .foregroundStyle(isHovered ? DS.Palette.textPrimary : DS.Palette.textSecondary)
        .padding(.horizontal, DS.Space.md)
        .frame(height: 24)
        .background(Capsule().strokeBorder(DS.Palette.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        .overlay(ImageFileDragSource(model: model))
        .onHover { isHovered = $0 }
        .help("Drag the edited image out")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drag the edited image out")
    }
}

private struct ImageFileDragSource: NSViewRepresentable {
    let model: CaptureEditorModel

    func makeNSView(context: Context) -> SourceView {
        let view = SourceView()
        view.model = model
        // SwiftUI's `.help` on the handle can't reach through this view.
        view.toolTip = "Drag the edited image out"
        return view
    }

    func updateNSView(_ view: SourceView, context: Context) {
        view.model = model
    }

    final class SourceView: NSView, NSDraggingSource {
        weak var model: CaptureEditorModel?

        override func mouseDown(with event: NSEvent) {}

        override func mouseDragged(with event: NSEvent) {
            guard let model, let url = model.exportedFile() else { return }
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let origin = convert(event.locationInWindow, from: nil)
            // The render in memory, not a decode of the PNG just written.
            let preview = model.dragPreview() ?? NSImage(contentsOf: url) ?? FileIcon.image(for: url)
            let longest = max(preview.size.width, preview.size.height, 1)
            let size = NSSize(width: preview.size.width / longest * 120, height: preview.size.height / longest * 120)
            item.setDraggingFrame(NSRect(x: origin.x - size.width / 2, y: origin.y - size.height / 2,
                                         width: size.width, height: size.height), contents: preview)
            DroppyAudio.playTick()
            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .copy
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            if operation != [] { model?.markDragDelivered() }
        }
    }
}

/// Lets the bar double as the window's title bar.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
