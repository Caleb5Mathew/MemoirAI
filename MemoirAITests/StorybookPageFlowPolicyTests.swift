import Foundation
import CoreData
import Testing
@testable import MemoirAI

struct StorybookPageFlowPolicyTests {
    @Test func maximumStandardBookPadsToPrintableHardcoverMinimum() {
        let unpaddedPageCount = 3 + (StorybookGenerationBatchPolicy.maximumPagesPerBook * 2)
        #expect(unpaddedPageCount == 21)
        #expect(BookPrintPaddingPolicy.paddingCount(for: unpaddedPageCount) == 3)
        #expect(unpaddedPageCount + BookPrintPaddingPolicy.paddingCount(for: unpaddedPageCount) == 24)
        #expect(BookPrintPaddingPolicy.paddingCount(for: 20) == 0)
        #expect(BookPrintPaddingPolicy.paddingCount(for: 24) == 0)
        #expect(BookPrintPaddingPolicy.paddingCount(for: 25) == 1)
    }

    @Test func generatedMemoryPagesPreferTheAIStoryTitleOverTheInterviewPrompt() {
        #expect(StorybookGeneratedMemoryTitlePolicy.title(
            illustrationTitle: " Sunflowers Beside the Porch ", extractedTitle: "Sunflowers Beside the Porch",
            displayTitle: "What type of kid were you?", prompt: "What type of kid were you?"
        ) == "Sunflowers Beside the Porch")
        #expect(StorybookGeneratedMemoryTitlePolicy.title(
            illustrationTitle: " ", extractedTitle: "A summer afternoon", displayTitle: "Old prompt", prompt: "Prompt"
        ) == "A summer afternoon")
        #expect(StorybookGeneratedMemoryTitlePolicy.title(
            illustrationTitle: nil, extractedTitle: nil, displayTitle: "Older generated title", prompt: "Prompt"
        ) == "Older generated title")
        #expect(StorybookGeneratedMemoryTitlePolicy.title(
            illustrationTitle: nil, extractedTitle: nil, displayTitle: " ", prompt: "Saved prompt"
        ) == "Saved prompt")
        #expect(StorybookGeneratedMemoryTitlePolicy.title(
            illustrationTitle: nil, extractedTitle: nil, displayTitle: nil, prompt: " "
        ) == "Memory")
    }

    @Test func generatedBookWaitsForCoverPreparationButDoesNotStrandOnFailure() {
        #expect(!StorybookCoverRevealPolicy.shouldReveal(
            canonicalArtifactsReady: false,
            coverPreparation: .ready
        ))
        #expect(!StorybookCoverRevealPolicy.shouldReveal(
            canonicalArtifactsReady: true,
            coverPreparation: .pending
        ))
        #expect(StorybookCoverRevealPolicy.shouldReveal(
            canonicalArtifactsReady: true,
            coverPreparation: .ready
        ))
        #expect(StorybookCoverRevealPolicy.shouldReveal(
            canonicalArtifactsReady: true,
            coverPreparation: .failed
        ))
    }

    @Test func galleryImageDownloadsRejectFailuresAndOversizedPayloads() {
        #expect(StorybookReaderImagePolicy.accepts(statusCode: 200, byteCount: 1))
        #expect(!StorybookReaderImagePolicy.accepts(statusCode: 404, byteCount: 1))
        #expect(!StorybookReaderImagePolicy.accepts(statusCode: 200, byteCount: 0))
        #expect(!StorybookReaderImagePolicy.accepts(
            statusCode: 200,
            byteCount: StorybookReaderImagePolicy.maximumByteCount + 1
        ))
    }
    @Test func loadedBookPresentationUsesViewModelState() {
        #expect(StorybookPagePresentationPolicy.shouldShowLoadedBook(
            hasGeneratedStorybook: true,
            pageCount: 6
        ))
        #expect(!StorybookPagePresentationPolicy.shouldShowLoadedBook(
            hasGeneratedStorybook: false,
            pageCount: 6
        ))
        #expect(!StorybookPagePresentationPolicy.shouldShowLoadedBook(
            hasGeneratedStorybook: true,
            pageCount: 0
        ))
    }

    @Test func restoredInteriorWaitsForCanonicalCoverMetadata() {
        let localSlots = StorybookReaderSlotPolicy.slots(interiorPageCount: 9, hasExteriorCover: false)
        #expect(localSlots.first == .interiorPage(0))
        #expect(StorybookPagePresentationPolicy.shouldShowProfileLoadingOverlay(
            isLoadingProfileBook: true,
            hasLoadedBook: true,
            hasCanonicalBookMetadata: false
        ))

        let canonicalSlots = StorybookReaderSlotPolicy.slots(interiorPageCount: 9, hasExteriorCover: true)
        #expect(canonicalSlots.first == .cover(.front))
        #expect(!StorybookPagePresentationPolicy.shouldShowProfileLoadingOverlay(
            isLoadingProfileBook: true,
            hasLoadedBook: true,
            hasCanonicalBookMetadata: true
        ))
    }

    @Test func resolvedCoverlessBooksAndOfflineFallbackRemainReadable() {
        #expect(!StorybookPagePresentationPolicy.shouldShowProfileLoadingOverlay(
            isLoadingProfileBook: true,
            hasLoadedBook: true,
            hasCanonicalBookMetadata: true
        ))
        #expect(!StorybookPagePresentationPolicy.shouldShowProfileLoadingOverlay(
            isLoadingProfileBook: false,
            hasLoadedBook: true,
            hasCanonicalBookMetadata: false
        ))
    }

    @Test func profileReconciliationDoesNotBlockAnEmptyBook() {
        for isLoading in [true, false] {
            #expect(!StorybookPagePresentationPolicy.shouldShowProfileLoadingOverlay(
                isLoadingProfileBook: isLoading,
                hasLoadedBook: false,
                hasCanonicalBookMetadata: false
            ))
        }
    }

    @Test func pageSelectionClampsWhenBookPagesChange() {
        #expect(StorybookPagePresentationPolicy.clampedPageIndex(6, pageCount: 6) == 5)
        #expect(StorybookPagePresentationPolicy.clampedPageIndex(-1, pageCount: 6) == 0)
        #expect(StorybookPagePresentationPolicy.clampedPageIndex(3, pageCount: 0) == 0)
    }

    @Test func loadingCopyExistsOnlyForExplicitLibraryOpen() {
        let library = StorybookPagePresentationPolicy.loadingCopy(isLibrarySelection: true)
        let initial = StorybookPagePresentationPolicy.loadingCopy(isLibrarySelection: false)

        #expect(library.title == "Opening your book…")
        #expect(initial.title.isEmpty)
        #expect(initial.subtitle.isEmpty)
    }

    @Test func interiorMemoirSubtitleUsesCollectionCopy() {
        let policy = CoverCopyPolicy(artStyle: .kidsBook, profileDisplayName: "Caleb")
        #expect(policy.interiorTitlePageBlurb() == "A collection of life stories")
        #expect(StorybookBookendRecoveryPolicy.recoveredMemoryID(
            storedMemoryID: nil, pageType: "textPage", title: "Alice’s Memoir",
            textContent: "A collection of memories from Alice’s life."
        ) == BookInteriorAnchor.titlePageMemoryId)
        #expect(StorybookBookendRecoveryPolicy.recoveredMemoryID(
            storedMemoryID: nil, pageType: "textPage", title: "An afternoon",
            textContent: "A collection of life stories"
        ) == nil)
    }

    @Test func memoirNameRejectsPlaceholdersAndNormalizesWhitespace() {
        for name in ["", " ", "Grandparent", "NARRATOR", "MemoirAI Reader", "Unknown"] {
            #expect(StorybookMemoirNamePolicy.usableName(name) == nil)
        }
        #expect(StorybookMemoirNamePolicy.usableName("  María\n  O’Neill ") == "María O’Neill")
        #expect(StorybookMemoirNamePolicy.usableName(String(repeating: "a", count: 101)) == nil)
        #expect(StorybookMemoirNamePolicy.usableName("Grandma Rose") == "Grandma Rose")
    }

    @Test func memoirNameUsesProfileBeforeUnambiguousNarrator() {
        #expect(StorybookMemoirNamePolicy.resolvedName(profileName: "Alice", narratorNames: ["Bob"]) == "Alice")
        #expect(StorybookMemoirNamePolicy.resolvedName(profileName: "Grandparent", narratorNames: ["Alice", "alice"]) == "Alice")
        #expect(StorybookMemoirNamePolicy.resolvedName(profileName: "Grandparent", narratorNames: ["Alice", "Bob"]) == nil)
        #expect(StorybookMemoirNamePolicy.resolvedName(profileName: nil, narratorNames: ["Narrator"]) == nil)
    }

    @Test func memoirTitleUsesUnicodePossessiveAndSafeFallback() {
        #expect(StorybookMemoirNamePolicy.bookTitle(for: "James") == "James’s Memoir")
        #expect(StorybookMemoirNamePolicy.bookTitle(for: "María O’Neill") == "María O’Neill’s Memoir")
        #expect(StorybookMemoirNamePolicy.bookTitle(for: "Grandparent") == "Memoir")
        #expect(CoverCopyPolicy(artStyle: .kidsBook, profileDisplayName: "Alice").defaultBookTitle() == "Alice’s Memoir")
    }

    @MainActor @Test func memoirNameReadsOnlyExplicitNarratorCharacters() {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let narrator = MemoryEntry(context: context)
        narrator.setValue(#"{"characters":[{"name":"Alice (me)","relationshipToNarrator":"self"},{"name":"Bob","relationshipToNarrator":"son"}]}"#, forKey: "characterDetails")
        let other = MemoryEntry(context: context)
        other.setValue(#"{"characters":[{"name":"Robert","relationshipToNarrator":"someone I met"},{"name":"Mary","relationshipToNarrator":"mother"}]}"#, forKey: "characterDetails")
        let conflict = MemoryEntry(context: context)
        conflict.setValue(#"{"characters":[{"name":"Evelyn","relationshipToNarrator":"narrator"}]}"#, forKey: "characterDetails")
        let invalid = MemoryEntry(context: context)
        invalid.setValue("invalid JSON", forKey: "characterDetails")
        let viewModel = StoryPageViewModel()
        #expect(viewModel.memoirName(profileName: "Grandparent", memories: [narrator, other]) == "Alice")
        #expect(viewModel.memoirName(profileName: "Grandparent", memories: [other, invalid]) == nil)
        #expect(viewModel.memoirName(profileName: "Grandparent", memories: [narrator, conflict]) == nil)
        #expect(viewModel.memoirName(profileName: "María", memories: [narrator, conflict]) == "María")
    }

    @MainActor @Test func profileRenameMatchesStableIDInsteadOfStaleFields() {
        let viewModel = ProfileViewModel()
        let original = viewModel.selectedProfile
        var changed = original
        changed.gender = "Female"
        viewModel.updateProfile(changed)
        viewModel.updateName(for: original, to: "Evelyn")
        #expect(viewModel.selectedProfile.name == "Evelyn")
        #expect(viewModel.selectedProfile.gender == "Female")
        #expect(viewModel.selectedProfile.id == original.id)
        viewModel.updateName(for: Profile(name: "Unrelated"), to: "Wrong person")
        #expect(viewModel.selectedProfile.name == "Evelyn")
    }

    @MainActor @Test func failedInteriorUpgradeDoesNotInventUnpublishedEdits() async {
        let model = StoryPageViewModel()
        #expect(!(await model.saveCurrentBookInPlace(reason: "interiorDesignUpdate")))
        #expect(!model.hasUnpublishedBookChanges)
        #expect(!(await model.saveCurrentBookInPlace(reason: "textPageEdit")))
        #expect(!(await model.saveCurrentBookInPlace(reason: "interiorDesignUpdate")))
        #expect(model.hasUnpublishedBookChanges)
    }

    @Test func interiorLayoutUpgradeRequiresANewPublishedVersion() throws {
        var data: [String: Any] = [
            "bookVersionId": "original", "profileId": "profile", "pageCount": 4,
            "artStyle": "kidsBook", "orientation": "landscape", "pageWidth": 792.0,
            "pageHeight": 612.0, "source": "story_generation"
        ]
        let legacy = try #require(BookVersionRecord.fromFirestoreData(data))
        #expect(legacy.layoutVersion == 1)
        #expect(BookInteriorUpgradePolicy.needsUpdate(layoutVersion: legacy.layoutVersion))
        #expect(!BookInteriorUpgradePolicy.needsUpdate(layoutVersion: BookPrintSpec.layoutVersion))
        #expect(!BookInteriorUpgradePolicy.needsUpdate(layoutVersion: BookPrintSpec.layoutVersion + 1))
        #expect(!BookInteriorUpgradePolicy.canOrderPublishedUpdate(previousBookID: "original", record: legacy, hasUnpublishedChanges: false))
        data["bookVersionId"] = "updated"
        data["layoutVersion"] = BookPrintSpec.layoutVersion
        let updated = try #require(BookVersionRecord.fromFirestoreData(data))
        #expect(BookInteriorUpgradePolicy.canOrderPublishedUpdate(previousBookID: "original", record: updated, hasUnpublishedChanges: false))
        #expect(!BookInteriorUpgradePolicy.canOrderPublishedUpdate(previousBookID: "original", record: updated, hasUnpublishedChanges: true))
        #expect(!BookInteriorUpgradePolicy.canOrderPublishedUpdate(previousBookID: "original", record: nil, hasUnpublishedChanges: false))
        #expect(BookRevisionSavePolicy.reusesExistingCover(for: "interiorDesignUpdate"))
    }

    @Test func catalogUsesTheHumanPrintTitleBeforeTheInternalBookKey() {
        #expect(BookCatalogTitlePolicy.displayTitle(
            printTitle: "Evelyn Hart's Memoir",
            bookDisplayName: "user392_book37",
            firstPageTitle: "First Memory"
        ) == "Evelyn Hart's Memoir")
        #expect(BookCatalogTitlePolicy.displayTitle(
            printTitle: " ",
            bookDisplayName: "user392_book37",
            firstPageTitle: "First Memory"
        ) == "user392_book37")
    }

    @Test func readerWrapsInteriorPagesWithTheGeneratedExteriorCover() {
        #expect(StorybookReaderSlotPolicy.slots(
            interiorPageCount: 3,
            hasExteriorCover: true
        ) == [
            .cover(.front),
            .interiorPage(0),
            .interiorPage(1),
            .interiorPage(2),
            .cover(.back)
        ])
        #expect(StorybookReaderSlotPolicy.slots(
            interiorPageCount: 2,
            hasExteriorCover: false
        ) == [.interiorPage(0), .interiorPage(1)])
    }

    @Test func allInteriorAnchorsAreRecognizedAsNonMemoryPages() {
        #expect(BookInteriorAnchor.isNonMemoryPage(BookInteriorAnchor.titlePageMemoryId))
        #expect(BookInteriorAnchor.isNonMemoryPage(BookInteriorAnchor.blankPageMemoryId))
        #expect(BookInteriorAnchor.isNonMemoryPage(BookInteriorAnchor.closingPageMemoryId))
        #expect(!BookInteriorAnchor.isNonMemoryPage(UUID()))
    }

    @Test func everyVisibleReaderSlotUsesTheUnifiedPageEditor() {
        #expect(StorybookPageEditDestinationPolicy.target(for: .cover(.front)) == .exteriorCover(.front))
        #expect(StorybookPageEditDestinationPolicy.target(for: .interiorPage(0)) == .interiorPage(0))
        #expect(StorybookPageEditDestinationPolicy.target(for: .interiorPage(4)) == .interiorPage(4))
        #expect(StorybookPageEditDestinationPolicy.target(for: .interiorPage(8)) == .interiorPage(8))
        #expect(StorybookPageEditDestinationPolicy.target(for: .interiorPage(9)) == .interiorPage(9))
        #expect(StorybookPageEditDestinationPolicy.target(for: .cover(.back)) == .exteriorCover(.back))
    }

    @Test func interiorBookendIDsAcceptNormalizedFirestoreUUIDStrings() {
        let lowercaseClosingID = BookInteriorAnchor.closingPageMemoryId.uuidString.lowercased()
        #expect(StorybookInteriorAnchorPolicy.matches(
            memoryID: "  \(lowercaseClosingID)\n",
            anchor: BookInteriorAnchor.closingPageMemoryId
        ))
        #expect(!StorybookInteriorAnchorPolicy.matches(
            memoryID: BookInteriorAnchor.titlePageMemoryId.uuidString,
            anchor: BookInteriorAnchor.closingPageMemoryId
        ))
        #expect(!StorybookInteriorAnchorPolicy.matches(
            memoryID: "not-a-uuid",
            anchor: BookInteriorAnchor.closingPageMemoryId
        ))
        #expect(!StorybookInteriorAnchorPolicy.matches(
            memoryID: nil,
            anchor: BookInteriorAnchor.closingPageMemoryId
        ))
    }

    @Test func persistedPageLinksPreserveMemoryAndBookendIdentifiers() {
        let memoryID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        #expect(BookVersionRecordFactory.memoryId(
            from: MemoryLinks.universalLink(memoryID: memoryID).absoluteString
        ) == memoryID.uuidString)
        #expect(BookVersionRecordFactory.memoryId(
            from: "memoirai://memory/\(BookInteriorAnchor.titlePageMemoryId.uuidString)"
        ) == BookInteriorAnchor.titlePageMemoryId.uuidString)
    }

    @Test func missingCloudBookendIdentifiersAreRecoveredAndDeduplicated() {
        let opening = StorybookBookendRecoveryPolicy.recoveredMemoryID(
            storedMemoryID: nil,
            pageType: "textPage",
            title: "Caleb’s Memoir",
            textContent: "Caleb’s personal memoir and life story, recorded and written."
        )
        let closing = StorybookBookendRecoveryPolicy.recoveredMemoryID(
            storedMemoryID: nil,
            pageType: "textPage",
            title: "About this book",
            textContent: "A life story."
        )

        #expect(opening == BookInteriorAnchor.titlePageMemoryId)
        #expect(closing == BookInteriorAnchor.closingPageMemoryId)
        #expect(StorybookBookendRecoveryPolicy.recoveredMemoryID(
            storedMemoryID: nil,
            pageType: "textPage",
            title: "Caleb’s Memoir",
            textContent: "A collection of life stories"
        ) == BookInteriorAnchor.titlePageMemoryId)
        #expect(StorybookBookendRecoveryPolicy.shouldInclude(
            memoryID: BookInteriorAnchor.titlePageMemoryId,
            seenBookendIDs: []
        ))
        #expect(!StorybookBookendRecoveryPolicy.shouldInclude(
            memoryID: BookInteriorAnchor.titlePageMemoryId,
            seenBookendIDs: [BookInteriorAnchor.titlePageMemoryId]
        ))
        #expect(StorybookBookendRecoveryPolicy.recoveredMemoryID(
            storedMemoryID: nil,
            pageType: "illustration",
            title: "About this book",
            textContent: nil
        ) == nil)
    }

    @Test func duplicateStorybookFinalizationTreatsTerminalJobsAsSuccess() {
        #expect(StorybookJobFinalizationPolicy.isCompletionSatisfied(status: "complete"))
        #expect(!StorybookJobFinalizationPolicy.isCompletionSatisfied(status: "aiComplete"))
        #expect(StorybookJobFinalizationPolicy.isFailureFinalizationSatisfied(status: "complete"))
        #expect(StorybookJobFinalizationPolicy.isFailureFinalizationSatisfied(status: "failed"))
        #expect(StorybookJobFinalizationPolicy.isFailureFinalizationSatisfied(status: "dismissedFailed"))
        #expect(!StorybookJobFinalizationPolicy.isFailureFinalizationSatisfied(status: "aiComplete"))
    }

    @Test func completedCloudJobLoadsCanonicalBookInsteadOfWaitingForever() {
        #expect(StorybookCloudJobResumeAction.action(for: "queued") == .waitForCloud)
        #expect(StorybookCloudJobResumeAction.action(for: "running") == .waitForCloud)
        #expect(StorybookCloudJobResumeAction.action(for: "aiComplete") == .finalizeCloudResults)
        #expect(StorybookCloudJobResumeAction.action(for: "complete") == .loadCompletedBook)
        #expect(StorybookCloudJobResumeAction.action(for: "failed") == .showFailure)
    }

    @Test func inProgressCloudSnapshotsDoNotRebuildCompletedPages() {
        #expect(StorybookCloudPageRebuildPolicy.shouldDeferPageRebuild(status: "queued"))
        #expect(StorybookCloudPageRebuildPolicy.shouldDeferPageRebuild(status: "ranking"))
        #expect(StorybookCloudPageRebuildPolicy.shouldDeferPageRebuild(status: "running"))
        #expect(!StorybookCloudPageRebuildPolicy.shouldDeferPageRebuild(status: "aiComplete"))
    }

    @Test func matchingCanonicalBookPreservesCompleteGeneratedPages() {
        let keys = [
            "textPage:11111111-1111-4111-8111-111111111111",
            "illustration:11111111-1111-4111-8111-111111111111"
        ]
        #expect(StorybookCanonicalInstallPolicy.canPreserveLocalPages(
            expectedBookVersionID: "book-a",
            canonicalBookVersionID: "book-a",
            localPageKeys: keys,
            canonicalPageKeys: keys,
            hasUnresolvedIllustrations: false,
            hasPlaceholderIllustrations: false
        ))
    }

    @Test func canonicalInstallHydratesColdMismatchedOrPartialBooks() {
        let keys = ["illustration:11111111-1111-4111-8111-111111111111"]
        #expect(!StorybookCanonicalInstallPolicy.canPreserveLocalPages(
            expectedBookVersionID: "book-a",
            canonicalBookVersionID: "book-a",
            localPageKeys: [],
            canonicalPageKeys: keys,
            hasUnresolvedIllustrations: false,
            hasPlaceholderIllustrations: false
        ))
        #expect(!StorybookCanonicalInstallPolicy.canPreserveLocalPages(
            expectedBookVersionID: "book-a",
            canonicalBookVersionID: "book-b",
            localPageKeys: keys,
            canonicalPageKeys: keys,
            hasUnresolvedIllustrations: false,
            hasPlaceholderIllustrations: false
        ))
        #expect(!StorybookCanonicalInstallPolicy.canPreserveLocalPages(
            expectedBookVersionID: "book-a",
            canonicalBookVersionID: "book-a",
            localPageKeys: keys,
            canonicalPageKeys: keys,
            hasUnresolvedIllustrations: true,
            hasPlaceholderIllustrations: false
        ))
        #expect(!StorybookCanonicalInstallPolicy.canPreserveLocalPages(
            expectedBookVersionID: "book-a",
            canonicalBookVersionID: "book-a",
            localPageKeys: keys,
            canonicalPageKeys: keys,
            hasUnresolvedIllustrations: false,
            hasPlaceholderIllustrations: true
        ))
    }

    @Test func globalProgressBannerAppearsOnlyOnRootScreens() {
        #expect(GlobalStorybookBannerVisibilityPolicy.shouldShow(
            hasActiveJob: true,
            isNavigationRoot: true,
            isStoryPageVisible: false,
            isDismissed: false
        ))
        #expect(!GlobalStorybookBannerVisibilityPolicy.shouldShow(
            hasActiveJob: true,
            isNavigationRoot: true,
            isStoryPageVisible: true,
            isDismissed: false
        ))
        #expect(!GlobalStorybookBannerVisibilityPolicy.shouldShow(
            hasActiveJob: true,
            isNavigationRoot: false,
            isStoryPageVisible: false,
            isDismissed: false
        ))
        #expect(!GlobalStorybookBannerVisibilityPolicy.shouldShow(
            hasActiveJob: true,
            isNavigationRoot: true,
            isStoryPageVisible: false,
            isDismissed: true
        ))
    }

    @Test func ethnicityDoesNotLeakFromAnotherProfile() {
        #expect(StorybookProfileSetupPolicy.initialEthnicity().isEmpty)
    }

    @Test func onlyFormatsWithMatchingCoverTemplatesCanBeOrdered() {
        #expect(PrintProductAvailabilityPolicy.unavailableReason(optionID: "kids_hardcover_casewrap") == nil)
        #expect(PrintProductAvailabilityPolicy.unavailableReason(optionID: "portrait_hardcover_casewrap") == nil)
        #expect(PrintProductAvailabilityPolicy.unavailableReason(optionID: "kids_coil_bound") != nil)
        #expect(PrintProductAvailabilityPolicy.unavailableReason(optionID: "kids_paperback_perfect") != nil)
    }

    @Test func generationBatchCapsOneBookWithoutChangingMonthlyAllowance() {
        #expect(StorybookGenerationBatchPolicy.maximumSelectablePages(remainingAllowance: 100) == 9)
        #expect(StorybookGenerationBatchPolicy.maximumSelectablePages(remainingAllowance: 4) == 4)
        #expect(StorybookGenerationBatchPolicy.maximumSelectablePages(remainingAllowance: 0) == 1)
        #expect(StorybookGenerationBatchPolicy.clampedTargetPageCount(100) == 9)
    }

    @Test func generationStyleIgnoresLegacyStoredSelections() {
        #expect(
            StorybookGenerationStylePolicy.supportedArtStyle(legacyStoredValue: ArtStyle.realistic.rawValue)
                == .kidsBook
        )
        #expect(
            StorybookGenerationStylePolicy.supportedArtStyle(legacyStoredValue: ArtStyle.comic.rawValue)
                == .kidsBook
        )
        #expect(
            StorybookGenerationStylePolicy.supportedArtStyle(legacyStoredValue: nil)
                == .kidsBook
        )
    }

    @Test func unavailableLayoutRecoveryIsTransactional() {
        let unavailable: Set<String> = ["page-1", "page-2"]
        #expect(BookPageRecoveryPolicy.pageIDsToRestore(
            selectedPageID: "page-1",
            unavailablePageIDs: unavailable
        ) == unavailable)
        #expect(BookPageRecoveryPolicy.pageIDsToRestore(
            selectedPageID: "page-3",
            unavailablePageIDs: unavailable
        ) == ["page-3"])
    }

    @Test func inlineTextEditsHaveABoundedMemorySize() {
        #expect(InlineBookTextEditPolicy.accepts(characterCount: 40_000))
        #expect(!InlineBookTextEditPolicy.accepts(characterCount: 40_001))
    }

    @Test func paginationChunksLongUnpunctuatedTextWithoutLosingContent() {
        let source = "abcdefghijklmnopqrstuvwxyz"
        let chunks = TextPaginationChunkPolicy.chunks(source) { $0.count <= 7 }

        #expect(chunks.allSatisfy { !$0.isEmpty && $0.count <= 7 })
        #expect(chunks.joined() == source)
    }

    @Test func kickoffBookIDsAreUniqueWithinTheSameMillisecond() {
        let profileID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_725_000_000.456)
        let first = StorybookVersionIDPolicy.make(profileID: profileID, createdAt: createdAt, nonce: UUID())
        let second = StorybookVersionIDPolicy.make(profileID: profileID, createdAt: createdAt, nonce: UUID())

        #expect(first != second)
        #expect(first.hasPrefix("\(profileID.uuidString)_1725000000456_"))
    }

    @Test func hydrationFindsIllustrationAfterInsertedBookend() {
        let target = UUID()
        let other = UUID()

        let index = StorybookIllustrationHydrationPolicy.destinationIndex(
            for: target,
            illustrationMemoryIDsByPage: [nil, nil, target, nil, other, nil]
        )

        #expect(index == 2)
    }

    @Test func hydrationRejectsMissingOrAmbiguousIllustrationIdentity() {
        let target = UUID()

        #expect(StorybookIllustrationHydrationPolicy.destinationIndex(
            for: target,
            illustrationMemoryIDsByPage: [nil, UUID(), nil]
        ) == nil)
        #expect(StorybookIllustrationHydrationPolicy.destinationIndex(
            for: target,
            illustrationMemoryIDsByPage: [target, nil, target]
        ) == nil)
    }

    @Test func interiorEditsReuseTheExistingCoverWithoutNewAIGeneration() {
        #expect(BookRevisionSavePolicy.reusesExistingCover(for: "freeformPageEdit"))
        #expect(BookRevisionSavePolicy.reusesExistingCover(for: "freeformPageReset"))
        #expect(BookRevisionSavePolicy.reusesExistingCover(for: "imageEdit"))
        #expect(!BookRevisionSavePolicy.reusesExistingCover(for: "printTitle"))
    }

    @Test func reusedCoverDownloadMustBeSecureSuccessfulAndBounded() throws {
        let secureURL = try #require(URL(string: "https://storage.example/cover.pdf"))
        let insecureURL = try #require(URL(string: "http://storage.example/cover.pdf"))
        #expect(BookCoverDownloadPolicy.accepts(url: secureURL, statusCode: 200, byteCount: 10))
        #expect(!BookCoverDownloadPolicy.accepts(url: insecureURL, statusCode: 200, byteCount: 10))
        #expect(!BookCoverDownloadPolicy.accepts(url: secureURL, statusCode: 404, byteCount: 10))
        #expect(!BookCoverDownloadPolicy.accepts(
            url: secureURL,
            statusCode: 200,
            byteCount: BookCoverDownloadPolicy.maximumByteCount + 1
        ))
    }

    @Test func encodedBookPayloadIsBounded() {
        #expect(StorybookPayloadCapacityPolicy.accepts(encodedByteCount: 1))
        #expect(StorybookPayloadCapacityPolicy.accepts(
            encodedByteCount: StorybookPayloadCapacityPolicy.maximumEncodedBookByteCount
        ))
        #expect(!StorybookPayloadCapacityPolicy.accepts(encodedByteCount: 0))
        #expect(!StorybookPayloadCapacityPolicy.accepts(
            encodedByteCount: StorybookPayloadCapacityPolicy.maximumEncodedBookByteCount + 1
        ))
    }

    @Test func localBookFilesUseTheEncodedPayloadLimitBeforeReading() {
        #expect(StorybookLocalFilePolicy.accepts(byteCount: 1))
        #expect(StorybookLocalFilePolicy.accepts(
            byteCount: StorybookPayloadCapacityPolicy.maximumEncodedBookByteCount
        ))
        #expect(!StorybookLocalFilePolicy.accepts(byteCount: 0))
        #expect(!StorybookLocalFilePolicy.accepts(
            byteCount: StorybookPayloadCapacityPolicy.maximumEncodedBookByteCount + 1
        ))
    }

    @Test func oversizedBooksBypassUbiquitousPayloadStorage() {
        #expect(StorybookUbiquitousPayloadPolicy.storesCurrentBook(encodedByteCount: 1))
        #expect(StorybookUbiquitousPayloadPolicy.storesCurrentBook(
            encodedByteCount: StorybookUbiquitousPayloadPolicy.maximumCurrentBookByteCount
        ))
        #expect(!StorybookUbiquitousPayloadPolicy.storesCurrentBook(encodedByteCount: 0))
        #expect(!StorybookUbiquitousPayloadPolicy.storesCurrentBook(
            encodedByteCount: StorybookUbiquitousPayloadPolicy.maximumCurrentBookByteCount + 1
        ))
    }

    @Test func pendingRetryMatchesCanonicalNonceBookIDExactly() {
        let profileID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_725_000_000.456)
        let canonicalID = StorybookVersionIDPolicy.make(
            profileID: profileID,
            createdAt: createdAt,
            nonce: UUID()
        )
        let book = PersistableStorybook(
            ownerUserID: nil,
            bookVersionID: canonicalID,
            profileID: profileID,
            pageItems: [],
            artStyle: "kidsBook",
            createdAt: createdAt
        )

        #expect(PendingStorybookMatchPolicy.matches(
            book,
            pendingBookID: canonicalID,
            profileID: profileID
        ))
        #expect(!PendingStorybookMatchPolicy.matches(
            book,
            pendingBookID: "\(profileID.uuidString)_1725000000456_legacy",
            profileID: profileID
        ))
    }

    @Test func pendingRetrySupportsLegacySecondAndMillisecondIDs() {
        let profileID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_725_000_000)
        let legacyBook = PersistableStorybook(
            ownerUserID: nil,
            bookVersionID: nil,
            profileID: profileID,
            pageItems: [],
            artStyle: "kidsBook",
            createdAt: createdAt
        )

        #expect(PendingStorybookMatchPolicy.matches(
            legacyBook,
            pendingBookID: "\(profileID.uuidString)_1725000000_legacy",
            profileID: profileID
        ))
        #expect(PendingStorybookMatchPolicy.matches(
            legacyBook,
            pendingBookID: "\(profileID.uuidString)_1725000000000_legacy",
            profileID: profileID
        ))
    }

    @Test func printAvailabilityExplainsBooksBelowTheMinimumWithoutSelectingAnInvalidFormat() {
        let ranges = [24...800]

        #expect(PrintProductAvailabilityPolicy.bookStatus(
            pageCount: 5,
            supportedPageRanges: ranges
        ) == .needsPages(current: 5, minimum: 24, remaining: 19))
        #expect(PrintProductAvailabilityPolicy.bookStatus(
            pageCount: 24,
            supportedPageRanges: ranges
        ) == .ready)
        #expect(PrintProductAvailabilityPolicy.bookStatus(
            pageCount: 801,
            supportedPageRanges: ranges
        ) == .unavailable)
        #expect(PrintProductAvailabilityPolicy.bookStatus(
            pageCount: 5,
            supportedPageRanges: []
        ) == .unavailable)
    }
}
