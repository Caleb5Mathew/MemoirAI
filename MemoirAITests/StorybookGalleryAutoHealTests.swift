//
//  StorybookGalleryAutoHealTests.swift
//  MemoirAITests
//

import Foundation
import Testing
@testable import MemoirAI

struct StorybookGalleryAutoHealTests {
    @Test func healingFilter_targetsOnlyStuckRenderedWithoutCover() {
        let t = Date(timeIntervalSince1970: 1_750_000_000)
        let good = makeGalleryRecord(
            id: "good_1",
            coverURL: "https://c.example/a.pdf",
            renderStatus: BookRenderStatus.rendered.rawValue,
            at: t
        )
        let stillPending = makeGalleryRecord(
            id: "pend_1",
            coverURL: nil,
            renderStatus: "pending",
            at: t
        )
        let stuck = makeGalleryRecord(
            id: "stuck_1",
            coverURL: "  ",
            renderStatus: BookRenderStatus.rendered.rawValue,
            at: t
        )
        let ids = StorybookCloudApplyPolicy.bookVersionIdsNeedingCoverBackfillHealing(
            [good, stillPending, stuck]
        )
        #expect(ids == ["stuck_1"])
    }
}

// MARK: - Test helpers
private func makeGalleryRecord(
    id: String,
    coverURL: String?,
    renderStatus: String,
    at: Date
) -> BookVersionRecord {
    BookVersionRecord(
        bookVersionId: id,
        profileId: "p",
        createdAt: at,
        memoryOrder: ["m0"],
        pageCount: 1,
        artStyle: "kids",
        orientation: "landscape",
        pageWidth: 792,
        pageHeight: 612,
        trimSizeInches: "11x8.5",
        layoutVersion: 1,
        printTitle: "T",
        backCoverPitch: "P",
        coverFontPreset: nil,
        pdfStoragePath: nil,
        pdfURL: nil,
        pdfPageCount: nil,
        coverStoragePath: nil,
        coverURL: coverURL,
        coverArtRevision: nil,
        syncedAt: nil,
        renderStatus: renderStatus,
        renderedAt: nil,
        renderError: nil,
        renderAttemptCount: 0,
        renderDurationMs: 0,
        totalPngBytes: nil,
        pdfBytes: nil,
        source: "story_generation",
        pages: [],
        bookDisplayName: nil,
        userHandle: nil,
        bookSeq: nil
    )
}
