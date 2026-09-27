import SwiftUI

/// Something happening right now that earns a place in the resting notch's
/// wings: a meeting about to start, a timer, a download, a charger plugged in.
/// Services publish these; the notch shows the one that matters most.
public struct LiveActivity: Identifiable, Equatable {
    public enum Priority: Int, Comparable, Sendable {
        /// Below music and the Tray: downloads, a running timer.
        case ambient = 0
        /// Above music: a meeting starting, a charger just plugged in.
        case urgent = 1
        public static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
    }

    public enum Trailing: Equatable {
        case text(String)
        /// 0…1, drawn as a small ring.
        case progress(Double)
        /// The live microphone level as bars (Meetings' call HUD); flat and red when muted.
        case micLevel(muted: Bool)
        /// An indeterminate ring (a coding agent at work).
        case spinner
        case none
    }

    /// Words beside the icon in the left wing.
    public enum Detail: Equatable {
        case none
        /// A clock counting up from this moment ("0:12").
        case elapsed(since: Date)
        case text(String)
    }

    public let id: String
    public var icon: String
    public var tint: Color
    public var trailing: Trailing
    public var priority: Priority
    /// Shown as the island's tooltip and read by VoiceOver.
    public var label: String
    public var expiresAt: Date?
    public var detail: Detail

    public init(id: String, icon: String, tint: Color, trailing: Trailing, priority: Priority,
                label: String, expiresAt: Date? = nil, detail: Detail = .none) {
        self.id = id
        self.icon = icon
        self.tint = tint
        self.trailing = trailing
        self.priority = priority
        self.label = label
        self.expiresAt = expiresAt
        self.detail = detail
    }

    /// Needs the wider resting wings (`DroppyShelfMetrics.activityWing`).
    public var isWide: Bool {
        if detail != .none { return true }
        if case .micLevel = trailing { return true }
        return false
    }
}

@MainActor
public final class LiveActivityCenter: ObservableObject {
    public static let shared = LiveActivityCenter()

    @Published public private(set) var activities: [LiveActivity] = []
    private var expiryTimers: [String: DispatchWorkItem] = [:]

    /// Activities meant to last at most this long follow the linger setting.
    private static let briefActivity: TimeInterval = 6

    private init() {}

    /// Adds or replaces the activity with the same id. A brief one (gone
    /// within a few seconds: a charger, a device, Caps Lock) stays for
    /// Settings › HUDs › Finished HUD linger instead of its own time.
    public func post(_ activity: LiveActivity) {
        var activity = activity
        if let expiresAt = activity.expiresAt {
            let duration = expiresAt.timeIntervalSinceNow
            if duration > 0, duration <= Self.briefActivity {
                activity.expiresAt = Date().addingTimeInterval(min(max(AppState.shared.finishedHUDLinger, 1), 10))
            }
        }
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            guard activities[index] != activity else { return }
            activities[index] = activity
        } else {
            withAnimation(DS.Motion.fluid) { activities.append(activity) }
        }
        expiryTimers[activity.id]?.cancel()
        expiryTimers[activity.id] = nil
        if let expiresAt = activity.expiresAt {
            let work = DispatchWorkItem { [weak self] in self?.end(activity.id) }
            expiryTimers[activity.id] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + max(expiresAt.timeIntervalSinceNow, 0), execute: work)
        }
    }

    public func end(_ id: String) {
        expiryTimers[id]?.cancel()
        expiryTimers[id] = nil
        guard activities.contains(where: { $0.id == id }) else { return }
        withAnimation(DS.Motion.fluid) { activities.removeAll { $0.id == id } }
    }

    /// The highest-priority activity at `priority`, newest first among equals.
    public func top(_ priority: LiveActivity.Priority) -> LiveActivity? {
        activities.last { $0.priority == priority }
    }
}

/// The wing pair for a live activity: icon on the left, text or a progress
/// ring on the right.
@MainActor
struct LiveActivityWings {
    let activity: LiveActivity

    var leading: some View {
        HStack(spacing: 5) {
            Image(systemName: activity.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(activity.tint)
                .contentTransition(.symbolEffect(.replace))
            switch activity.detail {
            case .none:
                EmptyView()
            case let .elapsed(since):
                Text(since, style: .timer)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(activity.tint)
                    .lineLimit(1)
                    .fixedSize()
            case let .text(text):
                Text(text)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(activity.tint)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    @ViewBuilder
    var trailing: some View {
        switch activity.trailing {
        case let .text(text):
            Text(text)
                .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                .foregroundStyle(activity.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        case let .progress(value):
            ZStack {
                Circle().stroke(Color.white.opacity(0.18), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: min(max(value, 0.02), 1))
                    .stroke(activity.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 14, height: 14)
            .animation(DS.Motion.fluid, value: value)
        case let .micLevel(muted):
            MicLevelBars(tint: muted ? DS.Palette.danger : activity.tint, isMuted: muted)
        case .spinner:
            ActivitySpinner(tint: activity.tint)
        case .none:
            Circle().fill(activity.tint).frame(width: 6, height: 6)
        }
    }
}

/// A small ring that turns forever: something is working.
struct ActivitySpinner: View {
    var tint: Color
    var size: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let turns = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1
            ZStack {
                Circle().stroke(tint.opacity(0.2), lineWidth: 2.2)
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(reduceMotion ? 0 : turns * 360))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Working")
    }
}

/// The call HUD's microphone meter: thin bars that follow the input level,
/// tallest in the middle like the reference's waveform.
struct MicLevelBars: View {
    var tint: Color
    var isMuted: Bool
    var bars = 9
    var height: CGFloat = 12
    @ObservedObject private var meter = MicLevelMeter.shared

    var body: some View {
        HStack(alignment: .center, spacing: 1.6) {
            ForEach(0..<bars, id: \.self) { index in
                let shape = 1 - abs(Double(index) - Double(bars - 1) / 2) / Double(bars) * 1.1
                let level = isMuted ? 0 : meter.level(bar: index, of: bars)
                Capsule()
                    .fill(tint.opacity(index % 2 == 0 ? 1 : 0.75))
                    .frame(width: 1.8, height: max(2.5, height * CGFloat(shape) * CGFloat(0.25 + 0.75 * level)))
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 0.08), value: meter.tick)
        .accessibilityLabel(isMuted ? "Microphone muted" : "Microphone level")
    }
}
