import Foundation

enum StorybookPagePresentationPolicy {
    static func shouldShowLoadedBook(hasGeneratedStorybook: Bool, pageCount: Int) -> Bool {
        hasGeneratedStorybook && pageCount > 0
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

enum StorybookUbiquitousPayloadPolicy {
    // NSUbiquitousKeyValueStore has a 1 MB aggregate quota. Leave room for the
    // book metadata and unrelated settings stored in the same container.
    static let maximumCurrentBookByteCount = 950 * 1024

    static func storesCurrentBook(encodedByteCount: Int) -> Bool {
        encodedByteCount > 0 && encodedByteCount <= maximumCurrentBookByteCount
    }
}
