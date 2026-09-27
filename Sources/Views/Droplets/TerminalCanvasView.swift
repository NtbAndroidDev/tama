import AppKit
import SwiftUI

/// The xterm palette TermiNotch draws with, tuned for the black shelf.
enum TerminalPalette {
    private static let ansi: [(Double, Double, Double)] = [
        (0.00, 0.00, 0.00), (0.87, 0.30, 0.30), (0.33, 0.83, 0.47), (0.90, 0.85, 0.35),
        (0.45, 0.67, 0.98), (0.80, 0.45, 0.85), (0.35, 0.78, 0.86), (0.85, 0.85, 0.85),
        (0.45, 0.45, 0.48), (1.00, 0.42, 0.42), (0.45, 0.93, 0.58), (1.00, 0.95, 0.45),
        (0.60, 0.78, 1.00), (0.92, 0.60, 0.95), (0.50, 0.90, 0.97), (1.00, 1.00, 1.00),
    ]

    static let defaultForeground = NSColor(white: 0.93, alpha: 1)

    static func color(_ color: TerminalColor) -> NSColor {
        switch color {
        case let .ansi(index):
            let c = ansi[min(max(index, 0), 15)]
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        case let .palette(index):
            if index < 16 { return self.color(.ansi(index)) }
            if index >= 232 {
                let level = (8 + 10 * Double(index - 232)) / 255
                return NSColor(srgbRed: level, green: level, blue: level, alpha: 1)
            }
            let n = index - 16
            func component(_ v: Int) -> Double { v == 0 ? 0 : (55 + 40 * Double(v)) / 255 }
            return NSColor(srgbRed: component(n / 36), green: component((n / 6) % 6), blue: component(n % 6), alpha: 1)
        case let .rgb(r, g, b):
            return NSColor(srgbRed: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: 1)
        }
    }

    /// Foreground and (optional) background for a cell's style.
    static func colors(for style: TerminalStyle) -> (NSColor, NSColor?) {
        var foreground = style.foreground.map(color) ?? defaultForeground
        var background = style.background.map(color)
        if style.bold, case let .ansi(index)? = style.foreground, index < 8 {
            foreground = color(.ansi(index + 8))
        }
        if style.inverse {
            let swapped = background ?? NSColor.black
            background = foreground
            foreground = swapped
        }
        if style.dim { foreground = foreground.withAlphaComponent(0.6) }
        return (foreground, background)
    }

    /// A row as styled text, for SwiftUI (the quick bar).
    static func attributed(_ row: [TerminalCell], size: CGFloat) -> AttributedString {
        var result = AttributedString()
        var index = 0
        var end = row.count
        while end > 0, row[end - 1].character == " ", row[end - 1].style.background == nil { end -= 1 }
        while index < end {
            let style = row[index].style
            var run = ""
            while index < end, row[index].style == style {
                run.append(row[index].character)
                index += 1
            }
            var piece = AttributedString(run)
            let (foreground, background) = colors(for: style)
            piece.foregroundColor = Color(nsColor: foreground)
            if let background { piece.backgroundColor = Color(nsColor: background) }
            piece.font = .system(size: size, weight: style.bold ? .bold : .regular, design: .monospaced)
            if style.underline { piece.underlineStyle = .single }
            result += piece
        }
        return result
    }
}

/// The terminal itself: draws the session's screen cell by cell and turns
/// key presses into the bytes a terminal sends. Scroll to read back;
/// drag to select, ⌘C copies.
final class TerminalCanvasView: NSView {
    var session: TerminalSession? {
        didSet {
            guard session !== oldValue else { return }
            scrollOffset = 0
            selection = nil
            needsDisplay = true
        }
    }
    var fontSize: CGFloat = 12 { didSet { if fontSize != oldValue { updateMetrics() } } }
    var onResize: ((Int, Int) -> Void)?

