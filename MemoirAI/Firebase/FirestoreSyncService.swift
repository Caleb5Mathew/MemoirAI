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
import FirebaseStorage
import UIKit

/// Chains `syncBook` / Storage for the same `bookVersionId` so concurrent in-place saves do not interleave.
private actor BookVersionSyncSequencer {
    private var inFlight: [String: Task<Void, Never>] = [:]
    /// Runs `work` after any earlier task for the same `bookId` has finished; latest snapshot wins.
    func run(bookId: String, work: @Sendable @escaping () async -> Void) async {
        let previous = inFlight[bookId]
        let t = Task {
            await previous?.value
            await work()
        }
        inFlight[bookId] = t
        await t.value
    }
}

/// Service for syncing local Core Data to Firebase Firestore
/// This runs alongside CloudKit - CloudKit handles fast local sync,
/// Firebase provides admin access to all user data
final class FirestoreSyncService {
    
    static let shared = FirestoreSyncService()
    
    private let db = Firestore.firestore()
    private let bookVersionSyncSequencer = BookVersionSyncSequencer()
    
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
        let queuedAt: Date
        /// Incremented when `invokeBookRenderFunction` fails; used for debugging / future backoff.
        var renderRetryCount: Int

        init(bookId: String, profileId: String, queuedAt: Date, renderRetryCount: Int = 0) {
            self.bookId = bookId
            self.profileId = profileId
            self.queuedAt = queuedAt
            self.renderRetryCount = renderRetryCount
        }

        private enum CodingKeys: String, CodingKey {
            case bookId, profileId, queuedAt, renderRetryCount
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            bookId = try c.decode(String.self, forKey: .bookId)
            profileId = try c.decode(String.self, forKey: .profileId)
            queuedAt = try c.decode(Date.self, forKey: .queuedAt)
            renderRetryCount = try c.decodeIfPresent(Int.self, forKey: .renderRetryCount) ?? 0
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(bookId, forKey: .bookId)
            try c.encode(profileId, forKey: .profileId)
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

