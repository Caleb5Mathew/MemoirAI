//
//  StorybookProgressEstimatorTests.swift
//  MemoirAITests
//

import Foundation
import Testing
@testable import MemoirAI

struct StorybookProgressEstimatorTests {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeEstimator(pages: Int = 10) -> StorybookProgressEstimator {
        StorybookProgressEstimator(pageCountHint: pages, calibration: .default, now: t0)
    }

    @Test func progressIsMonotonicAcrossFullRun() {
        var e = makeEstimator()
        var last = 0.0
        var samples: [Double] = []

        func sample(_ now: Date) {
            let p = e.snapshot(now: now).progress
            samples.append(p)
            #expect(p >= last)
            last = p
        }

        sample(t0.addingTimeInterval(2))
        e.noteStatus("queued", completed: 0, total: 0, now: t0.addingTimeInterval(6))
        sample(t0.addingTimeInterval(8))
        e.noteStatus("ranking", completed: 0, total: 0, now: t0.addingTimeInterval(10))
        sample(t0.addingTimeInterval(15))
        e.noteStatus("running", completed: 0, total: 10, now: t0.addingTimeInterval(25))
        for i in 1...10 {
            let now = t0.addingTimeInterval(25 + Double(i) * 12)
            e.noteStatus("running", completed: i, total: 10, now: now)
            sample(now)
        }
        e.noteStatus("aiComplete", completed: 10, total: 10, now: t0.addingTimeInterval(150))
        sample(t0.addingTimeInterval(152))
        e.noteFinalizeStep(.persist, now: t0.addingTimeInterval(160))
        e.noteFinalizeStep(.coverAndPrint, now: t0.addingTimeInterval(165))
        sample(t0.addingTimeInterval(180))
        e.noteFinalizeStep(.installBook, now: t0.addingTimeInterval(200))
        sample(t0.addingTimeInterval(205))
        e.noteDone(now: t0.addingTimeInterval(210))
        let final = e.snapshot(now: t0.addingTimeInterval(210))
        #expect(final.progress == 1.0)
        #expect(final.etaSeconds == 0)
    }

    @Test func progressStaysBelowOneUntilDone() {
        var e = makeEstimator(pages: 3)
        e.noteStatus("running", completed: 3, total: 3, now: t0.addingTimeInterval(40))
        e.noteStatus("aiComplete", completed: 3, total: 3, now: t0.addingTimeInterval(41))
        e.noteFinalizeStep(.installBook, now: t0.addingTimeInterval(60))
        // Even hours into a stuck finalize, the bar must not claim completion.
        let p = e.snapshot(now: t0.addingTimeInterval(7200)).progress
        #expect(p < 1.0)
        #expect(p >= 0.9)
    }

    @Test func signallessPhaseKeepsMovingButNeverFinishesPhase() {
        var e = makeEstimator()
        e.noteStatus("ranking", completed: 0, total: 0, now: t0)
        let early = e.snapshot(now: t0.addingTimeInterval(3)).progress
        let mid = e.snapshot(now: t0.addingTimeInterval(20)).progress
        let late = e.snapshot(now: t0.addingTimeInterval(300)).progress
        #expect(early < mid)
        #expect(mid < late)
        // Ranking stalls forever → progress must stay inside the ranking span,
        // i.e. never reach where "running" would begin.
        var atRunning = makeEstimator()
        atRunning.noteStatus("running", completed: 0, total: 10, now: t0)
        let runningStart = atRunning.snapshot(now: t0).progress
        #expect(late <= runningStart + 0.05)
    }

    @Test func illustratingUsesRealCounts() {
        var lowE = makeEstimator()
        lowE.noteStatus("running", completed: 2, total: 10, now: t0)
        var highE = makeEstimator()
        highE.noteStatus("running", completed: 8, total: 10, now: t0)
        let low = lowE.snapshot(now: t0).progress
        let high = highE.snapshot(now: t0).progress
        #expect(high > low + 0.2)
    }

