import Foundation

// A small VT100/xterm screen model for TermiNotch: enough of the escape
// language that shells, `ls --color`, git, brew, npm, top and less draw
// properly. It knows nothing about AppKit; the view draws `rows`.

/// A colour as the program asked for it; the view maps it to a palette.
public enum TerminalColor: Equatable, Hashable, Sendable {
    /// 0–15: the 16 ANSI colours (8–15 are the bright ones).
    case ansi(Int)
    /// 16–255 of the xterm 256-colour cube and grey ramp.
    case palette(Int)
    case rgb(UInt8, UInt8, UInt8)
}

public struct TerminalStyle: Equatable, Hashable, Sendable {
    public var foreground: TerminalColor?
    public var background: TerminalColor?
    public var bold = false
    public var dim = false
    public var italic = false
    public var underline = false
    public var inverse = false

    public init() {}
}

public struct TerminalCell: Equatable, Sendable {
    public var character: Character
    public var style: TerminalStyle

    public static let blank = TerminalCell(character: " ", style: TerminalStyle())

    public init(character: Character, style: TerminalStyle) {
        self.character = character
        self.style = style
    }
}

public final class TerminalScreen {
    public private(set) var columns: Int
    public private(set) var rowCount: Int
    /// Lines that scrolled off the top of the main screen, oldest first.
    public private(set) var scrollback: [[TerminalCell]] = []
    public private(set) var grid: [[TerminalCell]]
    public private(set) var cursorX = 0
    public private(set) var cursorY = 0
    public private(set) var cursorVisible = true
    /// DECCKM: arrows send ESC O A instead of ESC [ A (vim, less).
    public private(set) var applicationCursorKeys = false
    public private(set) var bracketedPaste = false
    public private(set) var isAlternateScreen = false
    /// OSC 0/2.
    public private(set) var title = ""
    /// OSC 7 (file://host/path), which our zsh prompt hook sends after each command.
    public private(set) var reportedDirectory: String?
    /// Bumped on every change so a view knows to redraw.
    public private(set) var version = 0

    public let scrollbackLimit: Int

    private var style = TerminalStyle()
    private var wrapPending = false
    private var autowrap = true
    private var scrollTop = 0
    private var scrollBottom: Int
    private var saved: (x: Int, y: Int, style: TerminalStyle) = (0, 0, TerminalStyle())
    private var mainGrid: [[TerminalCell]] = []
    private var mainCursor: (x: Int, y: Int) = (0, 0)

    // Parser
    private enum State { case ground, escape, csi, osc, oscEscape, charset, ignoreString, ignoreStringEscape }
    private var state = State.ground
    private var params = ""
    private var oscText = ""
    private var utf8 = [UInt8]()
    private var utf8Needed = 0

    /// Bytes the terminal owes the program (cursor-position and device
    /// reports); the session writes them back to the pty.
    public private(set) var responses = Data()

    public init(columns: Int = 80, rows: Int = 24, scrollbackLimit: Int = 3000) {
        self.columns = max(columns, 2)
        self.rowCount = max(rows, 1)
        self.scrollbackLimit = scrollbackLimit
        grid = Array(repeating: Array(repeating: .blank, count: max(columns, 2)), count: max(rows, 1))
        scrollBottom = max(rows, 1) - 1
    }

    public func takeResponses() -> Data {
        defer { responses.removeAll() }
        return responses
    }

    // MARK: Input

    public func feed(_ data: Data) {
        for byte in data { feed(byte) }
        version &+= 1
    }

    public func feed(_ text: String) { feed(Data(text.utf8)) }

    private func feed(_ byte: UInt8) {
        switch state {
        case .ground: ground(byte)
        case .escape: escape(byte)
        case .csi: csi(byte)
        case .osc:
            if byte == 0x07 { finishOSC() }
            else if byte == 0x1b { state = .oscEscape }
            else if oscText.utf8.count < 4096 { oscText.unicodeScalars.append(Unicode.Scalar(byte)) }
        case .oscEscape:
            // ESC \ ends it; anything else also ends it and is dropped.
            finishOSC()
            if byte != 0x5c { escape(byte) }
        case .charset:
            state = .ground
        case .ignoreString:
            if byte == 0x07 { state = .ground } else if byte == 0x1b { state = .ignoreStringEscape }
        case .ignoreStringEscape:
            state = byte == 0x5c ? .ground : .ignoreString
        }
    }

