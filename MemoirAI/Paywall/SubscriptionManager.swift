import Foundation
import RevenueCat
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import CryptoKit

// Updated subscription tiers to match RevenueCat package identifiers
enum Tier: String, CaseIterable {
    case monthly = "$rc_monthly"  // Matches RevenueCat dashboard package ID
    case yearly = "$rc_annual"    // Matches RevenueCat dashboard package ID

    var allowance: Int {
        // All subscription tiers get 100 images
        return 100
    }

    var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    var isYearly: Bool {
        return self == .yearly
    }
}

struct DeveloperAccessDistributionPolicy {
    static func permitsRemoteUnlock(receiptLastPathComponent _: String?) -> Bool {
        true
    }

    static var permitsCurrentBuild: Bool { true }
}

struct DeveloperEntitlementSyncPolicy {
    static func shouldSync(isDeveloperUnlocked: Bool) -> Bool {
        !isDeveloperUnlocked
    }
}

struct GenerationAllowancePolicy {
    static func canGenerate(pages: Int, remaining: Int, hasSubscription: Bool, developerUnlocked: Bool) -> Bool {
        developerUnlocked || pages <= 0 || (hasSubscription && remaining >= pages)
    }

    static func remainingAfterConsumption(pages: Int, remaining: Int, developerUnlocked: Bool) -> Int {
        guard !developerUnlocked, pages > 0 else { return remaining }
        return pages >= remaining ? 0 : remaining - pages
    }
}

struct DeveloperAccessCodePolicy {
    static func constantTimeMatches(candidateDigest: String, expectedDigest: String) -> Bool {
        guard candidateDigest.utf8.count == expectedDigest.utf8.count else { return false }
        var result: UInt8 = 0
        for (candidate, expected) in zip(candidateDigest.utf8, expectedDigest.utf8) {
            result |= candidate ^ expected
        }
        return result == 0
    }
}

enum DeveloperAccessError: LocalizedError {
    case incorrectCode

    var errorDescription: String? {
        switch self {
        case .incorrectCode:
            return "Incorrect access code."
        }
    }
}

enum RevenueCatIdentityPolicy {
    static func shouldIdentify(currentAppUserID: String, firebaseUserID: String) -> Bool {
        !firebaseUserID.isEmpty && currentAppUserID != firebaseUserID
    }

    static func isReady(
        isConfigured: Bool,
        currentAppUserID: String,
        firebaseUserID: String
    ) -> Bool {
        !isConfigured || (!firebaseUserID.isEmpty && currentAppUserID == firebaseUserID)
    }

    static func canApplyCustomerInfo(
        capturedFirebaseUserID: String,
        capturedAppUserID: String,
        currentFirebaseUserID: String?,
        currentAppUserID: String,
        identifiedFirebaseUserID: String?
    ) -> Bool {
        !capturedFirebaseUserID.isEmpty
            && capturedAppUserID == capturedFirebaseUserID
            && currentFirebaseUserID == capturedFirebaseUserID
            && currentAppUserID == capturedAppUserID
            && identifiedFirebaseUserID == capturedFirebaseUserID
    }
}

enum SubscriptionRefreshFailurePolicy {
    static func shouldPreserveLastVerifiedAccess(hasActiveTier: Bool) -> Bool {
        hasActiveTier
    }
}

enum SubscriptionStorageScope {
    static func key(prefix: String, userID: String, tierRawValue: String? = nil) -> String {
        let suffix = tierRawValue.map { "_\($0)" } ?? ""
        return "\(prefix)\(userID)\(suffix)"
    }
}

enum SubscriptionAllowancePeriod {
    static func utcMonthKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    static func nextResetDate(after date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        return calendar.date(byAdding: .month, value: 1, to: start) ?? date
    }
}

@MainActor
final class RCSubscriptionManager: NSObject, ObservableObject {
    static let shared = RCSubscriptionManager()

    @Published var offerings: Offerings?
    @Published var activeTier: Tier?
    @Published var remainingAllowance: Int = 0
    @Published var nextRenewalDate: Date?
    @Published private(set) var identifiedFirebaseUserID: String?
    @Published private(set) var identityErrorMessage: String?
    @Published private(set) var activationErrorMessage: String?

