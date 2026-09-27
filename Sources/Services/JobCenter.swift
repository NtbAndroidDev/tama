import SwiftUI

/// Hands progress from a background job back to its `JobCenter` entry.
/// Safe to call from any thread; updates are coalesced on the main actor.
public final class JobProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: Double?
    private var scheduled = false
    private let apply: @MainActor (Double) -> Void

    init(apply: @escaping @MainActor (Double) -> Void) { self.apply = apply }

    public func report(_ fraction: Double) {
        let value = min(max(fraction, 0), 1)
        lock.lock()
        pending = value
        let needsHop = !scheduled
        scheduled = true
        lock.unlock()
        guard needsHop else { return }
        // One main-actor hop per burst: a PDF with 100 pages or a busy export
        // poller must not flood the main queue.
        Task { @MainActor in
            if let latest = self.takePending() { self.apply(latest) }
        }
    }

    private func takePending() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        let latest = pending
        pending = nil
        scheduled = false
        return latest
    }

    public func callAsFunction(_ fraction: Double) { report(fraction) }
}

/// Long-running work (conversions) that must outlive the view that started it:
/// the shelf can collapse mid-job and the resting notch still shows progress.
@MainActor
public final class JobCenter: ObservableObject {
    public static let shared = JobCenter()

    public enum Outcome: Equatable, Sendable {
        case succeeded
        case failed(String)
        case cancelled
    }

    public enum State: Equatable, Sendable {
        case running
        case finished(Outcome)
    }

    public struct Job: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let appName: String
        /// nil while the work can't say how far along it is.
        public var progress: Double?
        public var state: State

        public var isRunning: Bool { state == .running }
    }

    public struct Banner {
        public var title: String
        public var message: String
        public var actionTitle: String?
        public var action: (@MainActor @Sendable () -> Void)?

        public init(title: String, message: String, actionTitle: String? = nil,
                    action: (@MainActor @Sendable () -> Void)? = nil) {
            self.title = title
            self.message = message
            self.actionTitle = actionTitle
            self.action = action
        }
    }

    /// Running jobs plus recently finished ones, oldest first.
    @Published public private(set) var jobs: [Job] = []

    public var runningJobs: [Job] { jobs.filter(\.isRunning) }

    private var tasks: [UUID: Task<Void, Never>] = [:]

    // Seams for tests, which must not spin up AppState or the notch.
    private let showBanner: @MainActor (_ appName: String, Banner) -> Void
    private let updateActivity: @MainActor (LiveActivity?) -> Void
    private let lingerAfterFinish: Duration

    static let activityID = "jobs"

    init(showBanner: @escaping @MainActor (_ appName: String, Banner) -> Void = JobCenter.appBanner,
         updateActivity: @escaping @MainActor (LiveActivity?) -> Void = JobCenter.notchActivity,
         lingerAfterFinish: Duration = .seconds(3)) {
        self.showBanner = showBanner
        self.updateActivity = updateActivity
        self.lingerAfterFinish = lingerAfterFinish
    }

    private static func appBanner(_ appName: String, _ banner: Banner) {
        AppState.shared.showNotification(appName: appName, title: banner.title, message: banner.message,
                                         actionTitle: banner.actionTitle, action: banner.action)
    }

    private static func notchActivity(_ activity: LiveActivity?) {
        if let activity {
            LiveActivityCenter.shared.post(activity)
        } else {
            LiveActivityCenter.shared.end(activityID)
        }
    }

    /// Starts `operation` as a job. `onSuccess` consumes the result and may
    /// return a banner; failures and cancels get a banner of their own.
    @discardableResult
    public func run<T: Sendable>(
        title: String,
        appName: String = "Convert",
        failureTitle: String = "Conversion Failed",
        operation: @escaping @Sendable (JobProgress) async throws -> T,
        onSuccess: @escaping @MainActor (T) -> Banner?,
        onFinish: (@MainActor (Outcome) -> Void)? = nil
    ) -> UUID {
        let id = UUID()
        jobs.append(Job(id: id, title: title, appName: appName, progress: nil, state: .running))
        let progress = JobProgress { [weak self] value in self?.setProgress(id, value) }
        refreshActivity()

        tasks[id] = Task { [weak self] in
            let outcome: Outcome
            var banner: Banner?
            do {
                let value = try await operation(progress)
                banner = onSuccess(value)
                outcome = .succeeded
            } catch is CancellationError {
                outcome = .cancelled
            } catch {
                outcome = Task.isCancelled ? .cancelled : .failed(error.localizedDescription)
            }
            self?.finish(id, outcome: outcome, banner: banner, failureTitle: failureTitle, onFinish: onFinish)
        }
        return id
    }

    public func cancel(_ id: UUID) {
        tasks[id]?.cancel()
    }

    public func cancelAll() {
        tasks.values.forEach { $0.cancel() }
    }

    func setProgress(_ id: UUID, _ value: Double) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].isRunning else { return }
        // Skip sub-percent changes; each publish redraws the notch.
        if let old = jobs[index].progress, abs(old - value) < 0.01, value < 1 { return }
        jobs[index].progress = value
        refreshActivity()
    }

    private func finish(_ id: UUID, outcome: Outcome, banner: Banner?, failureTitle: String,
                        onFinish: (@MainActor (Outcome) -> Void)?) {
        tasks[id] = nil
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        let job = jobs[index]
        jobs[index].state = .finished(outcome)
        if outcome == .succeeded { jobs[index].progress = 1 }
        refreshActivity()

        switch outcome {
        case .succeeded:
            if let banner { showBanner(job.appName, banner) }
        case let .failed(reason):
            showBanner(job.appName, Banner(title: failureTitle, message: reason))
        case .cancelled:
            showBanner(job.appName, Banner(title: "Cancelled", message: job.title))
        }
        onFinish?(outcome)

        let linger = lingerAfterFinish
        Task { [weak self] in
            try? await Task.sleep(for: linger)
            self?.jobs.removeAll { $0.id == id }
        }
    }

    /// Mean of the known fractions; nil when no running job reports one.
    nonisolated static func aggregateProgress(_ jobs: [Job]) -> Double? {
        let known = jobs.filter(\.isRunning).compactMap(\.progress)
        guard !known.isEmpty else { return nil }
        return known.reduce(0, +) / Double(known.count)
    }

    private func refreshActivity() {
        let running = runningJobs
        guard !running.isEmpty else { return updateActivity(nil) }
        let overall = Self.aggregateProgress(running)
        let percent = overall.map { " · \(Int(($0 * 100).rounded()))%" } ?? ""
        let what = running.count == 1 ? running[0].title : "\(running.count) jobs"
        updateActivity(LiveActivity(
            id: Self.activityID,
            icon: "arrow.triangle.2.circlepath",
            tint: DS.accent,
            trailing: overall.map { .progress($0) } ?? .none,
            priority: .ambient,
            label: "Converting \(what)\(percent)"
        ))
    }
}

/// A running job with a bar and a cancel button, for the convert surfaces.
struct JobRow: View {
    let job: JobCenter.Job
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(job.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let progress = job.progress {
                    ProgressView(value: progress).progressViewStyle(.linear).tint(DS.accent)
                } else {
                    ProgressView().progressViewStyle(.linear).tint(DS.accent)
                }
            }
            if job.isRunning {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel")
                .accessibilityLabel("Cancel \(job.title)")
            }
        }
    }
}
