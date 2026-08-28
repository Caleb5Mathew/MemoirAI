//
//  FirestoreSyncService.swift
//  MemoirAI
//
//  Syncs memories and books to Firebase Firestore for admin visibility
//

import Foundation
import CoreData
import CryptoKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import UIKit

enum PendingStorybookMatchPolicy {
    static func matches(
        _ book: PersistableStorybook,
        pendingBookID: String,
        profileID: UUID
    ) -> Bool {
        guard book.profileID == profileID else { return false }
        if let canonicalBookID = book.bookVersionID {
            return canonicalBookID == pendingBookID
        }
        guard let pendingCreatedAt = createdAtUnixSeconds(from: pendingBookID) else {
            return false
        }
        return Int(book.createdAt.timeIntervalSince1970) == pendingCreatedAt
    }

    static func createdAtUnixSeconds(from bookID: String) -> Int? {
        let parts = bookID.split(separator: "_")
        guard parts.count >= 2, let encodedTimestamp = Int(parts[1]) else { return nil }
        return encodedTimestamp >= 10_000_000_000 ? encodedTimestamp / 1_000 : encodedTimestamp
    }
}

/// Chains `syncBook` / Storage for the same `bookVersionId` so concurrent in-place saves do not interleave.
private actor BookVersionSyncSequencer {
    private struct Tail {
        let token: UUID
        let task: Task<Void, Never>
    }
    private var inFlight: [String: Tail] = [:]
    /// Runs `work` after any earlier task for the same `bookId` has finished; latest snapshot wins.
    func run<Result: Sendable>(
        bookId: String,
        work: @Sendable @escaping () async -> Result
    ) async -> Result {
        let previous = inFlight[bookId]?.task
        let token = UUID()
        let resultTask = Task {
            await previous?.value
            return await work()
        }
        let completionTask = Task {
            _ = await resultTask.value
        }
        inFlight[bookId] = Tail(token: token, task: completionTask)
        let result = await resultTask.value
        if inFlight[bookId]?.token == token {
            inFlight.removeValue(forKey: bookId)
        }
        return result
    }
}

/// Serializes cloud operations for one signed-in user's memory while allowing
/// unrelated memories to continue syncing concurrently.
actor MemoryOperationSequencer {
    private struct Tail {
        let token: UUID
        let task: Task<Void, Never>
    }

    private var tails: [String: Tail] = [:]

    func run<Result: Sendable>(
        key: String,
        operation: @MainActor @Sendable @escaping () async -> Result
    ) async -> Result {
        let previous = tails[key]?.task
        let token = UUID()
        let resultTask = Task { @MainActor in
            await previous?.value
            return await operation()
        }
        let completionTask = Task {
            _ = await resultTask.value
        }
        tails[key] = Tail(token: token, task: completionTask)

        let result = await resultTask.value
        if tails[key]?.token == token {
            tails.removeValue(forKey: key)
        }
        return result
    }
}

/// Service for syncing local Core Data to Firebase Firestore
/// This runs alongside CloudKit - CloudKit handles fast local sync,
/// Firebase provides admin access to all user data
final class FirestoreSyncService {
    typealias RenderedPageProvider = @MainActor @Sendable (Int) -> UIImage?
    
    static let shared = FirestoreSyncService()
    
    private let db = Firestore.firestore()
    private let bookVersionSyncSequencer = BookVersionSyncSequencer()
    private let memoryOperationSequencer = MemoryOperationSequencer()
    private let memorySyncPersistenceLock = NSLock()
    private let memoryDeletionPersistenceLock = NSLock()
    private let bookSyncPersistenceLock = NSLock()
    
    /// Sticky per signed-in `uid` so re-register from `performSyncBook` after `incrementPendingBookRenderRetry` does not wipe the count.
    private var lastPostSignInCoverBackfillUserId: String?
    private var coverHealBudgetLock = NSLock()
    private var coverHealSessionAttempts: [String: Int] = [:]
    private static let maxCoverHealAttemptsPerVersionPerSession = 2