    @Test func etaAdaptsToObservedRate() {
        var e = makeEstimator()
        e.noteStatus("running", completed: 0, total: 10, now: t0)
        // Feed completions at a steady 20s per memory — slower than the 12s default.
        for i in 1...5 {
            e.noteStatus("running", completed: i, total: 10, now: t0.addingTimeInterval(Double(i) * 20))
        }
        let eta = e.snapshot(now: t0.addingTimeInterval(100)).etaSeconds ?? 0
        // 5 memories left at ~20s each plus finalize (60s default): well above the
        // 12s-per-memory naive estimate of ~120s total.
        #expect(eta > 120)
        #expect(eta < 400)
    }

    @Test func resumeMidRunStartsDeepIntoTheBar() {
        var e = makeEstimator()
        // App relaunches; first snapshot arrives with the run already 8/10 done and a
        // server-side runningStartedAt 100s ago.
        e.noteStatus(
            "running",
            completed: 8,
            total: 10,
            runningStartedAt: t0.addingTimeInterval(-100),
            now: t0
        )
        let p = e.snapshot(now: t0).progress
        #expect(p > 0.4)
    }

    @Test func etaDecreasesAsWorkCompletes() {
        var e = makeEstimator()
        e.noteStatus("running", completed: 1, total: 10, now: t0.addingTimeInterval(12))
        let etaEarly = e.snapshot(now: t0.addingTimeInterval(13)).etaSeconds ?? 0
        e.noteStatus("running", completed: 9, total: 10, now: t0.addingTimeInterval(110))
        let etaLate = e.snapshot(now: t0.addingTimeInterval(111)).etaSeconds ?? 0
        #expect(etaLate < etaEarly)
    }

    @Test func etaDisplayStringBuckets() {
        #expect(StorybookProgressEstimator.etaDisplayString(seconds: 5) == "Wrapping up…")
        #expect(StorybookProgressEstimator.etaDisplayString(seconds: 30) == "Less than a minute left")
        #expect(StorybookProgressEstimator.etaDisplayString(seconds: 70) == "About a minute left")
        #expect(StorybookProgressEstimator.etaDisplayString(seconds: 300) == "About 5 minutes left")
    }

    // MARK: - Calibration

    @Test func calibrationRoundTripsAndClamps() {
        let suite = "StorybookProgressEstimatorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(StorybookProgressEstimator.Calibration.load(defaults: defaults) == .default)

        StorybookProgressEstimator.Calibration.record(
            observedPerMemory: 20,
            observedRanking: 30,
            observedFinalize: 90,
            defaults: defaults
        )
        let updated = StorybookProgressEstimator.Calibration.load(defaults: defaults)
        // EMA α=0.3 pulls each value toward the observation without jumping to it.
        #expect(updated.perMemorySeconds > StorybookProgressEstimator.Calibration.default.perMemorySeconds)
        #expect(updated.perMemorySeconds < 20)
        #expect(updated.rankingSeconds > StorybookProgressEstimator.Calibration.default.rankingSeconds)
        #expect(updated.finalizeSeconds > StorybookProgressEstimator.Calibration.default.finalizeSeconds)

        // Absurd observations get clamped to sane bounds.
        for _ in 0..<50 {
            StorybookProgressEstimator.Calibration.record(
                observedPerMemory: 10_000,
                observedRanking: 10_000,
                observedFinalize: 10_000,
                defaults: defaults
            )
        }
        let clamped = StorybookProgressEstimator.Calibration.load(defaults: defaults)
        #expect(StorybookProgressEstimator.Calibration.perMemoryBounds.contains(clamped.perMemorySeconds))
        #expect(StorybookProgressEstimator.Calibration.rankingBounds.contains(clamped.rankingSeconds))
        #expect(StorybookProgressEstimator.Calibration.finalizeBounds.contains(clamped.finalizeSeconds))
    }
}
