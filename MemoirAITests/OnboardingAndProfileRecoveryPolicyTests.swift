import Foundation
import Testing
@testable import MemoirAI

struct OnboardingAndProfileRecoveryPolicyTests {
    @Test func legacyOwnerResolutionPrefersLocalAnchor() {
        #expect(MemoryOwnershipPolicy.resolvedLegacyOwnerID(
            localOwnerID: "local-user",
            cloudOwnerID: "cloud-user"
        ) == "local-user")
    }

    @Test func deletionBarrierPreventsLegacyMemoryClaim() {
        #expect(!MemoryOwnershipPolicy.canClaimLegacyRows(
            claimedOwnerID: nil,
            currentUserID: "user-1",
            deletionBarrierActive: true
        ))
    }

    @Test func preservesExistingProfileOwnership() {
        let existing = UUID()
        let selected = UUID()

        #expect(MemoryProfileRecoveryPolicy.recoveredProfileID(
            existingProfileID: existing,
            selectedProfileID: selected
        ) == nil)
    }

    @Test func assignsOnlyLegacyUnassignedProfile() {
        let selected = UUID()

        #expect(MemoryProfileRecoveryPolicy.recoveredProfileID(
            existingProfileID: nil,
            selectedProfileID: selected
        ) == selected)
    }

    @Test func onboardingCompletesOnlyAfterPaywallDismissal() {
        #expect(OnboardingCompletionPolicy.shouldComplete(after: .finalContinueTapped) == false)
        #expect(OnboardingCompletionPolicy.shouldComplete(after: .paywallDismissed))
    }

    @Test func completedOnboardingCannotBeDowngradedByCloud() {
        #expect(OnboardingCompletionState.resolved(local: true, cloud: false))
        #expect(OnboardingCompletionState.resolved(local: true, cloud: true))
    }

    @Test func cloudCompletionCanRestoreLocalState() {
        #expect(OnboardingCompletionState.resolved(local: false, cloud: true))
        #expect(OnboardingCompletionState.resolved(local: false, cloud: false) == false)
    }

    @Test func firstAuthenticatedUserCanClaimLegacyRows() {
        #expect(MemoryOwnershipPolicy.canClaimLegacyRows(
            claimedOwnerID: nil,
            currentUserID: "first-user"
        ))
    }

    @Test func originalLegacyOwnerCanClaimRowsThatArriveLater() {
        #expect(MemoryOwnershipPolicy.canClaimLegacyRows(
            claimedOwnerID: "first-user",
            currentUserID: "first-user"
        ))
    }

    @Test func anotherAccountCannotClaimLegacyRows() {
        #expect(!MemoryOwnershipPolicy.canClaimLegacyRows(
            claimedOwnerID: "first-user",
            currentUserID: "second-user"
        ))
    }

    @Test func memoryOwnershipRequiresExactNonemptyUserIDs() {
        #expect(MemoryOwnershipPolicy.belongsToUser(
            entryOwnerID: "owner",
            currentUserID: "owner"
        ))
        #expect(!MemoryOwnershipPolicy.belongsToUser(
            entryOwnerID: nil,
            currentUserID: "owner"
        ))
        #expect(!MemoryOwnershipPolicy.belongsToUser(
            entryOwnerID: "owner",
            currentUserID: nil
        ))
        #expect(!MemoryOwnershipPolicy.belongsToUser(
            entryOwnerID: "owner",
            currentUserID: "other"
        ))
    }

    @Test func profileStorageIsNamespacedByFirebaseUser() {
        let profileID = UUID()
        #expect(ProfileStorageScope.fileName(userID: "user-a") != ProfileStorageScope.fileName(userID: "user-b"))
        #expect(ProfileStorageScope.backupKey(userID: "user-a") != ProfileStorageScope.backupKey(userID: "user-b"))
        #expect(ProfileStorageScope.cloudProfileKey(
            userID: "user-a",
            profileID: profileID
        ) != ProfileStorageScope.cloudProfileKey(
            userID: "user-b",
            profileID: profileID
        ))
    }

    @Test func profilePhotoStoragePathIsCanonicalAndUserScoped() {
        let profileID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        #expect(ProfilePhotoStorageScope.path(
            userID: "user-a",
            profileID: profileID
        ) == "users/user-a/profiles/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/subjectPhoto.jpg")
    }

    @MainActor
    @Test func profileMergePreservesLocalOnlyProfilesAndDeletionTombstones() {
        let localOnly = Profile(name: "Local", updatedAt: Date(timeIntervalSince1970: 20))
        let deleted = Profile(name: "Deleted", updatedAt: Date(timeIntervalSince1970: 20))
        let remote = Profile(name: "Remote", updatedAt: Date(timeIntervalSince1970: 10))

        let merged = ProfileViewModel.mergedProfiles(
            local: [localOnly],
            remote: [remote, deleted],
            deletedIDs: [deleted.id]
        )

        #expect(Set(merged.map(\.id)) == Set([localOnly.id, remote.id]))
    }

    @Test func profileDeletionRequiresAnotherProfileAndVerifiedEmptyContent() {
        #expect(ProfileDeletionPolicy.outcome(
            profileCount: 1,
            hasContent: false,
            verificationSucceeded: true
        ) == .lastProfile)
        #expect(ProfileDeletionPolicy.outcome(
            profileCount: 2,
            hasContent: true,
            verificationSucceeded: true
        ) == .hasContent)
        #expect(ProfileDeletionPolicy.outcome(
            profileCount: 2,
            hasContent: false,
            verificationSucceeded: false
        ) == .verificationFailed)
        #expect(ProfileDeletionPolicy.outcome(
            profileCount: 2,
            hasContent: false,
            verificationSucceeded: true
        ) == .deleted)
    }

    @Test func storybookStorageIsNamespacedByFirebaseUser() {
        let profileID = UUID()
        #expect(StorybookStorageScope.relativeDirectory(
            userID: "user-a",
            profileID: profileID
        ) != StorybookStorageScope.relativeDirectory(
            userID: "user-b",
            profileID: profileID
        ))
        #expect(StorybookStorageScope.migrationFlagKey(
            userID: "user-a",
            profileID: profileID
        ).contains("user-a"))
        #expect(StorybookStorageScope.cloudCurrentKey(
            userID: "user-a",
            profileID: profileID
        ) != StorybookStorageScope.cloudCurrentKey(
            userID: "user-b",
            profileID: profileID
        ))
    }

    @Test func storybookOwnershipRejectsOtherUsersAndUntrustedLegacyData() {
        #expect(StorybookOwnershipPolicy.canRead(
            ownerUserID: "user-a",
            currentUserID: "user-a",
            trustedLegacyOwner: false
        ))
        #expect(!StorybookOwnershipPolicy.canRead(
            ownerUserID: "user-a",
            currentUserID: "user-b",
            trustedLegacyOwner: true
        ))
        #expect(!StorybookOwnershipPolicy.canRead(
            ownerUserID: nil,
            currentUserID: "user-b",
            trustedLegacyOwner: false
        ))
    }
}
