import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum CaptureTool: String, CaseIterable, Identifiable {
    case select, crop
    case arrow, curvedArrow, line
    case rectangle, ellipse, square, circle, diamond
    case pen, highlighter, text, magnifier
    case step, pointer, pointerCircle, cursor, cursorCircle
    case pixelate, blur

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: return "Select"
        case .crop: return "Crop"
        case .arrow: return "Arrow"
        case .curvedArrow: return "Curved Arrow"
        case .line: return "Line"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .square: return "Square"
        case .circle: return "Circle"
        case .diamond: return "Diamond"
        case .pen: return "Freehand"
        case .highlighter: return "Highlighter"
        case .text: return "Text"
        case .magnifier: return "Magnifier"
        case .step: return "Number Sticker"
        case .pointer: return "Pointer Sticker"
        case .pointerCircle: return "Pointer Sticker (Circle)"
        case .cursor: return "Cursor Sticker"
        case .cursorCircle: return "Cursor Sticker (Circle)"
        case .pixelate: return "Pixelate"
        case .blur: return "Blur"
        }
    }

    var icon: String {
        switch self {
        case .select: return "cursorarrow"
        case .crop: return "crop"
        case .arrow: return "arrow.up.right"
        case .curvedArrow: return "arrow.turn.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "oval"
        case .square: return "square"
        case .circle: return "circle"
        case .diamond: return "diamond"
        case .pen: return "scribble"
        case .highlighter: return "highlighter"
        case .text: return "textformat"
        case .magnifier: return "plus.magnifyingglass"
        case .step: return "1.circle"
        case .pointer: return "hand.point.up.left.fill"
        case .pointerCircle: return "hand.tap.fill"
        case .cursor: return "cursorarrow.rays"
        case .cursorCircle: return "cursorarrow.click"
        case .pixelate: return "checkerboard.rectangle"
        case .blur: return "drop.halffull"
        }
    }

    /// Single-key shortcut; nil for the variants reached through their group.
    var shortcut: Character? {
        switch self {
        case .select: return "v"
        case .crop: return "c"
        case .arrow: return "a"
        case .curvedArrow: return "k"
        case .line: return "l"
        case .rectangle: return "r"
        case .ellipse: return "o"
        case .diamond: return "d"
        case .pen: return "p"
        case .highlighter: return "h"
        case .text: return "t"
        case .magnifier: return "m"
        case .step: return "n"
        case .pointer: return "i"
        case .cursor: return "u"
        case .pixelate: return "x"
        case .blur: return "b"
        case .square, .circle, .pointerCircle, .cursorCircle: return nil
        }
    }

    var help: String {
        shortcut.map { "\(title) (\(String($0).uppercased()))" } ?? title
    }

    /// Placed with a single click rather than dragged out.
    var isStamp: Bool { stickerKind != nil || self == .step }

    var stickerKind: StickerKind? {
        switch self {
        case .pointer: return .pointer
        case .pointerCircle: return .pointerCircle
        case .cursor: return .cursor
        case .cursorCircle: return .cursorCircle
        default: return nil
        }
    }

    /// The toolbar: one button per group, the variants in its menu.
    static let groups: [[CaptureTool]] = [
        [.select], [.crop],
        [.arrow, .curvedArrow], [.line], [.rectangle, .ellipse, .square, .circle, .diamond],
        [.pen], [.highlighter], [.text], [.magnifier],
        [.step, .pointer, .pointerCircle, .cursor, .cursorCircle],
        [.pixelate], [.blur],
    ]

    /// Groups followed by a divider in the toolbar.
    static let dividerAfter: Set<CaptureTool> = [.crop, .step]
}

/// The editor's keyboard shortcuts, for the cheat sheet in the editor and in Settings.
enum CaptureEditorShortcuts {
    static let general: [(keys: String, action: String)] = [
        ("⌘Z", "Undo"), ("⇧⌘Z", "Redo"), ("⌘C", "Copy image"), ("⌘S", "Save as PNG or JPEG"),
        ("↩", "Done: deliver and close"), ("⎋", "Deselect, leave crop, or close"), ("⌘W", "Close"),
        ("⌫", "Delete the selection"), ("← → ↑ ↓", "Nudge the selection (⇧ for 10 pt)"),
        ("⇧ + drag", "Straight angles, squares and circles"),
        ("⌘+ / ⌘−", "Zoom in / out"), ("⌘0", "Zoom to fit"), ("⌘1", "Actual size"),
        ("Pinch / scroll", "Zoom / pan the canvas"),
    ]

    static var tools: [(keys: String, action: String)] {
        CaptureTool.allCases.compactMap { tool in
            tool.shortcut.map { (String($0).uppercased(), tool.title) }
        }
    }
}

