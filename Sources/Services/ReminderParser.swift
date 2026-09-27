import Foundation

/// Splits "Call mom tomorrow 5pm #Family !!" into a title, due-date
/// components, a list mention and a priority.
struct ReminderDraft: Equatable, Sendable {
    var title: String
    /// Year/month/day, plus hour/minute only when the text named a time.
    var due: DateComponents?
    /// `#List` / `@List` (or `#"Two words"`): the Reminders list to use.
    var listName: String? = nil
    /// EventKit priority: 0 none, 1 high, 5 medium, 9 low.
    var priority: Int = 0
}

/// Reminder priorities as the page shows them. EventKit stores 1–4 as high,
/// 5 as medium and 6–9 as low.
public enum TaskPriority: Int, CaseIterable, Sendable {
    case none = 0, low = 9, medium = 5, high = 1

    public init(eventKit value: Int) {
        switch value {
        case 1...4: self = .high
        case 5: self = .medium
        case 6...9: self = .low
        default: self = .none
        }
    }

    public var title: String {
        switch self {
        case .none: "Normal Priority"
        case .low: "Low Priority"
        case .medium: "Medium Priority"
        case .high: "High Priority"
        }
    }

    public var marks: String {
        switch self {
        case .none: ""
        case .low: "!"
        case .medium: "!!"
        case .high: "!!!"
        }
    }

    /// Clicking the priority dot steps through them.
    public var next: TaskPriority {
        switch self {
        case .none: .low
        case .low: .medium
        case .medium: .high
        case .high: .none
        }
    }
}

enum ReminderParser {
    /// Words left dangling once the date is cut out ("Meeting on", "Standup
    /// at"), in the languages NSDataDetector reads dates in.
    static let danglingWords: Set<String> = [
        // English
        "on", "at", "by", "due", "for", "before", "until", "in", "from",
        // German
        "am", "um", "bis", "an", "für", "vor", "ab", "im", "zum", "zur", "nächsten", "nächste",
        // Dutch
        "op", "om", "tot", "voor", "vóór", "uiterlijk", "per", "volgende",
        // French
        "le", "à", "pour", "avant", "dans", "vers", "d'ici", "jusqu'à", "prochain", "prochaine",
        // Spanish / Portuguese / Italian
        "el", "las", "los", "para", "antes", "hasta", "en", "às", "até",
        "il", "alle", "alla", "entro", "prima", "próximo", "próxima", "prossimo",
        // Swedish / Danish / Norwegian
        "på", "kl", "kl.", "till", "innan", "senast", "til", "før",
    ]

    /// The detector resolves a bare day to noon; without one of these the
    /// reminder is all-day instead of silently due at 12:00.
    private static let timePattern = try! NSRegularExpression(
        pattern: #"\d{1,2}(:\d{2})?\s*[ap]\.?m\b|\d{1,2}[:.h]\d{2}|\b(noon|midnight|tonight|morning|afternoon|evening|hours?|minutes?|mins?|uur|uhr|heures?|horas?|ore|mittag|middag|midi)\b|\b(at|om|um|à|a las|alle|kl\.?)\s+\d{1,2}\b"#,
        options: [.caseInsensitive]
    )

    /// `#Work`, `@Work`, `#"Two words"`, `@"Two words"`.
    private static let listPattern = try! NSRegularExpression(
        pattern: #"(?:^|\s)[#@](?:"([^"]+)"|([\p{L}\p{N}_\-]+))"#
    )

    /// `!`, `!!` or `!!!` standing alone.
    private static let priorityPattern = try! NSRegularExpression(pattern: #"(?:^|\s)(!{1,3})(?=\s|$)"#)

    static func parse(_ text: String, calendar: Calendar = .current) -> ReminderDraft? {
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        var listName: String?
        if let match = listPattern.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)),
           let whole = Range(match.range, in: clean) {
            let quoted = Range(match.range(at: 1), in: clean).map { String(clean[$0]) }
            let bare = Range(match.range(at: 2), in: clean).map { String(clean[$0]).replacingOccurrences(of: "_", with: " ") }
            listName = quoted ?? bare
            clean.replaceSubrange(whole, with: " ")
        }

        var priority = 0
        if let match = priorityPattern.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)),
           let marks = Range(match.range(at: 1), in: clean), let whole = Range(match.range, in: clean) {
            switch clean[marks].count {
            case 3: priority = TaskPriority.high.rawValue
            case 2: priority = TaskPriority.medium.rawValue
            default: priority = TaskPriority.low.rawValue
            }
            clean.replaceSubrange(whole, with: " ")
        }
        clean = collapse(clean)
        // Only a mention or marks were typed: keep them as the title.
        guard !clean.isEmpty else {
            return ReminderDraft(title: text.trimmingCharacters(in: .whitespacesAndNewlines), due: nil)
        }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)),
              let date = match.date,
              let range = Range(match.range, in: clean) else {
            return ReminderDraft(title: clean, due: nil, listName: listName, priority: priority)
        }
        let phrase = String(clean[range])
        var title = collapse(clean.replacingCharacters(in: range, with: " "))
        var words = title.split(separator: " ")
        while let last = words.last, danglingWords.contains(last.lowercased()) { words.removeLast() }
        title = words.joined(separator: " ")

        let units: Set<Calendar.Component> = hasExplicitTime(phrase)
            ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
        var due = calendar.dateComponents(units, from: date)
        // Without a calendar `DateComponents.date` is nil, and the agenda sorts
        // and filters reminders by that. No time zone: EventKit treats it as floating.
        due.calendar = calendar
        return ReminderDraft(title: title.isEmpty ? clean : title, due: due, listName: listName, priority: priority)
    }

    static func hasExplicitTime(_ phrase: String) -> Bool {
        timePattern.firstMatch(in: phrase, range: NSRange(phrase.startIndex..., in: phrase)) != nil
    }

    private static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