    private init() {
        _ = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { await self?.handleAuthChangeForStuckCoverHeal(user: user) }
        }
        NotificationCenter.default.addObserver(
            forName: .bookCoverBackfillComplete,
            object: nil,
            queue: nil
        ) { [weak self] note in
            guard let bid = note.userInfo?["bookVersionId"] as? String else { return }
            self?.clearCoverHealSessionSlot(for: bid)
        }
    }

    struct BookRenderFunctionResponse {
        let status: String?
        let pdfURL: String?
        let pdfStoragePath: String?
        let renderDurationMs: Int?
        let pdfBytes: Int?
        let message: String?
    }
    
    private func migrationCompletionKey(for userId: String) -> String {
        "firebase_migration_complete_\(userId)"
    }

    // MARK: - Pending book sync (resume interrupted uploads)

    private static let pendingBookSyncStorageKey = "memoirai_pending_syncs"

    private struct PendingBookSyncRecord: Codable {
        let bookId: String
        let profileId: String
        let firebaseUserId: String?
        let queuedAt: Date
        /// Incremented when `invokeBookRenderFunction` fails; used for debugging / future backoff.
        var renderRetryCount: Int

        init(
            bookId: String,
            profileId: String,
            firebaseUserId: String,
            queuedAt: Date,
            renderRetryCount: Int = 0
        ) {
            self.bookId = bookId
            self.profileId = profileId
            self.firebaseUserId = firebaseUserId
            self.queuedAt = queuedAt
            self.renderRetryCount = renderRetryCount
        }

        private enum CodingKeys: String, CodingKey {
            case bookId, profileId, firebaseUserId, queuedAt, renderRetryCount
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            bookId = try c.decode(String.self, forKey: .bookId)
            profileId = try c.decode(String.self, forKey: .profileId)
            firebaseUserId = try c.decodeIfPresent(String.self, forKey: .firebaseUserId)
            queuedAt = try c.decode(Date.self, forKey: .queuedAt)
            renderRetryCount = try c.decodeIfPresent(Int.self, forKey: .renderRetryCount) ?? 0
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(bookId, forKey: .bookId)
            try c.encode(profileId, forKey: .profileId)
            try c.encodeIfPresent(firebaseUserId, forKey: .firebaseUserId)
            try c.encode(queuedAt, forKey: .queuedAt)
            try c.encode(renderRetryCount, forKey: .renderRetryCount)
        }
    }

    private func loadPendingBookSyncRecords() -> [PendingBookSyncRecord] {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingBookSyncStorageKey),
              let decoded = try? JSONDecoder().decode([PendingBookSyncRecord].self, from: data) else {
            return []
        }
        return decoded
    }

    private func registerPendingBookSync(
        bookId: String,
        profileId: String,
        firebaseUserId: String
    ) {
        guard let firebaseUserId = MemoryOwnershipPolicy.normalizedUserID(firebaseUserId) else { return }
        bookSyncPersistenceLock.withLock {
            var records = loadPendingBookSyncRecords()
            let existing = records.first {
                $0.bookId == bookId && $0.firebaseUserId == firebaseUserId
            }
            let preserveRetry = existing?.renderRetryCount ?? 0
            let preserveQueued = existing?.queuedAt ?? Date()
            records.removeAll { $0.bookId == bookId && $0.firebaseUserId == firebaseUserId }
            records.append(
                PendingBookSyncRecord(
                    bookId: bookId,
                    profileId: profileId,
                    firebaseUserId: firebaseUserId,
                    queuedAt: preserveQueued,
                    renderRetryCount: preserveRetry
                )
            )
            if let data = try? JSONEncoder().encode(records) {
                UserDefaults.standard.set(data, forKey: Self.pendingBookSyncStorageKey)
            }
        }
    }

    /// Public so `StoryPageViewModel.persistStorybook` can register *before* `queueBookSync` schedules work (removes a crash window).
    func registerPendingBookSyncForProfile(bookId: String, profileId: UUID) {
        guard let firebaseUserId = Auth.auth().currentUser?.uid else { return }
        registerPendingBookSync(
            bookId: bookId,
            profileId: profileId.uuidString,
            firebaseUserId: firebaseUserId
        )
    }

    func registerPendingBookSyncForProfile(
        bookId: String,
        profileId: UUID,
        firebaseUserId: String
    ) {
        registerPendingBookSync(
            bookId: bookId,
            profileId: profileId.uuidString,
            firebaseUserId: firebaseUserId
        )
    }

    private func incrementPendingBookRenderRetry(bookId: String) {
        guard let firebaseUserId = Auth.auth().currentUser?.uid else { return }
        bookSyncPersistenceLock.withLock {
            var records = loadPendingBookSyncRecords()
            guard let i = records.firstIndex(where: {
                $0.bookId == bookId && $0.firebaseUserId == firebaseUserId
            }) else { return }
            records[i].renderRetryCount += 1
            if let data = try? JSONEncoder().encode(records) {
                UserDefaults.standard.set(data, forKey: Self.pendingBookSyncStorageKey)
            }
            print("[CoverFlow] incrementPendingBookRenderRetry bookId=\(bookId.prefix(28))… count=\(records[i].renderRetryCount)")
        }
    }

    private func clearPendingBookSync(bookId: String) {
        guard let firebaseUserId = Auth.auth().currentUser?.uid else { return }
        bookSyncPersistenceLock.withLock {
            var records = loadPendingBookSyncRecords()
            records.removeAll { $0.bookId == bookId && $0.firebaseUserId == firebaseUserId }
            if let data = try? JSONEncoder().encode(records) {
                UserDefaults.standard.set(data, forKey: Self.pendingBookSyncStorageKey)
            }
        }
    }

    private func localStorybookMatchingPending(bookId: String, profileID: UUID) -> PersistableStorybook? {
        let decoder = JSONDecoder()
        if let pendingData = StorybookLocalStore.readPendingBookData(profileID: profileID),
           let book = try? decoder.decode(PersistableStorybook.self, from: pendingData),
           PendingStorybookMatchPolicy.matches(
               book,
               pendingBookID: bookId,
               profileID: profileID
           ) {
            return book
        }
        // Prefer current on-disk book when it matches this `bookId` (fresher than a stale history entry).
        if let currentData = StorybookLocalStore.readCurrentBookData(profileID: profileID),
           let book = try? decoder.decode(PersistableStorybook.self, from: currentData),
           PendingStorybookMatchPolicy.matches(
               book,
               pendingBookID: bookId,
               profileID: profileID
           ) {
            return book
        }
        for data in StorybookLocalStore.readHistoryDataArray(profileID: profileID) {
            guard let book = try? decoder.decode(PersistableStorybook.self, from: data),
                  PendingStorybookMatchPolicy.matches(
                      book,
                      pendingBookID: bookId,
                      profileID: profileID
                  ) else { continue }
            return book
        }
        return nil
    }

    /// Re-attempt uploads for books that never finished syncing (same device, local `.book` still present). Uses the freshest `current.book` for that version when possible.
    /// Also re-attempts any memory syncs queued by `queueMemorySyncWithProfile` that failed while offline (see `retryPendingMemorySyncs`).
    func retryPendingSyncs(for profileID: UUID) async {
        guard let firebaseUserId = Auth.auth().currentUser?.uid else { return }
        await retryPendingMemoryDeletions(firebaseUserId: firebaseUserId)
        await retryPendingMemorySyncs(for: profileID)
        let want = profileID.uuidString
        let pending = loadPendingBookSyncRecords().filter {
            $0.profileId == want && $0.firebaseUserId == firebaseUserId
        }
        guard !pending.isEmpty else { return }
        for record in pending {
            if let cloud = await fetchBookVersion(bookVersionId: record.bookId),
               !StorybookCloudApplyPolicy.isIncompleteCloudRecord(cloud),
               cloud.renderStatus == BookRenderStatus.rendered.rawValue,
               cloud.pdfURL != nil,
               !(cloud.coverURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                try? StorybookLocalStore.promotePendingBook(
                    bookVersionID: record.bookId,
                    profileID: profileID
                )
                clearPendingBookSync(bookId: record.bookId)
                continue
            }
            if localStorybookMatchingPending(bookId: record.bookId, profileID: profileID) != nil,
               let cloud = await fetchBookVersion(bookVersionId: record.bookId),
               !StorybookCloudApplyPolicy.isIncompleteCloudRecord(cloud),
               cloud.pageCount > 0,
               (cloud.pdfURL == nil || cloud.renderStatus != BookRenderStatus.rendered.rawValue) {
                let hasCover = !(cloud.coverURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                if !hasCover {
                    _ = await ensureCoverDesignExistsIfMissing(
                        bookVersionId: record.bookId,
                        respectSessionBudget: false
                    )
                }
                let renderOk = await invokeBookRenderFunction(bookVersionId: record.bookId) != nil
                if renderOk {
                    try? StorybookLocalStore.promotePendingBook(
                        bookVersionID: record.bookId,
                        profileID: profileID
                    )
                    clearPendingBookSync(bookId: record.bookId)
                } else {
                    incrementPendingBookRenderRetry(bookId: record.bookId)
                }
                continue
            }
            guard let book = localStorybookMatchingPending(bookId: record.bookId, profileID: profileID) else {
                continue
            }
            let synced = await syncBook(book, bookId: record.bookId, renderedPageImages: nil, coverInputs: nil)
            if synced {
                try? StorybookLocalStore.promotePendingBook(
                    bookVersionID: record.bookId,
                    profileID: profileID
                )
            }
        }
    }

    private var bookRenderFunctionURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "BOOK_RENDER_FUNCTION_URL") as? String,
              let url = URL(string: raw),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return url
    }

    /// True when Firestore reports FAILED_PRECONDITION for a missing composite index (common code 9).
    private func isMissingFirestoreCompositeIndexError(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == FirestoreErrorDomain,
              ns.code == FirestoreErrorCode.failedPrecondition.rawValue else {
            return false
        }
        let msg = ns.localizedDescription.lowercased()
        return msg.contains("index") || msg.contains("requires an index")
    }

    /// Fallback: no composite index — fetch recent bookVersions ordered by createdAt only, filter profileId in memory.
    private func fetchLatestBookVersionClientFilter(profileID: UUID, userId: String) async -> BookVersionRecord? {
        let ref = db.collection("users").document(userId).collection("bookVersions")
        do {
            let snapshot = try await ref.order(by: "createdAt", descending: true).limit(to: 80).getDocuments()
            let wanted = profileID.uuidString
            for doc in snapshot.documents {
                guard let record = BookVersionRecord.fromFirestoreData(doc.data()),
                      record.profileId == wanted else { continue }
                return record
            }
            return nil
        } catch {
            print("❌ fetchLatestBookVersionClientFilter failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchBookVersionsClientFilter(profileID: UUID, userId: String) async -> [BookVersionRecord] {
        let ref = db.collection("users").document(userId).collection("bookVersions")
        do {
            let snapshot = try await ref.order(by: "createdAt", descending: true).limit(to: 80).getDocuments()
            let wanted = profileID.uuidString
            return snapshot.documents.compactMap { BookVersionRecord.fromFirestoreData($0.data()) }
                .filter { $0.profileId == wanted }
        } catch {
            print("❌ fetchBookVersionsClientFilter failed: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Pending memory sync (resume interrupted uploads)

    private static let pendingMemorySyncStorageKey = "memoirai_pending_memory_syncs"

    private struct PendingMemorySyncRecord: Codable {
        let memoryId: String
        let profileId: String
        let firebaseUserId: String?
        let glossary: [String]
        let queuedAt: Date
        /// Incremented when a retry attempt still fails; used for debugging, same as `PendingBookSyncRecord.renderRetryCount`.
        var retryCount: Int

        init(
            memoryId: String,
            profileId: String,
            firebaseUserId: String?,
            glossary: [String],
            queuedAt: Date,
            retryCount: Int = 0
        ) {
            self.memoryId = memoryId
            self.profileId = profileId
            self.firebaseUserId = firebaseUserId
            self.glossary = glossary
            self.queuedAt = queuedAt
            self.retryCount = retryCount
        }

        private enum CodingKeys: String, CodingKey {
            case memoryId, profileId, firebaseUserId, glossary, queuedAt, retryCount
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            memoryId = try c.decode(String.self, forKey: .memoryId)
            profileId = try c.decode(String.self, forKey: .profileId)
            firebaseUserId = try c.decodeIfPresent(String.self, forKey: .firebaseUserId)
            glossary = try c.decodeIfPresent([String].self, forKey: .glossary) ?? []
            queuedAt = try c.decode(Date.self, forKey: .queuedAt)
            retryCount = try c.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(memoryId, forKey: .memoryId)
            try c.encode(profileId, forKey: .profileId)
            try c.encodeIfPresent(firebaseUserId, forKey: .firebaseUserId)
            try c.encode(glossary, forKey: .glossary)
            try c.encode(queuedAt, forKey: .queuedAt)
            try c.encode(retryCount, forKey: .retryCount)
        }
    }

    private func loadPendingMemorySyncRecords() -> [PendingMemorySyncRecord] {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingMemorySyncStorageKey),
              let decoded = try? JSONDecoder().decode([PendingMemorySyncRecord].self, from: data) else {
            return []
        }
        return decoded
    }

    private func registerPendingMemorySync(
        memoryId: String,
        profileId: String,
        firebaseUserId: String,
        glossary: [String]
    ) {
        guard let firebaseUserId = MemoryOwnershipPolicy.normalizedUserID(firebaseUserId) else { return }
        memorySyncPersistenceLock.withLock {
            var records = loadPendingMemorySyncRecords()
            let existing = records.first { $0.memoryId == memoryId && $0.firebaseUserId == firebaseUserId }
            let preserveRetry = existing?.retryCount ?? 0
            let preserveQueued = existing?.queuedAt ?? Date()
            records.removeAll { $0.memoryId == memoryId && $0.firebaseUserId == firebaseUserId }
            records.append(
                PendingMemorySyncRecord(
                    memoryId: memoryId,
                    profileId: profileId,
                    firebaseUserId: firebaseUserId,
                    glossary: glossary,
                    queuedAt: preserveQueued,
                    retryCount: preserveRetry
                )
            )
            if let data = try? JSONEncoder().encode(records) {
                UserDefaults.standard.set(data, forKey: Self.pendingMemorySyncStorageKey)
            }
        }
    }

    /// Non-private so tests can exercise the same register/re-register contract as `registerPendingBookSyncForProfile`.
    func registerPendingMemorySyncForProfile(
        memoryId: String,
        profile: Profile,
        firebaseUserId: String
    ) {
        registerPendingMemorySync(
            memoryId: memoryId,
            profileId: profile.id.uuidString,
            firebaseUserId: firebaseUserId,
            glossary: CloudTranscriptionService.glossary(for: profile)
        )
    }

    private func incrementPendingMemorySyncRetry(memoryId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        memorySyncPersistenceLock.withLock {
            var records = loadPendingMemorySyncRecords()
            guard let i = records.firstIndex(where: {
                $0.memoryId == memoryId && $0.firebaseUserId == currentUserId
            }) else { return }
            records[i].retryCount += 1
            if let data = try? JSONEncoder().encode(records) {
                UserDefaults.standard.set(data, forKey: Self.pendingMemorySyncStorageKey)
            }
            print("[MemorySync] incrementPendingMemorySyncRetry memoryId=\(memoryId.prefix(8))… count=\(records[i].retryCount)")
        }
    }

    private func clearPendingMemorySync(memoryId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        memorySyncPersistenceLock.withLock {
            var records = loadPendingMemorySyncRecords()
            records.removeAll {
                $0.memoryId == memoryId && $0.firebaseUserId == currentUserId
            }
            if let data = try? JSONEncoder().encode(records) {
                UserDefaults.standard.set(data, forKey: Self.pendingMemorySyncStorageKey)
            }
        }
    }

    // MARK: - Pending memory deletion (durable tombstones)

    private static let pendingMemoryDeletionStorageKey = "memoirai_pending_memory_deletions"

    private struct PendingMemoryDeletionRecord: Codable {
        let memoryId: String
        let profileId: String?
        let firebaseUserId: String
        let queuedAt: Date
        var retryCount: Int
    }

    private func loadPendingMemoryDeletionRecords() -> [PendingMemoryDeletionRecord] {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingMemoryDeletionStorageKey),
              let records = try? JSONDecoder().decode([PendingMemoryDeletionRecord].self, from: data) else {
            return []
        }
        return records
    }

    private func savePendingMemoryDeletionRecords(_ records: [PendingMemoryDeletionRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Self.pendingMemoryDeletionStorageKey)
    }

    /// Persists deletion intent before local content is removed so a crash or offline launch cannot resurrect it.
    func registerPendingMemoryDeletion(
        memoryId: UUID,
        profileId: UUID?,
        firebaseUserId: String?
    ) {
        guard let firebaseUserId, !firebaseUserId.isEmpty else { return }
        memoryDeletionPersistenceLock.withLock {
            var records = loadPendingMemoryDeletionRecords()
            let existing = records.first {
                $0.memoryId == memoryId.uuidString && $0.firebaseUserId == firebaseUserId
            }
            records.removeAll {
                $0.memoryId == memoryId.uuidString && $0.firebaseUserId == firebaseUserId
            }
            records.append(
                PendingMemoryDeletionRecord(
                    memoryId: memoryId.uuidString,
                    profileId: profileId?.uuidString ?? existing?.profileId,
                    firebaseUserId: firebaseUserId,
                    queuedAt: existing?.queuedAt ?? Date(),
                    retryCount: existing?.retryCount ?? 0
                )
            )
            savePendingMemoryDeletionRecords(records)
        }
        clearPendingMemorySync(memoryId: memoryId.uuidString)
    }

    func cancelPendingMemoryDeletion(memoryId: UUID, firebaseUserId: String?) {
        guard let firebaseUserId, !firebaseUserId.isEmpty else { return }
        memoryDeletionPersistenceLock.withLock {
            var records = loadPendingMemoryDeletionRecords()
            records.removeAll {
                $0.memoryId == memoryId.uuidString && $0.firebaseUserId == firebaseUserId
            }
            savePendingMemoryDeletionRecords(records)
        }
    }

    private func isMemoryDeletionPending(memoryId: UUID, firebaseUserId: String) -> Bool {
        memoryDeletionPersistenceLock.withLock {
            loadPendingMemoryDeletionRecords().contains {
                $0.memoryId == memoryId.uuidString && $0.firebaseUserId == firebaseUserId
            }
        }
    }

    private func incrementPendingMemoryDeletionRetry(memoryId: UUID, firebaseUserId: String) {
        memoryDeletionPersistenceLock.withLock {
            var records = loadPendingMemoryDeletionRecords()
            guard let index = records.firstIndex(where: {
                $0.memoryId == memoryId.uuidString && $0.firebaseUserId == firebaseUserId
            }) else { return }
            records[index].retryCount += 1
            savePendingMemoryDeletionRecords(records)
        }
    }

    @MainActor
    private func retryPendingMemoryDeletions(firebaseUserId: String) async {
        let pending = memoryDeletionPersistenceLock.withLock {
            loadPendingMemoryDeletionRecords().filter { $0.firebaseUserId == firebaseUserId }
        }
        for record in pending {
            guard let memoryId = UUID(uuidString: record.memoryId) else {
                memoryDeletionPersistenceLock.withLock {
                    var records = loadPendingMemoryDeletionRecords()
                    records.removeAll {
                        $0.memoryId == record.memoryId && $0.firebaseUserId == firebaseUserId
                    }
                    savePendingMemoryDeletionRecords(records)
                }
                continue
            }
            await deleteMemory(
                memoryId: memoryId,
                profileId: record.profileId.flatMap { UUID(uuidString: $0) },
                firebaseUserId: firebaseUserId
            )
        }
    }

    /// Re-attempt Firestore uploads for memories whose background sync previously failed (offline save).
    /// Dedupes by memory id; drops the pending record once synced or once the local `MemoryEntry` no longer exists.
    @MainActor
    private func retryPendingMemorySyncs(for profileID: UUID) async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        let want = profileID.uuidString
        let pending = memorySyncPersistenceLock.withLock {
            loadPendingMemorySyncRecords().filter {
                $0.profileId == want && $0.firebaseUserId == currentUserId
            }
        }
        guard !pending.isEmpty else { return }

        let context = PersistenceController.shared.container.viewContext
        for record in pending {
            guard let memoryUUID = UUID(uuidString: record.memoryId) else {
                clearPendingMemorySync(memoryId: record.memoryId)
                continue
            }
            let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "id == %@", memoryUUID as CVarArg),
                NSPredicate(format: "firebaseUserId == %@", currentUserId)
            ])
            request.fetchLimit = 1
            guard let entry = try? context.fetch(request).first else {
                // A locally deleted row must remove its remote copy rather than silently
                // dropping the last durable work record and allowing hydration to restore it.
                registerPendingMemoryDeletion(
                    memoryId: memoryUUID,
                    profileId: UUID(uuidString: record.profileId),
                    firebaseUserId: currentUserId
                )
                clearPendingMemorySync(memoryId: record.memoryId)
                continue
            }
            let synced = await syncMemory(entry)
            if synced {
                if TranscriptionRetryPolicy.shouldRequest(
                    status: entry.transcriptionStatus,
                    audioFileExtension: URL(string: entry.audioFileURL ?? "")?.pathExtension,
                    updatedAt: entry.transcriptionUpdatedAt
                ), let id = entry.id {
                    do {
                        _ = try await CloudTranscriptionService.shared.transcribe(memoryID: id, glossary: record.glossary)
                        clearPendingMemorySync(memoryId: record.memoryId)
                    } catch {
                        if entry.transcriptionStatus == "needsRerecording" {
                            clearPendingMemorySync(memoryId: record.memoryId)
                        } else {
                            incrementPendingMemorySyncRetry(memoryId: record.memoryId)
                        }
                        print("⚠️ Pending cloud transcription retry failed: \(error.localizedDescription)")
                    }
                } else if entry.transcriptionStatus != "processing" {
                    clearPendingMemorySync(memoryId: record.memoryId)
                }
            } else {
                if entry.transcriptionStatus == "needsRerecording" {
                    clearPendingMemorySync(memoryId: record.memoryId)
                } else {
                    incrementPendingMemorySyncRetry(memoryId: record.memoryId)
                }
            }
        }
    }

    // MARK: - Memory Sync

    /// Sync a memory entry to Firestore
    /// Call this after saving to Core Data
    /// - Returns: `true` when the Firestore write (and audio upload, if any) succeeded; `false` on any failure so callers can queue a retry.
    @discardableResult
    @MainActor
    func syncMemory(_ entry: MemoryEntry, profileName: String? = nil) async -> Bool {
        guard let firebaseUserId = Auth.auth().currentUser?.uid,
              let memoryId = entry.id else {
            print("⚠️ Cannot sync memory - missing signed-in user or memory ID")
            return false
        }
        let objectID = entry.objectID
        let operationKey = "\(firebaseUserId):\(memoryId.uuidString)"

        return await memoryOperationSequencer.run(key: operationKey) { @MainActor [self] in
            guard Auth.auth().currentUser?.uid == firebaseUserId,
                  !isMemoryDeletionPending(memoryId: memoryId, firebaseUserId: firebaseUserId) else {
                return false
            }
            let context = PersistenceController.shared.container.viewContext
            guard let currentEntry = try? context.existingObject(with: objectID) as? MemoryEntry,
                  !currentEntry.isDeleted else {
                return false
            }
            return await performMemorySync(currentEntry, profileName: profileName)
        }
    }

    @MainActor
    private func performMemorySync(_ entry: MemoryEntry, profileName: String?) async -> Bool {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ Cannot sync memory - user not signed in")
            return false
        }

        guard MemoryOwnershipPolicy.belongsToUser(
            entryOwnerID: entry.firebaseUserId,
            currentUserID: userId
        ) else {
            print("⚠️ Refusing to sync a memory without exact Firebase ownership")
            return false
        }

        guard let memoryId = entry.id else {
            print("⚠️ Cannot sync memory - no ID")
            return false
        }
        guard !isMemoryDeletionPending(memoryId: memoryId, firebaseUserId: userId) else {
            print("⚠️ Skipping sync for deleted memory \(memoryId.uuidString.prefix(8))…")
            return false
        }

        let memoryRef = db.collection("users").document(userId)
            .collection("memories").document(memoryId.uuidString)

        let prompt = entry.prompt ?? ""
        let text = entry.text ?? ""
        let createdAt = entry.createdAt ?? Date()
        let chapter = entry.chapter ?? ""
        let profileID = entry.profileID?.uuidString ?? ""
        let characterDetails = entry.characterDetails
        let audioData = entry.audioData
        let audioFileURL = entry.audioFileURL
        let transcriptionStatus = entry.transcriptionStatus
        let transcriptionEditedText = entry.transcriptionEditedText

        do {
            var memoryData: [String: Any] = [
                "prompt": prompt,
                "createdAt": createdAt,
                "chapter": chapter,
                "profileID": profileID,
                "syncedAt": FieldValue.serverTimestamp()
            ]

            // A transient read failure must not look like a missing document: doing
            // so would treat unchanged audio as new and reset a completed transcript.
            let remoteSnapshot = try await memoryRef.getDocument()
            let remoteData = remoteSnapshot.data() ?? [:]
            let localAudioURL = audioFileURL
                .flatMap(URL.init(string:))
                .flatMap { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            let uploadAudioURL = localAudioURL ?? ((audioData?.isEmpty == false) ? entry.playbackURL : nil)
            let fileExtension = uploadAudioURL?.pathExtension.lowercased() == "m4a" ? "m4a" : "caf"
            let isM4A = fileExtension == "m4a"
            var audioChanged = false

            if let uploadAudioURL {
                let audioByteCount = (try? uploadAudioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if isM4A && audioByteCount > 25 * 1024 * 1024 {
                    entry.transcriptionStatus = "needsRerecording"
                    entry.transcriptionUpdatedAt = Date()
                    try entry.managedObjectContext?.save()
                    print("❌ Recording is too large for cloud transcription")
                    return false
                }

                let audioSHA256 = try Self.sha256Hex(fileURL: uploadAudioURL)
                let storagePath = "users/\(userId)/audio/\(memoryId.uuidString).\(fileExtension)"
                audioChanged = remoteData["audioSHA256"] as? String != audioSHA256
                let remotePathMatches = remoteData["audioStoragePath"] as? String == storagePath
                if !audioChanged, remotePathMatches, let remoteURL = remoteData["audioURL"] as? String {
                    memoryData["audioURL"] = remoteURL
                } else {
                    memoryData["audioURL"] = try await StorageService.shared.uploadAudio(
                        uploadAudioURL,
                        memoryId: memoryId.uuidString,
                        fileExtension: fileExtension,
                        asUserID: userId
                    )
                }
                memoryData["audioStoragePath"] = storagePath
                memoryData["audioSHA256"] = audioSHA256
            } else if audioFileURL == nil || audioFileURL?.isEmpty == true {
                memoryData["audioURL"] = FieldValue.delete()
                memoryData["audioStoragePath"] = FieldValue.delete()
                memoryData["audioSHA256"] = FieldValue.delete()
            }

            // Include profile name for easy identification
            if let profileName = profileName {
                memoryData["profileName"] = profileName
            }

            if let characterDetails {
                memoryData["characterDetails"] = characterDetails
            }

            switch MemoryTranscriptionSyncPolicy.mode(
                audioChanged: audioChanged,
                isM4A: isM4A,
                status: transcriptionStatus,
                editedText: transcriptionEditedText,
                text: text
            ) {
            case .resetForNewAudio:
                memoryData["transcription"] = text
                memoryData["transcriptionStatus"] = "queued"
                memoryData["transcriptionRaw"] = FieldValue.delete()
                if let transcriptionEditedText {
                    memoryData["transcriptionEdited"] = transcriptionEditedText
                } else {
                    memoryData["transcriptionEdited"] = FieldValue.delete()
                }
                memoryData["transcriptionLanguage"] = FieldValue.delete()
                memoryData["transcriptionModel"] = FieldValue.delete()
                memoryData["transcriptionVersion"] = 0
                memoryData["transcriptionJobId"] = FieldValue.delete()
                memoryData["transcriptionLeaseExpiresAt"] = FieldValue.delete()
                memoryData["transcriptionAudioSHA256"] = FieldValue.delete()
            case .writeEditedText(let editedText):
                memoryData["transcription"] = editedText
                memoryData["transcriptionEdited"] = editedText
            case .writeLegacyText(let legacyText):
                memoryData["transcription"] = legacyText
            case .preserveServer:
                break
            }

            // Save to Firestore
            guard Auth.auth().currentUser?.uid == userId,
                  !isMemoryDeletionPending(memoryId: memoryId, firebaseUserId: userId) else {
                return false
            }
            try await memoryRef.setData(memoryData, merge: true)
            if audioChanged && isM4A {
                try? await StorageService.shared.deleteFile(
                    at: "users/\(userId)/audio/\(memoryId.uuidString).caf"
                )
            }
            print("✅ Synced memory \(memoryId.uuidString.prefix(8))… to Firebase")
            return true

        } catch {
            print("❌ Failed to sync memory to Firebase: \(error)")
            return false
        }
    }
    
    // MARK: - Book Sync

    /// Cover generation inputs for print cover (kids + portrait when Gemini is available).
    /// When `headshot` is nil, cover art must not depict people (`generateCoverIllustration` no-humans path).
    struct CoverInputs {
        let headshot: UIImage?
        let profileName: String
        let ethnicity: String?
        let gender: String?
        let memoryThemes: [String]
        let artStyle: ArtStyle
        /// User custom style phrase when `artStyle == .custom`; also forwarded for consistency on other styles if ever set.
        let customArtStyleText: String?
        /// Canonical title — rendered inside AI cover art when using Gemini; also passed to PDF renderer for legacy/native overlay paths.
        let printTitle: String
        /// Back panel marketing copy.
        let backCoverPitch: String
        let coverFontPreset: CoverFontPreset
        /// Server-built protagonist row from cloud storybook cast canon (optional).
        let protagonistCanonLine: String?
    }

    /// Sync a generated storybook to Firestore with rendered page artifacts. Concurrency: serialized per `bookId`.
    func syncBook(
        _ book: PersistableStorybook,
        bookId: String,
        renderedPageImages: [UIImage]? = nil,
        renderedPageProvider: RenderedPageProvider? = nil,
        coverInputs: CoverInputs? = nil,
        coverPDFOverride: Data? = nil
    ) async -> Bool {
        // Avoid capturing `var cover` in an `@Sendable` closure (Swift 6): resolve inputs once, synchronously.
        let finalCoverInputs: CoverInputs? = {
            if let c = coverInputs { return c }
            if renderedPageImages == nil { return Self.syntheticCoverInputsIfPossible(from: book) }
            return nil
        }()
        let rendered = renderedPageImages
        return await bookVersionSyncSequencer.run(bookId: bookId) { [self] in
            await self.performSyncBook(
                book,
                bookId: bookId,
                renderedPageImages: rendered,
                renderedPageProvider: renderedPageProvider,
                coverInputs: finalCoverInputs,
                coverPDFOverride: coverPDFOverride
            )
        }
    }

    /// When `coverInputs` and `renderedPageImages` were both nil (e.g. `retryPendingSyncs`), still allow Gemini + title-only cover from persisted text.
    private static func syntheticCoverInputsIfPossible(from book: PersistableStorybook) -> CoverInputs? {
        let art = ArtStyle.resolvedFromStored(book.artStyle)
        let rawTitle = book.bookDisplayTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let firstLine = book.pageItems.first?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = !rawTitle.isEmpty ? rawTitle : (!firstLine.isEmpty ? firstLine : "Memoir")
        let policy = CoverCopyPolicy(artStyle: art, profileDisplayName: title)
        let pitch = book.backCoverPitch?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (book.backCoverPitch ?? policy.fallbackBackCoverPitch(bookTitle: title))
            : policy.fallbackBackCoverPitch(bookTitle: title)
        let themes = book.pageItems.prefix(8).compactMap { $0.title?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return CoverInputs(
            headshot: nil,
            profileName: title,
            ethnicity: nil,
            gender: nil,
            memoryThemes: themes,
            artStyle: art,
            customArtStyleText: nil,
            printTitle: title,
            backCoverPitch: pitch,
            coverFontPreset: CoverFontPreset(rawValue: book.coverFontPreset ?? "") ?? policy.coverFontPreset(),
            protagonistCanonLine: nil
        )
    }

    private func performSyncBook(
        _ book: PersistableStorybook,
        bookId: String,
        renderedPageImages: [UIImage]? = nil,
        renderedPageProvider: RenderedPageProvider? = nil,
        coverInputs: CoverInputs? = nil,
        coverPDFOverride: Data? = nil
    ) async -> Bool {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ Cannot sync book - user not signed in")
            return false
        }
        guard book.ownerUserID == userId else {
            print("⚠️ Refusing to sync a storybook outside the active account")
            return false
        }
        
        let bookRef = db.collection("users").document(userId)
            .collection("bookVersions").document(bookId)
        
        do {
            registerPendingBookSync(
                bookId: bookId,
                profileId: book.profileID.uuidString,
                firebaseUserId: userId
            )
            print("[CoverFlow] syncBook START bookId=\(bookId.prefix(28))… persistPages=\(book.pageItems.count) hasRenderedImages=\(renderedPageImages != nil) hasCoverInputs=\(coverInputs != nil)")
            // Build canonical version record first.
            let syncStart = Date()
            let baseRecord = BookVersionRecordFactory.fromPersistable(book, bookVersionId: bookId)
            let isLandscapeTrim = baseRecord.pageWidth > baseRecord.pageHeight
            var coverStoragePath: String?
            var coverURL: String?

            if let coverPDFOverride {
                let result = try await StorageService.shared.uploadBookCoverPDF(
                    coverPDFOverride,
                    bookId: bookId,
                    asUserId: userId
                )
                coverStoragePath = result.storagePath
                coverURL = result.downloadURL
            }

            // Landscape trim (11×8.5): AI cover (headshot → likeness; no headshot → non-human art). Title is painted in-image.
            if isLandscapeTrim, coverStoragePath == nil, let inputs = coverInputs {
                let svc = GeminiImageService()
                print("[CoverFlow] AI cover START trim=landscape bookId=\(bookId.prefix(28))… artStyleKey=\(inputs.artStyle.firestoreKey) hasHeadshot=\(inputs.headshot != nil) themesCount=\(inputs.memoryThemes.count) backCoverPitchLen=\(inputs.backCoverPitch.count) hasCanon=\(inputs.protagonistCanonLine?.isEmpty == false)")
                do {
                    guard let coverArt = try await svc.generateCoverIllustration(
                        headshot: inputs.headshot,
                        profileName: inputs.profileName,
                        ethnicity: inputs.ethnicity,
                        gender: inputs.gender,
                        memoryThemes: inputs.memoryThemes,
                        artStyle: inputs.artStyle,
                        customStyle: inputs.customArtStyleText,
                        printTitle: inputs.printTitle,
                        protagonistCanonLine: inputs.protagonistCanonLine
                    ) else {
                        print("⚠️ [CoverFlow] AI cover FRONT_NIL trim=landscape bookId=\(bookId.prefix(28))… (Gemini returned no image)")
                        throw NSError(domain: "MemoirAI", code: -2, userInfo: [NSLocalizedDescriptionKey: "generateCoverIllustration returned nil"])
                    }
                    var backCoverArt: UIImage?
                    do {
                        backCoverArt = try await svc.generateBackCoverIllustration(
                            frontCoverArt: coverArt,
                            headshot: inputs.headshot,
                            profileName: inputs.profileName,
                            ethnicity: inputs.ethnicity,
                            gender: inputs.gender,
                            memoryThemes: inputs.memoryThemes,
                            artStyle: inputs.artStyle,
                            customStyle: inputs.customArtStyleText
                        )
                    } catch {
                        print("⚠️ [CoverFlow] AI back cover FAILED trim=landscape bookId=\(bookId.prefix(28))… — \(error.localizedDescription)")
                    }
                    if backCoverArt == nil {
                        print("⚠️ [CoverFlow] AI back cover returned nil trim=landscape bookId=\(bookId.prefix(28))… (continuing with front only)")
                    }
                    if let coverPDFData = BookCoverRenderer.renderLuluPDF(
                        frontCoverArt: coverArt,
                        backCoverArt: backCoverArt,
                        profileName: inputs.profileName,
                        pageCount: book.pageItems.count,
                        frontTitle: inputs.printTitle,
                        backCoverPitch: inputs.backCoverPitch,
                        fontPreset: inputs.coverFontPreset,
                        useNativeFrontTitleOverlay: false
                    ) {
                        let result = try await StorageService.shared.uploadBookCoverPDF(coverPDFData, bookId: bookId, asUserId: userId)
                        coverStoragePath = result.storagePath
                        coverURL = result.downloadURL
                        print("✅ Landscape trim cover PDF generated and uploaded")
                    } else {
                        print("⚠️ [CoverFlow] Landscape cover PDF render failed after AI success bookId=\(bookId.prefix(28))…")
                    }
                } catch {
                    print("⚠️ [CoverFlow] AI cover FRONT_FAILED trim=landscape bookId=\(bookId.prefix(28))… — \(error.localizedDescription)")
                }
            }

            // Landscape (kids) fallback: first interior illustration as cover when Gemini path did not produce `coverURL`.
            // Without this, `isBookOrderable` stays false on device (PDF can still render) while simulator often succeeds on Gemini.
            if isLandscapeTrim, coverStoragePath == nil, let renderedPageImages {
                let firstIllustration: UIImage? = {
                    for (index, page) in baseRecord.pages.enumerated() {
                        if page.type == "illustration", index < renderedPageImages.count {
                            return renderedPageImages[index]
                        }
                    }
                    return nil
                }()
                let trimmedDisplay = book.bookDisplayTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let firstPageTitle = book.pageItems.first?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let resolvedTitle: String? = {
                    if !trimmedDisplay.isEmpty { return trimmedDisplay }
                    return firstPageTitle.isEmpty ? nil : firstPageTitle
                }()
                let artStyle = ArtStyle.resolvedFromStored(book.artStyle)
                let policy = CoverCopyPolicy(artStyle: artStyle, profileDisplayName: resolvedTitle ?? "Memoir")
                let trimmedPitch = book.backCoverPitch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let pitch = trimmedPitch.isEmpty
                    ? policy.fallbackBackCoverPitch(bookTitle: resolvedTitle ?? "Memoir")
                    : trimmedPitch
                let fontPreset = CoverFontPreset(rawValue: book.coverFontPreset ?? "") ?? policy.coverFontPreset()

                if let coverArt = firstIllustration {
                    let memoryThemesForBack = book.pageItems.prefix(8).compactMap { item in
                        item.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                    }.filter { !$0.isEmpty }
                    let backCoverSvc = GeminiImageService()
                    let backCoverArt = try? await backCoverSvc.generateBackCoverIllustration(
                        frontCoverArt: coverArt,
                        headshot: nil,
                        profileName: resolvedTitle ?? "Memoir",
                        ethnicity: nil,
                        gender: nil,
                        memoryThemes: memoryThemesForBack,
                        artStyle: artStyle
                    )
                    if let coverPDFData = BookCoverRenderer.renderLuluPDF(
                        frontCoverArt: coverArt,
                        backCoverArt: backCoverArt,
                        profileName: resolvedTitle ?? "Memoir",
                        pageCount: book.pageItems.count,
                        frontTitle: resolvedTitle,
                        backCoverPitch: pitch,
                        fontPreset: fontPreset,
                        useNativeFrontTitleOverlay: false
                    ) {
                        let result = try await StorageService.shared.uploadBookCoverPDF(coverPDFData, bookId: bookId, asUserId: userId)
                        coverStoragePath = result.storagePath
                        coverURL = result.downloadURL
                        print("✅ Landscape trim cover PDF generated and uploaded (illustration fallback)")
                    } else {
                        print("⚠️ Landscape Book cover render failed (illustration fallback path)")
                    }
                } else {
                    print("⚠️ Landscape Book cover generation skipped (no illustration found)")
                }
            }

            // Portrait trim: prefer Gemini + AI title when `coverInputs` are available.
            if !isLandscapeTrim, coverStoragePath == nil, let inputs = coverInputs {
                let svc = GeminiImageService()
                print("[CoverFlow] AI cover START trim=portrait bookId=\(bookId.prefix(28))… artStyleKey=\(inputs.artStyle.firestoreKey) hasHeadshot=\(inputs.headshot != nil) themesCount=\(inputs.memoryThemes.count) backCoverPitchLen=\(inputs.backCoverPitch.count) hasCanon=\(inputs.protagonistCanonLine?.isEmpty == false)")
                do {
                    guard let coverArt = try await svc.generateCoverIllustration(
                        headshot: inputs.headshot,
                        profileName: inputs.profileName,
                        ethnicity: inputs.ethnicity,
                        gender: inputs.gender,
                        memoryThemes: inputs.memoryThemes,
                        artStyle: inputs.artStyle,
                        customStyle: inputs.customArtStyleText,
                        printTitle: inputs.printTitle,
                        protagonistCanonLine: inputs.protagonistCanonLine
                    ) else {
                        print("⚠️ [CoverFlow] AI cover FRONT_NIL trim=portrait bookId=\(bookId.prefix(28))… (Gemini returned no image)")
                        throw NSError(domain: "MemoirAI", code: -2, userInfo: [NSLocalizedDescriptionKey: "generateCoverIllustration returned nil"])
                    }
                    var backCoverArt: UIImage?
                    do {
                        backCoverArt = try await svc.generateBackCoverIllustration(
                            frontCoverArt: coverArt,
                            headshot: inputs.headshot,
                            profileName: inputs.profileName,
                            ethnicity: inputs.ethnicity,
                            gender: inputs.gender,
                            memoryThemes: inputs.memoryThemes,
                            artStyle: inputs.artStyle,
                            customStyle: inputs.customArtStyleText
                        )
                    } catch {
                        print("⚠️ [CoverFlow] AI back cover FAILED trim=portrait bookId=\(bookId.prefix(28))… — \(error.localizedDescription)")
                    }
                    if backCoverArt == nil {
                        print("⚠️ [CoverFlow] AI back cover returned nil trim=portrait bookId=\(bookId.prefix(28))…")
                    }
                    if let coverPDFData = BookCoverRenderer.renderPortraitPDF(
                        frontCoverArt: coverArt,
                        backCoverArt: backCoverArt,
                        profileName: inputs.profileName,
                        pageCount: book.pageItems.count,
                        frontTitle: inputs.printTitle,
                        backCoverPitch: inputs.backCoverPitch,
                        fontPreset: inputs.coverFontPreset,
                        useNativeFrontTitleOverlay: false
                    ) {
                        let result = try await StorageService.shared.uploadBookCoverPDF(coverPDFData, bookId: bookId, asUserId: userId)
                        coverStoragePath = result.storagePath
                        coverURL = result.downloadURL
                        print("✅ Portrait Book AI cover PDF generated and uploaded")
                    } else {
                        print("⚠️ [CoverFlow] Portrait AI cover PDF render failed bookId=\(bookId.prefix(28))…")
                    }
                } catch {
                    print("⚠️ [CoverFlow] AI cover FRONT_FAILED trim=portrait bookId=\(bookId.prefix(28))… — \(error.localizedDescription)")
                }
            }

            // Portrait fallback: interior illustration as front art — native title overlay remains for readability (no AI title).
            if !isLandscapeTrim, coverStoragePath == nil, let renderedPageImages {
                let firstIllustration: UIImage? = {
                    for (index, page) in baseRecord.pages.enumerated() {
                        if page.type == "illustration", index < renderedPageImages.count {
                            return renderedPageImages[index]
                        }
                    }
                    return nil
                }()
                let trimmedDisplay = book.bookDisplayTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let firstPageTitle = book.pageItems.first?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let resolvedTitle: String? = {
                    if !trimmedDisplay.isEmpty { return trimmedDisplay }
                    return firstPageTitle.isEmpty ? nil : firstPageTitle
                }()
                let artStyle = ArtStyle.resolvedFromStored(book.artStyle)
                let policy = CoverCopyPolicy(artStyle: artStyle, profileDisplayName: resolvedTitle ?? "Memoir")
                let trimmedPitch = book.backCoverPitch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let pitch = trimmedPitch.isEmpty
                    ? policy.fallbackBackCoverPitch(bookTitle: resolvedTitle ?? "Memoir")
                    : trimmedPitch
                let fontPreset = CoverFontPreset(rawValue: book.coverFontPreset ?? "") ?? policy.coverFontPreset()

                if let coverArt = firstIllustration {
                    let memoryThemesForBack = book.pageItems.prefix(8).compactMap { item in
                        item.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                    }.filter { !$0.isEmpty }
                    let backCoverSvc = GeminiImageService()
                    let backCoverArt = try? await backCoverSvc.generateBackCoverIllustration(
                        frontCoverArt: coverArt,
                        headshot: nil,
                        profileName: resolvedTitle ?? "Memoir",
                        ethnicity: nil,
                        gender: nil,
                        memoryThemes: memoryThemesForBack,
                        artStyle: artStyle
                    )
                    if let coverPDFData = BookCoverRenderer.renderPortraitPDF(
                        frontCoverArt: coverArt,
                        backCoverArt: backCoverArt,
                        profileName: resolvedTitle ?? "Memoir",
                        pageCount: book.pageItems.count,
                        frontTitle: resolvedTitle,
                        backCoverPitch: pitch,
                        fontPreset: fontPreset,
                        useNativeFrontTitleOverlay: false
                    ) {
                        let result = try await StorageService.shared.uploadBookCoverPDF(coverPDFData, bookId: bookId, asUserId: userId)
                        coverStoragePath = result.storagePath
                        coverURL = result.downloadURL
                        print("✅ Portrait Book cover PDF generated and uploaded (illustration fallback; no native front title overlay)")
                    } else {
                        print("⚠️ Portrait Book cover render failed (illustration fallback path)")
                    }
                } else {
                    print("⚠️ Portrait Book cover generation skipped (no illustration found)")
                }
            }

            var uploadedPages: [BookVersionPageRecord] = []
            var totalPngBytes = 0
            
            for (index, page) in baseRecord.pages.enumerated() {
                var updatedPage = page

                let recoveredFreeformImage: UIImage?
                if renderedPageProvider == nil,
                   renderedPageImages == nil,
                   index < book.pageItems.count,
                   let document = book.pageItems[index].freeformDocument {
                    let memoryID = book.pageItems[index].url
                        .flatMap(URL.init(string:))
                        .flatMap(MemoryLinks.parseMemoryDeepLink)
                    recoveredFreeformImage = await MainActor.run {
                        BookPagePrintRenderer.render(
                            document: document,
                            pixelSize: CGSize(
                                width: CGFloat(baseRecord.pageWidth) * 2,
                                height: CGFloat(baseRecord.pageHeight) * 2
                            ),
                            memoryID: memoryID
                        )
                    }
                } else {
                    recoveredFreeformImage = nil
                }

                let renderedImage: UIImage
                if let renderedPageProvider,
                   let streamedImage = await renderedPageProvider(index) {
                    renderedImage = streamedImage
                } else {
                    renderedImage = {
                    // 1. Prefer on-device rendered images (text + illustration) for full visual parity
                    if let renderedPageImages, index < renderedPageImages.count {
                        return renderedPageImages[index]
                    }
                    // 2. Process-death retry: rebuild the editable page from its persisted layers.
                    if let recoveredFreeformImage {
                        return recoveredFreeformImage
                    }
                    // 3. Fallback: use persisted image data for illustrations (e.g. legacy migration)
                    if index < book.pageItems.count,
                       let imageData = book.pageItems[index].imageData,
                       let image = UIImage(data: imageData) {
                        return image
                    }
                    // 4. Fallback: render text pages from content (required for Cloud Function; never skip)
                    if page.type == "textPage" {
                        let text = page.textContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return fallbackTextPageImage(
                            text: text.isEmpty ? " " : text,
                            title: page.title,
                            subtitle: page.subtitle,
                            widthPt: CGFloat(baseRecord.pageWidth),
                            heightPt: CGFloat(baseRecord.pageHeight)
                        )
                    }
                    // 5. Last resort: blank placeholder (ensures every page has an artifact)
                    print("⚠️ No image for page \(index) (type=\(page.type)); using blank placeholder")
                    return fallbackTextPageImage(
                        text: " ",
                        title: nil,
                        subtitle: nil,
                        widthPt: CGFloat(baseRecord.pageWidth),
                        heightPt: CGFloat(baseRecord.pageHeight)
                    )
                    }()
                }

                let artifacts = try await StorageService.shared.uploadRenderedBookPageArtifacts(
                    renderedImage,
                    bookId: bookId,
                    pageIndex: index,
                    isKidsBook: baseRecord.pageWidth > baseRecord.pageHeight,
                    asUserId: userId
                )
                totalPngBytes += artifacts.png.bytes

                var freeformDocumentStoragePath: String?
                var freeformDocumentURL: String?
                if index < book.pageItems.count,
                   let document = book.pageItems[index].freeformDocument {
                    let documentData = try JSONEncoder().encode(document)
                    let uploaded = try await StorageService.shared.uploadFreeformBookPageDocument(
                        documentData,
                        bookId: bookId,
                        pageIndex: index,
                        asUserId: userId
                    )
                    freeformDocumentStoragePath = uploaded.storagePath
                    freeformDocumentURL = uploaded.downloadURL
                }

                updatedPage = BookVersionPageRecord(
                    pageIndex: page.pageIndex,
                    type: page.type,
                    memoryId: page.memoryId,
                    memoryCreatedAt: page.memoryCreatedAt,
                    title: page.title,
                    subtitle: page.subtitle,
                    textContent: page.textContent,
                    imageStoragePath: artifacts.jpeg.storagePath,
                    imageURL: artifacts.jpeg.downloadURL,
                    renderedPageStoragePath: artifacts.png.storagePath,
                    renderedPageURL: artifacts.png.downloadURL,
                    renderedPageFormat: "png",
                    renderedPixelWidth: artifacts.png.pixelWidth,
                    renderedPixelHeight: artifacts.png.pixelHeight,
                    renderedChecksum: artifacts.png.checksum,
                    renderedBytes: artifacts.png.bytes,
                    freeformDocumentStoragePath: freeformDocumentStoragePath,
                    freeformDocumentURL: freeformDocumentURL,
                    createdAt: page.createdAt
                )
                uploadedPages.append(updatedPage)
            }
            
            let canonicalRecord = BookVersionRecord(
                bookVersionId: baseRecord.bookVersionId,
                profileId: baseRecord.profileId,
                createdAt: baseRecord.createdAt,
                memoryOrder: baseRecord.memoryOrder,
                pageCount: uploadedPages.count,
                artStyle: baseRecord.artStyle,
                orientation: baseRecord.orientation,
                pageWidth: baseRecord.pageWidth,
                pageHeight: baseRecord.pageHeight,
                trimSizeInches: baseRecord.trimSizeInches,
                layoutVersion: baseRecord.layoutVersion,
                printTitle: baseRecord.printTitle,
                backCoverPitch: baseRecord.backCoverPitch,
                coverFontPreset: baseRecord.coverFontPreset,
                pdfStoragePath: nil,
                pdfURL: nil,
                pdfPageCount: nil,
                coverStoragePath: coverStoragePath,
                coverURL: coverURL,
                coverArtRevision: nil,
                syncedAt: Date(),
                renderStatus: BookRenderStatus.pending.rawValue,
                renderedAt: nil,
                renderError: nil,
                renderAttemptCount: 0,
                renderDurationMs: Int(Date().timeIntervalSince(syncStart) * 1000),
                totalPngBytes: totalPngBytes,
                pdfBytes: nil,
                source: baseRecord.source,
                pages: uploadedPages,
                bookDisplayName: baseRecord.bookDisplayName,
                userHandle: baseRecord.userHandle,
                bookSeq: baseRecord.bookSeq
            )
            
            try await bookRef.setData(canonicalRecord.toFirestoreData(), merge: true)
            print("[CoverFlow] syncBook FULL setData DONE bookId=\(bookId.prefix(28))… pages=\(uploadedPages.count) hasCoverURL=\(coverURL != nil) renderStatus=\(canonicalRecord.renderStatus)")
            
            // Legacy metadata mirror for existing dashboards/query paths.
            let legacyBookRef = db.collection("users").document(userId)
                .collection("books").document(bookId)
            try await legacyBookRef.setData([
                "profileID": book.profileID.uuidString,
                "artStyle": book.artStyle,
                "createdAt": book.createdAt,
                "pageCount": uploadedPages.count,
                "bookVersionRef": bookId,
                "syncedAt": FieldValue.serverTimestamp()
            ], merge: true)

            if Auth.auth().currentUser?.isAnonymous == true {
                UserDefaults.standard.set(true, forKey: MemoirPersistenceUserDefaults.suggestAccountLinkAfterBook)
            }
            
            // Keep `pendingBookSync` until the server PDF job is actually triggered (or we record a render retry).
            let renderResponse = await invokeBookRenderFunction(bookVersionId: bookId)
            if renderResponse != nil {
                clearPendingBookSync(bookId: bookId)
            } else {
                incrementPendingBookRenderRetry(bookId: bookId)
            }
            
            print("✅ Synced canonical book version \(bookId.prefix(28))… to Firebase with \(uploadedPages.count) pages and \(totalPngBytes) PNG bytes (layout: \(Int(baseRecord.pageWidth))x\(Int(baseRecord.pageHeight))pt)")
            return true
        } catch {
            print("[CoverFlow] syncBook ERROR bookId=\(bookId.prefix(28))… — \(error.localizedDescription)")
            print("❌ Failed to sync book to Firebase: \(error)")
            return false
        }
    }

    private func fallbackTextPageImage(
        text: String,
        title: String?,
        subtitle: String?,
        widthPt: CGFloat,
        heightPt: CGFloat
    ) -> UIImage {
        let size = CGSize(width: max(widthPt, 1), height: max(heightPt, 1))
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            UIColor(red: 250.0 / 255.0, green: 248.0 / 255.0, blue: 243.0 / 255.0, alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            var y: CGFloat = size.height * 0.12
            let margin = size.width * 0.1
            let drawWidth = size.width - (margin * 2)

            if let title, !title.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: size.height * 0.045, weight: .semibold),
                    .foregroundColor: UIColor.black
                ]
                let rect = CGRect(x: margin, y: y, width: drawWidth, height: size.height * 0.12)
                title.draw(in: rect, withAttributes: attrs)
                y += size.height * 0.085
            }

            if let subtitle, !subtitle.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: size.height * 0.028, weight: .regular),
                    .foregroundColor: UIColor.darkGray
                ]
                let rect = CGRect(x: margin, y: y, width: drawWidth, height: size.height * 0.08)
                subtitle.draw(in: rect, withAttributes: attrs)
                y += size.height * 0.075
            }

            let bodyStyle = NSMutableParagraphStyle()
            bodyStyle.lineBreakMode = .byWordWrapping
            bodyStyle.alignment = .left
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size.height * 0.028, weight: .regular),
                .foregroundColor: UIColor.black,
                .paragraphStyle: bodyStyle
            ]

            let bodyRect = CGRect(
                x: margin,
                y: y,
                width: drawWidth,
                height: size.height - y - (size.height * 0.08)
            )
            (text as NSString).draw(in: bodyRect, withAttributes: bodyAttrs)
        }
    }
    
    /// Lightweight book sync without images (faster)
    func syncBookMetadata(_ book: PersistableStorybook, bookId: String) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let bookRef = db.collection("users").document(userId)
            .collection("bookVersions").document(bookId)
        
        do {
            let layout = BookVersionLayoutFactory.layout(forArtStyle: book.artStyle)
            let printSpec = BookPrintSpec.forArtStyle(book.artStyle)
            let memoryOrder = book.pageItems.compactMap { BookVersionRecordFactory.memoryId(from: $0.url) }
            let bookData: [String: Any] = [
                "bookVersionId": bookId,
                "profileId": book.profileID.uuidString,
                "artStyle": book.artStyle,
                "orientation": layout.orientation,
                "pageWidth": layout.pageWidth,
                "pageHeight": layout.pageHeight,
                "trimSizeInches": printSpec.trimSizeInches,
                "layoutVersion": printSpec.layoutVersion,
                "renderStatus": BookRenderStatus.pending.rawValue,
                "renderAttemptCount": 0,
                "memoryOrder": memoryOrder,
                "pageCount": book.pageItems.count,
                "source": BookVersionSource.storyGeneration.rawValue,
                "createdAt": Timestamp(date: book.createdAt),
                "syncedAt": FieldValue.serverTimestamp()
            ]
            
            try await bookRef.setData(bookData, merge: true)
            print("✅ Synced book metadata for \(bookId.prefix(28))…")
        } catch {
            print("❌ Failed to sync book metadata: \(error)")
        }
    }
    
    /// Fetch all canonical book versions for a profile, newest first.
    func fetchBookVersions(profileID: UUID) async -> [BookVersionRecord] {
        guard let userId = Auth.auth().currentUser?.uid else { return [] }
        // Avoid composite-index requirement by using createdAt ordering only and profile client filter.
        return await fetchBookVersionsClientFilter(profileID: profileID, userId: userId)
    }
    
    /// Fetch latest canonical book version for a profile.
    func fetchLatestBookVersion(profileID: UUID) async -> BookVersionRecord? {
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        // Avoid composite-index requirement by using createdAt ordering only and profile client filter.
        return await fetchLatestBookVersionClientFilter(profileID: profileID, userId: userId)
    }
    
    /// Fetch one canonical book version by exact ID (admin/order retrieval path).
    func fetchBookVersion(bookVersionId: String) async -> BookVersionRecord? {
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        
        let docRef = db.collection("users").document(userId)
            .collection("bookVersions")
            .document(bookVersionId)
        
        do {
            let snapshot = try await docRef.getDocument()
            guard let data = snapshot.data() else { return nil }
            return BookVersionRecord.fromFirestoreData(data)
        } catch {
            print("❌ Failed to fetch book version \(bookVersionId): \(error)")
            return nil
        }
    }

    /// Return canonical PDF URL if already rendered, or trigger cloud packaging and poll until ready.
    func fetchOrGenerateBookPDF(
        bookVersionId: String,
        forceRegenerate: Bool = false,
        timeoutSeconds: Int = 30
    ) async -> String? {
        if !forceRegenerate,
           let current = await fetchBookVersion(bookVersionId: bookVersionId),
           current.renderStatus == BookRenderStatus.rendered.rawValue,
           let pdfURL = current.pdfURL {
            return pdfURL
        }

        let response = await invokeBookRenderFunction(bookVersionId: bookVersionId, forceRegenerate: forceRegenerate)
        if response?.status == BookRenderStatus.rendered.rawValue, let ready = response?.pdfURL {
            return ready
        }

        let pollIntervalNs: UInt64 = 2_000_000_000
        let maxPolls = max(1, timeoutSeconds / 2)
        for _ in 0..<maxPolls {
            try? await Task.sleep(nanoseconds: pollIntervalNs)
            if let updated = await fetchBookVersion(bookVersionId: bookVersionId),
               updated.renderStatus == BookRenderStatus.rendered.rawValue,
               let pdfURL = updated.pdfURL {
                return pdfURL
            }
        }
        return nil
    }

    /// Triggers server-side PDF packaging from already uploaded PNG pages.
    func invokeBookRenderFunction(
        bookVersionId: String,
        forceRegenerate: Bool = false
    ) async -> BookRenderFunctionResponse? {
        await invokeBookRenderFunction(bookVersionId: bookVersionId, forceRegenerate: forceRegenerate, didRetryCoverRepair: false)
    }

    private func invokeBookRenderFunction(
        bookVersionId: String,
        forceRegenerate: Bool,
        didRetryCoverRepair: Bool
    ) async -> BookRenderFunctionResponse? {
        guard let functionURL = bookRenderFunctionURL else {
            print("⚠️ BOOK_RENDER_FUNCTION_URL missing in Info.plist, skipping cloud PDF trigger")
            return nil
        }
        guard let user = Auth.auth().currentUser else {
            print("⚠️ Cannot trigger render - user not signed in")
            return nil
        }

        do {
            let idToken = try await user.getIDToken()
            var request = URLRequest(url: functionURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "bookVersionId": bookVersionId,
                "forceRegenerate": forceRegenerate
            ])
            request.timeoutInterval = 300
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 300
            config.timeoutIntervalForResource = 300
            let session = URLSession(configuration: config)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return nil
            }
            if http.statusCode == 409, !didRetryCoverRepair {
                print("⚠️ Render function 409 (missing cover / precondition); repairing cover then retrying once")
                _ = await ensureCoverDesignExistsIfMissing(
                    bookVersionId: bookVersionId,
                    respectSessionBudget: false
                )
                return await invokeBookRenderFunction(
                    bookVersionId: bookVersionId,
                    forceRegenerate: forceRegenerate,
                    didRetryCoverRepair: true
                )
            }
            guard (200...299).contains(http.statusCode) else {
                print("❌ Render function failed with HTTP \(http.statusCode)")
                return nil
            }

            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if let s = json?["status"] as? String, s == "cover_precondition_exhausted" {
                let err = (json?["renderError"] as? String) ?? (json?["message"] as? String) ?? ""
                print("❌ PDF render: cover precondition exhausted (server) — \(err)")
                return nil
            }
            return BookRenderFunctionResponse(
                status: json?["status"] as? String,
                pdfURL: json?["pdfURL"] as? String,
                pdfStoragePath: json?["pdfStoragePath"] as? String,
                renderDurationMs: json?["renderDurationMs"] as? Int,
                pdfBytes: json?["pdfBytes"] as? Int,
                message: json?["message"] as? String
            )
        } catch {
            print("❌ Failed invoking render function: \(error.localizedDescription)")
            return nil
        }
    }

    /// Incremental artifact backfill for legacy versions missing rendered page PNGs.
    func backfillBookVersionArtifacts(profileID: UUID? = nil, limit: Int = 20) async -> Int {
        guard let userId = Auth.auth().currentUser?.uid else { return 0 }

        var query: Query = db.collection("users").document(userId)
            .collection("bookVersions")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        if let profileID {
            query = query.whereField("profileId", isEqualTo: profileID.uuidString)
        }

        do {
            let snapshot = try await query.getDocuments()
            let candidates = snapshot.documents.compactMap { BookVersionRecord.fromFirestoreData($0.data()) }
                .filter { record in
                    record.pages.contains(where: { $0.renderedPageURL == nil }) ||
                    record.renderStatus != BookRenderStatus.rendered.rawValue ||
                    record.pdfURL == nil
                }

            var updated = 0
            for record in candidates {
                if await invokeBookRenderFunction(bookVersionId: record.bookVersionId) != nil {
                    updated += 1
                }
            }
            return updated
        } catch {
            if let profileID, isMissingFirestoreCompositeIndexError(error) {
                print("⚠️ backfillBookVersionArtifacts index missing; retrying with client-side profile filter")
                return await backfillBookVersionArtifactsClientFilter(profileID: profileID, userId: userId, limit: limit)
            }
            print("❌ Failed backfill query: \(error.localizedDescription)")
            return 0
        }
    }

    private func backfillBookVersionArtifactsClientFilter(profileID: UUID, userId: String, limit: Int) async -> Int {
        let ref = db.collection("users").document(userId).collection("bookVersions")
        do {
            let snapshot = try await ref.order(by: "createdAt", descending: true).limit(to: max(80, limit * 4)).getDocuments()
            let wanted = profileID.uuidString
            let candidates = snapshot.documents.compactMap { BookVersionRecord.fromFirestoreData($0.data()) }
                .filter { $0.profileId == wanted }
                .prefix(limit * 2)
            var updated = 0
            for record in candidates {
                if record.pages.contains(where: { $0.renderedPageURL == nil }) ||
                    record.renderStatus != BookRenderStatus.rendered.rawValue ||
                    record.pdfURL == nil {
                    if await invokeBookRenderFunction(bookVersionId: record.bookVersionId) != nil {
                        updated += 1
                    }
                }
            }
            return updated
        } catch {
            print("❌ backfillBookVersionArtifactsClientFilter failed: \(error.localizedDescription)")
            return 0
        }
    }

    // MARK: - Cover Design Backfill

    /// One-time backfill for existing books: regenerate cover PDFs with upgraded prompt/composition logic.
    func backfillCoverDesigns(profileID: UUID? = nil, limit: Int = 20) async -> Int {
        guard let userId = Auth.auth().currentUser?.uid else { return 0 }

        var query: Query = db.collection("users").document(userId)
            .collection("bookVersions")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        if let profileID {
            query = query.whereField("profileId", isEqualTo: profileID.uuidString)
        }

        do {
            let snapshot = try await query.getDocuments()
            let records = snapshot.documents.compactMap { BookVersionRecord.fromFirestoreData($0.data()) }
            var updated = 0
            for record in records {
                if await regenerateCoverDesign(for: record, userId: userId) {
                    updated += 1
                }
            }
            return updated
        } catch {
            if let profileID, isMissingFirestoreCompositeIndexError(error) {
                return await backfillCoverDesignsClientFilter(profileID: profileID, userId: userId, limit: limit)
            }
            print("❌ backfillCoverDesigns failed: \(error.localizedDescription)")
            return 0
        }
    }

    private func backfillCoverDesignsClientFilter(profileID: UUID, userId: String, limit: Int) async -> Int {
        let ref = db.collection("users").document(userId).collection("bookVersions")
        do {
            let snapshot = try await ref.order(by: "createdAt", descending: true).limit(to: max(80, limit * 4)).getDocuments()
            let wanted = profileID.uuidString
            let records = snapshot.documents.compactMap { BookVersionRecord.fromFirestoreData($0.data()) }
                .filter { $0.profileId == wanted }
                .prefix(limit)
            var updated = 0
            for record in records {
                if await regenerateCoverDesign(for: record, userId: userId) {
                    updated += 1
                }
            }
            return updated
        } catch {
            print("❌ backfillCoverDesignsClientFilter failed: \(error.localizedDescription)")
            return 0
        }
    }

    // MARK: - Stuck cover heal (gallery + post-sign-in)

    private func handleAuthChangeForStuckCoverHeal(user: User?) async {
        if user == nil {
            lastPostSignInCoverBackfillUserId = nil
            return
        }
        guard let u = user else { return }
        if lastPostSignInCoverBackfillUserId == u.uid { return }
        lastPostSignInCoverBackfillUserId = u.uid
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard Auth.auth().currentUser?.uid == u.uid else { return }
        await runPostSignInStuckCoverHeal()
    }

    /// When `respectSessionBudget` is `true` (e.g. gallery auto-heal), at most `maxCoverHealAttemptsPerVersionPerSession` invocations per book per app run.
    private func clearCoverHealSessionSlot(for bookVersionId: String) {
        coverHealBudgetLock.lock()
        coverHealSessionAttempts.removeValue(forKey: bookVersionId)
        coverHealBudgetLock.unlock()
    }

    private func canConsumeCoverHealSessionAttempt(for bookVersionId: String) -> Bool {
        coverHealBudgetLock.lock()
        defer { coverHealBudgetLock.unlock() }
        let c = coverHealSessionAttempts[bookVersionId, default: 0]
        guard c < Self.maxCoverHealAttemptsPerVersionPerSession else { return false }
        coverHealSessionAttempts[bookVersionId] = c + 1
        return true
    }

    /// One-shot: after the user is signed in, nudge any `rendered`+no-cover books that `ensure` could not touch anonymously.
    private func runPostSignInStuckCoverHeal() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        do {
            let snap = try await db.collection("users").document(userId)
                .collection("bookVersions")
                .limit(to: 50)
                .getDocuments()
            for doc in snap.documents {
                let data = doc.data()
                guard let rec = BookVersionRecord.fromFirestoreData(data) else { continue }
                guard StorybookCloudApplyPolicy.isCoverStuckFinalizingState(rec) else { continue }
                let bid = rec.bookVersionId
                Task.detached(priority: .utility) { [weak self] in
                    _ = await self?.ensureCoverDesignExistsIfMissing(
                        bookVersionId: bid,
                        respectSessionBudget: false
                    )
                }
            }
        } catch {
            print("⚠️ runPostSignInStuckCoverHeal: \(error.localizedDescription)")
        }
    }

    /// If this book version exists in Firestore but has no `coverURL` yet, run the Gemini → PDF → Storage path used by cover backfill.
    /// Returns `true` without regenerating when a cover is already present (safe if initial sync is still racing).
    /// - Parameter respectSessionBudget: When `true`, gallery-style auto-heal throttles repeated work per `bookVersionId` per app session.
    func ensureCoverDesignExistsIfMissing(
        bookVersionId: String,
        respectSessionBudget: Bool = true
    ) async -> Bool {
        guard let userId = Auth.auth().currentUser?.uid else { return false }
        let docRef = db.collection("users").document(userId).collection("bookVersions").document(bookVersionId)
        do {
            let snapshot = try await docRef.getDocument()
            guard snapshot.exists, let data = snapshot.data(), let record = BookVersionRecord.fromFirestoreData(data) else {
                return false
            }
            let trimmed = record.coverURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return true
            }
            if respectSessionBudget, !canConsumeCoverHealSessionAttempt(for: bookVersionId) {
                print("⚠️ cover heal session budget hit for id=\(bookVersionId.prefix(20))… — skipping")
                return false
            }
            return await regenerateCoverDesign(for: record, userId: userId)
        } catch {
            print("ensureCoverDesignExistsIfMissing failed: \(error.localizedDescription)")
            return false
        }
    }

    private func regenerateCoverDesign(for record: BookVersionRecord, userId: String) async -> Bool {
        guard record.pageCount > 0 else { return false }

        let title = record.printTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (record.printTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Memoir")
            : ((record.pages.first?.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? (record.pages.first?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Memoir")
                : "Memoir")

        let artStyle = ArtStyle.resolvedFromStored(record.artStyle)
        let policy = CoverCopyPolicy(artStyle: artStyle, profileDisplayName: title)
        let pitch = record.backCoverPitch?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (record.backCoverPitch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            : policy.fallbackBackCoverPitch(bookTitle: title)
        let fontPreset = CoverFontPreset(rawValue: record.coverFontPreset ?? "") ?? policy.coverFontPreset()
        let themes = rankedCoverSignals(from: record.pages, maxCount: 5)

        let svc = GeminiImageService()
        print("[CoverFlow] AI cover START regenerateCoverDesign bookId=\(record.bookVersionId.prefix(28))… artStyleKey=\(artStyle.firestoreKey) trim=\(record.pageWidth > record.pageHeight ? "landscape" : "portrait")")
        let frontCoverArt: UIImage
        do {
            guard let img = try await svc.generateCoverIllustration(
                headshot: nil,
                profileName: title,
                ethnicity: nil,
                gender: nil,
                memoryThemes: themes,
                artStyle: artStyle,
                customStyle: nil,
                printTitle: title,
                protagonistCanonLine: nil
            ) else {
                print("⚠️ [CoverFlow] regenerateCoverDesign FRONT_NIL bookId=\(record.bookVersionId.prefix(28))…")
                return false
            }
            frontCoverArt = img
        } catch {
            print("⚠️ [CoverFlow] regenerateCoverDesign FRONT_FAILED bookId=\(record.bookVersionId.prefix(28))… — \(error.localizedDescription)")
            return false
        }

        var backCoverArt: UIImage?
        do {
            backCoverArt = try await svc.generateBackCoverIllustration(
                frontCoverArt: frontCoverArt,
                headshot: nil,
                profileName: title,
                ethnicity: nil,
                gender: nil,
                memoryThemes: themes,
                artStyle: artStyle,
                customStyle: nil
            )
            if backCoverArt == nil {
                print("⚠️ [CoverFlow] regenerateCoverDesign back cover returned nil bookId=\(record.bookVersionId.prefix(28))…")
            }
        } catch {
            print("⚠️ [CoverFlow] regenerateCoverDesign BACK_FAILED bookId=\(record.bookVersionId.prefix(28))… — \(error.localizedDescription)")
        }

        let pdfData: Data?
        if record.pageWidth > record.pageHeight {
            pdfData = BookCoverRenderer.renderLuluPDF(
                frontCoverArt: frontCoverArt,
                backCoverArt: backCoverArt,
                profileName: title,
                pageCount: record.pageCount,
                frontTitle: title,
                backCoverPitch: pitch,
                fontPreset: fontPreset,
                useNativeFrontTitleOverlay: false
            )
        } else {
            pdfData = BookCoverRenderer.renderPortraitPDF(
                frontCoverArt: frontCoverArt,
                backCoverArt: backCoverArt,
                profileName: title,
                pageCount: record.pageCount,
                frontTitle: title,
                backCoverPitch: pitch,
                fontPreset: fontPreset,
                useNativeFrontTitleOverlay: false
            )
        }

        guard let pdfData else { return false }
        do {
            let uploaded = try await StorageService.shared.uploadBookCoverPDF(pdfData, bookId: record.bookVersionId, asUserId: userId)
            let docRef = db.collection("users").document(userId).collection("bookVersions").document(record.bookVersionId)
            try await docRef.setData([
                "coverStoragePath": uploaded.storagePath,
                "coverURL": uploaded.downloadURL,
                "coverArtRevision": FieldValue.increment(Int64(1)),
                "syncedAt": FieldValue.serverTimestamp()
            ], merge: true)
            if let updated = await fetchBookVersion(bookVersionId: record.bookVersionId) {
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .bookCoverBackfillComplete,
                        object: nil,
                        userInfo: ["bookVersionId": record.bookVersionId, "record": updated]
                    )
                }
            }
            return true
        } catch {
            print("❌ regenerateCoverDesign failed for \(record.bookVersionId): \(error.localizedDescription)")
            return false
        }
    }

    private static let coverSignalStopWords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "from", "into", "about", "have", "has", "had",
        "were", "was", "are", "our", "your", "their", "them", "they", "then", "than", "when", "where",
        "what", "which", "while", "after", "before", "over", "under", "through", "around", "very",
        "just", "really", "also", "story", "memory", "memoir", "page"
    ]

    private func rankedCoverSignals(from pages: [BookVersionPageRecord], maxCount: Int) -> [String] {
        struct Signal {
            var score: Int
            var recency: Int
            var display: String
        }
        var titleStats: [String: Signal] = [:]
        var tokenStats: [String: Signal] = [:]
        for (index, page) in pages.sorted(by: { $0.pageIndex < $1.pageIndex }).enumerated() {
            if let title = page.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                let key = title.lowercased()
                if var existing = titleStats[key] {
                    existing.score += 3
                    existing.recency = max(existing.recency, index)
                    titleStats[key] = existing
                } else {
                    titleStats[key] = Signal(score: 3, recency: index, display: title)
                }
            }
            if let text = page.textContent {
                for token in coverKeywordTokens(from: text) {
                    if var existing = tokenStats[token] {
                        existing.score += 1
                        existing.recency = max(existing.recency, index)
                        tokenStats[token] = existing
                    } else {
                        tokenStats[token] = Signal(score: 1, recency: index, display: token.capitalized)
                    }
                }
            }
        }

        let sortedTitles = titleStats.values.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.recency != $1.recency { return $0.recency > $1.recency }
            return $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending
        }
        let sortedTokens = tokenStats.values.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.recency != $1.recency { return $0.recency > $1.recency }
            return $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending
        }

        var selected: [String] = []
        var seen = Set<String>()
        for stat in sortedTitles {
            let key = stat.display.lowercased()
            if seen.insert(key).inserted { selected.append(stat.display) }
            if selected.count >= maxCount { return selected }
        }
        for stat in sortedTokens where stat.score >= 2 {
            let key = stat.display.lowercased()
            if seen.insert(key).inserted { selected.append(stat.display) }
            if selected.count >= maxCount { break }
        }
        return selected
    }

    private func coverKeywordTokens(from text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !Self.coverSignalStopWords.contains($0) }
    }
    
    // MARK: - Hydrate local store from Firestore

    /// Imports missing memories and reconciles server-owned transcription state for existing rows.
    @MainActor
    func hydrateMemoriesFromFirestoreIfStoreEmpty(context: NSManagedObjectContext) async {
        guard let userId = Auth.auth().currentUser?.uid,
              !AuthenticationService.shared.isDeletingAccount else {
            print("⚠️ Firestore hydrate skipped — not signed in")
            return
        }

        await retryPendingMemoryDeletions(firebaseUserId: userId)

        let ref = db.collection("users").document(userId).collection("memories")
        let snapshot: QuerySnapshot
        do {
            snapshot = try await ref.getDocuments()
        } catch {
            print("❌ Firestore hydrate: list memories failed — \(error.localizedDescription)")
            return
        }

        guard Auth.auth().currentUser?.uid == userId,
              !AuthenticationService.shared.isDeletingAccount,
              !UserDefaults.standard.bool(forKey: AccountLocalCleanupCoordinator.pendingKey),
              !AccountCloudDataPolicy.isDeletionBarrierActive(userID: userId) else {
            print("⚠️ Firestore hydrate discarded — account session changed")
            return
        }

        guard !snapshot.documents.isEmpty else { return }

        let pendingMemoryIDs = memorySyncPersistenceLock.withLock {
            Set(loadPendingMemorySyncRecords().compactMap { record in
                record.firebaseUserId == userId ? record.memoryId : nil
            })
        }

        print("📥 Reconciling \(snapshot.documents.count) memories from Firestore…")

        for doc in snapshot.documents {
            guard let memoryUUID = UUID(uuidString: doc.documentID) else { continue }
            guard !pendingMemoryIDs.contains(doc.documentID) else {
                print("⏭️ Firestore hydrate preserved pending local edit for \(doc.documentID.prefix(8))…")
                continue
            }
            guard !isMemoryDeletionPending(memoryId: memoryUUID, firebaseUserId: userId) else {
                continue
            }

            let existsRequest = MemoryEntry.fetchRequest()
            existsRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "id == %@", memoryUUID as CVarArg),
                NSPredicate(format: "firebaseUserId == %@", userId)
            ])
            existsRequest.fetchLimit = 1

            let data = doc.data()
            let existingEntry = try? context.fetch(existsRequest).first
            let entry = existingEntry ?? MemoryEntry(context: context)
            entry.id = memoryUUID
            entry.firebaseUserId = userId
            entry.prompt = data["prompt"] as? String
            let remoteVersion = (data["transcriptionVersion"] as? NSNumber)?.int32Value ?? 0
            let remoteStatus = data["transcriptionStatus"] as? String
            let localNeedsCompletion = remoteStatus == "completed" && entry.transcriptionStatus != "completed"
            if existingEntry == nil || remoteVersion >= entry.transcriptionVersion || localNeedsCompletion {
                entry.transcriptionRawText = data["transcriptionRaw"] as? String
                entry.transcriptionStatus = remoteStatus
                entry.transcriptionLanguage = data["transcriptionLanguage"] as? String
                entry.transcriptionModel = data["transcriptionModel"] as? String
                entry.transcriptionVersion = remoteVersion
                if let transcriptionTimestamp = data["transcriptionUpdatedAt"] as? Timestamp {
                    entry.transcriptionUpdatedAt = transcriptionTimestamp.dateValue()
                }
                if entry.transcriptionEditedText == nil {
                    entry.transcriptionEditedText = data["transcriptionEdited"] as? String
                    entry.text = entry.transcriptionEditedText ?? (data["transcription"] as? String) ?? ""
                }
            }
            entry.chapter = data["chapter"] as? String
            entry.characterDetails = data["characterDetails"] as? String
            if let ts = data["createdAt"] as? Timestamp {
                entry.createdAt = ts.dateValue()
            } else {
                entry.createdAt = Date()
            }
            if let pidStr = data["profileID"] as? String, let pid = UUID(uuidString: pidStr) {
                entry.profileID = pid
            }

            let existingLocalAudioURL = entry.audioFileURL
                .flatMap(URL.init(string:))
                .flatMap { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            if entry.audioData == nil,
               existingLocalAudioURL == nil,
               let urlStr = data["audioURL"] as? String,
               let url = URL(string: urlStr),
               let scheme = url.scheme?.lowercased(),
               scheme == "https" {
                // Keep the private cloud reference. Download on playback instead of
                // yielding during hydration and racing account deletion/session changes.
                entry.audioFileURL = url.absoluteString
            }
        }

        do {
            try context.save()
            print("✅ Firestore memory hydrate saved to Core Data")
            NotificationCenter.default.post(name: .memoriesHydratedFromFirestore, object: nil)
        } catch {
            print("❌ Firestore hydrate: Core Data save failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Batch Migration
    
    /// Migrate all existing memories to Firebase (one-time operation)
    func migrateExistingMemories(_ memories: [MemoryEntry]) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ Cannot migrate - user not signed in")
            return
        }
        
        print("📤 Starting migration of \(memories.count) memories to Firebase...")
        
        for (index, memory) in memories.enumerated() {
            await syncMemory(memory)
            print("📤 Migrated \(index + 1)/\(memories.count) memories")
        }
        
        // Mark migration as complete
        let key = migrationCompletionKey(for: userId)
        UserDefaults.standard.set(true, forKey: key)
        print("✅ Migration complete for \(userId.prefix(8))…")
    }
    
    /// Check if migration has been completed
    var isMigrationComplete: Bool {
        guard let userId = Auth.auth().currentUser?.uid else { return false }
        let key = migrationCompletionKey(for: userId)
        return UserDefaults.standard.bool(forKey: key)
    }
    
    // MARK: - Profile Sync
    
    /// Sync user profile to Firebase (updates user document with profile info)
    func syncProfile(_ profile: Profile) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Update user document with profile info (for easy identification)
        let userRef = db.collection("users").document(userId)
        
        do {
            var userData: [String: Any] = [
                "profileName": profile.name,
                "profileID": profile.id.uuidString,
                "lastActiveAt": FieldValue.serverTimestamp()
            ]
            
            if let birthdate = profile.birthdate {
                userData["profileBirthdate"] = birthdate
            }
            
            try await userRef.setData(userData, merge: true)
            print("✅ Synced profile info to user document")
            
            // Also save to profiles subcollection for history
            let profileRef = userRef.collection("profiles").document(profile.id.uuidString)
            
            var profileData: [String: Any] = [
                "name": profile.name,
                "childNames": profile.childNames,
                "transcriptionGlossary": profile.transcriptionGlossary,
                "syncedAt": FieldValue.serverTimestamp()
            ]
            
            if let birthdate = profile.birthdate {
                profileData["birthdate"] = birthdate
            }
            
            try await profileRef.setData(profileData, merge: true)
        } catch {
            print("❌ Failed to sync profile: \(error)")
        }
    }
    
    /// Sync profile info along with memory (convenience method)
    func syncMemoryWithProfile(_ entry: MemoryEntry, profile: Profile) async {
        // First sync the profile info to user document
        await syncProfile(profile)
        
        // Then sync the memory
        await syncMemory(entry)
    }
    
    // MARK: - Delete Operations
    
    /// Durably deletes a memory. A permanent server tombstone prevents stale app
    /// instances from recreating the document or either audio object.
    @MainActor
    func deleteMemory(
        memoryId: UUID,
        profileId: UUID? = nil,
        firebaseUserId: String? = nil
    ) async {
        let intendedUserId = firebaseUserId ?? Auth.auth().currentUser?.uid
        registerPendingMemoryDeletion(
            memoryId: memoryId,
            profileId: profileId,
            firebaseUserId: intendedUserId
        )
        guard let intendedUserId,
              Auth.auth().currentUser?.uid == intendedUserId else { return }

        let operationKey = "\(intendedUserId):\(memoryId.uuidString)"
        let deleted = await memoryOperationSequencer.run(key: operationKey) { @MainActor [self] in
            await performMemoryDeletion(
                memoryId: memoryId,
                profileId: profileId,
                firebaseUserId: intendedUserId
            )
        }
        if deleted {
            cancelPendingMemoryDeletion(memoryId: memoryId, firebaseUserId: intendedUserId)
        } else {
            incrementPendingMemoryDeletionRetry(memoryId: memoryId, firebaseUserId: intendedUserId)
        }
    }

    @MainActor
    private func performMemoryDeletion(
        memoryId: UUID,
        profileId: UUID?,
        firebaseUserId: String
    ) async -> Bool {
        guard Auth.auth().currentUser?.uid == firebaseUserId else { return false }
        let userRef = db.collection("users").document(firebaseUserId)
        let memoryRef = userRef.collection("memories").document(memoryId.uuidString)
        let tombstoneRef = userRef.collection("memoryTombstones").document(memoryId.uuidString)
        let audioTombstones = userRef.collection("memoryAudioTombstones")
        var tombstoneData: [String: Any] = [
            "deletedAt": FieldValue.serverTimestamp(),
            "schemaVersion": 1
        ]
        if let profileId {
            tombstoneData["profileId"] = profileId.uuidString
        }

        do {
            let batch = db.batch()
            batch.setData(tombstoneData, forDocument: tombstoneRef, merge: true)
            for fileExtension in ["m4a", "caf"] {
                let filename = "\(memoryId.uuidString).\(fileExtension)"
                batch.setData(
                    ["deletedAt": FieldValue.serverTimestamp(), "schemaVersion": 1],
                    forDocument: audioTombstones.document(filename),
                    merge: true
                )
            }
            batch.deleteDocument(memoryRef)
            try await batch.commit()
        } catch {
            print("❌ Failed to commit memory tombstone: \(error.localizedDescription)")
            return false
        }

        var removedAllAudio = true
        for fileExtension in ["m4a", "caf"] {
            do {
                try await StorageService.shared.deleteFile(
                    at: "users/\(firebaseUserId)/audio/\(memoryId.uuidString).\(fileExtension)"
                )
            } catch {
                let errorCode = (error as NSError).code
                if errorCode != StorageErrorCode.objectNotFound.rawValue {
                    removedAllAudio = false
                    print("⚠️ Failed to delete \(fileExtension) audio for memory \(memoryId.uuidString.prefix(8))…: \(error.localizedDescription)")
                }
            }
        }
        if removedAllAudio {
            print("✅ Deleted memory \(memoryId.uuidString.prefix(8))… and blocked stale recreation")
        }
        return removedAllAudio
    }

    // MARK: - Book version delete (library)

    public enum BookVersionDeleteResult: Sendable, Equatable {
        case deleted
        case blockedBecauseOrderExists
        case error(String)
    }

    /// Returns `true` if the user has any `orders` row referencing this book (blocks destructive cleanup).
    func hasOrderReferencingBookVersion(_ bookVersionId: String) async -> Bool {
        guard let userId = Auth.auth().currentUser?.uid, !bookVersionId.isEmpty else { return true }
        do {
            let snap = try await db.collection("users").document(userId)
                .collection("orders")
                .whereField("bookVersionId", isEqualTo: bookVersionId)
                .limit(to: 1)
                .getDocuments()
            return !snap.documents.isEmpty
        } catch {
            print("⚠️ hasOrderReferencingBookVersion query failed: \(error.localizedDescription) — treat as blocked")
            return true
        }
    }

    /// Deletes the canonical `bookVersions` doc, legacy `books` mirror, Storage prefix, and any pending-resume row.
    func deleteBookVersion(bookId: String) async -> BookVersionDeleteResult {
        guard let userId = Auth.auth().currentUser?.uid else { return .error("Not signed in") }
        if await hasOrderReferencingBookVersion(bookId) {
            print("⛔ deleteBookVersion skipped: order exists for id=\(bookId.prefix(28))…")
            return .blockedBecauseOrderExists
        }
        do {
            try await StorageService.shared.deleteBookVersionFolder(bookId: bookId)
            try await db.collection("users").document(userId)
                .collection("bookVersions").document(bookId)
                .delete()
            try await db.collection("users").document(userId)
                .collection("books").document(bookId)
                .delete()
        } catch {
            return .error(error.localizedDescription)
        }
        clearPendingBookSync(bookId: bookId)
        print("🗑️ deleteBookVersion completed: \(bookId.prefix(32))…")
        return .deleted
    }

    // MARK: - One-time duplicate `bookVersions` doc cleanup (edit→duplicate-bug)

    private static let duplicateBookCleanupKeyPrefix = "memoirai_dup_cleanup_v1_"
    private static var duplicateBookCleanupInFlight: Set<String> = []
    private static let duplicateLock = NSLock()

    /// `true` if we have already run duplicate cleanup for this profile on this device.
    func isDuplicateBookCleanupDone(profileID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: "\(Self.duplicateBookCleanupKeyPrefix)\(profileID.uuidString)")
    }

    func markDuplicateBookCleanupDone(profileID: UUID) {
        UserDefaults.standard.set(true, forKey: "\(Self.duplicateBookCleanupKeyPrefix)\(profileID.uuidString)")
    }

    /// Groups likely duplicate `bookVersions` (same `profileId`, close `createdAt`, Jaccard overlap on `memoryOrder` ≥ 0.9) and deletes inferior copies. Safe: skips if any `orders` reference. Returns the list to show in the gallery.
    func runOneTimeDuplicateBookVersionCleanup(
        profileID: UUID,
        initialBooks: [BookVersionRecord]
    ) async -> [BookVersionRecord] {
        let inserted = Self.duplicateLock.withLock {
            Self.duplicateBookCleanupInFlight.insert(profileID.uuidString).inserted
        }
        if !inserted { return initialBooks }
        defer {
            _ = Self.duplicateLock.withLock {
                Self.duplicateBookCleanupInFlight.remove(profileID.uuidString)
            }
        }
        if initialBooks.count < 2 { return initialBooks }
        var remaining = initialBooks
        let wantedProfile = profileID.uuidString
        // Union-find on indices
        var parent = Array(0..<remaining.count)
        func find(_ i: Int) -> Int {
            if parent[i] != i { parent[i] = find(parent[i]) }
            return parent[i]
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[rb] = ra }
        }
        func jaccard(_ a: [String], _ b: [String]) -> Double {
            if a.isEmpty, b.isEmpty { return 1.0 }
            if a.isEmpty || b.isEmpty { return 0 }
            let sa = Set(a), sb = Set(b)
            let inter = sa.intersection(sb).count
            let u = sa.union(sb).count
            return u == 0 ? 0 : Double(inter) / Double(u)
        }
        for i in 0..<remaining.count {
            for j in (i + 1)..<remaining.count {
                let a = remaining[i], b = remaining[j]
                guard a.profileId == wantedProfile, b.profileId == wantedProfile else { continue }
                if abs(a.createdAt.timeIntervalSince(b.createdAt)) > 60 { continue }
                if jaccard(a.memoryOrder, b.memoryOrder) < 0.9 { continue }
                union(i, j)
            }
        }
        var groups: [Int: [Int]] = [:]
        for i in 0..<remaining.count {
            let r = find(i)
            groups[r, default: []].append(i)
        }
        func betterRecord(_ a: BookVersionRecord, _ b: BookVersionRecord) -> BookVersionRecord {
            if a.renderStatus == BookRenderStatus.rendered.rawValue, b.renderStatus != BookRenderStatus.rendered.rawValue { return a }
            if b.renderStatus == BookRenderStatus.rendered.rawValue, a.renderStatus != BookRenderStatus.rendered.rawValue { return b }
            if a.pageCount == a.pages.count, b.pageCount != b.pages.count { return a }
            if b.pageCount == b.pages.count, a.pageCount != a.pages.count { return b }
            if a.pages.count != b.pages.count { return a.pages.count > b.pages.count ? a : b }
            let aSync = a.syncedAt?.timeIntervalSince1970 ?? 0
            let bSync = b.syncedAt?.timeIntervalSince1970 ?? 0
            if aSync != bSync { return aSync > bSync ? a : b }
            return a.createdAt > b.createdAt ? a : b
        }
        for (_, idxs) in groups where idxs.count > 1 {
            let recs: [BookVersionRecord] = idxs.map { remaining[$0] }
            var keeper = recs[0]
            for r in recs.dropFirst() { keeper = betterRecord(keeper, r) }
            for r in recs where r.bookVersionId != keeper.bookVersionId {
                if await hasOrderReferencingBookVersion(r.bookVersionId) { continue }
                if await deleteBookVersion(bookId: r.bookVersionId) == .deleted {
                    let kp = keeper.bookVersionId
                    print("🧹 Duplicate cleanup: removed id=\(r.bookVersionId.prefix(32))… kept id=\(kp.prefix(32))…")
                    remaining.removeAll { $0.bookVersionId == r.bookVersionId }
                }
            }
        }
        return remaining
    }
}

