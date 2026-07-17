//
//  StorybookProgressEstimator.swift
//  MemoirAI
//
//  Single source of truth for the storybook generation progress bar and time estimate.
//
//  The pipeline has phases with very different signals:
//    kickoff  (client photo upload + memory sync — no progress signal)
//    queued   (waiting for the cloud worker to pick the job up)
//    ranking  (server one-shot LLM ranking — no progress signal)
//    illustrating (server, real completedMemoryCount/totalMemories from Firestore)
//    finalizing   (client: rebuild pages, persist, AI cover + print PDF, install)
//
//  The bar allocates its span to phases proportional to their expected duration,
//  uses real counts where they exist, and eases on elapsed time where they don't —
//  so it never freezes and never reaches 100% early. Expected durations are
//  calibrated from the user's previous successful runs.
//

import Foundation

struct StorybookProgressEstimator {

    enum Phase: Int, Comparable {
        case kickoff
        case queued
        case ranking
        case illustrating
        case finalizing
        case done

        static func < (lhs: Phase, rhs: Phase) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Client-side finalize sub-steps, in execution order (see `runFinalizeAfterCloudAI`).
    enum FinalizeStep: Int, CaseIterable, Comparable {
        case rebuildPages   // download illustrations, paginate text
        case persist        // Core Data + Firestore book version write
        case coverAndPrint  // AI cover art, print PDF render/upload, readiness polls
        case installBook    // final book version record fetch

        static func < (lhs: FinalizeStep, rhs: FinalizeStep) -> Bool { lhs.rawValue < rhs.rawValue }

        /// Share of the finalize phase, by typical duration. Must sum to 1.
        var weight: Double {
            switch self {
            case .rebuildPages: return 0.20
            case .persist: return 0.06
            case .coverAndPrint: return 0.62
            case .installBook: return 0.12
            }
        }
    }

    // MARK: - Calibration

    /// Expected durations learned from this user's previous successful generations.
    struct Calibration: Equatable {
        /// Wall-clock seconds per completed memory during `illustrating` (the cloud worker
        /// runs up to 3 images concurrently, so this is well below a single image's latency).
        var perMemorySeconds: Double
        var rankingSeconds: Double
        var finalizeSeconds: Double

        static let `default` = Calibration(perMemorySeconds: 12, rankingSeconds: 15, finalizeSeconds: 60)

        static let perMemoryBounds = 4.0...60.0
        static let rankingBounds = 5.0...90.0
        static let finalizeBounds = 20.0...240.0

        private static let key = "memoirai.storybookTimingCalibration"

        static func load(defaults: UserDefaults = .standard) -> Calibration {
            guard let dict = defaults.dictionary(forKey: key) else { return .default }
            return Calibration(
                perMemorySeconds: (dict["perMemory"] as? Double).map { perMemoryBounds.clamp($0) } ?? Calibration.default.perMemorySeconds,
                rankingSeconds: (dict["ranking"] as? Double).map { rankingBounds.clamp($0) } ?? Calibration.default.rankingSeconds,
                finalizeSeconds: (dict["finalize"] as? Double).map { finalizeBounds.clamp($0) } ?? Calibration.default.finalizeSeconds
            )
        }

        /// Blends a completed run's observed timings into the stored values (EMA, α = 0.3)
        /// so estimates track the user's real network and server speeds over time.
        static func record(
            observedPerMemory: Double?,
            observedRanking: Double?,
            observedFinalize: Double?,
            defaults: UserDefaults = .standard
        ) {
            var current = load(defaults: defaults)
            if let v = observedPerMemory {
                current.perMemorySeconds = perMemoryBounds.clamp(current.perMemorySeconds * 0.7 + v * 0.3)
            }
            if let v = observedRanking {
                current.rankingSeconds = rankingBounds.clamp(current.rankingSeconds * 0.7 + v * 0.3)
            }
            if let v = observedFinalize {
                current.finalizeSeconds = finalizeBounds.clamp(current.finalizeSeconds * 0.7 + v * 0.3)
            }
            defaults.set(
                [
                    "perMemory": current.perMemorySeconds,
                    "ranking": current.rankingSeconds,
                    "finalize": current.finalizeSeconds
                ],
                forKey: key
            )
        }
    }

    // MARK: - State

    private(set) var phase: Phase = .kickoff
    private let calibration: Calibration
    /// Expected number of illustrated memories until the server reports the real total.
    private var pageCountHint: Int

