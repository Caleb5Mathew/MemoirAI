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
