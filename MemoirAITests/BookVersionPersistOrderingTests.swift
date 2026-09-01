//
//  BookVersionPersistOrderingTests.swift
//  MemoirAITests
//
//  Contract: `registerPendingBookSyncForProfile` must synchronously persist before any async
//  work scheduled by `queueBookSync` can observe a missing pending row. We verify the
//  registration path is synchronous by decoding UserDefaults immediately.
//

import Foundation
import Testing
import UIKit
@testable import MemoirAI

/// Both tests read/write `UserDefaults.standard` under the same key as production; run serially to avoid parallel-test races.
@Suite(.serialized)
struct BookVersionPersistOrderingTests {
    private static let key = "memoirai_pending_syncs"
    private static let deletionKey = "memoirai_pending_memory_deletions"

    private struct PendingRow: Codable {
        let bookId: String
        let profileId: String
    }

    private struct PendingRowFull: Codable {
        let bookId: String
        let profileId: String
        let queuedAt: Date
        var renderRetryCount: Int
        var lastAttemptAt: Date?
    }

    private struct PendingDeletionRow: Codable {
        let memoryId: String
        let profileId: String?
        let firebaseUserId: String
        let queuedAt: Date
        var retryCount: Int
    }

    @Test func registerPendingBookSync_persistsBeforeReturning() throws {
        let suite = UserDefaults.standard
        let before = suite.data(forKey: Self.key)
        defer {
            if let b = before {
                suite.set(b, forKey: Self.key)
            } else {
                suite.removeObject(forKey: Self.key)
            }
        }
        suite.removeObject(forKey: Self.key)
        let profile = UUID()
        let book = "order-test-\(UUID().uuidString)"
        FirestoreSyncService.shared.registerPendingBookSyncForProfile(
            bookId: book,
            profileId: profile,
            firebaseUserId: "pending-book-test-user"
        )
        let data = try #require(suite.data(forKey: Self.key))
        let rows = try JSONDecoder().decode([PendingRow].self, from: data)
        let last = try #require(rows.last)
        #expect(last.bookId == book)
        #expect(last.profileId == profile.uuidString)
    }

    @Test func registerPendingBookSync_reRegister_preservesRenderRetryCount() throws {
        let suite = UserDefaults.standard
        let before = suite.data(forKey: Self.key)
        defer {
            if let b = before {
                suite.set(b, forKey: Self.key)
            } else {
                suite.removeObject(forKey: Self.key)
            }
        }
        suite.removeObject(forKey: Self.key)
        let profile = UUID()
        let book = "retry-preserve-\(UUID().uuidString)"
        FirestoreSyncService.shared.registerPendingBookSyncForProfile(
            bookId: book,
            profileId: profile,
            firebaseUserId: "pending-book-test-user"
        )
        var data = try #require(suite.data(forKey: Self.key))
        var rows = try JSONDecoder().decode([PendingRowFull].self, from: data)
        #expect(rows.count == 1)
        rows[0].renderRetryCount = 4
        rows[0].lastAttemptAt = Date(timeIntervalSince1970: 1234)
        let patched = try JSONEncoder().encode(rows)
        suite.set(patched, forKey: Self.key)
        FirestoreSyncService.shared.registerPendingBookSyncForProfile(
            bookId: book,
            profileId: profile,
            firebaseUserId: "pending-book-test-user"
        )
        data = try #require(suite.data(forKey: Self.key))
        rows = try JSONDecoder().decode([PendingRowFull].self, from: data)
        let row = try #require(rows.first { $0.bookId == book })
        #expect(row.renderRetryCount == 4)
        #expect(row.lastAttemptAt == Date(timeIntervalSince1970: 1234))
    }

    @Test func pendingBookRetryPolicy_backsOffRepeatedFailures() {
        #expect(PendingBookSyncRetryPolicy.delay(forRetryCount: 0) == 0)
        #expect(PendingBookSyncRetryPolicy.delay(forRetryCount: 1) == 15 * 60)
        #expect(PendingBookSyncRetryPolicy.delay(forRetryCount: 2) == 60 * 60)
        #expect(PendingBookSyncRetryPolicy.delay(forRetryCount: 3) == 6 * 60 * 60)
        #expect(PendingBookSyncRetryPolicy.delay(forRetryCount: 20) == 24 * 60 * 60)
    }

