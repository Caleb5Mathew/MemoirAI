//
//  StorybookInPlaceEditTests.swift
//  MemoirAITests
//

import Foundation
import Testing
@testable import MemoirAI

struct StorybookInPlaceEditTests {
    @Test func completeRecord_notIncomplete() {
        let r = makeBookRecordForTests(pageCount: 2, pages: mockPages(count: 2))
        #expect(StorybookCloudApplyPolicy.isIncompleteCloudRecord(r) == false)
    }

    @Test func jaccard_fullOverlap() {
        let a = (0..<10).map { "m\($0)" }
        #expect(jaccard(a, a) == 1.0)
    }
}

private func jaccard(_ a: [String], _ b: [String]) -> Double {
    if a.isEmpty, b.isEmpty { return 1.0 }
    if a.isEmpty || b.isEmpty { return 0 }
    let sa = Set(a), sb = Set(b)
    let inter = sa.intersection(sb).count
    let u = sa.union(sb).count
    return u == 0 ? 0 : Double(inter) / Double(u)
}

// MARK: - Test helpers
private func makeBookRecordForTests(
    pageCount: Int,
    pages: [BookVersionPageRecord]
) -> BookVersionRecord {
    BookVersionRecord(
        bookVersionId: "profile-uuid_1700000000",
        profileId: "profile-uuid",
        createdAt: Date(),
        memoryOrder: (0..<pageCount).map { "mem-\($0)" },
        pageCount: pageCount,
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
        coverURL: nil,
        coverArtRevision: nil,
        syncedAt: nil,
        renderStatus: BookRenderStatus.rendered.rawValue,
        renderedAt: nil,
        renderError: nil,
        renderAttemptCount: 0,
        renderDurationMs: 0,
        totalPngBytes: nil,
        pdfBytes: nil,
        source: "story_generation",
        pages: pages,
        bookDisplayName: nil,
        userHandle: nil,
        bookSeq: nil
    )
}

private func mockPages(count: Int) -> [BookVersionPageRecord] {
    (0..<count).map { i in
        BookVersionPageRecord(
            pageIndex: i,
            type: "illustration",
            memoryId: "mem-\(i)",
            memoryCreatedAt: nil,
            title: "t",
            subtitle: nil,
            textContent: nil,
            imageStoragePath: nil,
            imageURL: nil,
            renderedPageStoragePath: nil,
            renderedPageURL: nil,
            renderedPageFormat: nil,
            renderedPixelWidth: nil,
            renderedPixelHeight: nil,
            renderedChecksum: nil,
            renderedBytes: nil,
            createdAt: Date()
        )
    }
}