    private var phaseStartedAt: Date

    // Illustrating signals
    private var completedMemories = 0
    private var totalMemories = 0
    private var lastCompletionAt: Date?
    /// EMA of observed wall-clock seconds per completed memory this run.
    private var observedPerMemorySeconds: Double?

    // Ranking observation (for calibration)
    private var rankingStartedAt: Date?
    private var observedRankingSeconds: Double?

    // Finalizing signals
    private var finalizeStep: FinalizeStep = .rebuildPages
    private var finalizeStartedAt: Date?

    /// Monotonic clamp: the bar never moves backwards.
    private var displayedProgress: Double = 0

    init(pageCountHint: Int, calibration: Calibration = .load(), now: Date = Date()) {
        self.pageCountHint = max(1, pageCountHint)
        self.calibration = calibration
        self.phaseStartedAt = now
    }

    // MARK: - Inputs

    /// Feed every Firestore job snapshot here. `runningStartedAt` (server timestamp) makes
    /// rate estimates accurate when re-attaching to a job that ran while the app was closed.
    mutating func noteStatus(
        _ status: String,
        completed: Int,
        total: Int,
        runningStartedAt: Date? = nil,
        now: Date = Date()
    ) {
        if total > 0 {
            totalMemories = total
            pageCountHint = total
        }

        switch status {
        case "queued":
            advance(to: .queued, now: now)
        case "ranking":
            advance(to: .ranking, now: now)
            if rankingStartedAt == nil { rankingStartedAt = now }
        case "running":
            if phase < .illustrating {
                if let started = rankingStartedAt {
                    observedRankingSeconds = now.timeIntervalSince(started)
                }
                advance(to: .illustrating, now: now)
                if let serverStart = runningStartedAt, serverStart < phaseStartedAt {
                    phaseStartedAt = serverStart
                }
            }
            noteCompletedCount(completed, now: now)
        case "aiComplete", "complete":
            noteCompletedCount(max(completed, completedMemories), now: now)
            advance(to: .finalizing, now: now)
        default:
            break
        }
    }

    mutating func noteFinalizeStep(_ step: FinalizeStep, now: Date = Date()) {
        advance(to: .finalizing, now: now)
        guard step > finalizeStep || finalizeStartedAt == nil else { return }
        finalizeStep = step
        phaseStartedAt = now
    }

    mutating func noteDone(now: Date = Date()) {
        advance(to: .done, now: now)
    }

    // MARK: - Output

    /// Overall 0...1 progress (monotonic) and a remaining-time estimate.
    /// Call ~once per second while generating; time-based easing needs the ticks.
    mutating func snapshot(now: Date = Date()) -> (progress: Double, etaSeconds: Int?) {
        if phase == .done {
            displayedProgress = 1.0
            return (1.0, 0)
        }
        let raw = overallFraction(now: now)
        displayedProgress = min(0.99, max(displayedProgress, raw))
        return (displayedProgress, remainingSeconds(now: now))
    }

    /// Observed timings for `Calibration.record` — only meaningful after a successful run.
    func observedTimingsForCalibration(now: Date = Date()) -> (perMemory: Double?, ranking: Double?, finalize: Double?) {
        let finalize: Double? = finalizeStartedAt.map { now.timeIntervalSince($0) }
        return (observedPerMemorySeconds, observedRankingSeconds, finalize)
    }

    // MARK: - Internals

    private mutating func advance(to newPhase: Phase, now: Date) {
        guard newPhase > phase else { return }
        phase = newPhase
        phaseStartedAt = now
        if newPhase == .finalizing, finalizeStartedAt == nil {
            finalizeStartedAt = now
            finalizeStep = .rebuildPages
        }
    }

    private mutating func noteCompletedCount(_ completed: Int, now: Date) {
        guard completed > completedMemories else { return }
        let delta = completed - completedMemories
        let since = lastCompletionAt ?? phaseStartedAt
        let sample = now.timeIntervalSince(since) / Double(delta)
        if sample > 0.5 {
            if let current = observedPerMemorySeconds {
                observedPerMemorySeconds = current * 0.7 + sample * 0.3
            } else {
                observedPerMemorySeconds = sample
            }
        }
        completedMemories = completed
        lastCompletionAt = now
    }

