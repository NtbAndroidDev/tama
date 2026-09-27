import SwiftUI
import AppKit

/// Fonts, RTF and HTML conversion for notes.
enum RichText {
    static let bodySize: CGFloat = 13
    static let headingSizes: [CGFloat] = [22, 18, 15.5]

    static var bodyFont: NSFont { .systemFont(ofSize: bodySize) }

    static var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: NSColor.white]
    }

    static func headingFont(_ level: Int) -> NSFont {
        .systemFont(ofSize: headingSizes[max(0, min(level - 1, 2))], weight: level == 3 ? .semibold : .bold)
    }

    /// 1–3 for a heading-sized font, nil for body text.
    static func headingLevel(of font: NSFont?) -> Int? {
        guard let size = font?.pointSize else { return nil }
        if size >= 20 { return 1 }
        if size >= 16.5 { return 2 }
        if size >= 14.5 { return 3 }
        return nil
    }

    static func rtf(_ attributed: NSAttributedString) -> Data {
        (try? attributed.data(from: NSRange(location: 0, length: attributed.length),
                              documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
    }

    static func attributed(from rtf: Data) -> NSAttributedString {
        guard !rtf.isEmpty,
              let text = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                 documentAttributes: nil) else {
            return NSAttributedString(string: "", attributes: bodyAttributes)
        }
        return normalized(text)
    }

    /// Our look on anything read in: white text, system font keeping bold,
    /// italic and heading sizes, no foreign colours or paragraph styles.
    static func normalized(_ source: NSAttributedString) -> NSAttributedString {
        let text = NSMutableAttributedString(attributedString: source)
        let whole = NSRange(location: 0, length: text.length)
        text.removeAttribute(.backgroundColor, range: whole)
        text.removeAttribute(.paragraphStyle, range: whole)
        text.addAttribute(.foregroundColor, value: NSColor.white, range: whole)
        text.enumerateAttribute(.font, in: whole) { value, range, _ in
            let font = value as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            var result: NSFont
            if let level = headingLevel(of: font) {
                result = headingFont(level)
            } else {
                result = bodyFont
                if traits.contains(.bold) { result = NSFontManager.shared.convert(result, toHaveTrait: .boldFontMask) }
            }
            if traits.contains(.italic) { result = NSFontManager.shared.convert(result, toHaveTrait: .italicFontMask) }
            text.addAttribute(.font, value: result, range: range)
        }
        return text
    }

    // MARK: HTML (Apple Notes)

    /// A plain HTML body Notes renders well: a <div> per line, headings, lists,
    /// and <b>/<i>/<u> runs.
    static func html(from attributed: NSAttributedString) -> String {
        let string = attributed.string as NSString
        var html = ""
        var openList: String?
        var location = 0
        while location <= string.length {
            let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
            var content = lineRange
            // Drop the line break itself.
            while content.length > 0, let scalar = UnicodeScalar(string.character(at: content.location + content.length - 1)),
                  CharacterSet.newlines.contains(scalar) {
                content.length -= 1
            }
            let line = string.substring(with: content)
            var body = content
            var list: String?
            if line.hasPrefix("• ") {
                list = "ul"
                body = NSRange(location: content.location + 2, length: max(content.length - 2, 0))
            } else if let match = line.range(of: #"^\d+\. "#, options: .regularExpression) {
                list = "ol"
                let skip = line.distance(from: line.startIndex, to: match.upperBound)
                body = NSRange(location: content.location + skip, length: max(content.length - skip, 0))
            }
            if openList != list {
                if let openList { html += "</\(openList)>" }
                if let list { html += "<\(list)>" }
                openList = list
            }
            let inner = runs(in: attributed, range: body)
            let level = body.length > 0 ? headingLevel(of: attributed.attribute(.font, at: body.location, effectiveRange: nil) as? NSFont) : nil
            if list != nil {
                html += "<li>\(inner.isEmpty ? "<br>" : inner)</li>"
            } else if let level {
                html += "<div><h\(level)>\(inner)</h\(level)></div>"
            } else {
                html += "<div>\(inner.isEmpty ? "<br>" : inner)</div>"
            }
            let next = NSMaxRange(lineRange)
            if next <= location || next >= string.length { break }
            location = next
        }
        if let openList { html += "</\(openList)>" }
        return html
    }

    private static func runs(in attributed: NSAttributedString, range: NSRange) -> String {
        guard range.length > 0 else { return "" }
        var out = ""
        attributed.enumerateAttributes(in: range) { attributes, runRange, _ in
            var piece = escape((attributed.string as NSString).substring(with: runRange))
            let font = attributes[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            if traits.contains(.bold), headingLevel(of: font) == nil { piece = "<b>\(piece)</b>" }
            if traits.contains(.italic) { piece = "<i>\(piece)</i>" }
            if let underline = attributes[.underlineStyle] as? Int, underline != 0 { piece = "<u>\(piece)</u>" }
            out += piece
        }
        return out
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Notes' body HTML back into our rich text. List items come back as
    /// "• " / "1. " lines so the editor's list commands keep working.
    @MainActor
    static func attributed(fromHTML html: String) -> NSAttributedString {
        var source = html
        // WebKit drops list markers when converting; write them in first.
        source = numberOrderedLists(in: source)
        source = source.replacingOccurrences(of: "<li>", with: "<li>• ", options: .caseInsensitive)
        guard let data = source.data(using: .utf8),
              let parsed = try? NSAttributedString(data: data, options: [
                  .documentType: NSAttributedString.DocumentType.html,
                  .characterEncoding: String.Encoding.utf8.rawValue,
              ], documentAttributes: nil) else {
            return NSAttributedString(string: html, attributes: bodyAttributes)
        }
        let text = NSMutableAttributedString(attributedString: normalized(parsed))
        // HTML conversion leaves a trailing newline and list tabs behind.
        text.mutableString.replaceOccurrences(of: "\t•\t", with: "", options: [], range: NSRange(location: 0, length: text.length))
        text.mutableString.replaceOccurrences(of: "\t", with: "", options: [], range: NSRange(location: 0, length: text.length))
        while text.string.hasSuffix("\n") { text.deleteCharacters(in: NSRange(location: text.length - 1, length: 1)) }
        return text
    }

    /// `<ol><li>a</li><li>b</li></ol>` → numbered "1. a", "2. b".
    private static func numberOrderedLists(in html: String) -> String {
        var result = ""
        var rest = Substring(html)
        while let open = rest.range(of: "<ol>", options: .caseInsensitive) {
            result += rest[..<open.lowerBound]
            guard let close = rest.range(of: "</ol>", options: .caseInsensitive, range: open.upperBound..<rest.endIndex) else {
                rest = rest[open.lowerBound...]
                break
            }
            var list = String(rest[open.upperBound..<close.lowerBound])
            var number = 1
            while let item = list.range(of: "<li>", options: .caseInsensitive) {
                list.replaceSubrange(item, with: "<div>\(number). ")
                number += 1
            }
            list = list.replacingOccurrences(of: "</li>", with: "</div>", options: .caseInsensitive)
            result += list
            rest = rest[close.upperBound...]
        }
        return result + rest
    }
}

// MARK: - Editor

/// Formatting commands the floating toolbar sends to the text view.
@MainActor
final class RichTextController: ObservableObject {
    weak var textView: NSTextView?

    func toggleTrait(_ trait: NSFontTraitMask) {
        guard let textView else { return }
        let range = textView.selectedRange()
        let manager = NSFontManager.shared
        if range.length == 0 {
            let font = (textView.typingAttributes[.font] as? NSFont) ?? RichText.bodyFont
            let has = manager.traits(of: font).contains(trait)
            textView.typingAttributes[.font] = has ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
            return
        }
        guard let storage = textView.textStorage, textView.shouldChangeText(in: range, replacementString: nil) else { return }
        let first = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? RichText.bodyFont
        let adding = !manager.traits(of: first).contains(trait)
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, run, _ in
            let font = value as? NSFont ?? RichText.bodyFont
            storage.addAttribute(.font, value: adding ? manager.convert(font, toHaveTrait: trait)
                                                      : manager.convert(font, toNotHaveTrait: trait), range: run)
        }
        storage.endEditing()
        textView.didChangeText()
    }

    func toggleUnderline() {
        guard let textView else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            let on = (textView.typingAttributes[.underlineStyle] as? Int ?? 0) != 0
            textView.typingAttributes[.underlineStyle] = on ? 0 : NSUnderlineStyle.single.rawValue
            return
        }
        guard let storage = textView.textStorage, textView.shouldChangeText(in: range, replacementString: nil) else { return }
        let on = (storage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int ?? 0) != 0
        storage.addAttribute(.underlineStyle, value: on ? 0 : NSUnderlineStyle.single.rawValue, range: range)
        textView.didChangeText()
    }

    /// H1–H3 on the selected lines; the same level again turns them back to text.
    func heading(_ level: Int) {
        guard let textView, let storage = textView.textStorage else { return }
        let paragraphs = (storage.string as NSString).paragraphRange(for: textView.selectedRange())
        let current = paragraphs.length > 0
            ? RichText.headingLevel(of: storage.attribute(.font, at: paragraphs.location, effectiveRange: nil) as? NSFont)
            : RichText.headingLevel(of: textView.typingAttributes[.font] as? NSFont)
        let font = current == level ? RichText.bodyFont : RichText.headingFont(level)
        if paragraphs.length > 0, textView.shouldChangeText(in: paragraphs, replacementString: nil) {
            storage.addAttribute(.font, value: font, range: paragraphs)
            textView.didChangeText()
        }
        textView.typingAttributes[.font] = font
    }

    /// Bullets ("• ") or numbers ("1. ") on the selected lines, or off again.
    func toggleList(numbered: Bool) {
        guard let textView, let storage = textView.textStorage else { return }
        let string = storage.string as NSString
        let paragraphs = string.paragraphRange(for: textView.selectedRange())
        var lines: [NSRange] = []
        string.enumerateSubstrings(in: paragraphs, options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            lines.append(range)
        }
        if lines.isEmpty { lines = [NSRange(location: paragraphs.location, length: 0)] }
        let first = string.substring(with: lines[0])
        let isOn = numbered ? first.range(of: #"^\d+\. "#, options: .regularExpression) != nil : first.hasPrefix("• ")
        let replacements = lines.enumerated().map { index, range -> (NSRange, String) in
            let line = string.substring(with: range)
            let stripped = Self.stripMarker(line)
            if isOn { return (range, stripped) }
            return (range, (numbered ? "\(index + 1). " : "• ") + stripped)
        }
        guard textView.shouldChangeText(in: paragraphs, replacementString: nil) else { return }
        storage.beginEditing()
        for (range, text) in replacements.reversed() {
            let attributes = range.length > 0 ? storage.attributes(at: range.location, effectiveRange: nil) : textView.typingAttributes
            storage.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: attributes))
        }
        storage.endEditing()
        textView.didChangeText()
    }

    static func stripMarker(_ line: String) -> String {
        if line.hasPrefix("• ") { return String(line.dropFirst(2)) }
        if let match = line.range(of: #"^\d+\. "#, options: .regularExpression) { return String(line[match.upperBound...]) }
        return line
    }
}

