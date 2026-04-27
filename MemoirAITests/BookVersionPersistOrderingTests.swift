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

struct BookVersionPersistOrderingTests {
    private static let key = "memoirai_pending_syncs"

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
            profileId: profile
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
        FirestoreSyncService.shared.registerPendingBookSyncForProfile(bookId: book, profileId: profile)
        var data = try #require(suite.data(forKey: Self.key))
        var rows = try JSONDecoder().decode([PendingRowFull].self, from: data)
        #expect(rows.count == 1)
        rows[0].renderRetryCount = 4
        let patched = try JSONEncoder().encode(rows)
        suite.set(patched, forKey: Self.key)
        FirestoreSyncService.shared.registerPendingBookSyncForProfile(bookId: book, profileId: profile)
        data = try #require(suite.data(forKey: Self.key))
        rows = try JSONDecoder().decode([PendingRowFull].self, from: data)
        let row = try #require(rows.first { $0.bookId == book })
        #expect(row.renderRetryCount == 4)
    }
}
