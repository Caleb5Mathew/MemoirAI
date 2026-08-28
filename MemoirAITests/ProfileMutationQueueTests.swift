import Foundation
import Testing
@testable import MemoirAI

struct ProfileMutationQueueTests {
    @Test func latestMutationReplacesEarlierMutationForSameUserAndProfile() {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Caleb")
        let upsert = PendingProfileMutation(
            userID: "user-a",
            profileID: profileID,
            kind: .upsert,
            profile: profile,
            queuedAt: Date(timeIntervalSince1970: 1)
        )
        let deletion = PendingProfileMutation(
            userID: "user-a",
            profileID: profileID,
            kind: .delete,
            profile: nil,
            queuedAt: Date(timeIntervalSince1970: 2)
        )

        let result = ProfileMutationQueuePolicy.enqueued(deletion, into: [upsert])

        #expect(result == [deletion])
    }

    @Test func mutationsRemainIsolatedByUser() {
        let profileID = UUID()
        let userA = PendingProfileMutation(
            userID: "user-a",
            profileID: profileID,
            kind: .delete,
            profile: nil,
            queuedAt: Date(timeIntervalSince1970: 1)
        )
        let userB = PendingProfileMutation(
            userID: "user-b",
            profileID: profileID,
            kind: .delete,
            profile: nil,
            queuedAt: Date(timeIntervalSince1970: 2)
        )

        let result = ProfileMutationQueuePolicy.enqueued(userB, into: [userA])

        #expect(result.count == 2)
    }

    @Test func remoteUpsertIsRejectedAfterCrossDeviceDeletion() {
        #expect(!ProfileRemoteUpsertPolicy.shouldApply(
            pendingUpdatedAt: Date(timeIntervalSince1970: 20),
            remoteUpdatedAt: nil,
            tombstoneExists: true
        ))
    }

    @Test func olderOfflineEditDoesNotOverwriteNewerRemoteProfile() {
        #expect(!ProfileRemoteUpsertPolicy.shouldApply(
            pendingUpdatedAt: Date(timeIntervalSince1970: 10),
            remoteUpdatedAt: Date(timeIntervalSince1970: 20),
            tombstoneExists: false
        ))
    }

    @Test func newerOfflineEditCanUpdateOlderRemoteProfile() {
        #expect(ProfileRemoteUpsertPolicy.shouldApply(
            pendingUpdatedAt: Date(timeIntervalSince1970: 20),
            remoteUpdatedAt: Date(timeIntervalSince1970: 10),
            tombstoneExists: false
        ))
    }
}
