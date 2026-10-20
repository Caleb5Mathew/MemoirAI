import Foundation

enum StorybookPagePresentationPolicy {
    static func shouldShowLoadedBook(hasGeneratedStorybook: Bool, pageCount: Int) -> Bool {
        hasGeneratedStorybook && pageCount > 0
    }

    static func shouldShowProfileLoadingOverlay(
        isLoadingProfileBook: Bool,
        hasLoadedBook: Bool,
        hasCanonicalBookMetadata: Bool
    ) -> Bool {
        isLoadingProfileBook && hasLoadedBook && !hasCanonicalBookMetadata
    }

    static func clampedPageIndex(_ index: Int, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        return min(max(index, 0), pageCount - 1)
    }

    static func loadingCopy(isLibrarySelection: Bool) -> (title: String, subtitle: String) {
        if isLibrarySelection {
            return ("Opening your book…", "Loading pages and illustrations.")
        }
        return ("", "")
    }
}

enum StorybookReaderSlot: Equatable {
    case cover(BookCoverFlatPanel)
    case interiorPage(Int)
}

enum StorybookReaderSlotPolicy {
    static func slots(interiorPageCount: Int, hasExteriorCover: Bool) -> [StorybookReaderSlot] {
        let pages = (0..<max(interiorPageCount, 0)).map(StorybookReaderSlot.interiorPage)
        guard hasExteriorCover else { return pages }
        return [.cover(.front)] + pages + [.cover(.back)]
    }
}

enum StorybookEditablePageTarget: Equatable {
    case exteriorCover(BookCoverFlatPanel)
    case interiorPage(Int)
}

enum StorybookPageEditDestinationPolicy {
    static func target(for slot: StorybookReaderSlot) -> StorybookEditablePageTarget {
        switch slot {
        case .cover(let panel):
            return .exteriorCover(panel)
        case .interiorPage(let index):
            return .interiorPage(index)
        }
    }
}

enum BookCatalogTitlePolicy {
    static func displayTitle(
        printTitle: String?,
        bookDisplayName: String?,
        firstPageTitle: String?
    ) -> String {
        for candidate in [printTitle, bookDisplayName, firstPageTitle] {
            if let title = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
                return title
            }
        }
        return "Story"
    }
}

enum StorybookInteriorAnchorPolicy {
    static func matches(memoryID: String?, anchor: UUID) -> Bool {
        guard let memoryID = memoryID?.trimmingCharacters(in: .whitespacesAndNewlines),
              let parsedID = UUID(uuidString: memoryID) else {
            return false
        }
        return parsedID == anchor
    }
}

enum StorybookBookendRecoveryPolicy {
    static func recoveredMemoryID(
        storedMemoryID: String?,
        pageType: String,
        title: String?,
        textContent: String?
    ) -> UUID? {
        if let storedMemoryID,
           let explicitID = UUID(uuidString: storedMemoryID.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return explicitID
        }
        guard pageType == "textPage" else { return nil }

        let normalizedTitle = title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if normalizedTitle == "about this book" {
            return BookInteriorAnchor.closingPageMemoryId
        }
        if normalizedTitle == "made with memoir" {
            return BookInteriorAnchor.closingPageMemoryId
        }

        let normalizedBody = textContent?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if normalizedBody == "a collection of life stories",
           normalizedTitle == "memoir" || normalizedTitle.hasSuffix(" memoir") {
            return BookInteriorAnchor.titlePageMemoryId
        }
        if normalizedBody.contains("personal memoir and life story")
            && normalizedBody.contains("recorded and written") {
            return BookInteriorAnchor.titlePageMemoryId
        }
        if normalizedBody.hasPrefix("a collection of memories from")
            && normalizedBody.hasSuffix("’s life.") {
            return BookInteriorAnchor.titlePageMemoryId
        }
        return nil
    }

    static func shouldInclude(memoryID: UUID, seenBookendIDs: Set<UUID>) -> Bool {
        guard BookInteriorAnchor.isNonMemoryPage(memoryID) else {
            return true
        }
        return !seenBookendIDs.contains(memoryID)
    }
}

