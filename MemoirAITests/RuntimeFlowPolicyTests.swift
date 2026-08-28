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
}
