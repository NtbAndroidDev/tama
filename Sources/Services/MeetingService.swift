import AppKit
import EventKit

/// Watches the calendar for the next meeting: counts it down in the notch for
/// the last ten minutes and offers a Join button (Zoom, Meet, Teams, Webex)
/// when it starts. Reads the calendar only if access was already granted.
@MainActor
public final class MeetingService {
    public static let shared = MeetingService()

    /// How long before the start the countdown shows.
    private let lead: TimeInterval = 10 * 60
    /// The Calendar page's store: one EKEventStore is enough for the app,
    /// and its change notifications cover both.
    private var store: EKEventStore { CalendarService.shared.store }
    private var timer: Timer?
    private var announced: Set<String> = []
    private var storeObserver: NSObjectProtocol?

    /// What `tick` needs of the next meeting, read on EventKit's queue so no
    /// EKEvent crosses back to main.
    private struct Upcoming: Sendable {
        let id: String
        let start: Date
        let title: String?
        let joinURL: URL?
    }

    private init() {}

    public func start() {
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { _ in
            MainActor.assumeIsolated { MeetingService.shared.tick() }
        }
        let timer = Timer(timeInterval: 20, repeats: true) { _ in
            Task { @MainActor in
                // Caught up by PowerStateService on wake.
                guard !PowerStateService.shared.isDormant else { return }
                MeetingService.shared.tick()
            }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    /// Also called when the setting flips, so the countdown comes and goes at once.
    func tick() {
        let center = LiveActivityCenter.shared
        guard AppState.shared.showMeetingCountdown,
              EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            center.end("meeting")
            return
        }
        let now = Date()
        let lead = self.lead
        // The fetch runs every 20 s: off main, on the calendar's fetch queue.
        CalendarService.shared.onFetchQueue({ store in
            let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-60), end: now.addingTimeInterval(lead), calendars: nil)
            return store.events(matching: predicate)
                .filter { !$0.isAllDay && $0.startDate >= now.addingTimeInterval(-60) && $0.status != .canceled && !Self.isDeclined($0) }
                .min { $0.startDate < $1.startDate }
                .map { Upcoming(id: $0.calendarItemIdentifier, start: $0.startDate, title: $0.title,
                                joinURL: Self.joinURL(for: $0)) }
        }, then: { next in
            MeetingService.shared.show(next, now: now)
        })
    }

    private func show(_ next: Upcoming?, now: Date) {
        let center = LiveActivityCenter.shared
        // The setting may have been switched off while the fetch ran.
        guard AppState.shared.showMeetingCountdown, let event = next else {
            center.end("meeting")
            return
        }
        let remaining = event.start.timeIntervalSince(now)
        let title = event.title ?? "Meeting"
        let minutes = Int((remaining / 60).rounded(.up))
        center.post(LiveActivity(
            id: "meeting",
            icon: event.joinURL == nil ? "calendar" : "video.fill",
            tint: remaining <= 60 ? DS.Palette.warning : .white,
            trailing: .text(remaining <= 60 ? "now" : "\(minutes)m"),
            priority: .urgent,
            label: "\(title) \(remaining <= 60 ? "is starting" : "in \(minutes) min")",
            expiresAt: event.start.addingTimeInterval(90)
        ))

        let key = event.id + "\(event.start.timeIntervalSince1970)"
        if remaining <= 60, !announced.contains(key) {
            announced.insert(key)
            announce(event, title: title)
        }
    }

    private func announce(_ event: Upcoming, title: String) {
        let url = event.joinURL
        var join: (@MainActor @Sendable () -> Void)?
        if let url { join = { NSWorkspace.shared.open(url) } }
        let time = event.start.formatted(date: .omitted, time: .shortened)
        AppState.shared.showNotification(
            appName: "Calendar",
            title: title,
            message: url == nil ? "Starts at \(time)" : "Starts at \(time) · \(url?.host ?? "")",
            actionTitle: url == nil ? nil : "Join",
            action: join
        )
        if AppState.shared.soundEffects { NSSound(named: "Purr")?.play() }
    }

    private nonisolated static func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
    }

    /// The video-call link in the event's URL, location or notes.
    nonisolated static func joinURL(for event: EKEvent) -> URL? {
        let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "whereby.com", "meet.jit.si", "facetime.apple.com"]
        func isMeeting(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return false }
            return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
        if let url = event.url, isMeeting(url) { return url }
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        guard !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap(\.url)
            .first(where: isMeeting)
    }
}
