import Foundation

/// A small recursive-descent calculator for Quick Math. Unlike
/// `NSExpression(format:)` it never raises on half-typed input — it just
/// returns nil — and always uses floating-point division (7/2 = 3.5).
///
/// Grammar: + - * / % ^, parentheses, unary minus, `pi`, `e`, and the
/// functions sqrt, abs, sin, cos, tan, log (base 10), ln, round, floor, ceil.
/// "x", "×" and "÷" are accepted as operators and "−" (U+2212) as minus.
/// A comma groups thousands when it's followed by groups of three digits
/// ("1,000"); otherwise a single comma is a decimal point ("1,5").
public enum MathEvaluator {
    public static func evaluate(_ input: String) -> Double? {
        let normalized = input
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "\u{2212}", with: "-")
        var parser = Parser(Array(normalized.lowercased()))
        guard let value = parser.parseExpression(), parser.isAtEnd(), value.isFinite else { return nil }
        return value
    }

    /// Whole numbers without a decimal point, others to at most 6 places.
    public static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = "."
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private struct Parser {
        let chars: [Character]
        var pos = 0

        init(_ chars: [Character]) { self.chars = chars }

        mutating func isAtEnd() -> Bool { skip(); return pos >= chars.count }

        mutating func skip() {
            while pos < chars.count, chars[pos].isWhitespace { pos += 1 }
        }

        mutating func peek() -> Character? {
            skip()
            return pos < chars.count ? chars[pos] : nil
        }

        // expression := term (('+' | '-') term)*
        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let c = peek(), c == "+" || c == "-" {
                pos += 1
                guard let rhs = parseTerm() else { return nil }
                value = c == "+" ? value + rhs : value - rhs
            }
            return value
        }

        // term := unary (('*' | 'x' | '/' | '%') unary)*
        mutating func parseTerm() -> Double? {
            guard var value = parseUnary() else { return nil }
            while let c = peek(), c == "*" || c == "/" || c == "%" || (c == "x" && !startsWord(at: pos)) {
                pos += 1
                guard let rhs = parseUnary() else { return nil }
                switch c {
                case "/": guard rhs != 0 else { return nil }; value /= rhs
                case "%": guard rhs != 0 else { return nil }; value = value.truncatingRemainder(dividingBy: rhs)
                default: value *= rhs
                }
            }
            return value
        }

        // unary := ('-' | '+') unary | power
        // Sign binds looser than '^', so -2^2 is -(2^2) = -4 as on paper.
        mutating func parseUnary() -> Double? {
            if let c = peek(), c == "-" || c == "+" {
                pos += 1
                guard let v = parseUnary() else { return nil }
                return c == "-" ? -v : v
            }
            return parsePower()
        }

        // power := primary ('^' unary)?   (right-associative; 2^-1 allowed)
        mutating func parsePower() -> Double? {
            guard let base = parsePrimary() else { return nil }
            if peek() == "^" {
                pos += 1
                guard let exponent = parseUnary() else { return nil }
                return pow(base, exponent)
            }
            return base
        }

        // primary := number | constant | function '(' expression ')' | '(' expression ')'
        mutating func parsePrimary() -> Double? {
            guard let c = peek() else { return nil }
            if c == "(" {
                pos += 1
                guard let v = parseExpression(), peek() == ")" else { return nil }
                pos += 1
                return v
            }
            if c.isNumber || c == "." || c == "," {
                let start = pos
                while pos < chars.count, chars[pos].isNumber || chars[pos] == "." || chars[pos] == "," { pos += 1 }
                return Self.number(String(chars[start..<pos]))
            }
            if c.isLetter {
                let start = pos
                while pos < chars.count, chars[pos].isLetter { pos += 1 }
                let name = String(chars[start..<pos])
                switch name {
                case "pi", "π": return .pi
                case "e": return M_E
                default: break
                }
                guard peek() == "(" else { return nil }
                pos += 1
                guard let arg = parseExpression(), peek() == ")" else { return nil }
                pos += 1
                switch name {
                case "sqrt": return arg >= 0 ? sqrt(arg) : nil
                case "abs": return abs(arg)
                case "sin": return sin(arg)
                case "cos": return cos(arg)
                case "tan": return tan(arg)
                case "log": return arg > 0 ? log10(arg) : nil
                case "ln": return arg > 0 ? log(arg) : nil
                case "round": return arg.rounded()
                case "floor": return floor(arg)
                case "ceil": return ceil(arg)
                default: return nil
                }
            }
            if c == "π" { pos += 1; return .pi }
            return nil
        }

        /// A numeric literal with "," read as thousands separators ("1,000.5")
        /// when every group after the first has three digits, or else as the
        /// decimal point ("1,5"). Anything else ("1,2,3", "1.5,2") is invalid.
        static func number(_ literal: String) -> Double? {
            guard literal.contains(",") else { return Double(literal) }
            let parts = literal.split(separator: ".", omittingEmptySubsequences: false)
            let groups = parts[0].split(separator: ",", omittingEmptySubsequences: false)
            let isGrouped = parts.count <= 2
                && !parts.dropFirst().contains { $0.contains(",") }
                && (1...3).contains(groups[0].count)
                && groups.dropFirst().allSatisfy { $0.count == 3 }
            if isGrouped { return Double(literal.replacingOccurrences(of: ",", with: "")) }
            guard parts.count == 1, groups.count == 2 else { return nil }
            return Double(literal.replacingOccurrences(of: ",", with: "."))
        }

        /// "x" is multiplication unless it begins a word (none of our names do, but stay strict).
        private func startsWord(at index: Int) -> Bool {
            index + 1 < chars.count && chars[index + 1].isLetter
        }
    }
}