    private func ground(_ byte: UInt8) {
        if utf8Needed > 0 {
            if byte & 0xC0 == 0x80 {
                utf8.append(byte)
                utf8Needed -= 1
                if utf8Needed == 0 {
                    let text = String(decoding: utf8, as: UTF8.self)
                    utf8.removeAll()
                    for character in text { put(character) }
                }
                return
            }
            // A broken sequence: drop it and read this byte afresh.
            utf8.removeAll()
            utf8Needed = 0
        }
        switch byte {
        case 0x1b: state = .escape
        case 0x0d: carriageReturn()
        case 0x0a, 0x0b, 0x0c: lineFeed()
        case 0x08: backspace()
        case 0x09: tab()
        case 0x07, 0x00, 0x0e, 0x0f: break
        case 0x20..<0x7f: put(Character(Unicode.Scalar(byte)))
        case 0xC0..<0xE0: utf8 = [byte]; utf8Needed = 1
        case 0xE0..<0xF0: utf8 = [byte]; utf8Needed = 2
        case 0xF0..<0xF8: utf8 = [byte]; utf8Needed = 3
        default: break
        }
    }

    private func escape(_ byte: UInt8) {
        state = .ground
        switch byte {
        case 0x5b: // [
            params = ""
            state = .csi
        case 0x5d: // ]
            oscText = ""
            state = .osc
        case 0x28, 0x29, 0x2a, 0x2b: // ( ) * + : charset designation takes one more byte
            state = .charset
        case 0x50, 0x58, 0x5e, 0x5f: // DCS, SOS, PM, APC strings are skipped
            state = .ignoreString
        case 0x37: saveCursor()      // 7
        case 0x38: restoreCursor()   // 8
        case 0x44: lineFeed()        // D: index
        case 0x45: carriageReturn(); lineFeed() // E
        case 0x4d: reverseIndex()    // M
        case 0x63: reset()           // c
        default: break               // = > and the rest
        }
    }

    private func csi(_ byte: UInt8) {
        switch byte {
        case 0x30...0x3f: // digits ; : < = > ?
            if params.count < 64 { params.unicodeScalars.append(Unicode.Scalar(byte)) }
        case 0x20...0x2f: // intermediates (e.g. the space in "CSI 2 q")
            if params.count < 64 { params.unicodeScalars.append(Unicode.Scalar(byte)) }
        case 0x40...0x7e:
            state = .ground
            performCSI(Character(Unicode.Scalar(byte)), params)
        case 0x18, 0x1a: state = .ground
        case 0x1b: state = .escape
        default: break
        }
    }

    private func finishOSC() {
        state = .ground
        guard let separator = oscText.firstIndex(of: ";") else { return }
        let code = oscText[..<separator]
        let value = String(oscText[oscText.index(after: separator)...])
        switch code {
        case "0", "2": title = value
        case "7":
            if let url = URL(string: value), url.isFileURL {
                reportedDirectory = url.path
            }
        default: break
        }
    }

    // MARK: CSI

