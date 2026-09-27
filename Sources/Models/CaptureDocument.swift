import SwiftUI
import AppKit
import CoreGraphics

// MARK: - Capture document
// A screenshot being edited: the captured bitmap never changes; every edit is a
// value in an ordered list of operations, and pixels are only produced when
// `CaptureRenderer` flattens the two. All geometry is in image pixels with a
// top-left origin, the same orientation SwiftUI uses, so the canvas only has
// to scale.

/// Colour as plain sRGB components so operations stay value types and can
/// cross into the background renderer.
struct RGBAColor: Hashable, Sendable {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat
    var a: CGFloat = 1

    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var luminance: CGFloat { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    func opacity(_ alpha: CGFloat) -> RGBAColor { RGBAColor(r: r, g: g, b: b, a: alpha) }

    static let red = RGBAColor(r: 1.0, g: 0.23, b: 0.27)
    static let orange = RGBAColor(r: 1.0, g: 0.58, b: 0.0)
    static let yellow = RGBAColor(r: 1.0, g: 0.84, b: 0.04)
    static let green = RGBAColor(r: 0.2, g: 0.82, b: 0.4)
    static let blue = RGBAColor(r: 0.04, g: 0.52, b: 1.0)
    static let purple = RGBAColor(r: 0.69, g: 0.32, b: 0.87)
    static let white = RGBAColor(r: 1, g: 1, b: 1)
    static let black = RGBAColor(r: 0.08, g: 0.08, b: 0.09)

    static let swatches: [RGBAColor] = [.red, .orange, .yellow, .green, .blue, .purple, .white, .black]

    static let swatchNames = ["red", "orange", "yellow", "green", "blue", "purple", "white", "black"]

    /// "red" … "black"; anything else is red.
    static func named(_ name: String) -> RGBAColor {
        swatchNames.firstIndex(of: name).map { swatches[$0] } ?? .red
    }

    var swatchName: String? { Self.swatches.firstIndex(of: self).map { Self.swatchNames[$0] } }
}

enum RedactionStyle: String, Hashable, Sendable, CaseIterable {
    case pixelate
    case blur
}

/// Stamps placed with one click, tip at the click.
enum StickerKind: String, Hashable, Sendable, CaseIterable {
    /// A pointing hand.
    case pointer, pointerCircle
    /// The classic arrow cursor.
    case cursor, cursorCircle

    var hasCircle: Bool { self == .pointerCircle || self == .cursorCircle }
    var isHand: Bool { self == .pointer || self == .pointerCircle }
}

enum AnnotationKind: Hashable, Sendable {
    case arrow(from: CGPoint, to: CGPoint)
    /// A quadratic arrow bent through `control`, which has its own handle.
    case curvedArrow(from: CGPoint, control: CGPoint, to: CGPoint)
    case diamond(CGRect)
    /// A loupe showing what's under it `zoom` times larger.
    case magnifier(center: CGPoint, radius: CGFloat, zoom: CGFloat)
    case sticker(StickerKind, tip: CGPoint)
    case line(from: CGPoint, to: CGPoint)
    case rectangle(CGRect)
    case ellipse(CGRect)
    case freehand([CGPoint])
    case highlighter([CGPoint])
    /// `origin` is the top-left of the first line.
    case text(String, origin: CGPoint, fontSize: CGFloat)
    case redaction(CGRect, RedactionStyle)
    case step(Int, center: CGPoint)
}

struct Annotation: Identifiable, Hashable, Sendable {
    var id = UUID()
    var kind: AnnotationKind
    var color: RGBAColor
    /// Stroke width in image pixels; steps and text derive their size from it.
    var lineWidth: CGFloat
    /// Text annotations only.
    var font: CaptureFont = .system

    /// Highlighter strokes are a broad marker, not a pen line.
    var highlighterWidth: CGFloat { lineWidth * 4.5 }
    var stepRadius: CGFloat { lineWidth * 2.2 + 12 }
    /// A sticker's height; its circle (if any) is centred on the tip.
    var stickerSize: CGFloat { lineWidth * 5 + 34 }
    var stickerCircleRadius: CGFloat { stickerSize * 0.42 }

