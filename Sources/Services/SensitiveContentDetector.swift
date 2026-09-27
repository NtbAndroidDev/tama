import Foundation

/// Recognises secrets that shouldn't sit in clipboard history. Pure and
/// synchronous so it can be tested on its own. Short numeric codes (OTPs) are
/// deliberately let through: they expire in seconds and people paste them twice.
public enum SensitiveContentDetector {
    public enum Kind: String, CaseIterable, Sendable {
        case creditCard = "Card number"
        case privateKey = "Private key"
        case awsAccessKey = "AWS access key"
        case gitHubToken = "GitHub token"
        case jsonWebToken = "Access token"
    }

    /// The first kind of secret found in `text`, or nil when it looks harmless.
    public static func detect(_ text: String) -> Kind? {
        // Huge clips are dumps and logs; scanning them costs more than it saves.
        let sample = text.utf16.count > 200_000 ? String(text.prefix(200_000)) : text
        if matches(privateKey, in: sample) { return .privateKey }
        if matches(awsKey, in: sample) { return .awsAccessKey }
        if matches(gitHubToken, in: sample) { return .gitHubToken }
        if matches(jwt, in: sample) { return .jsonWebToken }
        if containsCardNumber(sample) { return .creditCard }
        return nil
    }

    public static func isSensitive(_ text: String) -> Bool {
        detect(text) != nil
    }

    // MARK: Patterns

    private static let privateKey = regex(#"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY(?: BLOCK)?-----"#)
    private static let awsKey = regex(#"(?<![A-Z0-9])(?:AKIA|ASIA)[0-9A-Z]{16}(?![A-Z0-9])"#)
    private static let gitHubToken = regex(#"(?<![A-Za-z0-9_])(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})"#)
    /// header.payload.signature, both JSON parts base64url-encoded — they always start with "eyJ".
    private static let jwt = regex(#"(?<![A-Za-z0-9_-])eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#)
    /// 13–19 digits, optionally grouped with single spaces or dashes.
    private static let cardCandidate = regex(#"(?<![0-9])[0-9](?:[ -]?[0-9]){12,18}(?![0-9])"#)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are constants; a typo should fail loudly in development.
        try! NSRegularExpression(pattern: pattern)
    }

    private static func matches(_ regex: NSRegularExpression, in text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // MARK: Card numbers

    static func containsCardNumber(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        for match in cardCandidate.matches(in: text, range: range) {
            guard let r = Range(match.range, in: text) else { continue }
            let digits = text[r].compactMap(\.wholeNumberValue)
            if looksLikeCard(digits) { return true }
        }
        return false
    }

    /// Issuer prefix and length narrow random numbers down before the Luhn
    /// check, which alone would pass one in ten.
    static func looksLikeCard(_ digits: [Int]) -> Bool {
        guard (13...19).contains(digits.count), let first = digits.first else { return false }
        // Visa 4, Mastercard 2/5, Amex 3, Discover/UnionPay 6.
        guard [2, 3, 4, 5, 6].contains(first) else { return false }
        // A run of one repeated digit is a placeholder, not a card.
        guard Set(digits).count > 1 else { return false }
        return luhn(digits)
    }

    static func luhn(_ digits: [Int]) -> Bool {
        var sum = 0
        for (offset, digit) in digits.reversed().enumerated() {
            if offset % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }
}