    private var font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private var boldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
    private var cellWidth: CGFloat = 7
    private var lineHeight: CGFloat = 15
    private let padding = NSSize(width: 4, height: 2)
    /// Lines scrolled back from the live screen.
    private var scrollOffset = 0
    private var scrollRemainder: CGFloat = 0
    /// Anchor and end of a drag selection, as (line in scrollback+screen, column).
    private var selection: (start: (Int, Int), end: (Int, Int))?

    override init(frame: NSRect) {
        super.init(frame: frame)
        updateMetrics()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Told when the keys arrive here and when they leave, so the shelf can
    /// stay open while a command is being typed into the shell.
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        onFocusChange?(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        onFocusChange?(false)
        return true
    }

    private func updateMetrics() {
        font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        boldFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        cellWidth = ("W" as NSString).size(withAttributes: [.font: font]).width
        lineHeight = ceil(font.ascender - font.descender + font.leading) + 2
        reportSize()
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reportSize()
    }

    private func reportSize() {
        guard bounds.width > 20, bounds.height > 10 else { return }
        let columns = Int((bounds.width - padding.width * 2) / cellWidth)
        let rows = Int((bounds.height - padding.height * 2) / lineHeight)
        onResize?(max(columns, 10), max(rows, 1))
    }

    func focus() {
        window?.makeFirstResponder(self)
    }

    // MARK: Drawing

    private var allLines: [[TerminalCell]] {
        guard let screen = session?.screen else { return [] }
        return screen.scrollback + screen.grid
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let screen = session?.screen else { return }
        let lines = allLines
        let visible = screen.rowCount
        scrollOffset = min(scrollOffset, screen.scrollback.count)
        let first = max(lines.count - visible - scrollOffset, 0)
        let isFocused = window?.firstResponder === self && window?.isKeyWindow == true
        let normalizedSelection = normalized(selection)

        for row in 0..<visible {
            let lineIndex = first + row
            guard lineIndex < lines.count else { break }
            let line = lines[lineIndex]
            let y = padding.height + CGFloat(row) * lineHeight
            // Selection highlight under the text.
            if let (start, end) = normalizedSelection, lineIndex >= start.0, lineIndex <= end.0 {
                let from = lineIndex == start.0 ? start.1 : 0
                let to = lineIndex == end.0 ? end.1 : line.count
                if to > from {
                    NSColor.selectedTextBackgroundColor.withAlphaComponent(0.55).setFill()
                    NSRect(x: padding.width + CGFloat(from) * cellWidth, y: y,
                           width: CGFloat(to - from) * cellWidth, height: lineHeight).fill()
                }
            }
            var column = 0
            while column < line.count {
                let style = line[column].style
                let start = column
                var text = ""
                while column < line.count, line[column].style == style {
                    text.append(line[column].character)
                    column += 1
                }
                let (foreground, background) = TerminalPalette.colors(for: style)
                let x = padding.width + CGFloat(start) * cellWidth
                if let background {
                    background.setFill()
                    NSRect(x: x, y: y, width: CGFloat(column - start) * cellWidth, height: lineHeight).fill()
                }
                if text.contains(where: { $0 != " " }) {
                    var attributes: [NSAttributedString.Key: Any] = [
                        .font: style.bold ? boldFont : font,
                        .foregroundColor: foreground,
                    ]
                    if style.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                    if style.italic { attributes[.obliqueness] = 0.18 }
                    // Characters are placed one by one when a run holds wide
                    // glyphs, so columns still line up.
                    if text.unicodeScalars.allSatisfy({ $0.isASCII }) {
                        (text as NSString).draw(at: NSPoint(x: x, y: y + 1), withAttributes: attributes)
                    } else {
                        for (offset, character) in text.enumerated() where character != " " {
                            (String(character) as NSString).draw(at: NSPoint(x: x + CGFloat(offset) * cellWidth, y: y + 1),
                                                                 withAttributes: attributes)
                        }
                    }
                }
            }
        }

        // The cursor: a block when focused, an outline when not.
        guard scrollOffset == 0, screen.cursorVisible, let session, !session.hasExited else { return }
        let rect = NSRect(x: padding.width + CGFloat(screen.cursorX) * cellWidth,
                          y: padding.height + CGFloat(screen.cursorY) * lineHeight,
                          width: cellWidth, height: lineHeight)
        if isFocused {
            NSColor.white.withAlphaComponent(0.75).setFill()
            rect.fill()
            let cell = screen.grid[screen.cursorY][screen.cursorX]
            if cell.character != " " {
                (String(cell.character) as NSString).draw(at: NSPoint(x: rect.minX, y: rect.minY + 1),
                                                          withAttributes: [.font: font, .foregroundColor: NSColor.black])
            }
        } else {
            NSColor.white.withAlphaComponent(0.5).setStroke()
            let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
        }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        guard let session else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            handleCommand(event, session: session)
            return
        }
        scrollOffset = 0
        selection = nil
        let application = session.screen.applicationCursorKeys
        func arrow(_ letter: String) -> String { (application ? "\u{1b}O" : "\u{1b}[") + letter }
        var bytes: String?
        switch Int(event.keyCode) {
        case 126: bytes = arrow("A")
        case 125: bytes = arrow("B")
        case 124: bytes = flags.contains(.option) ? "\u{1b}f" : arrow("C")
        case 123: bytes = flags.contains(.option) ? "\u{1b}b" : arrow("D")
        case 115: bytes = "\u{1b}[H"
        case 119: bytes = "\u{1b}[F"
        case 116: bytes = "\u{1b}[5~"
        case 121: bytes = "\u{1b}[6~"
        case 117: bytes = "\u{1b}[3~"
        case 36, 76: bytes = "\r"
        case 51: bytes = flags.contains(.option) ? "\u{1b}\u{7f}" : "\u{7f}"
        case 48: bytes = flags.contains(.shift) ? "\u{1b}[Z" : "\t"
        case 53: bytes = "\u{1b}"
        default: break
        }
        if let bytes {
            session.send(bytes)
            return
        }
        if flags.contains(.control), let characters = event.charactersIgnoringModifiers?.lowercased(),
           let scalar = characters.unicodeScalars.first, scalar.isASCII {
            let value = scalar.value
            switch value {
            case 0x61...0x7a: session.send(Data([UInt8(value - 0x60)]))           // ^A … ^Z
            case 0x40, 0x32, 0x20: session.send(Data([0]))                        // ^@ ^2 ^Space
            case 0x5b: session.send(Data([0x1b]))                                  // ^[
            case 0x5c: session.send(Data([0x1c]))                                  // ^\
            case 0x5d: session.send(Data([0x1d]))                                  // ^]
            case 0x2f, 0x2d: session.send(Data([0x1f]))                            // ^/ ^-
            default: break
            }
            return
        }
        if let characters = event.characters, !characters.isEmpty {
            session.send(characters)
        }
    }

