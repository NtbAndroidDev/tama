import AppKit
import CoreGraphics
import CoreImage
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// Flattens a `CaptureDocument` into pixels. Pure and thread-safe: the editor
/// calls it off the main thread for exports, and the canvas reuses `paint` to
/// draw live annotations, so what you see is exactly what gets exported.
///
/// Every drawing routine expects a context whose y axis points down (top-left
/// origin), matching the document's coordinates and SwiftUI's `Canvas`.
enum CaptureRenderer {

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    // MARK: Export

    /// The finished image at full pixel resolution: annotations, crop, then backdrop.
    static func render(
        original: CGImage,
        edits: CaptureEdits,
        backdrop: CaptureBackdrop,
        pixelScale: CGFloat,
        opaque: Bool = false
    ) -> CGImage? {
        guard let annotated = renderAnnotated(original: original, edits: edits) else { return nil }
        let framed = backdrop.isEnabled ? applyBackdrop(annotated, backdrop: backdrop, pixelScale: pixelScale) : annotated
        guard let framed else { return nil }
        return opaque ? flattenOnWhite(framed) : framed
    }

    static func renderAnnotated(original: CGImage, edits: CaptureEdits) -> CGImage? {
        let size = CGSize(width: original.width, height: original.height)
        guard let ctx = makeContext(size: size, colorSpace: original.colorSpace) else { return nil }
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        drawImage(original, in: CGRect(origin: .zero, size: size), ctx: ctx)

        for annotation in edits.annotations {
            // A redaction hides, and a magnifier enlarges, whatever is under it
            // at that point in the stack, including earlier annotations, so both
            // work from the canvas as drawn so far.
            paint(annotation, in: ctx, magnifierSource: { ctx.makeImage() }) { style in
                ctx.makeImage().flatMap { filtered($0, style: style) }
            }
        }

        guard let flat = ctx.makeImage() else { return nil }
        guard let crop = edits.crop?.integral.intersection(CGRect(origin: .zero, size: size)),
              !crop.isEmpty, crop.size != size else { return flat }
        return flat.cropping(to: crop)
    }

