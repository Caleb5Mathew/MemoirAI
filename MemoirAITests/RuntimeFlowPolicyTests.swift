import Foundation
import Testing
@testable import MemoirAI

struct RuntimeFlowPolicyTests {
    @Test func storybookPayloadCapsPinnedMemoriesAtServerLimit() {
        let ids = (0..<130).map { _ in UUID() }
        let pinned = StorybookJobPayloadPolicy.pinnedMemoryIDs(ids)
        #expect(pinned.count == StorybookJobPayloadPolicy.maximumPinnedMemoryCount)
        #expect(pinned.first == ids.first?.uuidString)
    }

    @Test func editedStorybooksAlwaysReceiveUniqueRevisionIdentifiers() {
        let profileID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000.123)
        let first = StorybookVersionIDPolicy.make(
            profileID: profileID,
            createdAt: createdAt,
            nonce: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        )
        let second = StorybookVersionIDPolicy.make(
            profileID: profileID,
            createdAt: createdAt,
            nonce: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        )

        #expect(first == "11111111-1111-4111-8111-111111111111_1700000000123_22222222-2222-4222-8222-222222222222")
        #expect(first != second)
    }

    @Test func testsAndPreviewsNeverStartCloudKitMirroring() {
        #expect(!PersistenceConfigurationPolicy.usesCloudKit(
            inMemory: true,
            isRunningTests: false
        ))
        #expect(!PersistenceConfigurationPolicy.usesCloudKit(
            inMemory: false,
            isRunningTests: true
        ))
        #expect(PersistenceConfigurationPolicy.usesCloudKit(
            inMemory: false,
            isRunningTests: false
        ))
    }

    @Test func knownCloudKitFailuresRetryWithLocalPersistence() {
        #expect(PersistenceConfigurationPolicy.shouldRetryLocalOnly(
            error: NSError(domain: NSCocoaErrorDomain, code: 134400),
            attemptedCloudKit: true
        ))
        #expect(!PersistenceConfigurationPolicy.shouldRetryLocalOnly(
            error: NSError(domain: NSCocoaErrorDomain, code: 134400),
            attemptedCloudKit: false
        ))
        #expect(!PersistenceConfigurationPolicy.shouldRetryLocalOnly(
            error: NSError(domain: NSCocoaErrorDomain, code: 999),
            attemptedCloudKit: true
        ))
    }

    @Test func persistenceFailureMessagePreservesTheExistingStore() {
        let message = PersistenceConfigurationPolicy.recoveryMessage(
            error: NSError(domain: NSCocoaErrorDomain, code: 640)
        )
        #expect(message.contains("existing store was preserved"))
        #expect(message.contains("640"))
    }

    @Test func diskImageCacheKeysAreStableAcrossRelaunches() {
        let first = DiskImageCachePolicy.fileName(forKey: "book|cover|revision")
        let second = DiskImageCachePolicy.fileName(forKey: "book|cover|revision")
        #expect(first == second)
        #expect(first.count == 68)
        #expect(first.hasSuffix(".jpg"))
    }

    @Test func sharedGrantAppliesOnlyToItsExactMemory() {
        let memoryID = UUID()
        #expect(SharedAccessGrantPolicy.grantsMemory(
            grantedMemoryID: memoryID.uuidString,
            requestedMemoryID: memoryID,
            revoked: false
        ))
        #expect(!SharedAccessGrantPolicy.grantsMemory(
            grantedMemoryID: UUID().uuidString,
            requestedMemoryID: memoryID,
            revoked: false
        ))
        #expect(!SharedAccessGrantPolicy.grantsMemory(
            grantedMemoryID: memoryID.uuidString,
            requestedMemoryID: memoryID,
            revoked: true
        ))
    }
    @Test func speechCompletionGateCanOnlyBeClaimedOnce() {
        let gate = OneShotCompletionGate()

        #expect(gate.claim())
        #expect(!gate.claim())
    }

    @Test func failedMemoryEditRestoresSavedTextAndKeepsEditorOpen() {
        let resolution = MemoryEditSavePolicy.resolve(
            originalText: "Saved story",
            draftText: "Unsaved draft",
            saveSucceeded: false
        )

        #expect(resolution.persistedText == "Saved story")
        #expect(resolution.keepsEditorOpen)
    }

    @Test func successfulMemoryEditCommitsDraftAndClosesEditor() {
        let resolution = MemoryEditSavePolicy.resolve(
            originalText: "Saved story",
            draftText: "Edited story",
            saveSucceeded: true
        )

        #expect(resolution.persistedText == "Edited story")
        #expect(!resolution.keepsEditorOpen)
    }

    @Test func playbackCompletionOnlyResetsItsOwnPlayback() {
        let activeGeneration = UUID()

        #expect(AudioPlaybackCompletionPolicy.shouldResetPlayback(
            completedGeneration: activeGeneration,
            activeGeneration: activeGeneration
        ))
        #expect(!AudioPlaybackCompletionPolicy.shouldResetPlayback(
            completedGeneration: UUID(),
            activeGeneration: activeGeneration
        ))
    }

    @Test func audioAvailabilityUsesMetadataWithoutMaterializingAFile() {
        #expect(MemoryAudioAvailabilityPolicy.hasAudio(
            localFileExists: true,
            embeddedAudioByteCount: nil
        ))
        #expect(MemoryAudioAvailabilityPolicy.hasAudio(
            localFileExists: false,
            embeddedAudioByteCount: 32
        ))
        #expect(!MemoryAudioAvailabilityPolicy.hasAudio(
            localFileExists: false,
            embeddedAudioByteCount: 0
        ))
        #expect(MemoryAudioAvailabilityPolicy.hasAudio(
            localFileExists: false,
            embeddedAudioByteCount: nil,
            hasRemoteAudio: true
        ))
    }

    @Test func recordingControlExposesItsCurrentAction() {
        let ready = PrimaryRecordingControlPolicy.state(isRecording: false, isPaused: false)
        let recording = PrimaryRecordingControlPolicy.state(isRecording: true, isPaused: false)
        let paused = PrimaryRecordingControlPolicy.state(isRecording: true, isPaused: true)

        #expect(ready == .ready)
        #expect(ready.accessibilityLabel == "Start recording")
        #expect(recording == .recording)
        #expect(recording.accessibilityLabel == "Pause recording")
        #expect(paused == .paused)
        #expect(paused.accessibilityLabel == "Resume recording")
        #expect(paused.accessibilityValue == "Paused")
    }

    @Test func audioStoragePathIsPinnedToTheCapturedUser() {
        #expect(StorageOwnershipPolicy.audioPath(
            userID: "user-a",
            memoryID: "memory-1",
            fileExtension: "M4A"
        ) == "users/user-a/audio/memory-1.m4a")
        #expect(StorageOwnershipPolicy.audioPath(
            userID: "user-a",
            memoryID: "memory-1",
            fileExtension: "unexpected"
        ) == "users/user-a/audio/memory-1.caf")
    }

    @Test func delayedMemoryWriteCannotCrossAccounts() {
        #expect(MemoryOwnershipPolicy.canAttemptRemoteWrite(
            intendedUserID: "user-a",
            currentUserID: "user-a"
        ))
        #expect(!MemoryOwnershipPolicy.canAttemptRemoteWrite(
            intendedUserID: "user-a",
            currentUserID: "user-b"
        ))
    }

    @Test func delayedStorybookFinalizeCannotPublishAfterContextSwitch() {
        let profileA = UUID()
        #expect(StorybookAsyncRunPolicy.isCurrent(
            expectedUserID: "user-a",
            expectedProfileID: profileA,
            expectedRun: 4,
            currentUserID: "user-a",
            currentProfileID: profileA,
            currentRun: 4
        ))
        #expect(!StorybookAsyncRunPolicy.isCurrent(
            expectedUserID: "user-a",
            expectedProfileID: profileA,
            expectedRun: 4,
            currentUserID: "user-b",
            currentProfileID: profileA,
            currentRun: 4
        ))
        #expect(!StorybookAsyncRunPolicy.isCurrent(
            expectedUserID: "user-a",
            expectedProfileID: profileA,
            expectedRun: 4,
            currentUserID: "user-a",
            currentProfileID: UUID(),
            currentRun: 5
        ))
    }

    @Test func audioFileHashStreamsTheCanonicalFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("memoirai-hash-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("memoir".utf8).write(to: url, options: .atomic)

        #expect(try FirestoreSyncService.sha256Hex(fileURL: url)
            == "f77b78e7fd6a09bfff820bf00d196bf37e6caf809b6e741a793d4db82489c4b1")
    }

    @Test func persistenceAllowsContentOnlyAfterTheStoreIsReady() {
        #expect(!PersistenceConfigurationPolicy.allowsApplicationContent(state: .loading))
        #expect(PersistenceConfigurationPolicy.allowsApplicationContent(state: .ready))
        #expect(!PersistenceConfigurationPolicy.allowsApplicationContent(
            state: .failed("Store unavailable")
        ))
    }

    @Test func recordingOrphanCleanupPreservesReferencedAndRecentDrafts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("memoirai-orphans-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stale = directory.appendingPathComponent("\(UUID().uuidString).m4a")
        let referenced = directory.appendingPathComponent("\(UUID().uuidString).m4a")
        let recent = directory.appendingPathComponent("\(UUID().uuidString).m4a")
        for url in [stale, referenced, recent] {
            try Data([1]).write(to: url)
        }
        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-48 * 60 * 60)],
            ofItemAtPath: stale.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-48 * 60 * 60)],
            ofItemAtPath: referenced.path
        )

        let removed = RecordingOrphanCleanup.removeStaleRecordings(
            in: directory,
            referencedFileURLs: [referenced],
            now: now,
            gracePeriod: 24 * 60 * 60
        )

        #expect(removed == [stale])
        #expect(FileManager.default.fileExists(atPath: referenced.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
    }
}
