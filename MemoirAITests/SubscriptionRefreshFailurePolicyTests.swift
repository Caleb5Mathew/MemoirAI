import Foundation
import Testing
@testable import MemoirAI

struct SubscriptionRefreshFailurePolicyTests {
    @Test func transientRefreshFailurePreservesOnlyPreviouslyVerifiedAccess() {
        #expect(SubscriptionRefreshFailurePolicy.shouldPreserveLastVerifiedAccess(hasActiveTier: true))
        #expect(!SubscriptionRefreshFailurePolicy.shouldPreserveLastVerifiedAccess(hasActiveTier: false))
    }

    @Test func revenueCatIdentityMustMatchFirebaseBeforeGeneration() {
        #expect(RevenueCatIdentityPolicy.isReady(
            isConfigured: true,
            currentAppUserID: "firebase-a",
            firebaseUserID: "firebase-a"
        ))
        #expect(!RevenueCatIdentityPolicy.isReady(
            isConfigured: true,
            currentAppUserID: "revenuecat-random",
            firebaseUserID: "firebase-a"
        ))
        #expect(RevenueCatIdentityPolicy.isReady(
            isConfigured: false,
            currentAppUserID: "",
            firebaseUserID: "firebase-a"
        ))
    }

    @Test func subscriptionAllowanceStorageIsUserScoped() {
        let userA = SubscriptionStorageScope.key(
            prefix: "allowance_",
            userID: "user-a",
            tierRawValue: Tier.monthly.rawValue
        )
        let userB = SubscriptionStorageScope.key(
            prefix: "allowance_",
            userID: "user-b",
            tierRawValue: Tier.monthly.rawValue
        )
        #expect(userA != userB)
        #expect(userA.contains("user-a"))
    }

    @Test func annualAllowanceResetsAtUtcMonthBoundary() {
        let august = Date(timeIntervalSince1970: 1_788_220_799)
        let september = Date(timeIntervalSince1970: 1_788_220_800)
        #expect(SubscriptionAllowancePeriod.utcMonthKey(for: august) == "2026-08")
        #expect(SubscriptionAllowancePeriod.utcMonthKey(for: september) == "2026-09")
        #expect(SubscriptionAllowancePeriod.nextResetDate(after: august) == september)
    }

    @Test func pushTokenCleanupDoesNotDeleteAnotherInstallationToken() {
        #expect(PushTokenOwnershipPolicy.shouldClear(
            storedToken: "device-a",
            localToken: "device-a"
        ))
        #expect(!PushTokenOwnershipPolicy.shouldClear(
            storedToken: "device-b",
            localToken: "device-a"
        ))
        #expect(!PushTokenOwnershipPolicy.shouldClear(storedToken: nil, localToken: "device-a"))
    }

    @Test func sharedAudioAccessOnlyAcceptsCanonicalOwnerPath() throws {
        let memoryID = try #require(UUID(uuidString: "11111111-1111-4111-8111-111111111111"))
        #expect(SharedAudioAccessPolicy.audioFile(
            storagePath: "users/owner/audio/\(memoryID.uuidString).m4a",
            ownerID: "owner",
            memoryID: memoryID
        ) == "\(memoryID.uuidString).m4a")
        #expect(SharedAudioAccessPolicy.audioFile(
            storagePath: "users/other/audio/\(memoryID.uuidString).m4a",
            ownerID: "owner",
            memoryID: memoryID
        ) == nil)
    }

    @Test func sharingUsesIndependentDocumentsPerMemory() throws {
        let first = try #require(UUID(uuidString: "11111111-1111-4111-8111-111111111111"))
        let second = try #require(UUID(uuidString: "22222222-2222-4222-8222-222222222222"))
        let firstID = SharedAccessDocumentID.requestOrGrant(requesterID: "requester", memoryID: first)
        let secondID = SharedAccessDocumentID.requestOrGrant(requesterID: "requester", memoryID: second)
        #expect(firstID != secondID)
        #expect(firstID.hasSuffix("__requester"))
    }

    @Test func customerInfoIsDiscardedAfterAccountSwitch() {
        #expect(RevenueCatIdentityPolicy.canApplyCustomerInfo(
            capturedFirebaseUserID: "user-a",
            capturedAppUserID: "user-a",
            currentFirebaseUserID: "user-a",
            currentAppUserID: "user-a",
            identifiedFirebaseUserID: "user-a"
        ))
        #expect(!RevenueCatIdentityPolicy.canApplyCustomerInfo(
            capturedFirebaseUserID: "user-a",
            capturedAppUserID: "user-a",
            currentFirebaseUserID: "user-b",
            currentAppUserID: "user-b",
            identifiedFirebaseUserID: "user-b"
        ))
    }
}