    private func performCSI(_ final: Character, _ raw: String) {
        let isPrivate = raw.hasPrefix("?")
        let hasIntermediate = raw.contains(" ") || raw.contains("!") || raw.contains("\"") || raw.contains("$")
        if hasIntermediate {
            if raw == "!", final == "p" { softReset() }
            return
        }
        let body = raw.drop { $0 == "?" || $0 == ">" || $0 == "=" || $0 == "<" }
        let values = body.split(separator: ";", omittingEmptySubsequences: false).map { Int($0.split(separator: ":").first ?? "") ?? 0 }
        func arg(_ index: Int, _ fallback: Int) -> Int {
            index < values.count && values[index] != 0 ? values[index] : fallback
        }
        if raw.hasPrefix(">") || raw.hasPrefix("=") {
            if final == "c" { responses.append(contentsOf: Array("\u{1b}[>0;10;1c".utf8)) }
            return
        }
        switch final {
        case "A": moveCursor(x: cursorX, y: max(cursorY - arg(0, 1), cursorY >= scrollTop ? scrollTop : 0))
        case "B", "e": moveCursor(x: cursorX, y: min(cursorY + arg(0, 1), cursorY <= scrollBottom ? scrollBottom : rowCount - 1))
        case "C", "a": moveCursor(x: cursorX + arg(0, 1), y: cursorY)
        case "D": moveCursor(x: cursorX - arg(0, 1), y: cursorY)
        case "E": moveCursor(x: 0, y: cursorY + arg(0, 1))
        case "F": moveCursor(x: 0, y: cursorY - arg(0, 1))
        case "G", "`": moveCursor(x: arg(0, 1) - 1, y: cursorY)
        case "d": moveCursor(x: cursorX, y: arg(0, 1) - 1)
        case "H", "f": moveCursor(x: arg(1, 1) - 1, y: arg(0, 1) - 1)
        case "J": eraseInDisplay(values.first ?? 0)
        case "K": eraseInLine(values.first ?? 0)
        case "L": insertLines(arg(0, 1))
        case "M": deleteLines(arg(0, 1))
        case "P": deleteCharacters(arg(0, 1))
        case "@": insertCharacters(arg(0, 1))
        case "X": eraseCharacters(arg(0, 1))
        case "S": for _ in 0..<min(arg(0, 1), rowCount) { scrollUp() }
        case "T": for _ in 0..<min(arg(0, 1), rowCount) { scrollDown() }
        case "m": selectGraphicRendition(isPrivate ? [] : (values.isEmpty ? [0] : values))
        case "r":
            let top = arg(0, 1) - 1
            let bottom = arg(1, rowCount) - 1
            if top < bottom, bottom < rowCount {
                scrollTop = top
                scrollBottom = bottom
            } else {
                scrollTop = 0
                scrollBottom = rowCount - 1
            }
            moveCursor(x: 0, y: 0)
        case "s": if !isPrivate { saveCursor() }
        case "u": restoreCursor()
        case "h", "l": setModes(values, on: final == "h", isPrivate: isPrivate)
        case "n":
            switch values.first ?? 0 {
            case 5: responses.append(contentsOf: Array("\u{1b}[0n".utf8))
            case 6: responses.append(contentsOf: Array("\u{1b}[\(cursorY + 1);\(cursorX + 1)R".utf8))
            default: break
            }
        case "c": responses.append(contentsOf: Array("\u{1b}[?1;2c".utf8))
        default: break // t, q and friends
        }
    }

    private func setModes(_ modes: [Int], on: Bool, isPrivate: Bool) {
        guard isPrivate else { return } // ANSI modes (insert mode) are rare in shells
        for mode in modes {
            switch mode {
            case 1: applicationCursorKeys = on
            case 7: autowrap = on
            case 25: cursorVisible = on
            case 47, 1047: switchScreen(alternate: on, saveCursor: false)
            case 1049: switchScreen(alternate: on, saveCursor: true)
            case 2004: bracketedPaste = on
            default: break
            }
        }
    }

    private func selectGraphicRendition(_ values: [Int]) {
        var index = 0
        while index < values.count {
            let code = values[index]
            switch code {
            case 0: style = TerminalStyle()
            case 1: style.bold = true
            case 2: style.dim = true
            case 3: style.italic = true
            case 4: style.underline = true
            case 7: style.inverse = true
            case 21, 22: style.bold = false; style.dim = false
            case 23: style.italic = false
            case 24: style.underline = false
            case 27: style.inverse = false
            case 30...37: style.foreground = .ansi(code - 30)
            case 39: style.foreground = nil
            case 40...47: style.background = .ansi(code - 40)
            case 49: style.background = nil
            case 90...97: style.foreground = .ansi(code - 90 + 8)
            case 100...107: style.background = .ansi(code - 100 + 8)
            case 38, 48:
                var color: TerminalColor?
                if index + 2 < values.count, values[index + 1] == 5 {
                    let n = values[index + 2]
                    color = n < 16 ? .ansi(n) : .palette(min(n, 255))
                    index += 2
                } else if index + 4 < values.count, values[index + 1] == 2 {
                    color = .rgb(UInt8(clamping: values[index + 2]), UInt8(clamping: values[index + 3]),
                                 UInt8(clamping: values[index + 4]))
                    index += 4
                }
                if code == 38 { style.foreground = color } else { style.background = color }
            default: break
            }
            index += 1
        }
    }

    // MARK: Primitives

