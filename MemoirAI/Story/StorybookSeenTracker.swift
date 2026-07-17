//
//  StorybookSeenTracker.swift
//  MemoirAI
//
//  Tracks which storybook generations the user has actually laid eyes on, so the
//  app-open auto-route (ContentView.routeToActiveCloudStorybookIfNeeded) brings them
//  to an unseen generation exactly once instead of never or forever.
//

import Foundation
import UIKit

/// Seen-state for storybook cloud jobs, in two scopes:
/// - Completed jobs are persisted: a finished book force-routes the user at most once, ever.
/// - In-flight jobs reset per foreground session: reopening the app routes back to a running
///   generation, but navigating away while the app stays open is respected.
@MainActor
final class StorybookSeenTracker {
    static let shared = StorybookSeenTracker()

    private static let completedSeenKey = "memoirai.storybookCompletedJobsSeen"
    private static let maxStoredJobIds = 50

    private let defaults: UserDefaults

    /// Jobs viewed during the current foreground session; cleared when the app backgrounds.
    private var seenThisForeground: Set<String> = []

    /// True while `StoryPage` is on screen; the auto-route is a no-op then.
    private(set) var isStoryPageVisible = false

    /// Set just before ContentView pushes the storybook route; consumed by `StoryPage.onAppear`
    /// so a job only counts as seen once the destination actually appeared.
    private var pendingRoute: (jobId: String, isComplete: Bool)?

    init(defaults: UserDefaults = .standard, observeLifecycle: Bool = true) {
        self.defaults = defaults
        if observeLifecycle {
            NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    StorybookSeenTracker.shared.resetForegroundSession()
                }
            }
        }
    }

    // MARK: - Queries

    func hasSeenCompleted(jobId: String) -> Bool {
        storedCompletedSeen().contains(jobId)
    }

    func hasSeenThisForeground(jobId: String) -> Bool {
        seenThisForeground.contains(jobId)
    }

    // MARK: - Marking

    func markSeenThisForeground(jobId: String) {
        seenThisForeground.insert(jobId)
    }

    func markCompletedSeen(jobId: String) {
        seenThisForeground.insert(jobId)
        var ids = storedCompletedSeen()
        guard !ids.contains(jobId) else { return }
        ids.append(jobId)
        if ids.count > Self.maxStoredJobIds {
            ids.removeFirst(ids.count - Self.maxStoredJobIds)
        }
        defaults.set(ids, forKey: Self.completedSeenKey)
    }

    // MARK: - Route handshake

    func notePendingRoute(jobId: String, isComplete: Bool) {
        pendingRoute = (jobId, isComplete)
    }

    /// Called from `StoryPage.onAppear`; marks the routed-to job as seen now that the
    /// user is actually looking at it.
    func consumePendingRouteAsSeen() {
        guard let pending = pendingRoute else { return }
        pendingRoute = nil
        if pending.isComplete {
            markCompletedSeen(jobId: pending.jobId)
        } else {
            markSeenThisForeground(jobId: pending.jobId)
        }
    }

    // MARK: - Lifecycle

    func setStoryPageVisible(_ visible: Bool) {
        isStoryPageVisible = visible
    }

    /// In-flight seen-state only lasts one foreground session: exiting the app means the
    /// next open should route back to a still-running generation.
    func resetForegroundSession() {
        seenThisForeground.removeAll()
        pendingRoute = nil
    }

    private func storedCompletedSeen() -> [String] {
        defaults.stringArray(forKey: Self.completedSeenKey) ?? []
    }
}
