import AppKit
import EventKit
import SwiftUI

/// One row on the Tasks & Calendar page: a calendar event or a reminder.
public struct AgendaEntry: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case event, reminder }

    public let id: String
    public let kind: Kind
    public let title: String
    public let start: Date?
    public let end: Date?
    public let isAllDay: Bool
    public let red: Double
    public let green: Double
    public let blue: Double
    /// EventKit priority (reminders).
    public var priority: Int = 0
    /// The calendar or Reminders list it lives in.
    public var calendarID: String = ""
    public var calendarTitle: String = ""
    /// Completed on the page and waiting for the clean-up delay.
    public var isCompleted: Bool = false
    /// A video-call link found in the event.
    public var joinURL: URL? = nil

    public var color: Color { Color(red: red, green: green, blue: blue) }
}

/// A calendar or Reminders list, for Settings' pickers.
public struct CalendarInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let source: String
    public let red: Double
    public let green: Double
    public let blue: Double
    public var color: Color { Color(red: red, green: green, blue: blue) }
}

public enum CalendarLayout: String, CaseIterable, Sendable {
    /// The reference's: today on the left, what's next grouped by day on the right.
    case agenda
    /// Ours: a month grid beside the agenda.
    case month
}

/// Reads events and reminders from the Mac's calendars for the Tasks &
/// Calendar page, and adds, completes, reschedules and deletes reminders.
@MainActor
public final class CalendarService: ObservableObject {
    public static let shared = CalendarService()

    @Published public private(set) var hasEventAccess = false
    @Published public private(set) var hasReminderAccess = false
    /// Reminders were refused (or restricted) — calendars may still be allowed,
    /// so the page needs its own message for adding tasks.
    @Published public private(set) var isReminderAccessDenied = false
    @Published public private(set) var agenda: [AgendaEntry] = []
    @Published public private(set) var busyDays: Set<DateComponents> = []
    @Published public private(set) var eventCalendars: [CalendarInfo] = []
    @Published public private(set) var reminderLists: [CalendarInfo] = []
    /// First fetch hasn't come back yet.
    @Published public private(set) var isLoading = true

    let store = EKEventStore()
    private var didRequest = false
    /// Completed on the page: shown struck through until the clean-up delay.
    private var completed: [String: (entry: AgendaEntry, at: Date)] = [:]
    private var cleanupTimer: Timer?