    private var blankCell: TerminalCell {
        // Erased cells keep the background colour, like xterm.
        var blankStyle = TerminalStyle()
        blankStyle.background = style.background
        return TerminalCell(character: " ", style: blankStyle)
    }

    private func blankRow() -> [TerminalCell] { Array(repeating: blankCell, count: columns) }

    private func put(_ character: Character) {
        if wrapPending {
            wrapPending = false
            carriageReturn()
            lineFeed()
        }
        grid[cursorY][cursorX] = TerminalCell(character: character, style: style)
        if cursorX >= columns - 1 {
            wrapPending = autowrap
        } else {
            cursorX += 1
        }
    }

    private func carriageReturn() {
        cursorX = 0
        wrapPending = false
    }

    private func lineFeed() {
        wrapPending = false
        if cursorY == scrollBottom {
            scrollUp()
        } else if cursorY < rowCount - 1 {
            cursorY += 1
        }
    }

    private func reverseIndex() {
        wrapPending = false
        if cursorY == scrollTop { scrollDown() } else if cursorY > 0 { cursorY -= 1 }
    }

    private func backspace() {
        wrapPending = false
        if cursorX > 0 { cursorX -= 1 }
    }

    private func tab() {
        cursorX = min((cursorX / 8 + 1) * 8, columns - 1)
    }

    private func scrollUp() {
        let line = grid.remove(at: scrollTop)
        if scrollTop == 0, !isAlternateScreen {
            scrollback.append(line)
            if scrollback.count > scrollbackLimit { scrollback.removeFirst(scrollback.count - scrollbackLimit) }
        }
        grid.insert(blankRow(), at: scrollBottom)
    }

    private func scrollDown() {
        grid.remove(at: scrollBottom)
        grid.insert(blankRow(), at: scrollTop)
    }

    private func moveCursor(x: Int, y: Int) {
        wrapPending = false
        cursorX = min(max(x, 0), columns - 1)
        cursorY = min(max(y, 0), rowCount - 1)
    }

    private func eraseInDisplay(_ mode: Int) {
        switch mode {
        case 0:
            eraseInLine(0)
            for row in (cursorY + 1)..<max(rowCount, cursorY + 1) { grid[row] = blankRow() }
        case 1:
            eraseInLine(1)
            for row in 0..<cursorY { grid[row] = blankRow() }
        case 2:
            for row in 0..<rowCount { grid[row] = blankRow() }
        case 3:
            scrollback.removeAll()
        default: break
        }
    }

    private func eraseInLine(_ mode: Int) {
        let range: Range<Int>
        switch mode {
        case 0: range = cursorX..<columns
        case 1: range = 0..<min(cursorX + 1, columns)
        default: range = 0..<columns
        }
        for column in range { grid[cursorY][column] = blankCell }
    }

    private func insertLines(_ count: Int) {
        guard cursorY >= scrollTop, cursorY <= scrollBottom else { return }
        for _ in 0..<min(count, scrollBottom - cursorY + 1) {
            grid.remove(at: scrollBottom)
            grid.insert(blankRow(), at: cursorY)
        }
    }

    private func deleteLines(_ count: Int) {
        guard cursorY >= scrollTop, cursorY <= scrollBottom else { return }
        for _ in 0..<min(count, scrollBottom - cursorY + 1) {
            grid.remove(at: cursorY)
            grid.insert(blankRow(), at: scrollBottom)
        }
    }

    private func deleteCharacters(_ count: Int) {
        let n = min(count, columns - cursorX)
        grid[cursorY].removeSubrange(cursorX..<(cursorX + n))
        grid[cursorY].append(contentsOf: Array(repeating: blankCell, count: n))
    }

    private func insertCharacters(_ count: Int) {
        let n = min(count, columns - cursorX)
        grid[cursorY].insert(contentsOf: Array(repeating: blankCell, count: n), at: cursorX)
        grid[cursorY].removeLast(n)
    }

    private func eraseCharacters(_ count: Int) {
        for column in cursorX..<min(cursorX + count, columns) { grid[cursorY][column] = blankCell }
    }

    private func saveCursor() { saved = (cursorX, cursorY, style) }

    private func restoreCursor() {
        style = saved.style
        moveCursor(x: saved.x, y: saved.y)
    }