/// An NSTextView for one note: rich text, undo, list continuation on Return,
/// and its content height reported for Grow canvas.
struct RichTextEditor: NSViewRepresentable {
    let noteID: UUID
    let rtf: Data
    let controller: RichTextController
    var onChange: (NSAttributedString) -> Void
    var onHeight: (CGFloat) -> Void

    /// Under the Scratchpad's prefix, so the console clears it as it goes.
    static let editingOwner = "droplet.scratchpad.editor"

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.scrollerStyle = .overlay
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        // Tama's own accent (Settings › Theming), like every other control here.
        textView.insertionPointColor = NSColor(DS.accent)
        textView.setAccessibilityLabel("Note")
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.typingAttributes = RichText.bodyAttributes
        textView.textStorage?.setAttributedString(RichText.attributed(from: rtf))
        context.coordinator.lastRTF = rtf
        controller.textView = textView
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
            context.coordinator.reportHeight(textView)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? NSTextView else { return }
        controller.textView = textView
        // Changed from outside (Undo of a clear, a sync from Apple Notes).
        if rtf != context.coordinator.lastRTF, context.coordinator.lastNoteID != noteID || !textView.hasMarkedText() {
            if rtf != RichText.rtf(textView.attributedString()) {
                textView.textStorage?.setAttributedString(RichText.attributed(from: rtf))
            }
            context.coordinator.lastRTF = rtf
            context.coordinator.lastNoteID = noteID
            context.coordinator.reportHeight(textView)
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        if coordinator.isEditing { AppState.shared.setEditing(false, owner: RichTextEditor.editingOwner) }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        var lastRTF = Data()
        var lastNoteID: UUID?
        var isEditing = false

        init(_ parent: RichTextEditor) {
            self.parent = parent
            self.lastNoteID = parent.noteID
        }

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
            // Typing holds the shelf open.
            AppState.shared.setEditing(true, owner: RichTextEditor.editingOwner)
        }

        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
            AppState.shared.setEditing(false, owner: RichTextEditor.editingOwner)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let snapshot = NSAttributedString(attributedString: textView.attributedString())
            lastRTF = RichText.rtf(snapshot)
            parent.onChange(snapshot)
            reportHeight(textView)
        }

        func reportHeight(_ textView: NSTextView) {
            guard let layout = textView.layoutManager, let container = textView.textContainer else { return }
            layout.ensureLayout(for: container)
            parent.onHeight(layout.usedRect(for: container).height + textView.textContainerInset.height * 2)
        }

        /// Return inside a list continues it; on an empty item it ends the list.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let string = textView.string as NSString
            let caret = textView.selectedRange()
            let paragraph = string.paragraphRange(for: NSRange(location: caret.location, length: 0))
            let line = string.substring(with: paragraph).trimmingCharacters(in: .newlines)
            var marker: String?
            if line.hasPrefix("• ") {
                marker = "• "
            } else if let match = line.range(of: #"^(\d+)\. "#, options: .regularExpression),
                      let number = Int(line[match].dropLast(2)) {
                marker = "\(number + 1). "
            }
            guard let marker else { return false }
            if RichTextController.stripMarker(line).isEmpty {
                // An empty item: drop its marker instead of adding another.
                let range = NSRange(location: paragraph.location, length: (line as NSString).length)
                if textView.shouldChangeText(in: range, replacementString: "") {
                    textView.textStorage?.replaceCharacters(in: range, with: "")
                    textView.didChangeText()
                }
                return true
            }
            textView.insertText("\n" + marker, replacementRange: caret)
            return true
        }
    }
}

