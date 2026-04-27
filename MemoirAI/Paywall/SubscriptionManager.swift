import Foundation
import RevenueCat
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

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

@MainActor
final class RCSubscriptionManager: NSObject, ObservableObject {
    static let shared = RCSubscriptionManager()

    @Published var offerings: Offerings?
    @Published var activeTier: Tier?
    @Published var remainingAllowance: Int = 0
    @Published var nextRenewalDate: Date?

    // 🔥 BACK TO USERDEFAULTS - Simple and reliable
    private let allowanceKeyPrefix = "memoirai_image_allowance_"
    private let lastResetPrefix    = "memoirai_image_lastReset_"
    private let renewalDateKey     = "memoirai_renewal_date"
    private let initializationKey  = "memoirai_initialized_"
    private let lastPurchaseDateKey = "memoirai_last_purchase_date_"
    
    // Maximum images per subscription period
    private let maxImagesPerPeriod: Int = 100
    /// When true, developer unlock survives cold launch until toggled off in Profile Edit or Settings.
    private let persistentDevModeKey = "memoirai_persistentDevMode"
    /// Session developer unlock (also true when persistent dev mode is on).
    @Published private(set) var isDeveloperUnlockedSession: Bool = false
    /// Mirrors UserDefaults for SwiftUI; use for gates like headshot bypass.
    @Published private(set) var isPersistentDevMode: Bool = false

