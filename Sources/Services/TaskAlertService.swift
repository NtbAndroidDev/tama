import AppKit
import EventKit

/// Tasks & Calendar in the resting notch: due-task alerts (a heads-up before,
/// a banner and optional chime at the due time), a progress ring for the
/// event under way, and optionally the next event or task in the wings.
@MainActor
public final class TaskAlertService {
    public static let shared = TaskAlertService()

    private var timer: Timer?
    /// Reminder id + due time, so a rescheduled task alerts again.
    private var headsUpSent: Set<String> = []
    private var dueSent: Set<String> = []
    private var started = false

    private init() {}

    public func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: CalendarService.shared.store,
                                               queue: .main) { _ in
            MainActor.assumeIsolated { TaskAlertService.shared.tick() }
        }
        let timer = Timer(timeInterval: 20, repeats: true) { _ in
            Task { @MainActor in
                // Caught up by PowerStateService on wake.
                guard !PowerStateService.shared.isDormant else { return }
                TaskAlertService.shared.tick()
            }
        }
        timer.tolerance = 4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func tick() {
        guard started else { return }
        let now = Date()
        // The events are fetched off the main thread (every 20 s); the rest
        // of the tick runs back on main with them.
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            handle(events: [], now: now)
            return
        }
        CalendarService.shared.timedEvents(from: now, window: 12 * 3600) { events in
            TaskAlertService.shared.handle(events: events, now: now)
        }
    }

    private func handle(events: [AgendaEntry], now: Date) {
        guard started else { return }
        let calendar = CalendarService.shared

        // Event under way: a ring filling as it runs; otherwise the next one.
        let current = events.filter { ($0.start ?? .distantFuture) <= now }
            .min { ($0.end ?? .distantFuture) < ($1.end ?? .distantFuture) }
        if CalendarSettings.shared.eventRing, let current, let start = current.start, let end = current.end, end > start {
            let fraction = now.timeIntervalSince(start) / end.timeIntervalSince(start)
            let left = Int((end.timeIntervalSince(now) / 60).rounded(.up))
            LiveActivityCenter.shared.post(LiveActivity(
                id: "eventProgress", icon: current.joinURL == nil ? "calendar" : "video.fill", tint: current.color,
                trailing: .progress(fraction), priority: .ambient,
                label: "\(current.title) · \(left) min left"
            ))
        } else {
            LiveActivityCenter.shared.end("eventProgress")
        }

        if CalendarSettings.shared.nextEventWing, current == nil || !CalendarSettings.shared.eventRing,
           let next = events.filter({ ($0.start ?? .distantPast) > now }).min(by: { $0.start! < $1.start! }),
           let start = next.start {
            LiveActivityCenter.shared.post(LiveActivity(
                id: "nextEvent", icon: "calendar", tint: next.color,
                trailing: .text(start.formatted(date: .omitted, time: .shortened)), priority: .ambient,
                label: "Next: \(next.title) at \(start.formatted(date: .omitted, time: .shortened))"
            ))
        } else if !CalendarSettings.shared.nextEventWing || current != nil {
            LiveActivityCenter.shared.end("nextEvent")
        }

        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            LiveActivityCenter.shared.end("taskDue")
            return
        }
        let lead = TimeInterval(max(CalendarSettings.shared.headsUpMinutes, 0) * 60)
        let wantsAlerts = CalendarSettings.shared.dueAlerts
        let wantsNextTask = CalendarSettings.shared.nextEventWing && events.isEmpty
        guard wantsAlerts || wantsNextTask else {
            LiveActivityCenter.shared.end("taskDue")
            return
        }
        calendar.dueReminders(before: now.addingTimeInterval(max(lead, 12 * 3600))) { reminders in
            TaskAlertService.shared.handle(reminders, lead: lead, alerts: wantsAlerts, nextTask: wantsNextTask)
        }
    }

    private func handle(_ reminders: [AgendaEntry], lead: TimeInterval, alerts: Bool, nextTask: Bool) {
        let now = Date()
        // Only timed tasks alert: an all-day one has no moment to be due at.
        let timed = reminders.filter { !$0.isAllDay && $0.start != nil }

        if nextTask, let next = timed.filter({ $0.start! > now }).min(by: { $0.start! < $1.start! }) {
            LiveActivityCenter.shared.post(LiveActivity(
                id: "nextEvent", icon: "checklist", tint: next.color,
                trailing: .text(next.start!.formatted(date: .omitted, time: .shortened)), priority: .ambient,
                label: "Next task: \(next.title)"
            ))
        }
        guard alerts else { return }

        var soon: AgendaEntry?
        for task in timed {
            guard let due = task.start else { continue }
            let key = task.id + "@\(Int(due.timeIntervalSince1970))"
            let until = due.timeIntervalSince(now)
            if until <= 0 {
                // Due now (or in the last few minutes, e.g. the Mac just woke).
                guard until > -300, !dueSent.contains(key) else { continue }
                dueSent.insert(key)
                announceDue(task)
            } else if lead > 0, until <= lead {
                if soon.map({ due < $0.start! }) ?? true { soon = task }
                guard !headsUpSent.contains(key) else { continue }
                headsUpSent.insert(key)
                let minutes = Int((until / 60).rounded(.up))
                AppState.shared.showNotification(appName: "Tasks", title: task.title,
                                                 message: "Due in \(minutes) min", icon: "checklist")
            }
        }
        if let soon, let due = soon.start {
            let minutes = Int((due.timeIntervalSince(now) / 60).rounded(.up))
            LiveActivityCenter.shared.post(LiveActivity(
                id: "taskDue", icon: "checklist", tint: DS.Palette.warning, trailing: .text("\(minutes)m"),
                priority: .urgent, label: "\(soon.title) is due in \(minutes) min", expiresAt: due.addingTimeInterval(60)
            ))
        } else if !dueSent.isEmpty, LiveActivityCenter.shared.activities.contains(where: { $0.id == "taskDue" }) {
            // Leave a just-posted "due" activity to expire on its own.
        } else {
            LiveActivityCenter.shared.end("taskDue")
        }
    }

    private func announceDue(_ task: AgendaEntry) {
        let state = AppState.shared
        LiveActivityCenter.shared.post(LiveActivity(
            id: "taskDue", icon: "checklist", tint: DS.Palette.warning, trailing: .text("now"),
            priority: .urgent, label: "\(task.title) is due", expiresAt: Date().addingTimeInterval(20)
        ))
        state.showNotification(appName: "Tasks", title: task.title, message: "Due now", icon: "checklist",
                               actionTitle: "Complete", action: { CalendarService.shared.complete(task) }, duration: 8)
        if CalendarSettings.shared.dueChime { NSSound(named: "Glass")?.play() }
    }
}
