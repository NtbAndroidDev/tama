import Foundation

/// Pomodoro › Momentum: how many focus sessions were finished today, and how
/// many days in a row have had at least one. Plain values with no side
/// effects, so the rollover rules can be checked directly.
public struct PomodoroMomentum: Equatable, Sendable {
    /// Focus sessions finished on `day`.
    public var sessionsToday: Int
    /// The day `sessionsToday` counts, as `yyyy-MM-dd`. Empty means never.
    public var day: String
    /// Days in a row ending on `day` with at least one finished session.
    public var streakDays: Int
    /// The longest streak so far.
    public var bestStreak: Int

    public init(sessionsToday: Int = 0, day: String = "", streakDays: Int = 0, bestStreak: Int = 0) {
        self.sessionsToday = sessionsToday
        self.day = day
        self.streakDays = streakDays
        self.bestStreak = bestStreak
    }

    /// `yyyy-MM-dd` in the user's calendar, so a streak follows local midnights.
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The counts after one more focus session finished at `date`.
    public func recording(_ date: Date, calendar: Calendar = .current) -> PomodoroMomentum {
        let today = Self.dayKey(date, calendar: calendar)
        var next = self
        if day == today {
            next.sessionsToday += 1
        } else {
            let yesterday = Self.dayKey(date.addingTimeInterval(-86_400), calendar: calendar)
            next.streakDays = (day == yesterday) ? streakDays + 1 : 1
            next.sessionsToday = 1
            next.day = today
        }
        next.bestStreak = max(next.bestStreak, next.streakDays)
        return next
    }

    /// The streak as it reads on `date`: it survives today and yesterday, and
    /// lapses after that, without needing a timer to clear it.
    public func currentStreak(on date: Date, calendar: Calendar = .current) -> Int {
        guard !day.isEmpty else { return 0 }
        let today = Self.dayKey(date, calendar: calendar)
        let yesterday = Self.dayKey(date.addingTimeInterval(-86_400), calendar: calendar)
        return (day == today || day == yesterday) ? streakDays : 0
    }

    /// Sessions counted for `date`, which is zero once the day rolls over.
    public func sessions(on date: Date, calendar: Calendar = .current) -> Int {
        day == Self.dayKey(date, calendar: calendar) ? sessionsToday : 0
    }

    /// "3 today · 5-day streak", or nil before the first session.
    public func summary(on date: Date, calendar: Calendar = .current) -> String? {
        let sessions = sessions(on: date, calendar: calendar)
        let streak = currentStreak(on: date, calendar: calendar)
        guard sessions > 0 || streak > 0 else { return nil }
        var parts: [String] = []
        if sessions > 0 { parts.append("\(sessions) today") }
        if streak > 0 { parts.append("\(streak)-day streak") }
        return parts.joined(separator: " · ")
    }
}
