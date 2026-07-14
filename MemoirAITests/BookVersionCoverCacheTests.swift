//
//  BookVersionCoverCacheTests.swift
//  MemoirAITests
//

import Foundation
import Testing
@testable import MemoirAI

struct BookVersionCoverCacheTests {
    @Test func coverThumbnailCacheRevision_prefersCoverArtRevisionOverSyncedAt() {
        let synced = Date(timeIntervalSince1970: 1_700_000_000)
        let r = makeRecord(coverArtRevision: 3, syncedAt: synced, coverStoragePath: "users/x/book/y/cover.pdf")
        #expect(r.coverThumbnailCacheRevision == "art:3")
    }

    @Test func coverThumbnailCacheRevision_fallsBackToPathWhenNoArtRevision() {
        let r = makeRecord(coverArtRevision: nil, syncedAt: nil, coverStoragePath: "users/x/cover.pdf")
        #expect(r.coverThumbnailCacheRevision == "path:users/x/cover.pdf")
    }

    @Test func cacheKey_sameCacheIdentityDifferentSignedURL_maintainsStableKey() {
        let u1 = URL(string: "https://a.example/first?token=1")!
        let u2 = URL(string: "https://a.example/second?token=2")!
        let k1 = CoverPDFThumbnailService.cacheKey(
            url: u1,
            layout: .kidsBook(pageCount: 24),
            panel: .front,
            cacheRevision: "art:1",
            cacheIdentity: "users/u/b/cover.pdf"
        )
        let k2 = CoverPDFThumbnailService.cacheKey(
            url: u2,
            layout: .kidsBook(pageCount: 24),
            panel: .front,
            cacheRevision: "art:1",
            cacheIdentity: "users/u/b/cover.pdf"
        )
        #expect(k1 == k2)
    }
}

private func makeRecord(coverArtRevision: Int?, syncedAt: Date?, coverStoragePath: String?) -> BookVersionRecord {
    BookVersionRecord(
        bookVersionId: "bid",
        profileId: "pid",
        createdAt: Date(),
        memoryOrder: [],
        pageCount: 0,
        artStyle: "kids",
        orientation: "landscape",
        pageWidth: 792,
        pageHeight: 612,
        trimSizeInches: "11x8.5",
        layoutVersion: 1,
        printTitle: nil,
        backCoverPitch: nil,
        coverFontPreset: nil,
        pdfStoragePath: nil,
        pdfURL: nil,
        pdfPageCount: nil,
        coverStoragePath: coverStoragePath,
        coverURL: "https://x/cover.pdf",
        coverArtRevision: coverArtRevision,
        syncedAt: syncedAt,
        renderStatus: BookRenderStatus.rendered.rawValue,
        renderedAt: nil,
        renderError: nil,
        renderAttemptCount: nil,
        renderDurationMs: nil,
        totalPngBytes: nil,
        pdfBytes: nil,
        source: BookVersionSource.storyGeneration.rawValue,
        pages: [],
        bookDisplayName: nil,
        userHandle: nil,
        bookSeq: nil
    )
}