    /// Points along a curved arrow, for hit testing and bounds.
    static func curvePoints(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, count: Int = 24) -> [CGPoint] {
        (0...count).map { i -> CGPoint in
            let t = CGFloat(i) / CGFloat(count)
            let u: CGFloat = 1 - t
            let wa: CGFloat = u * u, wc: CGFloat = 2 * u * t, wb: CGFloat = t * t
            let x: CGFloat = wa * a.x + wc * c.x + wb * b.x
            let y: CGFloat = wa * a.y + wc * c.y + wb * b.y
            return CGPoint(x: x, y: y)
        }
    }

    /// A gentle bow for a fresh curved arrow: the control point sits off the
    /// middle of the straight line, a quarter of its length to the side.
    static func defaultControl(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let dx = b.x - a.x, dy = b.y - a.y
        return CGPoint(x: mid.x + dy * 0.25, y: mid.y - dx * 0.25)
    }

    static func diamondPoints(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.midY),
         CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.midX, y: r.minY)]
    }

    func translated(by d: CGSize) -> Annotation {
        func move(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + d.width, y: p.y + d.height) }
        var copy = self
        switch kind {
        case let .arrow(a, b): copy.kind = .arrow(from: move(a), to: move(b))
        case let .line(a, b): copy.kind = .line(from: move(a), to: move(b))
        case let .rectangle(r): copy.kind = .rectangle(r.offsetBy(dx: d.width, dy: d.height))
        case let .ellipse(r): copy.kind = .ellipse(r.offsetBy(dx: d.width, dy: d.height))
        case let .freehand(pts): copy.kind = .freehand(pts.map(move))
        case let .highlighter(pts): copy.kind = .highlighter(pts.map(move))
        case let .text(s, o, f): copy.kind = .text(s, origin: move(o), fontSize: f)
        case let .redaction(r, style): copy.kind = .redaction(r.offsetBy(dx: d.width, dy: d.height), style)
        case let .step(n, c): copy.kind = .step(n, center: move(c))
        case let .curvedArrow(a, c, b): copy.kind = .curvedArrow(from: move(a), control: move(c), to: move(b))
        case let .diamond(r): copy.kind = .diamond(r.offsetBy(dx: d.width, dy: d.height))
        case let .magnifier(c, r, z): copy.kind = .magnifier(center: move(c), radius: r, zoom: z)
        case let .sticker(k, tip): copy.kind = .sticker(k, tip: move(tip))
        }
        return copy
    }

    /// Area the annotation covers, used for the selection outline.
    var bounds: CGRect {
        let pad = lineWidth / 2
        switch kind {
        case let .arrow(a, b):
            let head = CaptureRenderer.arrowHeadLength(lineWidth)
            return CGRect(points: [a, b]).insetBy(dx: -head / 2, dy: -head / 2)
        case let .line(a, b):
            return CGRect(points: [a, b]).insetBy(dx: -pad, dy: -pad)
        case let .rectangle(r), let .ellipse(r):
            return r.insetBy(dx: -pad, dy: -pad)
        case let .freehand(pts):
            return CGRect(points: pts).insetBy(dx: -pad, dy: -pad)
        case let .highlighter(pts):
            return CGRect(points: pts).insetBy(dx: -highlighterWidth / 2, dy: -highlighterWidth / 2)
        case let .text(s, o, f):
            return CGRect(origin: o, size: CaptureRenderer.textSize(s, fontSize: f, font: font))
        case let .redaction(r, _):
            return r
        case let .step(_, c):
            let r = stepRadius
            return CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        case let .curvedArrow(a, c, b):
            let head = CaptureRenderer.arrowHeadLength(lineWidth)
            return CGRect(points: Self.curvePoints(a, c, b)).insetBy(dx: -head / 2, dy: -head / 2)
        case let .diamond(r):
            return r.insetBy(dx: -pad, dy: -pad)
        case let .magnifier(c, r, _):
            let outer = r + lineWidth
            return CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2)
        case let .sticker(kind, tip):
            let h = stickerSize
            var box = CGRect(x: tip.x - h * 0.3, y: tip.y - h * 0.06, width: h * 0.85, height: h * 1.1)
            if kind.hasCircle {
                let r = stickerCircleRadius
                box = box.union(CGRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2))
            }
            return box
        }
    }

    /// Whether a click at `p` lands on this annotation. Outlines are hit on
    /// their stroke so a large box doesn't swallow clicks meant for what's inside it.
    func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        let reach = tolerance + lineWidth / 2
        switch kind {
        case let .arrow(a, b), let .line(a, b):
            return p.distance(toSegment: a, b) <= reach
        case let .rectangle(r):
            let outer = r.insetBy(dx: -reach, dy: -reach)
            let inner = r.insetBy(dx: reach, dy: reach)
            return outer.contains(p) && (inner.isNull || inner.isEmpty || !inner.contains(p))
        case let .ellipse(r):
            let rx = max(r.width / 2, 1), ry = max(r.height / 2, 1)
            let dx = (p.x - r.midX) / rx, dy = (p.y - r.midY) / ry
            return abs((dx * dx + dy * dy).squareRoot() - 1) * min(rx, ry) <= reach
        case let .freehand(pts):
            return pts.polylineDistance(to: p) <= reach
        case let .highlighter(pts):
            return pts.polylineDistance(to: p) <= tolerance + highlighterWidth / 2
        case .text, .redaction, .step, .sticker:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        case let .curvedArrow(a, c, b):
            return Self.curvePoints(a, c, b).polylineDistance(to: p) <= reach
        case let .diamond(r):
            return Self.diamondPoints(r).polylineDistance(to: p) <= reach
        case let .magnifier(c, r, _):
            return p.distance(to: c) <= r + reach
        }
    }
}

