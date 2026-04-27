import Foundation

/// Whether `loadLatestBookVersionFromCloud` should call `applyBookVersionRecord` or fall back to disk.
enum StorybookCloudApplyPolicy {
    /// Cloud `createdAt` can lag clocks slightly; treat local as newer only if more than this ahead.
    static let localNewerThanCloudEpsilonSeconds: TimeInterval = 1.0

    enum Outcome: Equatable {
        case shouldApply
        case skipBecauseGenerating
        case skipBecauseLocalPersistedBookIsNewer(localCreated: Date, cloudCreated: Date, deltaSeconds: TimeInterval)
        /// `pages` array in Firestore is not yet complete vs `pageCount` (e.g. interrupted `syncBook`).
        case skipBecauseCloudIsPartial(pagesInArray: Int, pageCount: Int)
    }

    /// True when the book version document was left mid-upload: fewer page rows than declared `pageCount`.
    static func isIncompleteCloudRecord(_ record: BookVersionRecord) -> Bool {
        record.pageCount > 0 && record.pages.count < record.pageCount
    }

    /// My Library / cloud doc can show **rendered** while `coverURL` is still empty (interrupted backfill, CF race, etc.). Gallery and heal paths treat this as "cover work still in flight" / stuck.
    static func isCoverStuckFinalizingState(_ record: BookVersionRecord) -> Bool {
        record.renderStatus == BookRenderStatus.rendered.rawValue
            && (record.coverURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// The opposite: cover is present, or the book is not in the "rendered but no cover" stuck hole (e.g. still pending, or already has a `coverURL`).
    static func isCoverPresentOrNotInStuckRenderedHole(_ record: BookVersionRecord) -> Bool {
        !isCoverStuckFinalizingState(record)
    }

    /// Same filter as the gallery "auto-heal" `ensureCoverDesignExistsIfMissing` loop: books stuck as rendered with no cover URL.
    static func bookVersionIdsNeedingCoverBackfillHealing(_ records: [BookVersionRecord]) -> [String] {
        records.filter { isCoverStuckFinalizingState($0) }.map(\.bookVersionId)
    }

    static func outcome(
        isLoading: Bool,
        localPersistedBookCreatedAt: Date?,
        cloudRecordCreatedAt: Date,
        epsilonSeconds: TimeInterval = localNewerThanCloudEpsilonSeconds
    ) -> Outcome {
        if isLoading { return .skipBecauseGenerating }
        guard let localCreated = localPersistedBookCreatedAt else { return .shouldApply }
        let delta = localCreated.timeIntervalSince(cloudRecordCreatedAt)
        if delta > epsilonSeconds {
            return .skipBecauseLocalPersistedBookIsNewer(
                localCreated: localCreated,
                cloudCreated: cloudRecordCreatedAt,
                deltaSeconds: delta
            )
        }
        return .shouldApply
    }

    /// `loadLatestBookVersion` path: skip applying a record that would replace local state with a truncated page list.
    static func outcome(
        isLoading: Bool,
        localPersistedBookCreatedAt: Date?,
        record: BookVersionRecord,
        epsilonSeconds: TimeInterval = localNewerThanCloudEpsilonSeconds
    ) -> Outcome {
        if isIncompleteCloudRecord(record) {
            return .skipBecauseCloudIsPartial(
                pagesInArray: record.pages.count,
                pageCount: record.pageCount
            )
        }
        return outcome(
            isLoading: isLoading,
            localPersistedBookCreatedAt: localPersistedBookCreatedAt,
            cloudRecordCreatedAt: record.createdAt,
            epsilonSeconds: epsilonSeconds
        )
    }
}
