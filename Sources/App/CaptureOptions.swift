import AppKit
import CoreText

// Options for Element Capture and the screenshot editor
// (Settings › Droplets › Element Capture).

/// What a capture grabs. Each has its own recordable shortcut.
public enum CaptureMode: String, CaseIterable, Identifiable, Sendable {
    case area, window, fullscreen, element, ocr

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .area: "Area"
        case .window: "Window"
        case .fullscreen: "Full Screen"
        case .element: "Element"
        case .ocr: "Snip & OCR"
        }
    }

    public var icon: String {
        switch self {
        case .area: "rectangle.dashed"
        case .window: "macwindow"
        case .fullscreen: "display"
        case .element: "viewfinder.rectangular"
        case .ocr: "text.viewfinder"
        }
    }

    public var summary: String {
        switch self {
        case .area: "Drag over any part of the screen."
        case .window: "Click the window to capture."
        case .fullscreen: "The whole display under the pointer."
        case .element: "Capture specific UI elements: hover a button, list or panel and click. Scroll to widen to the enclosing element."
        case .ocr: "Drag over text; it is read on-device."
        }
    }

    public var shortcutAction: ShortcutAction {
        switch self {
        case .area: .captureArea
        case .window: .captureWindow
        case .fullscreen: .captureFullscreen
        case .element: .captureElement
        case .ocr: .captureOCR
        }
    }
}

/// Settings › Element Capture › Default zoom level.
public enum CaptureEditorZoomDefault: String, CaseIterable, Identifiable, Sendable {
    /// The whole screenshot fits the window.
    case fit
    /// 100%: one screenshot point per screen point, panned when larger than the window.
    case native

    public var id: String { rawValue }
    public var title: String { self == .fit ? "Fit to window" : "Native size" }
}

/// Font families offered for text annotations. Resolved with CoreText so the
/// background renderer can use them off the main thread.
public enum CaptureFont: String, CaseIterable, Identifiable, Sendable {
    case system, rounded, serif, mono, avenir, helvetica, georgia, markerFelt, chalkboard

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "System"
        case .rounded: "Rounded"
        case .serif: "New York"
        case .mono: "Monospaced"
        case .avenir: "Avenir Next"
        case .helvetica: "Helvetica Neue"
        case .georgia: "Georgia"
        case .markerFelt: "Marker Felt"
        case .chalkboard: "Chalkboard SE"
        }
    }

    private var familyName: String? {
        switch self {
        case .avenir: "Avenir Next"
        case .helvetica: "Helvetica Neue"
        case .georgia: "Georgia"
        case .markerFelt: "Marker Felt"
        case .chalkboard: "Chalkboard SE"
        case .system, .rounded, .serif, .mono: nil
        }
    }

    /// Bold, as annotation text has always been.
    func font(size: CGFloat) -> CTFont {
        let bold = NSFont.systemFont(ofSize: size, weight: .bold)
        switch self {
        case .system:
            return bold as CTFont
        case .rounded, .serif:
            let design: NSFontDescriptor.SystemDesign = self == .rounded ? .rounded : .serif
            if let descriptor = bold.fontDescriptor.withDesign(design) {
                return CTFontCreateWithFontDescriptor(descriptor as CTFontDescriptor, size, nil)
            }
            return bold as CTFont
        case .mono:
            return NSFont.monospacedSystemFont(ofSize: size, weight: .bold) as CTFont
        default:
            guard let familyName else { return bold as CTFont }
            let base = CTFontCreateWithName(familyName as CFString, size, nil)
            // CoreText falls back to another family when this one is missing.
            guard (CTFontCopyFamilyName(base) as String) == familyName else { return bold as CTFont }
            return CTFontCreateCopyWithSymbolicTraits(base, size, nil, .boldTrait, .boldTrait) ?? base
        }
    }

    var isInstalled: Bool {
        guard let familyName else { return true }
        return (CTFontCopyFamilyName(CTFontCreateWithName(familyName as CFString, 12, nil)) as String) == familyName
    }

    static func named(_ raw: String?) -> CaptureFont { raw.flatMap(CaptureFont.init(rawValue:)) ?? .system }
}