    private func handleCommand(_ event: NSEvent, session: TerminalSession) {
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "v": paste()
        case "c": copySelection()
        case "a": selectAll()
        case "k": session.clear()
        case "t": TermiNotchSessions.shared.newTab()
        case "w": TermiNotchSessions.shared.close(session)
        case "=", "+": AppState.shared.termiNotchFontSize = min(AppState.shared.termiNotchFontSize + 1, 18)
        case "-": AppState.shared.termiNotchFontSize = max(AppState.shared.termiNotchFontSize - 1, 9)
        default: super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, let key = event.charactersIgnoringModifiers?.lowercased(),
           ["v", "c", "a", "k", "t", "w", "=", "+", "-"].contains(key) {
            keyDown(with: event)
            return true
        }
        // ^Tab and friends would otherwise be eaten by the panel.
        if flags.contains(.control) {
            keyDown(with: event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc func paste(_ sender: Any? = nil) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        scrollOffset = 0
        session?.paste(text)
    }

    @objc func copySelection(_ sender: Any? = nil) {
        guard let text = selectedText(), !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func copyAll(_ sender: Any? = nil) {
        guard let text = session?.screen.plainText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func selectAll() {
        let lines = allLines
        guard !lines.isEmpty else { return }
        selection = ((0, 0), (lines.count - 1, lines.last?.count ?? 0))
        needsDisplay = true
    }

    // MARK: Mouse

    private func position(for event: NSEvent) -> (Int, Int) {
        let point = convert(event.locationInWindow, from: nil)
        guard let screen = session?.screen else { return (0, 0) }
        let first = max(allLines.count - screen.rowCount - scrollOffset, 0)
        let row = min(max(Int((point.y - padding.height) / lineHeight), 0), screen.rowCount - 1)
        let column = min(max(Int(((point.x - padding.width) / cellWidth).rounded()), 0), screen.columns)
        return (first + row, column)
    }

    override func mouseDown(with event: NSEvent) {
        NotchWindowController.shared.focusPanel()
        focus()
        let spot = position(for: event)
        selection = (spot, spot)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = selection?.start else { return }
        selection = (start, position(for: event))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let selection, selection.start == selection.end { self.selection = nil }
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        guard let screen = session?.screen, !screen.isAlternateScreen else { return super.scrollWheel(with: event) }
        scrollRemainder += event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? lineHeight : 1)
        let lines = Int(scrollRemainder)
        guard lines != 0 else { return }
        scrollRemainder -= CGFloat(lines)
        scrollOffset = min(max(scrollOffset + lines, 0), screen.scrollback.count)
        needsDisplay = true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(copySelection(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Copy All Output", action: #selector(copyAll(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Clear Terminal Output", action: #selector(clearOutput(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Send Ctrl-C", action: #selector(interrupt(_:)), keyEquivalent: "").target = self
        return menu
    }

    @objc private func clearOutput(_ sender: Any?) { session?.clear() }
    @objc private func interrupt(_ sender: Any?) { session?.interrupt() }

    private func normalized(_ selection: (start: (Int, Int), end: (Int, Int))?) -> ((Int, Int), (Int, Int))? {
        guard let selection, selection.start != selection.end else { return nil }
        let a = selection.start, b = selection.end
        return (a.0, a.1) <= (b.0, b.1) ? (a, b) : (b, a)
    }

    private func selectedText() -> String? {
        guard let (start, end) = normalized(selection) else { return nil }
        let lines = allLines
        var out: [String] = []
        for index in start.0...min(end.0, lines.count - 1) {
            let line = lines[index]
            let from = index == start.0 ? min(start.1, line.count) : 0
            let to = index == end.0 ? min(end.1, line.count) : line.count
            var text = to > from ? String(line[from..<to].map(\.character)) : ""
            while text.last == " " { text.removeLast() }
            out.append(text)
        }
        return out.joined(separator: "\n")
    }
}

/// SwiftUI wrapper; redraws when the session's output changes.
struct TerminalCanvas: NSViewRepresentable {
    @ObservedObject var session: TerminalSession
    var fontSize: CGFloat
    var focusOnAppear = true
    /// Set when the terminal is drawn inside the shelf: typing into it then
    /// holds the shelf open, like any other field there.
    var editingOwner: String?

    func makeNSView(context: Context) -> TerminalCanvasView {
        let view = TerminalCanvasView(frame: .zero)
        if let editingOwner {
            view.onFocusChange = { focused in
                MainActor.assumeIsolated { AppState.shared.setEditing(focused, owner: editingOwner) }
            }
        }
        // Resizing publishes; do it after the layout pass that measured it.
        view.onResize = { columns, rows in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { TermiNotchSessions.shared.resizeAll(columns: columns, rows: rows) }
            }
        }
        view.session = session
        view.fontSize = fontSize
        if focusOnAppear {
            DispatchQueue.main.async { view.focus() }
        }
        return view
    }

    func updateNSView(_ view: TerminalCanvasView, context: Context) {
        view.session = session
        view.fontSize = fontSize
        _ = session.revision
        view.needsDisplay = true
    }

    /// A view torn down while it holds the keys never resigns them, so it
    /// lets go here rather than leaving the shelf held open.
    static func dismantleNSView(_ view: TerminalCanvasView, coordinator: ()) {
        view.onFocusChange?(false)
        view.onFocusChange = nil
    }
}
