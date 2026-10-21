import Foundation
import Testing
import UIKit
@testable import MemoirAI

struct RuntimeFlowPolicyTests {
    @Test func parentPromptRevisionPreservesEveryShippedSlot() {
        for chapter in allParentChapters {
            let previous = previousParentChapters.first { $0.number == chapter.number }
            #expect(previous?.title == chapter.title)
            #expect(previous?.prompts.count == chapter.prompts.count)
            for (index, prompt) in chapter.prompts.enumerated() {
                let old = previous?.prompts[index]
                #expect(old?.isPerChild == prompt.isPerChild)
                #expect(old?.x == prompt.x)
                #expect(old?.y == prompt.y)
                let names = prompt.isPerChild ? ["Maya", "Leo", "your child"] : [""]
                for name in names {
                    let currentText = prompt.text.replacingOccurrences(of: "{kid}", with: name)
                    let oldText = old?.text.replacingOccurrences(of: "{kid}", with: name)
                    let recognized = parentPromptTextsIncludingPrevious(currentText, chapterTitle: chapter.title)
                    #expect(recognized.contains(currentText))
                    #expect(oldText.map(recognized.contains) == true)
                }
            }
        }
    }

    @Test func parentPromptAliasesDoNotMixChildrenOrChapters() throws {
        let chapter = try #require(allParentChapters.first { $0.number == 2 })
        let old = try #require(previousParentChapters.first { $0.number == 2 })
        let current = chapter.prompts[0].text.replacingOccurrences(of: "{kid}", with: "Maya")
        let otherChild = old.prompts[0].text.replacingOccurrences(of: "{kid}", with: "Leo")
        #expect(!parentPromptTextsIncludingPrevious(current, chapterTitle: chapter.title).contains(otherChild))
        #expect(parentPromptTextsIncludingPrevious(current, chapterTitle: "Beginnings") == [current])
        #expect(parentPromptTextsIncludingPrevious("My own question", chapterTitle: chapter.title) == ["My own question"])
    }

    @Test func parentProgressRecognizesOldAndNewRecordingsForEverySlot() throws {
        for chapter in allParentChapters {
            let previous = try #require(previousParentChapters.first { $0.number == chapter.number })
            for (index, prompt) in chapter.prompts.enumerated() {
                for source in [prompt, previous.prompts[index]] {
                    let recorded = Set(expandedChildPrompts(for: source, childNames: ["Maya", "Leo"]).map(\.text))
                    #expect(isPromptSlotRecorded(prompt, chapterTitle: chapter.title, childNames: ["Maya", "Leo"], recordedPromptTexts: recorded))
                }
                #expect(!isPromptSlotRecorded(prompt, chapterTitle: chapter.title, childNames: ["Maya", "Leo"], recordedPromptTexts: []))
            }
        }
    }

    @Test func parentProgressRequiresEveryChildButAcceptsMixedPromptVersions() throws {
        let chapter = try #require(allParentChapters.first { $0.number == 2 })
        let previous = try #require(previousParentChapters.first { $0.number == 2 })
        let prompt = chapter.prompts[0]
        let maya = prompt.text.replacingOccurrences(of: "{kid}", with: "Maya")
        let leo = previous.prompts[0].text.replacingOccurrences(of: "{kid}", with: "Leo")
        #expect(!isPromptSlotRecorded(prompt, chapterTitle: chapter.title, childNames: ["Maya", "Leo"], recordedPromptTexts: [maya]))
        #expect(isPromptSlotRecorded(prompt, chapterTitle: chapter.title, childNames: ["Maya", "Leo"], recordedPromptTexts: [maya, leo]))
        #expect(!isPromptSlotRecorded(prompt, chapterTitle: chapter.title, childNames: ["Maya", "Leo", "Sam"], recordedPromptTexts: [maya, leo]))
        #expect(!isPromptSlotRecorded(chapter.prompts[1], chapterTitle: chapter.title, childNames: ["Maya", "Leo"], recordedPromptTexts: [maya, leo]))
    }