/// Everything the user changed, as one value: undo/redo keeps snapshots of it.
struct CaptureEdits: Hashable, Sendable {
    var annotations: [Annotation] = []
    /// Region of the original kept on export; nil keeps all of it.
    var crop: CGRect?

    var nextStepNumber: Int {
        let used = annotations.compactMap { a -> Int? in
            if case let .step(n, _) = a.kind { return n }
            return nil
        }
        return (used.max() ?? 0) + 1
    }
}

struct CaptureDocument {
    let original: CGImage
    /// Pixels per point of the captured screen, so stroke presets look the
    /// same on Retina and non-Retina captures.
    let pixelScale: CGFloat
    let sourceURL: URL?

    private(set) var edits = CaptureEdits()
    private var undoStack: [CaptureEdits] = []
    private var redoStack: [CaptureEdits] = []
    private var liveBase: CaptureEdits?

    private static let undoLimit = 200

    init(original: CGImage, pixelScale: CGFloat, sourceURL: URL?) {
        self.original = original
        self.pixelScale = max(pixelScale, 1)
        self.sourceURL = sourceURL
    }

    var imageSize: CGSize { CGSize(width: original.width, height: original.height) }
    var imageRect: CGRect { CGRect(origin: .zero, size: imageSize) }
    /// The part of the original that ends up in the export.
    var visibleRect: CGRect { edits.crop ?? imageRect }
    var canUndo: Bool { !undoStack.isEmpty || liveBase != nil }
    var canRedo: Bool { !redoStack.isEmpty }
    var isEdited: Bool { edits != CaptureEdits() }

    func annotation(_ id: UUID?) -> Annotation? {
        guard let id else { return nil }
        return edits.annotations.first { $0.id == id }
    }

    /// One undoable step.
    mutating func perform(_ change: (inout CaptureEdits) -> Void) {
        commitLiveChange()
        var next = edits
        change(&next)
        guard next != edits else { return }
        pushUndo(edits)
        edits = next
    }

    /// A continuous change such as dragging an annotation: every frame updates
    /// the document, but the whole gesture undoes as one step.
    mutating func updateLive(_ change: (inout CaptureEdits) -> Void) {
        if liveBase == nil { liveBase = edits }
        var next = edits
        change(&next)
        edits = next
    }

    mutating func commitLiveChange() {
        guard let base = liveBase else { return }
        liveBase = nil
        if base != edits { pushUndo(base) }
    }

    mutating func undo() {
        commitLiveChange()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(edits)
        edits = previous
    }

    mutating func redo() {
        commitLiveChange()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(edits)
        edits = next
    }

    private mutating func pushUndo(_ snapshot: CaptureEdits) {
        undoStack.append(snapshot)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst(undoStack.count - Self.undoLimit) }
        redoStack.removeAll()
    }
}

// MARK: - Beautify backdrop

