import Foundation
import Testing
@testable import MemoirAI

struct StorybookPageFlowPolicyTests {
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

    @Test func generationBatchCapsOneBookWithoutChangingMonthlyAllowance() {
        #expect(StorybookGenerationBatchPolicy.maximumSelectablePages(remainingAllowance: 100) == 9)
        #expect(StorybookGenerationBatchPolicy.maximumSelectablePages(remainingAllowance: 4) == 4)
        #expect(StorybookGenerationBatchPolicy.maximumSelectablePages(remainingAllowance: 0) == 1)
        #expect(StorybookGenerationBatchPolicy.clampedTargetPageCount(100) == 9)
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
}