    @Test func pendingBookRetryPolicy_retriesOnlyWhenDue() {
        let attempt = Date(timeIntervalSince1970: 10_000)
        #expect(PendingBookSyncRetryPolicy.shouldRetry(retryCount: 1, lastAttemptAt: nil, now: attempt))
        #expect(!PendingBookSyncRetryPolicy.shouldRetry(
            retryCount: 1,
            lastAttemptAt: attempt,
            now: attempt.addingTimeInterval(899)
        ))
        #expect(PendingBookSyncRetryPolicy.shouldRetry(
            retryCount: 1,
            lastAttemptAt: attempt,
            now: attempt.addingTimeInterval(900)
        ))
    }

    @Test func bookRenderCompletionPolicy_requiresRenderedPDFArtifact() {
        #expect(!BookRenderCompletionPolicy.isComplete(status: "rendering", pdfURL: "https://x/book.pdf"))
        #expect(!BookRenderCompletionPolicy.isComplete(status: "rendered", pdfURL: nil))
        #expect(!BookRenderCompletionPolicy.isComplete(status: "rendered", pdfURL: "  "))
        #expect(BookRenderCompletionPolicy.isComplete(status: "rendered", pdfURL: "https://x/book.pdf"))
    }

    @Test func coverArtRevisionPolicy_incrementsSamePathRegeneration() {
        #expect(CoverArtRevisionPolicy.next(existingRevision: nil, hasCover: true) == 1)
        #expect(CoverArtRevisionPolicy.next(existingRevision: 4, hasCover: true) == 5)
        #expect(CoverArtRevisionPolicy.next(existingRevision: 4, hasCover: false) == nil)
    }

    @Test func storageUploadOwnerPolicyRejectsSignOutAndAccountSwitch() {
        #expect(StorageUploadOwnerPolicy.isCurrentOwner(expectedUserID: "user-a", currentUserID: "user-a"))
        #expect(!StorageUploadOwnerPolicy.isCurrentOwner(expectedUserID: "user-a", currentUserID: "user-b"))
        #expect(!StorageUploadOwnerPolicy.isCurrentOwner(expectedUserID: "user-a", currentUserID: nil))
    }

    @MainActor
    @Test func pendingMemoryDeletion_persistsByUserAndCanBeCancelled() throws {
        let defaults = UserDefaults.standard
        let before = defaults.data(forKey: Self.deletionKey)
        defer {
            if let before {
                defaults.set(before, forKey: Self.deletionKey)
            } else {
                defaults.removeObject(forKey: Self.deletionKey)
            }
        }
        defaults.removeObject(forKey: Self.deletionKey)
        let memoryId = UUID()
        let profileId = UUID()
        let userId = "deletion-test-user"

        FirestoreSyncService.shared.registerPendingMemoryDeletion(
            memoryId: memoryId,
            profileId: profileId,
            firebaseUserId: userId
        )
        let data = try #require(defaults.data(forKey: Self.deletionKey))
        let rows = try JSONDecoder().decode([PendingDeletionRow].self, from: data)
        let row = try #require(rows.first)
        #expect(row.memoryId == memoryId.uuidString)
        #expect(row.profileId == profileId.uuidString)
        #expect(row.firebaseUserId == userId)

        FirestoreSyncService.shared.cancelPendingMemoryDeletion(
            memoryId: memoryId,
            firebaseUserId: userId
        )
        let clearedData = try #require(defaults.data(forKey: Self.deletionKey))
        #expect(try JSONDecoder().decode([PendingDeletionRow].self, from: clearedData).isEmpty)
    }
}

private actor SequencerEventLog {
    private var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func snapshot() -> [String] {
        events
    }
}

struct MemoryOperationSequencerTests {
    @Test func sameMemoryOperationsRunInFIFOOrder() async {
        let sequencer = MemoryOperationSequencer()
        let log = SequencerEventLog()

        let first = Task {
            await sequencer.run(key: "user:memory") {
                await log.append("first-start")
                try? await Task.sleep(for: .milliseconds(50))
                await log.append("first-end")
            }
        }
        try? await Task.sleep(for: .milliseconds(5))
        let second = Task {
            await sequencer.run(key: "user:memory") {
                await log.append("second-start")
                await log.append("second-end")
            }
        }

        await first.value
        await second.value
        #expect(await log.snapshot() == ["first-start", "first-end", "second-start", "second-end"])
    }
}

struct PendingSyncRetryGateTests {
    @Test func claimRejectsDuplicateUntilReleased() async {
        let gate = PendingSyncRetryGate()

        #expect(await gate.claim("user|profile"))
        #expect(!(await gate.claim("user|profile")))

        await gate.release("user|profile")
        #expect(await gate.claim("user|profile"))
    }
}

struct FallbackTextPageLayoutTests {
    @Test func wrappedTitleUsesMoreVerticalSpace() {
        let font = UIFont.systemFont(ofSize: 28, weight: .semibold)
        let shortHeight = FallbackTextPageLayout.measuredHeight(
            text: "A Short Title",
            width: 500,
            font: font,
            maximumHeight: 180
        )
        let wrappedHeight = FallbackTextPageLayout.measuredHeight(
            text: "What type of kid were you? Do you have any memories that best show who you were?",
            width: 500,
            font: font,
            maximumHeight: 180
        )

        #expect(wrappedHeight > shortHeight)
        #expect(wrappedHeight <= 180)
    }
}
