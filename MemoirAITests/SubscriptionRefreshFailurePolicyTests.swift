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