    static func applyBackdrop(_ image: CGImage, backdrop: CaptureBackdrop, pixelScale: CGFloat) -> CGImage? {
        let content = CGSize(width: image.width, height: image.height)
        let layout = backdrop.layout(content: content, pixelScale: pixelScale)
        let canvas = layout.canvasSize
        guard let ctx = makeContext(size: canvas, colorSpace: image.colorSpace) else { return nil }
        ctx.translateBy(x: 0, y: canvas.height)
        ctx.scaleBy(x: 1, y: -1)

        let colors = backdrop.preset.colors
        if colors.count == 1 {
            ctx.setFillColor(colors[0].cgColor)
            ctx.fill(CGRect(origin: .zero, size: canvas))
        } else if colors.count > 1,
                  let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                            colors: colors.map(\.cgColor) as CFArray, locations: nil) {
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: canvas.width, y: canvas.height), options: [])
        }

        let rect = layout.contentRect
        let path = CGPath(roundedRect: rect, cornerWidth: layout.cornerRadius, cornerHeight: layout.cornerRadius, transform: nil)
        ctx.saveGState()
        if backdrop.shadow {
            // Shadow offsets live in device space (y up), so "down" is negative.
            ctx.setShadow(offset: CGSize(width: 0, height: -10 * pixelScale), blur: 36 * pixelScale,
                          color: CGColor(gray: 0, alpha: 0.45))
        }
        // A transparency layer lets the shadow follow the clipped image, including
        // any transparent window-capture edges, instead of a solid slab.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(path)
        ctx.clip()
        drawImage(image, in: rect, ctx: ctx)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
        return ctx.makeImage()
    }

    static func flattenOnWhite(_ image: CGImage) -> CGImage? {
        let size = CGSize(width: image.width, height: image.height)
        guard let ctx = makeContext(size: size, colorSpace: image.colorSpace) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }

    enum FileFormat: String, CaseIterable, Sendable {
        case png, jpeg

        var utType: UTType { self == .png ? .png : .jpeg }
        var fileExtension: String { self == .png ? "png" : "jpg" }
    }

    static func encode(_ image: CGImage, as format: FileFormat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else { return nil }
        let props: [CFString: Any] = format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.9] : [:]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    // MARK: Redaction

    /// The whole image pixelated or blurred. The canvas previews a redaction by
    /// showing the matching patch of this, and the export uses the same
    /// parameters, so the two agree.
    static func filtered(_ image: CGImage, style: RedactionStyle) -> CGImage? {
        let input = CIImage(cgImage: image)
        let extent = input.extent
        let longest = max(extent.width, extent.height)
        let output: CIImage?
        switch style {
        case .pixelate:
            let filter = CIFilter(name: "CIPixellate")
            filter?.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
            filter?.setValue(max(8, longest / 90), forKey: kCIInputScaleKey)
            filter?.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)
            output = filter?.outputImage
        case .blur:
            let filter = CIFilter(name: "CIGaussianBlur")
            filter?.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
            filter?.setValue(max(10, longest / 110), forKey: kCIInputRadiusKey)
            output = filter?.outputImage
        }
        guard let output else { return nil }
        return ciContext.createCGImage(output.cropped(to: extent), from: extent)
    }

    // MARK: Painting

    static func arrowHeadLength(_ lineWidth: CGFloat) -> CGFloat { max(lineWidth * 4, 14) }

    /// Draws one annotation. `redactionSource` supplies the filtered image a
    /// redaction shows and `magnifierSource` the image a loupe enlarges; both
    /// must be in the same pixel space as the document.
    static func paint(_ a: Annotation, in ctx: CGContext, magnifierSource: () -> CGImage? = { nil },
                      redactionSource: (RedactionStyle) -> CGImage?) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(a.lineWidth)
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setFillColor(a.color.cgColor)

        switch a.kind {
        case let .arrow(from, to):
            drawArrow(from: from, to: to, width: a.lineWidth, in: ctx)
        case let .line(from, to):
            ctx.move(to: from)
            ctx.addLine(to: to)
            ctx.strokePath()
        case let .rectangle(r):
            let radius = min(a.lineWidth * 1.2, min(r.width, r.height) / 2)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.strokePath()
        case let .ellipse(r):
            ctx.strokeEllipse(in: r)
        case let .freehand(points):
            ctx.addPath(smoothPath(points))
            ctx.strokePath()
        case let .highlighter(points):
            ctx.setLineWidth(a.highlighterWidth)
            ctx.setLineCap(.butt)
            ctx.setStrokeColor(a.color.opacity(0.38).cgColor)
            ctx.addPath(smoothPath(points))
            ctx.strokePath()
        case let .text(string, origin, fontSize):
            drawText(string, origin: origin, fontSize: fontSize, font: a.font, color: a.color, in: ctx)
        case let .redaction(rect, style):
            let r = rect.integral
            guard r.width >= 1, r.height >= 1,
                  let source = redactionSource(style),
                  let patch = source.cropping(to: r) else { return }
            // The crop may be clamped at the image edge; draw it where it really came from.
            let clamped = r.intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))
            drawImage(patch, in: clamped, ctx: ctx)
        case let .step(number, center):
            drawStep(number, center: center, radius: a.stepRadius, color: a.color, in: ctx)
        case let .curvedArrow(from, control, to):
            drawCurvedArrow(from: from, control: control, to: to, width: a.lineWidth, in: ctx)
        case let .diamond(r):
            let path = CGMutablePath()
            path.addLines(between: Annotation.diamondPoints(r))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.strokePath()
        case let .magnifier(center, radius, zoom):
            drawMagnifier(center: center, radius: radius, zoom: zoom, source: magnifierSource(),
                          ringWidth: a.lineWidth, color: a.color, in: ctx)
        case let .sticker(kind, tip):
            drawSticker(kind, tip: tip, size: a.stickerSize, circleRadius: a.stickerCircleRadius, color: a.color, in: ctx)
        }
    }

    private static func drawCurvedArrow(from: CGPoint, control: CGPoint, to: CGPoint, width: CGFloat, in ctx: CGContext) {
        // The head points along the curve's end tangent.
        var dx = to.x - control.x, dy = to.y - control.y
        if hypot(dx, dy) < 0.5 { dx = to.x - from.x; dy = to.y - from.y }
        let tangent = hypot(dx, dy)
        guard tangent > 0.5 else { return }
        let ux = dx / tangent, uy = dy / tangent
        let chord = hypot(to.x - from.x, to.y - from.y)
        let head = min(arrowHeadLength(width), max(chord, 1) * 0.9)
        let halfBase = head * 0.55
        let base = CGPoint(x: to.x - ux * head, y: to.y - uy * head)
        let shaftEnd = CGPoint(x: to.x - ux * head * 0.6, y: to.y - uy * head * 0.6)
        ctx.move(to: from)
        ctx.addQuadCurve(to: shaftEnd, control: control)
        ctx.strokePath()

        ctx.move(to: to)
        ctx.addLine(to: CGPoint(x: base.x - uy * halfBase, y: base.y + ux * halfBase))
        ctx.addLine(to: CGPoint(x: base.x + uy * halfBase, y: base.y - ux * halfBase))
        ctx.closePath()
        ctx.setLineWidth(max(1, width * 0.35))
        ctx.drawPath(using: .fillStroke)
    }

    /// A round loupe: the source enlarged about the centre, a coloured ring
    /// and a thin white inner rim so it reads on any background.
    private static func drawMagnifier(center: CGPoint, radius: CGFloat, zoom: CGFloat, source: CGImage?,
                                      ringWidth: CGFloat, color: RGBAColor, in ctx: CGContext) {
        guard radius > 1 else { return }
        let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -radius * 0.04), blur: radius * 0.18,
                      color: CGColor(gray: 0, alpha: 0.45))
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillEllipse(in: circle)
        ctx.restoreGState()
        if let source {
            ctx.saveGState()
            ctx.addEllipse(in: circle)
            ctx.clip()
            let w = CGFloat(source.width) * zoom, h = CGFloat(source.height) * zoom
            drawImage(source, in: CGRect(x: center.x - center.x * zoom, y: center.y - center.y * zoom, width: w, height: h), ctx: ctx)
            ctx.restoreGState()
        }
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        ctx.setLineWidth(max(1, ringWidth * 0.35))
        ctx.strokeEllipse(in: circle.insetBy(dx: ringWidth * 0.6, dy: ringWidth * 0.6))
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(ringWidth)
        ctx.strokeEllipse(in: circle)
    }

    /// Pointer (a pointing hand) and Cursor (the arrow) stickers, drawn as
    /// vector shapes with the tip at `tip`. The circle variants add a click
    /// ring behind the tip.
    private static func drawSticker(_ kind: StickerKind, tip: CGPoint, size: CGFloat, circleRadius: CGFloat,
                                    color: RGBAColor, in ctx: CGContext) {
        if kind.hasCircle {
            let r = circleRadius
            let circle = CGRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2)
            ctx.setFillColor(color.opacity(0.28).cgColor)
            ctx.fillEllipse(in: circle)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(max(1.5, size * 0.045))
            ctx.strokeEllipse(in: circle)
        }
        var transform = CGAffineTransform(translationX: tip.x, y: tip.y).scaledBy(x: size, y: size)
        let shape = kind.isHand ? handPath() : cursorPath()
        guard let path = shape.copy(using: &transform) else { return }
        let fill: CGColor = kind.isHand ? color.cgColor : CGColor(gray: 0.05, alpha: 1)
        let outline: CGColor = kind.isHand && color.luminance > 0.7 ? CGColor(gray: 0.1, alpha: 1) : CGColor(gray: 1, alpha: 1)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.03), blur: size * 0.08, color: CGColor(gray: 0, alpha: 0.4))
        // A wide outline stroke first, then the fill over it: overlapping
        // parts of the shape show no seams.
        ctx.addPath(path)
        ctx.setStrokeColor(outline)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(size * 0.07)
        ctx.strokePath()
        ctx.restoreGState()
        ctx.addPath(path)
        ctx.setFillColor(fill)
        ctx.fillPath()
    }

    /// The arrow cursor, one unit tall, tip at the origin.
    private static func cursorPath() -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [
            CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 0.78), CGPoint(x: 0.19, y: 0.61), CGPoint(x: 0.32, y: 0.92),
            CGPoint(x: 0.45, y: 0.86), CGPoint(x: 0.32, y: 0.56), CGPoint(x: 0.56, y: 0.56),
        ])
        path.closeSubpath()
        return path
    }

    /// A hand pointing up, one unit tall, fingertip at the origin.
    private static func handPath() -> CGPath {
        let path = CGMutablePath()
        func rounded(_ r: CGRect, _ radius: CGFloat) {
            path.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        }
        rounded(CGRect(x: -0.09, y: 0, width: 0.18, height: 0.62), 0.09)       // index finger
        rounded(CGRect(x: 0.07, y: 0.30, width: 0.15, height: 0.30), 0.07)     // folded fingers
        rounded(CGRect(x: 0.19, y: 0.34, width: 0.15, height: 0.28), 0.07)
        rounded(CGRect(x: 0.31, y: 0.39, width: 0.14, height: 0.25), 0.07)
        rounded(CGRect(x: -0.09, y: 0.46, width: 0.54, height: 0.40), 0.14)    // palm
        rounded(CGRect(x: -0.27, y: 0.46, width: 0.24, height: 0.16), 0.08)    // thumb
        rounded(CGRect(x: 0.0, y: 0.80, width: 0.40, height: 0.22), 0.05)      // wrist
        return path
    }

    /// Draws a CGImage upright in a y-down context.
    static func drawImage(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    private static func drawArrow(from: CGPoint, to: CGPoint, width: CGFloat, in ctx: CGContext) {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 0.5 else { return }
        let ux = dx / length, uy = dy / length
        let head = min(arrowHeadLength(width), length * 0.9)
        let halfBase = head * 0.55
        let base = CGPoint(x: to.x - ux * head, y: to.y - uy * head)
        // Stop the shaft inside the head so its round cap doesn't poke past the sides.
        let shaftEnd = CGPoint(x: to.x - ux * head * 0.6, y: to.y - uy * head * 0.6)
        ctx.move(to: from)
        ctx.addLine(to: shaftEnd)
        ctx.strokePath()

        ctx.move(to: to)
        ctx.addLine(to: CGPoint(x: base.x - uy * halfBase, y: base.y + ux * halfBase))
        ctx.addLine(to: CGPoint(x: base.x + uy * halfBase, y: base.y - ux * halfBase))
        ctx.closePath()
        ctx.setLineWidth(max(1, width * 0.35))
        ctx.drawPath(using: .fillStroke)
    }

    /// Quadratic curves through the midpoints: smooths mouse jitter without
    /// drifting away from what was drawn.
    static func smoothPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            path.addLine(to: points.count == 2 ? points[1] : first)
            return path
        }
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    // MARK: Text

    static func font(size: CGFloat, font: CaptureFont = .system) -> CTFont {
        font.font(size: size)
    }

    private static func lines(_ string: String, font: CTFont) -> [CTLine] {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
        ]
        return string.components(separatedBy: "\n").map {
            CTLineCreateWithAttributedString(NSAttributedString(string: $0.isEmpty ? " " : $0, attributes: attributes))
        }
    }

    private static func lineHeight(_ font: CTFont) -> CGFloat {
        (CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)).rounded(.up)
    }

    static func textSize(_ string: String, fontSize: CGFloat, font name: CaptureFont = .system) -> CGSize {
        let f = font(size: fontSize, font: name)
        let all = lines(string, font: f)
        let width = all.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }.max() ?? 0
        return CGSize(width: ceil(width), height: lineHeight(f) * CGFloat(all.count))
    }

    private static func drawText(_ string: String, origin: CGPoint, fontSize: CGFloat, font name: CaptureFont,
                                 color: RGBAColor, in ctx: CGContext) {
        let f = font(size: fontSize, font: name)
        let height = lineHeight(f)
        let ascent = CTFontGetAscent(f)
        // A thin contrasting outline keeps labels legible on busy screenshots.
        let outline = color.luminance > 0.55 ? CGColor(gray: 0, alpha: 0.75) : CGColor(gray: 1, alpha: 0.9)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for (index, line) in lines(string, font: f).enumerated() {
            let baseline = CGPoint(x: origin.x, y: origin.y + CGFloat(index) * height + ascent)
            ctx.setTextDrawingMode(.stroke)
            ctx.setLineWidth(max(1, fontSize * 0.12))
            ctx.setStrokeColor(outline)
            ctx.textPosition = baseline
            CTLineDraw(line, ctx)
            ctx.setTextDrawingMode(.fill)
            ctx.setFillColor(color.cgColor)
            ctx.textPosition = baseline
            CTLineDraw(line, ctx)
        }
    }

    private static func drawStep(_ number: Int, center: CGPoint, radius: CGFloat, color: RGBAColor, in ctx: CGContext) {
        let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: circle)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
        ctx.setLineWidth(max(1, radius * 0.12))
        ctx.strokeEllipse(in: circle.insetBy(dx: radius * 0.06, dy: radius * 0.06))

        let f = NSFont.monospacedDigitSystemFont(ofSize: radius * 1.05, weight: .heavy) as CTFont
        let attributes: [NSAttributedString.Key: Any] = [
            .font: f,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "\(number)", attributes: attributes))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let capHeight = CTFontGetCapHeight(f)
        ctx.setFillColor(color.luminance > 0.7 ? CGColor(gray: 0.1, alpha: 1) : CGColor(gray: 1, alpha: 1))
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: center.x - width / 2, y: center.y + capHeight / 2)
        CTLineDraw(line, ctx)
    }

    // MARK: Context

    private static func makeContext(size: CGSize, colorSpace: CGColorSpace?) -> CGContext? {
        // Keep the capture's own profile (usually Display P3) so colours don't shift on export.
        let space = colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}