/// The floating glass format bar: B I U | H1 H2 H3 | bullets numbers.
struct NoteFormatBar: View {
    let controller: RichTextController

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            button(text: "B", weight: .heavy, help: "Bold") { controller.toggleTrait(.boldFontMask) }
            button(text: "I", italic: true, help: "Italic") { controller.toggleTrait(.italicFontMask) }
            button(text: "U", underline: true, help: "Underline") { controller.toggleUnderline() }
            divider
            button(text: "H1", help: "Heading 1") { controller.heading(1) }
            button(text: "H2", help: "Heading 2") { controller.heading(2) }
            button(text: "H3", help: "Heading 3") { controller.heading(3) }
            divider
            button(symbol: "list.bullet", help: "Bulleted list") { controller.toggleList(numbered: false) }
            button(symbol: "list.number", help: "Numbered list") { controller.toggleList(numbered: true) }
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xs)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(DS.Palette.hairlineStrong.opacity(0.7), lineWidth: 0.5))
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }

    private var divider: some View {
        Rectangle().fill(DS.Palette.hairlineStrong).frame(width: 1, height: 16).padding(.horizontal, 3)
            .accessibilityHidden(true)
    }

    private func button(text: String? = nil, symbol: String? = nil, weight: Font.Weight = .bold, italic: Bool = false,
                        underline: Bool = false, help: String, action: @escaping () -> Void) -> some View {
        FormatButton(text: text, symbol: symbol, weight: weight, italic: italic, underline: underline, help: help, action: action)
    }
}

private struct FormatButton: View {
    let text: String?
    let symbol: String?
    let weight: Font.Weight
    let italic: Bool
    let underline: Bool
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            action()
            DroppyAudio.playTick()
        } label: {
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                } else if let text {
                    Text(text)
                        .font(.system(size: 11.5, weight: weight))
                        .italic(italic)
                        .underline(underline)
                }
            }
            .foregroundStyle(isHovered ? DS.Palette.textPrimary : Color.white.opacity(0.8))
            .frame(width: 28, height: 26)
            .background(Circle().fill(isHovered ? DS.Palette.surface3 : Color.white.opacity(0.07)))
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .onHover { isHovered = $0 }
        .animation(DS.Motion.hover, value: isHovered)
        .help(help)
        .accessibilityLabel(help)
    }
}