    private var effectiveTotalMemories: Int {
        totalMemories > 0 ? totalMemories : pageCountHint
    }

    private var perMemorySeconds: Double {
        observedPerMemorySeconds ?? calibration.perMemorySeconds
    }

    private func expectedSeconds(for phase: Phase) -> Double {
        switch phase {
        case .kickoff:
            return min(20, 4 + 0.25 * Double(effectiveTotalMemories))
        case .queued:
            return 4
        case .ranking:
            return calibration.rankingSeconds
        case .illustrating:
            return perMemorySeconds * Double(effectiveTotalMemories)
        case .finalizing:
            return calibration.finalizeSeconds
        case .done:
            return 0
        }
    }

    /// 0...1 fraction of the CURRENT phase.
    private func currentPhaseFraction(now: Date) -> Double {
        let elapsed = now.timeIntervalSince(phaseStartedAt)
        switch phase {
        case .kickoff, .queued, .ranking:
            return easedFraction(elapsed: elapsed, expected: expectedSeconds(for: phase))
        case .illustrating:
            let total = Double(effectiveTotalMemories)
            let base = Double(completedMemories) / total
            // Creep toward the next completion so the bar keeps moving between
            // Firestore increments, but never claim a memory that isn't done.
            let sinceLast = now.timeIntervalSince(lastCompletionAt ?? phaseStartedAt)
            let creep = min(0.9, sinceLast / perMemorySeconds) / total
            return min(0.99, base + creep)
        case .finalizing:
            var fraction = 0.0
            for step in FinalizeStep.allCases where step < finalizeStep {
                fraction += step.weight
            }
            let stepExpected = max(3, finalizeStep.weight * expectedSeconds(for: .finalizing))
            let stepElapsed = now.timeIntervalSince(phaseStartedAt)
            fraction += finalizeStep.weight * easedFraction(elapsed: stepElapsed, expected: stepExpected)
            return min(0.99, fraction)
        case .done:
            return 1
        }
    }

    /// Asymptotic time-based progress for phases with no real signal: fast at first,
    /// slowing as it nears the cap — visibly alive, but can't complete early.
    private func easedFraction(elapsed: Double, expected: Double) -> Double {
        guard expected > 0, elapsed > 0 else { return 0 }
        let tau = expected * 0.6
        return min(0.97, 1 - exp(-elapsed / tau))
    }

    private func overallFraction(now: Date) -> Double {
        let phases: [Phase] = [.kickoff, .queued, .ranking, .illustrating, .finalizing]
        let expectations = phases.map { expectedSeconds(for: $0) }
        let totalExpected = expectations.reduce(0, +)
        guard totalExpected > 0 else { return 0 }

        var completedSeconds = 0.0
        for (p, expected) in zip(phases, expectations) {
            if p < phase {
                completedSeconds += expected
            } else if p == phase {
                completedSeconds += expected * currentPhaseFraction(now: now)
            }
        }
        return completedSeconds / totalExpected
    }

    private func remainingSeconds(now: Date) -> Int? {
        let phases: [Phase] = [.kickoff, .queued, .ranking, .illustrating, .finalizing]
        var remaining = 0.0
        for p in phases {
            if p > phase {
                remaining += expectedSeconds(for: p)
            } else if p == phase {
                if p == .illustrating {
                    // Real math: unfinished memories at the observed (or calibrated) rate.
                    let left = Double(max(0, effectiveTotalMemories - completedMemories))
                    let sinceLast = now.timeIntervalSince(lastCompletionAt ?? phaseStartedAt)
                    remaining += max(0, left * perMemorySeconds - min(sinceLast, perMemorySeconds))
                } else {
                    remaining += expectedSeconds(for: p) * (1 - currentPhaseFraction(now: now))
                }
            }
        }
        return Int(remaining.rounded())
    }

    // MARK: - Display formatting

    /// Coarse buckets hide the natural jitter of a live estimate.
    static func etaDisplayString(seconds: Int) -> String {
        switch seconds {
        case ..<15: return "Wrapping up…"
        case ..<45: return "Less than a minute left"
        case ..<95: return "About a minute left"
        default:
            let minutes = Int((Double(seconds) / 60).rounded())
            return "About \(minutes) minutes left"
        }
    }
}

private extension ClosedRange where Bound == Double {
    func clamp(_ value: Double) -> Double {
        Swift.min(upperBound, Swift.max(lowerBound, value))
    }
}
