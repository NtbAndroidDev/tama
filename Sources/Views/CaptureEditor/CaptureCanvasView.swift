import SwiftUI
import AppKit

/// The editing surface. It fits the window by default and zooms with
/// ⌘+ / ⌘− / ⌘0, pinch or the zoom menu; once larger than the window it pans
/// with the scroll wheel or two fingers. The captured bitmap is drawn once as
/// a plain image; annotations sit on top in `Canvas` layers that paint in
/// image pixels through the same `CaptureRenderer` the export uses. Committed
/// annotations and the stroke in progress are separate layers, so a freehand
/// stroke on a 5K capture only redraws itself each frame.
struct CaptureCanvasView: View {
    @ObservedObject var model: CaptureEditorModel
    @State private var pinchBase: CGFloat?

    private let margin: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let doc = model.document
            let viewport = model.viewport
            let layout = model.showsBackdrop
                ? model.backdrop.layout(content: viewport.size, pixelScale: doc.pixelScale)
                : CaptureBackdrop.Layout(canvasSize: viewport.size, contentRect: CGRect(origin: .zero, size: viewport.size), cornerRadius: 0)
            let fit = fitZoom(layout: layout, in: geo.size, pixelScale: doc.pixelScale)
            // Zoom is in screenshot points; the surface scales image pixels.
            let scale = (model.zoom ?? fit) / doc.pixelScale
            let content = CGSize(width: layout.canvasSize.width * scale, height: layout.canvasSize.height * scale)

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    if model.showsBackdrop {
                        backdropFill
                            .frame(width: content.width, height: content.height)
                    }
                    EditingSurface(model: model, viewport: viewport, scale: scale)
                        .frame(width: viewport.width * scale, height: viewport.height * scale, alignment: .topLeading)
                        .clipShape(RoundedRectangle(cornerRadius: layout.cornerRadius * scale, style: .continuous))
                        .shadow(color: .black.opacity(model.showsBackdrop && model.backdrop.shadow ? 0.45 : 0.3),
                                radius: model.showsBackdrop && model.backdrop.shadow ? 18 * doc.pixelScale * scale : 10,
                                y: model.showsBackdrop && model.backdrop.shadow ? 10 * doc.pixelScale * scale : 3)
                        .offset(x: layout.contentRect.minX * scale, y: layout.contentRect.minY * scale)
                }
                .frame(width: content.width, height: content.height, alignment: .topLeading)
                .padding(margin)
                .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
            .scrollIndicators(model.zoom == nil ? .hidden : .automatic)
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let base = pinchBase ?? model.effectiveZoom
                        if pinchBase == nil { pinchBase = base }
                        model.setZoom(base * value.magnification)
                    }
                    .onEnded { _ in pinchBase = nil }
            )
            .onAppear { model.fitZoom = fit }
            .onChange(of: fit) { _, newFit in model.fitZoom = newFit }
        }
        .background(DS.Palette.ink)
    }

    /// Fit, but never blow a small snip up past twice its on-screen size.
    private func fitZoom(layout: CaptureBackdrop.Layout, in size: CGSize, pixelScale: CGFloat) -> CGFloat {
        let available = CGSize(width: max(size.width - margin * 2, 40), height: max(size.height - margin * 2, 40))
        let scale = min(available.width / max(layout.canvasSize.width, 1),
                        available.height / max(layout.canvasSize.height, 1),
                        2 / pixelScale)
        return scale * pixelScale
    }

    @ViewBuilder
    private var backdropFill: some View {
        let colors = model.backdrop.preset.colors
        if colors.count > 1 {
            LinearGradient(colors: colors.map(\.color), startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if let solid = colors.first {
            solid.color
        } else {
            CheckerboardView()
        }
    }
}

/// Transparent backdrops show as a checkerboard, as image editors do.
private struct CheckerboardView: View {
    var body: some View {
        Canvas { ctx, size in
            let tile: CGFloat = 8
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.22)))
            var path = Path()
            for row in 0..<Int(ceil(size.height / tile)) {
                for col in 0..<Int(ceil(size.width / tile)) where (row + col).isMultiple(of: 2) {
                    path.addRect(CGRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile, width: tile, height: tile))
                }
            }
            ctx.fill(path, with: .color(Color(white: 0.3)))
        }
    }
}

// MARK: - Editing surface

private struct EditingSurface: View {
    @ObservedObject var model: CaptureEditorModel
    let viewport: CGRect
    let scale: CGFloat

    @State private var dragging = false