enum StorybookJobFinalizationPolicy {
    static func isCompletionSatisfied(status: String?) -> Bool {
        status == "complete"
    }

    static func isFailureFinalizationSatisfied(status: String?) -> Bool {
        guard let status else { return false }
        return ["complete", "failed", "dismissedFailed"].contains(status)
    }
}

enum StorybookCloudJobResumeAction: Equatable {
    case waitForCloud
    case finalizeCloudResults
    case loadCompletedBook
    case showFailure

    static func action(for status: String) -> StorybookCloudJobResumeAction {
        switch status {
        case "aiComplete":
            return .finalizeCloudResults
        case "complete":
            return .loadCompletedBook
        case "failed", "dismissedFailed":
            return .showFailure
        default:
            return .waitForCloud
        }
    }
}

enum StorybookCloudPageRebuildPolicy {
    /// In-progress snapshots exist to update progress. Rebuilding pages before the
    /// worker reaches `aiComplete` repeatedly downloads the same illustrations.
    static func shouldDeferPageRebuild(status: String) -> Bool {
        ["queued", "ranking", "running"].contains(status)
    }
}

enum StorybookCanonicalInstallPolicy {
    /// A freshly generated book already has full-resolution local pages. Once the
    /// matching canonical record is print-ready, only its metadata needs installing.
    /// Cold resumes and mismatched/partial page sets must use normal cloud hydration.
    static func canPreserveLocalPages(
        expectedBookVersionID: String?,
        canonicalBookVersionID: String,
        localPageKeys: [String],
        canonicalPageKeys: [String],
        hasUnresolvedIllustrations: Bool,
        hasPlaceholderIllustrations: Bool
    ) -> Bool {
        guard expectedBookVersionID == canonicalBookVersionID,
              !localPageKeys.isEmpty,
              localPageKeys == canonicalPageKeys,
              !hasUnresolvedIllustrations,
              !hasPlaceholderIllustrations else {
            return false
        }
        return true
    }
}

enum GlobalStorybookBannerVisibilityPolicy {
    static func shouldShow(
        hasActiveJob: Bool,
        isNavigationRoot: Bool,
        isStoryPageVisible: Bool,
        isDismissed: Bool
    ) -> Bool {
        hasActiveJob && isNavigationRoot && !isStoryPageVisible && !isDismissed
    }
}

enum StorybookProfileSetupPolicy {
    static func initialEthnicity() -> String {
        ""
    }
}

enum StorybookGenerationBatchPolicy {
    static let maximumPagesPerBook = 9

    static func maximumSelectablePages(remainingAllowance: Int) -> Int {
        max(1, min(maximumPagesPerBook, remainingAllowance))
    }

    static func clampedTargetPageCount(_ requested: Int) -> Int {
        max(1, min(maximumPagesPerBook, requested))
    }
}

enum BookPrintPaddingPolicy {
    static let hardcoverMinimumPageCount = 24
    static let minimumContentPageCountForPadding = 21

    static func paddingCount(for currentPageCount: Int) -> Int {
        guard currentPageCount >= minimumContentPageCountForPadding else { return 0 }
        if currentPageCount < hardcoverMinimumPageCount {
            return hardcoverMinimumPageCount - currentPageCount
        }
        return currentPageCount.isMultiple(of: 2) ? 0 : 1
    }
}

enum StorybookGenerationStylePolicy {
    static func supportedArtStyle(legacyStoredValue: String?) -> ArtStyle {
        .kidsBook
    }
}

enum TextPaginationChunkPolicy {
    static func chunks(
        _ text: String,
        fits: (String) -> Bool
    ) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let characters = Array(trimmed)
        guard !characters.isEmpty else { return [] }

