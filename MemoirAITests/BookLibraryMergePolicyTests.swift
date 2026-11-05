import Foundation
import Testing
@testable import MemoirAI

struct BookLibraryMergePolicyTests {
    private func book(profile: UUID, id: String?, owner: String? = "owner", time: Double) -> PersistableStorybook {
        PersistableStorybook(ownerUserID: owner, bookVersionID: id, profileID: profile,
                             pageItems: [], artStyle: "Kids", createdAt: Date(timeIntervalSince1970: time))
    }

    @Test func pendingLocalBookRemainsVisibleBesideCloudBooks() {
        let profile = UUID()
        let synced = book(profile: profile, id: "synced", time: 10)
        let pending = book(profile: profile, id: "pending", time: 20)
        let cloud = BookVersionRecordFactory.fromPersistable(synced, bookVersionId: "synced")
        let result = BookLibraryMergePolicy.merged(cloud: [cloud], local: [pending, synced],
                                                  profileID: profile, userID: "owner", trustedLegacyOwner: false)
        #expect(result.map { $0.record.bookVersionId } == ["pending", "synced"])
        #expect(result.last?.local?.bookVersionID == "synced")
    }

    @Test func currentPendingAndHistoryCopiesAppearOnlyOnce() {
        let profile = UUID()
        let local = book(profile: profile, id: "same", time: 10)
        let result = BookLibraryMergePolicy.merged(cloud: [], local: [local, local, local],
                                                  profileID: profile, userID: "owner", trustedLegacyOwner: false)
        #expect(result.count == 1)
        let cloud = BookVersionRecordFactory.fromPersistable(local, bookVersionId: "same")
        let synced = BookLibraryMergePolicy.merged(cloud: [cloud], local: [local, local],
                                                  profileID: profile, userID: "owner", trustedLegacyOwner: false)
        #expect(synced.count == 1)
        #expect(synced.first?.record.source == cloud.source)
    }

    @Test func booksFromAnotherAccountOrProfileNeverAppear() {
        let profile = UUID(), other = UUID()
        let wrongProfile = book(profile: other, id: "other-profile", time: 20)
        let wrongOwner = book(profile: profile, id: "other-owner", owner: "someone-else", time: 30)
        let ownerless = book(profile: profile, id: "untrusted", owner: nil, time: 40)
        let wrongCloud = BookVersionRecordFactory.fromPersistable(wrongProfile, bookVersionId: "other-profile")
        let result = BookLibraryMergePolicy.merged(cloud: [wrongCloud], local: [wrongProfile, wrongOwner, ownerless],
                                                  profileID: profile, userID: "owner", trustedLegacyOwner: false)
        #expect(result.isEmpty)
    }

    @Test func trustedLegacyCopyMatchesExactCreationDateWithoutSecondRounding() {
        let profile = UUID()
        let legacy = book(profile: profile, id: nil, owner: nil, time: 10.123)
        let sameSecond = book(profile: profile, id: "different", time: 10.900)
        let canonical = BookVersionRecordFactory.fromPersistable(legacy, bookVersionId: "canonical")
        let other = BookVersionRecordFactory.fromPersistable(sameSecond, bookVersionId: "different")
        let result = BookLibraryMergePolicy.merged(cloud: [canonical, other], local: [legacy],
                                                  profileID: profile, userID: "owner", trustedLegacyOwner: true)
        #expect(result.count == 2)
        #expect(result.first { $0.record.bookVersionId == "canonical" }?.local != nil)
        #expect(result.first { $0.record.bookVersionId == "different" }?.local == nil)
    }

    @Test func explicitNewRevisionIDIsNotMergedWithSameTimestampCloudBook() {
        let profile = UUID()
        let old = book(profile: profile, id: "old", time: 10)
        let revision = book(profile: profile, id: "new", time: 10)
        let cloud = BookVersionRecordFactory.fromPersistable(old, bookVersionId: "old")
        let result = BookLibraryMergePolicy.merged(cloud: [cloud], local: [revision],
                                                  profileID: profile, userID: "owner", trustedLegacyOwner: false)
        #expect(Set(result.map { $0.record.bookVersionId }) == Set(["old", "new"]))
    }
}