    private func switchScreen(alternate: Bool, saveCursor save: Bool) {
        guard alternate != isAlternateScreen else { return }
        if alternate {
            if save { mainCursor = (cursorX, cursorY) }
            mainGrid = grid
            grid = Array(repeating: Array(repeating: .blank, count: columns), count: rowCount)
            isAlternateScreen = true
        } else {
            grid = mainGrid.count == rowCount ? mainGrid : Array(repeating: Array(repeating: .blank, count: columns), count: rowCount)
            mainGrid = []
            isAlternateScreen = false
            if save { moveCursor(x: mainCursor.x, y: mainCursor.y) }
        }
        scrollTop = 0
        scrollBottom = rowCount - 1
    }

    private func softReset() {
        style = TerminalStyle()
        cursorVisible = true
        applicationCursorKeys = false
        autowrap = true
        scrollTop = 0
        scrollBottom = rowCount - 1
    }

    public func reset() {
        softReset()
        if isAlternateScreen { switchScreen(alternate: false, saveCursor: false) }
        grid = Array(repeating: Array(repeating: .blank, count: columns), count: rowCount)
        moveCursor(x: 0, y: 0)
        bracketedPaste = false
        version &+= 1
    }

    /// ⌘K: forget the scrollback and blank the screen, keeping the cursor's line on top.
    public func clearAll() {
        scrollback.removeAll()
        let current = grid[cursorY]
        grid = Array(repeating: Array(repeating: .blank, count: columns), count: rowCount)
        grid[0] = current
        cursorY = 0
        version &+= 1
    }

    // MARK: Size

    public func resize(columns newColumns: Int, rows newRows: Int) {
        let newColumns = max(newColumns, 2)
        let newRows = max(newRows, 1)
        guard newColumns != columns || newRows != rowCount else { return }
        func fit(_ row: [TerminalCell]) -> [TerminalCell] {
            row.count >= newColumns ? Array(row.prefix(newColumns))
                : row + Array(repeating: .blank, count: newColumns - row.count)
        }
        grid = grid.map(fit)
        if newRows < rowCount {
            // Lose lines from the top (into the scrollback) rather than the
            // cursor's line, the way Terminal does.
            let excess = rowCount - newRows
            let fromTop = min(excess, cursorY)
            if fromTop > 0 {
                if !isAlternateScreen { scrollback.append(contentsOf: grid.prefix(fromTop)) }
                grid.removeFirst(fromTop)
                cursorY -= fromTop
            }
            if grid.count > newRows { grid.removeLast(grid.count - newRows) }
        } else if newRows > rowCount {
            // Pull lines back out of the scrollback before adding blanks.
            var missing = newRows - rowCount
            while missing > 0, !isAlternateScreen, let line = scrollback.popLast() {
                grid.insert(fit(line), at: 0)
                cursorY += 1
                missing -= 1
            }
            grid.append(contentsOf: Array(repeating: Array(repeating: .blank, count: newColumns), count: missing))
        }
        if !mainGrid.isEmpty {
            mainGrid = mainGrid.map(fit)
            if mainGrid.count > newRows { mainGrid.removeFirst(mainGrid.count - newRows) }
            while mainGrid.count < newRows { mainGrid.append(Array(repeating: .blank, count: newColumns)) }
        }
        scrollback = scrollback.map(fit)
        columns = newColumns
        rowCount = newRows
        scrollTop = 0
        scrollBottom = newRows - 1
        cursorX = min(cursorX, newColumns - 1)
        cursorY = min(max(cursorY, 0), newRows - 1)
        wrapPending = false
        version &+= 1
    }

    // MARK: Reading

    /// A row as plain text without trailing blanks.
    public static func text(of row: [TerminalCell]) -> String {
        var text = String(row.map(\.character))
        while text.last == " " { text.removeLast() }
        return text
    }

    /// Every line, scrollback then screen, as text, with trailing empty lines dropped.
    public var plainText: String {
        var lines = (scrollback + grid).map(Self.text(of:))
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// The last non-empty lines, for the quick bar.
    public func lastLines(_ count: Int) -> [[TerminalCell]] {
        let all = scrollback + grid
        var end = all.count
        while end > 0, Self.text(of: all[end - 1]).isEmpty { end -= 1 }
        return Array(all[max(0, end - count)..<end])
    }
}
