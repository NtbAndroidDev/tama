import Foundation
import Testing
@testable import Droppy

/// NSDataDetector has no reference-date API and reads text in the current
/// time zone, so absolute dates are checked field by field and relative ones
/// against the same calendar's "tomorrow".
@Suite struct ReminderParserTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    @Test func absoluteDateWithTime() throws {
        let draft = try #require(ReminderParser.parse("Dentist Oct 5 2026 at 14:30", calendar: calendar))
        #expect(draft.title == "Dentist")
        let due = try #require(draft.due)
        #expect([due.year, due.month, due.day, due.hour, due.minute] == [2026, 10, 5, 14, 30])
        #expect(due.date != nil)   // the agenda sorts by this
    }

    @Test func dateOnlyIsAllDay() throws {
        // Regression: date-only text used to become a reminder due at 12:00.
        let draft = try #require(ReminderParser.parse("Pay rent on October 5, 2026", calendar: calendar))
        #expect(draft.title == "Pay rent")
        #expect(draft.due?.day == 5 && draft.due?.month == 10)
        #expect(draft.due?.hour == nil && draft.due?.minute == nil)
    }

    @Test func relativeDayAndTime() throws {
        let before = Date()
        let draft = try #require(ReminderParser.parse("Call mom tomorrow 5pm", calendar: calendar))
        #expect(draft.title == "Call mom")
        let due = try #require(draft.due)
        #expect(due.hour == 17 && due.minute == 0)
        let tomorrow = calendar.dateComponents([.day], from: calendar.date(byAdding: .day, value: 1, to: before)!).day
        let tomorrowAfter = calendar.dateComponents([.day], from: calendar.date(byAdding: .day, value: 1, to: Date())!).day
        #expect(due.day == tomorrow || due.day == tomorrowAfter)
    }

    @Test func danglingPrepositionIsTrimmed() throws {
        // Regression: "Meeting on Friday" became a reminder titled "Meeting on".
        #expect(ReminderParser.parse("Meeting on Friday", calendar: calendar)?.title == "Meeting")
        #expect(ReminderParser.parse("Standup at 9am", calendar: calendar)?.title == "Standup")
        #expect(ReminderParser.parse("Submit report by next Monday", calendar: calendar)?.title == "Submit report")
    }

    @Test func textWithoutDateKeepsTitle() {
        #expect(ReminderParser.parse("  Water plants ", calendar: calendar) == ReminderDraft(title: "Water plants", due: nil))
        #expect(ReminderParser.parse("   ", calendar: calendar) == nil)
    }

    @Test func wholeTextIsADateFallsBackToText() throws {
        let draft = try #require(ReminderParser.parse("tomorrow at 9am", calendar: calendar))
        #expect(draft.title == "tomorrow at 9am")
        #expect(draft.due?.hour == 9)
    }

    @Test(arguments: [("5pm", true), ("at 9", true), ("14:30", true), ("noon", true), ("10 a.m.", true),
                      ("in 2 hours", true), ("tomorrow", false), ("October 5, 2026", false), ("next Monday", false)])
    func explicitTimeDetection(_ phrase: String, _ expected: Bool) {
        #expect(ReminderParser.hasExplicitTime(phrase) == expected)
    }

    @Test func listMentionAndPriority() throws {
        let draft = try #require(ReminderParser.parse("Buy milk tomorrow #Groceries !!", calendar: calendar))
        #expect(draft.title == "Buy milk")
        #expect(draft.listName == "Groceries")
        #expect(draft.priority == TaskPriority.medium.rawValue)
        #expect(draft.due != nil)
    }

    @Test func quotedListAndAtMention() throws {
        #expect(ReminderParser.parse("Call Sam @\"Home stuff\"", calendar: calendar)?.listName == "Home stuff")
        #expect(ReminderParser.parse("Call Sam @Work", calendar: calendar)?.title == "Call Sam")
        #expect(ReminderParser.parse("Plan trip #Travel_Plans", calendar: calendar)?.listName == "Travel Plans")
    }

    @Test(arguments: [("Pay bills !", 9), ("Pay bills !!", 5), ("Pay bills !!!", 1), ("Wow! great", 0)])
    func priorityMarks(_ text: String, _ expected: Int) {
        #expect(ReminderParser.parse(text, calendar: calendar)?.priority == expected)
    }

    @Test func onlyMarksKeepsText() {
        #expect(ReminderParser.parse("#Work", calendar: calendar)?.title == "#Work")
    }

    @Test func multilingualDanglingWords() {
        #expect(ReminderParser.danglingWords.contains("om"))
        #expect(ReminderParser.danglingWords.contains("am"))
        #expect(ReminderParser.danglingWords.contains("pour"))
        #expect(ReminderParser.hasExplicitTime("om 14.30"))
        #expect(ReminderParser.hasExplicitTime("um 9 Uhr"))
    }

    @Test func priorityCycle() {
        #expect(TaskPriority.none.next == .low)
        #expect(TaskPriority.high.next == .none)
        #expect(TaskPriority(eventKit: 3) == .high)
        #expect(TaskPriority(eventKit: 7) == .low)
    }
}