enum BackdropPreset: String, CaseIterable, Identifiable, Sendable {
    case dusk, ocean, sunset, mint, graphite, paper, clear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dusk: return "Dusk"
        case .ocean: return "Ocean"
        case .sunset: return "Sunset"
        case .mint: return "Mint"
        case .graphite: return "Graphite"
        case .paper: return "Paper"
        case .clear: return "None"
        }
    }

    /// Gradient stops from the top-left corner to the bottom-right one; one stop is a solid fill.
    var colors: [RGBAColor] {
        switch self {
        case .dusk: return [RGBAColor(r: 0.98, g: 0.42, b: 0.64), RGBAColor(r: 0.45, g: 0.33, b: 0.93)]
        case .ocean: return [RGBAColor(r: 0.2, g: 0.78, b: 0.96), RGBAColor(r: 0.16, g: 0.33, b: 0.86)]
        case .sunset: return [RGBAColor(r: 1.0, g: 0.78, b: 0.36), RGBAColor(r: 0.96, g: 0.33, b: 0.38)]
        case .mint: return [RGBAColor(r: 0.62, g: 0.95, b: 0.78), RGBAColor(r: 0.18, g: 0.7, b: 0.62)]
        case .graphite: return [RGBAColor(r: 0.27, g: 0.29, b: 0.34), RGBAColor(r: 0.09, g: 0.1, b: 0.12)]
        case .paper: return [RGBAColor(r: 0.95, g: 0.95, b: 0.94)]
        case .clear: return []
        }
    }
}

enum BackdropAspect: String, CaseIterable, Identifiable, Sendable {
    case auto, wide, standard, square

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .wide: return "16:9"
        case .standard: return "4:3"
        case .square: return "1:1"
        }
    }

    var ratio: CGFloat? {
        switch self {
        case .auto: return nil
        case .wide: return 16.0 / 9.0
        case .standard: return 4.0 / 3.0
        case .square: return 1
        }
    }
}

/// Presentation frame around the export. Sizes are in points and scaled by
/// the capture's pixel density, so the same settings look alike on any screen.
struct CaptureBackdrop: Hashable, Sendable {
    var isEnabled = false
    var preset: BackdropPreset = .dusk
    var padding: CGFloat = 48
    var cornerRadius: CGFloat = 12
    var shadow = true
    var aspect: BackdropAspect = .auto

    struct Layout {
        let canvasSize: CGSize
        /// Where the screenshot sits in the canvas, top-left origin.
        let contentRect: CGRect
        let cornerRadius: CGFloat
    }

    func layout(content: CGSize, pixelScale: CGFloat) -> Layout {
        guard isEnabled else {
            return Layout(canvasSize: content, contentRect: CGRect(origin: .zero, size: content), cornerRadius: 0)
        }
        let pad = (padding * pixelScale).rounded()
        var width = content.width + pad * 2
        var height = content.height + pad * 2
        if let ratio = aspect.ratio {
            if width / height < ratio { width = (height * ratio).rounded() } else { height = (width / ratio).rounded() }
        }
        let origin = CGPoint(x: ((width - content.width) / 2).rounded(), y: ((height - content.height) / 2).rounded())
        let radius = min(cornerRadius * pixelScale, min(content.width, content.height) / 2)
        return Layout(canvasSize: CGSize(width: width, height: height),
                      contentRect: CGRect(origin: origin, size: content),
                      cornerRadius: radius)
    }
}

// MARK: - Geometry helpers

extension CGRect {
    init(points: [CGPoint]) {
        guard let first = points.first else { self = .zero; return }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = Swift.min(minX, p.x); maxX = Swift.max(maxX, p.x)
            minY = Swift.min(minY, p.y); maxY = Swift.max(maxY, p.y)
        }
        self.init(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Rectangle spanned by two drag points, in either direction.
    init(corner a: CGPoint, _ b: CGPoint) {
        self.init(x: Swift.min(a.x, b.x), y: Swift.min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

extension CGPoint {
    func distance(to p: CGPoint) -> CGFloat { hypot(x - p.x, y - p.y) }

    func distance(toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(to: a) }
        let t = Swift.max(0, Swift.min(1, ((x - a.x) * dx + (y - a.y) * dy) / lengthSquared))
        return distance(to: CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }
}

extension Array where Element == CGPoint {
    func polylineDistance(to p: CGPoint) -> CGFloat {
        guard count > 1 else { return first.map { p.distance(to: $0) } ?? .infinity }
        var best = CGFloat.infinity
        for i in 1..<count { best = Swift.min(best, p.distance(toSegment: self[i - 1], self[i])) }
        return best
    }
}