    private var storage = UserDefaults.standard
    private var firebaseUserIDProvider: () -> String? = { Auth.auth().currentUser?.uid }
    private var revenueCatUserIDProvider: () -> String = {
        Purchases.isConfigured ? Purchases.shared.appUserID : ""
    }
    private var syncsToFirestore = true
    private var latestCustomerInfoDate: Date?
    private var customerInfoUserID: String?

    /// Isolated storage and identities allow purchase state transitions to be tested without network services.
    init(storage: UserDefaults, firebaseUserID: @escaping () -> String?,
         revenueCatUserID: @escaping () -> String, identifiedUserID: String) {
        self.storage = storage
        self.firebaseUserIDProvider = firebaseUserID
        self.revenueCatUserIDProvider = revenueCatUserID
        self.syncsToFirestore = false
        super.init()
        identifiedFirebaseUserID = identifiedUserID
    }

    // 🔥 BACK TO USERDEFAULTS - Simple and reliable
    private let allowanceKeyPrefix = "memoirai_image_allowance_"
    private let lastResetPrefix    = "memoirai_image_lastReset_"
    private let renewalDateKeyPrefix = "memoirai_renewal_date_"
    private let initializationKey  = "memoirai_initialized_"
    
    // Maximum images per subscription period
    private let maxImagesPerPeriod: Int = 100
    /// When true, developer unlock survives cold launch until toggled off in Profile Edit or Settings.
    private let persistentDevModeKey = "memoirai_persistentDevMode"
    /// Session developer unlock (also true when persistent dev mode is on).
    @Published private(set) var isDeveloperUnlockedSession: Bool = false
    /// Mirrors UserDefaults for SwiftUI; use for gates like headshot bypass.
    @Published private(set) var isPersistentDevMode: Bool = false
    private var identifyingFirebaseUserID: String?

    private override init() {
        super.init()

        isPersistentDevMode = storage.bool(forKey: persistentDevModeKey)
        if isPersistentDevMode {
            unlockDeveloperMode()
            print("RCManager: Restored persistent developer mode from storage.")
        }

        // Add a small delay to ensure RevenueCat is fully configured
        Task {
            // Wait a brief moment for RevenueCat to be ready
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

            if Purchases.isConfigured {
                await MainActor.run {
                    Purchases.shared.delegate = self
                }
                await loadOfferings()
                await refreshCustomerInfo()
            } else {
                await MainActor.run {
                    print("RCManager: RevenueCat not configured - using development mode")
                    guard !isDeveloperUnlockedSession else { return }
                    activeTier = nil
                    remainingAllowance = 0
                    nextRenewalDate = nil
                }
            }

            await MainActor.run {
                if storage.bool(forKey: persistentDevModeKey) {
                    unlockDeveloperMode()
                }
            }
        }
    }

    /// Enables developer unlock and persists it across app restarts until `disablePersistentDevMode()`.
    func enablePersistentDevMode() {
        storage.set(true, forKey: persistentDevModeKey)
        storage.synchronize()
        isPersistentDevMode = true
        unlockDeveloperMode()
        print("RCManager: Persistent developer mode enabled – survives app restart until disabled.")
    }

    /// Turns off persisted dev unlock and re-evaluates real subscription state.
    func disablePersistentDevMode() {
        storage.set(false, forKey: persistentDevModeKey)
        storage.synchronize()
        isPersistentDevMode = false
        isDeveloperUnlockedSession = false
        activeTier = nil
        remainingAllowance = 0
        nextRenewalDate = nil
        Task { await refreshCustomerInfo() }
        print("RCManager: Persistent developer mode disabled.")
    }

    func loadOfferings() async {
        guard Purchases.isConfigured else { return }

        do {
            // Use specific offering instead of default
            offerings = try await Purchases.shared.offerings()
            
            // To use "Def2" offering instead of "default", uncomment this:
            // offerings = try await Purchases.shared.offerings()
            // if let def2Offering = offerings?.all["Def2"] {
            //     offerings?.current = def2Offering
            // }
            
            print("RCManager: Offerings loaded successfully.")

            // 🔎 DEBUG – Enhanced package debugging
            Task { @MainActor in
                if let current = offerings?.current {
                    print("🔍 Current offering: \(current.identifier)")
                    print("🔍 Packages delivered: \(current.availablePackages.map(\.identifier))")
                    print("🔍 Package details:")
                    for package in current.availablePackages {
                        print("  📦 \(package.identifier) -> \(package.storeProduct.productIdentifier)")
                    }
                    if current.availablePackages.isEmpty {
                        print("⚠️ No packages found in current offering!")
                    }
                } else {
                    print("❌ No current offering found!")
                }
                
                if let allOfferings = offerings?.all {
                    print("🔍 All offerings: \(allOfferings.keys)")
                }
            }

        } catch {
            print("❌ RCManager: Offerings error: \(error)")
            offerings = nil
        }
    }