        var result: [String] = []
        var start = 0
        while start < characters.count {
            var low = 1
            var high = characters.count - start
            var best = 0
            while low <= high {
                let middle = (low + high) / 2
                let candidate = String(characters[start..<(start + middle)])
                if fits(candidate) {
                    best = middle
                    low = middle + 1
                } else {
                    high = middle - 1
                }
            }

            var end = start + max(1, best)
            if end < characters.count {
                let candidateRange = start..<end
                if let boundary = characters[candidateRange].lastIndex(where: { $0.isWhitespace }),
                   boundary > start {
                    end = boundary
                }
            }
            let chunk = String(characters[start..<end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty { result.append(chunk) }
            start = end
            while start < characters.count, characters[start].isWhitespace {
                start += 1
            }
        }
        return result
    }
}

enum InlineBookTextEditPolicy {
    static let maximumMemoryCharacterCount = 40_000

    static func accepts(characterCount: Int) -> Bool {
        characterCount <= maximumMemoryCharacterCount
    }
}

enum BookPageRecoveryPolicy {
    static func pageIDsToRestore(
        selectedPageID: String,
        unavailablePageIDs: Set<String>
    ) -> Set<String> {
        unavailablePageIDs.contains(selectedPageID)
            ? unavailablePageIDs
            : [selectedPageID]
    }
}

enum StorybookIllustrationHydrationPolicy {
    /// A cloud illustration may finish after local compatibility pages are inserted.
    /// Resolve its destination by stable memory identity instead of its old array offset.
    static func destinationIndex(
        for memoryID: UUID,
        illustrationMemoryIDsByPage: [UUID?]
    ) -> Int? {
        let matches = illustrationMemoryIDsByPage.indices.filter {
            illustrationMemoryIDsByPage[$0] == memoryID
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }
}

enum BookRevisionSavePolicy {
    static func reusesExistingCover(for reason: String) -> Bool {
        [
            "interiorDesignUpdate",
            "freeformPageEdit",
            "freeformPageReset",
            "imageEdit",
            "textPageEdit",
            "illustrationTitleEdit",
            "repairPartialCloud",
            "repairShorterCloudRebuild"
        ].contains(reason)
    }
}

enum BookCoverDownloadPolicy {
    static let maximumByteCount = 100 * 1024 * 1024

    static func accepts(url: URL, statusCode: Int, byteCount: Int) -> Bool {
        url.scheme?.lowercased() == "https"
            && (200...299).contains(statusCode)
            && byteCount > 0
            && byteCount <= maximumByteCount
    }
}

enum StorybookPayloadCapacityPolicy {
    static let maximumEncodedBookByteCount = 64 * 1024 * 1024

    static func accepts(encodedByteCount: Int) -> Bool {
        encodedByteCount > 0 && encodedByteCount <= maximumEncodedBookByteCount
    }
}

enum StorybookCoverRevealPolicy {
    enum PreparationResult {
        case pending
        case ready
        case failed
    }

    static func shouldReveal(
        canonicalArtifactsReady: Bool,
        coverPreparation: PreparationResult
    ) -> Bool {
        guard canonicalArtifactsReady else { return false }
        switch coverPreparation {
        case .pending:
            return false
        case .ready, .failed:
            return true
        }
    }
}

enum StorybookUbiquitousPayloadPolicy {
    // NSUbiquitousKeyValueStore has a 1 MB aggregate quota. Leave room for the
    // book metadata and unrelated settings stored in the same container.
    static let maximumCurrentBookByteCount = 950 * 1024

    static func storesCurrentBook(encodedByteCount: Int) -> Bool {
        encodedByteCount > 0 && encodedByteCount <= maximumCurrentBookByteCount
    }
}

/// Cloud question-driven results can keep the interview prompt in displayTitle.
enum StorybookGeneratedMemoryTitlePolicy {
    static func title(illustrationTitle: String?, extractedTitle: String?, displayTitle: String?, prompt: String?) -> String {
        for candidate in [illustrationTitle, extractedTitle, displayTitle, prompt] {
            if let title = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                return title
            }
        }
        return "Memory"
    }
}
