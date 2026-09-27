import Foundation
import Testing
@testable import Droppy

@MainActor
@Suite struct JobCenterTests {
    final class Recorder {
        var banners: [(app: String, title: String, message: String)] = []
        var activities: [LiveActivity?] = []
    }

    private func makeCenter(_ r: Recorder) -> JobCenter {
        JobCenter(showBanner: { app, b in r.banners.append((app, b.title, b.message)) },
                  updateActivity: { r.activities.append($0) },
                  lingerAfterFinish: .milliseconds(10))
    }

    /// Runs a job and waits for its outcome.
    private func run<T: Sendable>(_ center: JobCenter, title: String = "job",
                                  _ op: @escaping @Sendable (JobProgress) async throws -> T,
                                  onStart: (UUID) -> Void = { _ in }) async -> JobCenter.Outcome {
        await withCheckedContinuation { cont in
            let id = center.run(title: title, appName: "Test", operation: op,
                                onSuccess: { _ in JobCenter.Banner(title: "Done", message: title) },
                                onFinish: { cont.resume(returning: $0) })
            onStart(id)
        }
    }

    @Test func successShowsBannerAndEndsActivity() async {
        let r = Recorder()
        let center = makeCenter(r)
        let outcome = await run(center) { progress in
            progress(0.5)
            try await Task.sleep(for: .milliseconds(50))
            return 42
        }
        #expect(outcome == .succeeded)
        #expect(r.banners.map(\.title) == ["Done"])
        #expect(center.jobs.first?.state == .finished(.succeeded))
        #expect(center.jobs.first?.progress == 1)
        #expect(center.runningJobs.isEmpty)
        // Posted while running, ended once nothing runs.
        #expect(r.activities.first??.id == JobCenter.activityID)
        #expect(r.activities.contains { $0?.trailing == .progress(0.5) })
        #expect(r.activities.last! == nil)
    }

    @Test func failureBannerCarriesReason() async {
        let r = Recorder()
        let outcome = await run(makeCenter(r)) { _ -> Int in throw FileConverter.ConversionError("Disk full") }
        #expect(outcome == .failed("Disk full"))
        #expect(r.banners.count == 1)
        #expect(r.banners[0].title == "Conversion Failed" && r.banners[0].message == "Disk full")
        #expect(r.banners[0].app == "Test")
    }

    @Test func cancelStopsCooperativeWork() async {
        let r = Recorder()
        let center = makeCenter(r)
        let outcome = await run(center, title: "long") { progress in
            for i in 0..<1000 {
                try Task.checkCancellation()
                progress(Double(i) / 1000)
                try await Task.sleep(for: .milliseconds(10))
            }
            return 0
        } onStart: { id in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                center.cancel(id)
            }
        }
        #expect(outcome == .cancelled)
        #expect(r.banners.map(\.title) == ["Cancelled"])
        #expect(center.runningJobs.isEmpty)
    }

    @Test func finishedJobsAreForgottenAfterLinger() async throws {
        let center = makeCenter(Recorder())
        _ = await run(center) { _ in 1 }
        #expect(center.jobs.count == 1)
        try await Task.sleep(for: .milliseconds(200))
        #expect(center.jobs.isEmpty)
    }

    @Test func aggregateProgressAveragesKnownRunningJobs() {
        func job(_ p: Double?, _ state: JobCenter.State = .running) -> JobCenter.Job {
            JobCenter.Job(id: UUID(), title: "", appName: "", progress: p, state: state)
        }
        #expect(JobCenter.aggregateProgress([]) == nil)
        #expect(JobCenter.aggregateProgress([job(nil)]) == nil)
        #expect(JobCenter.aggregateProgress([job(0.2), job(0.6), job(nil)]) == 0.4)
        #expect(JobCenter.aggregateProgress([job(0.5), job(1, .finished(.succeeded))]) == 0.5)
    }
}
