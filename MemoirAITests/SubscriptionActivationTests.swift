import Foundation
import RevenueCat
import Testing
@testable import MemoirAI

@MainActor
struct SubscriptionActivationTests {
    private let monthly = "com.Buildr.MemoirAI.ProMonthly"
    private let yearly = "com.Buildr.MemoirAI.ProYearly"

    private func customerInfo(
        product: String? = nil,
        mappedEntitlement: Bool = true,
        entitlementID: String = "Basic",
        expired: Bool = false,
        billingIssue: Bool = false,
        gracePeriod: Bool = false,
        graceExpired: Bool = false,
        refunded: Bool = false,
        additionalSubscriptions: [String: [String: Any]] = [:],
        requestDate: String = "2026-09-24T12:00:00Z"
    ) throws -> CustomerInfo {
        let purchaseDate = "2026-09-24T11:00:00Z"
        let expiration = expired ? "2026-09-24T11:30:00Z" : "2099-10-24T12:00:00Z"
        var subscriptions: [String: Any] = additionalSubscriptions
        var entitlements: [String: Any] = [:]
        if let product {
            var subscription: [String: Any] = [
                "purchase_date": purchaseDate,
                "expires_date": expiration,
                "store": "app_store",
                "is_sandbox": true,
                "period_type": "normal",
                "ownership_type": "PURCHASED"
            ]
            if billingIssue {
                subscription["billing_issues_detected_at"] = "2026-09-24T11:30:00Z"
            }
            if gracePeriod {
                subscription["grace_period_expires_date"] = graceExpired
                    ? "2026-09-24T11:45:00Z" : "2099-10-24T12:00:00Z"
            }
            if refunded {
                subscription["refunded_at"] = "2026-09-24T11:40:00Z"
            }
            subscriptions[product] = subscription
            if mappedEntitlement {
                entitlements[entitlementID] = [
                    "product_identifier": product,
                    "purchase_date": purchaseDate,
                    "expires_date": gracePeriod ? "2099-10-24T12:00:00Z" : expiration
                ]
            }
        }
        let response: [String: Any] = [
            "request_date": requestDate,
            "subscriber": [
                "original_app_user_id": "user-a",
                "first_seen": "2026-01-01T00:00:00Z",
                "subscriptions": subscriptions,
                "non_subscriptions": [:],
                "entitlements": entitlements
            ]
        ]
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CustomerInfo.self, from: JSONSerialization.data(withJSONObject: response))
    }

    private func withManager(_ body: (RCSubscriptionManager, UserDefaults) throws -> Void) throws {
        let suite = "SubscriptionActivationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = RCSubscriptionManager(
            storage: defaults, firebaseUserID: { "user-a" },
            revenueCatUserID: { "user-a" }, identifiedUserID: "user-a"
        )
        try body(manager, defaults)
    }

    @Test func purchaseImmediatelyReplacesExhaustedFreeStateWithPaidAllowance() throws {
        try withManager { manager, _ in
            let freeActive = try manager.applyPurchaseResult(customerInfo(), for: "user-a")
            #expect(!freeActive)
            #expect(manager.remainingAllowance == 0)
            #expect(!manager.canGenerate(pages: 1))
            let purchaseActive = try manager.applyPurchaseResult(customerInfo(product: monthly), for: "user-a")
            #expect(purchaseActive)
            #expect(manager.activeTier == .monthly)
            #expect(manager.remainingAllowance == 100)
            #expect(manager.canGenerate(pages: 20))
        }
    }

    @Test func restoreAnnualSubscriptionWithoutDashboardMappingUnlocksImages() throws {
        try withManager { manager, _ in
            let restoredActive = try manager.applyPurchaseResult(
                customerInfo(product: yearly, mappedEntitlement: false), for: "user-a"
            )
            #expect(restoredActive)
            #expect(manager.activeTier == .yearly)
            #expect(manager.remainingAllowance == 100)
            #expect(manager.canGenerate(pages: 100))
        }
    }

    @Test func legacyImageGenerationEntitlementStillUnlocksImages() throws {
        try withManager { manager, _ in
            let legacy = try customerInfo(product: monthly, entitlementID: "image_generation")
            let active = try manager.applyPurchaseResult(legacy, for: "user-a")
            #expect(active)
            #expect(manager.activeTier == .monthly)
            #expect(manager.remainingAllowance == 100)
        }
    }

    @Test func duplicatePurchaseRestoreAndRefreshPreserveConsumedAllowance() throws {
        try withManager { manager, _ in
            let purchased = try customerInfo(product: monthly)
            try manager.applyPurchaseResult(purchased, for: "user-a")
            manager.consume(pages: 12)
            try manager.applyPurchaseResult(purchased, for: "user-a")
            try manager.applyPurchaseResult(
                customerInfo(product: monthly, requestDate: "2026-09-24T12:01:00Z"), for: "user-a"
            )
            #expect(manager.remainingAllowance == 88)
        }
    }

    @Test func delayedFreeResponseCannotOverwritePurchase() throws {
        try withManager { manager, _ in
            try manager.applyPurchaseResult(
                customerInfo(product: monthly, requestDate: "2026-09-24T12:01:00Z"), for: "user-a"
            )
            manager.consume(pages: 3)
            let stillActive = try manager.applyPurchaseResult(customerInfo(), for: "user-a")
            #expect(stillActive)
            #expect(manager.activeTier == .monthly)
            #expect(manager.remainingAllowance == 97)
        }
    }

    @Test func equalTimestampFreeCallbackCannotRevokePurchase() throws {
        try withManager { manager, _ in
            try manager.applyPurchaseResult(customerInfo(product: monthly), for: "user-a")
            manager.consume(pages: 4)
            let stillActive = try manager.applyPurchaseResult(customerInfo(), for: "user-a")
            #expect(stillActive)
            #expect(manager.remainingAllowance == 96)
            #expect(manager.activeTier == .monthly)
        }
    }

    @Test func expiredOrUnrelatedProductsNeverUnlockGeneration() throws {
        try withManager { manager, _ in
            let expiredActive = try manager.applyPurchaseResult(
                customerInfo(product: monthly, expired: true), for: "user-a"
            )
            #expect(!expiredActive)
            let unrelatedActive = try manager.applyPurchaseResult(
                customerInfo(product: "unrelated.product", mappedEntitlement: false), for: "user-a"
            )
            #expect(!unrelatedActive)
            #expect(!manager.canGenerate(pages: 1))
            #expect(manager.remainingAllowance == 0)
            #expect(manager.activationErrorMessage != nil)
        }
    }

    @Test func newerExpirationRemovesPaidAccess() throws {
        try withManager { manager, _ in
            try manager.applyPurchaseResult(customerInfo(product: monthly), for: "user-a")
            let expiredActive = try manager.applyPurchaseResult(
                customerInfo(product: monthly, expired: true, requestDate: "2026-09-24T12:02:00Z"),
                for: "user-a"
            )
            #expect(!expiredActive)
            #expect(manager.remainingAllowance == 0)
            #expect(!manager.hasActiveSubscription)
        }
    }

    @Test func changedAccountRejectsPendingPurchase() throws {
        let suite = "SubscriptionActivationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var currentUser = "user-a"
        let manager = RCSubscriptionManager(
            storage: defaults, firebaseUserID: { currentUser },
            revenueCatUserID: { currentUser }, identifiedUserID: "user-a"
        )
        let purchase = try customerInfo(product: monthly)
        currentUser = "user-b"
        #expect(throws: (any Error).self) {
            try manager.applyPurchaseResult(purchase, for: "user-a")
        }
        #expect(manager.remainingAllowance == 0)
        #expect(!manager.hasActiveSubscription)
    }

    @Test func restoreDoesNotRefillExhaustedPaidAllowanceInSameUtcMonth() throws {
        try withManager { manager, defaults in
            try manager.applyPurchaseResult(customerInfo(product: monthly), for: "user-a")
            manager.consume(pages: 100)
            let restored = RCSubscriptionManager(
                storage: defaults, firebaseUserID: { "user-a" },
                revenueCatUserID: { "user-a" }, identifiedUserID: "user-a"
            )
            let restoredActive = try restored.applyPurchaseResult(customerInfo(product: monthly), for: "user-a")
            #expect(restoredActive)
            #expect(restored.hasActiveSubscription)
            #expect(restored.remainingAllowance == 0)
            #expect(!restored.canGenerate(pages: 1))
        }
    }

    @Test func developerAccessSurvivesFirstPaidActivation() throws {
        try withManager { manager, _ in
            manager.enablePersistentDevMode()
            try manager.applyPurchaseResult(customerInfo(product: monthly), for: "user-a")
            #expect(manager.remainingAllowance == Int.max)
            #expect(manager.canGenerate(pages: 1_000))
        }
    }

    @Test func billingGracePreservesPaidAccessAndConsumedAllowance() throws {
        try withManager { manager, _ in
            try manager.applyPurchaseResult(customerInfo(product: monthly), for: "user-a")
            manager.consume(pages: 8)
            try manager.applyPurchaseResult(customerInfo(
                product: monthly, expired: true, billingIssue: true, gracePeriod: true,
                requestDate: "2026-09-24T12:01:00Z"
            ), for: "user-a")
            #expect(manager.hasBillingIssue)
            #expect(manager.hasActiveSubscription)
            #expect(manager.remainingAllowance == 92)
        }
    }

    @Test func billingGraceWithoutEntitlementMappingStillPreservesAccess() throws {
        try withManager { manager, _ in
            try manager.applyPurchaseResult(customerInfo(
                product: monthly, mappedEntitlement: false, expired: true,
                billingIssue: true, gracePeriod: true
            ), for: "user-a")
            #expect(manager.hasBillingIssue)
            #expect(manager.hasActiveSubscription)
            #expect(manager.canGenerate(pages: 1))
        }
    }

    @Test func expiredBillingIssueShowsRecoveryWithoutGrantingAccess() throws {
        try withManager { manager, _ in
            try manager.applyPurchaseResult(customerInfo(
                product: monthly, mappedEntitlement: false, expired: true, billingIssue: true
            ), for: "user-a")
            #expect(manager.hasBillingIssue)
            #expect(!manager.hasActiveSubscription)
            #expect(!manager.canGenerate(pages: 1))
        }
    }

    @Test func recoveredPaymentClearsWarningAndRestoresAccess() throws {
        try withManager { manager, _ in
            try manager.applyPurchaseResult(customerInfo(
                product: monthly, expired: true, billingIssue: true
            ), for: "user-a")
            try manager.applyPurchaseResult(customerInfo(
                product: monthly, requestDate: "2026-09-24T12:01:00Z"
            ), for: "user-a")
            #expect(!manager.hasBillingIssue)
            #expect(manager.hasActiveSubscription)
            #expect(manager.canGenerate(pages: 1))
        }
    }

    @Test func accountChangeClearsBillingStateAndRejectsPreviousAccountCallback() throws {
        let suite = "SubscriptionActivationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var userID = "user-a"
        let manager = RCSubscriptionManager(
            storage: defaults, firebaseUserID: { userID },
            revenueCatUserID: { userID }, identifiedUserID: userID
        )
        let issue = try customerInfo(product: monthly, expired: true, billingIssue: true)
        try manager.applyPurchaseResult(issue, for: userID)
        #expect(manager.hasBillingIssue)
        userID = "user-b"
        manager.clearIdentityState()
        #expect(!manager.hasBillingIssue)
        #expect(throws: (any Error).self) {
            try manager.applyPurchaseResult(issue, for: "user-a")
        }
        #expect(!manager.hasBillingIssue)
    }

    @Test func healthyCurrentSubscriptionSuppressesOlderProductBillingFailure() throws {
        try withManager { manager, _ in
            let oldMonthly: [String: Any] = [
                "purchase_date": "2026-08-01T12:00:00Z",
                "expires_date": "2026-09-01T12:00:00Z",
                "billing_issues_detected_at": "2026-09-01T12:00:00Z",
                "store": "app_store", "is_sandbox": true,
                "period_type": "normal", "ownership_type": "PURCHASED"
            ]
            try manager.applyPurchaseResult(customerInfo(
                product: yearly, additionalSubscriptions: [monthly: oldMonthly]
            ), for: "user-a")
            #expect(!manager.hasBillingIssue)
            #expect(manager.activeTier == .yearly)
        }
    }

    @Test func delayedBillingFailureCannotOverwriteRecoveredPayment() throws {
        try withManager { manager, _ in
            try manager.applyPurchaseResult(customerInfo(
                product: monthly, requestDate: "2026-09-24T12:01:00Z"
            ), for: "user-a")
            try manager.applyPurchaseResult(customerInfo(
                product: monthly, expired: true, billingIssue: true
            ), for: "user-a")
            #expect(!manager.hasBillingIssue)
            #expect(manager.hasActiveSubscription)
        }
    }


    @Test func expiredGraceWithoutEntitlementCannotGrantAccess() throws {
        try withManager { manager, _ in
            try manager.applyPurchaseResult(customerInfo(
                product: monthly, mappedEntitlement: false, expired: true,
                billingIssue: true, gracePeriod: true, graceExpired: true
            ), for: "user-a")
            #expect(manager.hasBillingIssue)
            #expect(!manager.hasActiveSubscription)
            #expect(!manager.canGenerate(pages: 1))
        }
    }

    @Test func refundedSubscriptionCannotUseGraceFallback() throws {
        try withManager { manager, _ in
            try manager.applyPurchaseResult(customerInfo(
                product: monthly, mappedEntitlement: false, expired: true,
                billingIssue: true, gracePeriod: true, refunded: true
            ), for: "user-a")
            #expect(!manager.hasBillingIssue)
            #expect(!manager.hasActiveSubscription)
            #expect(!manager.canGenerate(pages: 1))
        }
    }

}