// MARK: - Convenience Extension for Background Sync

extension FirestoreSyncService {
    
    /// Queue a memory sync in the background (fire and forget)
    func queueMemorySync(_ entry: MemoryEntry, profileName: String? = nil) {
        let objectID = entry.objectID
        Task { @MainActor in
            let context = PersistenceController.shared.container.viewContext
            guard let queuedEntry = try? context.existingObject(with: objectID) as? MemoryEntry else { return }
            await syncMemory(queuedEntry, profileName: profileName)
        }
    }
    
    /// Queue a memory sync with profile info. Wrapped in a background task (mirrors `queueBookSync`) so an
    /// in-flight sync gets a grace period if the app is backgrounded mid-upload. On failure (e.g. offline),
    /// registers a pending-retry record so `retryPendingSyncs` resumes it next time the app becomes active —
    /// otherwise an offline save never reaches Firestore until an unrelated flow happens to re-sync it.
    func queueMemorySyncWithProfile(_ entry: MemoryEntry, profile: Profile) {
        let objectID = entry.objectID
        guard let queuedMemoryId = entry.id?.uuidString,
              let intendedUserID = MemoryOwnershipPolicy.normalizedUserID(entry.firebaseUserId) else { return }
        registerPendingMemorySyncForProfile(
            memoryId: queuedMemoryId,
            profile: profile,
            firebaseUserId: intendedUserID
        )
        Task { @MainActor in
            guard MemoryOwnershipPolicy.canAttemptRemoteWrite(
                intendedUserID: intendedUserID,
                currentUserID: Auth.auth().currentUser?.uid
            ) else { return }
            let context = PersistenceController.shared.container.viewContext
            guard let queuedEntry = try? context.existingObject(with: objectID) as? MemoryEntry,
                  MemoryOwnershipPolicy.belongsToUser(
                    entryOwnerID: queuedEntry.firebaseUserId,
                    currentUserID: intendedUserID
                  ) else { return }
            var backgroundTaskID = UIBackgroundTaskIdentifier.invalid
            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "MemoirAI.MemorySync") {
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                    backgroundTaskID = .invalid
                }
            }
            defer {
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                    backgroundTaskID = .invalid
                }
            }
            // Sync profile to user document first
            guard Auth.auth().currentUser?.uid == intendedUserID else { return }
            await syncProfile(profile)
            guard Auth.auth().currentUser?.uid == intendedUserID else { return }
            // Then sync memory with profile name
            let synced = await syncMemory(queuedEntry, profileName: profile.name)
            guard let currentEntry = try? context.existingObject(with: objectID) as? MemoryEntry,
                  !currentEntry.isDeleted,
                  let memoryId = currentEntry.id?.uuidString else { return }
            if synced {
                if TranscriptionRetryPolicy.shouldRequest(
                    status: currentEntry.transcriptionStatus,
                    audioFileExtension: URL(string: currentEntry.audioFileURL ?? "")?.pathExtension,
                    updatedAt: currentEntry.transcriptionUpdatedAt
                ), let id = currentEntry.id {
                    do {
                        _ = try await CloudTranscriptionService.shared.transcribe(memoryID: id, profile: profile)
                        clearPendingMemorySync(memoryId: memoryId)
                    } catch {
                        if currentEntry.transcriptionStatus == "needsRerecording" {
                            clearPendingMemorySync(memoryId: memoryId)
                        } else {
                            incrementPendingMemorySyncRetry(memoryId: memoryId)
                        }
                        print("⚠️ Cloud transcription request failed: \(error.localizedDescription)")
                    }
                } else if currentEntry.transcriptionStatus != "processing" {
                    clearPendingMemorySync(memoryId: memoryId)
                }
            } else {
                if currentEntry.transcriptionStatus == "needsRerecording" {
                    clearPendingMemorySync(memoryId: memoryId)
                } else {
                    incrementPendingMemorySyncRetry(memoryId: memoryId)
                }
            }
        }
    }
    
    /// Queue a book sync in the background.
    /// Pass `coverInputs` so Gemini can render the flat `cover.pdf` (AI title in-image; headshot drives likeness, or non-human art when headshot is nil).
    func queueBookSync(
        _ book: PersistableStorybook,
        bookId: String,
        renderedPageImages: [UIImage]? = nil,
        renderedPageProvider: RenderedPageProvider? = nil,
        coverInputs: FirestoreSyncService.CoverInputs? = nil,
        coverPDFOverride: Data? = nil
    ) {
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .storybookCloudUploadActivity,
                object: nil,
                userInfo: ["bookSyncCountDelta": 1]
            )
            var backgroundTaskID = UIBackgroundTaskIdentifier.invalid
            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "MemoirAI.StorybookSync") {
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                    backgroundTaskID = .invalid
                }
            }
            defer {
                NotificationCenter.default.post(
                    name: .storybookCloudUploadActivity,
                    object: nil,
                    userInfo: ["bookSyncCountDelta": -1]
                )
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                    backgroundTaskID = .invalid
                }
            }
            await self.syncBook(
                book,
                bookId: bookId,
                renderedPageImages: renderedPageImages,
                renderedPageProvider: renderedPageProvider,
                coverInputs: coverInputs,
                coverPDFOverride: coverPDFOverride
            )
        }
    }

    // MARK: - Cloud storybook generation (headshot + job queries)

    struct ActiveStorybookCloudJob: Equatable {
        let jobId: String
        let status: String
        let progressCompleted: Int
        let progressTotal: Int
        let currentStatus: String
    }

    private static func subjectPhotoChecksumKey(profileId: UUID) -> String {
        "memoir_subject_photo_sha256_\(profileId.uuidString.lowercased())"
    }

    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func resizedSubjectPhotoForUpload(_ image: UIImage, maxEdge: CGFloat = 1024) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        let longest = max(w, h)
        guard longest > maxEdge, longest > 0 else { return image }
        let scale = maxEdge / longest
        let newSize = CGSize(width: max(1, w * scale), height: max(1, h * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Uploads profile subject photo for cloud storybook workers; skips upload when checksum unchanged.
    /// - Returns: Storage path `users/{uid}/profiles/{profileId}/subjectPhoto.jpg`, or `nil` when no image / not signed in.
    func uploadSubjectPhotoIfNeeded(_ image: UIImage?, profileId: UUID) async throws -> String? {
        guard let image else { return nil }
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let resized = resizedSubjectPhotoForUpload(image)
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return nil }
        let hash = Self.sha256Hex(jpeg)
        let key = Self.subjectPhotoChecksumKey(profileId: profileId)
        let pathLower = profileId.uuidString.lowercased()
        let path = "users/\(uid)/profiles/\(pathLower)/subjectPhoto.jpg"
        if UserDefaults.standard.string(forKey: key) == hash {
            return path
        }
        let ref = Storage.storage().reference(withPath: path)
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(jpeg, metadata: meta)
        UserDefaults.standard.set(hash, forKey: key)
        return path
    }

    /// Jobs older than this are ignored for auto-resume / banner so stale `failed` rows from old deployments do not route the app forever.
    static let storybookCloudJobMaxActiveAge: TimeInterval = 7 * 24 * 60 * 60

    /// Returns whether a job document's `createdAt` is recent enough to treat as "active" for routing and UI.
    static func isStorybookJobRecentForActiveUI(createdAt: Any?, referenceNow: Date = Date()) -> Bool {
        guard let ts = createdAt as? Timestamp else { return false }
        let created = ts.dateValue()
        let age = referenceNow.timeIntervalSince(created)
        if age < 0 { return true }
        return age <= storybookCloudJobMaxActiveAge
    }

    /// Rows must be newest-first (Firestore `order(by: "createdAt", descending: true)`).
    static func pickActiveStorybookCloudJob(
        profileId: UUID,
        rowsNewestFirst: [(documentID: String, data: [String: Any])],
        referenceNow: Date = Date()
    ) -> ActiveStorybookCloudJob? {
        let pid = profileId.uuidString.lowercased()
        var filtered: [(id: String, d: [String: Any], st: String)] = []
        for row in rowsNewestFirst {
            let d = row.data
            guard Self.isStorybookJobRecentForActiveUI(createdAt: d["createdAt"], referenceNow: referenceNow) else { continue }
            let p = String(describing: d["profileId"] ?? "").lowercased()
            guard p == pid else { continue }
            let st = String(describing: d["status"] ?? "")
            if st == "dismissedFailed" { continue }
            filtered.append((row.documentID, d, st))
        }
        let supersedeNewer = Set(["queued", "ranking", "running", "aiComplete", "complete"])
        let inFlight = Set(["queued", "ranking", "running", "aiComplete"])
        for i in filtered.indices {
            let st = filtered[i].st
            if inFlight.contains(st) {
                return Self.makeActiveStorybookCloudJob(documentId: filtered[i].id, data: filtered[i].d)
            }
            if st == "failed" {
                var hasNewerSuperseding = false
                for j in filtered.indices where j < i {
                    if supersedeNewer.contains(filtered[j].st) {
                        hasNewerSuperseding = true
                        break
                    }
                }
                if !hasNewerSuperseding {
                    return Self.makeActiveStorybookCloudJob(documentId: filtered[i].id, data: filtered[i].d)
                }
            }
        }
        return nil
    }

    /// Newest recent `complete` job for this profile — used to route the user once to a book
    /// that finished while the app was closed. Rows must be newest-first.
    static func pickLatestCompletedStorybookCloudJob(
        profileId: UUID,
        rowsNewestFirst: [(documentID: String, data: [String: Any])],
        referenceNow: Date = Date()
    ) -> ActiveStorybookCloudJob? {
        let pid = profileId.uuidString.lowercased()
        for row in rowsNewestFirst {
            let d = row.data
            guard Self.isStorybookJobRecentForActiveUI(createdAt: d["createdAt"], referenceNow: referenceNow) else { continue }
            guard String(describing: d["profileId"] ?? "").lowercased() == pid else { continue }
            if String(describing: d["status"] ?? "") == "complete" {
                return Self.makeActiveStorybookCloudJob(documentId: row.documentID, data: d)
            }
        }
        return nil
    }

    private static func makeActiveStorybookCloudJob(documentId: String, data: [String: Any]) -> ActiveStorybookCloudJob {
        let prog = data["progress"] as? [String: Any] ?? [:]
        let completed = (prog["completedMemoryCount"] as? NSNumber)?.intValue ?? (prog["completedMemoryCount"] as? Int) ?? 0
        let total = (prog["totalMemories"] as? NSNumber)?.intValue ?? (prog["totalMemories"] as? Int) ?? 0
        let cur = String(describing: prog["currentStatus"] ?? "")
        let st = String(describing: data["status"] ?? "")
        return ActiveStorybookCloudJob(
            jobId: documentId,
            status: st,
            progressCompleted: completed,
            progressTotal: total,
            currentStatus: cur
        )
    }

    /// Latest storybook cloud job for this profile that still needs app attention (including `aiComplete` awaiting finalize).
    func fetchLatestActiveStorybookJob(profileId: UUID) async throws -> ActiveStorybookCloudJob? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let snap = try await db.collection("users").document(uid).collection("storybookJobs")
            .order(by: "createdAt", descending: true)
            .limit(to: 25)
            .getDocuments()
        let rows = snap.documents.map { ($0.documentID, $0.data()) }
        return Self.pickActiveStorybookCloudJob(profileId: profileId, rowsNewestFirst: rows)
    }

    /// Job the launch auto-route should bring the user to: an in-flight job if one exists,
    /// otherwise the newest recently-completed job (caller decides whether it was already seen).
    func fetchLatestRoutableStorybookJob(profileId: UUID) async throws -> ActiveStorybookCloudJob? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let snap = try await db.collection("users").document(uid).collection("storybookJobs")
            .order(by: "createdAt", descending: true)
            .limit(to: 25)
            .getDocuments()
        let rows = snap.documents.map { ($0.documentID, $0.data()) }
        if let active = Self.pickActiveStorybookCloudJob(profileId: profileId, rowsNewestFirst: rows) {
            return active
        }
        return Self.pickLatestCompletedStorybookCloudJob(profileId: profileId, rowsNewestFirst: rows)
    }

    func writeStorybookCloudJob(jobId: String, data: [String: Any]) async throws {
        guard Auth.auth().currentUser != nil else {
            throw NSError(domain: "FirestoreSyncService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        let callable = Functions.functions().httpsCallable("createStorybookJob")
        callable.timeoutInterval = 60
        _ = try await callable.call([
            "jobId": jobId,
            "job": data
        ])
    }

    func markStorybookJobComplete(jobId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("users").document(uid).collection("storybookJobs").document(jobId).setData(
            [
                "status": "complete",
                "updatedAt": FieldValue.serverTimestamp()
            ],
            merge: true
        )
    }

    /// Marks a stuck/broken cloud job as failed so the auto-resume listener
    /// stops re-attaching to it.  Used when the client detects an `aiComplete`
    /// snapshot whose `memoryResults` are unusable (e.g. all illustrations
    /// failed server-side before the failure check was deployed).
    func markStorybookJobFailed(jobId: String, reason: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("users").document(uid).collection("storybookJobs").document(jobId).setData(
            [
                "status": "failed",
                "error": reason,
                "updatedAt": FieldValue.serverTimestamp()
            ],
            merge: true
        )
    }
}
