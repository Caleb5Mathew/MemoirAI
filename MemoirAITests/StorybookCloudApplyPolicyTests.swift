//
//  StorybookCloudApplyPolicyTests.swift
//  MemoirAITests
//

import Foundation
import Testing
@testable import MemoirAI

struct StorybookCloudApplyPolicyTests {

    @Test func whenGenerating_skipsApply() {
        let cloud = Date(timeIntervalSince1970: 1_700_000_000)
        let local = cloud.addingTimeInterval(3600)
        let o = StorybookCloudApplyPolicy.outcome(
            isLoading: true,
            localPersistedBookCreatedAt: local,
            cloudRecordCreatedAt: cloud
        )
        #expect(o == .skipBecauseGenerating)
    }

    @Test func whenNoLocalBook_appliesCloud() {
        let cloud = Date(timeIntervalSince1970: 1_700_000_000)
        let o = StorybookCloudApplyPolicy.outcome(
            isLoading: false,
            localPersistedBookCreatedAt: nil,
            cloudRecordCreatedAt: cloud
        )
        #expect(o == .shouldApply)
    }

    @Test func whenLocalIsOneSecondAhead_appliesCloud() {
        let cloud = Date(timeIntervalSince1970: 1_700_000_000)
        let local = cloud.addingTimeInterval(1.0)
        let o = StorybookCloudApplyPolicy.outcome(
            isLoading: false,
            localPersistedBookCreatedAt: local,
            cloudRecordCreatedAt: cloud,
            epsilonSeconds: StorybookCloudApplyPolicy.localNewerThanCloudEpsilonSeconds
        )
        #expect(o == .shouldApply)
    }

    @Test func whenLocalIsJustOverEpsilonAhead_skipsApply() {
        let cloud = Date(timeIntervalSince1970: 1_700_000_000)
        let local = cloud.addingTimeInterval(1.01)
        let o = StorybookCloudApplyPolicy.outcome(
            isLoading: false,
            localPersistedBookCreatedAt: local,
            cloudRecordCreatedAt: cloud,
            epsilonSeconds: 1.0
        )
        guard case .skipBecauseLocalPersistedBookIsNewer(_, _, let delta) = o else {
            Issue.record("expected skipBecauseLocalPersistedBookIsNewer, got \(o)")
            return
        }
        #expect(delta > 1.0)
    }

    @Test func whenCloudIsNewer_appliesCloud() {
        let local = Date(timeIntervalSince1970: 1_700_000_000)
        let cloud = local.addingTimeInterval(10)
        let o = StorybookCloudApplyPolicy.outcome(
            isLoading: false,
            localPersistedBookCreatedAt: local,
            cloudRecordCreatedAt: cloud
        )
        #expect(o == .shouldApply)
    }

    @Test func incompleteCloudRecord_isDetected() {
        let r = makeRecord(pageCount: 5, pages: [])
        #expect(StorybookCloudApplyPolicy.isIncompleteCloudRecord(r) == true)
    }

    @Test func coverStuckFinalizingState_detected() {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let r = makeRecord(
            pageCount: 1,
            pages: [],
            createdAt: t,
            coverURL: nil,
            renderStatus: BookRenderStatus.rendered.rawValue
        )
        #expect(StorybookCloudApplyPolicy.isCoverStuckFinalizingState(r) == true)
    }

    @Test func coverPresentOrNotInStuckHole_whenCoverExists() {
        let r = makeRecord(
            pageCount: 1,
            pages: [],
            coverURL: "https://x/c.pdf",
            renderStatus: BookRenderStatus.rendered.rawValue
        )
        #expect(StorybookCloudApplyPolicy.isCoverPresentOrNotInStuckRenderedHole(r) == true)
    }

    @Test func whenRecordIncomplete_skipsByPolicy() {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let r = makeRecord(
            pageCount: 3,
            pages: [],
            createdAt: t
        )
        let o = StorybookCloudApplyPolicy.outcome(
            isLoading: false,
            localPersistedBookCreatedAt: t,
            record: r
        )
        if case .skipBecauseCloudIsPartial(0, 3) = o {
        } else {
            Issue.record("expected skipBecauseCloudIsPartial(0,3) got \(o)")
        }
    }
}

// MARK: - Test helpers
private func makeRecord(
    pageCount: Int,
    pages: [BookVersionPageRecord],
    createdAt: Date = Date(),
    coverURL: String? = nil,
    renderStatus: String = "pending"
) -> BookVersionRecord {
    BookVersionRecord(
        bookVersionId: "p1_1700000000",
        profileId: "p1-uuid",
        createdAt: createdAt,
        memoryOrder: (0..<pageCount).map { "m\($0)" },
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
        pages: pages,
        bookDisplayName: nil,
        userHandle: nil,
        bookSeq: nil
    )
}