    var body: some View {
        let doc = model.document
        let editingID = model.textEdit?.id
        let visible = editingID == nil ? doc.edits.annotations : doc.edits.annotations.filter { $0.id != editingID }

        ZStack(alignment: .topLeading) {
            Image(decorative: doc.original, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: doc.imageSize.width * scale, height: doc.imageSize.height * scale)
                .offset(x: -viewport.minX * scale, y: -viewport.minY * scale)

            AnnotationLayer(annotations: visible, previews: model.redactionPreviews, original: doc.original,
                            viewport: viewport, scale: scale)
                .equatable()

            if let draft = model.draft {
                AnnotationLayer(annotations: [draft], previews: model.redactionPreviews, original: doc.original,
                                viewport: viewport, scale: scale)
                    .equatable()
            }

            if let selected = model.selected, model.tool != .crop, editingID == nil {
                selectionOutline(selected.bounds)
                handles(for: selected)
            }

            if model.tool == .crop, let crop = model.cropDraft {
                CropOverlay(rect: toView(crop), bounds: CGSize(width: viewport.width * scale, height: viewport.height * scale))
            }

            if model.textEdit != nil {
                TextEntryField(model: model, viewport: viewport, scale: scale)
            }
        }
        .frame(width: viewport.width * scale, height: viewport.height * scale, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onContinuousHover { phase in
            switch phase {
            case .active: cursor.set()
            case .ended: NSCursor.arrow.set()
            }
        }
    }

    private var cursor: NSCursor {
        switch model.tool {
        case .select: return .arrow
        case .text: return .iBeam
        case .crop: return .crosshair
        case .pointer, .pointerCircle, .cursor, .cursorCircle, .step: return .pointingHand
        default: return .crosshair
        }
    }

    private func toImage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: viewport.minX + p.x / scale, y: viewport.minY + p.y / scale)
    }

    private func toView(_ r: CGRect) -> CGRect {
        CGRect(x: (r.minX - viewport.minX) * scale, y: (r.minY - viewport.minY) * scale,
               width: r.width * scale, height: r.height * scale)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                // Hit targets and "too small" thresholds are in screen points, not pixels.
                if !dragging {
                    dragging = true
                    model.dragBegan(at: toImage(value.startLocation),
                                    clickCount: NSApp.currentEvent?.clickCount ?? 1,
                                    handleReach: 8 / scale)
                }
                model.dragChanged(to: toImage(value.location), constrained: NSEvent.modifierFlags.contains(.shift))
            }
            .onEnded { value in
                dragging = false
                model.dragEnded(at: toImage(value.location), minimumSize: 4 / scale)
            }
    }

    /// A curved arrow's bend handle and a magnifier's edge handle.
    @ViewBuilder
    private func handles(for annotation: Annotation) -> some View {
        switch annotation.kind {
        case let .curvedArrow(a, c, b):
            Path { p in
                p.move(to: toView(a)); p.addLine(to: toView(c)); p.addLine(to: toView(b))
            }
            .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .allowsHitTesting(false)
            handleDot(at: toView(c))
        case let .magnifier(center, radius, _):
            handleDot(at: toView(CGPoint(x: center.x + radius, y: center.y)))
        default:
            EmptyView()
        }
    }

    private func handleDot(at point: CGPoint) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(DS.accent, lineWidth: 2))
            .shadow(color: .black.opacity(0.5), radius: 1.5)
            .position(point)
            .allowsHitTesting(false)
    }

    private func toView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - viewport.minX) * scale, y: (p.y - viewport.minY) * scale)
    }

    private func selectionOutline(_ bounds: CGRect) -> some View {
        let r = toView(bounds).insetBy(dx: -4, dy: -4)
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.black.opacity(0.5), lineWidth: 2)
            )
            .frame(width: r.width, height: r.height)
            .offset(x: r.minX, y: r.minY)
            .allowsHitTesting(false)
    }
}

/// One Canvas of annotations, skipped by SwiftUI when its inputs haven't changed.
private struct AnnotationLayer: View, Equatable {
    let annotations: [Annotation]
    let previews: [RedactionStyle: CGImage]
    /// What a magnifier enlarges on screen (the export enlarges the canvas as drawn).
    let original: CGImage
    let viewport: CGRect
    let scale: CGFloat

    nonisolated static func == (a: AnnotationLayer, b: AnnotationLayer) -> Bool {
        a.annotations == b.annotations && a.viewport == b.viewport && a.scale == b.scale
            && a.previews.count == b.previews.count
    }

    var body: some View {
        Canvas { ctx, _ in
            ctx.withCGContext { cg in
                cg.scaleBy(x: scale, y: scale)
                cg.translateBy(x: -viewport.minX, y: -viewport.minY)
                for annotation in annotations {
                    CaptureRenderer.paint(annotation, in: cg, magnifierSource: { original }) { previews[$0] }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Crop overlay

private struct CropOverlay: View {
    let rect: CGRect
    let bounds: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.addRect(CGRect(origin: .zero, size: bounds))
                p.addRect(rect)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))

            // Rule-of-thirds guides help line up the crop.
            Path { p in
                for i in 1...2 {
                    let x = rect.minX + rect.width * CGFloat(i) / 3
                    let y = rect.minY + rect.height * CGFloat(i) / 3
                    p.move(to: CGPoint(x: x, y: rect.minY)); p.addLine(to: CGPoint(x: x, y: rect.maxY))
                    p.move(to: CGPoint(x: rect.minX, y: y)); p.addLine(to: CGPoint(x: rect.maxX, y: y))
                }
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)

            Path { p in p.addRect(rect) }
                .stroke(Color.white, lineWidth: 1.5)

            ForEach(Array(handlePoints.enumerated()), id: \.offset) { _, point in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 9, height: 9)
                    .shadow(color: .black.opacity(0.5), radius: 1.5)
                    .position(point)
            }
        }
        .allowsHitTesting(false)
    }

    private var handlePoints: [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY)
        ]
    }
}

// MARK: - Inline text entry

private struct TextEntryField: View {
    @ObservedObject var model: CaptureEditorModel
    let viewport: CGRect
    let scale: CGFloat

    @FocusState private var focused: Bool

    var body: some View {
        if let edit = model.textEdit {
            let size = edit.fontSize * scale
            TextField("Type…", text: Binding(
                get: { model.textEdit?.string ?? "" },
                set: { model.textEdit?.string = $0 }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .font(Font(CaptureRenderer.font(size: size, font: edit.font)))
            .foregroundStyle(edit.color.color)
            .lineLimit(1...8)
            .fixedSize()
            .frame(minWidth: max(40, size * 2), alignment: .leading)
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            )
            .focused($focused)
            .onSubmit { model.commitTextEdit() }
            .onExitCommand { model.cancelTextEdit() }
            .offset(x: (edit.origin.x - viewport.minX) * scale - 2, y: (edit.origin.y - viewport.minY) * scale)
            .onAppear { focused = true }
        }
    }
}