enum StrokeSize: String, CaseIterable, Identifiable {
    case thin, medium, thick

    var id: String { rawValue }
    var title: String { self == .thin ? "S" : self == .medium ? "M" : "L" }
    /// Stroke width in points; multiplied by the capture's pixel density.
    var points: CGFloat { self == .thin ? 2 : self == .medium ? 4 : 8 }
    var textPoints: CGFloat { self == .thin ? 16 : self == .medium ? 24 : 36 }
    /// How much a magnifier enlarges.
    var magnifierZoom: CGFloat { self == .thin ? 1.6 : self == .medium ? 2 : 3 }
}

/// What a fresh capture should do with the result when the user clicks Done.
struct CaptureDelivery {
    var copyToClipboard: Bool
    var addToTray: Bool
    var saveToFolder = false

    var isEmpty: Bool { !copyToClipboard && !addToTray && !saveToFolder }
}

/// State and actions of one editor window. Tools produce `Annotation`s in
/// image pixels; the document keeps them, the canvas only displays them.
@MainActor
final class CaptureEditorModel: ObservableObject {
    @Published private(set) var document: CaptureDocument
    @Published var tool: CaptureTool = .arrow {
        didSet { toolChanged(from: oldValue) }
    }
    @Published var color: RGBAColor = RGBAColor.named(CaptureSettings.shared.annotationColor)
    @Published var strokeSize: StrokeSize = .medium
    @Published var font: CaptureFont = CaptureFont.named(CaptureSettings.shared.editorFont)
    /// Screen points per screenshot point; nil fits the window.
    @Published var zoom: CGFloat?
    @Published var showsShortcuts = false
    @Published var selectedID: UUID?
    /// The annotation being drawn; committed when the gesture ends.
    @Published var draft: Annotation?
    /// Crop rectangle while the crop tool is active.
    @Published var cropDraft: CGRect?
    @Published var textEdit: TextEdit?
    @Published var backdrop: CaptureBackdrop {
        didSet { Self.lastBackdrop = backdrop; scheduleExport() }
    }
    @Published var showsStylePanel = false
    @Published private(set) var redactionPreviews: [RedactionStyle: CGImage] = [:]
    @Published private(set) var isBusy = false

    struct TextEdit: Equatable {
        /// Existing annotation being edited, hidden from the canvas meanwhile.
        var id: UUID?
        var origin: CGPoint
        var string: String
        var fontSize: CGFloat
        var color: RGBAColor
        var font: CaptureFont = .system
    }

    let delivery: CaptureDelivery?
    weak var window: NSWindow?
    var onClose: (() -> Void)?

    private struct ExportKey: Equatable {
        let edits: CaptureEdits
        let backdrop: CaptureBackdrop
    }

    private var cached: (key: ExportKey, image: CGImage)?
    private var cachedFile: (key: ExportKey, url: URL)?
    /// The last result that left the editor (copied, saved, dragged, trayed).
    private var deliveredKey: ExportKey?
    private var exportTask: Task<Void, Never>?
    /// Where the current drag started, for crop moves and new crops.
    private var liveStart: CGPoint?
    private var dragKind: DragKind?
    private let fileStem: String
    private let tempFolder: URL

    private static var lastBackdrop = CaptureBackdrop()
    private static var backdropInitialized = false

    /// Settings › Screenshot Radius changed: new editors start from it.
    static func applyDefaultRadius(_ radius: Double) {
        lastBackdrop.cornerRadius = CGFloat(radius)
        backdropInitialized = true
    }

    private enum DragKind {
        case move(UUID, CGPoint)
        case draw(CGPoint)
        case crop(CropHandle, CGRect)
        /// A curved arrow's bend handle.
        case control(UUID)
        /// A magnifier's edge.
        case loupeEdge(UUID)
    }

    /// What "fit" is right now, reported by the canvas, so zooming in and out
    /// can start from it.
    var fitZoom: CGFloat = 1
    static let zoomSteps: [CGFloat] = [0.1, 0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.5, 2, 3, 4, 6, 8]

    enum CropHandle {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, move, new
    }

    init(document: CaptureDocument, delivery: CaptureDelivery?) {
        self.document = document
        self.delivery = delivery
        if !Self.backdropInitialized {
            Self.backdropInitialized = true
            Self.lastBackdrop.cornerRadius = CGFloat(CaptureSettings.shared.screenshotRadius)
        }
        self.backdrop = Self.lastBackdrop
        if CaptureSettings.shared.editorDefaultZoom == .native { zoom = 1 }
        let stem = document.sourceURL?.deletingPathExtension().lastPathComponent
        if let stem, !stem.isEmpty {
            fileStem = stem.hasSuffix(" edited") ? stem : "\(stem) edited"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            fileStem = "Screenshot \(formatter.string(from: Date()))"
        }
        tempFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TamaCapture", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        prepareRedactionPreviews()
    }