    func isIdentityReady(for firebaseUserID: String) -> Bool {
        identifiedFirebaseUserID == firebaseUserID && RevenueCatIdentityPolicy.isReady(
            isConfigured: Purchases.isConfigured,
            currentAppUserID: Purchases.isConfigured ? Purchases.shared.appUserID : firebaseUserID,
            firebaseUserID: firebaseUserID
        )
    }

    func clearIdentityState() {
        identifiedFirebaseUserID = nil
        latestCustomerInfoDate = nil
        customerInfoUserID = nil
        activationErrorMessage = nil
        identityErrorMessage = nil
        if !isDeveloperUnlockedSession {
            activeTier = nil
            remainingAllowance = 0
            nextRenewalDate = nil
        }
    }

    @discardableResult
    func identify(firebaseUserID: String) async -> Bool {
        guard !firebaseUserID.isEmpty, firebaseUserIDProvider() == firebaseUserID else { return false }
        if let identifiedFirebaseUserID, identifiedFirebaseUserID != firebaseUserID {
            self.identifiedFirebaseUserID = nil
            if !isDeveloperUnlockedSession {
                activeTier = nil
                remainingAllowance = 0
                nextRenewalDate = nil
            }
        }
        guard Purchases.isConfigured else {
            identifiedFirebaseUserID = firebaseUserID
            identityErrorMessage = nil
            return true
        }
        if Purchases.shared.appUserID == firebaseUserID {
            do {
                let info = try await Purchases.shared.customerInfo()
                guard firebaseUserIDProvider() == firebaseUserID else { return false }
                identifiedFirebaseUserID = firebaseUserID
                identityErrorMessage = nil
                guard RevenueCatIdentityPolicy.canApplyCustomerInfo(
                    capturedFirebaseUserID: firebaseUserID,
                    capturedAppUserID: firebaseUserID,
                    currentFirebaseUserID: firebaseUserIDProvider(),
                    currentAppUserID: Purchases.shared.appUserID,
                    identifiedFirebaseUserID: identifiedFirebaseUserID
                ) else { return false }
                _ = try applyPurchaseResult(info, for: firebaseUserID)
                return true
            } catch {
                guard firebaseUserIDProvider() == firebaseUserID else { return false }
                identifiedFirebaseUserID = nil
                identityErrorMessage = "Subscription verification failed. Check your connection and try again."
                return false
            }
        }
        if identifyingFirebaseUserID == firebaseUserID {
            for _ in 0..<200 where identifyingFirebaseUserID == firebaseUserID {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            return isIdentityReady(for: firebaseUserID)
        }

        identifyingFirebaseUserID = firebaseUserID
        defer { identifyingFirebaseUserID = nil }
        do {
            let result = try await Purchases.shared.logIn(firebaseUserID)
            guard firebaseUserIDProvider() == firebaseUserID else { return false }
            identifiedFirebaseUserID = firebaseUserID
            identityErrorMessage = nil
            guard RevenueCatIdentityPolicy.canApplyCustomerInfo(
                capturedFirebaseUserID: firebaseUserID,
                capturedAppUserID: firebaseUserID,
                currentFirebaseUserID: firebaseUserIDProvider(),
                currentAppUserID: Purchases.shared.appUserID,
                identifiedFirebaseUserID: identifiedFirebaseUserID
            ) else { return false }
            _ = try applyPurchaseResult(result.customerInfo, for: firebaseUserID)
            print("RCManager: RevenueCat identity linked to Firebase user.")
            return true
        } catch {
            guard firebaseUserIDProvider() == firebaseUserID else { return false }
            identifiedFirebaseUserID = nil
            identityErrorMessage = "Subscription verification failed. Check your connection and try again."
            print("RCManager: RevenueCat identity link failed: \(error.localizedDescription)")
            return false
        }
    }

    func refreshCustomerInfo(forceRefresh: Bool = false) async {
        guard Purchases.isConfigured else {
            print("⚠️ RevenueCat not configured - skipping customer info refresh")
            return
        }
        guard let firebaseUserID = firebaseUserIDProvider() else { return }
        if !isIdentityReady(for: firebaseUserID) {
            guard await identify(firebaseUserID: firebaseUserID) else { return }
            if !forceRefresh { return }
        }
        let appUserID = Purchases.shared.appUserID
        
        do {
            let info = try await Purchases.shared.customerInfo(fetchPolicy: forceRefresh ? .fetchCurrent : .cachedOrFetched)
            guard RevenueCatIdentityPolicy.canApplyCustomerInfo(
                capturedFirebaseUserID: firebaseUserID,
                capturedAppUserID: appUserID,
                currentFirebaseUserID: firebaseUserIDProvider(),
                currentAppUserID: Purchases.shared.appUserID,
                identifiedFirebaseUserID: identifiedFirebaseUserID
            ) else {
                print("RCManager: Discarded CustomerInfo because account identity changed during refresh.")
                return
            }
            print("RCManager: CustomerInfo refreshed. Entitlements: \(info.entitlements.active.keys)")
            _ = try applyPurchaseResult(info, for: firebaseUserID)
        } catch {
            guard firebaseUserIDProvider() == firebaseUserID,
                  revenueCatUserIDProvider() == appUserID,
                  identifiedFirebaseUserID == firebaseUserID else { return }
            activationErrorMessage = "Subscription verification failed. Check your connection and try again."
            print("❌ RCManager: CustomerInfo refresh failed: \(error).")
            if isDeveloperUnlockedSession {
                // Keep dev access active for this app session.
                unlockDeveloperMode()
            } else if !SubscriptionRefreshFailurePolicy.shouldPreserveLastVerifiedAccess(
                hasActiveTier: activeTier != nil
            ) {
                // A first-launch failure has no verified entitlement to preserve.
                activeTier = nil
                remainingAllowance = 0
                nextRenewalDate = nil
            } else {
                print("RCManager: Preserving last verified subscription during transient failure.")
            }
        }
    }

    @discardableResult
    func applyPurchaseResult(_ info: CustomerInfo, for firebaseUserID: String) throws -> Bool {
        guard RevenueCatIdentityPolicy.canApplyCustomerInfo(
            capturedFirebaseUserID: firebaseUserID,
            capturedAppUserID: firebaseUserID,
            currentFirebaseUserID: firebaseUserIDProvider(),
            currentAppUserID: revenueCatUserIDProvider(),
            identifiedFirebaseUserID: identifiedFirebaseUserID
        ) else {
            let message = "Your account changed. Sign in again to refresh your subscription."
            activationErrorMessage = message
            throw NSError(domain: "MemoirAI.Subscription", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
        if customerInfoUserID == firebaseUserID, let latestCustomerInfoDate {
            if info.requestDate < latestCustomerInfoDate {
                return hasActiveSubscription
            }
            // Cache and purchase callbacks can share a timestamp. Only a newer response may revoke access.
            if info.requestDate == latestCustomerInfoDate, hasActiveSubscription,
               activeSubscriptionProductID(in: info) == nil {
                return true
            }
        }
        customerInfoUserID = firebaseUserID
        latestCustomerInfoDate = info.requestDate
        activationErrorMessage = nil
        evaluateEntitlements(from: info, for: firebaseUserID)
        if !hasActiveSubscription && !info.activeSubscriptions.isEmpty {
            activationErrorMessage = "Your purchase could not be matched to a MemoirAI subscription. Restore purchases or contact support."
        }
        return hasActiveSubscription
    }

    private func activeSubscriptionProductID(in info: CustomerInfo) -> String? {
        for entitlementID in ["Basic", "image_generation"] {
            if let entitlement = info.entitlements[entitlementID], entitlement.isActive,
               mapProductIdToTier(entitlement.productIdentifier) != nil {
                return entitlement.productIdentifier
            }
        }
        // A verified subscription remains valid if its dashboard entitlement mapping is missing.
        return info.activeSubscriptions.sorted().first { mapProductIdToTier($0) != nil }
    }

    private func evaluateEntitlements(from info: CustomerInfo, for firebaseUserID: String) {
        let productID = activeSubscriptionProductID(in: info)
        let determinedTier = productID.flatMap { mapProductIdToTier($0) }
        let renewalDate = productID.flatMap { info.expirationDate(forProductIdentifier: $0) }
        let purchaseDate = productID.flatMap { info.purchaseDate(forProductIdentifier: $0) }

        if let newTier = determinedTier {
            print("RCManager: Active subscription found for tier: \(newTier.displayName)")
            setActiveTier(newTier, renewalDate: renewalDate, latestPurchaseDate: purchaseDate)
        } else {
            if isDeveloperUnlockedSession {
                print("RCManager: No active subscription found, but developer mode is active for this session.")
                unlockDeveloperMode()
            } else {
                print("RCManager: No active subscription found. User cannot generate images.")
                activeTier = nil
                remainingAllowance = 0
                nextRenewalDate = nil
            }
        }
        syncSubscriptionToFirestore(for: firebaseUserID)
    }

    private func syncSubscriptionToFirestore(for uid: String) {
        guard syncsToFirestore, firebaseUserIDProvider() == uid,
              identifiedFirebaseUserID == uid,
              DeveloperEntitlementSyncPolicy.shouldSync(
                isDeveloperUnlocked: isDeveloperUnlockedSession
              ),
              !Purchases.isConfigured || Purchases.shared.appUserID == uid else { return }
        let data: [String: Any] = [
            "hasActiveSubscription": activeTier != nil,
            "subscriptionTier": activeTier?.rawValue ?? NSNull(),
            "subscriptionUpdatedAt": FieldValue.serverTimestamp()
        ]
        Firestore.firestore().collection("users").document(uid)
            .setData(data, merge: true) { error in
                if let error = error {
                    print("❌ Failed to sync subscription to Firestore: \(error)")
                }
            }
    }

    // Helper function to map product IDs to package-based tiers
    private func mapProductIdToTier(_ productId: String) -> Tier? {
        switch productId {
        case "com.Buildr.MemoirAI.ProMonthly":
            return .monthly
        case "com.Buildr.MemoirAI.ProYearly":
            return .yearly
        default:
            print("⚠️ Unknown product ID: \(productId)")
            return nil
        }
    }

    // 🔥 COMPLETELY FIXED: This is the core fix for the 50/50 vs 45/50 issue
    private func setActiveTier(_ tier: Tier, renewalDate: Date?, latestPurchaseDate _: Date?) {
        guard let firebaseUserID = firebaseUserIDProvider() else {
            activeTier = nil
            remainingAllowance = 0
            nextRenewalDate = nil
            return
        }
        let oldTierID = activeTier?.rawValue
        activeTier = tier
        nextRenewalDate = renewalDate
        
        // Store renewal date
        if let renewalDate = renewalDate {
            storage.set(renewalDate, forKey: SubscriptionStorageScope.key(
                prefix: renewalDateKeyPrefix,
                userID: firebaseUserID
            ))
        }

        let allowanceUDKey = SubscriptionStorageScope.key(
            prefix: allowanceKeyPrefix,
            userID: firebaseUserID,
            tierRawValue: tier.rawValue
        )
        let initKey = SubscriptionStorageScope.key(
            prefix: initializationKey,
            userID: firebaseUserID,
            tierRawValue: tier.rawValue
        )
        let resetPeriodKey = SubscriptionStorageScope.key(
            prefix: lastResetPrefix,
            userID: firebaseUserID,
            tierRawValue: tier.rawValue
        )
        let currentPeriod = SubscriptionAllowancePeriod.utcMonthKey(for: Date())
        
        // Check if this is the first time we're setting up this tier
        let isFirstTimeSetup = !storage.bool(forKey: initKey)
        
        if isFirstTimeSetup {
            // 🔥 FIRST TIME: Set up with full allowance and mark as initialized
            remainingAllowance = maxImagesPerPeriod
            storage.set(remainingAllowance, forKey: allowanceUDKey)
            storage.set(true, forKey: initKey)
            
            storage.set(currentPeriod, forKey: resetPeriodKey)
            
            print("RCManager: First-time setup for \(tier.displayName). Starting allowance: \(remainingAllowance)")
            storage.synchronize()
            if isDeveloperUnlockedSession { unlockDeveloperMode() }
            return
        }
        
        let shouldReset = storage.string(forKey: resetPeriodKey) != currentPeriod
        
        // 🔥 CHECK FOR TIER CHANGE
        let tierChanged = oldTierID != nil && oldTierID != tier.rawValue
        
        if tierChanged || shouldReset {
            // Reset allowance
            remainingAllowance = maxImagesPerPeriod
            
            storage.set(currentPeriod, forKey: resetPeriodKey)
            
            storage.set(remainingAllowance, forKey: allowanceUDKey)
            print("RCManager: Allowance reset for \(tier.displayName). Reason: \(tierChanged ? "Tier changed" : "Period reset"). New allowance: \(remainingAllowance)")
        } else {
            // 🔥 NORMAL CASE: Load existing allowance (this preserves 45/50)
            if let storedValue = storage.object(forKey: allowanceUDKey) as? Int {
                remainingAllowance = storedValue
                print("RCManager: Loaded existing allowance for \(tier.displayName): \(remainingAllowance)")
            } else {
                // Fallback if somehow we lost the data
                remainingAllowance = maxImagesPerPeriod
                storage.set(remainingAllowance, forKey: allowanceUDKey)
                print("RCManager: Fallback setup for \(tier.displayName). Starting allowance: \(remainingAllowance)")
            }
        }
        
        // Force save
        storage.synchronize()

        // Apply developer override for current app session only.
        if isDeveloperUnlockedSession {
            self.unlockDeveloperMode()
        }
    }

    func purchase(package: Package) async throws {
        guard let firebaseUserID = firebaseUserIDProvider(),
              isIdentityReady(for: firebaseUserID) else {
            throw NSError(
                domain: "MemoirAI.Subscription",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Your subscription account is still connecting. Please try again."]
            )
        }
        let appUserID = Purchases.shared.appUserID
        // 🎯 Track checkout initiation for Facebook
        FacebookAnalytics.logCheckoutInitiated()
        
        let result = try await Purchases.shared.purchase(package: package)
        if result.userCancelled {
            print("RCManager: Purchase cancelled by user.")
            return
        }
        
        print("RCManager: Purchase successful. Refreshing customer info.")
        guard RevenueCatIdentityPolicy.canApplyCustomerInfo(
            capturedFirebaseUserID: firebaseUserID,
            capturedAppUserID: appUserID,
            currentFirebaseUserID: firebaseUserIDProvider(),
            currentAppUserID: Purchases.shared.appUserID,
            identifiedFirebaseUserID: identifiedFirebaseUserID
        ) else {
            throw NSError(
                domain: "MemoirAI.Subscription",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Your account changed during purchase. Sign in again to refresh your subscription."]
            )
        }
        _ = try applyPurchaseResult(result.customerInfo, for: firebaseUserID)
        
        // ✅ RevenueCat handles purchase events server-side via Conversions API
        // No client-side purchase logging needed to avoid duplicates
    }

    // 🔥 ENHANCED: Better consumption tracking
    func consume(pages: Int) {
        guard !isDeveloperUnlockedSession else { return }
        guard pages > 0 else {
            print("RCManager: Consume called with 0 pages. No action taken.")
            return
        }

        guard let currentTier = activeTier else {
            print("RCManager: Cannot consume images. No active subscription.")
            return
        }
        guard let firebaseUserID = firebaseUserIDProvider() else {
            print("RCManager: Cannot consume images without a Firebase identity.")
            return
        }
        
        guard remainingAllowance > 0 else {
            print("RCManager: Cannot consume \(pages) images. No remaining allowance.")
            return
        }

        let oldAllowance = remainingAllowance
        remainingAllowance = GenerationAllowancePolicy.remainingAfterConsumption(
            pages: pages,
            remaining: remainingAllowance,
            developerUnlocked: isDeveloperUnlockedSession
        )
        
        // Save immediately with verification
        let allowanceUDKey = SubscriptionStorageScope.key(
            prefix: allowanceKeyPrefix,
            userID: firebaseUserID,
            tierRawValue: currentTier.rawValue
        )
        storage.set(remainingAllowance, forKey: allowanceUDKey)
        storage.synchronize()
        
        // Verify the save worked
        let verification = storage.integer(forKey: allowanceUDKey)
        if verification != remainingAllowance {
            print("⚠️ WARNING: Save verification failed! Expected: \(remainingAllowance), Got: \(verification)")
        } else {
            print("✅ RCManager: Consumed \(pages) images. \(oldAllowance) → \(remainingAllowance)")
        }
    }

    func canGenerate(pages pagesToGenerate: Int) -> Bool {
        GenerationAllowancePolicy.canGenerate(
            pages: pagesToGenerate,
            remaining: remainingAllowance,
            hasSubscription: hasActiveSubscription,
            developerUnlocked: isDeveloperUnlockedSession
        )
    }

    // Get formatted renewal date string
    func getRenewalDateString() -> String {
        guard activeTier != nil else { return "N/A" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: SubscriptionAllowancePeriod.nextResetDate(after: Date()))
    }
    
    // Check if user has any active subscription
    var hasActiveSubscription: Bool {
        // Check for developer unlock first
        if isDeveloperUnlockedSession {
            return true
        }
        return activeTier != nil
    }

    var isDeveloperUnlocked: Bool {
        isDeveloperUnlockedSession
    }
    
    // Check if user has reached image limit
    var hasReachedImageLimit: Bool {
        return !isDeveloperUnlockedSession && hasActiveSubscription && remainingAllowance <= 0
    }

    // ✨ Smart generation advice based on remaining monthly allowance
    func getGenerationAdvice(for requestedPages: Int) -> String? {
        guard !isDeveloperUnlockedSession else { return nil }
        guard hasActiveSubscription else { return "Subscription required for image generation." }
        
        let remaining = remainingAllowance
        
        if requestedPages > remaining {
            return "You're requesting \(requestedPages) images but only have \(remaining) left in your monthly allowance. Consider generating fewer pages."
        }
        
        if requestedPages > 50 && remaining > 50 {
            return "This will use \(requestedPages) of your 100 monthly allowance. You'll have \(remaining - requestedPages) images remaining this month."
        }
        
        if remaining <= 10 {
            return "You have \(remaining) images left in your monthly allowance. Your allowance resets next month."
        }
        
        return nil // No warning needed
    }
    
    var monthlyAllowanceStatus: String {
        if isDeveloperUnlockedSession { return "Unlimited developer access" }
        guard hasActiveSubscription else { return "No active subscription" }
        return "\(remainingAllowance)/100 monthly allowance remaining"
    }
    
    // ✨ Check if generation would use a large portion of allowance
    func isLargeGeneration(pages: Int) -> Bool {
        return pages > 20 // More than 20% of monthly allowance
    }

    // MARK: – Developer mode unlock

    /// SHA-256 digest (hex) of the developer unlock password. Never store the plaintext.
    private static let developerPasswordDigestHex =
        "03a3f52f7b1fbdbd8224152e8fcc06e7eff398f63c9961fce7d032f560002128"

    /// Verifies a candidate developer unlock password against the stored digest
    /// using a constant-time comparison to avoid timing side-channels.
    static func verifyDeveloperPassword(_ input: String) -> Bool {
        let inputDigest = SHA256.hash(data: Data(input.utf8))
        let inputDigestHex = inputDigest.map { String(format: "%02x", $0) }.joined()

        return DeveloperAccessCodePolicy.constantTimeMatches(
            candidateDigest: inputDigestHex,
            expectedDigest: developerPasswordDigestHex
        )
    }

    func authorizeDeveloperAccess(_ input: String) async throws {
        guard Self.verifyDeveloperPassword(input) else {
            throw DeveloperAccessError.incorrectCode
        }

        enablePersistentDevMode()
    }

    private func unlockDeveloperMode() {
        isDeveloperUnlockedSession = true
        activeTier = .monthly
        remainingAllowance = Int.max
        print("RCManager: Developer mode unlocked for this session.")
    }
}

extension RCSubscriptionManager: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases,
                               receivedUpdated customerInfo: CustomerInfo) {
        let callbackAppUserID = purchases.appUserID
        Task { @MainActor in
            print("RCManager (Delegate): Received updated customer info. Refreshing state...")
            let manager = RCSubscriptionManager.shared
            guard let firebaseUserID = manager.firebaseUserIDProvider(),
                  RevenueCatIdentityPolicy.canApplyCustomerInfo(
                    capturedFirebaseUserID: firebaseUserID,
                    capturedAppUserID: callbackAppUserID,
                    currentFirebaseUserID: firebaseUserID,
                    currentAppUserID: Purchases.shared.appUserID,
                    identifiedFirebaseUserID: manager.identifiedFirebaseUserID
                  ) else { return }
            do {
                _ = try manager.applyPurchaseResult(customerInfo, for: firebaseUserID)
            } catch {
                print("RCManager: Could not apply subscription update: \(error.localizedDescription)")
            }
        }
    }
}