    private func registerPendingBookSync(bookId: String, profileId: String) {
        var records = loadPendingBookSyncRecords()
        let existing = records.first { $0.bookId == bookId }
        let preserveRetry = existing?.renderRetryCount ?? 0
        let preserveQueued = existing?.queuedAt ?? Date()
        records.removeAll { $0.bookId == bookId }
        records.append(
            PendingBookSyncRecord(
                bookId: bookId,
                profileId: profileId,
                queuedAt: preserveQueued,
                renderRetryCount: preserveRetry
            )
        )
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.pendingBookSyncStorageKey)
        }
    }

    /// Public so `StoryPageViewModel.persistStorybook` can register *before* `queueBookSync` schedules work (removes a crash window).
    func registerPendingBookSyncForProfile(bookId: String, profileId: UUID) {
        registerPendingBookSync(bookId: bookId, profileId: profileId.uuidString)
    }

    private func incrementPendingBookRenderRetry(bookId: String) {
        var records = loadPendingBookSyncRecords()
        guard let i = records.firstIndex(where: { $0.bookId == bookId }) else { return }
        records[i].renderRetryCount += 1
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.pendingBookSyncStorageKey)
        }
        print("[CoverFlow] incrementPendingBookRenderRetry bookId=\(bookId.prefix(28))… count=\(records[i].renderRetryCount)")
    }

    private func clearPendingBookSync(bookId: String) {
        var records = loadPendingBookSyncRecords()
        records.removeAll { $0.bookId == bookId }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.pendingBookSyncStorageKey)
        }
    }

    /// `bookVersionId` is `profileUUID_createdAtUnix` or `…_legacy`; returns `createdAt` unix seconds embedded in the id.
    private func createdAtUnixFromBookVersionId(_ bookId: String) -> Int? {
        let parts = bookId.split(separator: "_").map(String.init)
        guard parts.count >= 2 else { return nil }
        if parts.count >= 3, parts.last == "legacy" {
            return Int(parts[parts.count - 2])
        }
        return Int(parts[1])
    }

    private func localStorybookMatchingPending(bookId: String, profileID: UUID) -> PersistableStorybook? {
        let decoder = JSONDecoder()
        guard let ts = createdAtUnixFromBookVersionId(bookId) else { return nil }
        // Prefer current on-disk book when it matches this `bookId` (fresher than a stale history entry).
        if let currentData = StorybookLocalStore.readCurrentBookData(profileID: profileID),
           let book = try? decoder.decode(PersistableStorybook.self, from: currentData),
           book.profileID == profileID,
           Int(book.createdAt.timeIntervalSince1970) == ts {
            return book
        }
        for data in StorybookLocalStore.readHistoryDataArray(profileID: profileID) {
            guard let book = try? decoder.decode(PersistableStorybook.self, from: data),
                  book.profileID == profileID,
                  Int(book.createdAt.timeIntervalSince1970) == ts else { continue }
            return book
        }
        return nil
    }

    /// Re-attempt uploads for books that never finished syncing (same device, local `.book` still present). Uses the freshest `current.book` for that version when possible.
    /// Also re-attempts any memory syncs queued by `queueMemorySyncWithProfile` that failed while offline (see `retryPendingMemorySyncs`).
    func retryPendingSyncs(for profileID: UUID) async {
        guard Auth.auth().currentUser?.uid != nil else { return }
        await retryPendingMemorySyncs(for: profileID)
        let want = profileID.uuidString
        let pending = loadPendingBookSyncRecords().filter { $0.profileId == want }
        guard !pending.isEmpty else { return }
        for record in pending {
            if let cloud = await fetchBookVersion(bookVersionId: record.bookId),
               !StorybookCloudApplyPolicy.isIncompleteCloudRecord(cloud),
               cloud.renderStatus == BookRenderStatus.rendered.rawValue,
               cloud.pdfURL != nil,
               !(cloud.coverURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
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
                    clearPendingBookSync(bookId: record.bookId)
                } else {
                    incrementPendingBookRenderRetry(bookId: record.bookId)
                }
                continue
            }
            guard let book = localStorybookMatchingPending(bookId: record.bookId, profileID: profileID) else {
                continue
            }
            await syncBook(book, bookId: record.bookId, renderedPageImages: nil, coverInputs: nil)
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
        let queuedAt: Date
        /// Incremented when a retry attempt still fails; used for debugging, same as `PendingBookSyncRecord.renderRetryCount`.
        var retryCount: Int

        init(memoryId: String, profileId: String, queuedAt: Date, retryCount: Int = 0) {
            self.memoryId = memoryId
            self.profileId = profileId
            self.queuedAt = queuedAt
            self.retryCount = retryCount
        }

        private enum CodingKeys: String, CodingKey {
            case memoryId, profileId, queuedAt, retryCount
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            memoryId = try c.decode(String.self, forKey: .memoryId)
            profileId = try c.decode(String.self, forKey: .profileId)
            queuedAt = try c.decode(Date.self, forKey: .queuedAt)
            retryCount = try c.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(memoryId, forKey: .memoryId)
            try c.encode(profileId, forKey: .profileId)
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

    private func registerPendingMemorySync(memoryId: String, profileId: String) {
        var records = loadPendingMemorySyncRecords()
        let existing = records.first { $0.memoryId == memoryId }
        let preserveRetry = existing?.retryCount ?? 0
        let preserveQueued = existing?.queuedAt ?? Date()
        records.removeAll { $0.memoryId == memoryId }
        records.append(
            PendingMemorySyncRecord(
                memoryId: memoryId,
                profileId: profileId,
                queuedAt: preserveQueued,
                retryCount: preserveRetry
            )
        )
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.pendingMemorySyncStorageKey)
        }
    }

    /// Non-private so tests can exercise the same register/re-register contract as `registerPendingBookSyncForProfile`.
    func registerPendingMemorySyncForProfile(memoryId: String, profileId: UUID) {
        registerPendingMemorySync(memoryId: memoryId, profileId: profileId.uuidString)
    }

    private func incrementPendingMemorySyncRetry(memoryId: String) {
        var records = loadPendingMemorySyncRecords()
        guard let i = records.firstIndex(where: { $0.memoryId == memoryId }) else { return }
        records[i].retryCount += 1
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.pendingMemorySyncStorageKey)
        }
        print("[MemorySync] incrementPendingMemorySyncRetry memoryId=\(memoryId.prefix(8))… count=\(records[i].retryCount)")
    }

    private func clearPendingMemorySync(memoryId: String) {
        var records = loadPendingMemorySyncRecords()
        records.removeAll { $0.memoryId == memoryId }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.pendingMemorySyncStorageKey)
        }
    }

    /// Re-attempt Firestore uploads for memories whose background sync previously failed (offline save).
    /// Dedupes by memory id; drops the pending record once synced or once the local `MemoryEntry` no longer exists.
    @MainActor
    private func retryPendingMemorySyncs(for profileID: UUID) async {
        guard Auth.auth().currentUser?.uid != nil else { return }
        let want = profileID.uuidString
        let pending = loadPendingMemorySyncRecords().filter { $0.profileId == want }
        guard !pending.isEmpty else { return }

        let context = PersistenceController.shared.container.viewContext
        for record in pending {
            guard let memoryUUID = UUID(uuidString: record.memoryId) else {
                clearPendingMemorySync(memoryId: record.memoryId)
                continue
            }
            let request: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", memoryUUID as CVarArg)
            request.fetchLimit = 1
            guard let entry = try? context.fetch(request).first else {
                // Memory no longer exists locally (deleted) — nothing left to sync.
                clearPendingMemorySync(memoryId: record.memoryId)
                continue
            }
            let synced = await syncMemory(entry)
            if synced {
                clearPendingMemorySync(memoryId: record.memoryId)
            } else {
                incrementPendingMemorySyncRetry(memoryId: record.memoryId)
            }
        }
    }

    // MARK: - Memory Sync

    /// Sync a memory entry to Firestore
    /// Call this after saving to Core Data
    /// - Returns: `true` when the Firestore write (and audio upload, if any) succeeded; `false` on any failure so callers can queue a retry.
    @discardableResult
    func syncMemory(_ entry: MemoryEntry, profileName: String? = nil) async -> Bool {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ Cannot sync memory - user not signed in")
            return false
        }

        guard let memoryId = entry.id else {
            print("⚠️ Cannot sync memory - no ID")
            return false
        }

        let memoryRef = db.collection("users").document(userId)
            .collection("memories").document(memoryId.uuidString)

        do {
            // Upload audio if available; otherwise remove stale audioURL in Firestore (e.g. after re-record clear).
            var memoryData: [String: Any] = [
                "prompt": entry.prompt ?? "",
                "transcription": entry.text ?? "",
                "createdAt": entry.createdAt ?? Date(),
                "chapter": entry.chapter ?? "",
                "profileID": entry.profileID?.uuidString ?? "",
                "syncedAt": FieldValue.serverTimestamp()
            ]

            if let audioData = entry.audioData, !audioData.isEmpty {
                let uploaded = try await StorageService.shared.uploadAudio(audioData, memoryId: memoryId.uuidString)
                memoryData["audioURL"] = uploaded
            } else {
                memoryData["audioURL"] = FieldValue.delete()
            }

            // Include profile name for easy identification
            if let profileName = profileName {
                memoryData["profileName"] = profileName
            }

            if let characterDetails = entry.characterDetails {
                memoryData["characterDetails"] = characterDetails
            }

            // Save to Firestore
            try await memoryRef.setData(memoryData, merge: true)
            print("✅ Synced memory \(memoryId.uuidString) to Firebase")
            return true

        } catch {
            print("❌ Failed to sync memory to Firebase: \(error)")
            return false
        }
    }
    
    /// Update just the transcription for a memory
    func updateMemoryTranscription(memoryId: UUID, transcription: String) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let memoryRef = db.collection("users").document(userId)
            .collection("memories").document(memoryId.uuidString)
        
        do {
            try await memoryRef.updateData([
                "transcription": transcription,
                "syncedAt": FieldValue.serverTimestamp()
            ])
            print("✅ Updated transcription for memory \(memoryId.uuidString)")
        } catch {
            print("❌ Failed to update transcription: \(error)")
        }
    }
    
    // MARK: - Book Sync

    /// Writes identity + cover fields with `merge: true` so `fetchBookVersion` succeeds before the long per-page upload loop finishes.
    private func mergeEarlyBookVersionCoverMetadata(
        bookRef: DocumentReference,
        baseRecord: BookVersionRecord,
        coverStoragePath: String,
        coverURL: String
    ) async throws {
        var data: [String: Any] = [
            "bookVersionId": baseRecord.bookVersionId,
            "profileId": baseRecord.profileId,
            "createdAt": Timestamp(date: baseRecord.createdAt),
            "memoryOrder": baseRecord.memoryOrder,
            "pageCount": baseRecord.pageCount,
            "artStyle": baseRecord.artStyle,
            "orientation": baseRecord.orientation,
            "pageWidth": baseRecord.pageWidth,
            "pageHeight": baseRecord.pageHeight,
            "trimSizeInches": baseRecord.trimSizeInches,
            "layoutVersion": baseRecord.layoutVersion,
            "renderStatus": BookRenderStatus.pending.rawValue,
            "source": baseRecord.source,
            "pages": [],
            "coverStoragePath": coverStoragePath,
            "coverURL": coverURL,
            "coverArtRevision": FieldValue.increment(Int64(1)),
            "syncedAt": FieldValue.serverTimestamp()
        ]
        if let printTitle = baseRecord.printTitle { data["printTitle"] = printTitle }
        if let backCoverPitch = baseRecord.backCoverPitch { data["backCoverPitch"] = backCoverPitch }
        if let coverFontPreset = baseRecord.coverFontPreset { data["coverFontPreset"] = coverFontPreset }
        try await bookRef.setData(data, merge: true)
        print("[CoverFlow] syncBook earlyMerge DONE bookVersion=\(baseRecord.bookVersionId.prefix(28))… (page uploads still running)")
    }
    
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
        coverInputs: CoverInputs? = nil
    ) async {
        // Avoid capturing `var cover` in an `@Sendable` closure (Swift 6): resolve inputs once, synchronously.
        let finalCoverInputs: CoverInputs? = {
            if let c = coverInputs { return c }
            if renderedPageImages == nil { return Self.syntheticCoverInputsIfPossible(from: book) }
            return nil
        }()
        let rendered = renderedPageImages
        await bookVersionSyncSequencer.run(bookId: bookId) { [self] in
            await self.performSyncBook(
                book,
                bookId: bookId,
                renderedPageImages: rendered,
                coverInputs: finalCoverInputs
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
        coverInputs: CoverInputs? = nil
    ) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ Cannot sync book - user not signed in")
            return
        }
        
        let bookRef = db.collection("users").document(userId)
            .collection("bookVersions").document(bookId)
        
        do {
            registerPendingBookSync(bookId: bookId, profileId: book.profileID.uuidString)
            print("[CoverFlow] syncBook START bookId=\(bookId.prefix(28))… persistPages=\(book.pageItems.count) hasRenderedImages=\(renderedPageImages != nil) hasCoverInputs=\(coverInputs != nil)")
            // Build canonical version record first.
            let syncStart = Date()
            let baseRecord = BookVersionRecordFactory.fromPersistable(book, bookVersionId: bookId)
            let isLandscapeTrim = baseRecord.pageWidth > baseRecord.pageHeight
            var coverStoragePath: String?
            var coverURL: String?

            // Landscape trim (11×8.5): AI cover (headshot → likeness; no headshot → non-human art). Title is painted in-image.
            if isLandscapeTrim, let inputs = coverInputs {
                let svc = GeminiImageService()
                let themesPreview = inputs.memoryThemes.prefix(8).joined(separator: " | ")
                let canonPreview = inputs.protagonistCanonLine?.prefix(160).description ?? "<nil>"
                print("[CoverFlow] AI cover START trim=landscape bookId=\(bookId.prefix(28))… artStyleKey=\(inputs.artStyle.firestoreKey) hasHeadshot=\(inputs.headshot != nil) printTitle=\"\(inputs.printTitle)\" themesCount=\(inputs.memoryThemes.count) themesPreview=[\(themesPreview)] backCoverPitchLen=\(inputs.backCoverPitch.count) protagonistCanonLine.head=\(canonPreview) ethnicity=\(inputs.ethnicity ?? "<nil>") gender=\(inputs.gender ?? "<nil>")")
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
                let themesPreview = inputs.memoryThemes.prefix(8).joined(separator: " | ")
                let canonPreview = inputs.protagonistCanonLine?.prefix(160).description ?? "<nil>"
                print("[CoverFlow] AI cover START trim=portrait bookId=\(bookId.prefix(28))… artStyleKey=\(inputs.artStyle.firestoreKey) hasHeadshot=\(inputs.headshot != nil) printTitle=\"\(inputs.printTitle)\" themesCount=\(inputs.memoryThemes.count) themesPreview=[\(themesPreview)] backCoverPitchLen=\(inputs.backCoverPitch.count) protagonistCanonLine.head=\(canonPreview) ethnicity=\(inputs.ethnicity ?? "<nil>") gender=\(inputs.gender ?? "<nil>")")
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

            // So the client can load `coverURL` / `coverStoragePath` for the in-app title page
            // while page PNG uploads are still in progress (otherwise `fetchBookVersion` sees no doc until the final `setData`).
            if let path = coverStoragePath, let url = coverURL,
               !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try await mergeEarlyBookVersionCoverMetadata(
                    bookRef: bookRef,
                    baseRecord: baseRecord,
                    coverStoragePath: path,
                    coverURL: url
                )
            }

            var uploadedPages: [BookVersionPageRecord] = []
            var totalPngBytes = 0
            
            for (index, page) in baseRecord.pages.enumerated() {
                var updatedPage = page

                let renderedImage: UIImage = {
                    // 1. Prefer on-device rendered images (text + illustration) for full visual parity
                    if let renderedPageImages, index < renderedPageImages.count {
                        return renderedPageImages[index]
                    }
                    // 2. Fallback: use persisted image data for illustrations (e.g. legacy migration)
                    if index < book.pageItems.count,
                       let imageData = book.pageItems[index].imageData,
                       let image = UIImage(data: imageData) {
                        return image
                    }
                    // 3. Fallback: render text pages from content (required for Cloud Function; never skip)
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
                    // 4. Last resort: blank placeholder (ensures every page has an artifact)
                    print("⚠️ No image for page \(index) (type=\(page.type)); using blank placeholder")
                    return fallbackTextPageImage(
                        text: " ",
                        title: nil,
                        subtitle: nil,
                        widthPt: CGFloat(baseRecord.pageWidth),
                        heightPt: CGFloat(baseRecord.pageHeight)
                    )
                }()

                let artifacts = try await StorageService.shared.uploadRenderedBookPageArtifacts(
                    renderedImage,
                    bookId: bookId,
                    pageIndex: index,
                    isKidsBook: baseRecord.pageWidth > baseRecord.pageHeight,
                    asUserId: userId
                )
                totalPngBytes += artifacts.png.bytes

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
                    createdAt: page.createdAt
                )
                uploadedPages.append(updatedPage)
                try? await bookRef.setData(
                    ["pages": FieldValue.arrayUnion([updatedPage.toFirestoreData()])],
                    merge: true
                )
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
            
            print("✅ Synced canonical book version \(bookId) to Firebase with \(uploadedPages.count) pages and \(totalPngBytes) PNG bytes (layout: \(Int(baseRecord.pageWidth))x\(Int(baseRecord.pageHeight))pt)")
            
        } catch {
            print("[CoverFlow] syncBook ERROR bookId=\(bookId.prefix(28))… — \(error.localizedDescription)")
            print("❌ Failed to sync book to Firebase: \(error)")
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
            print("✅ Synced book metadata for \(bookId)")
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
    
    /// Uploads a new print `cover.pdf` and merges `coverURL` / `coverStoragePath` (same path as initial sync / `regenerateCoverDesign`).
    func mergeUploadedPrintCoverPDF(bookVersionId: String, pdfData: Data) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "FirestoreSyncService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        let uploaded = try await StorageService.shared.uploadBookCoverPDF(pdfData, bookId: bookVersionId)
        let docRef = db.collection("users").document(userId).collection("bookVersions").document(bookVersionId)
        try await docRef.setData([
            "coverStoragePath": uploaded.storagePath,
            "coverURL": uploaded.downloadURL,
            "coverArtRevision": FieldValue.increment(Int64(1)),
            "syncedAt": FieldValue.serverTimestamp()
        ], merge: true)
        print("[CoverFlow] mergeUploadedPrintCoverPDF DONE book=\(bookVersionId.prefix(28))…")
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
                let body = String(data: data, encoding: .utf8) ?? ""
                print("⚠️ Render function 409 (missing cover / precondition); repairing cover then retrying once. body=\(body)")
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
                let body = String(data: data, encoding: .utf8) ?? ""
                print("❌ Render function failed (\(http.statusCode)): \(body)")
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

    /// When Core Data has **no** `MemoryEntry` rows (e.g. fresh install, CloudKit unavailable) but Firestore
    /// still has `users/{uid}/memories` (same signed-in Apple/Google user), import documents into Core Data.
    @MainActor
    func hydrateMemoriesFromFirestoreIfStoreEmpty(context: NSManagedObjectContext) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ Firestore hydrate skipped — not signed in")
            return
        }

        let countRequest: NSFetchRequest<MemoryEntry> = MemoryEntry.fetchRequest()
        let localTotal = (try? context.count(for: countRequest)) ?? 0
        if localTotal > 0 {
            return
        }

        let ref = db.collection("users").document(userId).collection("memories")
        let snapshot: QuerySnapshot
        do {
            snapshot = try await ref.getDocuments()
        } catch {
            print("❌ Firestore hydrate: list memories failed — \(error.localizedDescription)")
            return
        }

        guard !snapshot.documents.isEmpty else { return }

        print("📥 Hydrating \(snapshot.documents.count) memories from Firestore (empty local store)…")

        for doc in snapshot.documents {
            guard let memoryUUID = UUID(uuidString: doc.documentID) else { continue }

            let existsRequest = MemoryEntry.fetchRequest()
            existsRequest.predicate = NSPredicate(format: "id == %@", memoryUUID as CVarArg)
            existsRequest.fetchLimit = 1
            if let count = try? context.count(for: existsRequest), count > 0 {
                continue
            }

            let data = doc.data()
            let entry = MemoryEntry(context: context)
            entry.id = memoryUUID
            entry.firebaseUserId = userId
            entry.prompt = data["prompt"] as? String
            entry.text = (data["transcription"] as? String) ?? ""
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

            if let urlStr = data["audioURL"] as? String,
               let url = URL(string: urlStr),
               let scheme = url.scheme?.lowercased(),
               scheme == "https" || scheme == "http" {
                do {
                    let (audioData, _) = try await URLSession.shared.data(from: url)
                    if !audioData.isEmpty {
                        entry.audioData = audioData
                    }
                } catch {
                    print("⚠️ Hydrate: audio download failed for \(memoryUUID.uuidString.prefix(8))… — \(error.localizedDescription)")
                }
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
        print("✅ Migration complete for \(userId) using key: \(key)")
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
            print("✅ Synced profile info to user document: \(profile.name)")
            
            // Also save to profiles subcollection for history
            let profileRef = userRef.collection("profiles").document(profile.id.uuidString)
            
            var profileData: [String: Any] = [
                "name": profile.name,
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
    
    /// Delete a memory from Firebase
    func deleteMemory(memoryId: UUID) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let memoryRef = db.collection("users").document(userId)
            .collection("memories").document(memoryId.uuidString)
        
        do {
            try await memoryRef.delete()
            print("✅ Deleted memory \(memoryId.uuidString) from Firebase")
        } catch {
            print("❌ Failed to delete memory: \(error)")
        }
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
            try await db.collection("users").document(userId)
                .collection("bookVersions").document(bookId)
                .delete()
            try? await db.collection("users").document(userId)
                .collection("books").document(bookId)
                .delete()
        } catch {
            return .error(error.localizedDescription)
        }
        clearPendingBookSync(bookId: bookId)
        await StorageService.shared.deleteBookVersionFolder(bookId: bookId)
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
        Self.duplicateLock.lock()
        let inserted = Self.duplicateBookCleanupInFlight.insert(profileID.uuidString).inserted
        Self.duplicateLock.unlock()
        if !inserted { return initialBooks }
        defer {
            Self.duplicateLock.lock()
            Self.duplicateBookCleanupInFlight.remove(profileID.uuidString)
            Self.duplicateLock.unlock()
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
        Task {
            await syncMemory(entry, profileName: profileName)
        }
    }
    
    /// Queue a memory sync with profile info. Wrapped in a background task (mirrors `queueBookSync`) so an
    /// in-flight sync gets a grace period if the app is backgrounded mid-upload. On failure (e.g. offline),
    /// registers a pending-retry record so `retryPendingSyncs` resumes it next time the app becomes active —
    /// otherwise an offline save never reaches Firestore until an unrelated flow happens to re-sync it.
    func queueMemorySyncWithProfile(_ entry: MemoryEntry, profile: Profile) {
        Task { @MainActor in
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
            await syncProfile(profile)
            // Then sync memory with profile name
            let synced = await syncMemory(entry, profileName: profile.name)
            guard let memoryId = entry.id?.uuidString else { return }
            if synced {
                clearPendingMemorySync(memoryId: memoryId)
            } else {
                registerPendingMemorySyncForProfile(memoryId: memoryId, profileId: profile.id)
            }
        }
    }
    
    /// Queue a book sync in the background.
    /// Pass `coverInputs` so Gemini can render the flat `cover.pdf` (AI title in-image; headshot drives likeness, or non-human art when headshot is nil).
    func queueBookSync(
        _ book: PersistableStorybook,
        bookId: String,
        renderedPageImages: [UIImage]? = nil,
        coverInputs: FirestoreSyncService.CoverInputs? = nil
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
                coverInputs: coverInputs
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

    func writeStorybookCloudJob(jobId: String, data: [String: Any]) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "FirestoreSyncService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        var merged = data
        merged["createdAt"] = FieldValue.serverTimestamp()
        merged["updatedAt"] = FieldValue.serverTimestamp()
        try await db.collection("users").document(uid).collection("storybookJobs").document(jobId).setData(merged)
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