    deinit {
        try? FileManager.default.removeItem(at: tempFolder)
    }

    // MARK: Derived

    var edits: CaptureEdits { document.edits }
    var selected: Annotation? { document.annotation(selectedID) }
    var lineWidth: CGFloat { strokeSize.points * document.pixelScale }
    var hasUndeliveredChanges: Bool {
        document.isEdited && deliveredKey != currentKey
    }

    /// Region of the original the canvas shows: everything while cropping,
    /// otherwise the crop.
    var viewport: CGRect { tool == .crop ? document.imageRect : document.visibleRect }

    /// Backdrop preview is off while cropping, where the whole capture is shown.
    var showsBackdrop: Bool { backdrop.isEnabled && tool != .crop }

    var exportPixelSize: CGSize {
        backdrop.layout(content: document.visibleRect.integral.size, pixelScale: document.pixelScale).canvasSize
    }

    private var currentKey: ExportKey { ExportKey(edits: document.edits, backdrop: backdrop) }

    // MARK: Undo

    func undo() {
        cancelTextEdit()
        document.undo()
        dropStaleSelection()
        syncCropDraft()
        scheduleExport()
    }

    func redo() {
        cancelTextEdit()
        document.redo()
        dropStaleSelection()
        syncCropDraft()
        scheduleExport()
    }

    private func perform(_ change: (inout CaptureEdits) -> Void) {
        document.perform(change)
        scheduleExport()
    }

    private func dropStaleSelection() {
        if document.annotation(selectedID) == nil { selectedID = nil }
    }

    // MARK: Styling the selection

    func setColor(_ newColor: RGBAColor) {
        color = newColor
        DroppyAudio.playTick()
        guard let id = selectedID else { return }
        perform { edits in
            guard let i = edits.annotations.firstIndex(where: { $0.id == id }) else { return }
            edits.annotations[i].color = newColor
        }
    }

    func setStrokeSize(_ size: StrokeSize) {
        strokeSize = size
        DroppyAudio.playTick()
        guard let id = selectedID else { return }
        let width = lineWidth
        let fontSize = size.textPoints * document.pixelScale
        let loupeZoom = size.magnifierZoom
        perform { edits in
            guard let i = edits.annotations.firstIndex(where: { $0.id == id }) else { return }
            edits.annotations[i].lineWidth = width
            if case let .text(s, o, _) = edits.annotations[i].kind {
                edits.annotations[i].kind = .text(s, origin: o, fontSize: fontSize)
            }
            if case let .magnifier(c, r, _) = edits.annotations[i].kind {
                edits.annotations[i].kind = .magnifier(center: c, radius: r, zoom: loupeZoom)
            }
        }
    }

    func setFont(_ newFont: CaptureFont) {
        font = newFont
        DroppyAudio.playTick()
        if textEdit != nil { textEdit?.font = newFont }
        guard let id = selectedID else { return }
        perform { edits in
            guard let i = edits.annotations.firstIndex(where: { $0.id == id }),
                  case .text = edits.annotations[i].kind else { return }
            edits.annotations[i].font = newFont
        }
    }

    // MARK: Zoom

    /// The zoom being shown, whether fitted or chosen.
    var effectiveZoom: CGFloat { zoom ?? fitZoom }

    func zoomIn() {
        let current = effectiveZoom
        zoom = Self.zoomSteps.first { $0 > current + 0.001 } ?? Self.zoomSteps.last
    }

    func zoomOut() {
        let current = effectiveZoom
        zoom = Self.zoomSteps.last { $0 < current - 0.001 } ?? Self.zoomSteps.first
    }

    func zoomToFit() { zoom = nil }
    func zoomToActualSize() { zoom = 1 }

    /// Pinch: continuous, clamped to the step range.
    func setZoom(_ value: CGFloat) {
        zoom = min(max(value, Self.zoomSteps.first ?? 0.1), Self.zoomSteps.last ?? 8)
    }

    var zoomLabel: String {
        zoom == nil ? "Fit" : "\(Int((effectiveZoom * 100).rounded()))%"
    }

    func deleteSelection() {
        guard let id = selectedID else { return }
        perform { $0.annotations.removeAll { $0.id == id } }
        selectedID = nil
        DroppyAudio.playDelete()
    }