    private init() {
        refreshAuthorization()
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadCalendars()
                self?.reload()
            }
        }
    }

    // MARK: Access

    private func refreshAuthorization() {
        hasEventAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        let reminders = EKEventStore.authorizationStatus(for: .reminder)
        hasReminderAccess = reminders == .fullAccess
        isReminderAccessDenied = reminders == .denied || reminders == .restricted
    }

    /// Asks once per launch; the page keeps working (grid only) without access.
    public func requestAccessIfNeeded() {
        refreshAuthorization()
        guard !didRequest, !(hasEventAccess && hasReminderAccess) else {
            reloadCalendars()
            reload()
            return
        }
        didRequest = true
        Task {
            let events = (try? await store.requestFullAccessToEvents()) ?? false
            let reminders = (try? await store.requestFullAccessToReminders()) ?? false
            hasEventAccess = events
            hasReminderAccess = reminders
            isReminderAccessDenied = !reminders
            reloadCalendars()
            reload()
        }
    }

    // MARK: Calendars & lists

    public func reloadCalendars() {
        refreshAuthorization()
        eventCalendars = hasEventAccess ? store.calendars(for: .event).map(Self.info).sorted(by: Self.byTitle) : []
        reminderLists = hasReminderAccess ? store.calendars(for: .reminder).map(Self.info).sorted(by: Self.byTitle) : []
    }

    private static func info(_ calendar: EKCalendar) -> CalendarInfo {
        let rgb = rgb(calendar.cgColor)
        return CalendarInfo(id: calendar.calendarIdentifier, title: calendar.title,
                            source: calendar.source?.title ?? "", red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    private static func byTitle(_ a: CalendarInfo, _ b: CalendarInfo) -> Bool {
        a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }

    private static func hiddenIDs(_ storage: String) -> Set<String> {
        Set(storage.split(separator: "\n").map(String.init))
    }

    /// The calendars the page shows (nil: all of them).
    private var visibleEventCalendars: [EKCalendar]? {
        let hidden = Self.hiddenIDs(CalendarSettings.shared.hiddenCalendars)
        guard !hidden.isEmpty else { return nil }
        return store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
    }

    private var visibleReminderLists: [EKCalendar]? {
        let hidden = Self.hiddenIDs(CalendarSettings.shared.hiddenLists)
        guard !hidden.isEmpty else { return nil }
        return store.calendars(for: .reminder).filter { !hidden.contains($0.calendarIdentifier) }
    }

    // MARK: Agenda

    private(set) var anchor = Calendar.current.startOfDay(for: Date())
    private var busyRange: (start: Date, end: Date)?
    /// Like `reloadGeneration`, for the grid's busy-day dots.
    private var busyGeneration = 0
    /// Bumped on every reload so a slow reminder fetch for an earlier day can't
    /// overwrite the agenda of the day picked since.
    private var reloadGeneration = 0

    /// Loads the agenda starting on `day` (a week of events plus open reminders).
    public func load(from day: Date) {
        anchor = Calendar.current.startOfDay(for: day)
        reload()
    }

    /// Marks days with events across the whole visible grid, which spans
    /// neighbouring months and is independent of the selected day's week.
    public func loadBusyDays(from start: Date, days: Int = 42) {
        let calendar = Calendar.current
        let first = calendar.startOfDay(for: start)
        let end = calendar.date(byAdding: .day, value: days, to: first) ?? first
        busyRange = (first, end)
        reloadBusyDays()
    }

    private func reloadBusyDays() {
        busyGeneration += 1
        let generation = busyGeneration
        guard hasEventAccess, let range = busyRange else {
            busyDays = []
            return
        }
        let (rangeStart, rangeEnd) = range
        fetchEvents(from: rangeStart, to: rangeEnd, map: { events in
            let calendar = Calendar.current
            var days: Set<DateComponents> = []
            for event in events {
                guard let start = event.startDate else { continue }
                // Multi-day events mark every day they cover inside the grid.
                var day = max(calendar.startOfDay(for: start), rangeStart)
                let last = min(event.endDate ?? start, rangeEnd)
                repeat {
                    days.insert(calendar.dateComponents([.year, .month, .day], from: day))
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    day = next
                } while day < last
            }
            return days
        }) { [weak self] days in
            guard let self, generation == self.busyGeneration else { return }
            self.busyDays = days
        }
    }

    // MARK: Fetching off the main thread

    /// `EKEventStore` isn't annotated Sendable, but Apple documents its
    /// synchronous fetches as fine (and better) off the main thread.
    struct StoreRef: @unchecked Sendable { let store: EKEventStore }

    /// Serial, so fetches come back to main in the order they were asked for.
    nonisolated static let fetchQueue = DispatchQueue(label: "app.tama.eventkit", qos: .userInitiated)

    /// Runs `work` against the store on `fetchQueue` — events(matching:) over
    /// a few weeks of busy calendars took long enough to hitch the shelf —
    /// then hands its value-type result back on main, in order.
    func onFetchQueue<T: Sendable>(_ work: @escaping @Sendable (EKEventStore) -> T,
                                   then completion: @escaping @MainActor @Sendable (T) -> Void) {
        let ref = StoreRef(store: store)
        Self.fetchQueue.async {
            let value = work(ref.store)
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(value) } }
        }
    }

    /// Events in the page's visible calendars (Settings' hidden ones left
    /// out), mapped by `map` on the fetch queue so no EKEvent crosses threads.
    private func fetchEvents<T: Sendable>(from start: Date, to end: Date,
                                          map: @escaping @Sendable ([EKEvent]) -> T,
                                          completion: @escaping @MainActor @Sendable (T) -> Void) {
        let hidden = Self.hiddenIDs(CalendarSettings.shared.hiddenCalendars)
        onFetchQueue({ store in
            var calendars: [EKCalendar]?
            if !hidden.isEmpty {
                let visible = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
                // Every calendar hidden: nothing to show (nil would mean all).
                guard !visible.isEmpty else { return map([]) }
                calendars = visible
            }
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
            return map(store.events(matching: predicate))
        }, then: completion)
    }

    private static func sorted(_ entries: [AgendaEntry]) -> [AgendaEntry] {
        entries.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }

    public func reload() {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 8, to: anchor) ?? anchor
        reloadBusyDays()

        reloadGeneration += 1
        let generation = reloadGeneration
        guard hasEventAccess, CalendarSettings.shared.showEvents else {
            applyEvents([], end: end, generation: generation)
            return
        }
        // The events come from the fetch queue; the reminders after them, as
        // before, so their callback finds this reload's events in `agenda`.
        fetchEvents(from: anchor, to: end, map: { events in
            events.filter { $0.status != .canceled }.map(Self.entry(for:))
        }) { [weak self] entries in
            guard let self, generation == self.reloadGeneration else { return }
            self.applyEvents(entries, end: end, generation: generation)
        }
    }

    private func applyEvents(_ entries: [AgendaEntry], end: Date, generation: Int) {
        // Keep the listed reminders until the fresh ones arrive, so the list
        // doesn't blink (or flash "No tasks or events") on every store change.
        let showTasks = hasReminderAccess && CalendarSettings.shared.showTasks
        let interim = showTasks ? agenda.filter { $0.kind == .reminder } : []
        agenda = Self.sorted(entries + interim)

        let lists = visibleReminderLists
        guard showTasks, lists?.isEmpty != true else {
            isLoading = false
            return
        }
        let hideUndated = CalendarSettings.shared.hideUndated
        // A bounded predicate drops reminders without a due date, so fetch every
        // open reminder and keep the undated ones plus those due before `end`.
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: lists)
        // EventKit calls back on its own queue: the closure must not be
        // main-actor isolated, or Swift 6 traps the moment access is granted.
        store.fetchReminders(matching: predicate) { @Sendable reminders in
            let rows = Self.agendaRows(from: reminders ?? [], dueBefore: end, hideUndated: hideUndated)
            Task { @MainActor [weak self] in
                guard let self, generation == self.reloadGeneration else { return }
                let events = self.agenda.filter { $0.kind == .event }
                let open = Set(rows.map(\.id))
                let done = self.completed.values.map(\.entry).filter { !open.contains($0.id) }
                self.agenda = Self.sorted(events + rows + done)
                self.isLoading = false
            }
        }
    }

    private nonisolated static func entry(for event: EKEvent) -> AgendaEntry {
        let rgb = rgb(event.calendar?.cgColor)
        return AgendaEntry(
            id: event.eventIdentifier ?? UUID().uuidString,
            kind: .event,
            title: event.title ?? "Event",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            red: rgb.0, green: rgb.1, blue: rgb.2,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            calendarTitle: event.calendar?.title ?? "",
            joinURL: MeetingService.joinURL(for: event)
        )
    }

    /// The next timed event that hasn't ended, within `days`, for the lock
    /// screen. Independent of the agenda, which follows the Calendar page.
    public func nextEvent(within days: Int = 7) -> AgendaEntry? {
        refreshAuthorization()
        guard hasEventAccess else { return nil }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: visibleEventCalendars)
        guard let event = store.events(matching: predicate)
            .filter({ !$0.isAllDay && ($0.endDate ?? .distantFuture) > now && $0.status != .canceled })
            .min(by: { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) })
        else { return nil }
        return Self.entry(for: event)
    }

    /// Timed events overlapping `now…now+window`, for the progress ring and
    /// next-event wing; fetched off the main thread, delivered on it.
    func timedEvents(from now: Date, window: TimeInterval,
                     completion: @escaping @MainActor @Sendable ([AgendaEntry]) -> Void) {
        guard hasEventAccess else { return completion([]) }
        fetchEvents(from: now.addingTimeInterval(-24 * 3600), to: now.addingTimeInterval(window), map: { events in
            events
                .filter { !$0.isAllDay && $0.status != .canceled && ($0.endDate ?? .distantPast) > now }
                .map(Self.entry(for:))
        }, completion: completion)
    }

    /// Open reminders due up to `end`, fetched off the main thread.
    func dueReminders(before end: Date, completion: @escaping @MainActor @Sendable ([AgendaEntry]) -> Void) {
        guard hasReminderAccess else { return completion([]) }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: Date().addingTimeInterval(-2 * 86_400),
                                                              ending: end, calendars: visibleReminderLists)
        store.fetchReminders(matching: predicate) { @Sendable reminders in
            let rows = Self.agendaRows(from: reminders ?? [], dueBefore: end, hideUndated: true, limit: 200)
            Task { @MainActor in completion(rows) }
        }
    }

    /// Open reminders due before `end` (or undated), as agenda rows.
    private nonisolated static func agendaRows(from reminders: [EKReminder], dueBefore end: Date,
                                               hideUndated: Bool, limit: Int = 40) -> [AgendaEntry] {
        let open = reminders
            .map { (reminder: $0, due: $0.dueDateComponents?.date) }
            .filter { $0.due.map { $0 < end } ?? !hideUndated }
            // EventKit returns them in no particular order; keep the most
            // pressing — soonest due first, undated last.
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            .map(\.reminder)
        return open.prefix(limit).map(reminderEntry)
    }

    private nonisolated static func reminderEntry(_ reminder: EKReminder) -> AgendaEntry {
        let rgb = rgb(reminder.calendar?.cgColor)
        return AgendaEntry(
            id: reminder.calendarItemIdentifier,
            kind: .reminder,
            title: reminder.title ?? "Reminder",
            start: reminder.dueDateComponents?.date,
            end: nil,
            isAllDay: reminder.dueDateComponents?.hour == nil,
            red: rgb.0, green: rgb.1, blue: rgb.2,
            priority: reminder.priority,
            calendarID: reminder.calendar?.calendarIdentifier ?? "",
            calendarTitle: reminder.calendar?.title ?? "",
            isCompleted: reminder.isCompleted
        )
    }

    // MARK: Adding

    public enum ReminderError: LocalizedError {
        case accessDenied
        case eventAccessDenied
        case noList
        case noCalendar
        case needsDate

        public var errorDescription: String? {
            switch self {
            case .accessDenied: "Tama can't use Reminders. Allow access in System Settings."
            case .eventAccessDenied: "Tama can't use Calendar. Allow access in System Settings."
            case .noList: "There's no Reminders list to add to."
            case .noCalendar: "There's no calendar to add to."
            case .needsDate: "Add a day or time for the event, like \u{201C}tomorrow 3pm\u{201D}."
            }
        }
    }

    /// The list a new task goes to: a `#List` mention, Settings' default, or the system's.
    private func list(named name: String?) -> EKCalendar? {
        let lists = store.calendars(for: .reminder).filter(\.allowsContentModifications)
        if let name {
            if let exact = lists.first(where: { $0.title.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                return exact
            }
            if let prefix = lists.first(where: { $0.title.range(of: name, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil }) {
                return prefix
            }
        }
        let preferred = CalendarSettings.shared.defaultList
        if !preferred.isEmpty, let list = lists.first(where: { $0.calendarIdentifier == preferred }) { return list }
        return store.defaultCalendarForNewReminders()
    }

    /// Natural-language entry: "Call mom tomorrow 5pm #Family !!" → a reminder
    /// due then, in Family, medium priority. Throws when access is missing or
    /// the save fails, so the caller can say so.
    public func addReminder(_ text: String) async throws {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if !hasReminderAccess, EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            let granted = (try? await store.requestFullAccessToReminders()) ?? false
            hasReminderAccess = granted
            isReminderAccessDenied = !granted
        }
        guard hasReminderAccess else {
            isReminderAccessDenied = true
            throw ReminderError.accessDenied
        }
        let draft = ReminderParser.parse(clean) ?? ReminderDraft(title: clean, due: nil)
        guard let list = list(named: draft.listName) else { throw ReminderError.noList }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.dueDateComponents = draft.due
        reminder.title = draft.title
        reminder.priority = draft.priority
        try store.save(reminder, commit: true)
        reload()
    }

    /// "Lunch with Sam Friday 1pm" → an hour-long event (all-day without a time)
    /// in Settings' default calendar.
    public func addEvent(_ text: String) async throws {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if !hasEventAccess, EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            hasEventAccess = (try? await store.requestFullAccessToEvents()) ?? false
        }
        guard hasEventAccess else { throw ReminderError.eventAccessDenied }
        guard let draft = ReminderParser.parse(clean), let due = draft.due, let start = due.date else {
            throw ReminderError.needsDate
        }
        let calendars = store.calendars(for: .event).filter(\.allowsContentModifications)
        let preferred = CalendarSettings.shared.defaultCalendar
        guard let calendar = calendars.first(where: { $0.calendarIdentifier == preferred })
                ?? draft.listName.flatMap({ name in calendars.first { $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame } })
                ?? store.defaultCalendarForNewEvents else { throw ReminderError.noCalendar }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = draft.title
        event.startDate = start
        if due.hour == nil {
            event.isAllDay = true
            event.endDate = start
        } else {
            event.endDate = start.addingTimeInterval(3600)
        }
        try store.save(event, span: .thisEvent, commit: true)
        reload()
    }

    // MARK: Editing reminders

    private func reminder(for entry: AgendaEntry) -> EKReminder? {
        guard entry.kind == .reminder else { return nil }
        return store.calendarItem(withIdentifier: entry.id) as? EKReminder
    }

    /// Returns false when the reminder couldn't be saved, so the row can come back.
    @discardableResult
    public func complete(_ entry: AgendaEntry) -> Bool {
        guard let reminder = reminder(for: entry) else { return false }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
        } catch {
            reminder.isCompleted = false
            return false
        }
        var done = entry
        done.isCompleted = true
        completed[entry.id] = (done, Date())
        if let index = agenda.firstIndex(where: { $0.id == entry.id }) { agenda[index] = done }
        scheduleCleanup()
        return true
    }

    /// Unticks a task still shown struck through.
    public func uncomplete(_ entry: AgendaEntry) {
        guard let reminder = reminder(for: entry) else { return }
        reminder.isCompleted = false
        guard (try? store.save(reminder, commit: true)) != nil else { return NSSound.beep() }
        completed[entry.id] = nil
        var open = entry
        open.isCompleted = false
        if let index = agenda.firstIndex(where: { $0.id == entry.id }) { agenda[index] = open }
    }

    /// Completed tasks leave after Settings' delay, in one sweep with one banner.
    private func scheduleCleanup() {
        guard cleanupTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            Task { @MainActor in CalendarService.shared.sweepCompleted() }
        }
        RunLoop.main.add(timer, forMode: .common)
        cleanupTimer = timer
    }

    private func sweepCompleted() {
        let delay = TimeInterval(max(CalendarSettings.shared.cleanupDelay, 0))
        let expired = completed.filter { Date().timeIntervalSince($0.value.at) >= delay }.map(\.key)
        if !expired.isEmpty {
            for id in expired { completed[id] = nil }
            withAnimation(DS.Motion.fluid) { agenda.removeAll { expired.contains($0.id) } }
            // A single task quietly goes; a batch says how many.
            if expired.count > 1 {
                AppState.shared.showNotification(appName: "Tasks", title: "\(expired.count) tasks cleaned up",
                                                 message: "Completed tasks are kept in Reminders.",
                                                 icon: "checkmark.circle.fill")
            }
        }
        if completed.isEmpty {
            cleanupTimer?.invalidate()
            cleanupTimer = nil
        }
    }

    public func setPriority(_ priority: TaskPriority, for entry: AgendaEntry) {
        guard let reminder = reminder(for: entry) else { return }
        reminder.priority = priority.rawValue
        save(reminder)
    }

    /// +1 day / +1 week; an undated task becomes due that far from today.
    public func postpone(_ entry: AgendaEntry, by component: Calendar.Component, value: Int = 1) {
        guard let reminder = reminder(for: entry) else { return }
        let calendar = Calendar.current
        let base = reminder.dueDateComponents?.date ?? calendar.startOfDay(for: Date())
        guard let moved = calendar.date(byAdding: component, value: value, to: base) else { return }
        let hasTime = reminder.dueDateComponents?.hour != nil
        var due = calendar.dateComponents(hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day], from: moved)
        due.calendar = calendar
        reminder.dueDateComponents = due
        // Alarms tied to the old date would fire at the wrong time.
        reminder.alarms?.filter { $0.absoluteDate != nil }.forEach { reminder.removeAlarm($0) }
        save(reminder)
    }

    public func removeDueDate(_ entry: AgendaEntry) {
        guard let reminder = reminder(for: entry) else { return }
        reminder.dueDateComponents = nil
        save(reminder)
    }

    /// Deletes a task behind an Undo banner, which recreates it.
    public func delete(_ entry: AgendaEntry) {
        guard let reminder = reminder(for: entry) else { return }
        let snapshot = (title: reminder.title ?? entry.title, due: reminder.dueDateComponents, priority: reminder.priority,
                        notes: reminder.notes, url: reminder.url, list: reminder.calendar?.calendarIdentifier)
        do {
            try store.remove(reminder, commit: true)
        } catch {
            NSSound.beep()
            return
        }
        completed[entry.id] = nil
        withAnimation(DS.Motion.fluid) { agenda.removeAll { $0.id == entry.id } }
        AppState.shared.showNotification(appName: "Tasks", title: "Task deleted", message: snapshot.title,
                                         icon: "trash.fill", actionTitle: "Undo") {
            let service = CalendarService.shared
            let restored = EKReminder(eventStore: service.store)
            restored.calendar = snapshot.list.flatMap { service.store.calendar(withIdentifier: $0) }
                ?? service.store.defaultCalendarForNewReminders()
            restored.title = snapshot.title
            restored.dueDateComponents = snapshot.due
            restored.priority = snapshot.priority
            restored.notes = snapshot.notes
            restored.url = snapshot.url
            do { try service.store.save(restored, commit: true) } catch { NSSound.beep() }
            service.reload()
        }
    }

    private func save(_ reminder: EKReminder) {
        do {
            try store.save(reminder, commit: true)
        } catch {
            NSSound.beep()
            AppState.shared.showNotification(appName: "Tasks", title: "Couldn't update the task",
                                             message: error.localizedDescription)
        }
        reload()
    }

    /// Opens an event (or the day) in Calendar.app.
    public func openInCalendar(_ entry: AgendaEntry) {
        if let start = entry.start {
            let seconds = Int(start.timeIntervalSinceReferenceDate)
            if let url = URL(string: "ical://ekevent/\(entry.id)?method=show&options=more"), entry.kind == .event,
               NSWorkspace.shared.open(url) { return }
            if let url = URL(string: "calshow:\(seconds)"), NSWorkspace.shared.open(url) { return }
        }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.kind == .event ? "com.apple.iCal" : "com.apple.reminders") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    nonisolated static func rgb(_ color: CGColor?) -> (Double, Double, Double) {
        guard let color,
              let converted = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let c = converted.components, c.count >= 3 else { return (1, 0.58, 0.0) }
        return (Double(c[0]), Double(c[1]), Double(c[2]))
    }
}
