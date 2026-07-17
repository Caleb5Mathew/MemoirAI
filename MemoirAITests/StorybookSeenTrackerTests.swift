//
//  StorybookSeenTrackerTests.swift
//  MemoirAITests
//

import Foundation
import Testing
@testable import MemoirAI

@MainActor
struct StorybookSeenTrackerTests {

    private func makeTracker() -> (StorybookSeenTracker, UserDefaults, String) {
        let suite = "StorybookSeenTrackerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (StorybookSeenTracker(defaults: defaults, observeLifecycle: false), defaults, suite)
    }

    @Test func completedSeenPersistsAcrossForegroundReset() {
        let (tracker, defaults, suite) = makeTracker()
        defer { defaults.removePersistentDomain(forName: suite) }

        tracker.markCompletedSeen(jobId: "job-a")
        #expect(tracker.hasSeenCompleted(jobId: "job-a"))
        #expect(tracker.hasSeenThisForeground(jobId: "job-a"))

        tracker.resetForegroundSession()
        #expect(tracker.hasSeenCompleted(jobId: "job-a"))
        #expect(!tracker.hasSeenThisForeground(jobId: "job-a"))
    }

    @Test func inFlightSeenClearsOnForegroundReset() {
        let (tracker, defaults, suite) = makeTracker()
        defer { defaults.removePersistentDomain(forName: suite) }

        tracker.markSeenThisForeground(jobId: "job-b")
        #expect(tracker.hasSeenThisForeground(jobId: "job-b"))
        #expect(!tracker.hasSeenCompleted(jobId: "job-b"))

        tracker.resetForegroundSession()
        #expect(!tracker.hasSeenThisForeground(jobId: "job-b"))
    }

    @Test func pendingRouteConsumedAsCompletedSeen() {
        let (tracker, defaults, suite) = makeTracker()
        defer { defaults.removePersistentDomain(forName: suite) }

        tracker.notePendingRoute(jobId: "job-c", isComplete: true)
        #expect(!tracker.hasSeenCompleted(jobId: "job-c"))

        tracker.consumePendingRouteAsSeen()
        #expect(tracker.hasSeenCompleted(jobId: "job-c"))

        // Second consume is a no-op (no pending route left).
        tracker.consumePendingRouteAsSeen()
        #expect(tracker.hasSeenCompleted(jobId: "job-c"))
    }

    @Test func pendingRouteConsumedAsForegroundSeenForInFlightJob() {
        let (tracker, defaults, suite) = makeTracker()
        defer { defaults.removePersistentDomain(forName: suite) }

        tracker.notePendingRoute(jobId: "job-d", isComplete: false)
        tracker.consumePendingRouteAsSeen()
        #expect(tracker.hasSeenThisForeground(jobId: "job-d"))
        #expect(!tracker.hasSeenCompleted(jobId: "job-d"))
    }

    @Test func pendingRouteClearedByForegroundReset() {
        let (tracker, defaults, suite) = makeTracker()
        defer { defaults.removePersistentDomain(forName: suite) }

        tracker.notePendingRoute(jobId: "job-e", isComplete: true)
        tracker.resetForegroundSession()
        tracker.consumePendingRouteAsSeen()
        #expect(!tracker.hasSeenCompleted(jobId: "job-e"))
    }

    @Test func completedSeenListIsCapped() {
        let (tracker, defaults, suite) = makeTracker()
        defer { defaults.removePersistentDomain(forName: suite) }

        for i in 0..<60 {
            tracker.markCompletedSeen(jobId: "job-\(i)")
        }
        // Oldest entries are trimmed; the most recent survive.
        #expect(!tracker.hasSeenCompleted(jobId: "job-0"))
        #expect(tracker.hasSeenCompleted(jobId: "job-59"))
        let stored = defaults.stringArray(forKey: "memoirai.storybookCompletedJobsSeen") ?? []
        #expect(stored.count == 50)
    }

    @Test func storyPageVisibilityFlag() {
        let (tracker, defaults, suite) = makeTracker()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(!tracker.isStoryPageVisible)
        tracker.setStoryPageVisible(true)
        #expect(tracker.isStoryPageVisible)
        tracker.setStoryPageVisible(false)
        #expect(!tracker.isStoryPageVisible)
    }
}