    private override init() {
        super.init()

        isPersistentDevMode = UserDefaults.standard.bool(forKey: persistentDevModeKey)
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
                    // In development, simulate no subscription
                    activeTier = nil
                    remainingAllowance = 0
                    nextRenewalDate = nil
                }
            }

            await MainActor.run {
                if UserDefaults.standard.bool(forKey: persistentDevModeKey) {
                    unlockDeveloperMode()
                }
            }
        }
    }

    /// Enables developer unlock and persists it across app restarts until `disablePersistentDevMode()`.
    func enablePersistentDevMode() {
        UserDefaults.standard.set(true, forKey: persistentDevModeKey)
        UserDefaults.standard.synchronize()
        isPersistentDevMode = true
        unlockDeveloperMode()
        print("RCManager: Persistent developer mode enabled – survives app restart until disabled.")
    }

    /// Turns off persisted dev unlock and re-evaluates real subscription state.
    func disablePersistentDevMode() {
        UserDefaults.standard.set(false, forKey: persistentDevModeKey)
        UserDefaults.standard.synchronize()
        isPersistentDevMode = false
        isDeveloperUnlockedSession = false
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

    func refreshCustomerInfo() async {
        guard Purchases.isConfigured else {
            print("⚠️ RevenueCat not configured - skipping customer info refresh")
            return
        }
        
        do {
            let info = try await Purchases.shared.customerInfo()
            print("RCManager: CustomerInfo refreshed. Entitlements: \(info.entitlements.active.keys)")
            evaluateEntitlements(from: info)
        } catch {
            print("❌ RCManager: CustomerInfo error: \(error). Setting as non-subscriber.")
            if isDeveloperUnlockedSession {
                // Keep dev access active for this app session.
                unlockDeveloperMode()
            } else {
                // No subscription = no generation allowed
                activeTier = nil
                remainingAllowance = 0
                nextRenewalDate = nil
            }
        }
    }

    private func evaluateEntitlements(from info: CustomerInfo) {
        var determinedTier: Tier? = nil
        var renewalDate: Date? = nil
        var purchaseDate: Date? = nil

        // Check for active entitlements and map product IDs to package IDs
        for entitlement in info.entitlements.active.values {
            if entitlement.isActive {
                // Map product identifiers to our package-based tiers
                let tier = mapProductIdToTier(entitlement.productIdentifier)
                if let tier = tier {
                    determinedTier = tier
                    renewalDate = entitlement.expirationDate
                    purchaseDate = entitlement.latestPurchaseDate
                    break
                }
            }
        }
        
        // Fallback: Check generic entitlement
        if determinedTier == nil, let ent = info.entitlements["image_generation"], ent.isActive {
            let tier = mapProductIdToTier(ent.productIdentifier)
            if let tier = tier {
                determinedTier = tier
                renewalDate = ent.expirationDate
                purchaseDate = ent.latestPurchaseDate
            }
        }

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
        syncSubscriptionToFirestore()
    }

    private func syncSubscriptionToFirestore() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
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
    private func setActiveTier(_ tier: Tier, renewalDate: Date?, latestPurchaseDate: Date?) {
        let oldTierID = activeTier?.rawValue
        activeTier = tier
        nextRenewalDate = renewalDate
        
        // Store renewal date
        if let renewalDate = renewalDate {
            UserDefaults.standard.set(renewalDate, forKey: renewalDateKey)
        }

        let now = Date()
        let calendar = Calendar.current
        let allowanceUDKey = allowanceKeyPrefix + tier.rawValue
        let initKey = initializationKey + tier.rawValue
        let purchaseDateKey = lastPurchaseDateKey + tier.rawValue
        
        // Check if this is the first time we're setting up this tier
        let isFirstTimeSetup = !UserDefaults.standard.bool(forKey: initKey)
        
        if isFirstTimeSetup {
            // 🔥 FIRST TIME: Set up with full allowance and mark as initialized
            remainingAllowance = maxImagesPerPeriod
            UserDefaults.standard.set(remainingAllowance, forKey: allowanceUDKey)
            UserDefaults.standard.set(true, forKey: initKey)
            
            // Set initial reset tracking
            if let purchaseDate = latestPurchaseDate {
                UserDefaults.standard.set(purchaseDate, forKey: purchaseDateKey)
            }
            
            print("RCManager: First-time setup for \(tier.displayName). Starting allowance: \(remainingAllowance)")
            UserDefaults.standard.synchronize()
            return
        }
        
        // 🔥 CHECK FOR PERIOD RESET based on purchase date
        var shouldReset = false
        if let currentPurchaseDate = latestPurchaseDate {
            if let lastProcessedPurchaseDate = UserDefaults.standard.object(forKey: purchaseDateKey) as? Date {
                // If the new purchase date is later than the last one we processed, it's a renewal.
                if currentPurchaseDate > lastProcessedPurchaseDate {
                    shouldReset = true
                }
        } else {
                // If we don't have a stored purchase date, but we have one now, treat it as a reset event.
                shouldReset = true
            }
        }
        
        // 🔥 CHECK FOR TIER CHANGE
        let tierChanged = oldTierID != nil && oldTierID != tier.rawValue
        
        if tierChanged || shouldReset {
            // Reset allowance
            remainingAllowance = maxImagesPerPeriod
            
            // Update reset tracking with the new purchase date
            if let purchaseDate = latestPurchaseDate {
                UserDefaults.standard.set(purchaseDate, forKey: purchaseDateKey)
            }
            
            UserDefaults.standard.set(remainingAllowance, forKey: allowanceUDKey)
            print("RCManager: Allowance reset for \(tier.displayName). Reason: \(tierChanged ? "Tier changed" : "Period reset"). New allowance: \(remainingAllowance)")
        } else {
            // 🔥 NORMAL CASE: Load existing allowance (this preserves 45/50)
            if let storedValue = UserDefaults.standard.object(forKey: allowanceUDKey) as? Int {
                remainingAllowance = storedValue
                print("RCManager: Loaded existing allowance for \(tier.displayName): \(remainingAllowance)")
            } else {
                // Fallback if somehow we lost the data
                remainingAllowance = maxImagesPerPeriod
                UserDefaults.standard.set(remainingAllowance, forKey: allowanceUDKey)
                print("RCManager: Fallback setup for \(tier.displayName). Starting allowance: \(remainingAllowance)")
            }
        }
        
        // Force save
        UserDefaults.standard.synchronize()

        // Apply developer override for current app session only.
        if isDeveloperUnlockedSession {
            self.unlockDeveloperMode()
        }
    }

    func purchase(package: Package) async throws {
        // 🎯 Track checkout initiation for Facebook
        FacebookAnalytics.logCheckoutInitiated()
        
        let result = try await Purchases.shared.purchase(package: package)
        if result.userCancelled {
            print("RCManager: Purchase cancelled by user.")
            return
        }
        
        print("RCManager: Purchase successful. Refreshing customer info.")
        evaluateEntitlements(from: result.customerInfo)
        
        // ✅ RevenueCat handles purchase events server-side via Conversions API
        // No client-side purchase logging needed to avoid duplicates
    }

    // 🔥 ENHANCED: Better consumption tracking
    func consume(pages: Int) {
        guard pages > 0 else {
            print("RCManager: Consume called with 0 pages. No action taken.")
            return
        }

        guard let currentTier = activeTier else {
            print("RCManager: Cannot consume images. No active subscription.")
            return
        }
        
        guard remainingAllowance > 0 else {
            print("RCManager: Cannot consume \(pages) images. No remaining allowance.")
            return
        }

        let oldAllowance = remainingAllowance
        let newAllowance = remainingAllowance - pages
        remainingAllowance = max(0, newAllowance)
        
        // Save immediately with verification
        let allowanceUDKey = allowanceKeyPrefix + currentTier.rawValue
        UserDefaults.standard.set(remainingAllowance, forKey: allowanceUDKey)
        UserDefaults.standard.synchronize()
        
        // Verify the save worked
        let verification = UserDefaults.standard.integer(forKey: allowanceUDKey)
        if verification != remainingAllowance {
            print("⚠️ WARNING: Save verification failed! Expected: \(remainingAllowance), Got: \(verification)")
        } else {
            print("✅ RCManager: Consumed \(pages) images. \(oldAllowance) → \(remainingAllowance)")
        }
    }

    func canGenerate(pages pagesToGenerate: Int) -> Bool {
        guard pagesToGenerate > 0 else { return true }

        // Must have active subscription to generate any images
        guard activeTier != nil else {
            print("RCManager: Cannot generate. No active subscription.")
            return false
        }

        if remainingAllowance >= pagesToGenerate {
            print("RCManager: Can generate \(pagesToGenerate) images. Remaining: \(remainingAllowance)")
            return true
        } else {
            print("RCManager: Cannot generate. Insufficient allowance. Remaining: \(remainingAllowance), Requested: \(pagesToGenerate)")
            return false
        }
    }
    
    // Get formatted renewal date string
    func getRenewalDateString() -> String {
        guard let tier = activeTier else { return "N/A" }
        
        let calendar = Calendar.current
        let now = Date()
        
        if tier.isYearly {
            // For yearly subscriptions, next reset is next Monday
            let nextMonday = calendar.nextDate(after: now, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime) ?? now
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: nextMonday)
        } else {
            // For monthly subscriptions, use actual renewal date
            if let renewalDate = nextRenewalDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return formatter.string(from: renewalDate)
            } else {
                // Fallback to next month
                let nextMonth = calendar.date(byAdding: .month, value: 1, to: now) ?? now
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return formatter.string(from: nextMonth)
            }
        }
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
        return hasActiveSubscription && remainingAllowance <= 0
    }

    // ✨ Smart generation advice based on remaining monthly allowance
    func getGenerationAdvice(for requestedPages: Int) -> String? {
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
        guard hasActiveSubscription else { return "No active subscription" }
        return "\(remainingAllowance)/100 monthly allowance remaining"
    }
    
    // ✨ Check if generation would use a large portion of allowance
    func isLargeGeneration(pages: Int) -> Bool {
        return pages > 20 // More than 20% of monthly allowance
    }

    // MARK: – Developer mode unlock
    func unlockDeveloperMode() {
        isDeveloperUnlockedSession = true
        activeTier = .monthly
        remainingAllowance = 2000
        print("🚀 Developer mode unlocked for this session – 2000 images")
    }
}

extension RCSubscriptionManager: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases,
                               receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            print("RCManager (Delegate): Received updated customer info. Refreshing state...")
            RCSubscriptionManager.shared.evaluateEntitlements(from: customerInfo)
        }
    }
}