    @Test func parentProgressWithoutChildNamesMatchesNeutralRecordings() throws {
        let chapter = try #require(allParentChapters.first { $0.number == 2 })
        let previous = try #require(previousParentChapters.first { $0.number == 2 })
        let prompt = chapter.prompts[0]
        for source in [prompt, previous.prompts[0]] {
            let neutral = source.text.replacingOccurrences(of: "{kid}", with: "your child")
            #expect(isPromptSlotRecorded(prompt, chapterTitle: chapter.title, childNames: [], recordedPromptTexts: [neutral]))
        }
        let named = prompt.text.replacingOccurrences(of: "{kid}", with: "Maya")
        #expect(!isPromptSlotRecorded(prompt, chapterTitle: chapter.title, childNames: [], recordedPromptTexts: [named]))
    }

    @Test func onlyAutomaticStorybookEntryResumesPendingGeneration() {
        #expect(!StorybookScreenEntry.standard.resumesPendingGeneration)
        #expect(StorybookScreenEntry.autoResumePendingGeneration.resumesPendingGeneration)
    }

    @Test func developerUnlockIsAvailableAcrossDistributionChannels() {
        #expect(DeveloperAccessDistributionPolicy.permitsRemoteUnlock(
            receiptLastPathComponent: "sandboxReceipt"
        ))
        #expect(DeveloperAccessDistributionPolicy.permitsRemoteUnlock(
            receiptLastPathComponent: "receipt"
        ))
        #expect(DeveloperAccessDistributionPolicy.permitsRemoteUnlock(
            receiptLastPathComponent: nil
        ))
    }

    @Test func developerGenerationNeverExhaustsAllowance() {
        #expect(GenerationAllowancePolicy.canGenerate(
            pages: Int.max, remaining: 0, hasSubscription: false, developerUnlocked: true
        ))
        #expect(GenerationAllowancePolicy.remainingAfterConsumption(
            pages: Int.max, remaining: Int.max, developerUnlocked: true
        ) == Int.max)
    }

    @Test func regularGenerationStillRequiresSubscriptionAndAllowance() {
        #expect(!GenerationAllowancePolicy.canGenerate(
            pages: 1, remaining: 100, hasSubscription: false, developerUnlocked: false
        ))
        #expect(!GenerationAllowancePolicy.canGenerate(
            pages: 2, remaining: 1, hasSubscription: true, developerUnlocked: false
        ))
        #expect(GenerationAllowancePolicy.canGenerate(
            pages: 2, remaining: 2, hasSubscription: true, developerUnlocked: false
        ))
        #expect(GenerationAllowancePolicy.remainingAfterConsumption(
            pages: 2, remaining: 3, developerUnlocked: false
        ) == 1)
        #expect(GenerationAllowancePolicy.remainingAfterConsumption(
            pages: Int.max, remaining: 3, developerUnlocked: false
        ) == 0)
        #expect(GenerationAllowancePolicy.remainingAfterConsumption(
            pages: -1, remaining: 3, developerUnlocked: false
        ) == 3)
    }

    @Test func developerCodeDigestComparisonIsExact() {
        #expect(DeveloperAccessCodePolicy.constantTimeMatches(
            candidateDigest: "abcdef",
            expectedDigest: "abcdef"
        ))
        #expect(!DeveloperAccessCodePolicy.constantTimeMatches(
            candidateDigest: "abcdeg",
            expectedDigest: "abcdef"
        ))
        #expect(!DeveloperAccessCodePolicy.constantTimeMatches(
            candidateDigest: "short",
            expectedDigest: "longer"
        ))
    }

    @Test func developerOverrideNeverSyncsAsPaidEntitlement() {
        #expect(!DeveloperEntitlementSyncPolicy.shouldSync(isDeveloperUnlocked: true))
        #expect(DeveloperEntitlementSyncPolicy.shouldSync(isDeveloperUnlocked: false))
    }

    @Test func explicitMemoirModeWinsOverLegacyPromptInference() {
        let memory = MemoryMemoirMetadata(
            storedModeRawValue: MemoirMode.parent.rawValue,
            chapter: allChapters[0].title,
            prompt: allChapters[0].prompts[0].text
        )

        #expect(MemoirModeClassifier.classify(memory) == .parent)
    }

    @Test func classifierRecognizesCurrentAndLegacyMemoirQuestions() {
        let life = MemoryMemoirMetadata(
            storedModeRawValue: nil,
            chapter: allChapters[0].title,
            prompt: allChapters[0].prompts[0].text
        )
        let parentLegacyChapter = allChaptersLegacyKnownPrompts.first { $0.number == 101 }!
        let parent = MemoryMemoirMetadata(
            storedModeRawValue: nil,
            chapter: parentLegacyChapter.title,
            prompt: parentLegacyChapter.prompts[0].text
        )
        let loveLegacyChapter = allChaptersLegacyKnownPrompts.first { $0.number == 201 }!
        let love = MemoryMemoirMetadata(
            storedModeRawValue: nil,
            chapter: loveLegacyChapter.title,
            prompt: loveLegacyChapter.prompts[0].text
        )

        #expect(MemoirModeClassifier.classify(life) == .normal)
        #expect(MemoirModeClassifier.classify(parent) == .parent)
        #expect(MemoirModeClassifier.classify(love) == .relationships)
    }

    @Test func ambiguousOrUncategorizedLegacyMemoriesStayUnclassified() {
        #expect(MemoirModeClassifier.classify(MemoryMemoirMetadata(
            storedModeRawValue: nil,
            chapter: "Childhood",
            prompt: "A custom question"
        )) == nil)
        #expect(MemoirModeClassifier.classify(MemoryMemoirMetadata(
            storedModeRawValue: nil,
            chapter: nil,
            prompt: "A freeform memory"
        )) == nil)
        #expect(MemoirModeClassifier.classify(MemoryMemoirMetadata(
            storedModeRawValue: "future-mode",
            chapter: allChapters[0].title,
            prompt: allChapters[0].prompts[0].text
        )) == nil)
    }

    @Test func modeFilterShowsOnlyPopulatedMemoirsAndKeepsAllInclusive() {
        let life = MemoryMemoirMetadata(
            storedModeRawValue: MemoirMode.normal.rawValue,
            chapter: nil,
            prompt: nil
        )
        let love = MemoryMemoirMetadata(
            storedModeRawValue: MemoirMode.relationships.rawValue,
            chapter: nil,
            prompt: nil
        )
        let unclassified = MemoryMemoirMetadata(
            storedModeRawValue: nil,
            chapter: nil,
            prompt: "Freeform"
        )

        #expect(MemoirModeFilterPolicy.availableModes(in: [love, unclassified, life]) == [.normal, .relationships])
        #expect(MemoirModeFilterPolicy.includes(unclassified, mode: nil))
        #expect(!MemoirModeFilterPolicy.includes(unclassified, mode: .normal))
        #expect(MemoirModeFilterPolicy.includes(love, mode: .relationships))
    }

    @Test func everyRelationshipChapterHasUniqueBundledArtwork() {
        let assetNames = allRelationshipChapters.compactMap {
            relationshipChapterImageAssetName(forChapterNumber: $0.number)
        }

        #expect(assetNames.count == 10)
        #expect(Set(assetNames).count == 10)
        #expect(allRelationshipChapters.allSatisfy {
            relationshipChapterImageAssetName(forChapterTitle: $0.title) != nil
        })
        #expect(assetNames.allSatisfy { UIImage(named: $0) != nil })
        #expect(relationshipChapterImageAssetName(forChapterNumber: 0) == nil)
        #expect(relationshipChapterImageAssetName(forChapterNumber: 11) == nil)
    }

    @Test func relationshipChaptersUseResponsiveArtworkCoordinates() {
        for chapterNumber in 1...10 {
            let relationshipCoordinates = ChapterJourneyNodeLayoutPolicy.coordinates(
                forRelationshipChapterNumber: chapterNumber
            )
            #expect(relationshipCoordinates.count == 4)
            #expect(relationshipCoordinates.allSatisfy {
                (0...1).contains($0.x) && (0...1).contains($0.y)
            })
        }

        #expect(ChapterJourneyNodeLayoutPolicy.coordinates(
            forRelationshipChapterNumber: 0
        ) == ChapterJourneyNodeLayoutPolicy.coordinates(forChapterTitle: "Unknown"))
    }

    @Test func chapterAliasesUseThePinnedMemoirMode() {
        #expect(chapterTitleMatches(
            "Beginning",
            "First Glimpse",
            memoirMode: .relationships
        ))
        #expect(!chapterTitleMatches(
            "Beginning",
            "First Glimpse",
            memoirMode: .normal
        ))
        #expect(chapterTitleMatches(
            "Childhood",
            "Beginnings",
            memoirMode: .normal
        ))
    }

    @Test func storybookHistoryRetentionCapsRevisionCountAndBytes() {
        let small = Array(repeating: 1_000, count: StorybookHistoryRetentionPolicy.maximumRevisionCount + 2)
        #expect(StorybookHistoryRetentionPolicy.removalCount(forOldestFirstByteCounts: small) == 2)

        let oversized = [
            StorybookHistoryRetentionPolicy.maximumTotalByteCount,
            10,
            10
        ]
        #expect(StorybookHistoryRetentionPolicy.removalCount(forOldestFirstByteCounts: oversized) == 1)
        #expect(StorybookHistoryRetentionPolicy.removalCount(
            forOldestFirstByteCounts: [StorybookHistoryRetentionPolicy.maximumTotalByteCount + 1]
        ) == 0)
    }
    @Test func legacyGenerationCountsAreClampedAtTheServerContract() {
        #expect(StorybookGenerationBatchPolicy.clampedTargetPageCount(0) == 1)
        #expect(StorybookGenerationBatchPolicy.clampedTargetPageCount(3) == 3)
        #expect(StorybookGenerationBatchPolicy.clampedTargetPageCount(100) == 9)
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
        #expect(PersistenceConfigurationPolicy.isRunningTests(
            environment: [:],
            arguments: ["MemoirAI", "-UITestRelationshipChapter", "3"]
        ))
        #expect(PersistenceConfigurationPolicy.isRunningTests(
            environment: ["XCTestConfigurationFilePath": "/tmp/test"],
            arguments: ["MemoirAI"]
        ))
        #expect(!PersistenceConfigurationPolicy.isRunningTests(
            environment: [:],
            arguments: ["MemoirAI"]
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

    @Test func playbackSessionIsConfiguredBeforeActivation() throws {
        final class SessionSpy: AudioPlaybackSessionConfiguring {
            var calls: [String] = []
            func setPlaybackCategory() throws { calls.append("category") }
            func activatePlaybackSession() throws { calls.append("active") }
        }

        let session = SessionSpy()
        try AudioPlaybackSessionPreparer(session: session).prepare()

        #expect(session.calls == ["category", "active"])
    }

    @Test func playbackSessionDoesNotActivateWhenCategoryConfigurationFails() {
        struct ExpectedFailure: Error {}
        final class SessionSpy: AudioPlaybackSessionConfiguring {
            var didActivate = false
            func setPlaybackCategory() throws { throw ExpectedFailure() }
            func activatePlaybackSession() throws { didActivate = true }
        }

        let session = SessionSpy()
        #expect(throws: ExpectedFailure.self) {
            try AudioPlaybackSessionPreparer(session: session).prepare()
        }
        #expect(!session.didActivate)
    }

    @Test func playbackErrorsDescribeTheActualFailureBoundary() {
        let session = AudioPlaybackErrorPolicy.message(for: .session)
        let local = AudioPlaybackErrorPolicy.message(for: .localMedia)
        let remote = AudioPlaybackErrorPolicy.message(for: .remoteMedia)

        #expect(session.contains("playback couldn’t start"))
        #expect(local.contains("saved recording"))
        #expect(remote.contains("downloaded"))
        #expect(Set([session, local, remote]).count == 3)
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

    @Test func restoredAudioAcceptsOnlyValidHTTPSReferences() {
        #expect(MemoryAudioAvailabilityPolicy.remoteURL(
            storedReference: "https://firebasestorage.googleapis.com/audio/memory.m4a"
        ) != nil)
        #expect(MemoryAudioAvailabilityPolicy.remoteURL(
            storedReference: "file:///private/recording.m4a"
        ) == nil)
        #expect(MemoryAudioAvailabilityPolicy.remoteURL(
            storedReference: "http://example.com/recording.m4a"
        ) == nil)
        #expect(MemoryAudioAvailabilityPolicy.remoteURL(
            storedReference: "not a url"
        ) == nil)
    }

    @Test func audioStorageFallbackAcceptsOnlyTheOwnedMemoryPath() {
        #expect(StorageOwnershipPolicy.isOwnedAudioPath(
            "users/user-1/audio/memory-1.m4a",
            userID: "user-1",
            memoryID: "memory-1"
        ))
        #expect(StorageOwnershipPolicy.isOwnedAudioPath(
            "users/user-1/audio/memory-1.caf",
            userID: "user-1",
            memoryID: "memory-1"
        ))
        #expect(!StorageOwnershipPolicy.isOwnedAudioPath(
            "users/user-2/audio/memory-1.m4a",
            userID: "user-1",
            memoryID: "memory-1"
        ))
        #expect(!StorageOwnershipPolicy.isOwnedAudioPath(
            "users/user-1/audio/other-memory.m4a",
            userID: "user-1",
            memoryID: "memory-1"
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

    @Test func recordingStartRequiresAnAuthenticatedUserScope() {
        #expect(MemoryUserScope.recordingStartFailureMessage(firebaseUserID: nil) != nil)
        #expect(MemoryUserScope.recordingStartFailureMessage(firebaseUserID: "   ") != nil)
        #expect(MemoryUserScope.recordingStartFailureMessage(firebaseUserID: "anonymous-user") == nil)
        #expect(MemoryUserScope.recordingStartFailureMessage(firebaseUserID: " signed-in-user ") == nil)
    }

    @Test func cloudTranscriptionDisclosureUsesSharedVendorNeutralCopy() {
        #expect(CloudTranscriptionDisclosure.title == "Audio & Transcription Privacy")
        #expect(CloudTranscriptionDisclosure.message.contains("transcription provider"))
        #expect(!CloudTranscriptionDisclosure.message.localizedCaseInsensitiveContains("OpenAI"))
    }

    @Test func recordingContentUsesThePhoneWidthAndCapsLargeScreens() {
        #expect(RecordingLayoutPolicy.contentWidth(availableWidth: 393) == 393)
        #expect(RecordingLayoutPolicy.contentWidth(availableWidth: 1_366) == 760)
        #expect(RecordingLayoutPolicy.contentWidth(availableWidth: 0) == 0)
        #expect(RecordingLayoutPolicy.contentWidth(availableWidth: .infinity) == 0)
    }

    @Test func recordingTextFocusUsesTheDedicatedWritingLayout() {
        #expect(RecordingLayoutPolicy.showsVoiceControls(isTextFocused: false))
        #expect(!RecordingLayoutPolicy.showsVoiceControls(isTextFocused: true))
    }

    @Test func recordingLayoutKeepsContentBelowSafeAreaAndBalancesExtraHeight() {
        #expect(RecordingLayoutPolicy.minimumTopSpacing(safeAreaTop: 0) == 72)
        #expect(RecordingLayoutPolicy.minimumTopSpacing(safeAreaTop: 59) == 103)
        #expect(RecordingLayoutPolicy.minimumTopSpacing(safeAreaTop: .infinity) == 72)
    }

    @Test func recordingBackButtonClearsTheDeviceSafeArea() {
        #expect(RecordingLayoutPolicy.backButtonTopPadding(safeAreaTop: 0) == 16)
        #expect(RecordingLayoutPolicy.backButtonTopPadding(safeAreaTop: 47) == 59)
        #expect(RecordingLayoutPolicy.backButtonTopPadding(safeAreaTop: 59) == 71)
        #expect(RecordingLayoutPolicy.backButtonTopPadding(safeAreaTop: .infinity) == 16)
    }

    @Test func chapterJourneyCanvasPreservesCanonicalArtworkAspectRatio() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let canvas = ChapterJourneyLayoutPolicy.artworkFrame(in: bounds)
        let expectedAspect = ChapterJourneyLayoutPolicy.canonicalArtworkSize.width
            / ChapterJourneyLayoutPolicy.canonicalArtworkSize.height

        #expect(abs(canvas.width / canvas.height - expectedAspect) < 0.000_001)
        #expect(canvas.midX == bounds.midX)
        #expect(canvas.minY == bounds.minY)
        #expect(canvas.minX <= bounds.minX)
        #expect(canvas.maxX >= bounds.maxX)
        #expect(canvas.maxY >= bounds.maxY)
        #expect(abs(canvas.width - 562.22) < 0.1)
    }

    @Test func chapterJourneyKeepsTopNodesBelowTheHeaderAcrossViewports() {
        let viewports = [
            CGSize(width: 393, height: 852),
            CGSize(width: 430, height: 932),
            CGSize(width: 1_024, height: 1_366),
            CGSize(width: 1_366, height: 1_024),
            CGSize(width: 852, height: 393)
        ]

        for viewport in viewports {
            let bounds = CGRect(origin: .zero, size: viewport)
            let artwork = ChapterJourneyLayoutPolicy.artworkFrame(in: bounds)
            #expect(artwork.minY == 0)
            #expect(artwork.width >= viewport.width)
            #expect(artwork.height >= viewport.height)

            for title in allChapters.map(\.title) + allParentChapters.map(\.title) {
                for coordinate in ChapterJourneyNodeLayoutPolicy.coordinates(forChapterTitle: title) {
                    let point = ChapterJourneyLayoutPolicy.point(
                        normalizedX: coordinate.x,
                        normalizedY: coordinate.y,
                        in: artwork
                    )
                    #expect(point.y >= 150)
                    #expect(point.y <= artwork.maxY)
                }
            }
        }
    }

    @Test func chapterJourneyMarkersMapOntoTheFilledArtwork() {
        let canvas = ChapterJourneyLayoutPolicy.artworkFrame(
            in: CGRect(x: 0, y: 0, width: 1_366, height: 1_024)
        )
        let center = ChapterJourneyLayoutPolicy.point(
            normalizedX: 0.5,
            normalizedY: 0.5,
            in: canvas
        )
        let clamped = ChapterJourneyLayoutPolicy.point(
            normalizedX: 2,
            normalizedY: -1,
            in: canvas
        )

        #expect(center.x == canvas.midX)
        #expect(center.y == canvas.midY)
        #expect(clamped.x == canvas.maxX)
        #expect(clamped.y == canvas.minY)
    }

    @Test func chapterJourneyUsesCoordinatesForEachArtworkTrail() {
        let beginnings = ChapterJourneyNodeLayoutPolicy.coordinates(forChapterTitle: "Beginnings")
        let growingUp = ChapterJourneyNodeLayoutPolicy.coordinates(forChapterTitle: "Growing Up")
        let parentAlias = ChapterJourneyNodeLayoutPolicy.coordinates(forChapterTitle: "The Day They Arrived")

        #expect(beginnings.count == 4)
        #expect(growingUp.count == 4)
        #expect(growingUp != beginnings)
        #expect(parentAlias == growingUp)
        #expect(growingUp[0] == CGPoint(x: 0.55, y: 0.80))
        #expect(growingUp[2] == CGPoint(x: 0.66, y: 0.44))

        for title in allChapters.map(\.title) + allParentChapters.map(\.title) {
            let coordinates = ChapterJourneyNodeLayoutPolicy.coordinates(forChapterTitle: title)
            #expect(coordinates.count == 4)
            #expect(coordinates.allSatisfy {
                $0.x.isFinite && $0.y.isFinite
                    && (0...1).contains($0.x)
                    && (0...1).contains($0.y)
            })
        }
    }

    @Test func chapterPathMarkersRemainFullyVisibleAcrossDeviceWidths() {
        let sizes = [
            CGSize(width: 320, height: 568), CGSize(width: 375, height: 812),
            CGSize(width: 393, height: 852), CGSize(width: 430, height: 932),
            CGSize(width: 768, height: 1024), CGSize(width: 1024, height: 1366),
            CGSize(width: 1366, height: 1024), CGSize(width: 852, height: 393)
        ]
        for size in sizes {
            let frame = ChapterJourneyLayoutPolicy.artworkFrame(in: CGRect(origin: .zero, size: size))
            for chapter in allChapters + allParentChapters {
                for anchor in ChapterJourneyNodeLayoutPolicy.coordinates(forChapterTitle: chapter.title) {
                    let point = ChapterJourneyLayoutPolicy.point(normalizedX: anchor.x, normalizedY: anchor.y, in: frame)
                    #expect(point.x >= 30)
                    #expect(point.x <= size.width - 30)
                    #expect(point.y >= 160)
                    #expect(point.y <= frame.height - 30)
                }
            }
        }
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
