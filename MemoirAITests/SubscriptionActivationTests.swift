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
        requestDate: String = "2026-09-24T12:00:00Z"
    ) throws -> CustomerInfo {
        let purchaseDate = "2026-09-24T11:00:00Z"
        let expiration = expired ? "2026-09-24T11:30:00Z" : "2099-10-24T12:00:00Z"
        var subscriptions: [String: Any] = [:]
        var entitlements: [String: Any] = [:]
        if let product {
            subscriptions[product] = [
                "purchase_date": purchaseDate,
                "expires_date": expiration,
                "store": "app_store",
                "is_sandbox": true,
                "period_type": "normal",
                "ownership_type": "PURCHASED"
            ]
            if mappedEntitlement {
                entitlements[entitlementID] = [
                    "product_identifier": product,
                    "purchase_date": purchaseDate,
                    "expires_date": expiration
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
}
