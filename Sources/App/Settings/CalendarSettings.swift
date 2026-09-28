import SwiftUI

/// Settings › Shelf › Tasks & Calendar.
@MainActor
public final class CalendarSettings: SettingsStore {
    public static let shared = CalendarSettings()

    /// The UserDefaults keys behind this store's properties.
    nonisolated static let keys: [String] = [
        "tasksShowTasks", "tasksShowEvents", "tasksHideUndated", "tasksHiddenCalendars",
        "tasksHiddenLists", "tasksDefaultList", "tasksDefaultCalendar", "tasksCleanupDelay",
        "tasksDueAlerts", "tasksDueChime", "tasksHeadsUpMinutes", "tasksEventRing",
        "tasksNextEventWing", "tasksWeekNumbers", "calendarLayout", "calendarPopoutOnTop"
    ]

    @AppStorage("tasksShowTasks") public var showTasks: Bool = true {
        didSet { CalendarService.shared.reload() }
    }
    @AppStorage("tasksShowEvents") public var showEvents: Bool = true {
        didSet { CalendarService.shared.reload() }
    }
    @AppStorage("tasksHideUndated") public var hideUndated: Bool = false {
        didSet { CalendarService.shared.reload() }
    }
    /// Newline-separated calendar identifiers left out of the page.
    @AppStorage("tasksHiddenCalendars") public var hiddenCalendars: String = "" {
        didSet { CalendarService.shared.reload() }
    }
    @AppStorage("tasksHiddenLists") public var hiddenLists: String = "" {
        didSet { CalendarService.shared.reload() }
    }
    /// Where new tasks and events go; "" is the system default.
    @AppStorage("tasksDefaultList") public var defaultList: String = ""
    @AppStorage("tasksDefaultCalendar") public var defaultCalendar: String = ""
    /// Seconds a completed task stays struck through before it's cleaned up.
    @AppStorage("tasksCleanupDelay") public var cleanupDelay: Int = 60
    @AppStorage("tasksDueAlerts") public var dueAlerts: Bool = true {
        didSet { TaskAlertService.shared.tick() }
    }
    @AppStorage("tasksDueChime") public var dueChime: Bool = true
    /// Minutes of warning before a task is due (0: at the due time only).
    @AppStorage("tasksHeadsUpMinutes") public var headsUpMinutes: Int = 10
    @AppStorage("tasksEventRing") public var eventRing: Bool = true {
        didSet { TaskAlertService.shared.tick() }
    }
    @AppStorage("tasksNextEventWing") public var nextEventWing: Bool = false {
        didSet { TaskAlertService.shared.tick() }
    }
    @AppStorage("tasksWeekNumbers") public var weekNumbers: Bool = true
    @AppStorage("calendarLayout") public var layout: CalendarLayout = .agenda
    @AppStorage("calendarPopoutOnTop") public var popoutOnTop: Bool = true {
        didSet { CalendarPopoutController.shared.applyLevel() }
    }

    private init() { super.init(keys: Self.keys) }
}