    func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        guard let id = selectedID else { return }
        perform { edits in
            guard let i = edits.annotations.firstIndex(where: { $0.id == id }) else { return }
            edits.annotations[i] = edits.annotations[i].translated(by: CGSize(width: dx, height: dy))
        }
    }

    // MARK: Canvas gestures (points are in image pixels)

    func dragBegan(at p: CGPoint, clickCount: Int, handleReach: CGFloat) {
        if textEdit != nil {
            commitTextEdit()
            dragKind = nil
            return
        }
        let tolerance = handleReach
        liveStart = p
        switch tool {
        case .select:
            if let selected, let handle = handleDrag(for: selected, at: p, reach: tolerance) {
                dragKind = handle
                return
            }
            if let hit = topmostAnnotation(at: p, tolerance: tolerance) {
                selectedID = hit.id
                if clickCount >= 2, case let .text(s, o, f) = hit.kind {
                    textEdit = TextEdit(id: hit.id, origin: o, string: s, fontSize: f, color: hit.color, font: hit.font)
                    dragKind = nil
                    return
                }
                dragKind = .move(hit.id, p)
            } else {
                selectedID = nil
                dragKind = nil
            }
        case .crop:
            let rect = cropDraft ?? document.imageRect
            dragKind = .crop(cropHandle(at: p, in: rect, reach: tolerance), rect)
        case .text:
            if let hit = topmostAnnotation(at: p, tolerance: tolerance), case let .text(s, o, f) = hit.kind {
                selectedID = hit.id
                textEdit = TextEdit(id: hit.id, origin: o, string: s, fontSize: f, color: hit.color, font: hit.font)
            } else {
                let fontSize = strokeSize.textPoints * document.pixelScale
                // Put the click on the middle of the first line, where the caret appears.
                let origin = CGPoint(x: p.x, y: p.y - fontSize * 0.6)
                textEdit = TextEdit(id: nil, origin: origin, string: "", fontSize: fontSize, color: color, font: font)
            }
            dragKind = nil
        case .step, .pointer, .pointerCircle, .cursor, .cursorCircle, .magnifier:
            selectedID = nil
            dragKind = .draw(p)
        default:
            selectedID = nil
            dragKind = .draw(p)
            if tool == .pen || tool == .highlighter {
                draft = makeAnnotation(from: p, to: p, points: [p])
            }
        }
    }

    func dragChanged(to p: CGPoint, constrained: Bool) {
        guard let dragKind else { return }
        switch dragKind {
        case let .move(id, start):
            let delta = CGSize(width: p.x - start.x, height: p.y - start.y)
            document.updateLive { edits in
                guard let i = edits.annotations.firstIndex(where: { $0.id == id }) else { return }
                edits.annotations[i] = edits.annotations[i].translated(by: delta)
            }
            self.dragKind = .move(id, p)
        case let .draw(start):
            if tool == .pen || tool == .highlighter {
                switch draft?.kind {
                case let .freehand(pts)?, let .highlighter(pts)?: appendPoint(p, to: pts)
                default: break
                }
            } else if tool == .magnifier {
                draft = magnifier(center: start, radius: start.distance(to: p))
            } else if !tool.isStamp {
                let forced = tool == .square || tool == .circle
                let end = constrained || forced ? constrain(p, from: start) : p
                draft = makeAnnotation(from: start, to: end, points: [])
            }
        case let .control(id):
            document.updateLive { edits in
                guard let i = edits.annotations.firstIndex(where: { $0.id == id }),
                      case let .curvedArrow(a, _, b) = edits.annotations[i].kind else { return }
                edits.annotations[i].kind = .curvedArrow(from: a, control: p, to: b)
            }
        case let .loupeEdge(id):
            let minimum = 12 * document.pixelScale
            document.updateLive { edits in
                guard let i = edits.annotations.firstIndex(where: { $0.id == id }),
                      case let .magnifier(c, _, z) = edits.annotations[i].kind else { return }
                edits.annotations[i].kind = .magnifier(center: c, radius: max(c.distance(to: p), minimum), zoom: z)
            }
        case let .crop(handle, original):
            cropDraft = resizedCrop(original, handle: handle, to: p, constrained: constrained)
        }
    }

    func dragEnded(at p: CGPoint, minimumSize: CGFloat) {
        defer { dragKind = nil }
        guard let dragKind else { return }
        switch dragKind {
        case .move, .control, .loupeEdge:
            document.commitLiveChange()
            scheduleExport()
        case let .draw(start):
            if tool.isStamp {
                let kind: AnnotationKind = tool.stickerKind.map { .sticker($0, tip: p) } ?? .step(edits.nextStepNumber, center: p)
                let annotation = Annotation(kind: kind, color: color, lineWidth: lineWidth)
                perform { $0.annotations.append(annotation) }
                DroppyAudio.playTick()
                draft = nil
                return
            }
            if tool == .magnifier {
                // A click drops a loupe of a default size; a drag sets its radius.
                let dragged = start.distance(to: p)
                let radius = dragged >= minimumSize * 3 ? dragged : 70 * document.pixelScale
                let annotation = magnifier(center: start, radius: radius)
                draft = nil
                perform { $0.annotations.append(annotation) }
                selectedID = annotation.id
                return
            }
            guard let annotation = draft else { return }
            draft = nil
            guard annotation.bounds.width >= minimumSize || annotation.bounds.height >= minimumSize
                    || tool == .pen || tool == .highlighter else { return }
            perform { $0.annotations.append(annotation) }
            selectedID = annotation.id
        case .crop:
            if let rect = cropDraft, rect.width < minimumSize || rect.height < minimumSize {
                cropDraft = edits.crop ?? document.imageRect
            }
        }
    }

    private func appendPoint(_ p: CGPoint, to points: [CGPoint]) {
        // Skip sub-pixel moves: long strokes stay light to redraw every frame.
        if let last = points.last, last.distance(to: p) < max(1, document.pixelScale * 0.75) { return }
        draft = makeAnnotation(from: points.first ?? p, to: p, points: points + [p])
    }

    private func makeAnnotation(from a: CGPoint, to b: CGPoint, points: [CGPoint]) -> Annotation? {
        let kind: AnnotationKind
        switch tool {
        case .arrow: kind = .arrow(from: a, to: b)
        case .line: kind = .line(from: a, to: b)
        case .rectangle: kind = .rectangle(CGRect(corner: a, b))
        case .ellipse: kind = .ellipse(CGRect(corner: a, b))
        case .pen: kind = .freehand(points)
        case .highlighter: kind = .highlighter(points)
        case .pixelate: kind = .redaction(CGRect(corner: a, b).intersection(document.imageRect), .pixelate)
        case .blur: kind = .redaction(CGRect(corner: a, b).intersection(document.imageRect), .blur)
        case .curvedArrow: kind = .curvedArrow(from: a, control: Annotation.defaultControl(a, b), to: b)
        case .square: kind = .rectangle(CGRect(corner: a, b))
        case .circle: kind = .ellipse(CGRect(corner: a, b))
        case .diamond: kind = .diamond(CGRect(corner: a, b))
        case .select, .crop, .text, .step, .magnifier, .pointer, .pointerCircle, .cursor, .cursorCircle: return nil
        }
        return Annotation(kind: kind, color: color, lineWidth: lineWidth)
    }

    private func magnifier(center: CGPoint, radius: CGFloat) -> Annotation {
        let r = max(radius, 12 * document.pixelScale)
        return Annotation(kind: .magnifier(center: center, radius: r, zoom: strokeSize.magnifierZoom),
                          color: color, lineWidth: lineWidth)
    }

    /// A drag that starts on the selection's own handle: a curved arrow's
    /// bend or a magnifier's edge.
    private func handleDrag(for annotation: Annotation, at p: CGPoint, reach: CGFloat) -> DragKind? {
        switch annotation.kind {
        case let .curvedArrow(_, control, _) where p.distance(to: control) <= reach * 1.5:
            return .control(annotation.id)
        case let .magnifier(center, radius, _) where abs(p.distance(to: center) - radius) <= reach * 1.5:
            return .loupeEdge(annotation.id)
        default:
            return nil
        }
    }

    /// Shift: lines snap to 45°, boxes become squares.
    private func constrain(_ p: CGPoint, from start: CGPoint) -> CGPoint {
        let dx = p.x - start.x, dy = p.y - start.y
        switch tool {
        case .arrow, .line, .curvedArrow:
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let length = hypot(dx, dy)
            return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        default:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        }
    }

    private func topmostAnnotation(at p: CGPoint, tolerance: CGFloat) -> Annotation? {
        edits.annotations.last { $0.hitTest(p, tolerance: tolerance) }
    }

    // MARK: Crop

    private func toolChanged(from old: CaptureTool) {
        guard old != tool else { return }
        if old == .crop { applyCrop() }
        if tool == .crop { syncCropDraft() }
        if textEdit != nil { commitTextEdit() }
        draft = nil
        if tool != .select { selectedID = nil }
    }

    private func syncCropDraft() {
        cropDraft = tool == .crop ? (edits.crop ?? document.imageRect) : nil
    }

    func applyCrop() {
        guard let rect = cropDraft?.integral.intersection(document.imageRect), !rect.isEmpty else { return }
        let crop: CGRect? = rect.size == document.imageSize ? nil : rect
        perform { $0.crop = crop }
        cropDraft = nil
    }

    /// Leaves the crop tool without keeping the rectangle being dragged.
    func cancelCrop() {
        cropDraft = edits.crop ?? document.imageRect
        tool = .select
    }

    func resetCrop() {
        cropDraft = document.imageRect
        perform { $0.crop = nil }
        DroppyAudio.playTick()
    }

    private func cropHandle(at p: CGPoint, in r: CGRect, reach: CGFloat) -> CropHandle {
        let nearLeft = abs(p.x - r.minX) <= reach, nearRight = abs(p.x - r.maxX) <= reach
        let nearTop = abs(p.y - r.minY) <= reach, nearBottom = abs(p.y - r.maxY) <= reach
        let withinX = p.x >= r.minX - reach && p.x <= r.maxX + reach
        let withinY = p.y >= r.minY - reach && p.y <= r.maxY + reach
        switch (nearLeft, nearRight, nearTop, nearBottom) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        default: break
        }
        if nearLeft && withinY { return .left }
        if nearRight && withinY { return .right }
        if nearTop && withinX { return .top }
        if nearBottom && withinX { return .bottom }
        return r.contains(p) ? .move : .new
    }

    private func resizedCrop(_ r: CGRect, handle: CropHandle, to p: CGPoint, constrained: Bool) -> CGRect {
        let bounds = document.imageRect
        let q = CGPoint(x: min(max(p.x, 0), bounds.maxX), y: min(max(p.y, 0), bounds.maxY))
        var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
        switch handle {
        case .topLeft: minX = q.x; minY = q.y
        case .top: minY = q.y
        case .topRight: maxX = q.x; minY = q.y
        case .right: maxX = q.x
        case .bottomRight: maxX = q.x; maxY = q.y
        case .bottom: maxY = q.y
        case .bottomLeft: minX = q.x; maxY = q.y
        case .left: minX = q.x
        case .move:
            guard let start = liveStart else { return r }
            var moved = r.offsetBy(dx: p.x - start.x, dy: p.y - start.y)
            moved.origin.x = min(max(moved.minX, 0), bounds.maxX - moved.width)
            moved.origin.y = min(max(moved.minY, 0), bounds.maxY - moved.height)
            return moved
        case .new:
            guard let start = liveStart else { return r }
            var end = q
            if constrained {
                let side = max(abs(q.x - start.x), abs(q.y - start.y))
                end = CGPoint(x: start.x + (q.x < start.x ? -side : side), y: start.y + (q.y < start.y ? -side : side))
            }
            return CGRect(corner: start, end).intersection(bounds)
        }
        return CGRect(corner: CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: maxY))
    }

    // MARK: Text

    func commitTextEdit() {
        guard let edit = textEdit else { return }
        textEdit = nil
        let string = edit.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = edit.id {
            perform { edits in
                if string.isEmpty {
                    edits.annotations.removeAll { $0.id == id }
                } else if let i = edits.annotations.firstIndex(where: { $0.id == id }) {
                    edits.annotations[i].kind = .text(string, origin: edit.origin, fontSize: edit.fontSize)
                    edits.annotations[i].font = edit.font
                }
            }
            if string.isEmpty { selectedID = nil }
        } else if !string.isEmpty {
            let annotation = Annotation(kind: .text(string, origin: edit.origin, fontSize: edit.fontSize),
                                        color: edit.color, lineWidth: lineWidth, font: edit.font)
            perform { $0.annotations.append(annotation) }
            selectedID = annotation.id
        }
    }

    func cancelTextEdit() { textEdit = nil }

    // MARK: Export

    private func prepareRedactionPreviews() {
        let original = document.original
        Task { [weak self] in
            let previews = await Task.detached(priority: .userInitiated) {
                var previews: [RedactionStyle: CGImage] = [:]
                for style in RedactionStyle.allCases {
                    previews[style] = CaptureRenderer.filtered(original, style: style)
                }
                return previews
            }.value
            self?.redactionPreviews = previews
        }
    }

    /// Renders shortly after edits settle, so Copy and drag-out are instant.
    /// The PNG file is written in the same background pass: drag-out needs a
    /// file URL synchronously, and encoding it on main at drag time stalled
    /// the drag for a large capture.
    private func scheduleExport() {
        exportTask?.cancel()
        let key = currentKey
        guard cached?.key != key || cachedFile?.key != key else { return }
        let original = document.original, scale = document.pixelScale
        let fileURL = newExportURL()
        let rendered = cached?.key == key ? cached?.image : nil
        exportTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .utility) { () -> (image: CGImage, written: Bool)? in
                guard let image = rendered ?? CaptureRenderer.render(original: original, edits: key.edits,
                                                                     backdrop: key.backdrop, pixelScale: scale) else { return nil }
                return (image, Self.writePNG(image, to: fileURL) != nil)
            }.value
            guard !Task.isCancelled, let result, let self else { return }
            self.cached = (key, result.image)
            if result.written { self.cachedFile = (key, fileURL) }
        }
    }

    /// A fresh, unique place for an exported PNG inside this editor's folder.
    private func newExportURL() -> URL {
        tempFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("\(fileStem).png")
    }

    /// Encodes and writes the PNG; its bytes, or nil if either step failed.
    private nonisolated static func writePNG(_ image: CGImage, to url: URL) -> Data? {
        guard let data = CaptureRenderer.encode(image, as: .png) else { return nil }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        } catch {
            return nil
        }
        return data
    }

    /// The exported PNG for the current state, file and bytes, with the
    /// encode and the disk work off main. Reuses the file `scheduleExport`
    /// already wrote, so Copy, Add to Tray and Done encode at most once
    /// between them (they used to encode once each, on main).
    private func exportedPNG() async -> (url: URL, data: Data)? {
        let key = currentKey
        if let cachedFile, cachedFile.key == key {
            let url = cachedFile.url
            if let data = await Task.detached(priority: .userInitiated, operation: { try? Data(contentsOf: url) }).value {
                return (url, data)
            }
        }
        guard let image = await flattenedAsync() else { return nil }
        let url = newExportURL()
        guard let data = await Task.detached(priority: .userInitiated, operation: { Self.writePNG(image, to: url) }).value
        else { return nil }
        if currentKey == key { cachedFile = (key, url) }
        return (url, data)
    }

    /// A drag image from the rendered result already in memory, so starting
    /// a drag doesn't decode the PNG it just wrote. Nil when it's stale.
    func dragPreview() -> NSImage? {
        guard let cached, cached.key == currentKey else { return nil }
        return NSImage(cgImage: cached.image, size: NSSize(width: cached.image.width, height: cached.image.height))
    }

    /// The flattened image for the current state; renders synchronously only
    /// when the background render hasn't caught up yet.
    func flattened() -> CGImage? {
        let key = currentKey
        if let cached, cached.key == key { return cached.image }
        guard let image = CaptureRenderer.render(original: document.original, edits: key.edits,
                                                 backdrop: key.backdrop, pixelScale: document.pixelScale) else { return nil }
        cached = (key, image)
        return image
    }

    private func flattenedAsync() async -> CGImage? {
        let key = currentKey
        if let cached, cached.key == key { return cached.image }
        let original = document.original, scale = document.pixelScale
        isBusy = true
        defer { isBusy = false }
        let image = await Task.detached(priority: .userInitiated) {
            CaptureRenderer.render(original: original, edits: key.edits, backdrop: key.backdrop, pixelScale: scale)
        }.value
        if let image { cached = (key, image) }
        return image
    }

    /// A PNG of the current state on disk, for drag-out, which needs the URL
    /// synchronously. Usually already written by `scheduleExport`; only a
    /// drag started within moments of an edit encodes here, on main.
    func exportedFile() -> URL? {
        commitPendingInput()
        let key = currentKey
        if let cachedFile, cachedFile.key == key, FileManager.default.fileExists(atPath: cachedFile.url.path) {
            return cachedFile.url
        }
        let url = newExportURL()
        guard let image = flattened(), Self.writePNG(image, to: url) != nil else { return nil }
        cachedFile = (key, url)
        return url
    }

    func markDragDelivered() { deliveredKey = currentKey }

    private func commitPendingInput() {
        if textEdit != nil { commitTextEdit() }
        if tool == .crop { applyCrop(); cropDraft = edits.crop ?? document.imageRect }
        document.commitLiveChange()
    }

    func copy() {
        commitPendingInput()
        Task {
            guard let image = await flattenedAsync(), let png = await exportedPNG()?.data else {
                reportFailure("Couldn't copy the image")
                return
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(png, forType: .png)
            deliveredKey = currentKey
            DroppyAudio.playCopySuccess()
            AppState.shared.showNotification(appName: "Capture", title: "Copied to Clipboard",
                                             message: "\(image.width) × \(image.height) px")
        }
    }

    func addToTray() {
        commitPendingInput()
        Task {
            guard let file = await exportedPNG()?.url else {
                reportFailure("Couldn't add the image to the Tray")
                return
            }
            // A private copy: the Tray moves temporary files into its own storage.
            let trayCopy = tempFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(file.lastPathComponent)
            do {
                try FileManager.default.createDirectory(at: trayCopy.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: file, to: trayCopy)
            } catch {
                reportFailure("Couldn't add the image to the Tray")
                return
            }
            AppState.shared.addShelfItems([ShelfItem(url: trayCopy)])
            deliveredKey = currentKey
            DroppyAudio.playDropSuccess()
            AppState.shared.showNotification(appName: "Capture", title: "Added to Tray", message: file.lastPathComponent)
        }
    }

    func save() {
        commitPendingInput()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(fileStem).png"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let pictures = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            panel.directoryURL = pictures
        }

        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        picker.addItems(withTitles: ["PNG", "JPEG"])
        let format = FormatSwitcher(panel: panel, stem: fileStem)
        picker.target = format
        picker.action = #selector(FormatSwitcher.changed(_:))
        let label = NSTextField(labelWithString: "Format:")
        let accessory = NSStackView(views: [label, picker])
        accessory.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        panel.accessoryView = accessory

        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            withExtendedLifetime(format) {}
            guard response == .OK, let url = panel.url, let self else { return }
            let chosen: CaptureRenderer.FileFormat = picker.indexOfSelectedItem == 1 ? .jpeg : .png
            Task { await self.write(to: url, format: chosen) }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: handler) } else { handler(panel.runModal()) }
    }

    private func write(to url: URL, format: CaptureRenderer.FileFormat) async {
        guard let image = await flattenedAsync() else { reportFailure("Couldn't render the image"); return }
        let data = await Task.detached(priority: .userInitiated) { () -> Data? in
            let output = format == .jpeg ? CaptureRenderer.flattenOnWhite(image) : image
            return output.flatMap { CaptureRenderer.encode($0, as: format) }
        }.value
        do {
            guard let data else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
            deliveredKey = currentKey
            DroppyAudio.playDropSuccess()
            AppState.shared.showNotification(appName: "Capture", title: "Saved", message: url.lastPathComponent,
                                             actionTitle: "Reveal") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } catch {
            reportFailure("Couldn't save \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Done: hands a fresh capture to where the Snipper was set to send it,
    /// or copies unsaved edits so closing never silently throws work away.
    func finish() {
        commitPendingInput()
        Task {
            if let delivery {
                // One encode, off main, serves the clipboard, the folder and the Tray.
                if !delivery.isEmpty, let export = await exportedPNG() {
                    if delivery.copyToClipboard {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setData(export.data, forType: .png)
                    }
                    var places: [String] = []
                    if delivery.saveToFolder, let saved = ScreenCaptureService.saveToFolder(export.url) {
                        places.append(saved.deletingLastPathComponent().lastPathComponent)
                    }
                    if delivery.addToTray {
                        let file = export.url
                        AppState.shared.addShelfItems([ShelfItem(url: file)])
                        places.append("Tray")
                    }
                    if delivery.copyToClipboard { places.append("Clipboard") }
                    DroppyAudio.playDropSuccess()
                    AppState.shared.showNotification(
                        appName: "Capture",
                        title: "Screenshot Ready",
                        message: places.isEmpty ? "Done" : "Saved to \(places.joined(separator: " & "))"
                    )
                } else if !delivery.isEmpty {
                    // The export failed: say so and keep the editor open, rather
                    // than close as if the screenshot had gone where it was sent.
                    reportFailure("Couldn't export the screenshot")
                    return
                }
            } else if hasUndeliveredChanges, let image = await flattenedAsync(),
                      let png = await exportedPNG()?.data {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setData(png, forType: .png)
                DroppyAudio.playCopySuccess()
                AppState.shared.showNotification(appName: "Capture", title: "Edited screenshot copied",
                                                 message: "\(image.width) × \(image.height) px")
            }
            deliveredKey = currentKey
            onClose?()
        }
    }

    /// Esc / close button: asks first when there are edits nobody has received yet.
    func requestDiscard() {
        commitPendingInput()
        guard hasUndeliveredChanges, let window else { onClose?(); return }
        let alert = NSAlert()
        alert.messageText = "Discard your edits?"
        alert.informativeText = "The annotated screenshot hasn't been copied, saved or added to the Tray."
        alert.addButton(withTitle: "Discard").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.onClose?() }
        }
    }

    private func reportFailure(_ message: String) {
        DroppyAudio.playDelete()
        AppState.shared.showNotification(appName: "Capture", title: "Something went wrong", message: message)
    }
}

/// Keeps the save panel's file extension in step with the format picker.
@MainActor
private final class FormatSwitcher: NSObject {
    weak var panel: NSSavePanel?
    let stem: String

    init(panel: NSSavePanel, stem: String) {
        self.panel = panel
        self.stem = stem
    }

    @objc func changed(_ sender: NSPopUpButton) {
        guard let panel else { return }
        let format: CaptureRenderer.FileFormat = sender.indexOfSelectedItem == 1 ? .jpeg : .png
        panel.allowedContentTypes = [format.utType]
        let current = (panel.nameFieldStringValue as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(current.isEmpty ? stem : current).\(format.fileExtension)"
    }
}
